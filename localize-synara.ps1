#Requires -Version 5.1
<#
    Synara 汉化脚本（Windows）

    用法:
        .\localize-synara.ps1
        .\localize-synara.ps1 -AppPath "D:\Apps\synara-desktop"

    流程:
        1. 定位 Synara 安装目录，确认应用未运行、Node.js 版本满足要求
        2. 解包 resources\app.asar 到临时目录
        3. 备份原始 app.asar（首次创建；检测到应用更新后自动刷新）
        4. 运行 localize-patch.js 替换前端 JS 字符串
        5. 重新打包 app.asar 并校验 unpacked 原生模块标记
        6. 校验通过后覆盖安装目录中的 app.asar（app.asar.unpacked 保持不变）

    每次 Synara 更新后重新运行本脚本即可恢复汉化。
#>
[CmdletBinding()]
param(
    [string]$AppPath,
    [string]$AsarVersion = '4.3.0',
    [switch]$KeepWorkDir
)

$ErrorActionPreference = 'Stop'
# 解包时可能因安装器裁剪了其它架构的文件而返回非零退出码，需要自行判断而不是直接中断
$PSNativeCommandUseErrorActionPreference = $false

# node 输出为 UTF-8，需让控制台按 UTF-8 解码，否则中文日志会乱码
try {
    $null = & chcp.com 65001
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
catch { }

if ($PSScriptRoot) {
    $ScriptDir = $PSScriptRoot
}
else {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

$PatchScript = Join-Path $ScriptDir 'localize-patch.js'
$BackupPath = Join-Path $ScriptDir 'app.asar.bak'
$TotalSteps = 6
$AssetsPatterns = @('settingsNavigation-*.js', '_chat-*.js', 'ChatView.logic-*.js', 'main-*.js', 'appSettings-*.js')
$PatchMarker = '新建对话'

function Write-Step {
    param([int]$Step, [string]$Text)
    Write-Host ''
    Write-Host "[$Step/$TotalSteps] $Text" -ForegroundColor Cyan
}

function Write-Detail {
    param([string]$Text)
    Write-Host "    $Text"
}

function Fail {
    param([string]$Text)
    Write-Host ''
    Write-Host "错误: $Text" -ForegroundColor Red
    exit 1
}

function Test-AppDir {
    param([string]$Dir)
    if (-not $Dir) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Dir 'resources\app.asar'))
}

function Find-SynaraApp {
    $direct = @()
    if ($env:LOCALAPPDATA) {
        $direct += (Join-Path $env:LOCALAPPDATA 'Programs\synara-desktop')
        $direct += (Join-Path $env:LOCALAPPDATA 'Programs\Synara')
        $direct += (Join-Path $env:LOCALAPPDATA 'Synara')
        $direct += (Join-Path $env:LOCALAPPDATA 'Programs\synara')
    }
    foreach ($programFiles in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($programFiles) { $direct += (Join-Path $programFiles 'Synara') }
    }
    foreach ($dir in $direct) {
        if (Test-AppDir $dir) { return $dir }
    }

    $roots = @()
    if ($env:LOCALAPPDATA) { $roots += (Join-Path $env:LOCALAPPDATA 'Programs') }
    if ($env:ProgramFiles) { $roots += $env:ProgramFiles }
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($sub in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            $exe = Join-Path $sub.FullName 'Synara.exe'
            if ((Test-Path -LiteralPath $exe) -and (Test-AppDir $sub.FullName)) {
                return $sub.FullName
            }
        }
    }
    return $null
}

function Assert-NodeVersion {
    param([string]$Minimum)
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCommand) {
        Fail "找不到 Node.js。请先安装 Node.js $Minimum 或更高版本（https://nodejs.org）。"
    }
    $npxCommand = Get-Command npx -ErrorAction SilentlyContinue
    if (-not $npxCommand) {
        Fail '找不到 npx。请重新安装 Node.js（其中包含 npm 与 npx）。'
    }
    $current = (& node --version).Trim().TrimStart('v')
    $currentParts = $current.Split('.')
    $minimumParts = $Minimum.Split('.')
    for ($i = 0; $i -lt $minimumParts.Count; $i++) {
        $a = 0
        $b = 0
        if ($i -lt $currentParts.Count) { [void][int]::TryParse($currentParts[$i], [ref]$a) }
        [void][int]::TryParse($minimumParts[$i], [ref]$b)
        if ($a -gt $b) { break }
        if ($a -lt $b) { Fail "当前 Node.js 版本为 v$current，@electron/asar $AsarVersion 需要 v$Minimum 或更高版本。" }
    }
    return $current
}

# 从 app.asar.unpacked 反推需要保持 unpacked 的模块根目录
function Get-UnpackRoots {
    param([string]$UnpackedDir)
    $roots = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $UnpackedDir) {
        foreach ($entry in (Get-ChildItem -LiteralPath $UnpackedDir -Directory -ErrorAction SilentlyContinue)) {
            if ($entry.Name -eq 'node_modules') {
                foreach ($module in (Get-ChildItem -LiteralPath $entry.FullName -Directory -ErrorAction SilentlyContinue)) {
                    if ($module.Name.StartsWith('@')) {
                        foreach ($scoped in (Get-ChildItem -LiteralPath $module.FullName -Directory -ErrorAction SilentlyContinue)) {
                            $roots.Add("node_modules/$($module.Name)/$($scoped.Name)")
                        }
                    }
                    else {
                        $roots.Add("node_modules/$($module.Name)")
                    }
                }
            }
            else {
                $roots.Add($entry.Name)
            }
        }
    }
    return $roots.ToArray()
}

# 生成 --unpack-dir 的 glob。
# 必须同时包含模块根目录本身：win32 依赖的可执行文件（esbuild.exe、claude.exe 等）
# 常直接放在模块根目录下，而 `根目录/**` 不会匹配根目录自身，会把这些文件打进 asar。
function Get-UnpackGlob {
    param([string[]]$Roots)
    if (-not $Roots -or $Roots.Count -eq 0) { return $null }
    $patterns = New-Object System.Collections.Generic.List[string]
    foreach ($root in $Roots) {
        $patterns.Add($root)
        $patterns.Add("$root/**")
    }
    return ('{' + ($patterns -join ',') + '}')
}

function Get-MissingPrimaryFiles {
    param([string]$ExtractDir)
    $missing = @()
    $assetsDir = Join-Path $ExtractDir 'apps\server\dist\client\assets'
    if (-not (Test-Path -LiteralPath $assetsDir)) {
        return @($assetsDir)
    }
    foreach ($pattern in $AssetsPatterns) {
        $hit = Get-ChildItem -LiteralPath $assetsDir -Filter $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $hit) { $missing += $pattern }
    }
    $mainJs = Join-Path $ExtractDir 'apps\desktop\dist-electron\main.js'
    if (-not (Test-Path -LiteralPath $mainJs)) { $missing += $mainJs }
    if (-not (Test-Path -LiteralPath (Join-Path $ExtractDir 'package.json'))) { $missing += 'package.json' }
    return $missing
}

function Test-AlreadyPatched {
    param([string]$ExtractDir)
    $assetsDir = Join-Path $ExtractDir 'apps\server\dist\client\assets'
    foreach ($pattern in @('_chat-*.js', 'settingsNavigation-*.js')) {
        $hit = Get-ChildItem -LiteralPath $assetsDir -Filter $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $hit) { continue }
        $content = [System.IO.File]::ReadAllText($hit.FullName, [System.Text.Encoding]::UTF8)
        if ($content.Contains($PatchMarker)) { return $true }
    }
    return $false
}

function Remove-WorkDir {
    param([string]$Dir)
    if (-not $Dir) { return }
    if (-not (Test-Path -LiteralPath $Dir)) { return }
    # 解包目录中存在超过 260 字符的路径，用 node 删除（Node 会自动使用 \\?\ 前缀）
    & node -e 'require("fs").rmSync(process.argv[1], { recursive: true, force: true })' $Dir 2>&1 | Out-Null
    if (Test-Path -LiteralPath $Dir) {
        Write-Detail "临时目录未能自动删除，请手动删除: $Dir"
    }
}

Write-Host '=== Synara 汉化脚本（Windows） ==='
Write-Host ''

# ---------------------------------------------------------------- 1. 环境检查
Write-Step 1 '检查安装目录与运行环境'

if (-not (Test-Path -LiteralPath $PatchScript)) {
    Fail "找不到汉化补丁脚本: $PatchScript"
}

if ($AppPath) {
    if (-not (Test-AppDir $AppPath)) {
        Fail "指定的安装目录中没有 resources\app.asar: $AppPath"
    }
    $appDir = $AppPath
}
else {
    $appDir = Find-SynaraApp
    if (-not $appDir) {
        Fail "找不到 Synara 安装目录。请用 -AppPath 指定，例如: -AppPath `"$env:LOCALAPPDATA\Programs\synara-desktop`""
    }
}

$resourcesDir = Join-Path $appDir 'resources'
$asarPath = Join-Path $resourcesDir 'app.asar'
$unpackedDir = Join-Path $resourcesDir 'app.asar.unpacked'

Write-Detail "安装目录: $appDir"
Write-Detail "目标文件: $asarPath"

$running = @(Get-Process -Name 'Synara' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    $ids = ($running | ForEach-Object { $_.Id }) -join ', '
    Fail "Synara 正在运行（PID: $ids）。请完全退出 Synara（含托盘图标）后重新运行。"
}

try {
    $stream = [System.IO.File]::Open($asarPath, 'Open', 'ReadWrite', 'None')
    $stream.Close()
}
catch {
    Fail "无法写入 $asarPath（文件被占用或权限不足）。请退出 Synara；若安装在 Program Files，请以管理员身份运行。"
}

$nodeVersion = Assert-NodeVersion -Minimum '22.12.0'
Write-Detail "Node.js: v$nodeVersion"
Write-Detail "asar 工具: @electron/asar@$AsarVersion"

# ---------------------------------------------------------------- 2. 解包
Write-Step 2 '解包 app.asar'

$workDir = Join-Path $env:TEMP ('synara-' + ([System.Guid]::NewGuid().ToString('N').Substring(0, 8)))
$extractDir = Join-Path $workDir 'extracted'
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
Write-Detail "临时目录: $workDir"

$extractOutput = & npx --yes "@electron/asar@$AsarVersion" extract $asarPath $extractDir 2>&1
$extractExit = $LASTEXITCODE
if ($extractExit -ne 0) {
    Write-Detail "解包返回码 $extractExit，检查是否仅缺少当前架构不需要的文件..."
}

$missing = @(Get-MissingPrimaryFiles -ExtractDir $extractDir)
if ($missing.Count -gt 0) {
    Remove-WorkDir $workDir
    Fail "解包结果不完整，缺少关键文件: $($missing -join ', ')。安装文件未被修改。"
}

$appVersion = (Get-Content -LiteralPath (Join-Path $extractDir 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version
$fileCount = @(Get-ChildItem -LiteralPath $extractDir -Recurse -File -Force -ErrorAction SilentlyContinue).Count
Write-Detail "解包完成，共 $fileCount 个文件（Synara $appVersion）"

# ---------------------------------------------------------------- 3. 备份
Write-Step 3 '备份原始 app.asar'

$alreadyPatched = Test-AlreadyPatched -ExtractDir $extractDir
if (-not (Test-Path -LiteralPath $BackupPath)) {
    Copy-Item -LiteralPath $asarPath -Destination $BackupPath -Force
    Write-Detail "已创建备份: $BackupPath"
    if ($alreadyPatched) {
        Write-Detail '注意: 当前 app.asar 已包含汉化内容，该备份不是原版。如需原版请从官方渠道重新安装。'
    }
}
elseif (-not $alreadyPatched) {
    Copy-Item -LiteralPath $asarPath -Destination $BackupPath -Force
    Write-Detail "检测到未汉化的 app.asar（应用已更新），已刷新备份: $BackupPath"
}
else {
    $backupTime = (Get-Item -LiteralPath $BackupPath).LastWriteTime.ToString('yyyy-MM-dd HH:mm')
    Write-Detail "备份已存在（$backupTime），保持不变: $BackupPath"
}

# ---------------------------------------------------------------- 4. 汉化
Write-Step 4 '应用汉化补丁'

$patchOutput = & node $PatchScript $extractDir 2>&1
$patchExit = $LASTEXITCODE
foreach ($line in $patchOutput) { Write-Detail $line }
if ($patchExit -ne 0) {
    Remove-WorkDir $workDir
    Fail '汉化补丁执行失败，安装文件未被修改。'
}

$totalMatch = [regex]::Match(($patchOutput -join "`n"), '总计:\s*(\d+)')
$totalReplaced = 0
if ($totalMatch.Success) { $totalReplaced = [int]$totalMatch.Groups[1].Value }
if ($totalReplaced -le 0) {
    Remove-WorkDir $workDir
    Fail '没有匹配到任何可替换的字符串，可能是 Synara 版本结构变化，已中止（安装文件未被修改）。'
}

# ---------------------------------------------------------------- 5. 打包与校验
Write-Step 5 '重新打包并校验'

$unpackRoots = @(Get-UnpackRoots -UnpackedDir $unpackedDir)
$unpackGlob = Get-UnpackGlob -Roots $unpackRoots
if ($unpackGlob) {
    Write-Detail "保持 unpacked 的模块（$($unpackRoots.Count) 个）:"
    foreach ($root in $unpackRoots) { Write-Detail "  - $root" }
}
else {
    Write-Detail '警告: 未找到 app.asar.unpacked 目录，原生模块可能无法正确加载'
}

$tempAsar = Join-Path $workDir 'app.asar.new'
$packArgs = @('--yes', "@electron/asar@$AsarVersion", 'pack', $extractDir, $tempAsar)
if ($unpackGlob) { $packArgs += @('--unpack-dir', $unpackGlob) }
$packOutput = & npx @packArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    foreach ($line in $packOutput) { Write-Detail $line }
    Remove-WorkDir $workDir
    Fail '重新打包失败，安装文件未被修改。'
}

$listOutput = @(& npx --yes "@electron/asar@$AsarVersion" list $tempAsar --is-pack 2>&1 | ForEach-Object { $_ -replace '\\', '/' })
if ($LASTEXITCODE -ne 0) {
    Remove-WorkDir $workDir
    Fail '无法读取打包结果，安装文件未被修改。'
}

$unpackEntries = @($listOutput | Where-Object { $_ -like 'unpack*: *' })
$packedPaths = @($listOutput | Where-Object { $_ -like 'pack*: *' } | ForEach-Object { $_.Substring($_.IndexOf(': ') + 2) })
if (-not ($listOutput | Where-Object { $_ -like '*apps/server/dist/client/assets/settingsNavigation-*' })) {
    Remove-WorkDir $workDir
    Fail '打包结果中缺少前端资源，安装文件未被修改。'
}
if ($unpackRoots.Count -gt 0) {
    # 原生模块目录下的任何文件都不允许被打进 asar，否则运行时会加载失败
    $rootPattern = '^/(' + (($unpackRoots | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')/'
    $misplaced = @($packedPaths | Where-Object { $_ -match $rootPattern })
    if ($misplaced.Count -gt 0) {
        Remove-WorkDir $workDir
        Fail "以下文件被打进了 asar，但它们必须在 app.asar.unpacked 中: $($misplaced -join ', ')。安装文件未被修改。"
    }
    Write-Detail "unpacked 文件: $($unpackEntries.Count) 个，覆盖 $($unpackRoots.Count) 个模块，无遗漏"
}
Write-Detail "打包完成: $($packedPaths.Count) 个内置文件，共 $($listOutput.Count) 个条目"

# ---------------------------------------------------------------- 6. 覆盖安装文件
Write-Step 6 '写入安装目录'

$newSize = (Get-Item -LiteralPath $tempAsar).Length
try {
    Copy-Item -LiteralPath $tempAsar -Destination $asarPath -Force
}
catch {
    Remove-WorkDir $workDir
    Fail "写入 $asarPath 失败: $($_.Exception.Message)"
}
$finalSize = (Get-Item -LiteralPath $asarPath).Length
if ($finalSize -ne $newSize) {
    Fail "写入后的文件大小异常（期望 $newSize 字节，实际 $finalSize 字节），请运行 restore-synara.ps1 恢复。"
}
Write-Detail "已写入 $asarPath（$([Math]::Round($finalSize / 1MB, 1)) MB）"

if (-not $KeepWorkDir) {
    Remove-WorkDir $workDir
}
else {
    Write-Detail "保留临时目录: $workDir"
}

Write-Host ''
Write-Host '=== 汉化完成！请启动 Synara 查看效果 ===' -ForegroundColor Green
Write-Host ''
Write-Host "共替换 $totalReplaced 处文本，汉化版本 Synara $appVersion。"
Write-Host "如需恢复原版，请运行 restore-synara.ps1（备份文件: $BackupPath）。"
Write-Host 'Synara 每次更新后需重新运行本脚本。'

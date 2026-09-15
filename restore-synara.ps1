#Requires -Version 5.1
<#
    Synara 恢复原版脚本（Windows）

    用法:
        .\restore-synara.ps1
        .\restore-synara.ps1 -AppPath "D:\Apps\synara-desktop"

    从 localize-synara.ps1 生成的备份 app.asar.bak 恢复原始 app.asar。
    如果 Synara 在汉化之后更新过，备份可能已经过期，建议直接从官方渠道重新安装。
#>
[CmdletBinding()]
param(
    [string]$AppPath
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# 与汉化脚本保持一致，避免中文日志乱码
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

$BackupPath = Join-Path $ScriptDir 'app.asar.bak'

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

Write-Host '=== Synara 恢复原版（Windows） ==='
Write-Host ''

if (-not (Test-Path -LiteralPath $BackupPath)) {
    Fail "找不到备份文件 $BackupPath，无法恢复原版。请从官方渠道重新安装 Synara。"
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

$asarPath = Join-Path $appDir 'resources\app.asar'

$running = @(Get-Process -Name 'Synara' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    $ids = ($running | ForEach-Object { $_.Id }) -join ', '
    Fail "Synara 正在运行（PID: $ids）。请完全退出 Synara（含托盘图标）后重新运行。"
}

$backupItem = Get-Item -LiteralPath $BackupPath
Write-Detail "安装目录: $appDir"
Write-Detail "备份文件: $BackupPath（$([Math]::Round($backupItem.Length / 1MB, 1)) MB，$($backupItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))）"

if ($backupItem.Length -lt 1MB) {
    Fail '备份文件大小异常，可能不是有效的 app.asar。请从官方渠道重新安装 Synara。'
}

try {
    Copy-Item -LiteralPath $BackupPath -Destination $asarPath -Force
}
catch {
    Fail "写入 $asarPath 失败: $($_.Exception.Message)"
}

Write-Host ''
Write-Host '=== 已恢复原版！请重启 Synara ===' -ForegroundColor Green
Write-Host ''
Write-Host "原版文件来自 $($backupItem.LastWriteTime.ToString('yyyy-MM-dd'))。"
Write-Host '如果 Synara 在此之后更新过，建议从官方渠道重新安装以避免版本不匹配。'

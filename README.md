# Synara 汉化脚本

English: [README.en.md](./README.en.md)

对 [Synara](https://github.com/Emanuele-web04/synara) 桌面应用（Electron）进行中文本地化的注入脚本，支持 macOS 与 Windows，app 更新后重复运行即可恢复汉化。

macOS 部分源自 [tttnny/synara-chinese-localization](https://github.com/tttnny/synara-chinese-localization)，在此基础上增加了 Windows 平台支持、预压缩资源同步与界面文案补充。

## 使用方法

### Windows

双击 `localize-synara.bat`，或在 PowerShell 中运行：

```powershell
# 汉化
.\localize-synara.ps1

# 指定安装目录（自动检测失败时）
.\localize-synara.ps1 -AppPath "D:\Apps\synara-desktop"

# 恢复原版
.\restore-synara.ps1
```

运行后启动 Synara 即可看到效果。脚本会自动查找安装目录（默认在 `%LOCALAPPDATA%\Programs\synara-desktop`）。

### macOS

```bash
# 汉化
./localize-synara.sh

# 指定 Synara.app 路径（默认 /Applications/Synara.app）
./localize-synara.sh /path/to/Synara.app

# 恢复原版
./restore-synara.sh
```

运行后重启 Synara 即可看到效果。脚本会自动备份原版 `app.asar` 到脚本目录，`restore-synara.sh` 可从该备份恢复。

## 前置条件

### Windows

- Node.js 22.12 或更高版本（脚本用它解包/打包 app.asar）
- 运行脚本前**完全退出 Synara**（包括托盘图标）
- 若 Synara 安装在 `Program Files`，需以管理员身份运行 PowerShell

### macOS

- Synara 安装在 `/Applications/Synara.app`
- Node.js 22.12 或更高版本（用于 `npx @electron/asar` 解包/打包）
- 运行脚本前**完全退出 Synara**（包括菜单栏图标）
- **完全磁盘访问权限**：系统设置 → 隐私与安全性 → 完全磁盘访问权限 → 添加你的终端 app 并开启，然后重启终端

## 工作原理

1. 备份原始 `app.asar`（仅首次创建；检测到应用更新后自动刷新）
2. 解包 `app.asar` 到临时目录
3. 对前端 JS bundle 执行字符串替换（2000+ 处）
4. 同步重建被替换文件的 `.br` / `.gz` 预压缩副本
5. 重新打包 `app.asar`（原生模块保持 unpacked）并校验
6. 校验通过后覆盖安装目录中的 `app.asar`

脚本通过文件名模式匹配（而非固定哈希名）定位 JS 文件，因此 app 更新后文件名变化也能正常工作。

### 两个关键细节

**预压缩资源**：Synara 的静态资源服务器按 `brotli > gzip > 原文件` 的优先级返回内容，浏览器请求会命中 `.br` 文件。因此补丁在改写 `.js` 之后会同步重建同名 `.br` / `.gz`，否则界面仍然显示英文。

**unpacked 原生模块**：`node-pty`、`esbuild`、`claude-agent-sdk` 等模块必须留在 `app.asar.unpacked` 中。模块根目录下往往直接放着可执行文件（如 `esbuild.exe`、`claude.exe`、`clipboard.*.node`），而 `node_modules/xxx/**` 这类 glob 不匹配模块根目录本身，所以打包时同时使用 `node_modules/xxx` 和 `node_modules/xxx/**` 两种模式，并在打包后校验没有任何原生模块文件被打进 asar。模块清单由脚本从 `app.asar.unpacked` 现场反推，因此不依赖硬编码列表。

## 翻译覆盖

- 设置页面全部 14 个分区（常规、外观、通知、行为、AppSnap、快捷键、工作树、归档、模型、提供商、技能、用量、高级、个人资料）
- 侧边栏导航、主聊天界面、会话详情页（审批、计划、终端、标记、Fork/交接、审查等）
- 键盘快捷键页面与命令说明（每条内置命令的名称和描述）
- 各设置页的描述文案、PR/差异面板、浏览器面板、自动化、语音笔记、引导页
- 更新通知、错误提示、确认对话框
- Windows 平台：原生菜单（文件、视图、设置、新建终端标签、键盘快捷键）、资源管理器相关文案（在资源管理器中打开）

未翻译的部分：版本更新日志（设置 → 高级 → 发布历史）中的长文本，以及主题名、编辑器名、命令、文件路径等专有名词（如 Dracula、VS Code、keybindings.json）保持原文。

## 文件说明

| 文件 | 平台 | 说明 |
|------|------|------|
| `localize-synara.ps1` | Windows | 汉化主脚本（检查→解包→备份→替换→打包校验→写入） |
| `localize-synara.bat` | Windows | 双击启动器（自动放行执行策略） |
| `restore-synara.ps1` | Windows | 恢复原版脚本 |
| `restore-synara.bat` | Windows | 双击启动器 |
| `localize-synara.sh` | macOS | 汉化主脚本（检查→解包→备份→替换→打包校验→写入→重签名） |
| `restore-synara.sh` | macOS | 恢复原版脚本 |
| `localize-patch.js` | 通用 | 核心翻译字典与替换逻辑（含预压缩资源同步） |

## 注意事项

- 每次 Synara 更新后需重新运行汉化脚本
- 备份文件 `app.asar.bak` 保存的是首次运行时的原版，体积约 240 MB，已加入 `.gitignore`
- 若 Synara 在汉化之后自动更新过，建议从官方渠道重新安装，而不是用旧备份恢复
- 少量动态字符串（如服务端返回的内容）无法通过静态替换汉化
- 如遇问题，从官方渠道重新安装即可恢复原版

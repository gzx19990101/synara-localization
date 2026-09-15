# Synara Chinese Localization

**English** | [简体中文](./README.md)

Patch scripts that inject a Simplified Chinese localization into the [Synara](https://github.com/Emanuele-web04/synara) desktop app (Electron). Works on macOS and Windows; re-run after every app update to restore the localization.

The macOS part is based on [tttnny/synara-chinese-localization](https://github.com/tttnny/synara-chinese-localization), with Windows support, pre-compressed asset regeneration and a large set of additional UI translations added here.

## Usage

### Windows

Double-click `localize-synara.bat`, or run it from PowerShell:

```powershell
# Localize
.\localize-synara.ps1

# Specify the install directory (when auto-detection fails)
.\localize-synara.ps1 -AppPath "D:\Apps\synara-desktop"

# Restore the original build
.\restore-synara.ps1
```

Start Synara afterwards to see the result. The script locates the install automatically (default: `%LOCALAPPDATA%\Programs\synara-desktop`).

### macOS

```bash
# Localize
./localize-synara.sh

# Specify a custom Synara.app path (default: /Applications/Synara.app)
./localize-synara.sh /path/to/Synara.app

# Restore the original build
./restore-synara.sh
```

Restart Synara afterwards to see the result. The script backs up the original `app.asar` next to itself, and `restore-synara.sh` restores from that backup.

## Requirements

### Windows

- Node.js 22.12 or newer (used to unpack/repack `app.asar`)
- Synara must be **fully closed** before running (including the tray icon)
- If Synara is installed under `Program Files`, run PowerShell as administrator

### macOS

- Synara installed at `/Applications/Synara.app`
- Node.js 22.12 or newer (for `npx @electron/asar`)
- Synara must be **fully closed** before running (including the menu bar icon)
- **Full Disk Access**: System Settings → Privacy & Security → Full Disk Access → add your terminal app and enable it, then restart the terminal

## How it works

1. Back up the original `app.asar` (created once; refreshed automatically when the app was updated)
2. Unpack `app.asar` into a temporary directory
3. Replace strings in the frontend JS bundles (2000+ replacements)
4. Rebuild the `.br` / `.gz` pre-compressed siblings of every modified file
5. Repack `app.asar` (native modules stay unpacked) and verify the result
6. Replace `app.asar` in the install directory only after verification passes

JS files are located by filename pattern rather than fixed hash names, so filename changes after an app update are handled automatically.

### Two details that matter

**Pre-compressed assets**: Synara's static asset server prefers `brotli > gzip > plain file`, so browser requests hit the `.br` files. The patch therefore rebuilds the matching `.br` / `.gz` files after rewriting a `.js` file; otherwise the UI still shows English.

**Unpacked native modules**: modules such as `node-pty`, `esbuild` and `claude-agent-sdk` must stay in `app.asar.unpacked`. Executables often sit directly in the module root (`esbuild.exe`, `claude.exe`, `clipboard.*.node`), and a glob like `node_modules/xxx/**` does not match the module root itself, so packing uses both `node_modules/xxx` and `node_modules/xxx/**`. After packing, the scripts verify that no file from a native module directory ended up inside the asar. The module list is derived from the existing `app.asar.unpacked` at runtime instead of being hardcoded.

## Translation coverage

- All 14 settings sections (General, Appearance, Notifications, Behavior, AppSnap, Keyboard Shortcuts, Worktrees, Archived, Models, Providers, Skills, Usage, Advanced, Profile)
- Sidebar navigation, main chat UI, thread detail view (approvals, plans, terminal, markers, fork/hand-off, review, ...)
- Keyboard shortcuts page and command descriptions (name and description of every built-in command)
- Settings descriptions, pull request and diff panels, browser panel, automations, voice notes, onboarding
- Update notifications, error messages, confirmation dialogs
- Windows-specific: native menu (File, View, Settings, New Terminal Tab, Keyboard Shortcuts) and Explorer-related strings (Open in Explorer)

Not translated on purpose: the long release notes in Settings → Advanced → Release history, plus proper nouns such as theme names, editor names, commands and file paths (for example `Dracula`, `VS Code`, `keybindings.json`).

## Files

| File | Platform | Description |
|------|----------|-------------|
| `localize-synara.ps1` | Windows | Main localization script (check → unpack → backup → patch → pack & verify → write) |
| `localize-synara.bat` | Windows | Double-click launcher (bypasses the execution policy) |
| `restore-synara.ps1` | Windows | Restore script |
| `restore-synara.bat` | Windows | Double-click launcher |
| `localize-synara.sh` | macOS | Main localization script (check → unpack → backup → patch → pack & verify → write → re-sign) |
| `restore-synara.sh` | macOS | Restore script |
| `localize-patch.js` | Both | Translation dictionary and replacement logic (also rebuilds pre-compressed assets) |

## Notes

- Re-run the script after every Synara update
- The backup file `app.asar.bak` is roughly 240 MB and is listed in `.gitignore`
- If Synara auto-updated after you localized it, prefer reinstalling from the official source over restoring an outdated backup
- A few dynamic strings (for example content returned by the server) cannot be localized by static replacement
- If anything goes wrong, reinstall Synara from the official source to get a clean build back

## Other languages

Simplified Chinese and English are available today. To add another language, copy `README.en.md` to `README.<locale>.md` and register it in the language bar at the top of both files.

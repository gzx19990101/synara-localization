#!/bin/bash
# Synara 恢复原版脚本（macOS）
# 用法: ./restore-synara.sh [Synara.app 路径]
#
# 从 localize-synara.sh 生成的备份 app.asar.bak 恢复原始 app.asar。
# 如果 Synara 在汉化之后更新过，备份可能已经过期，建议直接从官方渠道重新安装。

set -e

APP_PATH="${1:-/Applications/Synara.app}"
ASAR_PATH="$APP_PATH/Contents/Resources/app.asar"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_PATH="$SCRIPT_DIR/app.asar.bak"

echo "=== Synara 恢复原版（macOS） ==="
echo ""

if [ ! -f "$BACKUP_PATH" ]; then
    echo "错误: 找不到备份文件 $BACKUP_PATH，无法恢复原版。"
    echo "请从官方渠道重新安装 Synara。"
    exit 1
fi

if [ ! -f "$ASAR_PATH" ]; then
    echo "错误: 找不到 $ASAR_PATH"
    echo "请确认 Synara 已安装，或用参数指定: ./restore-synara.sh /path/to/Synara.app"
    exit 1
fi

if pgrep -f "Synara.app/Contents/MacOS/Synara" > /dev/null 2>&1; then
    echo "错误: Synara 正在运行，请完全退出后重新运行（包括菜单栏图标）"
    exit 1
fi

BACKUP_SIZE="$(wc -c < "$BACKUP_PATH" | tr -d ' ')"
if [ "$BACKUP_SIZE" -lt 1048576 ]; then
    echo "错误: 备份文件大小异常，可能不是有效的 app.asar。请从官方渠道重新安装 Synara。"
    exit 1
fi

echo "    安装目录: $APP_PATH"
echo "    备份文件: $BACKUP_PATH（$(echo "$BACKUP_SIZE" | awk '{printf "%.1f", $1/1048576}') MB）"

cp "$BACKUP_PATH" "$ASAR_PATH"

# 修改 asar 后原签名失效，macOS 会阻止启动
if command -v codesign > /dev/null 2>&1; then
    codesign --remove-signature "$APP_PATH" 2>/dev/null || true
    codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true
fi
if command -v xattr > /dev/null 2>&1; then
    xattr -cr "$APP_PATH" 2>/dev/null || true
fi

echo ""
echo "=== 已恢复原版！请重启 Synara ==="
echo ""
echo "如果 Synara 在备份之后更新过，建议从官方渠道重新安装以避免版本不匹配。"

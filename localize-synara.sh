#!/bin/bash
# Synara 汉化脚本（macOS）
# 用法: ./localize-synara.sh [Synara.app 路径]
# 每次 Synara 更新后重新运行本脚本即可恢复汉化
# 依赖: node >= 22.12, npx (用于 @electron/asar 打包/解包)
#
# 流程:
#   1. 检查安装目录、运行状态与 Node 版本
#   2. 解包 app.asar 到临时目录
#   3. 备份原始 app.asar（首次创建；检测到应用更新后自动刷新）
#   4. 运行 localize-patch.js 替换前端 JS 字符串
#   5. 重新打包 app.asar 并校验 unpacked 原生模块标记
#   6. 覆盖安装目录中的 app.asar 并移除失效的代码签名

set -e

APP_PATH="${1:-/Applications/Synara.app}"
ASAR_PATH="$APP_PATH/Contents/Resources/app.asar"
UNPACKED_DIR="$ASAR_PATH.unpacked"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_SCRIPT="$SCRIPT_DIR/localize-patch.js"
BACKUP_PATH="$SCRIPT_DIR/app.asar.bak"
ASAR_PKG="@electron/asar@4.3.0"
MIN_NODE_MAJOR=22
MIN_NODE_MINOR=12

echo "=== Synara 汉化脚本（macOS） ==="
echo ""

# ---------------------------------------------------------------- 1. 环境检查
echo "[1/6] 检查安装目录与运行环境"

if [ ! -f "$ASAR_PATH" ]; then
    echo "错误: 找不到 $ASAR_PATH"
    echo "请确认 Synara 已安装，或用参数指定: ./localize-synara.sh /path/to/Synara.app"
    exit 1
fi

if [ ! -f "$PATCH_SCRIPT" ]; then
    echo "错误: 找不到汉化补丁脚本 $PATCH_SCRIPT"
    exit 1
fi

if ! command -v node > /dev/null 2>&1 || ! command -v npx > /dev/null 2>&1; then
    echo "错误: 需要 Node.js $MIN_NODE_MAJOR.$MIN_NODE_MINOR 或更高版本（含 npx）"
    exit 1
fi

NODE_VERSION="$(node --version | sed 's/^v//')"
NODE_MAJOR="$(echo "$NODE_VERSION" | cut -d. -f1)"
NODE_MINOR="$(echo "$NODE_VERSION" | cut -d. -f2)"
if [ "$NODE_MAJOR" -lt "$MIN_NODE_MAJOR" ] ||
    { [ "$NODE_MAJOR" -eq "$MIN_NODE_MAJOR" ] && [ "$NODE_MINOR" -lt "$MIN_NODE_MINOR" ]; }; then
    echo "错误: 当前 Node.js 版本为 v$NODE_VERSION，@electron/asar 需要 v$MIN_NODE_MAJOR.$MIN_NODE_MINOR 或更高版本"
    exit 1
fi

if pgrep -f "Synara.app/Contents/MacOS/Synara" > /dev/null 2>&1; then
    echo "错误: Synara 正在运行，请完全退出后重新运行（包括菜单栏图标）"
    exit 1
fi

echo "    安装目录: $APP_PATH"
echo "    目标文件: $ASAR_PATH"
echo "    Node.js: v$NODE_VERSION"
echo "    asar 工具: $ASAR_PKG"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/synara-localize.XXXXXX")"
EXTRACT_DIR="$WORK_DIR/extracted"
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------------------------------------------------------------- 2. 解包
echo ""
echo "[2/6] 解包 app.asar"

# 安装器可能裁剪掉其它架构的文件，此时解包会返回非零退出码，因此改为校验关键文件是否齐全
set +e
npx --yes "$ASAR_PKG" extract "$ASAR_PATH" "$EXTRACT_DIR" > "$WORK_DIR/extract.log" 2>&1
EXTRACT_CODE=$?
set -e
if [ "$EXTRACT_CODE" -ne 0 ]; then
    echo "    解包返回码 $EXTRACT_CODE，检查关键文件是否完整..."
fi

ASSETS_DIR="$EXTRACT_DIR/apps/server/dist/client/assets"
check_asset() {
    if ! ls "$ASSETS_DIR"/$1 > /dev/null 2>&1; then
        echo "错误: 解包结果不完整，缺少 $1。安装文件未被修改。"
        exit 1
    fi
}
check_asset "settingsNavigation-*.js"
check_asset "_chat-*.js"
check_asset "ChatView.logic-*.js"
check_asset "main-*.js"
check_asset "appSettings-*.js"

if [ ! -f "$EXTRACT_DIR/apps/desktop/dist-electron/main.js" ] || [ ! -f "$EXTRACT_DIR/package.json" ]; then
    echo "错误: 解包结果不完整，缺少 Electron 主进程或 package.json。安装文件未被修改。"
    exit 1
fi

APP_VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$EXTRACT_DIR/package.json" | head -1)"
FILE_COUNT="$(find "$EXTRACT_DIR" -type f | wc -l | tr -d ' ')"
echo "    解包完成，共 $FILE_COUNT 个文件（Synara $APP_VERSION）"

# ---------------------------------------------------------------- 3. 备份
echo ""
echo "[3/6] 备份原始 app.asar"

ALREADY_PATCHED=0
CHAT_FILE="$(ls "$ASSETS_DIR"/_chat-*.js 2>/dev/null | head -1)"
if [ -n "$CHAT_FILE" ] && grep -q "新建对话" "$CHAT_FILE" 2>/dev/null; then
    ALREADY_PATCHED=1
fi

if [ ! -f "$BACKUP_PATH" ]; then
    cp "$ASAR_PATH" "$BACKUP_PATH"
    echo "    已创建备份: $BACKUP_PATH"
    if [ "$ALREADY_PATCHED" -eq 1 ]; then
        echo "    注意: 当前 app.asar 已包含汉化内容，该备份不是原版。如需原版请从官方渠道重新安装。"
    fi
elif [ "$ALREADY_PATCHED" -eq 0 ]; then
    cp "$ASAR_PATH" "$BACKUP_PATH"
    echo "    检测到未汉化的 app.asar（应用已更新），已刷新备份: $BACKUP_PATH"
else
    echo "    备份已存在，保持不变: $BACKUP_PATH"
fi

# ---------------------------------------------------------------- 4. 汉化
echo ""
echo "[4/6] 应用汉化补丁"

set +e
node "$PATCH_SCRIPT" "$EXTRACT_DIR" 2>&1 | sed 's/^/    /'
PATCH_CODE=${PIPESTATUS[0]}
set -e
if [ "$PATCH_CODE" -ne 0 ]; then
    echo "错误: 汉化补丁执行失败，安装文件未被修改。"
    exit 1
fi

# 从 app.asar.unpacked 反推需要保持 unpacked 的模块根目录
UNPACK_ROOTS=""
if [ -d "$UNPACKED_DIR/node_modules" ]; then
    for module_dir in "$UNPACKED_DIR/node_modules"/*; do
        [ -d "$module_dir" ] || continue
        module_name="$(basename "$module_dir")"
        if [ "${module_name#@}" != "$module_name" ]; then
            for scoped_dir in "$module_dir"/*; do
                [ -d "$scoped_dir" ] || continue
                root="$(basename "$module_dir")/$(basename "$scoped_dir")"
                UNPACK_ROOTS="${UNPACK_ROOTS:+$UNPACK_ROOTS,}$root"
            done
        else
            UNPACK_ROOTS="${UNPACK_ROOTS:+$UNPACK_ROOTS,}$module_name"
        fi
    done
fi

if [ -n "$UNPACK_ROOTS" ]; then
    # 模块根目录本身也要匹配：可执行文件常直接放在模块根目录下，
    # 而 "模块/**" 不会匹配模块根目录自身，会把这些文件打进 asar。
    UNPACK_GLOB=""
    OLD_IFS="$IFS"
    IFS=','
    for root in $UNPACK_ROOTS; do
        UNPACK_GLOB="${UNPACK_GLOB:+$UNPACK_GLOB,}node_modules/$root,node_modules/$root/**"
    done
    IFS="$OLD_IFS"
    UNPACK_GLOB="{$UNPACK_GLOB}"
    echo "    保持 unpacked 的模块（$(echo "$UNPACK_ROOTS" | tr ',' '\n' | wc -l | tr -d ' ') 个）: $UNPACK_ROOTS"
else
    UNPACK_GLOB=""
    echo "    警告: 未找到 app.asar.unpacked 目录，原生模块可能无法正确加载"
fi

# ---------------------------------------------------------------- 5. 打包与校验
echo ""
echo "[5/6] 重新打包并校验"

TMP_ASAR="$WORK_DIR/app.asar.new"
PACK_ARGS=""
[ -n "$UNPACK_GLOB" ] && PACK_ARGS="--unpack-dir $UNPACK_GLOB"

# shellcheck disable=SC2086
if ! npx --yes "$ASAR_PKG" pack "$EXTRACT_DIR" "$TMP_ASAR" $PACK_ARGS > "$WORK_DIR/pack.log" 2>&1; then
    sed 's/^/    /' "$WORK_DIR/pack.log"
    echo "错误: 重新打包失败，安装文件未被修改。"
    exit 1
fi

npx --yes "$ASAR_PKG" list "$TMP_ASAR" --is-pack | tr '\\' '/' > "$WORK_DIR/list.txt"

if ! grep -q "apps/server/dist/client/assets/settingsNavigation-" "$WORK_DIR/list.txt"; then
    echo "错误: 打包结果中缺少前端资源，安装文件未被修改。"
    exit 1
fi

PACKED_COUNT="$(grep -c "^pack" "$WORK_DIR/list.txt" || true)"
UNPACKED_COUNT="$(grep -c "^unpack" "$WORK_DIR/list.txt" || true)"

if [ -n "$UNPACK_ROOTS" ]; then
    # 原生模块目录下不允许有任何文件被打进 asar，否则运行时会加载失败
    ROOTS_REGEX="$(echo "$UNPACK_ROOTS" | sed 's/,/|/g' | sed 's/\./\\./g')"
    MISPLACED="$(grep -E "^pack[[:space:]]*: /($ROOTS_REGEX)/" "$WORK_DIR/list.txt" || true)"
    if [ -n "$MISPLACED" ]; then
        echo "错误: 以下文件被打进了 asar，但它们必须在 app.asar.unpacked 中:"
        echo "$MISPLACED" | head -20 | sed 's/^/    /'
        echo "安装文件未被修改。"
        exit 1
    fi
    echo "    unpacked 文件: $UNPACKED_COUNT 个，原生模块目录下无遗漏"
fi
echo "    打包完成: $PACKED_COUNT 个内置文件"

# ---------------------------------------------------------------- 6. 覆盖安装文件
echo ""
echo "[6/6] 写入安装目录并处理代码签名"

TMP_SIZE="$(wc -c < "$TMP_ASAR" | tr -d ' ')"
cp "$TMP_ASAR" "$ASAR_PATH"
FINAL_SIZE="$(wc -c < "$ASAR_PATH" | tr -d ' ')"
if [ "$TMP_SIZE" != "$FINAL_SIZE" ]; then
    echo "错误: 写入后的文件大小异常（期望 $TMP_SIZE 字节，实际 $FINAL_SIZE 字节），请运行 ./restore-synara.sh 恢复。"
    exit 1
fi
echo "    已写入 $ASAR_PATH（$(echo "$FINAL_SIZE" | awk '{printf "%.1f", $1/1048576}') MB）"

# 修改 asar 后原签名失效，macOS 会阻止启动
if command -v codesign > /dev/null 2>&1; then
    codesign --remove-signature "$APP_PATH" 2>/dev/null || true
    codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true
fi
if command -v xattr > /dev/null 2>&1; then
    xattr -cr "$APP_PATH" 2>/dev/null || true
fi

echo ""
echo "=== 汉化完成！请启动 Synara 查看效果 ==="
echo ""
echo "汉化版本 Synara $APP_VERSION。"
echo "如需恢复原版，请运行 ./restore-synara.sh（备份文件: $BACKUP_PATH）。"
echo "Synara 每次更新后需重新运行本脚本。"

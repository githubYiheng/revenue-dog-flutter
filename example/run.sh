#!/usr/bin/env bash
#
# run.sh —— 带 staging key 启动 / 构建 Flutter 测试 app（设计 §7「测试 app」、M3）
#
#   example/run.sh android [--release] [--build] [flutter 参数…]   # 真机 / 模拟器跑 Android（Play license tester 测试购买）
#   example/run.sh ios     [--release] [--build] [flutter 参数…]   # 真机 / 模拟器跑 iOS（App Store 沙盒，不走本地 .storekit）
#   example/run.sh ios-xcode [--release]                           # 只生成带 key 的 Xcode 配置，然后在 Xcode 里 Run
#                                                                  #（Runner scheme 挂了 RevenueDog.storekit，本地 StoreKit 交易）
#   例：example/run.sh android -d <device-id>        example/run.sh ios --build --simulator
#
# key 从哪来（绝不入库、绝不打印）：
#   iOS     ~/selah-keys/revdog-staging-demo-pk.txt              （staging 项目 demo，裸值）
#   Android ~/selah-keys/revdog-example-android-staging-pk.txt   （staging 项目 revdog-example，CLI 原文，取 `key` 行）
#   可用 REVDOG_KEY_FILE_IOS / REVDOG_KEY_FILE_ANDROID 覆盖路径；REVDOG_BASE_URL 覆盖后端（缺省 staging）。
# 注入方式：写一个 0600 的临时 JSON 交给 `--dart-define-from-file`，脚本退出即删 ——
#   key 不出现在命令行参数（`ps` 看不到）、不进 shell history。
#   例外：ios-xcode 模式下 Flutter 会把 dart-define 以 base64 写进 ios/Flutter/Generated.xcconfig（已 gitignore，仅本机）。
#
# 为什么 iOS 分两种：`flutter run` 用 simctl / devicectl 直接装起，**不走 Xcode scheme 的 Run 动作**，
#   所以 scheme 里的 StoreKit Configuration 只在「Xcode 里点 Run」时生效。本地 .storekit 交易绝不打线上（cutover-gate C1）；
#   这里 baseUrl 缺省 staging，同样不会打生产。
#
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.4}"
KEY_FILE_IOS="${REVDOG_KEY_FILE_IOS:-$HOME/selah-keys/revdog-staging-demo-pk.txt}"
KEY_FILE_ANDROID="${REVDOG_KEY_FILE_ANDROID:-$HOME/selah-keys/revdog-example-android-staging-pk.txt}"
BASE_URL="${REVDOG_BASE_URL:-https://api-staging.revdog.org}"

usage() { sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
fail()  { echo "❌ $*" >&2; exit 1; }
step()  { printf '\n==> %s\n' "$*"; }

PLATFORM="${1:-}"
[[ -n "$PLATFORM" ]] || usage
shift
case "$PLATFORM" in android|ios|ios-xcode) ;; *) usage ;; esac

MODE="--debug"
BUILD=0
PASSTHROUGH=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --release) MODE="--release" ;;
        --build)   BUILD=1 ;;
        -h|--help) usage ;;
        *)         PASSTHROUGH+=("$1") ;;
    esac
    shift
done

# 取 key：CLI 原文格式取 `key <值>` 那一行；否则整个文件必须只有一个 token（裸值）。只校验形状，不回显。
read_key() {
    local file="$1" key
    [[ -f "$file" ]] || fail "key 文件不存在：$file"
    key="$(awk '$1 == "key" { print $2; exit }' "$file")"
    if [[ -z "$key" ]]; then
        [[ "$(wc -w < "$file" | tr -d ' ')" == "1" ]] || fail "$file 既没有 'key <值>' 行，也不是单个裸值"
        key="$(tr -d '[:space:]' < "$file")"
    fi
    [[ "$key" =~ ^pk_[A-Za-z0-9_-]+$ ]] || fail "$file 里的 key 不是 pk_ 开头的 public key（不回显值）"
    printf '%s' "$key"
}

EXAMPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$EXAMPLE_DIR"

if [[ "$PLATFORM" == "android" ]]; then
    KEY_NAME="REVDOG_API_KEY_ANDROID"; KEY_FILE="$KEY_FILE_ANDROID"
else
    KEY_NAME="REVDOG_API_KEY_IOS"; KEY_FILE="$KEY_FILE_IOS"
fi
KEY="$(read_key "$KEY_FILE")"

DEFINES_FILE="$(umask 077 && mktemp "${TMPDIR:-/tmp}/revdog-example-defines.XXXXXX")"
trap 'rm -f "$DEFINES_FILE" "$DEFINES_FILE.json"' EXIT
# --dart-define-from-file 按扩展名识别格式，必须以 .json 结尾。
DEFINES_FILE_JSON="$DEFINES_FILE.json"
( umask 077 && printf '{"%s":"%s","REVDOG_BASE_URL":"%s"}\n' "$KEY_NAME" "$KEY" "$BASE_URL" > "$DEFINES_FILE_JSON" )
unset KEY

echo "平台 $PLATFORM · 模式 ${MODE#--} · key 文件 ${KEY_FILE}（已读取，不回显）· baseUrl $BASE_URL"

flutter() { fvm spawn "$FLUTTER_VERSION" "$@"; }

step "pub get"
flutter pub get

case "$PLATFORM" in
    android)
        if [[ "$BUILD" == "1" ]]; then
            step "build apk ${MODE#--}"
            flutter build apk "$MODE" --dart-define-from-file="$DEFINES_FILE_JSON" ${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}
        else
            step "run ${MODE#--}（Android）"
            flutter run "$MODE" --dart-define-from-file="$DEFINES_FILE_JSON" ${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}
        fi
        ;;
    ios)
        if [[ "$BUILD" == "1" ]]; then
            step "build ios ${MODE#--}"
            flutter build ios "$MODE" --dart-define-from-file="$DEFINES_FILE_JSON" ${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}
        else
            step "run ${MODE#--}（iOS，App Store 沙盒；本地 .storekit 请用 ios-xcode）"
            flutter run "$MODE" --dart-define-from-file="$DEFINES_FILE_JSON" ${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}
        fi
        ;;
    ios-xcode)
        step "build ios --config-only ${MODE#--}（把 dart-define 写进 Generated.xcconfig）"
        flutter build ios --config-only "$MODE" --dart-define-from-file="$DEFINES_FILE_JSON" ${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}
        cat <<XCODE

下一步：open "$EXAMPLE_DIR/ios/Runner.xcworkspace"
  → 选 Runner scheme + 模拟器 / 真机 → Run（⌘R）。
  Edit Scheme → Run → Options → StoreKit Configuration 应显示 RevenueDog.storekit（本地商品 com.demo.*）。
  交易管理：Xcode → Debug → StoreKit → Manage Transactions（退款 / Ask to Buy 批准 / 清空）。
XCODE
        ;;
esac

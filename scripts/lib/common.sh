# scripts/ の各スクリプトが source する共通の関数。単体では実行しない。
# macOS 標準の bash 3.2 で動かすので、連想配列・mapfile・${var,,} などは使わない。
# 進み具合とエラーは標準エラーに出し、標準出力は結果（.app の場所など）だけにする。

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  _BOLD=$'\033[1m' _RED=$'\033[31m' _YELLOW=$'\033[33m' _RESET=$'\033[0m'
else
  _BOLD="" _RED="" _YELLOW="" _RESET=""
fi

# いまのステップの名前。release.sh が失敗の表示に使う
# shellcheck disable=SC2034
CURRENT_STEP=""

step() {
  # shellcheck disable=SC2034
  CURRENT_STEP="$*"
  printf '%s==> %s%s\n' "$_BOLD" "$*" "$_RESET" >&2
}

info() { printf '    %s\n' "$*" >&2; }
warn() { printf '%swarning:%s %s\n' "$_YELLOW" "$_RESET" "$*" >&2; }
error() { printf '%serror:%s %s\n' "$_RED" "$_RESET" "$*" >&2; }

die() {
  error "$*"
  exit 1
}

# 前後の空白を除く
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# 見つからないコマンドを1行ずつ出す
missing_commands() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || printf '%s\n' "$c"
  done
}

require_commands() {
  local missing
  missing="$(missing_commands "$@")"
  [[ -z "$missing" ]] || die "必要なコマンドがありません: $(printf '%s' "$missing" | tr '\n' ' ')（XcodeGen は brew install xcodegen）"
}

# xcconfig の値を読む。Xcode と同じく // から後ろはコメント、$() は空文字として扱う。
# 同じキーが何度もあれば最後のもの。無ければ空文字
xcconfig_value() {
  local file="$1" key="$2" line value found="" empty_expansion="\$()"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    case "$line" in
      "$key"=* | "$key"[[:space:]]*=*) ;;
      *) continue ;;
    esac
    value="${line#*=}"
    value="${value%%//*}"
    value="${value//"$empty_expansion"/}"
    found="$(trim "$value")"
  done <"$file"
  printf '%s' "$found"
}

# xcconfig の = から後ろを、// で切らずにそのまま読む（値が // で切れているかを見分けるため）。
# 同じキーが何度もあれば最後のもの。無ければ空文字
xcconfig_raw_value() {
  local file="$1" key="$2" line found=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    case "$line" in
      "$key"=* | "$key"[[:space:]]*=*) ;;
      *) continue ;;
    esac
    found="$(trim "${line#*=}")"
  done <"$file"
  printf '%s' "$found"
}

# project.yml の DEVELOPMENT_TEAM（チーム ID）
project_team_id() {
  sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM:[[:space:]]*"?([A-Z0-9]{10})"?.*$/\1/p' "$1" | head -n 1
}

# キーチェーンにある有効なコード署名の証明書（security find-identity の行）
signing_identities() {
  security find-identity -v -p codesigning 2>/dev/null || true
}

# チームの Developer ID Application 証明書の SHA-1。無ければ空文字
developer_id_identity() {
  local team="$1"
  signing_identities |
    grep -F '"Developer ID Application:' |
    grep -F "($team)\"" |
    head -n 1 |
    awk '{ print $2 }' || true
}

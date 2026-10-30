#!/bin/bash
# 直販用のリリースを作る: アーカイブ → 書き出し → 署名の確認 → 公証 → DMG → appcast。
# 使い方は --help、準備と手順の全体は docs/release.md。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
使い方: scripts/release.sh [オプション] <バージョン> <ビルド番号>

  <バージョン>    利用者に見せる版（MARKETING_VERSION）。例: 1.2.0
  <ビルド番号>    Sparkle が新旧を比べる番号（CURRENT_PROJECT_VERSION）。
                  リリースのたびに、公開済みのものより大きい整数にする

オプション:
  --dry-run          公証とステープルをせずに、署名した DMG と appcast の試し版まで作る。
                     公開用のフォルダ（NONET_RELEASES_DIR）には触れない
  --notes <ファイル>  リリースノート（.html / .md / .txt）。appcast に埋め込まれる。
                     リポジトリの中に置いても、このファイルはコミットしていなくてよい
  --first-release    初めてのリリース。公開中の appcast が無い（HTTP 404・410）ときに、新しく作ってよいことを示す
  --force-local-appcast
                     公開中の appcast を取ってこずに、手元の appcast.xml（NONET_RELEASES_DIR）をそのまま使う。
                     公開中のビルドが手元に無いと止まるが、手元が正しいと分かっているときだけ付ける
  --allow-dirty      コミットしていない変更があっても続ける
  -h, --help         この説明を表示する

環境変数:
  NONET_NOTARY_PROFILE       notarytool store-credentials で保存したプロファイル名（--dry-run 以外で必須）
  NONET_RELEASES_DIR         公開する DMG と appcast.xml を貯めるフォルダ（既定: build/releases）
  NONET_DOWNLOAD_URL_PREFIX  DMG を置く URL（既定: appcast.xml と同じ場所）
  NONET_SPARKLE_KEY_ACCOUNT  Sparkle の秘密鍵のキーチェーンのアカウント名（既定: ed25519）
  NONET_NOTARY_TIMEOUT       公証の結果を待つ上限（既定: 1h）

できるもの:
  build/release/<バージョン>/   作業用（アーカイブ・書き出した .app・ログ）
  $NONET_RELEASES_DIR/Nonet-<バージョン>.dmg と appcast.xml（--dry-run では作業用フォルダの appcast-preview/）
  手元の appcast は NONET_APPCAST_URL のファイル名にかかわらず appcast.xml。その URL にアップロードする
EOF
}

usage_error() {
  error "$1"
  printf '詳しくは scripts/release.sh --help\n' >&2
  exit 2
}

# MARKETING_VERSION は「1.2」か「1.2.3」
is_valid_version() {
  local re='^[0-9]+\.[0-9]+(\.[0-9]+)?$'
  [[ "$1" =~ $re ]]
}

# CFBundleVersion は Sparkle が大小を比べるので、1 以上の整数に限る
is_valid_build() {
  local re='^[1-9][0-9]*$'
  [[ "$1" =~ $re ]]
}

# Ed25519 の公開鍵（32 バイト）の base64。標準形（= 付き）と URL 安全形（= 無し）を受け付ける
is_ed25519_public_key() {
  local standard='^[A-Za-z0-9+/]{43}=$' url_safe='^[A-Za-z0-9_-]{43}$'
  [[ "$1" =~ $standard || "$1" =~ $url_safe ]]
}

is_placeholder() {
  case "$1" in
    *example.com* | *example.org* | *example.net* | *.invalid* | *TODO*) return 0 ;;
    *) return 1 ;;
  esac
}

# Config/Nonet.xcconfig の販売用の値の問題を1行ずつ出す。問題が無ければ何も出さない
config_problems() {
  local file="$1" key value uncut
  if [[ ! -f "$file" ]]; then
    printf '%s がありません\n' "$file"
    return 0
  fi
  for key in NONET_APPCAST_URL NONET_PURCHASE_URL NONET_SUPPORT_URL NONET_PRIVACY_URL; do
    value="$(xcconfig_value "$file" "$key")"
    if [[ -z "$value" ]]; then
      printf '%s が空です\n' "$key"
    elif [[ "$value" == "https:" || "$value" == "http:" ]]; then
      printf '%s が「%s」で切れています。xcconfig では // から後ろがコメントになるので %s/example.com/… のように書いてください\n' \
        "$key" "$value" "https:/\$()"
    elif [[ "$value" != https://?* ]]; then
      printf '%s は https:// で始まる URL にしてください（いまは %s）\n' "$key" "$value"
    elif is_placeholder "$value"; then
      printf '%s が仮の値のままです（%s）\n' "$key" "$value"
    fi
  done
  for key in NONET_SPARKLE_PUBLIC_KEY NONET_LICENSE_PUBLIC_KEY; do
    value="$(xcconfig_value "$file" "$key")"
    # base64 の公開鍵の約1%は「//」を含み、xcconfig ではそこから後ろがコメントになって切れる
    uncut="$(xcconfig_raw_value "$file" "$key")"
    uncut="${uncut//"\$()"/}"
    if is_ed25519_public_key "$value"; then
      continue
    elif [[ "$uncut" == *//* ]] && is_ed25519_public_key "$uncut"; then
      printf '%s が「//」の所で切れています。xcconfig では // から後ろがコメントになるので、公開鍵の「//」を「%s」と書いてください\n' \
        "$key" "/\$()/"
    elif [[ -z "$value" ]]; then
      printf '%s が空です\n' "$key"
    else
      printf '%s が Ed25519 の公開鍵（base64 で 44 文字）になっていません\n' "$key"
    fi
  done
}

# AI のアクションは FoundationModels（macOS 26 の SDK から）が無いとビルドから外れ、古い Xcode でもビルドは通ってしまう。
# そのまま配ると AI のアクションがすべて「macOS 26 以降が必要」で失敗するので、選ばれている SDK に無ければ問題を1行出す
foundation_models_problem() {
  local sdk version
  sdk="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  version="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
  if [[ -z "$sdk" ]]; then
    printf 'macOS の SDK が見つかりません（xcode-select -p で、選ばれている Xcode を確かめてください）\n'
  elif [[ ! -d "$sdk/System/Library/Frameworks/FoundationModels.framework" ]]; then
    printf 'macOS SDK %s に FoundationModels がありません。Xcode 26 以降を選んでください（sudo xcode-select -s /Applications/Xcode.app）。古い SDK でビルドすると、AI のアクションが動かないアプリになります\n' \
      "${version:-（版が不明）}"
  fi
}

# プライバシーポリシー（docs/privacy.md）は、製品版が試用の記録をログインキーチェーンの項目にも置くと書いている。
# アプリ（App/）がその置き場所を使っていなければ（UserDefaultsLicenseStorage(keychain: SystemTrialRecordKeychain())）、問題を1行出す
trial_keychain_problem() {
  local root="$1" service="com.iam74k4.Nonet.license.trial"
  [[ -d "$root/App" ]] || return 0
  grep -qF "$service" "$root/docs/privacy.md" 2>/dev/null || return 0
  grep -rqsF --include='*.swift' 'SystemTrialRecordKeychain()' "$root/App" && return 0
  printf 'App/ が試用の記録をキーチェーンに置いていません（AppDelegate の UserDefaultsLicenseStorage() を UserDefaultsLicenseStorage(keychain: SystemTrialRecordKeychain()) にする）。プライバシーポリシー（docs/privacy.md と販売ページ）は、製品版がキーチェーンの項目 %s を作ると書いています\n' "$service"
}

# Sparkle の appcast（RSS）らしい中身か。ホスティングによっては、無いファイルにも 200 で index.html を返す
is_appcast_file() {
  grep -qE '<rss[[:space:]>]' "$1" 2>/dev/null
}

# appcast に載っているビルド番号（sparkle:version）を、小さい順に1行ずつ（同じものは1つ）
appcast_builds() {
  [[ -f "$1" ]] || return 0
  grep -oE '<sparkle:version>[0-9]+</sparkle:version>|sparkle:version="[0-9]+"' "$1" |
    grep -oE '[0-9]+' |
    sort -n -u || true
}

# appcast に載っている最大のビルド番号。無ければ空文字
appcast_latest_build() {
  appcast_builds "$1" | tail -n 1
}

# 1つ目の appcast にあって、2つ目に無いビルド番号（空白区切り）。無ければ空文字
appcast_builds_missing() {
  local build missing="" others
  others="$(appcast_builds "$2")"
  for build in $(appcast_builds "$1"); do
    grep -qx "$build" <<<"$others" || missing+="${missing:+ }$build"
  done
  printf '%s' "$missing"
}

# 空白・改行の違いを除けば同じか（ホスティングが空白を書き換えることがある）
same_ignoring_whitespace() {
  cmp -s <(tr -d '[:space:]' <"$1") <(tr -d '[:space:]' <"$2")
}

# URL の最後の名前（? と # から後ろは除く）。例: https://x/updates/nonet.xml?v=1 → nonet.xml
url_file_name() {
  local path="${1%%[?#]*}"
  printf '%s' "${path##*/}"
}

# appcast.xml と同じ場所（末尾は /）
download_url_prefix() {
  local appcast_url="$1" override="${2:-}" prefix
  if [[ -n "$override" ]]; then
    prefix="$override"
  else
    prefix="${appcast_url%/*}"
  fi
  [[ "$prefix" == */ ]] || prefix="$prefix/"
  printf '%s' "$prefix"
}

# Info.plist の値。無ければ空文字
plist_value() {
  plutil -extract "$2" raw -o - "$1" 2>/dev/null || true
}

# codesign -dvv の出力（codesign は標準エラーに出す）
signature_details() {
  codesign -dvv "$1" 2>&1 || true
}

# 公証に必要な署名（Developer ID・セキュアタイムスタンプ）の問題を1行ずつ出す。
# team を渡せばチーム ID も、require_runtime が 1 なら hardened runtime も確かめる
signature_problems() {
  local path="$1" team="$2" require_runtime="$3" details name
  name="${path#"$WORK/"}"
  details="$(signature_details "$path")"
  grep -q '^Authority=Developer ID Application:' <<<"$details" ||
    printf '%s が Developer ID Application で署名されていません\n' "$name"
  if [[ -n "$team" ]]; then
    grep -q "^TeamIdentifier=$team\$" <<<"$details" ||
      printf '%s のチーム ID が %s ではありません\n' "$name" "$team"
  fi
  grep -q '^Timestamp=' <<<"$details" ||
    printf '%s にセキュアタイムスタンプがありません（--timestamp）\n' "$name"
  if [[ "$require_runtime" == 1 ]]; then
    grep -q 'flags=0x[0-9a-f]*(.*runtime' <<<"$details" ||
      printf '%s で hardened runtime が有効になっていません\n' "$name"
  fi
  return 0
}

# コミットしていない変更（git status --porcelain）。--notes のファイルがリポジトリの中にあれば、それだけは数えない
# （アプリには入らないので、リリースの後でタグと一緒にコミットすればよい）
uncommitted_changes() {
  local root="$1" notes="$2" root_real notes_real
  local pathspecs=(":(top)")
  if [[ -n "$notes" && -f "$notes" ]]; then
    root_real="$(cd "$root" && pwd -P)"
    notes_real="$(cd "$(dirname "$notes")" && pwd -P)/$(basename "$notes")"
    if [[ "$notes_real" == "$root_real"/* ]]; then
      pathspecs+=(":(exclude,literal)${notes_real#"$root_real"/}")
    fi
  fi
  git -C "$root" status --porcelain -- "${pathspecs[@]}" 2>/dev/null || true
}

parse_args() {
  DRY_RUN=0
  FIRST_RELEASE=0
  FORCE_LOCAL_APPCAST=0
  ALLOW_DIRTY=0
  NOTES=""
  VERSION=""
  BUILD=""
  local positional=() arg
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      --dry-run) DRY_RUN=1 ;;
      --first-release) FIRST_RELEASE=1 ;;
      --force-local-appcast) FORCE_LOCAL_APPCAST=1 ;;
      --allow-dirty) ALLOW_DIRTY=1 ;;
      --notes)
        [[ $# -ge 2 && -n "$2" ]] || usage_error "--notes にはファイルを指定してください"
        NOTES="$2"
        shift
        ;;
      --notes=*) NOTES="${1#--notes=}" ;;
      --)
        shift
        for arg in "$@"; do positional+=("$arg"); done
        break
        ;;
      -*) usage_error "知らないオプションです: $1" ;;
      *) positional+=("$1") ;;
    esac
    shift
  done

  [[ ${#positional[@]} -eq 2 ]] || usage_error "バージョンとビルド番号を指定してください（例: scripts/release.sh 1.2.0 42）"
  VERSION="${positional[0]}"
  BUILD="${positional[1]}"
  is_valid_version "$VERSION" || usage_error "バージョンは 1.2 か 1.2.3 の形にしてください: $VERSION"
  is_valid_build "$BUILD" || usage_error "ビルド番号は 1 以上の整数にしてください: $BUILD"
}

# 時間のかかる作業の前に、足りないものをまとめて知らせる
preflight() {
  local problems="" missing line dirty
  local tools=(xcodegen xcodebuild xcrun codesign spctl hdiutil security ditto plutil curl file)

  missing="$(missing_commands "${tools[@]}")"
  [[ -z "$missing" ]] || problems+="必要なコマンドがありません: $(printf '%s' "$missing" | tr '\n' ' ')（XcodeGen は brew install xcodegen）"$'\n'

  TEAM="$(project_team_id "$ROOT/project.yml")"
  if [[ -z "$TEAM" ]]; then
    problems+="project.yml に DEVELOPMENT_TEAM がありません"$'\n'
  elif [[ -z "$missing" ]]; then
    IDENTITY="$(developer_id_identity "$TEAM")"
    [[ -n "$IDENTITY" ]] || problems+="チーム $TEAM の有効な Developer ID Application 証明書がキーチェーンにありません（docs/release.md「Developer ID 証明書」）"$'\n'
  fi

  if [[ -z "$missing" ]]; then
    line="$(foundation_models_problem)"
    [[ -z "$line" ]] || problems+="$line"$'\n'
  fi

  line="$(trial_keychain_problem "$ROOT")"
  [[ -z "$line" ]] || problems+="$line"$'\n'

  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      problems+="Config/Nonet.xcconfig: $line"$'\n'
    fi
  done < <(config_problems "$ROOT/Config/Nonet.xcconfig")

  if [[ -n "$NOTES" ]]; then
    if [[ ! -f "$NOTES" ]]; then
      problems+="リリースノートがありません: $NOTES"$'\n'
    else
      case "$NOTES" in
        *.html | *.md | *.txt) ;;
        *) problems+="リリースノートは .html / .md / .txt にしてください: $NOTES"$'\n' ;;
      esac
    fi
  fi

  if [[ "$DRY_RUN" == 0 ]]; then
    if [[ -z "${NONET_NOTARY_PROFILE:-}" ]]; then
      problems+="NONET_NOTARY_PROFILE が設定されていません（notarytool のキーチェーンのプロファイル名。docs/release.md「公証の準備」）"$'\n'
    elif [[ -z "$missing" ]] && ! xcrun notarytool history --keychain-profile "$NONET_NOTARY_PROFILE" >/dev/null 2>&1; then
      problems+="notarytool のプロファイル「$NONET_NOTARY_PROFILE」で認証できません（ネットワークを確かめるか、xcrun notarytool store-credentials で保存し直してください）"$'\n'
    fi
  fi

  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    dirty="$(uncommitted_changes "$ROOT" "$NOTES")"
    if [[ -n "$dirty" ]]; then
      if [[ "$DRY_RUN" == 1 || "$ALLOW_DIRTY" == 1 ]]; then
        warn "コミットしていない変更があります"
      else
        problems+="コミットしていない変更があります。コミットしてから出すか、--allow-dirty を付けてください"$'\n'
      fi
    fi
  fi

  if [[ -n "$problems" ]]; then
    error "リリースの準備が足りません:"
    sed 's/^/  - /' <<<"${problems%$'\n'}" >&2
    exit 1
  fi
}

# 失敗したらログの末尾を見せる。xcodebuild の出力は長いのでファイルに残す
run_logged() {
  local log="$1"
  shift
  if ! "$@" >"$log" 2>&1; then
    tail -n 40 "$log" >&2
    die "「$CURRENT_STEP」に失敗しました。ログの全体: $log"
  fi
}

# SPARKLE_BIN に Sparkle のツール（generate_appcast・generate_keys）のフォルダを入れる。
# die がサブシェルの中で終わらないよう、$( ) では呼ばない
find_sparkle_bin() {
  local tool
  tool="$(find "$1/SourcePackages/artifacts" -type f -name generate_appcast -perm -100 2>/dev/null | head -n 1 || true)"
  [[ -n "$tool" ]] || die "Sparkle の generate_appcast が $1/SourcePackages/artifacts にありません（パッケージの解決に失敗した可能性があります）"
  SPARKLE_BIN="$(dirname "$tool")"
}

# 解決した Sparkle の版（Package.resolved）。分からなければ空文字
sparkle_resolved_version() {
  local resolved="$1/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  [[ -f "$resolved" ]] || return 0
  grep -A 6 '"identity" *: *"sparkle"' "$resolved" | sed -nE 's/.*"version" *: *"([^"]+)".*/\1/p' | head -n 1 || true
}

check_sparkle_key() {
  local bin="$1" expected="$2" actual
  actual="$("$bin/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null | tail -n 1 || true)"
  actual="$(trim "$actual")"
  [[ -n "$actual" ]] || die "Sparkle の秘密鍵がキーチェーンにありません（アカウント: $SPARKLE_ACCOUNT）。docs/release.md「Sparkle の鍵」で作るか、書き出した鍵を generate_keys -f で取り込んでください"
  [[ "$actual" == "$expected" ]] ||
    die "キーチェーンの Sparkle の鍵（公開鍵 $actual）が NONET_SPARKLE_PUBLIC_KEY と違います。このまま出すと、利用者がアップデートを受け取れなくなります"
}

# 公開中の appcast を取ってきて（作業用フォルダの published-appcast.xml）、手元の appcast.xml とビルドの番号で比べる。
# - 手元に無ければ、公開中のものを使う
# - 公開中のものにあって手元に無いビルドがあれば止まる。別の Mac やバックアップの古い appcast から作ると、
#   公開中の項目が消えたり、公開済みと同じビルド番号を出したりしてしまう
# - 手元のものの方がビルドが多いだけなら、警告して手元のものを使う（前のリリースの appcast をまだアップロードしていない・
#   CDN がアップロードの前の appcast をまだ返している。どちらも手元のものが新しい）
# - ビルドが同じで中身が違えば、空白の違いだけなら手元のものを使い、それ以外（公開中のものをサーバーで直したなど）は止まる
# --force-local-appcast なら、手元にあるときは取ってこない。
# 公開中のものを取れないまま新しく作ると、過去の項目が消えた appcast で公開中のものを上書きしてしまう。
# そのため新しく作るのは「404・410（まだ無い）かつ --first-release」のときだけで、403・503 などでは止まる
# （dry run では何も公開しないので、取れなければ警告して続ける）
fetch_published_appcast() {
  local dest="$1" url="$2" first_release="$3" force_local="$4" dry_run="${5:-0}" code="" status=0 retry
  local download="$WORK/published-appcast.xml" missing extra
  if [[ -f "$dest" && "$force_local" == 1 ]]; then
    warn "--force-local-appcast: 公開中の appcast と比べずに、手元の $dest を使います"
    return 0
  fi
  retry="ネットワークやサーバーを確かめてからやり直すか、公開中の appcast を $dest に置いて --force-local-appcast を付けてください"
  # -f は 400 以上をすべて同じ終了コード（22）にするので使わず、状態コードを受け取る。
  # curl の失敗は exit で返す（set -E の ERR トラップがコマンド置換の中で鳴らないように）
  rm -f "$download"
  code="$(curl -sSL --max-time 30 -o "$download" -w '%{http_code}' "$url" || exit $?)" || status=$?
  if [[ "$status" != 0 ]]; then
    rm -f "$download"
    published_appcast_unavailable "$dry_run" "公開中の appcast を取得できませんでした（curl の終了コード $status）: $url" "$retry"
    return 0
  fi
  case "$code" in
    200)
      if ! is_appcast_file "$download"; then
        rm -f "$download"
        die "公開中の appcast の中身が appcast（RSS）ではありません: $url
    サーバーが、無いファイルにも 200 で別のページ（index.html など）を返していないか確かめてください"
      fi
      if [[ ! -f "$dest" ]]; then
        cp "$download" "$dest"
        info "公開中の appcast を取り込みました: $url"
      elif cmp -s "$download" "$dest"; then
        info "手元の appcast は公開中のものと同じです: $url"
      else
        missing="$(appcast_builds_missing "$download" "$dest")"
        extra="$(appcast_builds_missing "$dest" "$download")"
        if [[ -n "$missing" ]]; then
          die "手元の appcast に、公開中のビルド $missing がありません: $dest
    手元のものが古い（別の Mac やバックアップから戻した）なら、手元の appcast.xml を消すと公開中のものを取ってきます。
    取ってきた公開中の appcast: $download
    手元のものが正しいと分かっているときだけ --force-local-appcast を付けてください"
        elif [[ -n "$extra" ]]; then
          warn "手元の appcast には、公開中のものに無いビルド $extra があります。手元のものを使います（$url）
    前のリリースの appcast.xml をまだアップロードしていないなら、今回のものと一緒に、そのビルドの DMG もアップロードしてください。
    アップロードしたばかりなら、CDN などが前の appcast をまだ返しているだけです"
        elif same_ignoring_whitespace "$download" "$dest"; then
          info "手元の appcast は公開中のものと同じです（空白の違いだけ）: $url"
        else
          die "手元の appcast と公開中のものは、同じビルドの項目の中身が違います: $dest
    取ってきた公開中の appcast: $download
    公開中のものをサーバーで直したなら、手元の appcast.xml を消すと公開中のものを取ってきます。
    手元のものが正しいと分かっているときだけ --force-local-appcast を付けてください"
        fi
      fi
      ;;
    404 | 410)
      rm -f "$download"
      [[ "$first_release" == 1 ]] || die "公開中の appcast が見つかりません（HTTP $code）: $url
    初めてのリリースなら --first-release を付けてください。
    公開済みなら、NONET_APPCAST_URL が公開中の URL と同じかを確かめるか、公開中の appcast を $dest に置き、--force-local-appcast を付けてやり直してください
    （このまま新しく作ると、過去の版の項目が消えた appcast になり、利用者にアップデートが届かなくなります）"
      if [[ -f "$dest" ]]; then
        info "公開中の appcast はまだありません（HTTP $code）。手元の appcast を引き継ぎます"
      else
        info "公開中の appcast はまだありません（HTTP $code）。初めてのリリースとして新しく作ります"
      fi
      ;;
    *)
      rm -f "$download"
      published_appcast_unavailable "$dry_run" "公開中の appcast を取得できませんでした（HTTP ${code:-不明}）: $url" "$retry"
      ;;
  esac
}

# 公開中の appcast を取れなかった。本番では止まり、dry run では警告して、手元のもの（無ければ新しい appcast）で続ける
published_appcast_unavailable() {
  local dry_run="$1" problem="$2" advice="$3"
  if [[ "$dry_run" == 1 ]]; then
    warn "$problem
    dry run なので、公開中のものと比べずに続けます（本番ではここで止まります）"
    return 0
  fi
  die "$problem
    $advice"
}

write_export_options() {
  cat >"$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>$TEAM</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
EOF
}

# 書き出した .app が、署名・版・販売用の値のすべてで正しいか
verify_app() {
  local app="$1" plist="$1/Contents/Info.plist" problems="" file key expected actual
  codesign --verify --deep --strict --verbose=2 "$app" >/dev/null 2>"$WORK/codesign-verify.log" || {
    cat "$WORK/codesign-verify.log" >&2
    die "codesign --verify に失敗しました"
  }

  problems+="$(signature_problems "$app" "$TEAM" 1)"$'\n'
  # Sparkle の XPC サービスや Autoupdate など、中の実行ファイルも Developer ID とタイムスタンプが無いと公証が通らない
  while IFS= read -r -d '' file; do
    file -b "$file" | grep -q 'Mach-O' || continue
    problems+="$(signature_problems "$file" "" 0)"$'\n'
  done < <(find "$app/Contents/Frameworks" "$app/Contents/PlugIns" "$app/Contents/Library" -type f -perm -100 -print0 2>/dev/null)

  for key in CFBundleShortVersionString:"$VERSION" CFBundleVersion:"$BUILD" \
    SUFeedURL:"$APPCAST_URL" SUPublicEDKey:"$SPARKLE_PUBLIC_KEY" \
    NonetPurchaseURL:"$PURCHASE_URL" NonetLicensePublicKey:"$LICENSE_PUBLIC_KEY"; do
    expected="${key#*:}"
    key="${key%%:*}"
    actual="$(plist_value "$plist" "$key")"
    [[ "$actual" == "$expected" ]] || problems+="Info.plist の $key が「$actual」です（期待: $expected）"$'\n'
  done

  problems="$(sed '/^$/d' <<<"$problems")"
  if [[ -n "$problems" ]]; then
    error "書き出したアプリに問題があります:"
    sed 's/^/  - /' <<<"$problems" >&2
    exit 1
  fi
  info "署名・版・販売用の値を確かめました"
}

# 公証に出して結果を待つ。通らなければログを見せて止まる
notarize() {
  local file="$1" result status id
  result="$WORK/notary-$(basename "$file").plist"
  info "公証に出しています: $(basename "$file")（数分から数十分かかります）"
  xcrun notarytool submit "$file" \
    --keychain-profile "$NONET_NOTARY_PROFILE" \
    --wait --timeout "$NOTARY_TIMEOUT" \
    --output-format plist >"$result" 2>"$result.err" || true
  status="$(plist_value "$result" status)"
  id="$(plist_value "$result" id)"
  if [[ "$status" != "Accepted" ]]; then
    cat "$result.err" >&2 2>/dev/null || true
    if [[ -n "$id" ]]; then
      error "公証のログ（ID: $id）:"
      xcrun notarytool log "$id" --keychain-profile "$NONET_NOTARY_PROFILE" >&2 || true
    fi
    die "公証が通りませんでした（状態: ${status:-不明}）: $(basename "$file")"
  fi
  info "公証が通りました（ID: $id）"
}

staple() {
  xcrun stapler staple "$1" >/dev/null || die "ステープルに失敗しました: $1"
  xcrun stapler validate "$1" >/dev/null || die "ステープルの確認に失敗しました: $1"
}

# Gatekeeper の評価。公証の前は rejected になるのが正常なので、--dry-run では知らせるだけ。
# type は execute（.app）か open（DMG）
assess() {
  local path="$1" type="$2" log status=0
  log="$WORK/spctl-$(basename "$path").log"
  if [[ "$type" == open ]]; then
    spctl -a -vv -t open --context context:primary-signature "$path" >"$log" 2>&1 || status=$?
  else
    spctl -a -vv -t execute "$path" >"$log" 2>&1 || status=$?
  fi
  sed 's/^/    /' "$log" >&2
  if [[ "$status" != 0 ]]; then
    if [[ "$DRY_RUN" == 1 ]]; then
      info "公証していないので rejected になります（--dry-run では正常）"
    else
      die "Gatekeeper の評価（spctl）に失敗しました: $path"
    fi
  fi
}

make_dmg() {
  local app="$1" dmg="$2" staging="$WORK/dmg"
  rm -rf "$staging" "$dmg"
  mkdir -p "$staging"
  ditto "$app" "$staging/Nonet.app"
  ln -s /Applications "$staging/Applications"
  run_logged "$WORK/hdiutil.log" hdiutil create -volname "Nonet" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg"
  run_logged "$WORK/hdiutil-verify.log" hdiutil verify "$dmg"
  codesign --force --sign "$IDENTITY" --timestamp "$dmg" || die "DMG の署名に失敗しました"
  codesign --verify --strict --verbose=2 "$dmg" >/dev/null 2>&1 || die "DMG の署名の確認に失敗しました"
}

main() {
  set -E
  trap 'error "予期しないエラーで止まりました（release.sh $LINENO 行目、ステップ: ${CURRENT_STEP:-準備}）"' ERR

  parse_args "$@"

  WORK="$ROOT/build/release/$VERSION"
  DERIVED="$ROOT/build/DerivedData"
  RELEASES_DIR="${NONET_RELEASES_DIR:-$ROOT/build/releases}"
  SPARKLE_ACCOUNT="${NONET_SPARKLE_KEY_ACCOUNT:-ed25519}"
  NOTARY_TIMEOUT="${NONET_NOTARY_TIMEOUT:-1h}"
  TEAM=""
  IDENTITY=""
  SPARKLE_BIN=""

  local mode=""
  [[ "$DRY_RUN" == 0 ]] || mode="、dry run"
  step "準備を確かめる（Nonet $VERSION、ビルド $BUILD$mode）"
  preflight
  local config="$ROOT/Config/Nonet.xcconfig"
  APPCAST_URL="$(xcconfig_value "$config" NONET_APPCAST_URL)"
  PURCHASE_URL="$(xcconfig_value "$config" NONET_PURCHASE_URL)"
  SPARKLE_PUBLIC_KEY="$(xcconfig_value "$config" NONET_SPARKLE_PUBLIC_KEY)"
  LICENSE_PUBLIC_KEY="$(xcconfig_value "$config" NONET_LICENSE_PUBLIC_KEY)"
  info "チーム: $TEAM / 署名: Developer ID Application（$IDENTITY）"

  local appcast_dir
  if [[ "$DRY_RUN" == 1 ]]; then
    appcast_dir="$WORK/appcast-preview"
  else
    appcast_dir="$RELEASES_DIR"
  fi
  rm -rf "$WORK"
  mkdir -p "$WORK" "$appcast_dir"
  if [[ "$DRY_RUN" == 1 && -f "$RELEASES_DIR/appcast.xml" ]]; then
    cp "$RELEASES_DIR/appcast.xml" "$appcast_dir/appcast.xml"
  fi

  step "Xcode プロジェクトを作り、パッケージを解決する"
  run_logged "$WORK/xcodegen.log" xcodegen generate --spec "$ROOT/project.yml"
  run_logged "$WORK/resolve.log" xcodebuild -resolvePackageDependencies \
    -project "$ROOT/Nonet.xcodeproj" -scheme Nonet -derivedDataPath "$DERIVED"
  find_sparkle_bin "$DERIVED"
  local sparkle_version
  sparkle_version="$(sparkle_resolved_version "$ROOT/Nonet.xcodeproj")"
  [[ -z "$sparkle_version" ]] || info "Sparkle $sparkle_version（project.yml の exactVersion で固定）"

  step "Sparkle の鍵とビルド番号を確かめる"
  check_sparkle_key "$SPARKLE_BIN" "$SPARKLE_PUBLIC_KEY"
  fetch_published_appcast "$appcast_dir/appcast.xml" "$APPCAST_URL" "$FIRST_RELEASE" "$FORCE_LOCAL_APPCAST" "$DRY_RUN"
  local latest
  latest="$(appcast_latest_build "$appcast_dir/appcast.xml")"
  if [[ -n "$latest" && "$BUILD" -le "$latest" ]]; then
    die "ビルド番号 $BUILD は、appcast に載っている最大の $latest より大きくしてください（Sparkle はビルド番号で新旧を比べます）。
    公開していない試しの項目なら、$appcast_dir/appcast.xml から消してください"
  fi
  if [[ "$FIRST_RELEASE" == 1 && -n "$latest" ]]; then
    warn "--first-release を付けていますが、appcast にはすでにビルド $latest までの項目があります（項目はそのまま引き継ぎます）"
  fi
  info "Sparkle の鍵は一致しています。appcast の最新のビルド: ${latest:-なし}"

  step "アーカイブする（Release、Developer ID、hardened runtime）"
  local archive="$WORK/Nonet.xcarchive"
  run_logged "$WORK/archive.log" xcodebuild archive \
    -project "$ROOT/Nonet.xcodeproj" \
    -scheme Nonet \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    -archivePath "$archive" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS=--timestamp

  step "書き出す（developer-id）"
  write_export_options "$WORK/ExportOptions.plist"
  run_logged "$WORK/export.log" xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$WORK/ExportOptions.plist" \
    -exportPath "$WORK/export"
  local app="$WORK/export/Nonet.app"
  [[ -d "$app" ]] || die "書き出しは終わりましたが $app がありません"

  step "署名を確かめる"
  verify_app "$app"

  if [[ "$DRY_RUN" == 0 ]]; then
    step "アプリを公証してステープルする"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$WORK/Nonet.zip"
    notarize "$WORK/Nonet.zip"
    staple "$app"
  else
    step "アプリの公証を飛ばす（dry run）"
  fi
  assess "$app" execute

  step "DMG を作って署名する"
  local dmg="$WORK/Nonet-$VERSION.dmg"
  make_dmg "$app" "$dmg"

  if [[ "$DRY_RUN" == 0 ]]; then
    step "DMG を公証してステープルする"
    notarize "$dmg"
    staple "$dmg"
  else
    step "DMG の公証を飛ばす（dry run）"
  fi
  assess "$dmg" open

  step "appcast を更新する（Sparkle generate_appcast）"
  cp -f "$dmg" "$appcast_dir/"
  if [[ -n "$NOTES" ]]; then
    cp -f "$NOTES" "$appcast_dir/Nonet-$VERSION.${NOTES##*.}"
  fi
  local prefix
  prefix="$(download_url_prefix "$APPCAST_URL" "${NONET_DOWNLOAD_URL_PREFIX:-}")"
  # -o が無いと generate_appcast は SUFeedURL の最後の名前（例: nonet.xml）で読み書きするので、手元の名前を決めておく
  local appcast_args=(--account "$SPARKLE_ACCOUNT" --download-url-prefix "$prefix" -o "$appcast_dir/appcast.xml")
  [[ -z "$NOTES" ]] || appcast_args+=(--embed-release-notes)
  run_logged "$WORK/generate_appcast.log" "$SPARKLE_BIN/generate_appcast" "${appcast_args[@]}" "$appcast_dir"
  grep -q "<sparkle:version>$BUILD</sparkle:version>" "$appcast_dir/appcast.xml" 2>/dev/null ||
    die "appcast.xml にビルド $BUILD の項目がありません。ログ: $WORK/generate_appcast.log"

  step "できました: Nonet $VERSION（ビルド $BUILD）"
  info "DMG:     $appcast_dir/Nonet-$VERSION.dmg"
  info "appcast: $appcast_dir/appcast.xml"
  info "ダウンロードの URL: ${prefix}Nonet-$VERSION.dmg"
  if [[ "$DRY_RUN" == 1 ]]; then
    info "dry run なので公証していません。この DMG は配らないでください"
    return 0
  fi
  local feed_name rename=""
  feed_name="$(url_file_name "$APPCAST_URL")"
  [[ -z "$feed_name" || "$feed_name" == appcast.xml ]] || rename="（ファイル名を $feed_name にする）"
  info "次にやること（docs/release.md「リリースごとの手順」）:"
  info "  1. scripts/publish.sh $VERSION（DMG・新しい *.delta・最後に appcast.xml の順に上げて、公開中のものを確かめる。docs/hosting.md）"
  info "     ほかの場所に置くなら: Nonet-$VERSION.dmg と新しい *.delta を $prefix に、そのあと appcast.xml を $APPCAST_URL に$rename"
  info "  2. git tag -a v$VERSION -m \"Nonet $VERSION\" && git push origin v$VERSION"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

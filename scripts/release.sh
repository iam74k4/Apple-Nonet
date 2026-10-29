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
  --notes <ファイル>  リリースノート（.html / .md / .txt）。appcast に埋め込まれる
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
  local file="$1" key value
  if [[ ! -f "$file" ]]; then
    printf '%s がありません\n' "$file"
    return 0
  fi
  for key in NONET_APPCAST_URL NONET_PURCHASE_URL; do
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
    if [[ -z "$value" ]]; then
      printf '%s が空です\n' "$key"
    elif ! is_ed25519_public_key "$value"; then
      printf '%s が Ed25519 の公開鍵（base64 で 44 文字）になっていません\n' "$key"
    fi
  done
}

# appcast に載っている最大のビルド番号（sparkle:version）。無ければ空文字
appcast_latest_build() {
  [[ -f "$1" ]] || return 0
  grep -oE '<sparkle:version>[0-9]+</sparkle:version>|sparkle:version="[0-9]+"' "$1" |
    grep -oE '[0-9]+' |
    sort -n |
    tail -n 1 || true
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

parse_args() {
  DRY_RUN=0
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
    dirty="$(git -C "$ROOT" status --porcelain 2>/dev/null || true)"
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

check_sparkle_key() {
  local bin="$1" expected="$2" actual
  actual="$("$bin/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null | tail -n 1 || true)"
  actual="$(trim "$actual")"
  [[ -n "$actual" ]] || die "Sparkle の秘密鍵がキーチェーンにありません（アカウント: $SPARKLE_ACCOUNT）。docs/release.md「Sparkle の鍵」で作るか、書き出した鍵を generate_keys -f で取り込んでください"
  [[ "$actual" == "$expected" ]] ||
    die "キーチェーンの Sparkle の鍵（公開鍵 $actual）が NONET_SPARKLE_PUBLIC_KEY と違います。このまま出すと、利用者がアップデートを受け取れなくなります"
}

# appcast.xml が手元に無ければ、公開中のものを取ってくる。404 なら初めてのリリースとして新しく作る
fetch_published_appcast() {
  local dest="$1" url="$2" status=0
  [[ ! -f "$dest" ]] || return 0
  curl -fsSL --max-time 30 -o "$dest.download" "$url" || status=$?
  if [[ "$status" == 0 ]]; then
    mv "$dest.download" "$dest"
    info "公開中の appcast を取り込みました: $url"
  elif [[ "$status" == 22 ]]; then
    rm -f "$dest.download"
    info "公開中の appcast はまだありません。新しく作ります（初めてのリリースなら正常）"
  else
    rm -f "$dest.download"
    die "公開中の appcast を取得できませんでした（curl の終了コード $status）: $url
    ネットワークを確かめるか、公開中の appcast.xml を $(dirname "$dest") に置いてからやり直してください"
  fi
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

  step "Sparkle の鍵とビルド番号を確かめる"
  check_sparkle_key "$SPARKLE_BIN" "$SPARKLE_PUBLIC_KEY"
  fetch_published_appcast "$appcast_dir/appcast.xml" "$APPCAST_URL"
  local latest
  latest="$(appcast_latest_build "$appcast_dir/appcast.xml")"
  if [[ -n "$latest" && "$BUILD" -le "$latest" ]]; then
    die "ビルド番号 $BUILD は、appcast に載っている最大の $latest より大きくしてください（Sparkle はビルド番号で新旧を比べます）。
    公開していない試しの項目なら、$appcast_dir/appcast.xml から消してください"
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
  local appcast_args=(--account "$SPARKLE_ACCOUNT" --download-url-prefix "$prefix")
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
  info "次にやること（docs/release.md「リリースごとの手順」）:"
  info "  1. Nonet-$VERSION.dmg と新しい *.delta を $prefix にアップロード"
  info "  2. そのあと appcast.xml を $APPCAST_URL にアップロード"
  info "  3. git tag -a v$VERSION -m \"Nonet $VERSION\" && git push origin v$VERSION"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

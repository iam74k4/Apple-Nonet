#!/bin/bash
# scripts/release.sh が作ったリリースを1つ、https://nonet.astlog.dev に公開する
# （Cloudflare R2 のバケット nonet-updates に、固定した wrangler の r2 object put --remote で上げる）。
# 順番は DMG → その版のデルタ → 最後に appcast.xml。使い方は --help、置き場所と最初の準備は docs/hosting.md。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# 公開の場所。cloudflare/wrangler.toml（routes と bucket_name）と cloudflare/src/http.js（UPDATES_PREFIX）に合わせる
# （食い違えば scripts/tests/publish_test.sh が失敗する）
SITE_ORIGIN="https://nonet.astlog.dev"
UPDATES_PREFIX="$SITE_ORIGIN/updates/"
APPCAST_URL="${UPDATES_PREFIX}appcast.xml"
DOWNLOAD_URL="$SITE_ORIGIN/download"
BUCKET="nonet-updates"

CLOUDFLARE_DIR="$ROOT/cloudflare"
WRANGLER="$CLOUDFLARE_DIR/node_modules/.bin/wrangler"
APPCAST_INFO="$CLOUDFLARE_DIR/scripts/appcast-info.js"

# R2 に付ける Content-Type。Worker（cloudflare/src/updates.js）が返すものと同じ。wrangler は拡張子から推さない
DMG_TYPE="application/x-apple-diskimage"
DELTA_TYPE="application/octet-stream"
APPCAST_TYPE="application/xml; charset=utf-8"
# wrangler r2 object put が1回で上げられる大きさの上限（wrangler 4.133.0 の MAX_UPLOAD_SIZE_BYTES）
MAX_UPLOAD_BYTES=$((300 * 1024 * 1024))

usage() {
  cat <<'EOF'
使い方: scripts/publish.sh [オプション] <バージョン>

scripts/release.sh が NONET_RELEASES_DIR に作ったリリースを https://nonet.astlog.dev に公開する。
置く先は Cloudflare R2 のバケット nonet-updates（wrangler r2 object put --remote）。

  <バージョン>  release.sh に渡したバージョン。例: 1.2.0

上げる順番（appcast が先に出ると、まだ無い DMG を指してしまうため）:
  1. Nonet-<バージョン>.dmg
  2. appcast のその版の項目にあるデルタ（*.delta）のうち、同じ中身がまだ上がっていないもの
  3. appcast.xml
上げる前に、公開中の appcast.xml を NONET_RELEASES_DIR/appcast-history/ に控える（戻すときに上げ直す）。

上げる前に確かめること:
  - DMG と appcast.xml があり、appcast.xml を Worker（/download）と同じ読み方で読めること
  - DMG の署名（codesign --verify）・公証のステープル（xcrun stapler validate）・Gatekeeper の評価
    （spctl -a -t open --context context:primary-signature）が通ること。通らない DMG は上げない
  - appcast.xml のその版の項目（DMG とデルタ）に sparkle:edSignature があること。署名の無い更新を Sparkle は受け付けない
  - appcast.xml にその版の項目があり、URL が https://nonet.astlog.dev/updates/Nonet-<バージョン>.dmg、
    length が DMG の大きさと同じで、既定のチャンネルで最新であること（/download の行き先になる）
  - 項目にあるデルタが手元にあり、大きさが合うこと
  - Config/Nonet.xcconfig の NONET_APPCAST_URL が https://nonet.astlog.dev/updates/appcast.xml であること
  - 公開中の appcast が手元のものより新しくないこと。公開中の版のファイルを別の中身で差し替えないこと
上げた後に確かめること:
  - 公開中の appcast（写しを使わずに取る）にその版があること
  - DMG の URL が 200 で、Content-Length が DMG の大きさと同じこと
  - /download がその DMG へリダイレクトすること

オプション:
  --dry-run   確かめて、上げるものとコマンドを表示するだけ。何も上げない
  -h, --help  この説明を表示する

環境変数:
  NONET_RELEASES_DIR    release.sh が DMG・デルタ・appcast.xml を置いたフォルダ（既定: build/releases）
  CLOUDFLARE_API_TOKEN  Cloudflare の API トークン。無ければ wrangler login のログインを使う

先に cloudflare/ で npm ci を実行しておく（package.json で固定した wrangler を使う）。
EOF
}

usage_error() {
  error "$1"
  printf '詳しくは scripts/publish.sh --help\n' >&2
  exit 2
}

# release.sh と同じ「1.2」か「1.2.3」
is_valid_version() {
  local re='^[0-9]+\.[0-9]+(\.[0-9]+)?$'
  [[ "$1" =~ $re ]]
}

parse_args() {
  DRY_RUN=0
  VERSION=""
  local positional=() arg
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      --dry-run) DRY_RUN=1 ;;
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
  [[ ${#positional[@]} -eq 1 ]] || usage_error "公開するバージョンを1つ指定してください（例: scripts/publish.sh 1.2.0）"
  VERSION="${positional[0]}"
  is_valid_version "$VERSION" || usage_error "バージョンは 1.2 か 1.2.3 の形にしてください: $VERSION"
}

file_size() {
  wc -c <"$1" | tr -d '[:space:]'
}

# R2 の ETag は、1回の PUT で上げたものなら中身の MD5（16 進）
file_md5() {
  if command -v md5 >/dev/null 2>&1; then
    md5 -q "$1"
  else
    md5sum "$1" | cut -d ' ' -f 1
  fi
}

# appcast-info.js の要約（タブ区切り）から、1 列目が kind の行を出す。列と値を渡せば、その列がその値の行だけ
rows() {
  local summary="$1" kind="$2" column="${3:-0}" value="${4:-}"
  awk -F'\t' -v kind="$kind" -v column="$column" -v value="$value" \
    '$1 == kind && (column == 0 || $column == value)' "$summary"
}

# 1 行目の、ある列の値
first_column() {
  awk -F'\t' -v column="$1" 'NR == 1 { print $column }'
}

# 項目（item）のビルド番号のうち最大のもの。無ければ 0
max_build() {
  rows "$1" item | awk -F'\t' '$2 ~ /^[0-9]+$/ && $2 + 0 > max { max = $2 + 0 } END { print max + 0 }'
}

# appcast を Worker の /download と同じパーサーで読み、要約を out に書く。読めなければ、理由と hint を出して止まる
summarize_appcast() {
  local file="$1" out="$2" label="$3" hint="$4"
  if ! node "$APPCAST_INFO" "$file" >"$out" 2>"$out.err"; then
    die "$label を読めません: $(cat "$out.err")
    $hint"
  fi
}

# ヘッダのファイル（curl -D）から、名前（小文字）の値を出す。何度もあれば最後のもの
header_value() {
  tr -d '\r' <"$1" | awk -v name="$2" '
    {
      i = index($0, ":")
      if (i > 1 && tolower(substr($0, 1, i - 1)) == name) {
        value = substr($0, i + 1)
        sub(/^[ \t]+/, "", value)
        sub(/[ \t]+$/, "", value)
        found = value
      }
    }
    END { print found }'
}

# 公開中の URL を GET する。途中の写し（キャッシュ）を使わせないよう Cache-Control: no-cache を付け、
# リダイレクトはたどらない。状態コードを CODE、本文を dest に入れる。つながらなければ止まる
http_get() {
  local url="$1" dest="$2" status=0
  CODE="$(curl -sS --max-time 60 -H 'Cache-Control: no-cache' -D "$WORK/headers" -o "$dest" -w '%{http_code}' "$url")" || status=$?
  [[ "$status" == 0 ]] || die "$url に届きません（curl の終了コード $status）。
    ネットワークと、Worker を出してあるか（docs/hosting.md「最初のデプロイ」）を確かめてください"
}

# 公開中の URL に HEAD を送る。CODE・LENGTH（Content-Length）・ETAG（引用符を外したもの）・LOCATION に入れる
http_head() {
  local url="$1" status=0
  CODE="$(curl -sS --max-time 60 -I -H 'Cache-Control: no-cache' -D "$WORK/headers" -o /dev/null -w '%{http_code}' "$url")" || status=$?
  [[ "$status" == 0 ]] || die "$url に届きません（curl の終了コード $status）。
    ネットワークと、Worker を出してあるか（docs/hosting.md「最初のデプロイ」）を確かめてください"
  LENGTH="$(header_value "$WORK/headers" content-length)"
  ETAG="$(header_value "$WORK/headers" etag)"
  ETAG="${ETAG#W/}"
  ETAG="${ETAG//\"/}"
  LOCATION="$(header_value "$WORK/headers" location)"
}

# 時間のかかる作業やネットワークの前に、足りないものをまとめて知らせる
preflight() {
  local problems="" missing value
  missing="$(missing_commands curl node awk codesign xcrun spctl)"
  [[ -z "$missing" ]] || problems+="必要なコマンドがありません: $(printf '%s' "$missing" | tr '\n' ' ')（node は Node.js 22 以降）"$'\n'
  if ! command -v md5 >/dev/null 2>&1 && ! command -v md5sum >/dev/null 2>&1; then
    problems+="md5 も md5sum もありません"$'\n'
  fi
  [[ -x "$WRANGLER" ]] ||
    problems+="固定した wrangler（cloudflare/node_modules/.bin/wrangler）がありません。先に cloudflare/ で npm ci を実行してください（cd cloudflare && npm ci）"$'\n'
  [[ -f "$APPCAST_INFO" ]] || problems+="$APPCAST_INFO がありません"$'\n'

  if [[ ! -f "$ROOT/Config/Nonet.xcconfig" ]]; then
    problems+="Config/Nonet.xcconfig がありません"$'\n'
  else
    value="$(xcconfig_value "$ROOT/Config/Nonet.xcconfig" NONET_APPCAST_URL)"
    [[ "$value" == "$APPCAST_URL" ]] ||
      problems+="Config/Nonet.xcconfig の NONET_APPCAST_URL が「$value」です。アプリはそこを見るので、$APPCAST_URL に上げても届きません（NONET_APPCAST_URL = https:/\$()/nonet.astlog.dev/updates/appcast.xml にして、ビルドから出し直す）"$'\n'
  fi

  if [[ ! -d "$RELEASES_DIR" ]]; then
    problems+="リリースのフォルダがありません: $RELEASES_DIR（NONET_RELEASES_DIR）"$'\n'
  else
    [[ -f "$RELEASES_DIR/$DMG_NAME" ]] ||
      problems+="$RELEASES_DIR に $DMG_NAME がありません（scripts/release.sh $VERSION <ビルド番号> で作る）"$'\n'
    [[ -f "$RELEASES_DIR/appcast.xml" ]] ||
      problems+="$RELEASES_DIR に appcast.xml がありません（scripts/release.sh が作る）"$'\n'
  fi

  if [[ -n "$problems" ]]; then
    error "公開の準備が足りません:"
    sed 's/^/  - /' <<<"${problems%$'\n'}" >&2
    exit 1
  fi
  RELEASES_DIR="$(cd "$RELEASES_DIR" && pwd)"
}

# appcast.xml の、url を指す <enclosure …> の開始タグ（複数行に分かれていても1行にして）。無ければ空
appcast_enclosure() {
  tr '\r\n\t' '   ' <"$1" | grep -oE '<enclosure[^>]*>' | grep -F "url=\"$2\"" | head -n 1 || true
}

# DMG とデルタ（DELTA_NAMES）の enclosure に、空でない sparkle:edSignature があるか。無いものを1行ずつ出す。
# 署名の無い更新を Sparkle は受け付けない。署名は generate_appcast が Sparkle の秘密鍵で付ける
appcast_signature_problems() {
  local file="$1" urls=("$DMG_URL") url name tag
  for name in ${DELTA_NAMES[@]+"${DELTA_NAMES[@]}"}; do
    urls+=("$UPDATES_PREFIX$name")
  done
  for url in "${urls[@]}"; do
    tag="$(appcast_enclosure "$file" "$url")"
    if [[ -z "$tag" ]]; then
      printf '%s の enclosure が appcast.xml にありません\n' "$url"
    elif ! grep -qE 'sparkle:edSignature="[^"]+"' <<<"$tag"; then
      printf '%s の enclosure に sparkle:edSignature がありません\n' "$url"
    fi
  done
}

# 手元の appcast.xml の、この版の項目を確かめる。BUILD・DMG_SIZE・DELTA_NAMES を決める
check_local_release() {
  local summary="$WORK/local.tsv" matches count other short default length newest_build newest_url
  local url delta_length name size pattern problems
  summarize_appcast "$RELEASES_DIR/appcast.xml" "$summary" "手元の appcast.xml" \
    "Worker も読めないので、このまま上げると /download が 503 になります。scripts/release.sh が作ったままか確かめてください"

  matches="$(rows "$summary" item 5 "$DMG_URL")"
  count="$(grep -c . <<<"$matches" || true)"
  if [[ "$count" == 0 ]]; then
    other="$(rows "$summary" item 3 "$VERSION" | first_column 5)"
    if [[ -n "$other" ]]; then
      die "手元の appcast.xml の $VERSION の項目は $other を指しています（期待: $DMG_URL）。
    DMG は $UPDATES_PREFIX の下に置きます。NONET_DOWNLOAD_URL_PREFIX を設定せずに scripts/release.sh を動かし直してください"
    fi
    die "手元の appcast.xml に $VERSION（$DMG_URL）の項目がありません。scripts/release.sh $VERSION <ビルド番号> を最後まで通したか確かめてください"
  fi
  [[ "$count" == 1 ]] || die "手元の appcast.xml に $DMG_URL を指す項目が $count 個あります。どれが正しいか分からないので止めます"

  BUILD="$(first_column 2 <<<"$matches")"
  short="$(first_column 3 <<<"$matches")"
  default="$(first_column 4 <<<"$matches")"
  length="$(first_column 6 <<<"$matches")"
  [[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || die "$VERSION の項目のビルド番号（sparkle:version）が整数ではありません: $BUILD"
  [[ "$short" == "$VERSION" ]] || die "$DMG_URL の項目の版（sparkle:shortVersionString）が $short です（期待: $VERSION）"
  [[ "$default" == 1 ]] || die "$VERSION の項目にはチャンネル（sparkle:channel）が付いています。/download が指さない版は、このスクリプトでは公開しません"

  DMG_SIZE="$(file_size "$RELEASES_DIR/$DMG_NAME")"
  [[ "$length" == "$DMG_SIZE" ]] ||
    die "appcast.xml の $VERSION の length（$length バイト）が $DMG_NAME の大きさ（$DMG_SIZE バイト）と違います。
    DMG と appcast が別の回の release.sh のものです。scripts/release.sh をやり直してください"

  newest_build="$(rows "$summary" newest | first_column 2)"
  newest_url="$(rows "$summary" newest | first_column 3)"
  [[ "$newest_url" == "$DMG_URL" ]] ||
    die "手元の appcast.xml で最新（既定のチャンネル）なのはビルド ${newest_build:-なし}（${newest_url:-なし}）で、$VERSION（ビルド $BUILD）ではありません。
    上げても /download は $VERSION を指しません"

  # デルタは Nonet<このビルド>-<古いビルド>.delta（generate_appcast の名前。Worker が配るのもこの形だけ）
  pattern="^Nonet${BUILD}-[1-9][0-9]*\\.delta\$"
  DELTA_NAMES=()
  while IFS=$'\t' read -r _ _ url delta_length _; do
    name="${url#"$UPDATES_PREFIX"}"
    if [[ "$url" != "$UPDATES_PREFIX"* || ! "$name" =~ $pattern ]]; then
      die "$VERSION の項目のデルタの URL が ${UPDATES_PREFIX}Nonet${BUILD}-<ビルド>.delta の形ではありません: $url"
    fi
    [[ -f "$RELEASES_DIR/$name" ]] || die "appcast.xml にあるデルタ $name が $RELEASES_DIR にありません"
    size="$(file_size "$RELEASES_DIR/$name")"
    [[ "$delta_length" == "$size" ]] ||
      die "appcast.xml の $name の length（$delta_length バイト）が、ファイルの大きさ（$size バイト）と違います"
    DELTA_NAMES+=("$name")
  done < <(rows "$summary" delta 2 "$BUILD")

  problems="$(appcast_signature_problems "$RELEASES_DIR/appcast.xml")"
  if [[ -n "$problems" ]]; then
    error "手元の appcast.xml の項目に Sparkle の署名がありません:"
    sed 's/^/  - /' <<<"$problems" >&2
    die "Sparkle は署名の無い更新を受け付けないので、このまま上げると利用者がアップデートできません。
    キーチェーンに Sparkle の秘密鍵があるか（docs/release.md「Sparkle の鍵」）を確かめて、scripts/release.sh をやり直してください"
  fi

  info "ビルド $BUILD / $DMG_NAME $DMG_SIZE バイト / デルタ ${#DELTA_NAMES[@]} 個 / Sparkle の署名あり"
}

# 上げる DMG が、署名・公証のステープル・Gatekeeper の評価のすべてを通るか。通らないものを上げると、利用者の Mac で開けない。
# 通らないものをすべて出してから止まる（dry run でも同じ。ネットワークは使わない）
verify_dmg() {
  local dmg="$RELEASES_DIR/$DMG_NAME" problems="" log="$WORK/dmg-check.log"
  if ! codesign --verify --strict --verbose=2 "$dmg" >"$log" 2>&1; then
    problems+="DMG の署名を確かめられません（codesign --verify）: $(tr '\n' ' ' <"$log")"$'\n'
  fi
  if ! xcrun stapler validate "$dmg" >"$log" 2>&1; then
    problems+="DMG に公証のチケットがステープルされていません（xcrun stapler validate）。--dry-run で作った DMG や、公証の前の DMG ではないか確かめてください: $(tr '\n' ' ' <"$log")"$'\n'
  fi
  if ! spctl -a -t open --context context:primary-signature -v "$dmg" >"$log" 2>&1; then
    problems+="Gatekeeper が DMG を受け付けません（spctl -a -t open）: $(tr '\n' ' ' <"$log")"$'\n'
  fi
  if [[ -n "$problems" ]]; then
    error "DMG に問題があります:"
    sed 's/^/  - /' <<<"${problems%$'\n'}" >&2
    die "$DMG_NAME は上げません。scripts/release.sh を --dry-run なしで最後まで通した DMG か確かめてください"
  fi
  info "$DMG_NAME: 署名・公証のステープル・Gatekeeper の評価を確かめました"
}

# 公開中の appcast と R2 の今の中身を見て、何を上げるかを決める（UPLOAD_NAMES・UPLOAD_TYPES・SKIPPED_NAMES）
check_published() {
  local published_max local_max name
  http_get "$APPCAST_URL" "$WORK/published.xml"
  case "$CODE" in
    200)
      PUBLISHED_EXISTS=1
      summarize_appcast "$WORK/published.xml" "$WORK/published.tsv" "公開中の appcast" \
        "$APPCAST_URL が appcast ではないものを返しています。無いファイルに 200 でページを返す設定（SPA のフォールバック）になっていないか確かめてください（docs/hosting.md）"
      published_max="$(max_build "$WORK/published.tsv")"
      local_max="$(max_build "$WORK/local.tsv")"
      if [[ "$published_max" -gt "$local_max" ]]; then
        die "公開中の appcast にはビルド $published_max まであり、手元の appcast.xml（ビルド $local_max まで）より新しいです。
    このまま上げると、公開中の新しい版の項目が消えます。別の Mac から公開したなら、公開中の appcast を
    $RELEASES_DIR/appcast.xml に置いてから scripts/release.sh をやり直してください"
      fi
      LIVE=0
      [[ -z "$(rows "$WORK/published.tsv" item 2 "$BUILD")" ]] || LIVE=1
      if [[ "$LIVE" == 0 ]]; then
        # 同じ版（か同じ DMG の URL）を別のビルドでもう公開している: 出した版の番号は使い直さない。
        # 上げると公開中の DMG を別の中身で差し替え、その版の項目は appcast から消える
        local reused
        reused="$( { rows "$WORK/published.tsv" item 3 "$VERSION"; rows "$WORK/published.tsv" item 5 "$DMG_URL"; } | first_column 2)"
        [[ -z "$reused" ]] || die "版 $VERSION（$DMG_NAME）はビルド $reused としてもう公開されています。出した版の番号は使い直しません。
    新しい版の番号で scripts/release.sh からやり直してください"
      fi
      if [[ "$LIVE" == 1 ]]; then
        info "公開中の appcast: ビルド $published_max まで（ビルド $BUILD はもう公開されています）"
      else
        info "公開中の appcast: ビルド $published_max まで"
      fi
      ;;
    404)
      LIVE=0
      PUBLISHED_EXISTS=0
      info "公開中の appcast はまだありません（HTTP 404）。初めての公開として進めます"
      ;;
    *)
      die "公開中の appcast を確かめられません（HTTP $CODE）: $APPCAST_URL
    Worker を出してあるか、R2 のバケット $BUCKET があるかを確かめてください（docs/hosting.md）"
      ;;
  esac

  UPLOAD_NAMES=()
  UPLOAD_TYPES=()
  SKIPPED_NAMES=()
  plan_file "$DMG_NAME" "$DMG_TYPE" 0
  for name in ${DELTA_NAMES[@]+"${DELTA_NAMES[@]}"}; do
    plan_file "$name" "$DELTA_TYPE" 1
  done
  # appcast.xml はいつも最後に、いつも上げる
  UPLOAD_NAMES+=(appcast.xml)
  UPLOAD_TYPES+=("$APPCAST_TYPE")
}

# R2 の今の中身（公開中の URL への HEAD の ETag）と手元のファイルを比べ、上げるか飛ばすかを決める。
# skippable が 1 なら、同じ中身がもうあれば飛ばす（デルタ）。DMG はいつも上げ直す
plan_file() {
  local name="$1" type="$2" skippable="$3" file="$RELEASES_DIR/$1" state size
  size="$(file_size "$file")"
  [[ "$size" -le "$MAX_UPLOAD_BYTES" ]] || die "$name は $size バイトで、wrangler r2 object put で上げられる 300 MiB を超えています"
  http_head "$UPDATES_PREFIX$name"
  case "$CODE" in
    200)
      if [[ "$ETAG" == "$(file_md5 "$file")" ]]; then
        state=same
      else
        state=different
      fi
      ;;
    404) state=missing ;;
    *) die "R2 の $name を確かめられません（$UPDATES_PREFIX$name が HTTP $CODE）" ;;
  esac
  if [[ "$LIVE" == 1 && "$state" == different ]]; then
    die "ビルド $BUILD はもう公開されていて、R2 の $name は手元のものと中身が違います。
    公開中の版のファイルを差し替えると、appcast の署名と合わなくなり、利用者がアップデートを受け取れなくなります。
    作り直したなら、新しいビルド番号で scripts/release.sh からやり直してください"
  fi
  if [[ "$skippable" == 1 && "$state" == same ]]; then
    SKIPPED_NAMES+=("$name")
  else
    UPLOAD_NAMES+=("$name")
    UPLOAD_TYPES+=("$type")
  fi
}

print_plan() {
  local i name
  for i in "${!UPLOAD_NAMES[@]}"; do
    name="${UPLOAD_NAMES[$i]}"
    info "$((i + 1)). $name（$(file_size "$RELEASES_DIR/$name") バイト、${UPLOAD_TYPES[$i]}）"
  done
  for name in ${SKIPPED_NAMES[@]+"${SKIPPED_NAMES[@]}"}; do
    info "飛ばす: $name（同じ中身がもう R2 にあります）"
  done
  if [[ "$PUBLISHED_EXISTS" == 1 ]]; then
    info "上げる前に、公開中の appcast.xml を $RELEASES_DIR/appcast-history/ に控えます"
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    info "実行するコマンド（cloudflare/ で）:"
    for i in "${!UPLOAD_NAMES[@]}"; do
      name="${UPLOAD_NAMES[$i]}"
      info "  node_modules/.bin/wrangler r2 object put $BUCKET/$name --file $RELEASES_DIR/$name --content-type '${UPLOAD_TYPES[$i]}' --remote"
    done
  fi
}

# 1つ上げる。失敗したらそこで止まる（appcast.xml より前で止まれば、公開中の版は変わらない）
put_object() {
  local name="$1" type="$2" file="$RELEASES_DIR/$1" log="$WORK/wrangler-$1.log"
  info "$name"
  if ! (cd "$CLOUDFLARE_DIR" && "$WRANGLER" r2 object put "$BUCKET/$name" --file "$file" --content-type "$type" \
    --remote --config "$CLOUDFLARE_DIR/wrangler.toml") >"$log" 2>&1; then
    sed 's/^/    /' "$log" >&2
    if [[ "$name" == appcast.xml ]]; then
      die "appcast.xml のアップロードに失敗しました。DMG とデルタは上がっていますが、公開中の appcast は前のままです。
    原因を直して、同じコマンドでやり直してください"
    fi
    die "$name のアップロードに失敗しました。appcast.xml はまだ上げていないので、公開中の版は変わっていません。
    認証（wrangler login か CLOUDFLARE_API_TOKEN）とバケット $BUCKET を確かめて、同じコマンドでやり直してください"
  fi
}

# 上げたあと、利用者と同じ URL から見えるかを確かめる。違うところをすべて出してから止まる
verify_published() {
  local problems=""
  http_get "$APPCAST_URL" "$WORK/after.xml"
  if [[ "$CODE" != 200 ]]; then
    problems+="公開中の appcast が HTTP $CODE です: $APPCAST_URL"$'\n'
  else
    summarize_appcast "$WORK/after.xml" "$WORK/after.tsv" "上げたあとの公開中の appcast" \
      "$APPCAST_URL を curl で見て、docs/hosting.md「戻す」の手順で前の appcast.xml を上げ直してください"
    if [[ -z "$(rows "$WORK/after.tsv" item 2 "$BUILD" | awk -F'\t' -v url="$DMG_URL" '$5 == url')" ]]; then
      problems+="公開中の appcast にビルド $BUILD（$DMG_URL）がありません: $APPCAST_URL"$'\n'
    else
      info "appcast: ビルド $BUILD があります"
    fi
  fi

  http_head "$DMG_URL"
  if [[ "$CODE" != 200 ]]; then
    problems+="DMG の URL が HTTP $CODE です: $DMG_URL"$'\n'
  elif [[ "$LENGTH" != "$DMG_SIZE" ]]; then
    problems+="DMG の Content-Length が ${LENGTH:-無し} です（期待: $DMG_SIZE）: $DMG_URL"$'\n'
  else
    info "DMG: 200、$LENGTH バイト"
  fi

  http_head "$DOWNLOAD_URL"
  case "$CODE" in
    302 | 303 | 307)
      if [[ "$LOCATION" == "$DMG_URL" ]]; then
        info "/download: $CODE → $LOCATION"
      else
        problems+="/download の行き先が ${LOCATION:-無し} です（期待: $DMG_URL）"$'\n'
      fi
      ;;
    *) problems+="/download が HTTP $CODE です（期待: $DMG_URL への 302）"$'\n' ;;
  esac

  if [[ -n "$problems" ]]; then
    error "上げ終わりましたが、公開された中身が合いません:"
    sed 's/^/  - /' <<<"${problems%$'\n'}" >&2
    die "docs/hosting.md「確かめる」の curl で見てください。直らなければ「戻す」の手順で前の appcast.xml を上げ直します"
  fi
}

main() {
  parse_args "$@"
  RELEASES_DIR="${NONET_RELEASES_DIR:-$ROOT/build/releases}"
  DMG_NAME="Nonet-$VERSION.dmg"
  DMG_URL="$UPDATES_PREFIX$DMG_NAME"
  BUILD=""
  DMG_SIZE=""
  LIVE=0
  PUBLISHED_EXISTS=0
  DELTA_NAMES=()

  local mode=""
  [[ "$DRY_RUN" == 0 ]] || mode="、dry run"
  step "準備を確かめる（Nonet $VERSION$mode）"
  preflight
  # TMPDIR の末尾の / で「//」にならないよう、cd と pwd で正規化する
  WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/nonet-publish.XXXXXX")" && pwd)"
  trap 'rm -rf "$WORK"' EXIT

  step "手元のリリースを確かめる（$RELEASES_DIR）"
  check_local_release

  step "DMG の署名・公証・Gatekeeper を確かめる"
  verify_dmg

  step "公開中のものと比べる（$SITE_ORIGIN）"
  check_published

  step "上げるもの（R2 のバケット $BUCKET、この順番）"
  print_plan
  if [[ "$DRY_RUN" == 1 ]]; then
    step "dry run なので、何も上げずに終わります"
    return 0
  fi

  # 戻すときに上げ直せるよう、いま公開中の appcast を控える。generate_appcast はフォルダの直下の
  # DMG などしか見ないので、appcast-history/ の中は次の release.sh に混ざらない
  local backup
  if [[ "$PUBLISHED_EXISTS" == 1 ]]; then
    step "公開中の appcast.xml を控える"
    backup="$RELEASES_DIR/appcast-history/$(date -u +%Y%m%dT%H%M%SZ)-before-$VERSION.xml"
    mkdir -p "$RELEASES_DIR/appcast-history"
    cp "$WORK/published.xml" "$backup"
    info "$backup（docs/hosting.md「戻す」）"
  fi

  step "アップロードする"
  local i
  for i in "${!UPLOAD_NAMES[@]}"; do
    put_object "${UPLOAD_NAMES[$i]}" "${UPLOAD_TYPES[$i]}"
  done

  step "公開されたかを確かめる"
  verify_published

  step "公開しました: Nonet $VERSION（ビルド $BUILD）"
  info "appcast:   $APPCAST_URL"
  info "DMG:       $DMG_URL"
  info "/download: $DMG_URL へ"
  info "次にやること: docs/release.md「確かめる」（別の Mac で DMG を開く・一つ前の版から Sparkle で更新する）と、タグ（git tag -a v$VERSION）"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

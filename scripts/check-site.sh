#!/bin/bash
# 販売ページ（site/）を確かめる: HTML の基本・リンク切れ・最低限のアクセシビリティ・外部の読み込みが無いこと（購入のページの Paddle.js を除く）・商標の表記・
# canonical と hreflang・フッターから法的な文書（プライバシー・利用規約・特商法）へのリンク・robots.txt と sitemap.xml・共有の画像（og:image）・
# 利用ガイドの目次と見出しのアンカー・アプリの「利用ガイド」「プライバシー」「購入する」の URL（xcconfig）がサイトのページ（と、購入のほかは英語版の en/）を指していること。
# --strict を付けると、TODO（価格・販売サービス・問い合わせ先などの仮の値）が残っているときと、canonical が無くてアプリの URL を確かめられないときも失敗にする。公開の前に使う。
# 使い方: scripts/check-site.sh [--strict] [--config <xcconfig（既定: Config/Nonet.xcconfig）>] [サイトのフォルダ（既定: site）]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

STRICT=0
SITE="$ROOT/site"
CONFIG="$ROOT/Config/Nonet.xcconfig"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --strict) STRICT=1 ;;
    --config)
      [[ $# -ge 2 ]] || die "--config には xcconfig のファイルを指定してください"
      CONFIG="$2"
      shift
      ;;
    -*) die "知らないオプションです: $1" ;;
    *) SITE="$(cd "$1" && pwd)" ;;
  esac
  shift
done
[[ -d "$SITE" ]] || die "サイトのフォルダがありません: $SITE"

PROBLEMS=0

problem() {
  printf '  - %s\n' "$*" >&2
  PROBLEMS=$((PROBLEMS + 1))
}

# 外部（http(s):// か //）を指す値か。srcset のように URL を並べた値も見る。値は小文字にしてから渡す
points_outside() {
  local re='(^|[[:space:],])(https?:)?//'
  [[ "$1" =~ $re ]]
}

# タグの属性の値（引用符は外す）を1行ずつ出す。names は「src|href」のような正規表現
attribute_values() {
  local tag="$1" names="$2" pair value
  while IFS= read -r pair; do
    value="$(trim "${pair#*=}")"
    case "$value" in
      \"*\" | \'*\') value="${value:1:${#value}-2}" ;;
    esac
    printf '%s\n' "$value"
  done < <(LC_ALL=C grep -oE "[[:space:]]($names)[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*'|[^[:space:]\"'>]+)" <<<"$tag" || true)
}

# <link> が、ページを開いただけで読み込まれるか。関係を示すだけの rel（alternate・canonical など）は読み込まない
link_fetches() {
  local rels token tokens=()
  rels="$(attribute_values "$1" rel)"
  read -r -a tokens <<<"$rels" || true
  # rel が無い・空の <link> は、念のため読み込むものとして扱う
  [[ ${#tokens[@]} -gt 0 ]] || return 0
  for token in "${tokens[@]}"; do
    case "$token" in
      alternate | canonical | author | license | me | help | bookmark | next | prev) ;;
      *) return 0 ;;
    esac
  done
  return 1
}

# 外部のスクリプトを読んでよいのは、購入のページの Paddle.js だけ（Paddle の購入画面を開く。site/_headers の CSP も
# この2つのページだけ広げる。プライバシーポリシーの「8. 販売ページ」）。小文字で書く
STORE_SCRIPT="https://cdn.paddle.com/paddle/v2/paddle.js"
STORE_PAGES="buy.html en/buy.html"

# プライバシーの約束（クッキー・解析・外部のフォントを使わず、外部のスクリプトは購入のページの Paddle.js だけ）のため、
# 開いただけで外部に取りに行くものが無いかを見る。改行をまたぐタグ・一重引用符・大文字も見るよう、
# 1 行にまとめて小文字にしてから調べる。<a> のリンクは押すまで読み込まれないので対象外
check_external_markup() {
  local file="$1" rel="$2" flat tag name value kind
  flat="$(LC_ALL=C tr '\n\r\t' '   ' <"$file" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  while IFS= read -r tag; do
    [[ "$tag" == *//* ]] || continue
    name="${tag#<}"
    name="${name%%[[:space:]/>]*}"
    if [[ "$name" == link ]] && ! link_fetches "$tag"; then
      continue
    fi
    case "$name" in
      script) kind="スクリプト" ;;
      link) kind="スタイル・フォント・アイコンなど" ;;
      *) kind="画像や埋め込み" ;;
    esac
    while IFS= read -r value; do
      if points_outside "$value"; then
        if [[ "$name" == script && "$value" == "$STORE_SCRIPT" && " $STORE_PAGES " == *" $rel "* ]]; then
          continue
        fi
        problem "$rel: 外部の${kind}を読み込んでいます（<$name> の ${value}）"
      fi
    done < <(attribute_values "$tag" 'src|href|xlink:href|data|poster|srcset')
  done < <(LC_ALL=C grep -oE '<(script|link|img|iframe|frame|video|audio|source|track|embed|object|input|image|use|feimage)([[:space:]/][^>]*)?>' <<<"$flat" || true)

  # <style> と style 属性の中の CSS
  if LC_ALL=C grep -qE "@import|url\\([[:space:]]*[\"']?(https?:)?//" <<<"$flat"; then
    problem "$rel: 外部のファイルを読み込んでいます（<style> や style 属性の @import・url(https://…)）"
  fi
  return 0
}

# href / src の行き先が存在するか。#id はその id があるか
check_reference() {
  local file="$1" rel="$2" url="$3" path frag="" target
  case "$url" in
    http://* | https://* | mailto:* | tel:* | data:*) return 0 ;;
    "") problem "$rel: 空のリンクがあります" && return 0 ;;
    javascript:*) problem "$rel: javascript: のリンクは使わない（${url}）" && return 0 ;;
  esac
  path="${url%%#*}"
  [[ "$url" != *#* ]] || frag="${url#*#}"
  path="${path%%\?*}"
  if [[ -z "$path" ]]; then
    target="$file"
  else
    target="$(dirname "$file")/$path"
    [[ ! -d "$target" ]] || target="${target%/}/index.html"
    if [[ ! -f "$target" ]]; then
      problem "$rel: リンク先がありません: $url"
      return 0
    fi
  fi
  if [[ -n "$frag" ]] && ! grep -qF "id=\"$frag\"" "$target"; then
    problem "$rel: リンク先の #$frag がありません（${url}）"
  fi
  return 0
}

check_html() {
  local file="$1" rel lang expected_lang count url tag
  rel="${file#"$SITE/"}"

  head -n 1 "$file" | grep -qi '^<!doctype html>$' || problem "$rel: 1 行目が <!doctype html> ではありません"
  lang="$(sed -nE 's/.*<html[^>]* lang="([a-zA-Z-]+)".*/\1/p' "$file" | head -n 1)"
  case "$rel" in
    en/*) expected_lang=en ;;
    *) expected_lang=ja ;;
  esac
  [[ "$lang" == "$expected_lang" ]] || problem "$rel: <html lang> が「${expected_lang}」ではありません（いまは「${lang}」）"
  grep -qi '<meta charset="utf-8">' "$file" || problem "$rel: <meta charset=\"utf-8\"> がありません"
  grep -q '<meta name="viewport" content="width=device-width' "$file" || problem "$rel: viewport の指定がありません"
  grep -qE '<title>[^<]+</title>' "$file" || problem "$rel: <title> がありません"
  grep -qE '<meta name="description" content="[^"]+">' "$file" || problem "$rel: <meta name=\"description\"> がありません"
  grep -q '<main' "$file" || problem "$rel: <main> がありません"
  count="$(grep -oE '<h1[ >]' "$file" | wc -l | tr -d ' ' || true)"
  [[ "$count" == 1 ]] || problem "$rel: <h1> は 1 つにしてください（いまは ${count}）"

  while IFS= read -r tag; do
    [[ "$tag" == *" alt="* ]] || problem "$rel: alt の無い画像があります: $tag"
  done < <(grep -oE '<img [^>]*>' "$file" || true)

  check_external_markup "$file" "$rel"

  while IFS= read -r url; do
    check_reference "$file" "$rel" "$url"
  done < <(grep -oE "(href|src)=(\"[^\"]*\"|'[^']*')" "$file" | sed -E "s/^(href|src)=[\"']//; s/[\"']\$//" || true)

  # 同じ id が2つあると、#id のリンクが前のほうにしか飛ばない
  while IFS= read -r tag; do
    problem "$rel: id が重なっています: $tag"
  done < <(grep -oE '[[:space:]]id="[^"]*"' "$file" | sed -E 's/^[[:space:]]//' | sort | uniq -d || true)

  case "$(basename "$file")" in
    index.html)
      if ! grep -q 'Stream Deck' "$file" || ! grep -q 'Corsair Memory' "$file"; then
        problem "$rel: Stream Deck の商標の表記（Corsair Memory, Inc.）がありません"
      fi
      grep -qE 'href="([^"]*/)?privacy\.html"' "$file" || problem "$rel: プライバシーポリシーへのリンクがありません"
      grep -qE 'href="([^"]*/)?guide\.html"' "$file" || problem "$rel: 利用ガイドへのリンクがありません"
      ;;
    guide.html) check_guide "$file" "$rel" ;;
  esac

  check_head "$file" "$rel"
  check_footer "$file" "$rel"
  check_images "$file" "$rel"
}

# 利用ガイド: 見出し（h2〜h4）にはすべて id を付け（ほかのページやアプリから #id で開けるように）、
# h2 は目次（<nav class="toc">）からリンクする。本文の中のリンクは目次の代わりにならない
check_guide() {
  local file="$1" rel="$2" flat toc tag ident id_pattern='[[:space:]]id="([^"]+)"'
  flat="$(LC_ALL=C tr '\n\r\t' '   ' <"$file")"
  toc="$(LC_ALL=C sed -nE 's/^.*(<nav[^>]*[[:space:]]class="([^"]*[[:space:]])?toc([[:space:]][^"]*)?"[^>]*>)/\1/p' <<<"$flat" | LC_ALL=C sed 's|</nav>.*||')"
  while IFS= read -r tag; do
    if [[ "$tag" =~ $id_pattern ]]; then
      ident="${BASH_REMATCH[1]}"
      if [[ "$tag" == "<h2"* && "$toc" != *"href=\"#$ident\""* ]]; then
        problem "$rel: 目次に #$ident へのリンクがありません"
      fi
    else
      problem "$rel: id の無い見出しがあります: $tag"
    fi
  done < <(LC_ALL=C grep -oE '<h[234]([[:space:]][^>]*)?>' <<<"$flat" || true)
}

# <link rel="canonical" href="…"> のホスト（小文字）。属性の順や rel のほかの値は問わない。無ければ空文字
canonical_host() {
  local file="$1" tag rels href host_pattern='^https?://([^/?#]+)'
  [[ -f "$file" ]] || return 0
  while IFS= read -r tag; do
    rels="$(attribute_values "$tag" rel | tr '\n' ' ')"
    [[ " $rels " == *[[:space:]]canonical[[:space:]]* ]] || continue
    href="$(attribute_values "$tag" href | head -n 1)"
    if [[ "$href" =~ $host_pattern ]]; then
      printf '%s' "${BASH_REMATCH[1]}"
      return 0
    fi
  done < <(LC_ALL=C tr '\n\r\t' '   ' <"$file" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C grep -oE '<link([[:space:]][^>]*)?>' || true)
  return 0
}

# site/ の中の path（先頭の / は無し）に当たるページがあるか。空か / で終わるなら、そのフォルダの index.html
site_page_exists() {
  local path="$1"
  if [[ -z "$path" || "$path" == */ ]]; then
    [[ -f "$SITE/${path}index.html" ]]
  else
    [[ -f "$SITE/$path" || -f "$SITE/$path/index.html" ]]
  fi
}

# 英語で動くアプリが開く path。最後の要素の前に en/ を入れる（guide.html → en/guide.html、docs/ → en/docs/）。サイトの直下は en/
english_path() {
  local path="$1" trailing="" parent=""
  if [[ "$path" == */ ]]; then
    trailing=/
    path="${path%/}"
  fi
  if [[ -z "$path" ]]; then
    printf 'en/'
    return 0
  fi
  [[ "$path" != */* ]] || parent="${path%/*}/"
  printf '%sen/%s%s' "$parent" "${path##*/}" "$trailing"
}

# アプリの「利用ガイド」「プライバシー」「購入する」のボタンが開く URL（xcconfig）が、このサイトのページを指しているなら、
# そのページと、英語で動くアプリが開く en/ のページが site/ にあるか（購入のページも、このサイトのものなら en/ を開く）。ホストは site/index.html の canonical で決める。
# canonical が無いと確かめられないので、--strict では問題にする（ふだんは知らせるだけ）
check_app_links() {
  local host key url rest url_host path en_path
  if [[ ! -f "$CONFIG" ]]; then
    # アプリに入れる URL を確かめられない。公開前（--strict）は止める
    if [[ "$STRICT" == 1 ]]; then
      problem "アプリの設定（${CONFIG}）がありません。アプリが開く URL を確かめられません（--config で指定してください）"
    else
      info "アプリの設定（${CONFIG}）が無いので、アプリが開く URL は確かめていません"
    fi
    return 0
  fi
  host="$(canonical_host "$SITE/index.html")"
  for key in NONET_SUPPORT_URL NONET_PRIVACY_URL NONET_PURCHASE_URL; do
    url="$(xcconfig_value "$CONFIG" "$key")"
    [[ "$url" == http://* || "$url" == https://* ]] || continue
    if [[ -z "$host" ]]; then
      if [[ "$STRICT" == 1 ]]; then
        problem "$(basename "$SITE")/index.html に canonical が無いので、${key}（${url}）がこのサイトのページを指しているか確かめられません（公開する URL の canonical を入れてください）"
      else
        info "$(basename "$SITE")/index.html に canonical が無いので、${key}（${url}）の行き先は確かめていません（--strict では失敗にする）"
      fi
      continue
    fi
    rest="${url#*://}"
    url_host="${rest%%[/?#]*}"
    url_host="$(printf '%s' "$url_host" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
    [[ "$url_host" == "$host" ]] || continue
    path="${rest#"${rest%%[/?#]*}"}"
    path="${path%%[?#]*}"
    path="${path#/}"
    if ! site_page_exists "$path"; then
      if [[ -n "$path" && "$path" != */ && -f "$SITE/$path.html" ]]; then
        # 拡張子を省いた URL（/guide）は、S3 ＋ CloudFront のように .html を補わないホストでは 404 になる
        problem "$(basename "$CONFIG") の ${key}（${url}）は .html を省いています。補わないホストでは開けないので、/$path.html と書いてください"
      else
        problem "$(basename "$CONFIG") の ${key}（${url}）に当たるページが $(basename "$SITE")/ にありません"
      fi
      continue
    fi
    # アプリは英語で動いているとき、最後の要素の前に en/ を入れたページを開く（…/guide.html → …/en/guide.html）。
    # 購入のページも、このサイトのものなら同じ（AppLinks.localized）
    en_path="$(english_path "$path")"
    if ! site_page_exists "$en_path"; then
      problem "$(basename "$CONFIG") の ${key}（${url}）の英語のページ（${url%%://*}://${rest%%[/?#]*}/${en_path}。英語で動くアプリが開く）が $(basename "$SITE")/ にありません"
    fi
  done
  return 0
}

# MARK: 検索と共有（canonical・hreflang・sitemap.xml・robots.txt・og:image）とフッター

# 法的な文書。どれも site/ にあり、各ページのフッターからリンクする（英語のページの特商法は日本語のページへ）
LEGAL_PAGES="privacy.html en/privacy.html terms.html en/terms.html tokushoho.html"
FOOTER_LEGAL_LINKS="privacy.html terms.html tokushoho.html"

# 検索に出さないページ（<meta name="robots" content="noindex">。404・ダウンロードのページ）
is_noindex() {
  LC_ALL=C grep -qiE '<meta[[:space:]]+name="robots"[[:space:]]+content="[^"]*noindex' "$1"
}

# 別の仕組みが作るページ。ここでは直さず、足りないものを知らせるだけにする
#   guide.html・en/guide.html: scripts/build-guide.py が docs/user-guide*.md から作る
generated_by() {
  case "$(basename "$1")" in
    guide.html) printf 'scripts/build-guide.py' ;;
  esac
}

# site/ の中の rel（index.html・en/terms.html など）の公開する URL。index.html はフォルダの URL（/・/en/）
page_url() {
  local rel="$1"
  case "$rel" in
    index.html) rel="" ;;
    */index.html) rel="${rel%index.html}" ;;
  esac
  printf 'https://%s/%s' "$HOST" "$rel"
}

# 日本語と英語の組の、もう一方のページ（en/x.html ↔ x.html）。無ければ空文字
counterpart_of() {
  local rel="$1" other
  case "$rel" in
    en/*) other="${rel#en/}" ;;
    *) other="en/$rel" ;;
  esac
  [[ -f "$SITE/$other" ]] && printf '%s' "$other"
  return 0
}

# <link> を「rel<TAB>hreflang<TAB>href」で1行ずつ出す。属性の順・大文字・改行を問わない（URL は小文字にして比べる）
link_tags() {
  local tag
  while IFS= read -r tag; do
    printf '%s\t%s\t%s\n' "$(attribute_values "$tag" rel | head -n 1)" "$(attribute_values "$tag" hreflang | head -n 1)" \
      "$(attribute_values "$tag" href | head -n 1)"
  done < <(LC_ALL=C tr '\n\r\t' '   ' <"$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C grep -oE '<link([[:space:]][^>]*)?>' || true)
}

# <meta property="…" content="…"> の content。無ければ空文字
meta_property() {
  sed -nE "s/.*<meta property=\"$2\" content=\"([^\"]*)\".*/\\1/p" "$1" | head -n 1
}

# PNG の大きさを「幅×高さ」で出す。PNG でなければ空文字
png_size() {
  local bytes=()
  [[ -f "$1" ]] || return 0
  read -r -a bytes <<<"$(LC_ALL=C od -An -tu1 -N24 "$1" | tr -s ' \n' '  ')"
  [[ "${#bytes[@]}" -ge 24 && "${bytes[0]}" == 137 && "${bytes[1]}" == 80 && "${bytes[2]}" == 78 && "${bytes[3]}" == 71 ]] || return 0
  printf '%d×%d' $(((bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19])) \
    $(((bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23]))
}

# 検索に出すページは、自分の URL の canonical を持ち、日本語と英語の組があれば hreflang で互いを指す
# （ja・en と、言語の合わないブラウザ向けの x-default は英語のページ）。URL はどれも絶対の URL。
# 別の仕組みが作るページで足りないものは、問題にせず知らせる（直すのはその仕組みのほう）
check_head() {
  local file="$1" rel="$2" links canonical counterpart ja en expected line issues=() maker
  [[ -n "$HOST" ]] || return 0
  is_noindex "$file" && return 0
  links="$(link_tags "$file")"
  canonical="$(awk -F'\t' '(" " $1 " ") ~ / canonical / { print $3; exit }' <<<"$links")"
  expected="$(page_url "$rel")"
  if [[ -z "$canonical" ]]; then
    issues+=("<link rel=\"canonical\" href=\"$expected\"> がありません")
  elif [[ "$canonical" != "$expected" ]]; then
    issues+=("canonical が $expected ではありません（いまは ${canonical}）")
  fi
  counterpart="$(counterpart_of "$rel")"
  if [[ -n "$counterpart" ]] && ! is_noindex "$SITE/$counterpart"; then
    case "$rel" in
      en/*) ja="$counterpart" en="$rel" ;;
      *) ja="$rel" en="$counterpart" ;;
    esac
    for line in "ja"$'\t'"$(page_url "$ja")" "en"$'\t'"$(page_url "$en")" "x-default"$'\t'"$(page_url "$en")"; do
      if ! awk -F'\t' '(" " $1 " ") ~ / alternate / { print $2 "\t" $3 }' <<<"$links" | grep -qxF "$line"; then
        issues+=("<link rel=\"alternate\" hreflang=\"${line%%$'\t'*}\" href=\"${line#*$'\t'}\"> がありません")
      fi
    done
  fi
  [[ ${#issues[@]} -gt 0 ]] || return 0
  maker="$(generated_by "$file")"
  if [[ -n "$maker" ]]; then
    info "$rel は $maker が作るページなので止めません。$maker で直すこと: $(printf '%s。' "${issues[@]}")"
    return 0
  fi
  for line in "${issues[@]}"; do
    problem "$rel: $line"
  done
}

# どのページのフッターからも、法的な文書へ行ける
check_footer() {
  local file="$1" rel="$2" footer name pattern missing=() maker
  footer="$(LC_ALL=C tr '\n\r\t' '   ' <"$file" | sed -nE 's/.*(<footer([[:space:]][^>]*)?>.*<\/footer>).*/\1/p')"
  for name in $FOOTER_LEGAL_LINKS; do
    pattern="href=\"[^\"]*${name//./\\.}[\"#]"
    [[ "$footer" =~ $pattern ]] || missing+=("$name")
  done
  [[ ${#missing[@]} -gt 0 ]] || return 0
  maker="$(generated_by "$file")"
  if [[ -n "$maker" ]]; then
    info "$rel は $maker が作るページなので止めません。$maker でフッターに足すリンク: ${missing[*]}"
    return 0
  fi
  problem "$rel: フッターに ${missing[*]} へのリンクがありません（法的な文書は、どのページのフッターからも開けるようにする）"
}

# 共有の画像（og:image）はこのサイトの画像で、og:image:width・height と同じ大きさ。apple-touch-icon は 180×180
check_images() {
  local file="$1" rel="$2" url path width height actual tag href
  url="$(meta_property "$file" 'og:image')"
  if [[ -n "$url" && -n "$HOST" ]]; then
    if [[ "$url" != "https://$HOST/"* ]]; then
      problem "$rel: og:image がこのサイト（https://$HOST/）の画像ではありません: $url"
    else
      path="${url#"https://$HOST/"}"
      width="$(meta_property "$file" 'og:image:width')"
      height="$(meta_property "$file" 'og:image:height')"
      if [[ ! -f "$SITE/$path" ]]; then
        problem "$rel: og:image の画像がありません: site/${path}（python3 -I scripts/make-site-images.py で作る）"
      elif [[ -n "$width$height" ]]; then
        actual="$(png_size "$SITE/$path")"
        [[ "$actual" == "${width}×$height" ]] || problem "$rel: og:image（site/${path}）の大きさが ${width}×$height ではありません（いまは ${actual:-PNG ではない}）"
      fi
    fi
  fi
  while IFS= read -r tag; do
    href="$(attribute_values "$tag" href | head -n 1)"
    [[ -n "$href" && -f "$(dirname "$file")/$href" ]] || continue
    actual="$(png_size "$(dirname "$file")/$href")"
    [[ "$actual" == "180×180" ]] || problem "$rel: apple-touch-icon（${href}）が 180×180 の PNG ではありません（いまは ${actual:-PNG ではない}）"
  done < <(LC_ALL=C tr '\n\r\t' '   ' <"$file" | LC_ALL=C grep -oE '<link[^>]*rel="apple-touch-icon"[^>]*>' || true)
}

check_legal_pages() {
  local rel
  for rel in $LEGAL_PAGES; do
    [[ -f "$SITE/$rel" ]] || problem "法的な文書のページがありません: $rel"
  done
}

# robots.txt は sitemap.xml の場所を絶対の URL で書く。sitemap.xml の URL はどれもこのサイトのページで、
# 検索に出すページ（noindex でないもの）はすべて <loc> にあり、noindex のページは無い
check_robots_and_sitemap() {
  local robots="$SITE/robots.txt" sitemap="$SITE/sitemap.xml" listed url file rel
  [[ -n "$HOST" ]] || return 0
  if [[ ! -f "$robots" ]]; then
    problem "robots.txt がありません"
  elif ! grep -qxF "Sitemap: https://$HOST/sitemap.xml" "$robots"; then
    problem "robots.txt に「Sitemap: https://$HOST/sitemap.xml」の行がありません"
  fi
  if [[ ! -f "$sitemap" ]]; then
    problem "sitemap.xml がありません"
    return 0
  fi
  listed="$(grep -oE '<loc>[^<]*</loc>' "$sitemap" | sed -E 's|</?loc>||g' || true)"
  while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    if [[ "$url" != "https://$HOST/"* ]]; then
      problem "sitemap.xml: このサイト（https://$HOST/）の外の URL です: $url"
    elif ! site_page_exists "${url#"https://$HOST/"}"; then
      problem "sitemap.xml: ページがありません: $url"
    fi
  done < <({
    printf '%s\n' "$listed"
    grep -oE 'href="[^"]*"' "$sitemap" | sed -E 's/^href="//; s/"$//' || true
  } | sort -u)
  while IFS= read -r file; do
    rel="${file#"$SITE/"}"
    url="$(page_url "$rel")"
    if is_noindex "$file"; then
      if grep -qxF "$url" <<<"$listed"; then
        problem "sitemap.xml: 検索に出さない（noindex の）ページが入っています: $url"
      fi
    elif ! grep -qxF "$url" <<<"$listed"; then
      problem "sitemap.xml に ${rel}（${url}）がありません"
    fi
  done <<<"$html_files"
  return 0
}

check_css() {
  local file="$1" rel="${1#"$SITE/"}"
  if LC_ALL=C grep -qiE "@import|url\\([[:space:]]*[\"']?(https?:)?//" "$file"; then
    problem "$rel: 外部のファイルを読み込んでいます（@import や url(https://…)）"
  fi
}

# スクリプトから外部に通信しない（fetch・画像の差し込みなど）。文字列の中の URL を探す
check_js() {
  local file="$1" rel="${1#"$SITE/"}"
  if LC_ALL=C grep -qiE "[\"'\`](https?:)?//" "$file"; then
    problem "$rel: 外部の URL があります（スクリプトから外部に通信しない）"
  fi
}

html_files="$(find "$SITE" -type f -name '*.html' | sort)"
[[ -n "$html_files" ]] || die "$SITE に HTML がありません"
# 公開するホスト（小文字）。site/index.html の canonical で決める。無ければ canonical・hreflang・sitemap の URL は確かめられない
HOST="$(canonical_host "$SITE/index.html")"
[[ -n "$HOST" ]] || problem "index.html: <link rel=\"canonical\"> がありません（公開する URL。ほかのページの canonical・hreflang・sitemap.xml はこれと比べる）"
while IFS= read -r file; do
  check_html "$file"
done <<<"$html_files"
check_legal_pages
check_robots_and_sitemap
while IFS= read -r file; do
  [[ -z "$file" ]] || check_css "$file"
done < <(find "$SITE" -type f -name '*.css' | sort)
while IFS= read -r file; do
  [[ -z "$file" ]] || check_external_markup "$file" "${file#"$SITE/"}"
done < <(find "$SITE" -type f -name '*.svg' | sort)
while IFS= read -r file; do
  [[ -z "$file" ]] || check_js "$file"
done < <(find "$SITE" -type f -name '*.js' | sort)
check_app_links

# 公開前に埋める仮の値。TODO の印と、届かない .invalid のドメイン（画像などのバイナリは見ない）
todos="$(grep -rnIE 'TODO|\.invalid' "$SITE" | sed "s|^$SITE/||" || true)"
if [[ -n "$todos" ]]; then
  if [[ "$STRICT" == 1 ]]; then
    while IFS= read -r line; do
      problem "仮の値が残っています: $(trim "$line")"
    done <<<"$todos"
  else
    info "公開前に埋めるところ（--strict で失敗にする）: $(printf '%s\n' "$todos" | wc -l | tr -d ' ') か所"
  fi
fi

# 試すために入れた Paddle のテスト用（sandbox）のトークン。公開したページに残ると、本当の購入ができない（docs/release.md 3.6.1）
sandbox="$(grep -rnIE "data-paddle-token[[:space:]]*=[[:space:]]*[\"']test_" "$SITE" | sed "s|^$SITE/||" || true)"
if [[ -n "$sandbox" ]]; then
  if [[ "$STRICT" == 1 ]]; then
    while IFS= read -r line; do
      problem "Paddle のテスト用のトークン（test_）が残っています。公開するページには live_ のトークンを入れる: $(trim "$line")"
    done <<<"$sandbox"
  else
    info "Paddle のテスト用のトークン（test_）が入っています（--strict で失敗にする）: $(printf '%s\n' "$sandbox" | wc -l | tr -d ' ') か所"
  fi
fi

# Paddle のトークンと価格の ID の形（site/buy.js と同じ決まり）。形が違うと、公開したページは「準備中」のまま購入を開けない。
# 仮の値（TODO）は上で知らせるので、ここでは埋めた値だけを見る
# 属性は " でも ' でも、= の前後に空白があっても読む（buy.js は dataset で読むので、どの書き方でも効く）
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  location="${line%%:data-paddle-*}"
  attribute="${line#"$location":}"
  # 属性の名前（= の前の空白は除く）と、引用符を外した値（= の後の空白・タブも除く）
  name="${attribute%%[[:space:]=]*}"
  value="$(trim "${attribute#*=}")"
  value="${value:1:${#value}-2}"
  [[ "$value" == *TODO* ]] && continue
  case "$name" in
    data-paddle-token) pattern='^(live|test)_[A-Za-z0-9]{27}$' label="クライアント用トークン（live_ と 27 文字）" ;;
    *) pattern='^pri_[a-z0-9]{26}$' label="価格の ID（pri_ と 26 文字）" ;;
  esac
  if ! [[ "$value" =~ $pattern ]]; then
    if [[ "$STRICT" == 1 ]]; then
      problem "Paddle の${label}の形ではありません（buy.js が購入を開きません）: ${location#"$SITE/"}: $value"
    else
      info "Paddle の${label}の形ではありません（--strict で失敗にする）: ${location#"$SITE/"}: $value"
    fi
  fi
done < <(grep -rnIoE "data-paddle-(token|price)[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*')" "$SITE" || true)

# リリースのたびに、実物で確かめて埋めるところ（data-placeholder。確認済みの macOS の版など）。
# 価格・販売サービス・問い合わせ先のように一度埋めれば済むものではないので、--strict でも止めずに知らせる（docs/release.md）
pending="$(grep -rnIoE 'data-placeholder="[^"]+"' "$SITE" | sed -E "s|^$SITE/||; s|:[0-9]+:data-placeholder=\"([^\"]+)\"| \\1|" | sort -u || true)"
if [[ -n "$pending" ]]; then
  info "リリースの前に実物で確かめて埋めるところ（--strict でも止めない）: $(printf '%s\n' "$pending" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
fi

if [[ "$PROBLEMS" != 0 ]]; then
  die "サイトに $PROBLEMS 件の問題があります（${SITE}）"
fi
info "サイトに問題はありません（${SITE}）"

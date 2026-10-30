#!/bin/bash
# 販売ページ（site/）を確かめる: HTML の基本・リンク切れ・最低限のアクセシビリティ・外部の読み込みが無いこと・商標の表記・
# 利用ガイドの目次と見出しのアンカー・アプリの「利用ガイド」「プライバシー」の URL（xcconfig）がサイトのページを指していること。
# --strict を付けると、TODO（価格・URL などの仮の値）が残っているときと、canonical が無くてアプリの URL を確かめられないときも失敗にする。公開の前に使う。
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
      sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# プライバシーの約束（クッキー・解析・外部のフォントやスクリプトを使わない）のため、
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
        problem "$rel: 外部の${kind}を読み込んでいます（<$name> の $value）"
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
    javascript:*) problem "$rel: javascript: のリンクは使わない（$url）" && return 0 ;;
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
    problem "$rel: リンク先の #$frag がありません（$url）"
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
  [[ "$lang" == "$expected_lang" ]] || problem "$rel: <html lang> が「$expected_lang」ではありません（いまは「$lang」）"
  grep -qi '<meta charset="utf-8">' "$file" || problem "$rel: <meta charset=\"utf-8\"> がありません"
  grep -q '<meta name="viewport" content="width=device-width' "$file" || problem "$rel: viewport の指定がありません"
  grep -qE '<title>[^<]+</title>' "$file" || problem "$rel: <title> がありません"
  grep -qE '<meta name="description" content="[^"]+">' "$file" || problem "$rel: <meta name=\"description\"> がありません"
  grep -q '<main' "$file" || problem "$rel: <main> がありません"
  count="$(grep -oE '<h1[ >]' "$file" | wc -l | tr -d ' ' || true)"
  [[ "$count" == 1 ]] || problem "$rel: <h1> は 1 つにしてください（いまは $count）"

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
      grep -qE 'href="privacy\.html"' "$file" || problem "$rel: プライバシーポリシーへのリンクがありません"
      grep -qE 'href="guide\.html"' "$file" || problem "$rel: 利用ガイドへのリンクがありません"
      ;;
    guide.html) check_guide "$file" "$rel" ;;
  esac
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

# アプリの「利用ガイド」「プライバシー」のボタンが開く URL（xcconfig）が、このサイトのページを指しているなら、
# そのページが site/ にあるか。ホストは site/index.html の canonical で決める。
# canonical が無いと確かめられないので、--strict では問題にする（ふだんは知らせるだけ）
check_app_links() {
  local host key url rest url_host path found
  [[ -f "$CONFIG" ]] || return 0
  host="$(canonical_host "$SITE/index.html")"
  for key in NONET_SUPPORT_URL NONET_PRIVACY_URL; do
    url="$(xcconfig_value "$CONFIG" "$key")"
    [[ "$url" == http://* || "$url" == https://* ]] || continue
    if [[ -z "$host" ]]; then
      if [[ "$STRICT" == 1 ]]; then
        problem "$(basename "$SITE")/index.html に canonical が無いので、$key（$url）がこのサイトのページを指しているか確かめられません（公開する URL の canonical を入れてください）"
      else
        info "$(basename "$SITE")/index.html に canonical が無いので、$key（$url）の行き先は確かめていません（--strict では失敗にする）"
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
    found=""
    if [[ -z "$path" || "$path" == */ ]]; then
      [[ -f "$SITE/${path}index.html" ]] && found=1
    elif [[ -f "$SITE/$path" || -f "$SITE/$path/index.html" ]]; then
      found=1
    elif [[ -f "$SITE/$path.html" ]]; then
      # 拡張子を省いた URL（/guide）は、S3 ＋ CloudFront のように .html を補わないホストでは 404 になる
      problem "$(basename "$CONFIG") の $key（$url）は .html を省いています。補わないホストでは開けないので、/$path.html と書いてください"
      continue
    fi
    [[ -n "$found" ]] || problem "$(basename "$CONFIG") の $key（$url）に当たるページが $(basename "$SITE")/ にありません"
  done
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
while IFS= read -r file; do
  check_html "$file"
done <<<"$html_files"
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

# 公開前に埋める仮の値。TODO の印と、届かない .invalid のドメイン
todos="$(grep -rnE 'TODO|\.invalid' "$SITE" | sed "s|^$SITE/||" || true)"
if [[ -n "$todos" ]]; then
  if [[ "$STRICT" == 1 ]]; then
    while IFS= read -r line; do
      problem "仮の値が残っています: $(trim "$line")"
    done <<<"$todos"
  else
    info "公開前に埋めるところ（--strict で失敗にする）: $(printf '%s\n' "$todos" | wc -l | tr -d ' ') か所"
  fi
fi

if [[ "$PROBLEMS" != 0 ]]; then
  die "サイトに $PROBLEMS 件の問題があります（$SITE）"
fi
info "サイトに問題はありません（$SITE）"

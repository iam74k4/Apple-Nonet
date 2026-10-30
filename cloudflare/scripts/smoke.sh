#!/bin/bash
# 手元で本物の Worker（固定した wrangler の wrangler dev --local）を立て、すべての URL を curl で確かめる。
# Cloudflare には何も送らない。R2 は使い捨てのフォルダ（--persist-to）の中だけで、終わったら消す。
#   1. 出す前: /download と /updates/appcast.xml が 404
#   2. 試しの DMG・デルタ・appcast（test/fixtures/appcast.xml）を手元の R2 に置く
#   3. ページ・404・/updates/*（HEAD・Range・304・416・405・パスの細工）・/download を確かめる
# 使い方: cloudflare/scripts/smoke.sh（先に cloudflare/ で npm ci）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUDFLARE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$CLOUDFLARE_DIR/.." && pwd)"
# shellcheck source=../../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"

case "${1:-}" in
  -h | --help)
    sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

WRANGLER="$CLOUDFLARE_DIR/node_modules/.bin/wrangler"
[[ -x "$WRANGLER" ]] || die "wrangler がありません。先に cloudflare/ で npm ci を実行してください"
require_commands curl node

WORK="$(mktemp -d "${TMPDIR:-/tmp}/nonet-smoke.XXXXXX")"
STATE="$WORK/state"
DEV_PID=""
FAILED=0

cleanup() {
  if [[ -n "$DEV_PID" ]] && kill -0 "$DEV_PID" 2>/dev/null; then
    kill "$DEV_PID" 2>/dev/null || true
    wait "$DEV_PID" 2>/dev/null || true
  fi
  if [[ "$FAILED" == 0 ]]; then
    rm -rf "$WORK"
  else
    info "wrangler dev のログ: $WORK/dev.log"
  fi
}
trap cleanup EXIT

# 空いているポートを2つ（Worker と、wrangler dev が開くデバッガー）
read -r PORT INSPECTOR_PORT < <(node -e '
const net = require("net");
const ports = [];
const next = () => {
  const server = net.createServer();
  server.listen(0, "127.0.0.1", () => {
    ports.push(server.address().port);
    server.close(() => (ports.length < 2 ? next() : console.log(ports.join(" "))));
  });
};
next();')
BASE="http://127.0.0.1:$PORT"

step "wrangler dev --local を立てる（ポート $PORT）"
(
  cd "$CLOUDFLARE_DIR"
  exec "$WRANGLER" dev --local --ip 127.0.0.1 --port "$PORT" --inspector-port "$INSPECTOR_PORT" \
    --persist-to "$STATE" --show-interactive-dev-session=false
) >"$WORK/dev.log" 2>&1 &
DEV_PID=$!
for _ in $(seq 1 120); do
  curl -s -o /dev/null "$BASE/" 2>/dev/null && break
  kill -0 "$DEV_PID" 2>/dev/null || {
    FAILED=1
    tail -n 30 "$WORK/dev.log" >&2
    die "wrangler dev が止まりました"
  }
  sleep 0.5
done
curl -s -o /dev/null "$BASE/" || {
  FAILED=1
  die "wrangler dev が 60 秒たっても応えません"
}

# 1 つの確かめ。curl の結果（状態コードとヘッダ）を見て ok / FAIL を出す
#   expect <説明> <期待する状態コード> <curl の引数…>
# 直前の応答のヘッダは HEADERS、本文は $WORK/body に残る
expect() {
  local label="$1" status="$2" actual
  shift 2
  actual="$(curl -s --path-as-is -o "$WORK/body" -D "$WORK/headers" -w '%{http_code}' "$@" || true)"
  HEADERS="$(tr -d '\r' <"$WORK/headers" | tr '[:upper:]' '[:lower:]')"
  if [[ "$actual" == "$status" ]]; then
    printf 'ok    %-58s %s\n' "$label" "$actual"
  else
    printf 'FAIL  %-58s %s（期待: %s）\n' "$label" "$actual" "$status"
    FAILED=1
  fi
}

# 直前の応答のヘッダに、この行（小文字）が含まれること
expect_header() {
  if grep -qF -- "$1" <<<"$HEADERS"; then
    printf 'ok      ヘッダ %s\n' "$1"
  else
    printf 'FAIL    ヘッダ %s がありません\n' "$1"
    FAILED=1
  fi
}

expect_body() {
  if grep -qF -- "$1" "$WORK/body"; then
    printf 'ok      本文に %s\n' "$1"
  else
    printf 'FAIL    本文に %s がありません\n' "$1"
    FAILED=1
  fi
}

step "出す前"
expect "/download（まだ appcast が無い）" 404 "$BASE/download"
expect_body "ページが見つかりません"
expect_header "cache-control: no-store"
expect "/updates/appcast.xml（まだ無い）" 404 "$BASE/updates/appcast.xml"
expect_header "content-type: text/plain"

step "試しのリリースを手元の R2 に置く"
head -c 300000 /dev/urandom >"$WORK/Nonet-1.2.0.dmg"
printf 'delta' >"$WORK/Nonet42-41.delta"
put() {
  "$WRANGLER" r2 object put "nonet-updates/$1" --file "$2" --content-type "$3" --local --persist-to "$STATE" \
    --config "$CLOUDFLARE_DIR/wrangler.toml" >>"$WORK/put.log" 2>&1 || {
    FAILED=1
    cat "$WORK/put.log" >&2
    die "手元の R2 に置けませんでした: $1"
  }
  info "nonet-updates/$1"
}
put Nonet-1.2.0.dmg "$WORK/Nonet-1.2.0.dmg" application/x-apple-diskimage
put Nonet42-41.delta "$WORK/Nonet42-41.delta" application/octet-stream
put appcast.xml "$CLOUDFLARE_DIR/test/fixtures/appcast.xml" "application/xml; charset=utf-8"

step "販売ページ"
expect "/" 200 "$BASE/"
expect_header "content-type: text/html"
expect_header "content-security-policy: default-src 'none'; script-src 'self'"
expect_header "x-content-type-options: nosniff"
expect_header "referrer-policy: strict-origin-when-cross-origin"
expect_header "permissions-policy: accelerometer=()"
expect_body '<html lang="ja">'
expect "/en/" 200 "$BASE/en/"
expect_body '<html lang="en">'
expect "/en（/en/ へ）" 301 "$BASE/en"
expect_header "location: /en/"
for page in /privacy.html /en/privacy.html /guide.html /en/guide.html /style.css /script.js /favicon.svg; do
  if [[ -f "$ROOT/site$page" ]]; then
    expect "$page" 200 "$BASE$page"
    expect_header "x-content-type-options: nosniff"
  else
    printf 'skip  %-58s site%s がまだ無い\n' "$page" "$page"
  fi
done
expect "/privacy.html は .html のまま（リダイレクトしない）" 200 -I "$BASE/privacy.html"
expect "/privacy（.html なしは無いページ）" 404 "$BASE/privacy"
expect "HEAD /" 200 -I "$BASE/"

step "無いページ"
expect "/no-such-page" 404 "$BASE/no-such-page"
expect_body "ページが見つかりません"
expect_header "content-security-policy: default-src 'none'"
expect "/a/b/c/（深いパス）" 404 "$BASE/a/b/c/"
expect_body '<base href="/">'
expect "/en/no-such-page（英語の 404）" 404 "$BASE/en/no-such-page"
expect_body "Page not found"
expect "/index.html.bak" 404 "$BASE/index.html.bak"
expect "/_headers（配らない）" 404 "$BASE/_headers"

step "/updates/*"
expect "/updates/appcast.xml" 200 "$BASE/updates/appcast.xml"
expect_header "content-type: application/xml; charset=utf-8"
expect_header "cache-control: no-cache"
expect_header "content-security-policy: default-src 'none'; frame-ancestors 'none'; sandbox"
expect_header "x-content-type-options: nosniff"
expect_body "<sparkle:version>42</sparkle:version>"
etag="$(sed -n 's/^etag: //p' <<<"$HEADERS")"
expect "If-None-Match（304）" 304 -H "If-None-Match: $etag" "$BASE/updates/appcast.xml"
expect "HEAD DMG" 200 -I "$BASE/updates/Nonet-1.2.0.dmg"
expect_header "content-length: 300000"
expect_header "content-type: application/x-apple-diskimage"
expect_header "accept-ranges: bytes"
expect "GET DMG（全体）" 200 "$BASE/updates/Nonet-1.2.0.dmg"
if cmp -s "$WORK/body" "$WORK/Nonet-1.2.0.dmg"; then
  printf 'ok      中身が置いた DMG と同じ\n'
else
  printf 'FAIL    中身が置いた DMG と違います\n'
  FAILED=1
fi
expect "Range bytes=100-199（206）" 206 -H "Range: bytes=100-199" "$BASE/updates/Nonet-1.2.0.dmg"
expect_header "content-range: bytes 100-199/300000"
expect_header "content-length: 100"
expect "Range の外（416）" 416 -H "Range: bytes=300000-" "$BASE/updates/Nonet-1.2.0.dmg"
expect_header "content-range: bytes */300000"
expect "デルタ" 200 "$BASE/updates/Nonet42-41.delta"
expect_header "content-type: application/octet-stream"
expect "POST（405）" 405 -X POST "$BASE/updates/appcast.xml"
expect_header "allow: get, head"
expect "/updates" 404 "$BASE/updates"
expect "/updates/（一覧は出さない）" 404 "$BASE/updates/"
expect "/updates/Nonet-9.9.9.dmg（無い）" 404 "$BASE/updates/Nonet-9.9.9.dmg"
expect "/updates/%2e%2e%2fappcast.xml" 404 "$BASE/updates/%2e%2e%2fappcast.xml"
expect "/updates/..%2fappcast.xml" 404 "$BASE/updates/..%2fappcast.xml"
expect "/updates/..%5cappcast.xml" 404 "$BASE/updates/..%5cappcast.xml"
expect "/updates//appcast.xml" 404 "$BASE/updates//appcast.xml"
expect "/updates/../updates/appcast.xml（解いても同じファイル）" 200 "$BASE/updates/../updates/appcast.xml"
expect "/updates/../index.html（/updates の外。サイトのページ）" 200 "$BASE/updates/../index.html"

step "/download"
expect "/download" 302 "$BASE/download"
# wrangler dev は Location のホストを手元のものに書き換えるので、パスだけを見る（本番は https://nonet.astlog.dev/…）
expect_header "/updates/nonet-1.2.0.dmg"
expect_header "cache-control: no-store"
expect "HEAD /download" 302 -I "$BASE/download"
expect "POST /download（405）" 405 -X POST "$BASE/download"

if [[ "$FAILED" != 0 ]]; then
  die "確かめた中に失敗があります"
fi
step "すべて通りました"

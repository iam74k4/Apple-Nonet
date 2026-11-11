#!/bin/bash
# Nonet のデモ動画を1本、共通の背景の上で収録する（手順の全体は docs/portfolio.md の「デモ動画」）。
# 使い方: scripts/demo/record.sh <名前> <bundle ID> <台本の JSON> <見本の設定のフォルダ>
#   例: scripts/demo/record.sh xcode com.apple.dt.Xcode scripts/demo/xcode.json ~/Desktop/nonet-demo
# build/demo/<名前>-raw.mp4（2880×1800・H.264。仕上げの vidtool concat --size 1440 900 で縮める。寄せても粗くならないように）に書き、その場所を標準出力に出す。
# 実行するところだったアクションは build/demo/<名前>-demo.log の「demo: perform …」で分かる（デモは何も実行しない）。
# 先に scripts/build.sh で Debug のアプリを作っておく。収録の道具（build/record-screen・build/demo-pointer）と背景はここで作る。
# 流している間、主の画面の全体が背景で覆われる。画面が点いていて、ロックされていないこと。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

case "${1:-}" in
  -h | --help)
    sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac
[[ $# -eq 4 ]] || die "使い方: scripts/demo/record.sh <名前> <bundle ID> <台本の JSON> <見本の設定のフォルダ>"

NAME="$1"
BUNDLE_ID="$2"
SCRIPT_FILE="$3"
CONFIG_DIR="$4"

APP="$ROOT/build/DerivedData/Build/Products/Debug/Nonet.app/Contents/MacOS/Nonet"
OUT="$ROOT/build/demo"
RECORDER="$ROOT/build/record-screen"
POINTER="$ROOT/build/demo-pointer"
BACKDROP="$ROOT/build/backdrop.png"
RAW="$OUT/$NAME-raw.mp4"
DEMO_LOG="$OUT/$NAME-demo.log"
RECORD_LOG="$OUT/$NAME-rec.log"
# アプリは、このファイルができてから台本を始め、消えるまで背景を出したままにする（--demo-start-file）
GO="$OUT/$NAME-go"
# 収録の最長の秒。台本より長くしておく（台本が終わったら、ここで止める）
MAX_SECONDS=60

require_commands swift swiftc
[[ -x "$APP" ]] || die "Debug のアプリがありません: $APP（先に scripts/build.sh）"
[[ -f "$SCRIPT_FILE" ]] || die "台本がありません: $SCRIPT_FILE"
# --config-dir を付けないと、動いているほかの Nonet に任せて終わり、付けても空のフォルダでは初回の設定になる
[[ -f "$CONFIG_DIR/configuration.json" ]] || die "見本の設定がありません: $CONFIG_DIR/configuration.json（作り方は docs/portfolio.md の「つくり方」）"

app_pid=""
recorder_pid=""
pointer_origin=""

# 途中で止まっても、背景を出したままのアプリと収録を残さず、ポインタを戻す（開始のファイルを待っているアプリは、自分では終わらない）。
# ここでも、収録が止まるのを待ってから背景を消す
cleanup() {
  if [[ -n "$recorder_pid" ]]; then
    kill -INT "$recorder_pid" 2>/dev/null || true
    wait "$recorder_pid" 2>/dev/null || true
  fi
  rm -f "$GO"
  [[ -z "$app_pid" ]] || kill "$app_pid" 2>/dev/null || true
  restore_pointer
}
trap cleanup EXIT

restore_pointer() {
  local x y
  [[ -n "$pointer_origin" ]] || return 0
  read -r x y <<<"$pointer_origin"
  pointer_origin=""
  "$POINTER" set "$x" "$y" || true
}

# ファイル $1 に文字列 $2 が出るまで、最長 $3 秒待つ。その前にプロセス $4 が終わっていたら、待つのをやめる
wait_for_line() {
  local file="$1" text="$2" tries=$(($3 * 10)) pid="$4"
  while ((tries > 0)); do
    if grep -qF -- "$text" "$file" 2>/dev/null; then
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      # 書いてすぐ終わったのかもしれないので、もう一度だけ見る
      grep -qF -- "$text" "$file" 2>/dev/null
      return
    fi
    sleep 0.1
    tries=$((tries - 1))
  done
  return 1
}

# ソース $1 が実行ファイル $2 より新しければ（無ければ）、残りの引数を付けてコンパイルする
compile_tool() {
  local src="$1" binary="$2"
  shift 2
  [[ ! -x "$binary" || "$src" -nt "$binary" ]] || return 0
  swiftc -O "$@" "$src" -o "$binary"
}

mkdir -p "$OUT"
rm -f "$GO" "$RAW" "$DEMO_LOG" "$RECORD_LOG"

step "収録の道具と背景を作る"
compile_tool "$ROOT/scripts/record-screen.swift" "$RECORDER" -parse-as-library
compile_tool "$SCRIPT_DIR/pointer.swift" "$POINTER"
# 背景は、いまの主の画面と同じ大きさで毎回作る（画面が替わっていると、アプリが縦横比の違いで始めずに終える）
swift "$ROOT/scripts/make-backdrop.swift" "$BACKDROP" >&2

step "背景を敷く（$BUNDLE_ID・$(basename "$SCRIPT_FILE")）"
"$APP" --config-dir "$CONFIG_DIR" --demo-script-file "$SCRIPT_FILE" --demo-start-file "$GO" \
  --demo-app "$BUNDLE_ID" --demo-backdrop "$BACKDROP" >/dev/null 2>"$DEMO_LOG" &
app_pid=$!
# 背景が出ると、アプリが撮る範囲を書く。背景や台本を読めないときは、理由（demo: error: …）を書いて終わる
if ! wait_for_line "$DEMO_LOG" "capture-region=" 15 "$app_pid"; then
  cat "$DEMO_LOG" >&2
  die "デモを始められません（上の demo: error: を確かめる）"
fi
region="$(sed -n 's/.*capture-region=//p' "$DEMO_LOG" | head -n 1)"
IFS=, read -r region_x region_y region_width region_height <<<"$region"
info "撮る範囲: $region"
# 背景が画面に出きってから撮り始める（先に撮ると、実際の画面が写る）
sleep 1.5

step "収録する"
"$RECORDER" "$RAW" "$MAX_SECONDS" "$region_x" "$region_y" "$region_width" "$region_height" 2880 1800 8000000 >"$RECORD_LOG" 2>&1 &
recorder_pid=$!
if ! wait_for_line "$RECORD_LOG" "収録を始めました" 15 "$recorder_pid"; then
  cat "$RECORD_LOG" >&2
  die "収録を始められません（画面の収録の許可・画面のロックを確かめる）"
fi
# HUD はポインタの位置に開くので、撮る範囲の真ん中へ動かしておく
pointer_origin="$("$POINTER" get)"
"$POINTER" set "$((region_x + region_width / 2))" "$((region_y + region_height / 2))"
sleep 1
touch "$GO"
if ! wait_for_line "$DEMO_LOG" "demo: finished" "$MAX_SECONDS" "$app_pid"; then
  cat "$DEMO_LOG" >&2
  die "台本が終わりませんでした"
fi
# 最後の場面を少し残してから止める。収録を止めてから背景を消す（逆にすると、実際の画面が写る）
sleep 0.5
kill -INT "$recorder_pid"
wait "$recorder_pid" || die "収録を書き終えられませんでした: $(cat "$RECORD_LOG")"
recorder_pid=""
rm -f "$GO"
wait "$app_pid" || warn "アプリが 0 以外で終わりました"
app_pid=""
restore_pointer

info "$(tail -n 1 "$RECORD_LOG")"
while IFS= read -r line; do
  info "$line"
done < <(grep -F "demo: perform" "$DEMO_LOG" || true)
printf '%s\n' "$RAW"

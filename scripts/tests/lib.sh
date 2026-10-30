# テストの道具。run.sh が各テストの前に source する（ROOT と TEST_TMP は run.sh が決める）。
# 外部のツールは fakes/ の偽物に差し替え、ネットワーク・証明書・Xcode に頼らずに動かす。

FAKES_DIR="$ROOT/scripts/tests/fakes"

TEST_TEAM="TESTTEAM01"
TEST_APPCAST_URL="https://nonet.test/updates/appcast.xml"
TEST_PURCHASE_URL="https://store.nonet.test/buy"
TEST_SPARKLE_KEY="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
TEST_LICENSE_KEY="BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="

fail() {
  printf '  %s\n' "$@" >&2
  return 1
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "${3:-値が違います}" "  期待: $1" "  実際: $2"
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "${3:-含まれていません}: 「$2」" "--- 対象 ---" "$1"
}

assert_not_contains() {
  [[ "$1" != *"$2"* ]] || fail "${3:-含まれてはいけません}: 「$2」" "--- 対象 ---" "$1"
}

assert_status() {
  [[ "$STATUS" == "$1" ]] || fail "終了コードが $1 ではなく $STATUS" "--- 出力 ---" "$OUT"
}

assert_failed() {
  [[ "$STATUS" != 0 ]] || fail "失敗するはずが成功しました" "--- 出力 ---" "$OUT"
}

assert_file() {
  [[ -e "$1" ]] || fail "ファイルがありません: $1"
}

assert_no_file() {
  [[ ! -e "$1" ]] || fail "ファイルがあってはいけません: $1"
}

fake_log() {
  cat "$FAKE_LOG"
}

assert_called() {
  assert_contains "$(fake_log)" "$1" "${2:-呼ばれていません}"
}

assert_not_called() {
  assert_not_contains "$(fake_log)" "$1" "${2:-呼ばれてはいけません}"
}

# 記録の中で、渡した文字列がこの順に現れること（それぞれ最初に現れた行で比べる）
assert_called_in_order() {
  local previous=0 line pattern
  for pattern in "$@"; do
    line="$(grep -nF -- "$pattern" "$FAKE_LOG" | head -n 1 | cut -d: -f1 || true)"
    [[ -n "$line" ]] || fail "呼ばれていません: $pattern" "--- 記録 ---" "$(fake_log)" || return 1
    [[ "$line" -gt "$previous" ]] || fail "順番が違います: $pattern（$line 行目）" "--- 記録 ---" "$(fake_log)" || return 1
    previous="$line"
  done
}

# コマンドを実行し、標準出力と標準エラーをまとめて OUT、終了コードを STATUS に入れる。失敗してもテストは止まらない
run() {
  STATUS=0
  OUT="$("$@" 2>&1)" || STATUS=$?
}

# 標準出力を STDOUT、標準エラーを STDERR に分けて受け取る
run_split() {
  STATUS=0
  STDOUT="$("$@" 2>"$TEST_TMP/.stderr")" || STATUS=$?
  STDERR="$(cat "$TEST_TMP/.stderr")"
  OUT="$STDOUT$STDERR"
}

# 外部のツールを偽物に差し替え、テストに関係する環境変数を決まった状態にする
use_fakes() {
  export PATH="$FAKES_DIR:/usr/bin:/bin:/usr/sbin:/sbin"
  export FAKE_LOG="$TEST_TMP/fake.log"
  : >"$FAKE_LOG"
  export NO_COLOR=1
  export FAKE_TEAM="$TEST_TEAM"
  export FAKE_SPARKLE_PUBLIC_KEY="$TEST_SPARKLE_KEY"
  export FAKE_PLIST_FEED="$TEST_APPCAST_URL"
  export FAKE_PLIST_ED_KEY="$TEST_SPARKLE_KEY"
  export FAKE_PLIST_PURCHASE="$TEST_PURCHASE_URL"
  export FAKE_PLIST_LICENSE_KEY="$TEST_LICENSE_KEY"
  # AI のアクションに要る FoundationModels の入った偽の macOS SDK
  export FAKE_SDK_PATH="$TEST_TMP/sdk/MacOSX.sdk"
  mkdir -p "$FAKE_SDK_PATH/System/Library/Frameworks/FoundationModels.framework"
  unset NONET_NOTARY_PROFILE NONET_RELEASES_DIR NONET_DOWNLOAD_URL_PREFIX NONET_SPARKLE_KEY_ACCOUNT NONET_NOTARY_TIMEOUT
}

write_valid_xcconfig() {
  cat >"$1" <<EOF
// テスト用の販売用の値。URL の // は xcconfig ではコメントになるので \$() をはさむ
NONET_APPCAST_URL = https:/\$()/nonet.test/updates/appcast.xml
NONET_SPARKLE_PUBLIC_KEY = $TEST_SPARKLE_KEY
NONET_PURCHASE_URL = https:/\$()/store.nonet.test/buy
NONET_SUPPORT_URL = https:/\$()/nonet.test/guide.html
NONET_PRIVACY_URL = https:/\$()/nonet.test/privacy.html
NONET_LICENSE_PUBLIC_KEY = $TEST_LICENSE_KEY
EOF
}

# スクリプトを一時フォルダの偽のリポジトリ（REPO）にコピーする。
# スクリプトはリポジトリの場所を自分の置き場所から決めるので、こうすると本物のリポジトリに触れずに済む
make_fake_repo() {
  REPO="$TEST_TMP/repo"
  mkdir -p "$REPO/scripts/lib" "$REPO/scripts/tests" "$REPO/Config" "$REPO/Packages/NonetKit" "$REPO/cloudflare/test"
  cp "$ROOT"/scripts/*.sh "$REPO/scripts/"
  cp "$ROOT"/scripts/lib/*.sh "$REPO/scripts/lib/"
  # test.sh から呼ばれる自己テストの代わり（本物を呼ぶと入れ子になる）
  cat >"$REPO/scripts/tests/run.sh" <<'EOF'
#!/bin/bash
printf 'tests/run.sh\n' >>"$FAKE_LOG"
exit "${FAKE_SELFTEST_STATUS:-0}"
EOF
  chmod +x "$REPO/scripts/tests/run.sh"
  cat >"$REPO/project.yml" <<EOF
name: Nonet
settings:
  base:
    DEVELOPMENT_TEAM: $TEST_TEAM
EOF
  write_valid_xcconfig "$REPO/Config/Nonet.xcconfig"
}

# ビルド番号の項目を持つ appcast.xml を作る
write_appcast() {
  local file="$1" build
  shift
  mkdir -p "$(dirname "$file")"
  {
    printf '<?xml version="1.0" encoding="utf-8"?>\n<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n<channel>\n'
    for build in "$@"; do
      printf '<item><sparkle:version>%s</sparkle:version></item>\n' "$build"
    done
    printf '</channel>\n</rss>\n'
  } >"$file"
}

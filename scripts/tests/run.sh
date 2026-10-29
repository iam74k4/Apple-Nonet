#!/bin/bash
# scripts/ とサイト・ドキュメントのテストを動かす。
# 各 *_test.sh の test_* 関数を、それぞれ新しいサブシェルと一時フォルダで実行する（set -e なので最初の失敗で止まる）。
# 使い方: scripts/tests/run.sh [テスト名の一部]
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
export ROOT
filter="${1:-}"

passed=0
failed=0
failures=""

for file in "$TESTS_DIR"/*_test.sh; do
  suite="$(basename "$file" .sh)"
  names="$(
    # shellcheck source=/dev/null
    source "$file"
    declare -F | awk '{ print $3 }' | grep '^test_' || true
  )"
  for name in $names; do
    [[ -z "$filter" || "$suite.$name" == *"$filter"* ]] || continue
    # TMPDIR の末尾の / で「//」にならないよう、スクリプトと同じく cd と pwd で正規化する
    tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/nonet-test.XXXXXX")" && pwd)"
    # if の条件の中で動かすと set -e が効かなくなるので、終了コードは後で受け取る
    set +e
    (
      set -euo pipefail
      TEST_TMP="$tmp"
      # shellcheck source=lib.sh
      source "$TESTS_DIR/lib.sh"
      # shellcheck source=/dev/null
      source "$file"
      cd "$TEST_TMP" || exit 1
      "$name"
    ) >"$tmp/.output" 2>&1
    status=$?
    set -e
    if [[ "$status" == 0 ]]; then
      passed=$((passed + 1))
      printf 'ok    %s.%s\n' "$suite" "$name"
      rm -rf "$tmp"
    else
      failed=$((failed + 1))
      failures+="$suite.$name"$'\n'
      printf 'FAIL  %s.%s\n' "$suite" "$name"
      sed 's/^/      /' "$tmp/.output"
      printf '      （一時フォルダ: %s）\n' "$tmp"
    fi
  done
done

total=$((passed + failed))
if [[ "$total" == 0 ]]; then
  printf 'テストが見つかりません（絞り込み: %s）\n' "$filter" >&2
  exit 1
fi
if [[ "$failed" != 0 ]]; then
  printf '\n%d 件中 %d 件失敗:\n' "$total" "$failed"
  sed 's/^/  - /' <<<"${failures%$'\n'}"
  exit 1
fi
printf '\n%d 件すべて通りました\n' "$total"

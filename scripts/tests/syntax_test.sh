# scripts/ のシェルスクリプトそのものの確認（構文・実行権限・決まりごと・shellcheck）

all_shell_scripts() {
  find "$ROOT/scripts" -type f \( -name '*.sh' -o -path '*/tests/fakes/*' \) | sort
}

test_every_script_parses() {
  local file
  while IFS= read -r file; do
    bash -n "$file" || fail "構文エラー: ${file#"$ROOT/"}"
  done < <(all_shell_scripts)
}

test_entry_scripts_are_executable_and_strict() {
  local file
  for file in "$ROOT"/scripts/*.sh "$ROOT"/scripts/tests/run.sh "$ROOT"/scripts/tests/fakes/* "$ROOT"/scripts/tests/fakes/sparkle/*; do
    [[ -f "$file" ]] || continue
    [[ -x "$file" ]] || fail "実行権限がありません: ${file#"$ROOT/"}"
    assert_eq "#!/bin/bash" "$(head -n 1 "$file")" "${file#"$ROOT/"} の 1 行目（macOS 標準の bash 3.2 で動かす）"
    grep -q '^set -euo pipefail$' "$file" || fail "set -euo pipefail がありません: ${file#"$ROOT/"}"
  done
}

# 警告以上を失敗にする（CI は shellcheck を入れて動かす）。source は各スクリプトの場所から読む
test_shellcheck_when_available() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    printf 'shellcheck が無いので飛ばしました（brew install shellcheck）\n'
    return 0
  fi
  local files=() file
  while IFS= read -r file; do files+=("$file"); done < <(all_shell_scripts)
  shellcheck --external-sources --source-path=SCRIPTDIR --shell=bash --severity=warning "${files[@]}"
}

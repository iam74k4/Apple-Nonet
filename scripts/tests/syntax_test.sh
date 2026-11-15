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

# macOS の /bin/bash（3.2）は、UTF-8 のロケール（ja_JP.UTF-8・en_US.UTF-8。ふだんのターミナルや CI）では、
# 「$mode）」のように変数のすぐ後ろに続く日本語の 1 バイト目までを変数名に含めて、set -u で止まる（C のロケールでは通る）。
# 変数のすぐ後ろが ASCII でない文字なら「${mode}）」のように {} で囲む
test_variables_before_non_ascii_text_are_braced() {
  local found="" file
  while IFS= read -r file; do
    found+="$(perl -ne 'next if /^\s*#/; print "$ARGV:$.: $_" if /(?<![\\\$])\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xff]/' "$file")"
  done < <(all_shell_scripts; [[ ! -d "$ROOT/cloudflare/scripts" ]] || find "$ROOT/cloudflare/scripts" -type f -name '*.sh')
  [[ -z "$found" ]] || fail "変数のすぐ後ろに日本語などが続いています。\${name} のように囲んでください" "$found"
}

# 上の決まりを、実際に UTF-8 のロケールの bash で確かめる（囲まないと unbound variable で止まる）
test_bash_reads_braced_variables_the_same_in_utf8() {
  local out
  out="$(LC_ALL=en_US.UTF-8 /bin/bash -c 'set -u; mode=x; printf "%s\n" "a${mode}の"' 2>&1)" || fail "UTF-8 のロケールの bash が止まりました" "$out"
  assert_eq "axの" "$out" "UTF-8 のロケールの bash"
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

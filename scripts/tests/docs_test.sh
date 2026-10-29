# ドキュメント（README・docs/）と CI の設定が、実物とずれていないかのテスト

OWNED_DOCS="README.md docs/release.md docs/user-guide.md docs/privacy.md"

test_markdown_links_resolve() {
  local doc link path anchor target heading_pattern
  for doc in $OWNED_DOCS; do
    assert_file "$ROOT/$doc"
    while IFS= read -r link; do
      case "$link" in
        http://* | https://* | mailto:*) continue ;;
      esac
      path="${link%%#*}"
      anchor=""
      [[ "$link" != *#* ]] || anchor="${link#*#}"
      if [[ -z "$path" ]]; then
        target="$ROOT/$doc"
      else
        target="$(dirname "$ROOT/$doc")/$path"
        [[ -e "$target" ]] || fail "$doc: リンク先がありません: $link"
      fi
      if [[ -n "$anchor" && -f "$target" ]]; then
        # GitHub の見出しのアンカー（空白は -）。記号の扱いまでは真似しないので、ゆるく比べる
        heading_pattern="^#+ .*$(printf '%s' "$anchor" | sed 's/-/./g')"
        grep -qiE "$heading_pattern" "$target" || fail "$doc: 見出しがありません: $link"
      fi
    done < <(grep -oE '\]\([^)[:space:]]+\)' "$ROOT/$doc" | sed -E 's/^\]\(//; s/\)$//' || true)
  done
}

test_user_guide_covers_every_script_variable() {
  local variables name
  variables="$(grep -oE 'NONET_[A-Z_]+' "$ROOT/Packages/NonetKit/Sources/NonetCore/Model/ScriptEnvironment.swift" | sort -u)"
  [[ -n "$variables" ]] || fail "ScriptEnvironment.swift から変数の名前を読めません"
  for name in $variables PROJECT_DIR; do
    grep -q "$name" "$ROOT/docs/user-guide.md" || fail "docs/user-guide.md に $name の説明がありません"
  done
}

# 「指を離したとき」（ExecutionTiming.onFingerLift）では指を離すと実行されるので、やめ方は実行のタイミングごとに書く
test_user_guide_cancel_covers_both_execution_timings() {
  local section
  section="$(sed -n '/^### やめる/,/^##/p' "$ROOT/docs/user-guide.md")"
  [[ -n "$section" ]] || fail "docs/user-guide.md に「やめる」の節がありません"
  assert_contains "$section" "「キーを離したとき」（既定）" "やめる: 既定のタイミングでのやめ方"
  assert_contains "$section" "「指を離したとき」" "やめる: 指を離したときのやめ方"
  assert_contains "$section" "左の⇧" "やめる: ほかのキーで中断できること"
  assert_contains "$section" "空きマス" "やめる: 空きマスで離せば何も起きないこと"
}

# ドキュメントに書いた release.sh のオプションが、スクリプトにあること
test_documented_release_options_exist() {
  local doc option options
  options="$(sed -n '/^usage()/,/^}/p' "$ROOT/scripts/release.sh" | grep -oE -- '--[a-z-]+' | sort -u)"
  for doc in README.md docs/release.md; do
    for option in $(grep -E 'scripts/release\.sh' "$ROOT/$doc" | grep -oE -- '(^|[[:space:]`])--[a-z][a-z-]*' | grep -oE -- '--[a-z-]+' | sort -u); do
      grep -qx -- "$option" <<<"$options" || fail "$doc: release.sh に無いオプションです: $option"
    done
  done
}

test_release_doc_covers_script_options_and_variables() {
  local name
  for name in $(sed -n '/^usage()/,/^}/p' "$ROOT/scripts/release.sh" | grep -oE 'NONET_[A-Z_]+|--[a-z-]+' | sort -u); do
    grep -q -- "$name" "$ROOT/docs/release.md" || fail "docs/release.md に $name の説明がありません"
  done
  for name in $(grep -oE '^NONET_[A-Z_]+' "$ROOT/Config/Nonet.xcconfig"); do
    grep -q "$name" "$ROOT/docs/release.md" || fail "docs/release.md に Config/Nonet.xcconfig の $name の説明がありません"
  done
}

test_privacy_policy_dates_match_the_site() {
  local ja en
  ja="$(sed -nE 's/^最終更新: (.+)$/\1/p' "$ROOT/docs/privacy.md")"
  en="$(sed -nE 's/^Last updated: (.+)$/\1/p' "$ROOT/docs/privacy.md")"
  [[ -n "$ja" && -n "$en" ]] || fail "docs/privacy.md に最終更新日がありません"
  grep -qF "最終更新: $ja" "$ROOT/site/privacy.html" || fail "site/privacy.html の最終更新日が docs/privacy.md（$ja）と違います"
  grep -qF "Last updated: $en" "$ROOT/site/en/privacy.html" || fail "site/en/privacy.html の最終更新日が docs/privacy.md（$en）と違います"
}

test_ci_runs_the_test_script() {
  local ci="$ROOT/.github/workflows/ci.yml"
  assert_file "$ci"
  grep -q 'scripts/test.sh' "$ci" || fail "CI が scripts/test.sh を動かしていません"
  grep -q 'brew install xcodegen' "$ci" || fail "CI が XcodeGen を入れていません"
  grep -qE '^on:' "$ci" || fail "CI の on: がありません"
  grep -q 'pull_request' "$ci" || fail "CI がプルリクエストで動きません"
}

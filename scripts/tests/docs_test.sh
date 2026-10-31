# ドキュメント（README・docs/）と CI の設定が、実物とずれていないかのテスト

OWNED_DOCS="README.md docs/release.md docs/user-guide.md docs/user-guide.en.md docs/privacy.md docs/hosting.md"

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

# やめ方（SessionCancellation・SessionEnd.interrupted）を、利用ガイドの「やめる」の節がすべて書いている。
# 外枠の幅は GridInsets.cancelFrame と同じ数字にする
test_user_guide_cancel_covers_every_way_to_cancel() {
  local section frame
  section="$(sed -n '/^### やめる/,/^##/p' "$ROOT/docs/user-guide.md")"
  [[ -n "$section" ]] || fail "docs/user-guide.md に「やめる」の節がありません"
  assert_contains "$section" "外枠で離す" "やめる: 外枠で離せば何も実行しないこと"
  assert_contains "$section" "キーを押す" "やめる: キーで閉じられること"
  assert_contains "$section" "空きマス" "やめる: 空きマスで離せば何も起きないこと"
  assert_contains "$section" "境目" "やめる: マスの境目で離せば実行しないこと"
  assert_contains "$section" "20秒" "やめる: 長すぎる操作は自動で閉じること"
  frame="$(grep -E 'static let cancelFrame' "$ROOT/Packages/NonetKit/Sources/NonetCore/Engine/GridMapper.swift")"
  assert_contains "$frame" "left: 0.11, right: 0.11, bottom: 0.15, top: 0.17" "外枠の幅が変わったら、利用ガイドの「やめる」の数字も直す"
  assert_contains "$section" "左右の端から幅の 11%、手前の端から奥行きの 15%、奥の端から 17%" "やめる: 外枠の幅"
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

# Mac の中に保存するものを、プライバシーポリシーの3つ（docs と販売ページの日英）がすべて書いている
test_privacy_policy_lists_what_is_stored() {
  local file item service
  service="$(sed -nE 's/.*static let service = "([^"]+)".*/\1/p' "$ROOT/Packages/NonetKit/Sources/NonetCore/Licensing/TrialRecordKeychain.swift")"
  [[ -n "$service" ]] || fail "キーチェーンの項目のサービス名を読めません"
  for file in docs/privacy.md site/privacy.html site/en/privacy.html; do
    for item in configuration.json configuration.backup.json com.iam74k4.Nonet.plist Application\ Support/Nonet "$service" .command \
      Nonet/Terminal Nonet/Shortcuts input-; do
      grep -qF "$item" "$ROOT/$file" || fail "$file に保存するもの（$item）の説明がありません"
    done
  done
}

# プライバシーポリシーが書いているスクリプトの変数（それがあるときだけ読むもの）が、本当にある
test_privacy_policy_names_real_script_variables() {
  local file name variables
  variables="$(grep -oE 'NONET_[A-Z_]+' "$ROOT/Packages/NonetKit/Sources/NonetCore/Model/ScriptEnvironment.swift" | sort -u)"
  [[ -n "$variables" ]] || fail "ScriptEnvironment.swift から変数の名前を読めません"
  for file in docs/privacy.md site/privacy.html site/en/privacy.html; do
    for name in NONET_SELECTED_TEXT NONET_BROWSER_URL; do
      grep -qF "$name" "$ROOT/$file" || fail "$file に $name の説明がありません"
    done
    for name in $(grep -oE 'NONET_[A-Z_]+' "$ROOT/$file" | sort -u); do
      grep -qx "$name" <<<"$variables" || fail "$file のスクリプトの変数 $name が ScriptEnvironment.swift にありません"
    done
  done
}

# NonetCore は純粋なロジック（docs/architecture.md §2）。Security・LocalAuthentication は、ライセンスの節に書いた例外のファイルだけが使う
test_core_uses_system_frameworks_only_where_documented() {
  local core="$ROOT/Packages/NonetKit/Sources/NonetCore" exception="Licensing/TrialRecordKeychain.swift" files
  files="$(grep -rlE '^import (AppKit|Security|LocalAuthentication)$' "$core" | sed "s#^$core/##" || true)"
  [[ -z "$files" || "$files" == "$exception" ]] || fail "NonetCore で AppKit・Security・LocalAuthentication を使うファイルが増えました: $files"
  if [[ -n "$files" ]]; then
    sed -n '/^### ライセンス/,/^### /p' "$ROOT/docs/architecture.md" | grep -qF "$exception" ||
      fail "docs/architecture.md のライセンスの節に、$exception の例外の説明がありません"
  fi
}

test_ci_runs_the_test_script() {
  local ci="$ROOT/.github/workflows/ci.yml"
  assert_file "$ci"
  grep -q 'scripts/test.sh' "$ci" || fail "CI が scripts/test.sh を動かしていません"
  grep -q 'brew install xcodegen' "$ci" || fail "CI が XcodeGen を入れていません"
  grep -qE '^on:' "$ci" || fail "CI の on: がありません"
  grep -q 'pull_request' "$ci" || fail "CI がプルリクエストで動きません"
}

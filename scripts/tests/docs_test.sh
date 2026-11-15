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
  assert_contains "$section" "輪の外で離す" "やめる: アイコンの輪の外で離せば何も実行しないこと"
  assert_contains "$section" "キーを押す" "やめる: キーで閉じられること"
  assert_contains "$section" "空きマス" "やめる: 空きマスで離せば何も起きないこと"
  assert_contains "$section" "境目" "やめる: マスの境目で離せば実行しないこと"
  assert_contains "$section" "20秒" "やめる: 長すぎる操作は自動で閉じること"
  frame="$(grep -E 'static let outerRadius' "$ROOT/Packages/NonetKit/Sources/NonetCore/Engine/RadialMapper.swift")"
  assert_contains "$frame" "outerRadius: Double = 134" "輪の外の半径が変わったら、利用ガイドの「やめる」の数字も直す"
  assert_contains "$section" "134pt" "やめる: 輪の外の半径"
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
  grep -qF "最終更新: $ja" "$ROOT/site/privacy.html" || fail "site/privacy.html の最終更新日が docs/privacy.md（${ja}）と違います"
  grep -qF "Last updated: $en" "$ROOT/site/en/privacy.html" || fail "site/en/privacy.html の最終更新日が docs/privacy.md（${en}）と違います"
}

# Mac の中に保存するものを、プライバシーポリシーの3つ（docs と販売ページの日英）がすべて書いている
test_privacy_policy_lists_what_is_stored() {
  local file item service
  service="$(sed -nE 's/.*static let service = "([^"]+)".*/\1/p' "$ROOT/Packages/NonetKit/Sources/NonetCore/Licensing/TrialRecordKeychain.swift")"
  [[ -n "$service" ]] || fail "キーチェーンの項目のサービス名を読めません"
  for file in docs/privacy.md site/privacy.html site/en/privacy.html; do
    for item in configuration.json configuration.backup.json com.iam74k4.Nonet.plist Application\ Support/Nonet "$service" .command \
      Nonet/Terminal Nonet/Shortcuts input-; do
      grep -qF "$item" "$ROOT/$file" || fail "$file に保存するもの（${item}）の説明がありません"
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

# 読めない・保存すると失う・別の版の設定ファイルを、アプリが残す名前（ConfigurationStore.swift）を、プライバシーポリシーの3つが日英とも書いている
privacy_copy_names() {
  # HTML の &lt; &gt; を戻し、<日時> や <date-time> のような置き換え部分をそろえて、configuration.….json の名前を出す
  sed -e 's/&lt;/</g; s/&gt;/>/g' | sed -E 's/<[^>]*>/<>/g' | grep -oE 'configuration[.][A-Za-z0-9<>.-]*[.]json' | sort -u || true
}

test_privacy_policy_names_the_settings_copies_the_app_keeps() {
  local store="$ROOT/Packages/NonetKit/Sources/NonetCore/Model/ConfigurationStore.swift" name ja_md en_md
  # アプリがこの名前で残している（名前を変えたら、ポリシーも直す）
  grep -qF 'base: "configuration.corrupt-\(' "$store" || fail "ConfigurationStore.swift の configuration.corrupt-… の名前が変わりました"
  grep -qF 'family: "configuration.lossy"' "$store" || fail "ConfigurationStore.swift の configuration.lossy-… の名前が変わりました"
  grep -qF 'family: "configuration.v\(' "$store" || fail "ConfigurationStore.swift の configuration.v<番号>.json の名前が変わりました"
  ja_md="$(sed -n '/^## 日本語$/,/^## English$/p' "$ROOT/docs/privacy.md")"
  en_md="$(sed -n '/^## English$/,$p' "$ROOT/docs/privacy.md")"
  [[ -n "$ja_md" && -n "$en_md" ]] || fail "docs/privacy.md の日本語と英語の節を読めません"
  for name in 'configuration.corrupt-<>.json' 'configuration.lossy-<>.json' 'configuration.v<>.json'; do
    grep -qxF "$name" <<<"$(privacy_copy_names <<<"$ja_md")" || fail "docs/privacy.md の日本語に $name の説明がありません"
    grep -qxF "$name" <<<"$(privacy_copy_names <<<"$en_md")" || fail "docs/privacy.md の英語に $name の説明がありません"
  done
  # 販売ページは、同じ言語の docs/privacy.md と同じ名前を書いている
  assert_eq "$(privacy_copy_names <<<"$ja_md")" "$(privacy_copy_names <"$ROOT/site/privacy.html")" "site/privacy.html と docs/privacy.md（日本語）の設定ファイルの名前"
  assert_eq "$(privacy_copy_names <<<"$en_md")" "$(privacy_copy_names <"$ROOT/site/en/privacy.html")" "site/en/privacy.html と docs/privacy.md（英語）の設定ファイルの名前"
}

# 証明書・鍵・環境変数のファイルをコミットしない（docs/release.md は .p12 の書き出しを勧めている）
test_gitignore_keeps_secret_files_out_of_the_repo() {
  if ! command -v git >/dev/null 2>&1 || ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'git の作業ツリーではないので飛ばしました\n'
    return 0
  fi
  local path
  for path in cert.p12 DeveloperID.p12 AuthKey_ABCDE12345.p8 key.pem cert.cer .dev.vars cloudflare/.dev.vars .env .env.local .env.production \
    secrets/anything nonet-license.private-key; do
    git -C "$ROOT" check-ignore -q --no-index "$path" || fail ".gitignore が $path を無視していません"
  done
  # 無視しすぎない
  for path in README.md project.yml scripts/release.sh .env.example cloudflare/wrangler.toml; do
    ! git -C "$ROOT" check-ignore -q --no-index "$path" || fail ".gitignore が $path まで無視しています"
  done
}

test_no_secret_files_or_private_keys_are_tracked() {
  if ! command -v git >/dev/null 2>&1 || ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'git の作業ツリーではないので飛ばしました\n'
    return 0
  fi
  local files
  files="$(git -C "$ROOT" ls-files | grep -E '[.](p12|p8|pem|cer|private-key)$|(^|/)[.]dev[.]vars$|(^|/)[.]env($|[.])' | grep -vE '(^|/)[.]env[.]example$' || true)"
  [[ -z "$files" ]] || fail "コミットしてはいけないファイルが追跡されています:" "$files"
  # 正規表現にしてあるので、このファイル自身には当たらない
  files="$(git -C "$ROOT" grep -I -l -E 'BEGIN (RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY' || true)"
  [[ -z "$files" ]] || fail "秘密鍵が追跡されているファイルにあります:" "$files"
}

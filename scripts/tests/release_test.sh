# scripts/release.sh のテスト。前半は関数の単体テスト、後半は偽のツールで全体を通す

load_release() {
  # shellcheck source=../release.sh
  source "$ROOT/scripts/release.sh"
}

# 偽のリポジトリで、公証まで含む本番の流れを動かせる状態にする。
# 手元に appcast は無く、公開中の appcast（偽の curl が返す）にはビルド 41 が載っている
prepare_release() {
  use_fakes
  make_fake_repo
  RELEASES="$TEST_TMP/releases"
  export NONET_RELEASES_DIR="$RELEASES"
  export NONET_NOTARY_PROFILE="nonet-test-profile"
  write_appcast "$TEST_TMP/published/appcast.xml" 41
  export FAKE_CURL_BODY="$TEST_TMP/published/appcast.xml"
}

# 公開中の appcast がまだ無い状態（偽の curl は 404 を返す）
no_published_appcast() {
  unset FAKE_CURL_BODY
}

# MARK: - 引数

test_version_validation() {
  load_release
  local v
  for v in 1.0 1.2.3 10.20.30; do
    is_valid_version "$v" || fail "正しいバージョンを拒否: $v"
  done
  for v in 1 1.2.3.4 v1.2 1.2-beta 1..2 ""; do
    ! is_valid_version "$v" || fail "おかしなバージョンを受け付けた: $v"
  done
}

test_build_validation() {
  load_release
  local b
  for b in 1 42 1000; do
    is_valid_build "$b" || fail "正しいビルド番号を拒否: $b"
  done
  for b in 0 01 1.2 -1 abc ""; do
    ! is_valid_build "$b" || fail "おかしなビルド番号を受け付けた: $b"
  done
}

test_help_prints_usage_and_needs_nothing() {
  make_fake_repo
  run env PATH=/usr/bin:/bin "$REPO/scripts/release.sh" --help
  assert_status 0
  assert_contains "$OUT" "使い方: scripts/release.sh"
  assert_contains "$OUT" "--dry-run"
  assert_contains "$OUT" "--allow-dirty"
  assert_contains "$OUT" "--allow-branch"
  assert_contains "$OUT" "NONET_NOTARY_PROFILE"
}

test_arguments_are_required() {
  use_fakes
  make_fake_repo
  run "$REPO/scripts/release.sh"
  assert_status 2
  assert_contains "$OUT" "バージョンとビルド番号を指定してください"
  run "$REPO/scripts/release.sh" 1.2.0
  assert_status 2
  run "$REPO/scripts/release.sh" 1.2.0 42 43
  assert_status 2
}

test_invalid_arguments_are_usage_errors() {
  use_fakes
  make_fake_repo
  run "$REPO/scripts/release.sh" v1.2 42
  assert_status 2
  assert_contains "$OUT" "1.2 か 1.2.3 の形"
  run "$REPO/scripts/release.sh" 1.2.0 1.5
  assert_status 2
  assert_contains "$OUT" "1 以上の整数"
  run "$REPO/scripts/release.sh" --frobnicate 1.2.0 42
  assert_status 2
  assert_contains "$OUT" "知らないオプションです: --frobnicate"
  run "$REPO/scripts/release.sh" 1.2.0 42 --notes
  assert_status 2
  assert_not_called "xcodegen"
}

# MARK: - xcconfig

test_xcconfig_value_follows_xcode_rules() {
  local file="$TEST_TMP/test.xcconfig"
  cat >"$file" <<'EOF'
// コメント
NONET_APPCAST_URL = https://nonet.test/appcast.xml
NONET_PURCHASE_URL=https:/$()/store.nonet.test/buy // 末尾のコメント
NONET_PURCHASE_URL_OLD = https:/$()/old.nonet.test
   NONET_SPARKLE_PUBLIC_KEY   =   first
NONET_SPARKLE_PUBLIC_KEY = second
NONET_LICENSE_PUBLIC_KEY =
EOF
  printf 'WINDOWS_LINE = value\r\n' >>"$file"
  # shellcheck source=../lib/common.sh
  source "$ROOT/scripts/lib/common.sh"
  assert_eq "https:" "$(xcconfig_value "$file" NONET_APPCAST_URL)" "// から後ろはコメント"
  assert_eq "https://store.nonet.test/buy" "$(xcconfig_value "$file" NONET_PURCHASE_URL)" "\$() は空文字"
  assert_eq "second" "$(xcconfig_value "$file" NONET_SPARKLE_PUBLIC_KEY)" "後に書いたものが勝つ"
  assert_eq "" "$(xcconfig_value "$file" NONET_LICENSE_PUBLIC_KEY)" "空の値"
  assert_eq "" "$(xcconfig_value "$file" NONET_MISSING)" "無いキー"
  assert_eq "value" "$(xcconfig_value "$file" WINDOWS_LINE)" "CRLF の行"
}

test_config_problems_lists_every_empty_value() {
  load_release
  local file="$TEST_TMP/empty.xcconfig" problems
  # 本物の Config/Nonet.xcconfig のキーを使う。値が埋まった後でも試せるよう、値は空にする
  sed -E 's/^(NONET_[A-Z_]+)[[:space:]]*=.*$/\1 =/' "$ROOT/Config/Nonet.xcconfig" >"$file"
  problems="$(config_problems "$file")"
  assert_contains "$problems" "NONET_APPCAST_URL が空です"
  assert_contains "$problems" "NONET_PURCHASE_URL が空です"
  assert_contains "$problems" "NONET_SUPPORT_URL が空です"
  assert_contains "$problems" "NONET_PRIVACY_URL が空です"
  assert_contains "$problems" "NONET_SPARKLE_PUBLIC_KEY が空です"
  assert_contains "$problems" "NONET_LICENSE_PUBLIC_KEY が空です"
  assert_contains "$problems" "NONET_SUPPORT_EMAIL が空です"
}

test_config_problems_accepts_valid_values() {
  load_release
  write_valid_xcconfig "$TEST_TMP/valid.xcconfig"
  assert_eq "" "$(config_problems "$TEST_TMP/valid.xcconfig")"
}

test_config_problems_explains_truncated_url() {
  load_release
  local file="$TEST_TMP/bad.xcconfig" problems
  write_valid_xcconfig "$file"
  cat >>"$file" <<'EOF'
NONET_APPCAST_URL = https://nonet.test/appcast.xml
NONET_PURCHASE_URL = http:/$()/store.nonet.test
EOF
  problems="$(config_problems "$file")"
  assert_contains "$problems" "NONET_APPCAST_URL が「https:」で切れています"
  assert_contains "$problems" "https:/\$()/example.com"
  assert_contains "$problems" "NONET_PURCHASE_URL は https:// で始まる URL にしてください"
}

test_config_problems_rejects_placeholders_and_bad_keys() {
  load_release
  local file="$TEST_TMP/bad.xcconfig" problems
  write_valid_xcconfig "$file"
  cat >>"$file" <<'EOF'
NONET_PURCHASE_URL = https:/$()/TODO.invalid/buy
NONET_SPARKLE_PUBLIC_KEY = tooShort=
EOF
  problems="$(config_problems "$file")"
  assert_contains "$problems" "NONET_PURCHASE_URL が仮の値のままです"
  assert_contains "$problems" "NONET_SPARKLE_PUBLIC_KEY が Ed25519 の公開鍵"
  assert_not_contains "$problems" "NONET_LICENSE_PUBLIC_KEY"
}

test_config_problems_checks_the_support_email() {
  load_release
  local file="$TEST_TMP/bad.xcconfig" problems value
  write_valid_xcconfig "$file"
  for value in "mailto:support@nonet.test" "support" "support@nonet" "a b@nonet.test" "support@nonet.test?cc=x@y.test"; do
    printf 'NONET_SUPPORT_EMAIL = %s\n' "$value" >>"$file"
    problems="$(config_problems "$file")"
    assert_contains "$problems" "NONET_SUPPORT_EMAIL は support@example.com のようなメールアドレスにしてください（いまは $value）"
  done
  printf 'NONET_SUPPORT_EMAIL = %s\n' "support@example.com" >>"$file"
  assert_contains "$(config_problems "$file")" "NONET_SUPPORT_EMAIL が仮の値のままです（support@example.com）"
  printf 'NONET_SUPPORT_EMAIL = %s\n' "help+nonet@mail.astlog.dev" >>"$file"
  assert_eq "" "$(config_problems "$file")"
}

test_config_problems_explains_a_key_cut_by_double_slash() {
  load_release
  local file="$TEST_TMP/bad.xcconfig" problems slashed
  # base64 の公開鍵の約1%は「//」を含む（Sparkle の generate_keys は選び直さない）
  slashed="AAAAAAAAAAAAAAAAAAAA//AAAAAAAAAAAAAAAAAAAAA="
  is_ed25519_public_key "$slashed" || fail "テストの鍵が 44 文字の base64 ではありません"
  write_valid_xcconfig "$file"
  printf 'NONET_SPARKLE_PUBLIC_KEY = %s\n' "$slashed" >>"$file"
  problems="$(config_problems "$file")"
  assert_contains "$problems" "NONET_SPARKLE_PUBLIC_KEY が「//」の所で切れています"
  assert_contains "$problems" "「/\$()/」と書いてください"
  assert_not_contains "$problems" "NONET_LICENSE_PUBLIC_KEY"

  # /$()/ と書けば通る
  printf 'NONET_SPARKLE_PUBLIC_KEY = %s\n' "AAAAAAAAAAAAAAAAAAAA/\$()/AAAAAAAAAAAAAAAAAAAAA=" >>"$file"
  assert_eq "" "$(config_problems "$file")"
  assert_eq "$slashed" "$(xcconfig_value "$file" NONET_SPARKLE_PUBLIC_KEY)"

  # 鍵の後ろのコメントは問題ない
  printf 'NONET_LICENSE_PUBLIC_KEY = %s // ライセンスの鍵\n' "$TEST_LICENSE_KEY" >>"$file"
  assert_eq "" "$(config_problems "$file")"
}

test_xcconfig_raw_value_keeps_comments_and_expansions() {
  # shellcheck source=../lib/common.sh
  source "$ROOT/scripts/lib/common.sh"
  printf 'KEY = abc/$()/def // memo\nOTHER=1\n  KEY=last//x  \n' >"$TEST_TMP/raw.xcconfig"
  assert_eq "last//x" "$(xcconfig_raw_value "$TEST_TMP/raw.xcconfig" KEY)"
  assert_eq "1" "$(xcconfig_raw_value "$TEST_TMP/raw.xcconfig" OTHER)"
  assert_eq "" "$(xcconfig_raw_value "$TEST_TMP/raw.xcconfig" NONE)"
}

test_release_needs_an_sdk_with_foundation_models() {
  prepare_release
  export FAKE_SDK_PATH="$TEST_TMP/old-sdk/MacOSX15.5.sdk" FAKE_SDK_VERSION=15.5
  mkdir -p "$FAKE_SDK_PATH/System/Library/Frameworks"
  run "$REPO/scripts/release.sh" --dry-run 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "リリースの準備が足りません"
  assert_contains "$OUT" "macOS SDK 15.5 に FoundationModels がありません。Xcode 26 以降を選んでください"
  assert_not_called "xcodegen"
  assert_not_called "xcodebuild"
}

test_sparkle_resolved_version() {
  load_release
  local project="$TEST_TMP/Nonet.xcodeproj"
  assert_eq "" "$(sparkle_resolved_version "$project")" "まだ解決していない"
  mkdir -p "$project/project.xcworkspace/xcshareddata/swiftpm"
  cat >"$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" <<'EOF'
{
  "pins" : [
    {
      "identity" : "sparkle",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/sparkle-project/Sparkle",
      "state" : {
        "revision" : "ab7d71291238df6e0492143b120c9b696a35f603",
        "version" : "2.10.1"
      }
    }
  ],
  "version" : 3
}
EOF
  assert_eq "2.10.1" "$(sparkle_resolved_version "$project")"
}

# 新しい Mac や CI で、試していない Sparkle の版に変わらないよう、版を固定している
test_project_pins_sparkle_to_an_exact_version() {
  local pinned
  pinned="$(sed -n '/^  Sparkle:/,/^[^ ]/p' "$ROOT/project.yml" | sed -nE 's/^[[:space:]]*exactVersion:[[:space:]]*"?([0-9.]+)"?.*$/\1/p')"
  [[ -n "$pinned" ]] || fail "project.yml の Sparkle に exactVersion がありません"
  grep -q "exactVersion: \"$pinned\"" "$ROOT/docs/release.md" || fail "docs/release.md に Sparkle の版（$pinned）の説明がありません"
}

# プライバシーポリシーが書いているキーチェーンの項目を、アプリが作らないまま出さない
test_trial_keychain_problem() {
  load_release
  local root="$TEST_TMP/project" service
  service="$(sed -nE 's/.*static let service = "([^"]+)".*/\1/p' "$ROOT/Packages/NonetKit/Sources/NonetCore/Licensing/TrialRecordKeychain.swift")"
  [[ -n "$service" ]] || fail "キーチェーンの項目のサービス名を読めません"
  grep -qF "service=\"$service\"" "$ROOT/scripts/release.sh" || fail "release.sh のサービス名が TrialRecordKeychain.swift（$service）と違います"
  mkdir -p "$root/App" "$root/docs"
  assert_eq "" "$(trial_keychain_problem "$TEST_TMP/none")" "App/ が無い（テスト用の偽のリポジトリ）"
  printf 'storage: UserDefaultsLicenseStorage()\n' >"$root/App/AppDelegate.swift"
  assert_eq "" "$(trial_keychain_problem "$root")" "ポリシーがキーチェーンを書いていない"
  printf 'ログインキーチェーンの項目（%s）\n' "$service" >"$root/docs/privacy.md"
  assert_contains "$(trial_keychain_problem "$root")" "App/ が試用の記録をキーチェーンに置いていません"
  printf 'storage: UserDefaultsLicenseStorage(keychain: SystemTrialRecordKeychain())\n' >"$root/App/AppDelegate.swift"
  assert_eq "" "$(trial_keychain_problem "$root")"
}

test_preflight_stops_when_the_app_does_not_write_the_trial_keychain() {
  prepare_release
  mkdir -p "$REPO/App" "$REPO/docs"
  printf 'storage: UserDefaultsLicenseStorage()\n' >"$REPO/App/AppDelegate.swift"
  printf '（com.iam74k4.Nonet.license.trial）\n' >"$REPO/docs/privacy.md"
  run "$REPO/scripts/release.sh" --dry-run 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "App/ が試用の記録をキーチェーンに置いていません"
  assert_not_called "xcodebuild"
}

test_config_problems_reports_missing_file() {
  load_release
  assert_contains "$(config_problems "$TEST_TMP/none.xcconfig")" "がありません"
}

test_ed25519_public_key_format() {
  load_release
  is_ed25519_public_key "$TEST_SPARKLE_KEY" || fail "標準の base64 を拒否"
  is_ed25519_public_key "abcdefghijklmnopqrstuvwxyz-_ABCDEFGHIJKLMNO" || fail "URL 安全な base64 を拒否"
  ! is_ed25519_public_key "AAAA" || fail "短すぎる鍵を受け付けた"
  ! is_ed25519_public_key "${TEST_SPARKLE_KEY}AAAA" || fail "長すぎる鍵を受け付けた"
  ! is_ed25519_public_key "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==" || fail "32 バイトでない鍵を受け付けた"
}

# Debug ビルド（開発用）は、同じ bundle ID の製品版と同じ Mac で動くので、本番の appcast を見に行ってはいけない。
# Debug だけ NONET_APPCAST_URL を空にする（Info.plist の SUFeedURL が空になり、アプリは Sparkle を動かさず、
# メニューの「アップデートを確認」も「アップデートがあります…」の印も出ない）。Release は xcconfig の値のまま
test_debug_builds_do_not_check_for_updates() {
  # shellcheck source=../lib/common.sh
  source "$ROOT/scripts/lib/common.sh"
  local target debug release
  target="$(sed -n '/^targets:/,/^schemes:/p' "$ROOT/project.yml")"
  debug="$(sed -n '/^        Debug:$/,/^        Release:$/p' <<<"$target")"
  release="$(sed -n '/^        Release:$/,$p' <<<"$target")"
  [[ -n "$debug" && -n "$release" ]] || fail "project.yml の Nonet ターゲットに Debug と Release の設定がありません"
  assert_contains "$debug" '          NONET_APPCAST_URL: ""' "Debug の NONET_APPCAST_URL を空にする"
  assert_not_contains "$release" "NONET_" "Release は Config/Nonet.xcconfig の値のまま（Release で販売用の値を上書きしない）"
  # 両方の構成が同じ xcconfig を読む。販売用の値は、このファイルだけで決める
  grep -qx '  Debug: Config/Nonet.xcconfig' "$ROOT/project.yml" || fail "Debug が Config/Nonet.xcconfig を読んでいません"
  grep -qx '  Release: Config/Nonet.xcconfig' "$ROOT/project.yml" || fail "Release が Config/Nonet.xcconfig を読んでいません"
  # 空にすると効く仕組み: Info.plist の SUFeedURL が NONET_APPCAST_URL で、空なら配信先なしとして Sparkle を作らない
  assert_contains "$(cat "$ROOT/project.yml")" 'SUFeedURL: $(NONET_APPCAST_URL)'
  assert_contains "$(cat "$ROOT/App/Info.plist")" '<string>$(NONET_APPCAST_URL)</string>'
  assert_contains "$(cat "$ROOT/App/AppInfo.swift")" 'string("SUFeedURL") != nil && string("SUPublicEDKey") != nil'
  assert_contains "$(cat "$ROOT/App/UpdaterController.swift")" 'if AppInfo.hasUpdateFeed {'
  assert_contains "$(cat "$ROOT/App/UpdaterController.swift")" 'var isAvailable: Bool { controller != nil }'
  assert_contains "$(cat "$ROOT/App/AppDelegate.swift")" 'updater.isAvailable ?'
  # xcconfig の値そのものは、Debug 用に変えない（release.sh と publish.sh が読む）
  assert_contains "$(xcconfig_value "$ROOT/Config/Nonet.xcconfig" NONET_APPCAST_URL)" "https://"
}

# MARK: - 小さな関数

test_project_team_id() {
  # shellcheck source=../lib/common.sh
  source "$ROOT/scripts/lib/common.sh"
  printf 'settings:\n  base:\n    DEVELOPMENT_TEAM: NL9ZXK2SGR\n' >"$TEST_TMP/a.yml"
  printf 'settings:\n  base:\n    DEVELOPMENT_TEAM: "AB12CD34EF"\n' >"$TEST_TMP/b.yml"
  printf 'name: Nonet\n' >"$TEST_TMP/c.yml"
  assert_eq "NL9ZXK2SGR" "$(project_team_id "$TEST_TMP/a.yml")"
  assert_eq "AB12CD34EF" "$(project_team_id "$TEST_TMP/b.yml")"
  assert_eq "" "$(project_team_id "$TEST_TMP/c.yml")"
  assert_eq "NL9ZXK2SGR" "$(project_team_id "$ROOT/project.yml")" "本物の project.yml"
}

test_developer_id_identity_matches_team() {
  use_fakes
  # shellcheck source=../lib/common.sh
  source "$ROOT/scripts/lib/common.sh"
  assert_eq "2222222222222222222222222222222222222222" "$(developer_id_identity "$TEST_TEAM")"
  assert_eq "" "$(developer_id_identity "OTHERTEAM1")" "別のチーム"
  export FAKE_IDENTITIES=""
  assert_eq "" "$(developer_id_identity "$TEST_TEAM")" "証明書が無い"
}

test_appcast_latest_build() {
  load_release
  write_appcast "$TEST_TMP/a.xml" 3 12 7
  assert_eq "12" "$(appcast_latest_build "$TEST_TMP/a.xml")"
  printf '<enclosure sparkle:version="40" url="x"/>\n<enclosure sparkle:version="9"/>\n' >"$TEST_TMP/b.xml"
  assert_eq "40" "$(appcast_latest_build "$TEST_TMP/b.xml")" "古い書き方（属性）"
  write_appcast "$TEST_TMP/c.xml"
  assert_eq "" "$(appcast_latest_build "$TEST_TMP/c.xml")" "項目が無い"
  assert_eq "" "$(appcast_latest_build "$TEST_TMP/none.xml")" "ファイルが無い"
}

test_download_url_prefix() {
  load_release
  assert_eq "https://nonet.test/updates/" "$(download_url_prefix "https://nonet.test/updates/appcast.xml")"
  assert_eq "https://cdn.nonet.test/dl/" "$(download_url_prefix "https://nonet.test/appcast.xml" "https://cdn.nonet.test/dl")"
  assert_eq "https://cdn.nonet.test/dl/" "$(download_url_prefix "https://nonet.test/appcast.xml" "https://cdn.nonet.test/dl/")"
}

test_url_file_name() {
  load_release
  assert_eq "appcast.xml" "$(url_file_name "https://nonet.test/updates/appcast.xml")"
  assert_eq "nonet.xml" "$(url_file_name "https://nonet.test/updates/nonet.xml?v=2")" "? から後ろ"
  assert_eq "feed.xml" "$(url_file_name "https://nonet.test/feed.xml#top")" "# から後ろ"
  assert_eq "" "$(url_file_name "https://nonet.test/updates/")" "名前が無い"
}

test_is_appcast_file() {
  load_release
  write_appcast "$TEST_TMP/a.xml" 1
  is_appcast_file "$TEST_TMP/a.xml" || fail "appcast を見分けられない"
  printf '<!doctype html>\n<html><body>Nonet</body></html>\n' >"$TEST_TMP/page.html"
  ! is_appcast_file "$TEST_TMP/page.html" || fail "HTML のページを appcast と判定した"
  ! is_appcast_file "$TEST_TMP/none.xml" || fail "無いファイルを appcast と判定した"
}

# 本物の git で、リリースノートだけが確認から外れること
test_uncommitted_changes_ignore_only_the_release_notes() {
  if ! command -v git >/dev/null 2>&1; then
    printf 'git が無いので飛ばしました\n'
    return 0
  fi
  load_release
  # 使う人の git の設定（署名・フックなど）に左右されないようにする
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  local repo="$TEST_TMP/git-repo"
  mkdir -p "$repo/notes" "$TEST_TMP/elsewhere"
  printf 'a\n' >"$repo/tracked.txt"
  git -C "$repo" init -q
  git -C "$repo" add tracked.txt
  git -C "$repo" -c user.name=test -c user.email=test@nonet.test -c commit.gpgsign=false -c core.hooksPath=/dev/null \
    commit -q -m init
  printf '# 1.2.0\n' >"$repo/notes/1.2.0.md"
  printf '# 1.2.0\n' >"$TEST_TMP/elsewhere/1.2.0.md"

  assert_eq "" "$(uncommitted_changes "$repo" "$repo/notes/1.2.0.md")" "未追跡のフォルダの中のノート"
  assert_eq "" "$(cd "$repo/notes" && uncommitted_changes "$repo" "1.2.0.md")" "相対パスのノート"
  assert_contains "$(uncommitted_changes "$repo" "")" "notes/" "ノートを渡さなければ数える"
  assert_contains "$(uncommitted_changes "$repo" "$TEST_TMP/elsewhere/1.2.0.md")" "notes/" "リポジトリの外のノートは関係ない"

  # 未追跡のフォルダは git がまとめて「?? notes/」と出す
  printf 'draft\n' >"$repo/notes/other.md"
  assert_contains "$(uncommitted_changes "$repo" "$repo/notes/1.2.0.md")" "?? notes/" "ほかの未追跡のファイル"
  rm "$repo/notes/other.md"
  printf 'b\n' >>"$repo/tracked.txt"
  assert_contains "$(uncommitted_changes "$repo" "$repo/notes/1.2.0.md")" "tracked.txt" "変更したファイル"
}

# .claude/ は手元の道具の状態を置く場所。未追跡のファイルだけ、コミットしていない変更に数えない（本物の git で確かめる）
test_uncommitted_changes_ignore_untracked_claude_files() {
  if ! command -v git >/dev/null 2>&1; then
    printf 'git が無いので飛ばしました\n'
    return 0
  fi
  load_release
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  local repo="$TEST_TMP/git-repo"
  mkdir -p "$repo/.claude/hooks" "$repo/.claude/worktrees/agent-1" "$repo/sub/.claude"
  printf 'a\n' >"$repo/tracked.txt"
  printf 'hook\n' >"$repo/.claude/hooks/tracked.sh"
  git -C "$repo" init -q
  git -C "$repo" add tracked.txt .claude/hooks/tracked.sh
  git -C "$repo" -c user.name=test -c user.email=test@nonet.test -c commit.gpgsign=false -c core.hooksPath=/dev/null \
    commit -q -m init
  printf 'x\n' >"$repo/.claude/settings.local.json"
  printf 'x\n' >"$repo/.claude/worktrees/agent-1/file"
  assert_contains "$(git -C "$repo" status --porcelain)" "?? .claude/" "git は数える（このテストの前提）"
  assert_eq "" "$(uncommitted_changes "$repo" "")" "未追跡の .claude/ のファイル"

  # 追跡しているファイルの変更や、ほかの未追跡のファイルは数える
  printf 'more\n' >>"$repo/.claude/hooks/tracked.sh"
  assert_contains "$(uncommitted_changes "$repo" "")" " M .claude/hooks/tracked.sh" "追跡している .claude/ のファイルの変更"
  git -C "$repo" checkout -q -- .claude/hooks/tracked.sh
  assert_eq "" "$(uncommitted_changes "$repo" "")"
  printf 'x\n' >"$repo/other.txt"
  assert_contains "$(uncommitted_changes "$repo" "")" "?? other.txt" "ほかの未追跡のファイル"
  rm "$repo/other.txt"
  # リポジトリの直下の .claude/ だけ（ほかの場所の .claude/ は別のもの）
  printf 'x\n' >"$repo/sub/.claude/file"
  assert_contains "$(uncommitted_changes "$repo" "")" "?? sub/" "サブフォルダの .claude/"
}

# MARK: - 準備の確認

test_preflight_lists_all_problems_before_building() {
  use_fakes
  make_fake_repo
  printf '// 空\n' >"$REPO/Config/Nonet.xcconfig"
  export FAKE_IDENTITIES=""
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "リリースの準備が足りません"
  assert_contains "$OUT" "Developer ID Application 証明書がキーチェーンにありません"
  assert_contains "$OUT" "NONET_APPCAST_URL が空です"
  assert_contains "$OUT" "NONET_SPARKLE_PUBLIC_KEY が空です"
  assert_contains "$OUT" "NONET_PURCHASE_URL が空です"
  assert_contains "$OUT" "NONET_LICENSE_PUBLIC_KEY が空です"
  assert_contains "$OUT" "NONET_NOTARY_PROFILE が設定されていません"
  assert_not_called "xcodegen"
  assert_not_called "xcodebuild"
}

test_preflight_checks_notary_profile() {
  prepare_release
  export FAKE_NOTARY_HISTORY_STATUS=1
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "プロファイル「nonet-test-profile」で認証できません"
  assert_called "xcrun notarytool history --keychain-profile nonet-test-profile"
  assert_not_called "xcodebuild"
}

test_dirty_tree_needs_allow_dirty() {
  prepare_release
  export FAKE_GIT_STATUS=" M App/AppDelegate.swift"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "--allow-dirty"
  run "$REPO/scripts/release.sh" --allow-dirty 1.2.0 42
  assert_status 0
  assert_contains "$OUT" "コミットしていない変更があります"
}

# 始めに、ビルドするコミット・ブランチ・コミットしていない変更の有無を出す（準備の確認より前に）
test_release_shows_the_commit_branch_and_tree_state_first() {
  prepare_release
  export FAKE_GIT_HEAD="89abcdef0123456789abcdef0123456789abcdef"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 0
  assert_contains "$OUT" "コミット:     89abcdef0123456789abcdef0123456789abcdef"
  assert_contains "$OUT" "ブランチ:     main"
  assert_contains "$OUT" "作業ツリー:   きれい"
  assert_contains "$OUT" "push:         済み（origin/main）"
  assert_called "git -C $REPO rev-parse HEAD"
  assert_contains "$(grep '^==> ' <<<"$OUT" | head -n 1)" "ビルドするもの（Nonet 1.2.0、ビルド 42）" "最初に出す見出し"
}

test_release_shows_which_files_are_uncommitted() {
  prepare_release
  export FAKE_GIT_STATUS=" M App/AppDelegate.swift\n?? notes/draft.md"
  run "$REPO/scripts/release.sh" --allow-dirty 1.2.0 42
  assert_status 0
  assert_contains "$OUT" "作業ツリー:   コミットしていない変更があります（2 件）"
  assert_contains "$OUT" " M App/AppDelegate.swift"
  assert_contains "$OUT" "?? notes/draft.md"
}

# .claude/ の中の未追跡のファイルは、コミットしていない変更に数えない。追跡しているファイルの変更は数える
test_untracked_files_under_dot_claude_are_not_dirty() {
  prepare_release
  export FAKE_GIT_STATUS="?? .claude/\n?? .claude/worktrees/agent-1/"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 0
  assert_contains "$OUT" "作業ツリー:   きれい"
  assert_not_contains "$OUT" "コミットしていない変更があります"

  export FAKE_GIT_STATUS="?? .claude/\n M project.yml\n M .claude/settings.json"
  run "$REPO/scripts/release.sh" 1.2.1 43
  assert_status 1
  assert_contains "$OUT" "コミットしていない変更があります（2 件）"
  assert_contains "$OUT" "コミットしてから出すか、--allow-dirty を付けてください"
  assert_not_contains "$OUT" "?? .claude/"
}

# 本番は main からだけ出せる。--allow-branch で外せる。dry run は止まらない
test_release_needs_the_main_branch() {
  prepare_release
  export FAKE_GIT_BRANCH="feature/pricing"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "ブランチ:     feature/pricing"
  assert_contains "$OUT" "リリースの準備が足りません"
  assert_contains "$OUT" "ブランチが main ではありません（いまは feature/pricing）"
  assert_contains "$OUT" "--allow-branch を付けてください"
  assert_not_called "xcodegen"
  assert_not_called "xcodebuild"

  run "$REPO/scripts/release.sh" --dry-run 1.2.1 42
  assert_status 0
  assert_contains "$OUT" "ブランチが main ではありません（いまは feature/pricing）。dry run なので続けますが、本番ではここで止まります"

  run "$REPO/scripts/release.sh" --allow-branch 1.2.0 42
  assert_status 0
  assert_contains "$OUT" "main ではないブランチ feature/pricing から出します（--allow-branch）"
  assert_contains "$OUT" "できました: Nonet 1.2.0（ビルド 42）"
}

test_release_from_a_detached_head_needs_allow_branch() {
  prepare_release
  export FAKE_GIT_BRANCH=""
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "ブランチ:     （どのブランチでもありません。detached HEAD）"
  assert_contains "$OUT" "ブランチが main ではありません（いまは detached HEAD）"
  assert_not_called "xcodebuild"
  run "$REPO/scripts/release.sh" --allow-branch 1.2.0 42
  assert_status 0
}

# ブランチと変更のどちらも、それぞれのオプションが要る（片方のオプションで、もう片方は通らない）
test_branch_and_dirty_problems_are_listed_together() {
  prepare_release
  export FAKE_GIT_BRANCH="topic" FAKE_GIT_STATUS=" M project.yml"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "コミットしていない変更があります。コミットしてから出すか、--allow-dirty を付けてください"
  assert_contains "$OUT" "ブランチが main ではありません（いまは topic）"
  run "$REPO/scripts/release.sh" --allow-dirty 1.2.0 42
  assert_status 1
  assert_not_contains "$OUT" "コミットしてから出すか"
  assert_contains "$OUT" "ブランチが main ではありません"
  run "$REPO/scripts/release.sh" --allow-branch 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "コミットしてから出すか"
  assert_not_contains "$OUT" "ブランチが main ではありません"
  run "$REPO/scripts/release.sh" --allow-branch --allow-dirty 1.2.0 42
  assert_status 0
  assert_called "xcodebuild archive"
}

# まだ push していないコミットは警告するだけ（リモートの情報は手元にあるものだけを見る。ネットワークは使わない）
test_release_warns_when_the_commit_is_not_pushed() {
  prepare_release
  export FAKE_GIT_REMOTE_BRANCHES=""
  run "$REPO/scripts/release.sh" --dry-run 1.2.0 42
  assert_status 0
  assert_contains "$OUT" "push:         このコミットを含むリモートのブランチがありません"
  assert_called "git -C $REPO branch -r --contains HEAD"
  assert_not_called "git -C $REPO fetch"
  assert_not_called "git -C $REPO ls-remote"
  export FAKE_GIT_NO_REMOTE=1
  run "$REPO/scripts/release.sh" --dry-run 1.2.0 42
  assert_status 0
  assert_contains "$OUT" "push:         リモートがありません"
}

test_notes_must_exist_and_be_supported() {
  prepare_release
  run "$REPO/scripts/release.sh" --notes "$TEST_TMP/none.md" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "リリースノートがありません"
  printf 'notes' >"$TEST_TMP/notes.rtf"
  run "$REPO/scripts/release.sh" --notes "$TEST_TMP/notes.rtf" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" ".html / .md / .txt"
}

# MARK: - 全体の流れ

test_release_runs_the_whole_pipeline_in_order() {
  prepare_release
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 0
  local work="$REPO/build/release/1.2.0"
  assert_called_in_order \
    "xcodegen generate --spec $REPO/project.yml" \
    "xcodebuild -resolvePackageDependencies -project $REPO/Nonet.xcodeproj -scheme Nonet -derivedDataPath $REPO/build/DerivedData" \
    "generate_keys --account ed25519 -p" \
    "curl -sSL --max-time 30 -o $work/published-appcast.xml -w %{http_code} $TEST_APPCAST_URL" \
    "xcodebuild archive -project $REPO/Nonet.xcodeproj -scheme Nonet -configuration Release" \
    "export method=developer-id team=$TEST_TEAM" \
    "codesign --verify --deep --strict --verbose=2 $work/export/Nonet.app" \
    "codesign -dvv $work/export/Nonet.app" \
    "xcrun notarytool submit $work/Nonet.zip --keychain-profile nonet-test-profile --wait --timeout 1h --output-format plist" \
    "xcrun stapler staple $work/export/Nonet.app" \
    "xcrun stapler validate $work/export/Nonet.app" \
    "spctl -a -vv -t execute $work/export/Nonet.app" \
    "hdiutil create -volname Nonet -srcfolder $work/dmg" \
    "hdiutil verify $work/Nonet-1.2.0.dmg" \
    "codesign --force --sign 2222222222222222222222222222222222222222 --timestamp $work/Nonet-1.2.0.dmg" \
    "xcrun notarytool submit $work/Nonet-1.2.0.dmg --keychain-profile nonet-test-profile --wait" \
    "xcrun stapler staple $work/Nonet-1.2.0.dmg" \
    "spctl -a -vv -t open --context context:primary-signature $work/Nonet-1.2.0.dmg" \
    "generate_appcast --account ed25519 --download-url-prefix https://nonet.test/updates/ -o $RELEASES/appcast.xml $RELEASES"
  assert_called "MARKETING_VERSION=1.2.0 CURRENT_PROJECT_VERSION=42 DEVELOPMENT_TEAM=$TEST_TEAM CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=Developer ID Application ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp"
  assert_called "hdiutil srcfolder: Applications Nonet.app"
  assert_called "hdiutil applications-link: /Applications"
  assert_file "$RELEASES/Nonet-1.2.0.dmg"
  assert_no_file "$RELEASES/appcast.xml.download"
  assert_contains "$OUT" "公開中の appcast を取り込みました: $TEST_APPCAST_URL"
  assert_contains "$(cat "$RELEASES/appcast.xml")" "<sparkle:version>41</sparkle:version>" "公開中の項目を引き継ぐ"
  assert_contains "$(cat "$RELEASES/appcast.xml")" "<sparkle:version>42</sparkle:version>"
  assert_not_contains "$OUT" "ファイル名を"
  assert_contains "$OUT" "できました: Nonet 1.2.0（ビルド 42）"
  assert_contains "$OUT" "https://nonet.test/updates/Nonet-1.2.0.dmg"
  assert_contains "$OUT" "scripts/publish.sh 1.2.0"
  assert_contains "$OUT" "git tag -a v1.2.0"
}

test_dry_run_skips_notarization_and_leaves_releases_alone() {
  prepare_release
  unset NONET_NOTARY_PROFILE
  export FAKE_SPCTL_STATUS=3
  write_appcast "$RELEASES/appcast.xml" 10
  export FAKE_CURL_BODY="$RELEASES/appcast.xml"
  local before
  before="$(cat "$RELEASES/appcast.xml")"
  run "$REPO/scripts/release.sh" --dry-run 1.2.0 42
  assert_status 0
  assert_not_called "notarytool"
  assert_not_called "stapler"
  # dry run でも公開中の appcast と比べる（本番の前に気づける）
  assert_called "curl -sSL --max-time 30 -o $REPO/build/release/1.2.0/published-appcast.xml"
  assert_contains "$OUT" "手元の appcast は公開中のものと同じです"
  assert_contains "$OUT" "--dry-run では正常"
  assert_contains "$OUT" "この DMG は配らないでください"
  assert_eq "$before" "$(cat "$RELEASES/appcast.xml")" "公開用の appcast は変わらない"
  assert_no_file "$RELEASES/Nonet-1.2.0.dmg"
  local preview="$REPO/build/release/1.2.0/appcast-preview"
  assert_file "$preview/Nonet-1.2.0.dmg"
  assert_contains "$(cat "$preview/appcast.xml")" "<sparkle:version>10</sparkle:version>"
  assert_contains "$(cat "$preview/appcast.xml")" "<sparkle:version>42</sparkle:version>"
}

test_build_number_must_increase() {
  prepare_release
  write_appcast "$RELEASES/appcast.xml" 41 42
  export FAKE_CURL_BODY="$RELEASES/appcast.xml"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "ビルド番号 42 は、appcast に載っている最大の 42 より大きくしてください"
  assert_not_called "xcodebuild archive"
}

test_local_appcast_must_have_every_published_build() {
  prepare_release
  # 別の Mac のフォルダ: 公開中の 42 を知らない
  write_appcast "$RELEASES/appcast.xml" 41
  write_appcast "$TEST_TMP/published.xml" 41 42
  export FAKE_CURL_BODY="$TEST_TMP/published.xml"
  local before
  before="$(cat "$RELEASES/appcast.xml")"
  run "$REPO/scripts/release.sh" 1.3.0 42
  assert_status 1
  assert_contains "$OUT" "手元の appcast に、公開中のビルド 42 がありません: $RELEASES/appcast.xml"
  assert_contains "$OUT" "取ってきた公開中の appcast: $REPO/build/release/1.3.0/published-appcast.xml"
  assert_contains "$OUT" "--force-local-appcast"
  assert_not_contains "$OUT" "予期しないエラー"
  assert_not_called "xcodebuild archive"
  assert_eq "$before" "$(cat "$RELEASES/appcast.xml")" "手元の appcast は変えない"
  assert_no_file "$RELEASES/appcast.xml.download"

  # 手元のものを消せば、公開中のものを取ってくる
  rm "$RELEASES/appcast.xml"
  run "$REPO/scripts/release.sh" 1.3.0 43
  assert_status 0
  assert_eq "3" "$(grep -c '<item>' "$RELEASES/appcast.xml")" "41・42・43"
}

# アップロードしてすぐの次のリリースで、CDN が前の appcast を返した（手元の方がビルドが多い）
test_local_appcast_ahead_of_the_published_one_continues() {
  prepare_release
  write_appcast "$RELEASES/appcast.xml" 41 42
  write_appcast "$TEST_TMP/published.xml" 41
  export FAKE_CURL_BODY="$TEST_TMP/published.xml"
  run "$REPO/scripts/release.sh" 1.2.1 43
  assert_status 0
  assert_contains "$OUT" "手元の appcast には、公開中のものに無いビルド 42 があります。手元のものを使います"
  assert_contains "$OUT" "CDN などが前の appcast をまだ返している"
  assert_eq "3" "$(grep -c '<item>' "$RELEASES/appcast.xml")" "41・42・43"
}

test_whitespace_changes_by_the_host_are_ignored() {
  prepare_release
  write_appcast "$RELEASES/appcast.xml" 41
  # ホスティングが改行と字下げを書き換えた
  sed -e 's/></>\
  </g' "$RELEASES/appcast.xml" >"$TEST_TMP/published.xml"
  export FAKE_CURL_BODY="$TEST_TMP/published.xml"
  ! cmp -s "$RELEASES/appcast.xml" "$TEST_TMP/published.xml" || fail "テストの appcast が同じになっている"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 0
  assert_contains "$OUT" "手元の appcast は公開中のものと同じです（空白の違いだけ）"
}

test_same_builds_with_different_items_stop() {
  prepare_release
  write_appcast "$RELEASES/appcast.xml" 41
  # 公開中のものはサーバーで直した（DMG の URL を差し替えたなど）
  sed 's#<item>#<item><title>Nonet 1.1.0</title>#' "$RELEASES/appcast.xml" >"$TEST_TMP/published.xml"
  export FAKE_CURL_BODY="$TEST_TMP/published.xml"
  local before
  before="$(cat "$RELEASES/appcast.xml")"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "手元の appcast と公開中のものは、同じビルドの項目の中身が違います: $RELEASES/appcast.xml"
  assert_not_called "xcodebuild archive"
  assert_eq "$before" "$(cat "$RELEASES/appcast.xml")" "手元の appcast は変えない"
}

test_appcast_builds() {
  load_release
  write_appcast "$TEST_TMP/a.xml" 3 12 7 12
  assert_eq "3 7 12" "$(appcast_builds "$TEST_TMP/a.xml" | tr '\n' ' ' | sed 's/ $//')"
  write_appcast "$TEST_TMP/b.xml" 7 13
  assert_eq "3 12" "$(appcast_builds_missing "$TEST_TMP/a.xml" "$TEST_TMP/b.xml")"
  assert_eq "13" "$(appcast_builds_missing "$TEST_TMP/b.xml" "$TEST_TMP/a.xml")"
  assert_eq "3 7 12" "$(appcast_builds_missing "$TEST_TMP/a.xml" "$TEST_TMP/none.xml")"
  assert_eq "" "$(appcast_builds_missing "$TEST_TMP/none.xml" "$TEST_TMP/a.xml")"
}

test_force_local_appcast_skips_the_comparison() {
  prepare_release
  write_appcast "$RELEASES/appcast.xml" 41
  write_appcast "$TEST_TMP/published.xml" 40
  export FAKE_CURL_BODY="$TEST_TMP/published.xml"
  run "$REPO/scripts/release.sh" --force-local-appcast 1.2.0 42
  assert_status 0
  assert_not_called "curl"
  assert_contains "$OUT" "--force-local-appcast: 公開中の appcast と比べずに、手元の $RELEASES/appcast.xml を使います"
  assert_contains "$(cat "$RELEASES/appcast.xml")" "<sparkle:version>41</sparkle:version>"
  assert_not_contains "$(cat "$RELEASES/appcast.xml")" "<sparkle:version>40</sparkle:version>"

  # 手元に無ければ、付けていても公開中のものを取ってくる
  rm "$RELEASES/appcast.xml"
  run "$REPO/scripts/release.sh" --force-local-appcast 1.2.1 43
  assert_status 0
  assert_called "curl -sSL"
  assert_contains "$(cat "$RELEASES/appcast.xml")" "<sparkle:version>40</sparkle:version>"
}

test_local_appcast_without_a_published_one_needs_a_flag() {
  prepare_release
  no_published_appcast
  write_appcast "$RELEASES/appcast.xml" 1
  run "$REPO/scripts/release.sh" 1.0.1 2
  assert_status 1
  assert_contains "$OUT" "公開中の appcast が見つかりません（HTTP 404）"
  assert_not_called "xcodebuild archive"
  # 初めてのリリースの appcast をまだアップロードしていない
  run "$REPO/scripts/release.sh" --first-release 1.0.1 2
  assert_status 0
  assert_contains "$OUT" "手元の appcast を引き継ぎます"
  assert_eq "2" "$(grep -c '<item>' "$RELEASES/appcast.xml")" "1・2"
}

test_published_appcast_is_fetched_when_missing() {
  prepare_release
  write_appcast "$TEST_TMP/published.xml" 50
  export FAKE_CURL_BODY="$TEST_TMP/published.xml"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "最大の 50 より大きく"
  run "$REPO/scripts/release.sh" 1.2.0 51
  assert_status 0
  assert_contains "$(cat "$RELEASES/appcast.xml")" "<sparkle:version>50</sparkle:version>"
  assert_contains "$(cat "$RELEASES/appcast.xml")" "<sparkle:version>51</sparkle:version>"
}

# dry run は何も公開しないので、公開中の appcast を取れなくても（ネットワークが無いなど）続ける
test_dry_run_continues_when_the_published_appcast_cannot_be_fetched() {
  prepare_release
  write_appcast "$RELEASES/appcast.xml" 41
  export FAKE_CURL_STATUS=6
  run "$REPO/scripts/release.sh" --dry-run 1.2.0 42
  assert_status 0
  assert_contains "$OUT" "公開中の appcast を取得できませんでした（curl の終了コード 6）"
  assert_contains "$OUT" "dry run なので、公開中のものと比べずに続けます"
  assert_contains "$(cat "$REPO/build/release/1.2.0/appcast-preview/appcast.xml")" "<sparkle:version>41</sparkle:version>"
  unset FAKE_CURL_STATUS
  export FAKE_CURL_HTTP_CODE=503
  run "$REPO/scripts/release.sh" --dry-run 1.2.0 42
  assert_status 0
  assert_contains "$OUT" "公開中の appcast を取得できませんでした（HTTP 503）"
}

test_network_error_while_fetching_appcast_stops() {
  prepare_release
  export FAKE_CURL_STATUS=6
  run "$REPO/scripts/release.sh" --first-release 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "公開中の appcast を取得できませんでした（curl の終了コード 6）: $TEST_APPCAST_URL"
  assert_not_contains "$OUT" "予期しないエラー"
  assert_not_called "xcodebuild archive"
  assert_no_file "$RELEASES/appcast.xml.download"
}

# 403・429・5xx を「まだ無い」と取り違えると、過去の項目の消えた appcast を公開してしまう
test_http_errors_while_fetching_appcast_stop() {
  prepare_release
  local code
  for code in 401 403 429 500 503; do
    : >"$FAKE_LOG"
    export FAKE_CURL_HTTP_CODE="$code"
    run "$REPO/scripts/release.sh" --first-release 1.2.0 42
    assert_status 1
    assert_contains "$OUT" "公開中の appcast を取得できませんでした（HTTP $code）: $TEST_APPCAST_URL"
    assert_not_contains "$OUT" "新しく作ります"
    assert_not_contains "$OUT" "予期しないエラー"
    assert_not_called "xcodebuild archive"
    assert_no_file "$RELEASES/appcast.xml"
    assert_no_file "$RELEASES/appcast.xml.download"
  done
}

test_missing_appcast_needs_first_release() {
  prepare_release
  no_published_appcast
  local code
  for code in 404 410; do
    export FAKE_CURL_HTTP_CODE="$code"
    run "$REPO/scripts/release.sh" 1.2.0 42
    assert_status 1
    assert_contains "$OUT" "公開中の appcast が見つかりません（HTTP $code）: $TEST_APPCAST_URL"
    assert_contains "$OUT" "初めてのリリースなら --first-release を付けてください"
    assert_not_called "xcodebuild archive"
    assert_no_file "$RELEASES/appcast.xml"
    assert_no_file "$RELEASES/appcast.xml.download"
  done
  # dry run でも同じところで止まる（本番の前に気づける）
  run "$REPO/scripts/release.sh" --dry-run 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "--first-release を付けてください"
}

test_first_release_creates_a_new_appcast() {
  prepare_release
  no_published_appcast
  run "$REPO/scripts/release.sh" --first-release 1.0.0 1
  assert_status 0
  assert_contains "$OUT" "公開中の appcast はまだありません（HTTP 404）。初めてのリリースとして新しく作ります"
  assert_eq "1" "$(grep -c '<item>' "$RELEASES/appcast.xml")" "新しい項目だけ"
  assert_contains "$(cat "$RELEASES/appcast.xml")" "<sparkle:version>1</sparkle:version>"
  assert_no_file "$RELEASES/appcast.xml.download"
}

test_first_release_flag_keeps_a_published_appcast() {
  prepare_release
  run "$REPO/scripts/release.sh" --first-release 1.2.0 42
  assert_status 0
  assert_contains "$OUT" "--first-release を付けていますが、appcast にはすでにビルド 41 までの項目があります"
  assert_contains "$(cat "$RELEASES/appcast.xml")" "<sparkle:version>41</sparkle:version>"
  assert_contains "$(cat "$RELEASES/appcast.xml")" "<sparkle:version>42</sparkle:version>"
}

test_html_page_instead_of_appcast_stops() {
  prepare_release
  printf '<!doctype html>\n<html><body>Nonet</body></html>\n' >"$TEST_TMP/index.html"
  export FAKE_CURL_BODY="$TEST_TMP/index.html"
  run "$REPO/scripts/release.sh" --first-release 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "公開中の appcast の中身が appcast（RSS）ではありません: $TEST_APPCAST_URL"
  assert_not_called "xcodebuild archive"
  assert_no_file "$RELEASES/appcast.xml"
  assert_no_file "$RELEASES/appcast.xml.download"
}

# generate_appcast は -o が無いと SUFeedURL の名前（ここでは nonet.xml）で読み書きする
test_feed_url_not_named_appcast_xml() {
  prepare_release
  cat >>"$REPO/Config/Nonet.xcconfig" <<'EOF'
NONET_APPCAST_URL = https:/$()/nonet.test/updates/nonet.xml
EOF
  export FAKE_PLIST_FEED="https://nonet.test/updates/nonet.xml"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 0
  assert_called "curl -sSL --max-time 30 -o $REPO/build/release/1.2.0/published-appcast.xml -w %{http_code} https://nonet.test/updates/nonet.xml"
  assert_called "generate_appcast wrote: appcast.xml"
  assert_no_file "$RELEASES/nonet.xml"
  assert_contains "$(cat "$RELEASES/appcast.xml")" "<sparkle:version>41</sparkle:version>"
  assert_contains "$(cat "$RELEASES/appcast.xml")" "<sparkle:version>42</sparkle:version>"
  assert_contains "$OUT" "appcast.xml を https://nonet.test/updates/nonet.xml に（ファイル名を nonet.xml にする）"

  # 次のリリースも、手元の appcast.xml を引き継ぐ（前の appcast はアップロード済み）
  export FAKE_CURL_BODY="$RELEASES/appcast.xml"
  run "$REPO/scripts/release.sh" 1.2.1 43
  assert_status 0
  assert_eq "3" "$(grep -c '<item>' "$RELEASES/appcast.xml")" "41・42・43"
  assert_no_file "$RELEASES/nonet.xml"
}

test_sparkle_key_must_match_config() {
  prepare_release
  export FAKE_SPARKLE_PUBLIC_KEY="CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC="
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "NONET_SPARKLE_PUBLIC_KEY と違います"
  assert_not_called "xcodebuild archive"
}

test_missing_sparkle_key_stops() {
  prepare_release
  export FAKE_SPARKLE_KEY_MISSING=1
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "Sparkle の秘密鍵がキーチェーンにありません"
  assert_not_contains "$OUT" "予期しないエラー"
}

test_missing_sparkle_tools_stop_with_a_clear_message() {
  prepare_release
  export FAKE_NO_SPARKLE_ARTIFACTS=1
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "Sparkle の generate_appcast が $REPO/build/DerivedData/SourcePackages/artifacts にありません"
  assert_not_contains "$OUT" "予期しないエラー"
  assert_not_called "generate_keys"
}

test_placeholder_detection_is_not_too_eager() {
  load_release
  ! is_placeholder "https://store.nonet.test/buy" || fail "普通の URL を仮の値と判定した"
  ! is_placeholder "https://todoist.nonet.test/buy" || fail "小文字の todo を仮の値と判定した"
  is_placeholder "https://TODO.invalid/buy" || fail "TODO を見逃した"
  is_placeholder "https://example.com/appcast.xml" || fail "example.com を見逃した"
}

test_notarization_rejection_shows_log_and_stops() {
  prepare_release
  export FAKE_NOTARY_STATUS=Invalid
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "公証が通りませんでした（状態: Invalid）: Nonet.zip"
  assert_contains "$OUT" "偽の公証ログ"
  assert_called "xcrun notarytool log 00000000-1111-2222-3333-444444444444 --keychain-profile nonet-test-profile"
  assert_not_called "hdiutil create"
  assert_no_file "$RELEASES/Nonet-1.2.0.dmg"
}

test_gatekeeper_rejection_fails_a_real_release() {
  prepare_release
  export FAKE_SPCTL_STATUS=3
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "Gatekeeper の評価（spctl）に失敗しました"
}

test_archive_failure_shows_the_log() {
  prepare_release
  export FAKE_XCODEBUILD_FAIL_ACTION=archive
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "偽の xcodebuild が archive で失敗しました"
  assert_contains "$OUT" "「アーカイブする（Release、Developer ID、hardened runtime）」に失敗しました"
  assert_contains "$OUT" "$REPO/build/release/1.2.0/archive.log"
  assert_not_contains "$OUT" "予期しないエラー"
  assert_not_called "-exportArchive"
}

test_wrong_info_plist_values_are_caught() {
  prepare_release
  export FAKE_PLIST_FEED="https://wrong.nonet.test/appcast.xml"
  export FAKE_PLIST_LICENSE_KEY=""
  export FAKE_PLIST_SUPPORT_EMAIL="old@nonet.test"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "Info.plist の SUFeedURL が「https://wrong.nonet.test/appcast.xml」です"
  assert_contains "$OUT" "Info.plist の NonetLicensePublicKey が「」です"
  assert_contains "$OUT" "Info.plist の NonetSupportEmail が「old@nonet.test」です（期待: $TEST_SUPPORT_EMAIL）"
  assert_not_called "notarytool submit"
}

test_signature_without_runtime_or_timestamp_is_caught() {
  prepare_release
  export FAKE_CODESIGN_DETAILS="CodeDirectory v=20500 size=1 flags=0x0(none) hashes=1
Authority=Apple Development: Test Developer (ABCDE12345)
TeamIdentifier=OTHERTEAM1"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "export/Nonet.app が Developer ID Application で署名されていません"
  assert_contains "$OUT" "のチーム ID が $TEST_TEAM ではありません"
  assert_contains "$OUT" "セキュアタイムスタンプがありません"
  assert_contains "$OUT" "hardened runtime が有効になっていません"
  assert_not_called "notarytool submit"
}

test_nested_code_must_be_signed_for_notarization() {
  prepare_release
  export FAKE_NESTED_MACHO=1
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 0
  assert_called "codesign -dvv $REPO/build/release/1.2.0/export/Nonet.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"

  export FAKE_CODESIGN_NESTED_DETAILS="Authority=(unavailable)
Signature=adhoc"
  export FAKE_CURL_BODY="$RELEASES/appcast.xml"
  run "$REPO/scripts/release.sh" 1.2.1 43
  assert_status 1
  assert_contains "$OUT" "Sparkle.framework/Versions/B/Autoupdate が Developer ID Application で署名されていません"
}

# 公証はどの実行ファイルにも hardened runtime を求める。Sparkle の書き出しや版上げで中の実行ファイルの runtime が落ちたら、
# 公証に出して待つ前に止まる。dylib（Sparkle 本体）は runtime の対象ではない
test_nested_executables_need_hardened_runtime() {
  prepare_release
  export FAKE_NESTED_MACHO=1
  export FAKE_CODESIGN_NESTED_DETAILS="CodeDirectory v=20500 size=1 flags=0x0(none) hashes=1
Authority=Developer ID Application: Test Developer ($TEST_TEAM)
Timestamp=Oct 30, 2026 at 10:00:00
TeamIdentifier=$TEST_TEAM"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  local executable
  for executable in Autoupdate Updater.app/Contents/MacOS/Updater \
    XPCServices/Downloader.xpc/Contents/MacOS/Downloader XPCServices/Installer.xpc/Contents/MacOS/Installer; do
    assert_contains "$OUT" "Sparkle.framework/Versions/B/$executable で hardened runtime が有効になっていません"
  done
  assert_called "codesign -dvv $REPO/build/release/1.2.0/export/Nonet.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
  assert_not_contains "$OUT" "Versions/B/Sparkle で hardened runtime"
  assert_not_contains "$OUT" "Developer ID Application で署名されていません"
  assert_not_called "notarytool submit"
}

# アプリの中の XPC サービスや、Contents/MacOS のアプリ本体以外の実行ファイルも同じ
test_app_level_helpers_need_hardened_runtime() {
  prepare_release
  local app="$TEST_TMP/Nonet.app"
  export FAKE_CODESIGN_NESTED_DETAILS="CodeDirectory v=20500 size=1 flags=0x2(adhoc) hashes=1
Authority=Developer ID Application: Test Developer ($TEST_TEAM)
Timestamp=Oct 30, 2026 at 10:00:00"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/XPCServices/Helper.xpc/Contents/MacOS"
  cp /usr/bin/true "$app/Contents/MacOS/Nonet"
  cp /usr/bin/true "$app/Contents/MacOS/nonet-helper"
  cp /usr/bin/true "$app/Contents/XPCServices/Helper.xpc/Contents/MacOS/Helper"
  load_release
  WORK="$TEST_TMP" TEAM="$TEST_TEAM" VERSION=1.2.0 BUILD=42 APPCAST_URL="" SPARKLE_PUBLIC_KEY="" PURCHASE_URL="" \
    LICENSE_PUBLIC_KEY="" SUPPORT_EMAIL=""
  run verify_app "$app"
  assert_status 1
  assert_contains "$OUT" "Nonet.app/Contents/MacOS/nonet-helper で hardened runtime が有効になっていません"
  assert_contains "$OUT" "Nonet.app/Contents/XPCServices/Helper.xpc/Contents/MacOS/Helper で hardened runtime が有効になっていません"
  # アプリ本体の実行ファイルは .app として確かめる（同じ問題を2回出さない）
  assert_not_called "codesign -dvv $app/Contents/MacOS/Nonet"
}

# MARK: - 書き出したアプリの中身（自己診断・DEBUG のコード・get-task-allow）

# 書き出した .app を、公証に出す前に --self-check で本当に動かす
test_release_runs_the_self_check_on_the_exported_app() {
  prepare_release
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 0
  local app="$REPO/build/release/1.2.0/export/Nonet.app"
  assert_called "Nonet executable: $app/Contents/MacOS/Nonet"
  assert_called_in_order \
    "codesign --verify --deep --strict --verbose=2 $app" \
    "Nonet --self-check" \
    "xcrun notarytool submit"
  assert_called "strings -a $app/Contents/MacOS/Nonet"
  assert_called "codesign -d --entitlements :- $app"
  assert_contains "$OUT" "--self-check が ok であることを確かめました"
}

test_failed_self_check_stops_before_notarization() {
  prepare_release
  export FAKE_SELF_CHECK_STATUS=1
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "書き出したアプリに問題があります"
  assert_contains "$OUT" "export/Nonet.app/Contents/MacOS/Nonet --self-check が ok になりませんでした（終了コード 1、ok: false、failures: [\"multitouch\"]）"
  assert_not_called "notarytool submit"
  assert_no_file "$RELEASES/Nonet-1.2.0.dmg"
}

# 終了コードが 0 でも、ok と報告していなければ止める（逆も）。入れ子の "ok": true に騙されない
test_self_check_must_report_ok_and_exit_zero() {
  prepare_release
  export FAKE_SELF_CHECK_OUTPUT='{"failures":["presets"],"ok":false}'
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "終了コード 0、ok: false、failures: [\"presets\"]"

  export FAKE_SELF_CHECK_OUTPUT='{"configurationRoundTrip":{"ok":true},"failures":["presets"],"ok":false}'
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "終了コード 0、ok: false"

  export FAKE_SELF_CHECK_OUTPUT=""
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "終了コード 0、ok: なし"

  export FAKE_SELF_CHECK_OUTPUT="これは JSON ではありません"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "ok: なし"
  assert_contains "$OUT" "出力: これは JSON ではありません"

  export FAKE_SELF_CHECK_OUTPUT='{"failures":[],"ok":true}' FAKE_SELF_CHECK_STATUS=1
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "終了コード 1、ok: true"
  assert_not_called "notarytool submit"
}

test_self_check_that_never_finishes_is_stopped() {
  prepare_release
  export FAKE_SELF_CHECK_HANG=1 NONET_SELF_CHECK_TIMEOUT=1
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "--self-check が 1 秒たっても終わりません"
  assert_not_called "notarytool submit"
}

# DEBUG ビルドだけのコード（App/DemoMode.swift・App/DebugPreview.swift）が Release の実行ファイルに残っていたら止める
test_release_binary_with_debug_only_code_is_rejected() {
  prepare_release
  load_release
  local marker
  for marker in "${DEBUG_ONLY_MARKERS[@]}"; do
    export FAKE_APP_DEBUG_TEXT="$marker"
    run "$REPO/scripts/release.sh" 1.2.0 42
    assert_status 1 "$marker"
    assert_contains "$OUT" "export/Nonet.app/Contents/MacOS/Nonet に DEBUG ビルドだけのコード（$marker）が入っています" "$marker"
    assert_not_called "notarytool submit"
  done
  export FAKE_APP_DEBUG_TEXT="DemoSession DebugPreview"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "DEBUG ビルドだけのコード（DebugPreview DemoSession）"

  # 起動引数の名前は NonetUI の ShellLaunchOptions がどのビルドでも読むので、印にしない（本番が必ず止まってしまう）
  export FAKE_APP_DEBUG_TEXT="--demo-script --demo-start-file --config-dir --preview-hud DemoScript"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 0
}

# 印が、本当に DEBUG のコードだけにある文字列か（名前を変えて印が空振りしない・Release のコードにある文字列で本番が止まらない）
test_debug_only_markers_are_only_in_debug_code() {
  load_release
  local sources=() file marker found
  while IFS= read -r file; do sources+=("$file"); done < <(
    find "$ROOT/App" "$ROOT/Packages/NonetKit/Sources" -name '*.swift' | sort
  )
  for marker in "${DEBUG_ONLY_MARKERS[@]}"; do
    found="$(python3 -I "$ROOT/scripts/tests/swift_debug_scope.py" find "$marker" "${sources[@]}")"
    grep -q '^debug ' <<<"$found" || fail "release.sh の DEBUG_ONLY_MARKERS の「$marker」が、#if DEBUG のコードにありません（名前を変えたなら印も直す）"
    ! grep -q '^release ' <<<"$found" || fail "「$marker」が #if DEBUG の外にもあります（Release のビルドにも入るので、印にできません）:" "$(grep '^release ' <<<"$found")"
  done
}

# get-task-allow の付いた署名（Debug ビルドの署名）は、ほかのプロセスがデバッガーでつなげるので配らない
test_get_task_allow_signature_is_rejected() {
  prepare_release
  export FAKE_CODESIGN_GET_TASK_ALLOW=true
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "export/Nonet.app が com.apple.security.get-task-allow の付いた署名です"
  assert_called "codesign -d --entitlements :- $REPO/build/release/1.2.0/export/Nonet.app"
  assert_not_called "notarytool submit"

  # false は付いていないのと同じ
  export FAKE_CODESIGN_GET_TASK_ALLOW=false
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 0
}

# MARK: - 公開した版の出し直し

# generate_appcast と同じ形の項目（版・ビルド・DMG の URL）を1行ずつ持つ appcast
#   write_versioned_appcast <ファイル> <ビルド>:<版> …
write_versioned_appcast() {
  local file="$1" pair
  shift
  mkdir -p "$(dirname "$file")"
  {
    printf '<?xml version="1.0" standalone="yes"?>\n<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n<channel>\n'
    for pair in "$@"; do
      printf '<item>\n<title>%s</title>\n<sparkle:version>%s</sparkle:version>\n<sparkle:shortVersionString>%s</sparkle:shortVersionString>\n' \
        "${pair#*:}" "${pair%%:*}" "${pair#*:}"
      printf '<enclosure url="https://nonet.test/updates/Nonet-%s.dmg" length="1" type="application/octet-stream" sparkle:edSignature="c2ln"/>\n</item>\n' \
        "${pair#*:}"
    done
    printf '</channel>\n</rss>\n'
  } >"$file"
}

test_appcast_has_version_and_url() {
  load_release
  write_versioned_appcast "$TEST_TMP/a.xml" 41:1.2.0
  appcast_has_version "$TEST_TMP/a.xml" 1.2.0 || fail "版 1.2.0 を見逃した"
  ! appcast_has_version "$TEST_TMP/a.xml" 1.2 || fail "1.2 を 1.2.0 と同じとみなした"
  ! appcast_has_version "$TEST_TMP/a.xml" 1.2.00 || fail "1.2.00 を 1.2.0 と同じとみなした"
  ! appcast_has_version "$TEST_TMP/a.xml" 1x2x0 || fail ". を任意の文字とみなした"
  ! appcast_has_version "$TEST_TMP/none.xml" 1.2.0 || fail "無いファイルに版があるとみなした"
  # 古い形（属性）
  printf '<item><enclosure sparkle:shortVersionString="1.3.0" sparkle:version="50" url="https://nonet.test/u/a.dmg"/></item>\n' >"$TEST_TMP/b.xml"
  appcast_has_version "$TEST_TMP/b.xml" 1.3.0 || fail "属性の版を見逃した"
  appcast_has_url "$TEST_TMP/a.xml" "https://nonet.test/updates/Nonet-1.2.0.dmg" || fail "同じ URL を見逃した"
  ! appcast_has_url "$TEST_TMP/a.xml" "https://nonet.test/updates/Nonet-1.2.0.dmg.bak" || fail "違う URL を同じとみなした"
  ! appcast_has_url "$TEST_TMP/a.xml" "" || fail "空の URL を同じとみなした"
}

# 公開後に版を上げ忘れた（ビルド番号だけ上げた）。公証の前に止まる
test_published_version_cannot_be_released_again() {
  prepare_release
  write_versioned_appcast "$TEST_TMP/published/appcast.xml" 41:1.2.0
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "$RELEASES/appcast.xml には、すでに版 1.2.0 の項目があります"
  assert_contains "$OUT" "docs/release.md 2.9"
  assert_not_contains "$OUT" "予期しないエラー"
  assert_not_called "xcodebuild archive"
  assert_no_file "$RELEASES/Nonet-1.2.0.dmg"
  # 新しい版なら通る
  run "$REPO/scripts/release.sh" 1.2.1 42
  assert_status 0
}

# 手元の appcast に載っていれば、パッケージの解決より前（準備の確認）で止まる。dry run でも同じ
test_local_appcast_with_the_same_version_stops_in_preflight() {
  prepare_release
  write_versioned_appcast "$RELEASES/appcast.xml" 41:1.2.0
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "リリースの準備が足りません"
  assert_contains "$OUT" "$RELEASES/appcast.xml には、すでに版 1.2.0 の項目があります"
  assert_not_called "xcodegen"
  run "$REPO/scripts/release.sh" --dry-run 1.2.0 42
  assert_status 1
  assert_not_called "xcodegen"
}

# 版の番号が無い古い項目でも、同じ DMG の URL を指していれば止まる（NONET_DOWNLOAD_URL_PREFIX も使う）
test_same_dmg_url_stops() {
  prepare_release
  write_appcast "$TEST_TMP/published/appcast.xml" 41
  sed -i '' 's#</sparkle:version>#</sparkle:version><enclosure url="https://cdn.nonet.test/dl/Nonet-1.2.0.dmg" length="1"/>#' \
    "$TEST_TMP/published/appcast.xml"
  export NONET_DOWNLOAD_URL_PREFIX="https://cdn.nonet.test/dl"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "すでに同じ DMG の URL（https://cdn.nonet.test/dl/Nonet-1.2.0.dmg）の項目があります"
  assert_not_called "xcodebuild archive"
  # DMG を置く場所が違えば、別の DMG
  rm -rf "$RELEASES"
  : >"$FAKE_LOG"
  unset NONET_DOWNLOAD_URL_PREFIX
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 0
}

# 公開用のフォルダの DMG は上書きしない（別の Mac から appcast を取り込んで同じ版を出しても）
test_existing_dmg_is_never_overwritten() {
  prepare_release
  mkdir -p "$RELEASES"
  printf 'published dmg\n' >"$RELEASES/Nonet-1.2.0.dmg"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "$RELEASES/Nonet-1.2.0.dmg がすでにあります。公開済みの DMG を上書きしないよう止めました"
  assert_not_called "xcodegen"
  assert_eq "published dmg" "$(cat "$RELEASES/Nonet-1.2.0.dmg")" "DMG は変わらない"
}

# 本番で一度出した版を、ビルド番号だけ上げてもう一度出そうとした（レビューで再現した流れ）
test_releasing_the_same_version_twice_stops() {
  prepare_release
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 0
  assert_contains "$(cat "$RELEASES/appcast.xml")" "<sparkle:shortVersionString>1.2.0</sparkle:shortVersionString>"
  local before
  before="$(cat "$RELEASES/Nonet-1.2.0.dmg")"
  export FAKE_CURL_BODY="$RELEASES/appcast.xml"
  : >"$FAKE_LOG"
  run "$REPO/scripts/release.sh" 1.2.0 43
  assert_status 1
  assert_contains "$OUT" "Nonet-1.2.0.dmg がすでにあります"
  assert_contains "$OUT" "すでに版 1.2.0 の項目があります"
  assert_not_called "xcodegen"
  assert_eq "$before" "$(cat "$RELEASES/Nonet-1.2.0.dmg")" "公開済みの DMG は変わらない"
  assert_eq "1" "$(grep -c 'Nonet-1.2.0.dmg' "$RELEASES/appcast.xml")" "同じ URL の項目は1つのまま"

  # DMG を別の場所に移していても、appcast で止まる
  mv "$RELEASES/Nonet-1.2.0.dmg" "$TEST_TMP/"
  run "$REPO/scripts/release.sh" 1.2.0 43
  assert_status 1
  assert_not_contains "$OUT" "がすでにあります。公開済みの DMG"
  assert_contains "$OUT" "すでに版 1.2.0 の項目があります"
  assert_not_called "xcodebuild archive"
}

test_release_notes_are_embedded_in_appcast() {
  prepare_release
  printf '# 1.2.0\n- 速くなりました\n' >"$TEST_TMP/notes.md"
  run "$REPO/scripts/release.sh" --notes "$TEST_TMP/notes.md" 1.2.0 42
  assert_status 0
  assert_file "$RELEASES/Nonet-1.2.0.md"
  assert_called "--embed-release-notes $RELEASES"
  assert_called "Nonet-1.2.0.dmg Nonet-1.2.0.md"
}

# docs/release.md のとおり、リポジトリの中の notes/ にノートを書いてすぐ本番を動かせる（本物の git で確かめる）
test_release_notes_inside_the_repo_do_not_block_a_release() {
  if [[ ! -x /usr/bin/git ]]; then
    printf '/usr/bin/git が無いので飛ばしました\n'
    return 0
  fi
  prepare_release
  export FAKE_GIT_REAL=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  printf 'build/\nNonet.xcodeproj/\n' >"$REPO/.gitignore"
  /usr/bin/git -C "$REPO" init -q
  # 本番は main からだけ出せる（init.defaultBranch に左右されないよう、ブランチ名を決める）
  /usr/bin/git -C "$REPO" symbolic-ref HEAD refs/heads/main
  /usr/bin/git -C "$REPO" add -A
  /usr/bin/git -C "$REPO" -c user.name=test -c user.email=test@nonet.test -c commit.gpgsign=false -c core.hooksPath=/dev/null \
    commit -q -m init
  mkdir -p "$REPO/notes"
  printf '# 1.2.0\n- 速くなりました\n' >"$REPO/notes/1.2.0.md"

  cd "$REPO" || return 1
  run scripts/release.sh --notes notes/1.2.0.md 1.2.0 42
  assert_status 0
  assert_not_contains "$OUT" "コミットしていない変更があります"
  assert_file "$RELEASES/Nonet-1.2.0.md"

  # ほかの変更があれば、これまでどおり止まる
  printf '# 1.2.1\n' >"$REPO/notes/1.2.1.md"
  printf 'changed\n' >>"$REPO/project.yml"
  run scripts/release.sh --notes notes/1.2.1.md 1.2.1 43
  assert_status 1
  assert_contains "$OUT" "コミットしていない変更があります。コミットしてから出すか、--allow-dirty を付けてください"
}

test_download_prefix_and_key_account_can_be_overridden() {
  prepare_release
  export NONET_DOWNLOAD_URL_PREFIX="https://cdn.nonet.test/dl"
  export NONET_SPARKLE_KEY_ACCOUNT="nonet"
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 0
  assert_called "generate_keys --account nonet -p"
  assert_called "generate_appcast --account nonet --download-url-prefix https://cdn.nonet.test/dl/ -o $RELEASES/appcast.xml $RELEASES"
}

test_appcast_without_the_new_item_fails() {
  prepare_release
  export FAKE_APPCAST_SKIP_ITEM=1
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "appcast.xml にビルド 42 の項目がありません"
}

test_unexpected_failure_names_the_step() {
  prepare_release
  write_appcast "$RELEASES/appcast.xml" 41
  # 公開中の appcast は作業用フォルダに取ってくるので、公開用のフォルダが書けなくても比べられる
  export FAKE_CURL_BODY="$RELEASES/appcast.xml"
  chmod 555 "$RELEASES"
  run "$REPO/scripts/release.sh" 1.2.0 42
  chmod 755 "$RELEASES"
  assert_failed
  assert_contains "$OUT" "予期しないエラーで止まりました"
  assert_contains "$OUT" "ステップ: appcast を更新する（Sparkle generate_appcast）"
  assert_not_called "generate_appcast --account"
}

test_release_works_outside_a_git_checkout() {
  prepare_release
  export FAKE_GIT_NOT_REPO=1
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 0
  assert_contains "$OUT" "git の作業ツリーではないので、コミットとブランチを確かめられません"
  assert_not_called "git -C $REPO status"
}

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
  run "$REPO/scripts/release.sh" --force-local-appcast 1.2.0 43
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
  run "$REPO/scripts/release.sh" 1.2.0 42
  assert_status 1
  assert_contains "$OUT" "Info.plist の SUFeedURL が「https://wrong.nonet.test/appcast.xml」です"
  assert_contains "$OUT" "Info.plist の NonetLicensePublicKey が「」です"
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
  run "$REPO/scripts/release.sh" 1.2.0 43
  assert_status 1
  assert_contains "$OUT" "Sparkle.framework/Versions/B/Autoupdate が Developer ID Application で署名されていません"
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
  assert_not_called "git -C $REPO status"
}

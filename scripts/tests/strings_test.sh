# scripts/sync-strings.sh のテスト（偽の swift と xcrun xcstringstool で動かす）

# 偽のリポジトリに、文言が1つずつ入ったカタログを置く
prepare_catalogs() {
  use_fakes
  make_fake_repo
  local target
  for target in NonetCore NonetPlatform NonetUI; do
    mkdir -p "$REPO/Packages/NonetKit/Sources/$target/Resources"
    write_catalog "$REPO/Packages/NonetKit/Sources/$target/Resources/Localizable.xcstrings" "$target の文言"
  done
  mkdir -p "$REPO/App"
  write_catalog "$REPO/App/Localizable.xcstrings" "App の文言"
}

# 英語の訳がある文言を1つ持つカタログ
write_catalog() {
  cat >"$1" <<EOF
{
  "sourceLanguage" : "ja",
  "strings" : {
    "$2" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Text" } }
      }
    }
  },
  "version" : "1.0"
}
EOF
}

test_catalog_problems_lists_missing_and_untranslated_strings() {
  # shellcheck source=../sync-strings.sh
  source "$ROOT/scripts/sync-strings.sh"
  cat >"$TEST_TMP/committed.xcstrings" <<'EOF'
{
  "sourceLanguage" : "ja",
  "strings" : {
    "訳がある" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Translated" } } } },
    "訳が無い" : { },
    "使われなくなった" : { "extractionState" : "stale" },
    "訳さない" : { "shouldTranslate" : false }
  }
}
EOF
  cat >"$TEST_TMP/synced.xcstrings" <<'EOF'
{
  "sourceLanguage" : "ja",
  "strings" : {
    "訳がある" : { "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Translated" } } } },
    "訳が無い" : { },
    "使われなくなった" : { "extractionState" : "stale" },
    "訳さない" : { "shouldTranslate" : false },
    "新しい文言" : { },
    "新しい %lld 件" : { "extractionState" : "extracted_with_value" },
    "訳さない新しい文言" : { "shouldTranslate" : false }
  }
}
EOF
  local problems
  problems="$(catalog_problems "$TEST_TMP/synced.xcstrings" "$TEST_TMP/committed.xcstrings")"
  assert_contains "$problems" "カタログに無い: 新しい文言"
  assert_contains "$problems" "カタログに無い: 新しい %lld 件"
  assert_contains "$problems" "英語が無い: 訳が無い"
  assert_not_contains "$problems" "訳がある"
  assert_not_contains "$problems" "使われなくなった"
  assert_not_contains "$problems" "訳さない"
  assert_eq "3" "$(grep -c '' <<<"$problems")" "3件"

  # 無いカタログは空とみなす
  assert_contains "$(catalog_problems "$TEST_TMP/synced.xcstrings" "$TEST_TMP/none.xcstrings")" "カタログに無い: 訳がある"
  assert_eq "" "$(catalog_problems "$TEST_TMP/committed.xcstrings" "$TEST_TMP/committed.xcstrings" | grep -v '英語が無い' || true)"
}

test_check_reports_a_missing_string_and_leaves_catalogs_alone() {
  prepare_catalogs
  local catalog="$REPO/Packages/NonetKit/Sources/NonetUI/Resources/Localizable.xcstrings" before
  before="$(cat "$catalog")"
  export FAKE_XCSTRINGS_NEW_KEY="新しいボタン"
  run "$REPO/scripts/sync-strings.sh" --check
  assert_status 1
  assert_contains "$OUT" "コードの文言が String Catalog に無いか、英語の訳がありません"
  assert_contains "$OUT" "Packages/NonetKit/Sources/NonetUI/Resources/Localizable.xcstrings"
  assert_contains "$OUT" "カタログに無い: 新しいボタン"
  assert_contains "$OUT" "NonetCore: 足りない文言はありません"
  assert_eq "$before" "$(cat "$catalog")" "カタログは書き換えない"
  assert_called "swift build --package-path $REPO/Packages/NonetKit --build-path"

  # App/ のカタログも確かめる
  export FAKE_XCSTRINGS_TARGET="/App"
  run "$REPO/scripts/sync-strings.sh" --check
  assert_status 1
  assert_contains "$OUT" "App/Localizable.xcstrings"
}

# Xcode 26（CI）の swift build は .stringsdata を -emit-localized-strings-path のフォルダに並べて置く。
# 置き場所ではなく中の source でターゲットを見分けるので、どちらでも同じに通る
test_check_finds_stringsdata_in_either_layout() {
  prepare_catalogs
  export FAKE_SWIFT_STRINGS_FLAT=1
  run "$REPO/scripts/sync-strings.sh" --check
  assert_status 0
  assert_contains "$OUT" "NonetUI: 足りない文言はありません"
  local target
  for target in NonetCore NonetPlatform NonetUI; do
    assert_contains "$(cat "$FAKE_LOG")" "${target}View.stringsdata"
  done
}

test_check_passes_when_every_string_is_translated() {
  prepare_catalogs
  run "$REPO/scripts/sync-strings.sh" --check
  assert_status 0
  assert_contains "$OUT" "コードの文言は、すべてカタログにあり英語の訳があります"
}

test_sync_still_updates_the_catalogs() {
  prepare_catalogs
  export FAKE_XCSTRINGS_NEW_KEY="新しいボタン"
  run "$REPO/scripts/sync-strings.sh"
  assert_status 0
  assert_contains "$(cat "$REPO/Packages/NonetKit/Sources/NonetUI/Resources/Localizable.xcstrings")" "新しいボタン"
  assert_contains "$OUT" "NonetUI: 2 件（英語が無い: 1 件）"
}

test_sync_strings_options() {
  make_fake_repo
  run "$REPO/scripts/sync-strings.sh" --help
  assert_status 0
  assert_contains "$OUT" "--check"
  use_fakes
  run "$REPO/scripts/sync-strings.sh" --frobnicate
  assert_status 1
  assert_contains "$OUT" "知らないオプションです: --frobnicate"
  assert_not_called "swift"
}

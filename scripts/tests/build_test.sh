# scripts/build.sh と scripts/test.sh のテスト（偽の xcodegen・xcodebuild・swift で動かす）

test_build_prints_app_path_from_any_directory() {
  use_fakes
  make_fake_repo
  mkdir -p "$TEST_TMP/elsewhere"
  cd "$TEST_TMP/elsewhere" || return 1
  run_split "$REPO/scripts/build.sh"
  assert_status 0
  assert_eq "$REPO/build/DerivedData/Build/Products/Debug/Nonet.app" "$STDOUT" "標準出力は .app の場所だけ"
  assert_called_in_order \
    "xcodegen generate --spec $REPO/project.yml" \
    "xcodebuild build -project $REPO/Nonet.xcodeproj -scheme Nonet -configuration Debug -derivedDataPath $REPO/build/DerivedData -destination platform=macOS,arch=$(uname -m)"
  assert_not_called "CODE_SIGN_IDENTITY=-"
}

test_build_passes_extra_arguments_to_xcodebuild() {
  use_fakes
  make_fake_repo
  run_split "$REPO/scripts/build.sh" CODE_SIGNING_ALLOWED=NO
  assert_status 0
  assert_called "-quiet CODE_SIGNING_ALLOWED=NO"
}

test_build_falls_back_to_adhoc_signing() {
  use_fakes
  make_fake_repo
  export FAKE_IDENTITIES=""
  run_split "$REPO/scripts/build.sh"
  assert_status 0
  assert_called "CODE_SIGN_IDENTITY=-"
  assert_contains "$STDERR" "アドホック署名にします"
  assert_eq "$REPO/build/DerivedData/Build/Products/Debug/Nonet.app" "$STDOUT"
}

test_build_failure_propagates() {
  use_fakes
  make_fake_repo
  export FAKE_XCODEBUILD_STATUS=65
  run_split "$REPO/scripts/build.sh"
  assert_status 65
  assert_eq "" "$STDOUT" "失敗したら場所を出さない"
}

test_build_reports_missing_tools() {
  use_fakes
  make_fake_repo
  # xcodegen だけが無い PATH
  mkdir -p "$TEST_TMP/bin"
  ln -s "$FAKES_DIR/xcodebuild" "$FAKES_DIR/security" "$TEST_TMP/bin/"
  run env PATH="$TEST_TMP/bin:/usr/bin:/bin" "$REPO/scripts/build.sh"
  assert_status 1
  assert_contains "$OUT" "必要なコマンドがありません: xcodegen"
  assert_contains "$OUT" "brew install xcodegen"
}

test_build_help() {
  make_fake_repo
  run "$REPO/scripts/build.sh" --help
  assert_status 0
  assert_contains "$OUT" "Debug ビルド"
}

test_test_sh_runs_every_stage_in_order() {
  use_fakes
  make_fake_repo
  cd / || return 1
  run "$REPO/scripts/test.sh"
  assert_status 0
  assert_called_in_order \
    "tests/run.sh" \
    "swift build (in NonetKit)" \
    "swift test (in NonetKit)" \
    "xcodegen generate --spec $REPO/project.yml" \
    "xcodebuild build -project $REPO/Nonet.xcodeproj -scheme Nonet -configuration Debug -destination generic/platform=macOS -derivedDataPath $REPO/build/TestDerivedData -quiet CODE_SIGNING_ALLOWED=NO"
  assert_contains "$OUT" "すべて通りました"
}

test_test_sh_stops_at_the_first_failure() {
  use_fakes
  make_fake_repo
  export FAKE_SELFTEST_STATUS=1
  run "$REPO/scripts/test.sh"
  assert_failed
  assert_not_called "swift"

  : >"$FAKE_LOG"
  export FAKE_SELFTEST_STATUS=0 FAKE_SWIFT_TEST_STATUS=1
  run "$REPO/scripts/test.sh"
  assert_failed
  assert_called "swift test"
  assert_not_called "xcodebuild"

  : >"$FAKE_LOG"
  export FAKE_SWIFT_TEST_STATUS=0 FAKE_XCODEBUILD_STATUS=65
  run "$REPO/scripts/test.sh"
  assert_status 65
  assert_not_contains "$OUT" "すべて通りました"
}

# Release のビルドが読む起動引数は --self-check だけであることの静的な確認。
# App/*.swift のうち #if DEBUG の外にあるコードが、DEBUG 専用の起動引数（--config-dir・--demo・--snapshot など。
# ShellLaunchOptions の selfCheck 以外）を読んでいないかを、scripts/tests/swift_debug_scope.py が調べる。
# 読んでいると、配った製品版でも、起動引数ひとつで設定の置き場所や試用の状態を変えられてしまう

# 起動引数（options.xxx・launchOptions.xxx）の読み取りを調べる。ファイルを渡す
scan_launch_options() {
  run python3 -I "$ROOT/scripts/tests/swift_debug_scope.py" launch-options "$@"
}

# 手書きの Swift を書いて、そのパスを SWIFT_FIXTURE に入れる。使い方: write_swift <名前> <<'EOF' … EOF
write_swift() {
  mkdir -p "$TEST_TMP/swift"
  SWIFT_FIXTURE="$TEST_TMP/swift/$1.swift"
  cat >"$SWIFT_FIXTURE"
}

test_release_code_reads_only_the_self_check_launch_option() {
  local files=() file
  while IFS= read -r file; do files+=("$file"); done < <(find "$ROOT/App" -maxdepth 1 -name '*.swift' | sort)
  [[ ${#files[@]} -ge 4 ]] || fail "App/*.swift が見つかりません"
  scan_launch_options "${files[@]}"
  assert_status 0

  # 何も調べていないのではない: 本物のソースに、Release でも読む selfCheck と、DEBUG の中で読む起動引数がある
  grep -q 'launchOptions.selfCheck' "$ROOT/App/main.swift" || fail "App/main.swift が --self-check を読んでいません"
  run python3 -I "$ROOT/scripts/tests/swift_debug_scope.py" find "options.configDirectory" "$ROOT/App/AppDelegate.swift"
  assert_status 0
  assert_contains "$OUT" "debug $ROOT/App/AppDelegate.swift:"
  assert_not_contains "$OUT" "release "
}

test_launch_options_check_finds_debug_options_outside_debug() {
  write_swift outside <<'EOF'
func start() {
    if options.demo { run() }
}
EOF
  scan_launch_options "$SWIFT_FIXTURE"
  assert_status 1
  assert_contains "$OUT" "outside.swift:2: options.demo は #if DEBUG の外にあります"
  assert_contains "$OUT" "読んでよい起動引数は selfCheck だけです"

  # #if DEBUG の後ろ・#else の側・#if !DEBUG の側は Release に入る
  write_swift after_block <<'EOF'
#if DEBUG
let a = options.demo
#endif
let b = options.configDirectory
EOF
  scan_launch_options "$SWIFT_FIXTURE"
  assert_status 1
  assert_contains "$OUT" "after_block.swift:4: options.configDirectory"
  assert_not_contains "$OUT" "after_block.swift:2"

  write_swift else_branch <<'EOF'
#if DEBUG
let a = options.demo
#else
let b = options.simulateExpiredTrial
#endif
EOF
  scan_launch_options "$SWIFT_FIXTURE"
  assert_status 1
  assert_contains "$OUT" "else_branch.swift:4: options.simulateExpiredTrial"
  assert_not_contains "$OUT" "else_branch.swift:2"

  write_swift not_debug <<'EOF'
#if !DEBUG
let a = options.demo
#else
let b = options.demo
#endif
EOF
  scan_launch_options "$SWIFT_FIXTURE"
  assert_status 1
  assert_contains "$OUT" "not_debug.swift:2: options.demo"
  assert_not_contains "$OUT" "not_debug.swift:4"

  # #elseif は DEBUG でないときの枝
  write_swift elseif_branch <<'EOF'
#if DEBUG
let a = options.demo
#elseif os(macOS)
let b = options.snapshotDirectory
#endif
EOF
  scan_launch_options "$SWIFT_FIXTURE"
  assert_status 1
  assert_contains "$OUT" "elseif_branch.swift:4: options.snapshotDirectory"
}

test_launch_options_check_finds_every_way_of_reading_an_option() {
  write_swift forms <<'EOF'
func f() {
    let a = self.options.previewHUD
    let b = launchOptions.configDirectory
    let c = options?.demoScript
    let d = options . showOnboarding
    let url = "https://nonet.test/x"; let e = options.demo
    /* 閉じたコメント */ let g = options.snapshotDirectory
    let h = "\(options.previewToast)"
}
EOF
  scan_launch_options "$SWIFT_FIXTURE"
  assert_status 1
  local expected
  for expected in "forms.swift:2: options.previewHUD" "forms.swift:3: launchOptions.configDirectory" "forms.swift:4: options?.demoScript" \
    "forms.swift:5: options.showOnboarding" "forms.swift:6: options.demo" "forms.swift:7: options.snapshotDirectory" \
    "forms.swift:8: options.previewToast"; do
    assert_contains "$OUT" "$expected"
  done
}

test_launch_options_check_allows_what_release_may_use() {
  write_swift allowed <<'EOF'
import AppKit

// options.demo はコメントの中
/// options.configDirectory はドキュメントコメントの中
/*
 options.simulateExpiredTrial は
 /* 入れ子の */ ブロックコメントの中
 */
let launchOptions = ShellLaunchOptions.parse(CommandLine.arguments)
if launchOptions.selfCheck { exit(SelfCheck.run()) }
let delegate = AppDelegate(options: launchOptions)
final class Box {
    private let options: ShellLaunchOptions
    init(options: ShellLaunchOptions) { self.options = options }
    func check() -> Bool { self.options.selfCheck || options.selfCheck }
}
#if DEBUG
let a = options.demo
#if os(macOS)
let b = options.configDirectory
#else
let c = launchOptions.snapshotDirectory
#endif
let d = options.previewHUD
#endif
#if os(macOS)
let e = 1
#endif
#if !DEBUG
let f = options.selfCheck
#else
let g = options.simulateExpiredTrial
#endif
EOF
  scan_launch_options "$SWIFT_FIXTURE"
  assert_status 0
}

# DEBUG を含む複雑な条件は、Release に入るかを取り違えないよう、読めないものとして止める
test_launch_options_check_stops_on_conditions_it_cannot_read() {
  local condition
  for condition in "DEBUG && FOO" "DEBUG || FOO" "!DEBUG && FOO" "(DEBUG || FOO)"; do
    write_swift complex <<EOF
#if $condition
let a = options.demo
#endif
EOF
    scan_launch_options "$SWIFT_FIXTURE"
    assert_status 2 "$condition"
    assert_contains "$OUT" "complex.swift: 1 行目: 読めない条件です"
    assert_contains "$OUT" "#if $condition"
  done
  write_swift elseif_debug <<'EOF'
#if FOO
#elseif DEBUG
let a = options.demo
#endif
EOF
  scan_launch_options "$SWIFT_FIXTURE"
  assert_status 2
  assert_contains "$OUT" "elseif_debug.swift: 2 行目: 読めない条件です"

  write_swift unclosed <<'EOF'
#if DEBUG
let a = options.demo
EOF
  scan_launch_options "$SWIFT_FIXTURE"
  assert_status 2
  assert_contains "$OUT" "#endif が足りません"
  write_swift stray_endif <<'EOF'
let a = 1
#endif
EOF
  scan_launch_options "$SWIFT_FIXTURE"
  assert_status 2
  assert_contains "$OUT" "stray_endif.swift: 2 行目: #endif に対応する #if がありません"
}

test_swift_debug_scope_usage_errors() {
  run python3 -I "$ROOT/scripts/tests/swift_debug_scope.py"
  assert_status 2
  assert_contains "$OUT" "使い方: swift_debug_scope.py"
  run python3 -I "$ROOT/scripts/tests/swift_debug_scope.py" launch-options
  assert_status 2
}

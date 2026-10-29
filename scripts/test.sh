#!/bin/bash
# 自動テスト一式。失敗したらそこで止まり、0 以外で終わる。CI（.github/workflows/ci.yml）もこれを動かす。
#   1. scripts/ とサイト・ドキュメントのテスト（scripts/tests/run.sh）
#   2. NonetKit の swift build と swift test
#   3. アプリのビルド（署名なし、Apple シリコンと Intel の両方。DerivedData は build/TestDerivedData）
#   4. ビルドしたアプリの自己診断（--self-check: 画面を出さずに、プリセット・設定の保存・MultitouchSupport を確かめる）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

case "${1:-}" in
  -h | --help)
    sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

require_commands swift xcodegen xcodebuild

step "scripts/ とサイト・ドキュメントのテスト"
"$SCRIPT_DIR/tests/run.sh"

step "NonetKit: swift build"
(cd "$ROOT/Packages/NonetKit" && swift build)

step "NonetKit: swift test"
(cd "$ROOT/Packages/NonetKit" && swift test)

step "Xcode プロジェクトを作る（XcodeGen）"
xcodegen generate --spec "$ROOT/project.yml" --quiet

# 開発用の署名済みビルド（build/DerivedData）を署名なしで上書きしないよう、別の場所に作る
step "アプリのビルド（署名なし）"
xcodebuild build \
  -project "$ROOT/Nonet.xcodeproj" \
  -scheme Nonet \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$ROOT/build/TestDerivedData" \
  -quiet \
  CODE_SIGNING_ALLOWED=NO

step "アプリの自己診断（--self-check）"
"$ROOT/build/TestDerivedData/Build/Products/Debug/Nonet.app/Contents/MacOS/Nonet" --self-check
echo

step "すべて通りました"

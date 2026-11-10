#!/bin/bash
# 自動テスト一式。失敗したらそこで止まり、0 以外で終わる。CI（.github/workflows/ci.yml）もこれを動かす。
#   1. scripts/ とサイト・ドキュメントのテスト（scripts/tests/run.sh）と、販売ページの Worker のテスト（cloudflare/ の node --test。依存は要らない）
#   2. NonetKit の swift build と swift test
#   3. コードの文言がすべて String Catalog にあり、英語の訳があるか（scripts/sync-strings.sh --check。カタログは書き換えない）
#   4. アプリのビルド（署名なし、Apple シリコンと Intel の両方。DerivedData は build/TestDerivedData）。Release の設定でも作る
#      （#if DEBUG の中にしか無いものを使っていると、リリースの直前まで気づかない）
#   5. ビルドしたアプリの自己診断（--self-check: 画面を出さずに、プリセット・設定の保存・MultitouchSupport を確かめる）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

case "${1:-}" in
  -h | --help)
    sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

require_commands swift xcodegen xcodebuild xcrun python3 node

step "scripts/ とサイト・ドキュメントのテスト"
"$SCRIPT_DIR/tests/run.sh"

step "販売ページの Worker のテスト（cloudflare/）"
(cd "$ROOT/cloudflare" && node --test test/*.test.js)

step "NonetKit: swift build"
(cd "$ROOT/Packages/NonetKit" && swift build)

step "NonetKit: swift test"
(cd "$ROOT/Packages/NonetKit" && swift test)

# 新しい文言をカタログに入れ忘れると、英語の利用者に日本語のまま出る（カタログのテストは、カタログにある文言しか見ない）
step "文言が String Catalog にあるか（sync-strings.sh --check）"
"$SCRIPT_DIR/sync-strings.sh" --check

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

# リリースの設定でもコンパイルできるか。scripts/release.sh を動かすまで Release でビルドすることが無いので、ここで確かめる
step "アプリのビルド（Release の設定、署名なし）"
xcodebuild build \
  -project "$ROOT/Nonet.xcodeproj" \
  -scheme Nonet \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$ROOT/build/TestDerivedData" \
  -quiet \
  CODE_SIGNING_ALLOWED=NO

step "アプリの自己診断（--self-check）"
"$ROOT/build/TestDerivedData/Build/Products/Debug/Nonet.app/Contents/MacOS/Nonet" --self-check
echo

step "すべて通りました"

#!/bin/bash
# Debug ビルド。XcodeGen でプロジェクトを作り、DerivedData は build/DerivedData に置く。
# できた .app の場所だけを標準出力に出す（例: open "$(scripts/build.sh)"）。
# 引数はそのまま xcodebuild に渡す（例: scripts/build.sh CODE_SIGNING_ALLOWED=NO）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

case "${1:-}" in
  -h | --help)
    sed -n '2,4p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

require_commands xcodegen xcodebuild

DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/Debug/Nonet.app"

step "Xcode プロジェクトを作る（XcodeGen）"
xcodegen generate --spec "$ROOT/project.yml" --quiet >&2

# Apple Development 証明書で署名すると、再ビルドしてもアクセシビリティの許可が消えない。
# 無ければアドホック署名にする（再ビルドのたびに許可し直しが要る）
signing=()
if ! signing_identities | grep -qF '"Apple Development:'; then
  warn "Apple Development 証明書が無いのでアドホック署名にします（再ビルドのたびにアクセシビリティの許可が必要）"
  signing=(CODE_SIGN_IDENTITY=-)
fi

# 手元で動かすので、この Mac のアーキテクチャだけを作る
step "ビルド（Debug）"
xcodebuild build \
  -project "$ROOT/Nonet.xcodeproj" \
  -scheme Nonet \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  -destination "platform=macOS,arch=$(uname -m)" \
  -quiet \
  ${signing[@]+"${signing[@]}"} \
  "$@" >&2

[[ -d "$APP" ]] || die "ビルドは終わりましたが $APP がありません"
printf '%s\n' "$APP"

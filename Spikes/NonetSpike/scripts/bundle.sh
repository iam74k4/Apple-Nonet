#!/bin/bash
# swift build の成果物を .app に包んで署名する。
# Apple Development 証明書で署名すると、再ビルドしてもアクセシビリティ等の許可が消えない。
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NonetSpike"
APP="build/NonetSpike.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/NonetSpike"
cp Support/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "warning: Apple Development 証明書が無いのでアドホック署名にします（再ビルドのたびに権限の再許可が必要）" >&2
  codesign --force --sign - "$APP"
fi

echo "$PWD/$APP"

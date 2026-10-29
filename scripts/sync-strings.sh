#!/bin/bash
# 画面の文言を String Catalog（各ターゲットの Localizable.xcstrings）に集める。
# NonetKit はコンパイラで抽出する（String.LocalizationValue を受ける関数に渡した文字列も拾える）。App/ は軽い解析で抽出する。
# 使われなくなった文言は stale になるだけで、翻訳は消えない。英語の抜けは swift test（LocalizationCatalogTests）が見つける。
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

require_commands swift xcrun python3

WORK="$(mktemp -d "${TMPDIR:-/tmp}/nonet-strings.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# 文言の数と、英語が無い数
summary() {
  python3 -I - "$1" <<'EOF'
import json, sys
strings = json.load(open(sys.argv[1], encoding="utf-8")).get("strings", {})
live = {k: v for k, v in strings.items() if v.get("extractionState") != "stale" and v.get("shouldTranslate", True)}
missing = [k for k, v in live.items() if "en" not in v.get("localizations", {})]
print(f"{len(live)} 件（英語が無い: {len(missing)} 件）")
EOF
}

# 無ければ空のカタログを作る（日本語が元の言語）
ensure_catalog() {
  [[ -f "$1" ]] && return 0
  printf '{\n  "sourceLanguage" : "ja",\n  "strings" : {\n\n  },\n  "version" : "1.0"\n}\n' >"$1"
}

step "NonetKit をビルドして文言を抽出する"
swift build \
  --package-path "$ROOT/Packages/NonetKit" \
  --build-path "$WORK/build" \
  -Xswiftc -emit-localized-strings \
  -Xswiftc -emit-localized-strings-path -Xswiftc "$WORK/strings" >&2

for target in NonetCore NonetPlatform NonetUI; do
  catalog="$ROOT/Packages/NonetKit/Sources/$target/Resources/Localizable.xcstrings"
  ensure_catalog "$catalog"
  files=()
  # ビルドシステムによって置き場所が <target>.build か <target>-t.build になる
  while IFS= read -r file; do files+=("$file"); done < <(
    find "$WORK" \( -path "*/$target.build/*" -o -path "*/$target-t.build/*" \) -name '*.stringsdata' | sort
  )
  [[ ${#files[@]} -gt 0 ]] || die "$target の .stringsdata が見つかりません"
  xcrun xcstringstool sync "$catalog" --stringsdata "${files[@]}"
  info "$target: $(summary "$catalog")"
done

step "App/ の文言を抽出する"
catalog="$ROOT/App/Localizable.xcstrings"
ensure_catalog "$catalog"
mkdir -p "$WORK/app"
xcrun xcstringstool extract --modern-localizable-strings --output-directory "$WORK/app" "$ROOT"/App/*.swift
files=()
while IFS= read -r file; do files+=("$file"); done < <(find "$WORK/app" -name '*.stringsdata' | sort)
if [[ ${#files[@]} -gt 0 ]]; then
  xcrun xcstringstool sync "$catalog" --stringsdata "${files[@]}"
fi
info "App: $(summary "$catalog")"

#!/bin/bash
# 画面の文言を String Catalog（各ターゲットの Localizable.xcstrings）に集める。
# NonetKit はコンパイラで抽出する（String.LocalizationValue を受ける関数に渡した文字列も拾える）。App/ は軽い解析で抽出する。
# 使われなくなった文言は stale になるだけで、翻訳は消えない。英語の抜けは swift test（LocalizationCatalogTests）が見つける。
# --check: カタログを書き換えずに、コードの文言がすべてカタログにあり英語の訳があるかを確かめる（scripts/test.sh が動かす）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

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

# 抽出を取り込んだカタログ（$1）にあって、コミットしたカタログ（$2。無ければ空とみなす）に無いか、英語の訳が無い文言を1行ずつ出す。
# コードで使われなくなった文言（stale）と、訳さない文言は数えない
catalog_problems() {
  python3 -I - "$1" "$2" <<'EOF'
import json, os, sys

def strings(path):
    if not os.path.exists(path):
        return {}
    return json.load(open(path, encoding="utf-8")).get("strings", {})

synced, committed = strings(sys.argv[1]), strings(sys.argv[2])
for key in sorted(synced):
    value = synced[key]
    if value.get("extractionState") == "stale" or value.get("shouldTranslate", True) is False:
        continue
    entry = committed.get(key)
    if entry is None:
        print(f"カタログに無い: {key}")
    elif entry.get("shouldTranslate", True) is not False and "en" not in entry.get("localizations", {}):
        print(f"英語が無い: {key}")
EOF
}

# カタログ（$2）に .stringsdata（$3 以降）を取り込む。
# --check ではコピーに取り込んで比べ、足りない文言を PROBLEMS に足す（カタログは書き換えない）
# $WORK の下の .stringsdata のうち、ターゲットのソース（Packages/NonetKit/Sources/<target>/）から出たものを1行に1つ出す。
# 置き場所はツールチェーンで違う（Xcode 27 の swift build は <target>-t.build の下、Xcode 26 の CI では
# -emit-localized-strings-path のフォルダなど）ので、場所ではなく中の "source"（元のソースファイル）で見分ける
stringsdata_for() {
  python3 -I - "$WORK" "$ROOT/Packages/NonetKit/Sources/$1" <<'PY'
import json, os, pathlib, sys
work, prefix = pathlib.Path(sys.argv[1]), os.path.realpath(sys.argv[2]) + os.sep
for path in sorted(work.rglob("*.stringsdata")):
    try:
        source = json.loads(path.read_text(encoding="utf-8")).get("source", "")
    except (OSError, ValueError, AttributeError):
        continue
    if source and os.path.realpath(source).startswith(prefix):
        print(path)
PY
}

sync_catalog() {
  local name="$1" catalog="$2" synced problems
  shift 2
  if [[ "$CHECK" == 0 ]]; then
    ensure_catalog "$catalog"
    [[ $# -eq 0 ]] || xcrun xcstringstool sync "$catalog" --stringsdata "$@"
    info "$name: $(summary "$catalog")"
    return 0
  fi
  # xcstringstool は .stringsdata の表の名前（Localizable）とカタログのファイル名を合わせるので、名前は変えない
  synced="$WORK/check/$name/$(basename "$catalog")"
  mkdir -p "$WORK/check/$name"
  if [[ -f "$catalog" ]]; then
    cp "$catalog" "$synced"
  else
    ensure_catalog "$synced"
  fi
  [[ $# -eq 0 ]] || xcrun xcstringstool sync "$synced" --stringsdata "$@"
  problems="$(catalog_problems "$synced" "$catalog")"
  if [[ -z "$problems" ]]; then
    info "$name: 足りない文言はありません"
  else
    info "$name: 足りない文言があります"
    PROBLEMS+="${catalog#"$ROOT/"}"$'\n'"$(sed 's/^/  /' <<<"$problems")"$'\n'
  fi
}

main() {
  CHECK=0
  case "${1:-}" in
    -h | --help)
      sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --check) CHECK=1 ;;
    "") ;;
    *) die "知らないオプションです: $1（使い方は scripts/sync-strings.sh --help）" ;;
  esac

  require_commands swift xcrun python3

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/nonet-strings.XXXXXX")"
  trap 'rm -rf "$WORK"' EXIT
  PROBLEMS=""

  step "NonetKit をビルドして文言を抽出する"
  swift build \
    --package-path "$ROOT/Packages/NonetKit" \
    --build-path "$WORK/build" \
    -Xswiftc -emit-localized-strings \
    -Xswiftc -emit-localized-strings-path -Xswiftc "$WORK/strings" >&2

  local target catalog files file
  for target in NonetCore NonetPlatform NonetUI; do
    catalog="$ROOT/Packages/NonetKit/Sources/$target/Resources/Localizable.xcstrings"
    files=()
    while IFS= read -r file; do files+=("$file"); done < <(stringsdata_for "$target")
    [[ ${#files[@]} -gt 0 ]] || die "$target の .stringsdata が見つかりません"
    sync_catalog "$target" "$catalog" "${files[@]}"
  done

  step "App/ の文言を抽出する"
  catalog="$ROOT/App/Localizable.xcstrings"
  mkdir -p "$WORK/app"
  xcrun xcstringstool extract --modern-localizable-strings --output-directory "$WORK/app" "$ROOT"/App/*.swift
  files=()
  while IFS= read -r file; do files+=("$file"); done < <(find "$WORK/app" -name '*.stringsdata' | sort)
  sync_catalog App "$catalog" ${files[@]+"${files[@]}"}

  if [[ "$CHECK" == 1 ]]; then
    if [[ -n "$PROBLEMS" ]]; then
      error "コードの文言が String Catalog に無いか、英語の訳がありません:"
      printf '%s' "$PROBLEMS" >&2
      die "scripts/sync-strings.sh を実行してカタログに集め、英語の訳を入れてください（docs/release.md「文言の英語」）"
    fi
    info "コードの文言は、すべてカタログにあり英語の訳があります"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

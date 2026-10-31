"""Swift のソースを #if DEBUG の内と外に分けて調べる（scripts/tests/launch_options_test.sh が使う）。標準ライブラリだけで動く。

使い方（python3 -I で動かす）:
  swift_debug_scope.py launch-options <ファイル>...
      #if DEBUG の外で、起動引数（options.<名前>・launchOptions.<名前>）を読んでいる所を探す。
      Release のビルドで読んでよい起動引数は selfCheck だけ（--self-check）。ほかを読んでいれば 1 で終わる
  swift_debug_scope.py find <文字列> <ファイル>...
      コード（コメントは除く）にその文字列がある行を、「debug <ファイル>:<行>」か「release <ファイル>:<行>」で出す

#if の条件は DEBUG と !DEBUG（と、DEBUG を含まない条件）だけ読む。DEBUG を含む複雑な条件（DEBUG && …）は、
Release に入るかを取り違えないよう、読めないものとして 2 で終わる。
調べるのは「options.xxx」の形の読み取りだけで、options を別の名前に入れ替えて読む書き方（let o = options; o.xxx）は見つけられない。
文字列の中の options.xxx は、補間（\\(options.xxx)）のコードかもしれないので、文字列の中も調べる（見つかったら止まる側に倒す）。
"""

import re
import sys

RELEASE_ALLOWED_OPTIONS = {"selfCheck"}
OPTION_READ = re.compile(r"(?<![A-Za-z0-9_])(?:launchOptions|options)\s*[?!]?\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)")
MENTIONS_DEBUG = re.compile(r"\bDEBUG\b")


class Unsupported(Exception):
    pass


def code_lines(text):
    """(行番号, コメントを除いた行) を順に返す。ブロックコメント（入れ子も）と複数行の文字列は行をまたぐ"""
    block = 0
    in_triple = False
    for number, raw in enumerate(text.splitlines(), 1):
        out = []
        in_string = False
        i = 0
        while i < len(raw):
            pair = raw[i : i + 2]
            if block:
                if pair == "/*":
                    block += 1
                    i += 2
                elif pair == "*/":
                    block -= 1
                    i += 2
                else:
                    i += 1
                continue
            if in_triple:
                if raw.startswith('"""', i):
                    in_triple = False
                    out.append('"""')
                    i += 3
                else:
                    out.append(raw[i])
                    i += 1
                continue
            if in_string:
                if raw[i] == "\\":
                    out.append(raw[i : i + 2])
                    i += 2
                    continue
                if raw[i] == '"':
                    in_string = False
                out.append(raw[i])
                i += 1
                continue
            if raw.startswith('"""', i):
                in_triple = True
                out.append('"""')
                i += 3
            elif raw[i] == '"':
                in_string = True
                out.append('"')
                i += 1
            elif pair == "//":
                break
            elif pair == "/*":
                block = 1
                i += 2
            else:
                out.append(raw[i])
                i += 1
        yield number, "".join(out)


def condition_kind(condition):
    """#if の条件が debug（DEBUG のときだけ）・release（DEBUG でないときだけ）・neutral（DEBUG に関係しない）のどれか"""
    compact = re.sub(r"\s+", "", condition)
    if compact in ("DEBUG", "(DEBUG)"):
        return "debug"
    if compact in ("!DEBUG", "!(DEBUG)"):
        return "release"
    if MENTIONS_DEBUG.search(condition):
        raise Unsupported("読めない条件です（#if DEBUG か #if !DEBUG だけにしてください）: #if %s" % condition.strip())
    return "neutral"


def frame_is_debug(frame):
    """いまの枝が DEBUG のビルドだけに入るか"""
    kind, branch = frame
    if kind == "debug":
        return branch == 0
    if kind == "release":
        return branch > 0
    return False


def scoped_lines(text):
    """(行番号, コード, DEBUG のビルドだけに入る行か) を順に返す。#if などの行そのものは返さない"""
    stack = []
    for number, code in code_lines(text):
        stripped = code.strip()
        if stripped.startswith("#if"):
            try:
                kind = condition_kind(stripped[3:])
            except Unsupported as error:
                raise Unsupported("%d 行目: %s" % (number, error)) from None
            stack.append((kind, 0))
        elif stripped.startswith("#elseif"):
            if not stack:
                raise Unsupported("%d 行目: #elseif に対応する #if がありません" % number)
            if MENTIONS_DEBUG.search(stripped):
                raise Unsupported("%d 行目: 読めない条件です: %s" % (number, stripped))
            kind, branch = stack.pop()
            stack.append((kind, branch + 1))
        elif stripped.startswith("#else"):
            if not stack:
                raise Unsupported("%d 行目: #else に対応する #if がありません" % number)
            kind, branch = stack.pop()
            stack.append((kind, branch + 1))
        elif stripped.startswith("#endif"):
            if not stack:
                raise Unsupported("%d 行目: #endif に対応する #if がありません" % number)
            stack.pop()
        else:
            yield number, code, any(frame_is_debug(frame) for frame in stack)
    if stack:
        raise Unsupported("#endif が足りません（#if が閉じていません）")


def scoped_file(path):
    """scoped_lines をファイルに使う。読めない条件は、ファイルの名前を付けて Unsupported にする"""
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    try:
        yield from scoped_lines(text)
    except Unsupported as error:
        raise Unsupported("%s: %s" % (path, error)) from None


def check_launch_options(paths):
    """Release にも入るコードが読んでいる、DEBUG 専用の起動引数。(ファイル, 行, 名前) の一覧"""
    violations = []
    for path in paths:
        for number, code, in_debug in scoped_file(path):
            if in_debug:
                continue
            for match in OPTION_READ.finditer(code):
                if match.group(1) not in RELEASE_ALLOWED_OPTIONS:
                    violations.append((path, number, match.group(0).replace(" ", "")))
    return violations


def main(argv):
    if len(argv) >= 3 and argv[1] == "launch-options":
        violations = check_launch_options(argv[2:])
        for path, number, text in violations:
            print(
                "%s:%d: %s は #if DEBUG の外にあります（Release でも読んでよい起動引数は %s だけです）"
                % (path, number, text, ", ".join(sorted(RELEASE_ALLOWED_OPTIONS)))
            )
        return 1 if violations else 0
    if len(argv) >= 4 and argv[1] == "find":
        needle = argv[2]
        for path in argv[3:]:
            for number, code, in_debug in scoped_file(path):
                if needle in code:
                    print("%s %s:%d" % ("debug" if in_debug else "release", path, number))
        return 0
    sys.stderr.write("使い方: swift_debug_scope.py launch-options <ファイル>... | find <文字列> <ファイル>...\n")
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Unsupported as error:
        sys.stderr.write("%s\n" % error)
        sys.exit(2)

"""利用ガイドの Markdown（docs/user-guide.md・docs/user-guide.en.md）から、販売サイトのページ（site/guide.html・site/en/guide.html）を作る。
ガイドを直したら、これで両方のページを作り直す。--check はページを書き換えずに、作り直しが要るかだけを確かめる（scripts/tests/site_test.sh が使う）。
使い方: python3 -I scripts/build-guide.py [--check] [--root <リポジトリ（既定: このスクリプトの1つ上）>]
"""
import argparse
import difflib
import html
import os
import re
import sys

# 見出し（## 〜 ####）のアンカー。日本語と英語で同じ id にするので、見出しの文字ではなく並び順で決める。
# 節を足したり消したりしたら、ここも同じ位置で直す（一度公開した id は変えない。アプリやほかのページが #id で開く）
IDS = [
    (2, "about"), (3, "requirements"),
    (2, "getting-started"), (3, "install"), (3, "accessibility"), (3, "welcome-guide"),
    (2, "basics"), (3, "open"), (3, "run"), (3, "cancel"), (3, "hold-buttons"), (3, "while-open"),
    (3, "pages"), (3, "global-and-launcher"), (3, "haptics"),
    (2, "menu-bar"),
    (2, "profiles"), (3, "profile-list"), (3, "pages-and-buttons"), (3, "shared-buttons"), (3, "undo-and-restore"), (3, "power-editing"),
    (3, "inspector"), (3, "pick-from-menus"),
    (2, "actions"), (3, "keystrokes"), (3, "open-app"), (3, "url"), (3, "script"), (4, "script-variables"),
    (3, "shortcut"), (3, "menu-item"), (3, "ai"), (3, "file"), (3, "screen-capture"),
    (2, "general"), (3, "opening-and-hud"), (3, "general-profiles"), (3, "feedback"), (3, "advanced"),
    (3, "startup"), (3, "export-import"),
    (2, "license"),
    (2, "updates"),
    (2, "troubleshooting"), (3, "no-accessibility"), (3, "secure-input"), (3, "no-trackpad"),
    (3, "nothing-happens"), (3, "menu-bar-icon-missing"), (3, "opens-by-accident"), (3, "pointer-stuck"),
    (3, "wrong-button"), (3, "script-fails"), (3, "automation"), (3, "menu-item-fails"),
    (3, "ai-unavailable"), (3, "selected-text"), (3, "no-haptics"), (3, "login-item"), (3, "damaged-settings"), (3, "reset"),
    (2, "uninstall"),
]

# 公開する場所（site/ のほかのページの canonical・hreflang と同じ。scripts/check-site.sh が site/index.html の canonical と比べる）
SITE_URL = "https://nonet.astlog.dev/"

# Markdown のリンク先（docs/ からの相対）を、サイトのページに置き換える
LINKS = {"privacy.md": "privacy.html"}


class GuideError(Exception):
    pass


def github_slug(text):
    """GitHub が見出しに付けるアンカー（Markdown の中の #… のリンクはこれを指す）"""
    text = re.sub(r"[*`]", "", text).strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


class Converter:
    def __init__(self, md, source, md_dir):
        self.lines = md.split("\n")
        self.source = source
        self.md_dir = md_dir
        self.headings = []  # (level, id, text)
        self.slugs = {}
        # 見出しに id を振る（位置で決める）
        in_code = False
        found = []
        for line in self.lines:
            if line.startswith("```"):
                in_code = not in_code
                continue
            if in_code:
                continue
            m = re.match(r"^(#{2,4}) (.+)$", line)
            if m:
                found.append((len(m.group(1)), m.group(2)))
        for index, (level, text) in enumerate(found):
            if index >= len(IDS):
                raise GuideError(f"{source}: 見出しが IDS より多い（「{text}」）。scripts/build-guide.py の IDS に id を足してください")
            expected_level, ident = IDS[index]
            if level != expected_level:
                raise GuideError(
                    f"{source}: {index + 1}番目の見出し「{text}」のレベルが {level} です（IDS では {expected_level} の {ident}）。"
                    "節を足したり消したりしたら、IDS も同じ位置で直してください"
                )
            self.headings.append((level, ident, text))
            self.slugs[github_slug(text)] = ident
        if len(found) != len(IDS):
            raise GuideError(f"{source}: 見出しが {len(found)} 個ですが、IDS は {len(IDS)} 個です")

    def inline(self, text):
        parts = re.split(r"(`[^`]*`)", text)
        out = []
        for part in parts:
            if part.startswith("`") and part.endswith("`") and len(part) >= 2:
                out.append("<code>" + html.escape(part[1:-1], quote=False) + "</code>")
                continue
            s = html.escape(part, quote=False)
            s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
            s = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", self.link, s)
            out.append(s)
        return "".join(out)

    def link(self, m):
        label, url = m.group(1), m.group(2)
        if url.startswith("#"):
            ident = self.slugs.get(url[1:])
            if not ident:
                raise GuideError(f"{self.source}: リンク先の見出しがありません: {url}")
            url = "#" + ident
        elif not re.match(r"^[a-z]+:", url):
            path = url.split("#", 1)[0]
            if not os.path.exists(os.path.join(self.md_dir, path)):
                raise GuideError(f"{self.source}: リンク先がありません: {url}")
            if path not in LINKS:
                raise GuideError(f"{self.source}: サイトでの行き先が分からないリンクです: {url}（scripts/build-guide.py の LINKS に足してください）")
            url = LINKS[path] + url[len(path):]
        return f'<a href="{html.escape(url)}">{label}</a>'

    def convert(self):
        out = []
        i = 0
        heading_index = 0
        lines = self.lines
        title = None
        while i < len(lines):
            line = lines[i]
            if not line.strip():
                i += 1
                continue
            if line.startswith("<!--"):
                while "-->" not in lines[i]:
                    i += 1
                i += 1
                continue
            if line.startswith("# "):
                title = line[2:]
                i += 1
                continue
            m = re.match(r"^(#{2,4}) (.+)$", line)
            if m:
                level, ident, text = self.headings[heading_index]
                heading_index += 1
                out.append(f'<h{level} id="{ident}">{self.inline(text)}</h{level}>')
                i += 1
                continue
            if line.startswith("```"):
                lang = line[3:].strip()
                i += 1
                code = []
                while not lines[i].startswith("```"):
                    code.append(lines[i])
                    i += 1
                i += 1
                cls = f' class="language-{lang}"' if lang else ""
                out.append(f"<pre><code{cls}>" + html.escape("\n".join(code), quote=False) + "</code></pre>")
                continue
            if line.startswith("|"):
                rows = []
                while i < len(lines) and lines[i].startswith("|"):
                    rows.append(lines[i])
                    i += 1
                out.append(self.table(rows))
                continue
            if re.match(r"^(\s*)([-*]|\d+\.) ", line):
                block = []
                while i < len(lines) and lines[i].strip() and (re.match(r"^(\s*)([-*]|\d+\.) ", lines[i]) or lines[i].startswith(" ")):
                    block.append(lines[i])
                    i += 1
                out.append(self.list_html(block))
                continue
            para = []
            while i < len(lines) and lines[i].strip() and not re.match(r"^(#|```|\||\s*([-*]|\d+\.) )", lines[i]):
                para.append(lines[i].strip())
                i += 1
            out.append("<p>" + self.inline(" ".join(para)) + "</p>")
        if title is None:
            raise GuideError(f"{self.source}: 「# 」の題名がありません")
        return title, out

    def table(self, rows):
        def cells(row):
            row = row.strip()
            if not (row.startswith("|") and row.endswith("|")):
                raise GuideError(f"{self.source}: 表の行が | で始まって | で終わっていません: {row}")
            return [c.strip() for c in row[1:-1].split("|")]

        header = cells(rows[0])
        body = [cells(r) for r in rows[2:]]
        out = ['<div class="table-wrap">', "  <table>", "    <thead>", "      <tr>"]
        out += [f'        <th scope="col">{self.inline(c)}</th>' for c in header]
        out += ["      </tr>", "    </thead>", "    <tbody>"]
        for r in body:
            if len(r) != len(header):
                raise GuideError(f"{self.source}: 表の列の数が見出しと違います: {' | '.join(r)}")
            out.append("      <tr>" + "".join(f"<td>{self.inline(c)}</td>" for c in r) + "</tr>")
        out += ["    </tbody>", "  </table>", "</div>"]
        return "\n".join(out)

    def list_html(self, block):
        items = []
        for line in block:
            m = re.match(r"^(\s*)([-*]|\d+\.) (.*)$", line)
            if not m:
                raise GuideError(f"{self.source}: 箇条書きの中に、項目でない行があります: {line.strip()}")
            items.append((len(m.group(1)), "ol" if m.group(2)[0].isdigit() else "ul", m.group(3)))
        html_lines, _ = self.render_items(items, 0)
        return "\n".join(html_lines)

    def render_items(self, items, start, depth=0):
        indent, kind, _ = items[start]
        pad = "  " * depth
        out = [f"{pad}<{kind}>"]
        i = start
        while i < len(items) and items[i][0] == indent:
            _, _, text = items[i]
            i += 1
            if i < len(items) and items[i][0] > indent:
                child, i = self.render_items(items, i, depth + 2)
                out.append(f"{pad}  <li>{self.inline(text)}")
                out += child
                out.append(f"{pad}  </li>")
            else:
                out.append(f"{pad}  <li>{self.inline(text)}</li>")
        out.append(f"{pad}</{kind}>")
        return out, i

    def toc(self):
        sections = []
        for level, ident, text in self.headings:
            if level == 2:
                sections.append((ident, text, []))
            elif level == 3:
                sections[-1][2].append((ident, text))
        out = ["<ol>"]
        for ident, text, subs in sections:
            link = f'<a href="#{ident}">{self.inline(text)}</a>'
            if not subs:
                out.append(f"  <li>{link}</li>")
                continue
            out.append(f"  <li>{link}")
            out.append("    <ol>")
            out += [f'      <li><a href="#{i}">{self.inline(t)}</a></li>' for i, t in subs]
            out.append("    </ol>")
            out.append("  </li>")
        out.append("</ol>")
        return out


LOGO = '<symbol id="i-logo" viewBox="0 0 24 24"><rect x="2" y="2" width="5" height="5" rx="1.5"/><rect x="9.5" y="2" width="5" height="5" rx="1.5"/><rect x="17" y="2" width="5" height="5" rx="1.5"/><rect x="2" y="9.5" width="5" height="5" rx="1.5"/><rect x="9.5" y="9.5" width="5" height="5" rx="1.5" fill="currentColor" stroke="none"/><rect x="17" y="9.5" width="5" height="5" rx="1.5"/><rect x="2" y="17" width="5" height="5" rx="1.5"/><rect x="9.5" y="17" width="5" height="5" rx="1.5"/><rect x="17" y="17" width="5" height="5" rx="1.5"/></symbol>'

# ページごとの決まった部分（ヘッダーとフッターは index.html と同じにする）
PAGES = [
    dict(
        md="docs/user-guide.md",
        out="site/guide.html",
        lang="ja",
        title="利用ガイド — Nonet",
        description="Nonet の使い方。上の縁から開く9つのボタン、プロファイルの編集、アクションの種類、設定、ライセンス、困ったときの対処をまとめています。",
        path="guide.html",
        prefix="",
        skip="本文へ移動",
        nav_label="サイト内の移動",
        nav=[("./#how", "使い方"), ("./#features", "機能"), ("./#pricing", "価格"), ("./#faq", "よくある質問")],
        guide_label="利用ガイド",
        lang_link='<a class="lang-link" href="en/guide.html" hreflang="en" lang="en">English</a>',
        comment="<!-- 原本は docs/user-guide.md。このページは python3 -I scripts/build-guide.py で作る（手で直さない。作り直し忘れは scripts/tests/site_test.sh が見つける） -->",
        toc_label="目次",
        footer_links=[
            '<li><a href="guide.html" aria-current="page">利用ガイド</a></li>',
            '<li><a href="privacy.html">プライバシーポリシー</a></li>',
            '<li><a href="terms.html">利用規約</a></li>',
            '<li><a href="tokushoho.html">特定商取引法に基づく表記</a></li>',
            "<!-- TODO: 問い合わせ先のメールアドレス（index.html と同じ） -->",
            '<li><a href="mailto:support@TODO.invalid">お問い合わせ</a></li>',
            '<li><a href="en/guide.html" hreflang="en" lang="en">English</a></li>',
        ],
        legal="Apple、Mac、MacBook、macOS、Magic Trackpad、Force Touch、Apple Intelligence、Siri、Launchpad、Xcode、Safari は Apple Inc. の商標です。そのほかの製品名は各社の商標です。",
    ),
    dict(
        md="docs/user-guide.en.md",
        out="site/en/guide.html",
        lang="en",
        title="User Guide — Nonet",
        description="How to use Nonet: opening the nine buttons from the top edge, editing profiles, action types, settings, your license and troubleshooting.",
        path="en/guide.html",
        prefix="../",
        skip="Skip to content",
        nav_label="Site",
        nav=[("./#how", "How it works"), ("./#features", "Features"), ("./#pricing", "Pricing"), ("./#faq", "FAQ")],
        guide_label="User guide",
        lang_link='<a class="lang-link" href="../guide.html" hreflang="ja" lang="ja">日本語</a>',
        comment="<!-- The source is docs/user-guide.en.md. This page is built with python3 -I scripts/build-guide.py (don't edit it by hand; scripts/tests/site_test.sh catches a page that wasn't rebuilt) -->",
        toc_label="Contents",
        footer_links=[
            '<li><a href="guide.html" aria-current="page">User guide</a></li>',
            '<li><a href="privacy.html">Privacy policy</a></li>',
            '<li><a href="terms.html">Terms</a></li>',
            '<li><a href="../tokushoho.html" hreflang="ja">Legal notice (Japan)</a></li>',
            "<!-- TODO: support email address (same as index.html) -->",
            '<li><a href="mailto:support@TODO.invalid">Contact</a></li>',
            '<li><a href="../guide.html" hreflang="ja" lang="ja">日本語</a></li>',
        ],
        legal="Apple, Mac, MacBook, macOS, Magic Trackpad, Force Touch, Apple Intelligence, Siri, Launchpad, Xcode and Safari are trademarks of Apple Inc. Other product names are trademarks of their respective owners.",
    ),
]


def indent(lines, n):
    pad = " " * n
    return [pad + l if l else l for l in lines]


def build(root, page):
    """ページの HTML と見出しを返す"""
    path = os.path.join(root, page["md"])
    with open(path, encoding="utf-8") as f:
        md = f.read()
    conv = Converter(md, page["md"], os.path.dirname(path))
    title, body = conv.convert()
    nav = [f'        <li><a href="{href}">{label}</a></li>' for href, label in page["nav"]]
    nav.append(f'        <li><a href="guide.html" aria-current="page">{page["guide_label"]}</a></li>')
    p = page["prefix"]
    out = [
        "<!doctype html>",
        f'<html lang="{page["lang"]}">',
        "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        f"<title>{page['title']}</title>",
        f'<meta name="description" content="{page["description"]}">',
        '<meta name="color-scheme" content="light dark">',
        # 検索に出すページの決まり（scripts/check-site.sh）: 自分の URL の canonical と、日本語・英語・x-default（英語）の hreflang
        f'<link rel="canonical" href="{SITE_URL}{page["path"]}">',
        *[f'<link rel="alternate" hreflang="{lang}" href="{SITE_URL}{path}">'
          for lang, path in (("ja", PAGES[0]["path"]), ("en", PAGES[1]["path"]), ("x-default", PAGES[1]["path"]))],
        f'<link rel="icon" href="{p}favicon.svg" type="image/svg+xml">',
        f'<link rel="apple-touch-icon" href="{p}apple-touch-icon.png">',
        f'<link rel="stylesheet" href="{p}style.css">',
        "</head>",
        "<body>",
        '<svg width="0" height="0" style="position:absolute" aria-hidden="true" focusable="false">',
        "  " + LOGO,
        "</svg>",
        "",
        f'<a class="skip" href="#main">{page["skip"]}</a>',
        "",
        '<header class="site-header">',
        '  <div class="wrap header-inner">',
        '    <a class="brand" href="./"><svg class="logo" aria-hidden="true"><use href="#i-logo"/></svg>Nonet</a>',
        f'    <nav class="site-nav" aria-label="{page["nav_label"]}">',
        "      <ul>",
        *nav,
        "      </ul>",
        "    </nav>",
        '    <div class="header-actions">',
        "      " + page["lang_link"],
        "    </div>",
        "  </div>",
        "</header>",
        "",
        page["comment"],
        '<main id="main" class="doc guide">',
        '  <div class="wrap">',
        f"    <h1>{html.escape(title, quote=False)}</h1>",
        f'    <nav class="toc" aria-label="{page["toc_label"]}">',
        f'      <p class="toc-title" aria-hidden="true">{page["toc_label"]}</p>',
        *indent(conv.toc(), 6),
        "    </nav>",
    ]
    for block in body:
        if block.startswith("<h2"):
            out.append("")
        if block.startswith("<pre>"):
            # コードの中は字下げしない（そのまま表示される）
            lines = block.split("\n")
            out += ["    " + lines[0]] + lines[1:]
        else:
            out += indent(block.split("\n"), 4)
    out += [
        "  </div>",
        "</main>",
        "",
        '<footer class="site-footer">',
        '  <div class="wrap footer-inner">',
        '    <div class="footer-top">',
        '      <a class="brand" href="./"><svg class="logo" aria-hidden="true"><use href="#i-logo"/></svg>Nonet</a>',
        '      <ul class="footer-links">',
        *["        " + l for l in page["footer_links"]],
        "      </ul>",
        "    </div>",
        '    <div class="legal">',
        f"      <p>{page['legal']}</p>",
        "      <p>© 2026 Takanari Okazaki</p>",
        "    </div>",
        "  </div>",
        "</footer>",
        "</body>",
        "</html>",
        "",
    ]
    return "\n".join(out), conv.headings


def main():
    parser = argparse.ArgumentParser(description="利用ガイドの Markdown から site/guide.html・site/en/guide.html を作る")
    parser.add_argument("--check", action="store_true", help="書き換えずに、ページが Markdown から作ったものと同じかを確かめる")
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))), help="リポジトリのフォルダ")
    args = parser.parse_args()

    try:
        built = [(page, *build(args.root, page)) for page in PAGES]
    except (GuideError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    # 日本語と英語で、節の並び（レベルと id）をそろえる
    ja, en = built[0][2], built[1][2]
    if [h[:2] for h in ja] != [h[:2] for h in en]:
        print("error: 日本語と英語の利用ガイドで、見出しの並びが違います", file=sys.stderr)
        return 1

    stale = []
    for page, text, _ in built:
        out = os.path.join(args.root, page["out"])
        if args.check:
            try:
                with open(out, encoding="utf-8") as f:
                    current = f.read()
            except OSError:
                current = ""
            if current != text:
                stale.append(page["out"])
                diff = difflib.unified_diff(current.splitlines(), text.splitlines(), page["out"], f"{page['md']} から作ったもの", lineterm="", n=1)
                for line in list(diff)[:20]:
                    print(f"    {line}", file=sys.stderr)
        else:
            with open(out, "w", encoding="utf-8") as f:
                f.write(text)
            print(f"{page['out']} を作りました（{page['md']}、見出し {len(ja)} 個）", file=sys.stderr)
    if stale:
        print(f"error: {'・'.join(stale)} が Markdown と違います。python3 -I scripts/build-guide.py で作り直してください", file=sys.stderr)
        return 1
    if args.check:
        print("利用ガイドのページは Markdown と同じです", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

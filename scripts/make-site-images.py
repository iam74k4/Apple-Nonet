#!/usr/bin/env python3
"""販売ページの画像を作る（手で描かず、ページとアプリのアイコンから作る）。

  site/images/og-ja.png・site/images/og-en.png
      SNS で共有したときの画像（1200×630）。各言語の index.html の見出し（h1）と、HUD のデモ（静止画。
      JavaScript が無いときと同じ絵）を、site/style.css のまま headless の Google Chrome で描く
  site/apple-touch-icon.png
      ホーム画面のアイコン（180×180）。アプリのアイコン（App/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png）
      の黒い板の部分を、黒の正方形いっぱいに描く（iOS が角を丸める）

見出し・デモ・アプリのアイコンを変えたら作り直す。macOS の sips と Google Chrome が要る。
使い方: python3 -I scripts/make-site-images.py [--chrome <Chrome の実行ファイル>]
"""

import argparse
import html
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
APP_ICON = ROOT / "App/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
DEFAULT_CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

OG_WIDTH, OG_HEIGHT = 1200, 630
TOUCH_ICON_SIZE = 180
# アプリのアイコンの下絵（1024）での板の位置と大きさ（scripts/make-icon.swift の IconGeometry.plate）。
# 板の外（角）は、板のグラデーションの下の色（#000000。scripts/make-icon.swift の IconPalette.plateBottom）で埋める
ICON_CANVAS, ICON_PLATE_ORIGIN, ICON_PLATE_SIZE = 1024, 100, 824

# 見出しの下に添える1行。ページの価格・試用の文言と合わせる
TAGLINES = {
    "ja": "14日間無料 ・ 買い切り ・ macOS 14 以降",
    "en": "14-day free trial · One-time purchase · macOS 14 or later",
}

OG_CSS = f"""
html, body {{ width: {OG_WIDTH}px; height: {OG_HEIGHT}px; margin: 0; overflow: hidden; }}
.og {{
  box-sizing: border-box;
  width: {OG_WIDTH}px;
  height: {OG_HEIGHT}px;
  padding: 56px 72px;
  display: grid;
  grid-template-columns: minmax(0, 1fr) 460px;
  gap: 56px;
  align-items: center;
}}
.og-copy {{ display: flex; flex-direction: column; gap: 24px; }}
.og .brand {{ font-size: 28px; gap: 12px; }}
.og .brand .logo {{ width: 36px; height: 36px; }}
.og .eyebrow {{ font-size: 18px; }}
.og h1 {{ font-size: 62px; line-height: 1.22; letter-spacing: 0.01em; }}
/* 日本語の見出しは、1行目（「トラックパッドが、」）が折り返さない大きさにする */
.og h1:lang(ja) {{ font-size: 52px; }}
.og .og-tagline {{ font-size: 22px; color: var(--fg-soft); }}
.og .demo {{ margin: 0; }}
.og .demo-stage {{ max-width: 460px; }}
"""


def die(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def first(pattern, text, what):
    match = re.search(pattern, text, re.S)
    if match is None:
        die(f"{what} が見つかりません")
    return match


def element_from(text, start_tag, what):
    """start_tag で始まる <div> を、対応する </div> まで切り出す"""
    start = text.find(start_tag)
    if start < 0:
        die(f"{what} が見つかりません")
    depth = 0
    for match in re.finditer(r"<(/?)div\b[^>]*>", text[start:]):
        depth += -1 if match.group(1) else 1
        if depth == 0:
            return text[start : start + match.end()]
    die(f"{what} の終わりが見つかりません")


def og_page(lang, page):
    source = page.read_text(encoding="utf-8")
    sprite = first(r'<svg width="0" height="0".*?</svg>', source, f"{page} の SVG のシンボル").group(0)
    heading = first(r"<h1>(.*?)</h1>", source, f"{page} の h1").group(1)
    eyebrow = first(r'<p class="eyebrow"[^>]*>(.*?)</p>', source, f"{page} の eyebrow").group(1)
    stage = element_from(source, '<div class="demo-stage"', f"{page} のデモ")
    stylesheet = (SITE / "style.css").as_uri()
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<link rel="stylesheet" href="{stylesheet}">
<style>{OG_CSS}</style>
</head>
<body>
{sprite}
<div class="og">
  <div class="og-copy">
    <p class="brand"><svg class="logo" aria-hidden="true"><use href="#i-logo"/></svg>Nonet</p>
    <p class="eyebrow" lang="en">{eyebrow}</p>
    <h1>{heading}</h1>
    <p class="og-tagline">{html.escape(TAGLINES[lang])}</p>
  </div>
  <figure class="demo">{stage}</figure>
</div>
</body>
</html>
"""


def touch_icon_page():
    scale = TOUCH_ICON_SIZE / ICON_PLATE_SIZE
    size = ICON_CANVAS * scale
    offset = -ICON_PLATE_ORIGIN * scale
    return f"""<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
html, body {{ width: {TOUCH_ICON_SIZE}px; height: {TOUCH_ICON_SIZE}px; margin: 0; overflow: hidden; background: #000000; }}
img {{ position: absolute; left: {offset:.3f}px; top: {offset:.3f}px; width: {size:.3f}px; height: {size:.3f}px; }}
</style>
</head>
<body><img src="{APP_ICON.as_uri()}" alt=""></body>
</html>
"""


def render(chrome, profile, page, output, width, height):
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    command = [
        chrome,
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--no-first-run",
        "--no-default-browser-check",
        "--allow-file-access-from-files",
        f"--user-data-dir={profile}",
        "--force-device-scale-factor=1",
        # ライトの配色で描く（システムがダークでも）
        "--blink-settings=preferredColorScheme=1",
        f"--window-size={width},{height}",
        f"--screenshot={output}",
        page.as_uri(),
    ]
    result = subprocess.run(command, capture_output=True, text=True, timeout=120)
    if result.returncode != 0 or not output.exists():
        die(f"Chrome で {output.name} を描けませんでした:\n{result.stderr[-2000:]}")
    size = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(output)], capture_output=True, text=True, check=True)
    numbers = [int(value) for value in re.findall(r"pixel(?:Width|Height): (\d+)", size.stdout)]
    if numbers != [width, height]:
        die(f"{output} の大きさが {width}×{height} ではありません（{numbers}）")
    print(f"{output.relative_to(ROOT)}（{width}×{height}）")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--chrome", default=DEFAULT_CHROME, help="Google Chrome（か Chromium）の実行ファイル")
    args = parser.parse_args()
    if not pathlib.Path(args.chrome).exists() and shutil.which(args.chrome) is None:
        die(f"Chrome がありません: {args.chrome}（--chrome で指定する）")
    if shutil.which("sips") is None:
        die("sips がありません（macOS で動かす）")
    if not APP_ICON.exists():
        die(f"アプリのアイコンがありません: {APP_ICON}（swift scripts/make-icon.swift で作る）")

    with tempfile.TemporaryDirectory(prefix="nonet-site-images.") as work:
        work = pathlib.Path(work)
        profile = work / "profile"
        for lang, page in (("ja", SITE / "index.html"), ("en", SITE / "en" / "index.html")):
            source = work / f"og-{lang}.html"
            source.write_text(og_page(lang, page), encoding="utf-8")
            render(args.chrome, profile, source, SITE / "images" / f"og-{lang}.png", OG_WIDTH, OG_HEIGHT)
        source = work / "apple-touch-icon.html"
        source.write_text(touch_icon_page(), encoding="utf-8")
        render(args.chrome, profile, source, SITE / "apple-touch-icon.png", TOUCH_ICON_SIZE, TOUCH_ICON_SIZE)


if __name__ == "__main__":
    main()

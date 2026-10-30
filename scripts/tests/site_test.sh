# 販売ページ（site/）と、それを確かめる scripts/check-site.sh のテスト

# 問題の無い最小のサイトを TEST_TMP/site に作る
write_fixture_site() {
  SITE="$TEST_TMP/site"
  mkdir -p "$SITE/en"
  cat >"$SITE/index.html" <<'EOF'
<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>テスト</title>
<meta name="description" content="テスト用のページ">
<link rel="stylesheet" href="style.css">
<link rel="canonical" href="https://nonet.test/">
<link rel="alternate" hreflang="en" href="https://nonet.test/en/">
<script src="script.js" defer></script>
</head>
<body>
<main id="main">
<h1>見出し</h1>
<a href="#main">本文</a> <a href="en/">English</a> <a href="https://nonet.test/">外部</a>
<img src="logo.svg" alt="ロゴ">
</main>
<footer><a href="guide.html">ガイド</a> <a href="privacy.html">プライバシー</a> Stream Deck は Corsair Memory, Inc. の商標です。</footer>
</body>
</html>
EOF
  sed -e 's/lang="ja"/lang="en"/' -e 's|href="en/"|href="../"|' -e 's|href="style.css"|href="../style.css"|' \
    -e 's|src="logo.svg"|src="../logo.svg"|' -e 's|src="script.js"|src="../script.js"|' "$SITE/index.html" >"$SITE/en/index.html"
  cp "$SITE/index.html" "$SITE/privacy.html"
  cp "$SITE/en/index.html" "$SITE/en/privacy.html"
  cp "$SITE/index.html" "$SITE/guide.html"
  cp "$SITE/en/index.html" "$SITE/en/guide.html"
  printf 'body { color: black; background: url("bg.svg"); }\n' >"$SITE/style.css"
  printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' >"$SITE/logo.svg"
  cp "$SITE/logo.svg" "$SITE/bg.svg"
  printf '// コメントの // は URL ではない\nconst a = "x"; // 終わり\n' >"$SITE/script.js"
}

check_fixture() {
  run "$ROOT/scripts/check-site.sh" "$@" "$SITE"
}

test_real_site_passes_checks() {
  run "$ROOT/scripts/check-site.sh"
  assert_status 0
  assert_contains "$OUT" "サイトに問題はありません"
}

test_fixture_site_passes() {
  write_fixture_site
  check_fixture
  assert_status 0
}

test_broken_links_and_anchors_are_found() {
  write_fixture_site
  printf '<a href="missing.html">x</a><a href="#nowhere">y</a><a href="en/#nope">z</a>\n' >>"$SITE/index.html"
  check_fixture
  assert_status 1
  assert_contains "$OUT" "index.html: リンク先がありません: missing.html"
  assert_contains "$OUT" "リンク先の #nowhere がありません"
  assert_contains "$OUT" "リンク先の #nope がありません（en/#nope）"
}

test_basic_html_problems_are_found() {
  write_fixture_site
  sed -i '' -e 's/lang="en"/lang="ja"/' -e '/name="description"/d' "$SITE/en/index.html"
  printf '<h1>二つ目</h1>\n<img src="logo.svg">\n' >>"$SITE/index.html"
  check_fixture
  assert_status 1
  assert_contains "$OUT" "en/index.html: <html lang> が「en」ではありません"
  assert_contains "$OUT" "en/index.html: <meta name=\"description\"> がありません"
  assert_contains "$OUT" "index.html: <h1> は 1 つにしてください（いまは 2）"
  assert_contains "$OUT" "alt の無い画像があります"
}

test_external_resources_are_rejected() {
  write_fixture_site
  printf '<script src="https://cdn.nonet.test/x.js"></script>\n' >>"$SITE/index.html"
  printf '<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+JP" rel="stylesheet">\n' >>"$SITE/en/index.html"
  printf '@import url("https://fonts.googleapis.com/css2");\n' >>"$SITE/style.css"
  check_fixture
  assert_status 1
  assert_contains "$OUT" "index.html: 外部のスクリプトを読み込んでいます（<script> の https://cdn.nonet.test/x.js）"
  assert_contains "$OUT" "en/index.html: 外部のスタイル・フォント・アイコンなどを読み込んでいます（<link> の https://fonts.googleapis.com/"
  assert_contains "$OUT" "style.css: 外部のファイルを読み込んでいます"
}

# 1 行の <script src> と <link rel=stylesheet> 以外の書き方でも、外部の読み込みを見逃さない
test_external_resources_in_other_forms_are_rejected() {
  write_fixture_site
  cat >>"$SITE/index.html" <<'EOF'
<style>@import url("https://fonts.googleapis.com/css2?family=Noto+Sans+JP");</style>
<link rel="icon" href="https://cdn.nonet.test/icon.png">
<img src='https://pixel.nonet.test/p.gif' alt="">
<iframe
  title="動画"
  src="https://www.youtube.com/embed/x"></iframe>
EOF
  cat >>"$SITE/en/index.html" <<'EOF'
<IMG SRC="//cdn.nonet.test/a.png" ALT="a">
<img src="../logo.svg" srcset="../logo.svg 1x, https://cdn.nonet.test/b.png 2x" alt="b">
<video poster="https://cdn.nonet.test/poster.jpg"><source src="https://cdn.nonet.test/v.mp4"></video>
<div style="background: URL( 'https://cdn.nonet.test/bg.png' )"></div>
EOF
  cat >"$SITE/bg.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="https://cdn.nonet.test/i.png"/></svg>
EOF
  printf 'fetch("https://analytics.nonet.test/hit");\n' >>"$SITE/script.js"
  check_fixture
  assert_status 1
  assert_contains "$OUT" "index.html: 外部のファイルを読み込んでいます（<style> や style 属性の @import・url(https://…)）"
  assert_contains "$OUT" "index.html: 外部のスタイル・フォント・アイコンなどを読み込んでいます（<link> の https://cdn.nonet.test/icon.png）"
  assert_contains "$OUT" "index.html: 外部の画像や埋め込みを読み込んでいます（<img> の https://pixel.nonet.test/p.gif）"
  assert_contains "$OUT" "index.html: 外部の画像や埋め込みを読み込んでいます（<iframe> の https://www.youtube.com/embed/x）"
  assert_contains "$OUT" "en/index.html: 外部の画像や埋め込みを読み込んでいます（<img> の //cdn.nonet.test/a.png）"
  assert_contains "$OUT" "en/index.html: 外部の画像や埋め込みを読み込んでいます（<img> の ../logo.svg 1x, https://cdn.nonet.test/b.png 2x）"
  assert_contains "$OUT" "en/index.html: 外部の画像や埋め込みを読み込んでいます（<video> の https://cdn.nonet.test/poster.jpg）"
  assert_contains "$OUT" "en/index.html: 外部の画像や埋め込みを読み込んでいます（<source> の https://cdn.nonet.test/v.mp4）"
  assert_contains "$OUT" "en/index.html: 外部のファイルを読み込んでいます（<style> や style 属性"
  assert_contains "$OUT" "bg.svg: 外部の画像や埋め込みを読み込んでいます（<image> の https://cdn.nonet.test/i.png）"
  assert_contains "$OUT" "script.js: 外部の URL があります"
}

# リンク・関係を示すだけの <link>・ローカルのファイルは、外部の読み込みではない
test_links_and_local_resources_are_allowed() {
  write_fixture_site
  cat >>"$SITE/index.html" <<'EOF'
<a
  href='https://store.nonet.test/buy'>購入</a>
<link rel="alternate" type="application/rss+xml" href="https://nonet.test/updates/appcast.xml">
<img src='logo.svg' srcset="logo.svg 1x, bg.svg 2x" alt="ロゴ">
<div style="background: url('bg.svg')"></div>
EOF
  check_fixture
  assert_status 0
  assert_contains "$OUT" "サイトに問題はありません"
}

test_trademark_notice_and_privacy_link_are_required() {
  write_fixture_site
  sed -i '' -e 's/Corsair Memory, Inc. の商標です。//' -e 's|<a href="privacy.html">プライバシー</a>||' "$SITE/index.html"
  check_fixture
  assert_status 1
  assert_contains "$OUT" "index.html: Stream Deck の商標の表記（Corsair Memory, Inc.）がありません"
  assert_contains "$OUT" "index.html: プライバシーポリシーへのリンクがありません"
}

test_strict_mode_fails_on_placeholders() {
  write_fixture_site
  check_fixture --strict
  assert_status 0
  printf '<!-- TODO: 価格 -->\n<a href="https://TODO.invalid/buy">購入</a>\n' >>"$SITE/index.html"
  check_fixture
  assert_status 0
  assert_contains "$OUT" "公開前に埋めるところ（--strict で失敗にする）: 2 か所"
  check_fixture --strict
  assert_status 1
  assert_contains "$OUT" "仮の値が残っています: index.html:"
  assert_contains "$OUT" "TODO.invalid/buy"
}

test_pages_and_assets_exist() {
  local file
  for file in index.html en/index.html privacy.html en/privacy.html guide.html en/guide.html style.css script.js favicon.svg; do
    assert_file "$ROOT/site/$file"
  done
}

test_japanese_page_carries_the_concept() {
  local page
  page="$(cat "$ROOT/site/index.html")"
  assert_contains "$page" "Stream Deckは、"
  assert_contains "$page" "もう手元にある。"
  assert_contains "$page" "買わなくていい"
  assert_contains "$page" "覚えなくていい"
  assert_contains "$page" "設定しなくていい"
  assert_contains "$page" "14日間"
  assert_contains "$page" "macOS 14"
}

test_demo_markup_matches_the_script() {
  local page attr name
  # script.js が読む data-* を、両方のページが持っていること
  local attrs
  attrs="$(
    {
      grep -oE 'dataset\.[a-zA-Z]+' "$ROOT/site/script.js" | sed -E 's/^dataset\.//; s/([A-Z])/-\1/g' | tr '[:upper:]' '[:lower:]' | sed 's/^/data-/'
      grep -oE '\[data-[a-z-]+\]' "$ROOT/site/script.js" | tr -d '[]'
    } | sort -u
  )"
  [[ -n "$attrs" ]] || fail "script.js から data-* を読めません"
  for page in index.html en/index.html; do
    for attr in $attrs; do
      # data-label は data-label-pause などの一部にもなるので、属性として探す
      name="$attr"
      if [[ "$attr" == data-label ]]; then
        name='data-label="'
      fi
      grep -q -- "$name" "$ROOT/site/$page" || fail "$page に $attr がありません（script.js が使う）"
    done
    assert_eq 9 "$(grep -c 'data-cell ' "$ROOT/site/$page")" "$page のマスの数"
    assert_eq 1 "$(grep -c 'class="cell on"' "$ROOT/site/$page")" "$page の静止画で光らせるマス"
  done
}

# HUD のデモの動き（偽の DOM と時計で script.js を動かす）。node が無ければ飛ばす
test_demo_script_behaves_in_both_languages() {
  if ! command -v node >/dev/null 2>&1; then
    printf 'node が無いので飛ばしました\n'
    return 0
  fi
  local page
  for page in index.html en/index.html; do
    node "$ROOT/scripts/tests/demo_harness.js" "$ROOT/site/$page" "$ROOT/site/script.js"
  done
}

test_languages_link_to_each_other() {
  grep -q 'href="en/" hreflang="en"' "$ROOT/site/index.html" || fail "日本語のページから英語へのリンクがありません"
  grep -q 'href="../" hreflang="ja"' "$ROOT/site/en/index.html" || fail "英語のページから日本語へのリンクがありません"
  grep -q 'href="en/privacy.html"' "$ROOT/site/privacy.html" || fail "プライバシーポリシーの英語版へのリンクがありません"
  grep -q 'href="../privacy.html"' "$ROOT/site/en/privacy.html" || fail "プライバシーポリシーの日本語版へのリンクがありません"
  grep -q 'href="en/guide.html" hreflang="en"' "$ROOT/site/guide.html" || fail "利用ガイドの英語版へのリンクがありません"
  grep -q 'href="../guide.html" hreflang="ja"' "$ROOT/site/en/guide.html" || fail "利用ガイドの日本語版へのリンクがありません"
}

# MARK: 利用ガイド（site/guide.html・site/en/guide.html。原本は docs/user-guide.md・docs/user-guide.en.md）

# 利用ガイドの見出しに id が無い・目次に無い・id が重なっているのを見つける。本文の中のリンクは目次の代わりにならない
test_guide_page_problems_are_found() {
  write_fixture_site
  cat >>"$SITE/guide.html" <<'EOF'
<nav class="toc" aria-label="目次"><a href="#start">はじめに</a></nav>
<h2 id="start">はじめに</h2>
<p>詳しくは<a href="#orphan">目次に無い節</a>へ。</p>
<h2 id="orphan">目次に無い節</h2>
<h3>id の無い節</h3>
<h3 id="start">同じ id</h3>
EOF
  check_fixture
  assert_status 1
  assert_contains "$OUT" "- guide.html: 目次に #orphan へのリンクがありません"
  assert_not_contains "$OUT" "#start へのリンクがありません"
  assert_contains "$OUT" "- guide.html: id の無い見出しがあります: <h3>"
  assert_contains "$OUT" '- guide.html: id が重なっています: id="start"'
  assert_not_contains "$OUT" "en/guide.html"
}

# 目次が無ければ、どの h2 も目次から開けない
test_guide_page_without_a_toc_is_found() {
  write_fixture_site
  printf '<nav class="site-nav"><a href="#start">はじめに</a></nav>\n<h2 id="start">はじめに</h2>\n' >>"$SITE/en/guide.html"
  check_fixture
  assert_status 1
  assert_contains "$OUT" "- en/guide.html: 目次に #start へのリンクがありません"
}

test_index_pages_must_link_to_the_guide() {
  write_fixture_site
  sed -i '' 's|<a href="guide.html">ガイド</a>||' "$SITE/en/index.html"
  check_fixture
  assert_status 1
  assert_contains "$OUT" "- en/index.html: 利用ガイドへのリンクがありません"
  assert_not_contains "$OUT" "- index.html: 利用ガイドへのリンクがありません"
}

# アプリの「利用ガイド」（NONET_SUPPORT_URL）と「プライバシー」（NONET_PRIVACY_URL）だけを書いた xcconfig。
# URL の // は xcconfig ではコメントになるので、https:/$()/… の形で書く
write_app_links_config() {
  printf 'NONET_SUPPORT_URL = %s\nNONET_PRIVACY_URL = %s\n' "$2" "$3" | sed 's|://|:/$()/|' >"$1"
}

check_app_links_fixture() {
  run "$ROOT/scripts/check-site.sh" "$@" --config "$TEST_TMP/Nonet.xcconfig" "$SITE"
}

# フォルダの URL を確かめるためのページ: help/（日本語）と en/help/（英語）。リンクが切れないよう、同じフォルダに guide.html と privacy.html も置く
write_help_pages() {
  local name
  mkdir -p "$SITE/help" "$SITE/en/help"
  for name in index guide privacy; do
    sed 's/lang="en"/lang="ja"/' "$SITE/en/index.html" >"$SITE/help/$name.html"
    sed 's|"\.\./|"../../|g' "$SITE/en/index.html" >"$SITE/en/help/$name.html"
  done
}

# アプリの「利用ガイド」と「プライバシー」が、サイトに無いページを指していない
test_app_links_must_point_to_pages_of_the_site() {
  local config="$TEST_TMP/Nonet.xcconfig"
  write_fixture_site
  write_app_links_config "$config" https://nonet.test/guide.html https://nonet.test/privacy.html
  check_app_links_fixture
  assert_status 0

  # 大文字のホスト・#節・サイトの直下（/。英語は /en/）・フォルダ（/help と /help/。英語は /en/help）も行き先として読める
  write_app_links_config "$config" https://NONET.test/guide.html#troubleshooting https://nonet.test/
  check_app_links_fixture
  assert_status 0
  write_help_pages
  write_app_links_config "$config" https://nonet.test/help https://nonet.test/help/
  check_app_links_fixture
  assert_status 0

  # ほかのホスト（ヘルプセンターなど）を指すなら、このサイトでは確かめない
  write_app_links_config "$config" https://help.nonet.test/guide https://nonet.test/privacy.html
  check_app_links_fixture
  assert_status 0
  assert_not_contains "$OUT" "NONET_SUPPORT_URL"

  write_app_links_config "$config" https://nonet.test/guide.html https://nonet.test/privacy.html
  rm "$SITE/guide.html"
  check_app_links_fixture
  assert_status 1
  assert_contains "$OUT" "Nonet.xcconfig の NONET_SUPPORT_URL（https://nonet.test/guide.html）に当たるページが site/ にありません"
  assert_not_contains "$OUT" "NONET_PRIVACY_URL"
}

# 拡張子を省いた URL（/guide）は、.html を補わないホスト（S3 ＋ CloudFront など）では 404 になる
test_app_links_must_not_drop_the_html_extension() {
  local config="$TEST_TMP/Nonet.xcconfig"
  write_fixture_site
  write_app_links_config "$config" https://nonet.test/guide https://nonet.test/en/privacy
  check_app_links_fixture
  assert_status 1
  assert_contains "$OUT" "NONET_SUPPORT_URL（https://nonet.test/guide）は .html を省いています。補わないホストでは開けないので、/guide.html と書いてください"
  assert_contains "$OUT" "NONET_PRIVACY_URL（https://nonet.test/en/privacy）は .html を省いています。補わないホストでは開けないので、/en/privacy.html と書いてください"
  assert_not_contains "$OUT" "に当たるページが"
}

# 英語で動くアプリは、最後の要素の前に en/ を入れたページ（…/guide.html → …/en/guide.html）を開くので、それもサイトに要る
test_app_links_need_the_english_page() {
  local config="$TEST_TMP/Nonet.xcconfig"
  write_fixture_site
  cp "$SITE/index.html" "$SITE/help.html"
  write_app_links_config "$config" https://nonet.test/help.html#start https://nonet.test/privacy.html
  check_app_links_fixture
  assert_status 1
  assert_contains "$OUT" "- Nonet.xcconfig の NONET_SUPPORT_URL（https://nonet.test/help.html#start）の英語のページ（https://nonet.test/en/help.html。英語で動くアプリが開く）が site/ にありません"
  assert_not_contains "$OUT" "NONET_PRIVACY_URL"
  assert_not_contains "$OUT" "に当たるページが"

  cp "$SITE/en/index.html" "$SITE/en/help.html"
  check_app_links_fixture
  assert_status 0

  # 英語のページを指すと、英語で動くアプリは en/en/ を開いてしまう
  write_app_links_config "$config" https://nonet.test/guide.html https://nonet.test/en/privacy.html
  check_app_links_fixture
  assert_status 1
  assert_contains "$OUT" "NONET_PRIVACY_URL（https://nonet.test/en/privacy.html）の英語のページ（https://nonet.test/en/en/privacy.html。英語で動くアプリが開く）が site/ にありません"
  assert_not_contains "$OUT" "NONET_SUPPORT_URL"

  # フォルダの URL は、フォルダの名前の前に en/ が入る
  write_help_pages
  rm -r "$SITE/en/help"
  write_app_links_config "$config" https://nonet.test/help/ https://nonet.test/privacy.html
  check_app_links_fixture
  assert_status 1
  assert_contains "$OUT" "NONET_SUPPORT_URL（https://nonet.test/help/）の英語のページ（https://nonet.test/en/help/。英語で動くアプリが開く）が site/ にありません"
}

# canonical は属性の順や大文字・小文字にかかわらず読む
test_app_links_use_the_canonical_in_any_form() {
  local config="$TEST_TMP/Nonet.xcconfig"
  write_fixture_site
  sed -i '' 's|<link rel="canonical" href="https://nonet.test/">|<LINK href="https://Nonet.test/" type="text/html" REL="canonical">|' "$SITE/index.html"
  write_app_links_config "$config" https://nonet.test/help.html https://nonet.test/privacy.html
  check_app_links_fixture
  assert_status 1
  assert_contains "$OUT" "NONET_SUPPORT_URL（https://nonet.test/help.html）に当たるページが site/ にありません"
  assert_not_contains "$OUT" "canonical が無い"
}

# canonical がまだ無いサイトでは確かめられない。ふだんは知らせるだけで、--strict（公開の前）では失敗にする
test_app_links_without_a_canonical_fail_in_strict_mode() {
  local config="$TEST_TMP/Nonet.xcconfig"
  write_fixture_site
  sed -i '' '/rel="canonical"/d' "$SITE/index.html"
  write_app_links_config "$config" https://nonet.test/help.html https://nonet.test/privacy.html
  check_app_links_fixture
  assert_status 0
  assert_contains "$OUT" "site/index.html に canonical が無いので、NONET_SUPPORT_URL（https://nonet.test/help.html）の行き先は確かめていません"
  assert_not_contains "$OUT" "に当たるページが"

  check_app_links_fixture --strict
  assert_status 1
  assert_contains "$OUT" "- site/index.html に canonical が無いので、NONET_SUPPORT_URL（https://nonet.test/help.html）がこのサイトのページを指しているか確かめられません"
  assert_contains "$OUT" "- site/index.html に canonical が無いので、NONET_PRIVACY_URL（https://nonet.test/privacy.html）がこのサイトのページを指しているか確かめられません"

  # URL がまだ空（http(s) でない）なら、確かめるものが無い
  printf 'NONET_SUPPORT_URL =\nNONET_PRIVACY_URL =\n' >"$config"
  check_app_links_fixture --strict
  assert_status 0
}

# Markdown の見出し（## 〜 ####）を「レベル 文字」で1行ずつ出す。コードの中は除き、強調・コード・リンクの印は外す
guide_markdown_headings() {
  awk '/^```/ { code = !code; next } !code && /^#{2,4} / { level = index($0, " ") - 1; print level " " substr($0, level + 2) }' "$1" |
    sed -E 's/\*\*//g; s/`//g; s/\[([^]]*)\]\([^)]*\)/\1/g'
}

# ページの見出し（h2〜h4。1行に1つ）を同じ形で出す
guide_html_headings() {
  grep -E '^[[:space:]]*<h[234][ >]' "$1" |
    sed -E 's/^[[:space:]]*<h([234])[^>]*>(.*)<\/h[234]>.*$/\1 \2/; s/<[^>]+>//g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g'
}

# ページは Markdown から作る。節を足したり名前を変えたりしたら、両方を直す
test_guide_pages_match_their_markdown() {
  local pair md page
  for pair in "docs/user-guide.md site/guide.html" "docs/user-guide.en.md site/en/guide.html"; do
    md="${pair% *}"
    page="${pair#* }"
    assert_file "$ROOT/$md"
    [[ -n "$(guide_markdown_headings "$ROOT/$md")" ]] || fail "$md から見出しを読めません"
    assert_eq "$(guide_markdown_headings "$ROOT/$md")" "$(guide_html_headings "$ROOT/$page")" "$page の見出しが $md と違います"
  done
  # 日本語と英語で節の並びと、ページのアンカーをそろえる（言語を切り替えても同じ #id で開ける）
  assert_eq "$(guide_markdown_headings "$ROOT/docs/user-guide.md" | cut -d ' ' -f 1)" \
    "$(guide_markdown_headings "$ROOT/docs/user-guide.en.md" | cut -d ' ' -f 1)" "日本語と英語の利用ガイドの節の並び"
  assert_eq "$(grep -oE '<h[234] id="[^"]+"' "$ROOT/site/guide.html")" \
    "$(grep -oE '<h[234] id="[^"]+"' "$ROOT/site/en/guide.html")" "日本語と英語の利用ガイドのアンカー"
}

# 利用ガイドのページを作る scripts/build-guide.py。python3 が無ければ飛ばす（sync-strings.sh も python3 を使う）
build_guide() {
  run python3 -I "$ROOT/scripts/build-guide.py" "$@"
}

# ページは Markdown から作ったものそのまま（見出しだけでなく本文も）。Markdown を直したら作り直す
test_guide_pages_are_built_from_their_markdown() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 が無いので飛ばしました\n'
    return 0
  fi
  build_guide --check
  assert_status 0
  assert_contains "$OUT" "利用ガイドのページは Markdown と同じです"
}

# 本文だけを直して作り直し忘れたページ・無い見出しや無いファイルへのリンクを見つける
test_guide_build_finds_stale_pages_and_broken_links() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 が無いので飛ばしました\n'
    return 0
  fi
  local repo="$TEST_TMP/repo"
  mkdir -p "$repo/docs" "$repo/site/en"
  cp "$ROOT/docs/user-guide.md" "$ROOT/docs/user-guide.en.md" "$ROOT/docs/privacy.md" "$repo/docs/"
  cp "$ROOT/site/guide.html" "$repo/site/"
  cp "$ROOT/site/en/guide.html" "$repo/site/en/"
  build_guide --check --root "$repo"
  assert_status 0

  # 見出しは同じで、本文の既定値だけが変わった
  sed -i '' 's/| 0.30 s |/| 0.25 s |/' "$repo/docs/user-guide.en.md"
  build_guide --check --root "$repo"
  assert_status 1
  assert_contains "$OUT" "site/en/guide.html が Markdown と違います"
  assert_contains "$OUT" "0.25 s"
  assert_not_contains "$OUT" "--- site/guide.html"
  build_guide --root "$repo"
  assert_status 0
  build_guide --check --root "$repo"
  assert_status 0
  assert_contains "$(cat "$repo/site/en/guide.html")" "<td>0.25 s</td>"

  # 見出しの名前を変えると、それを指す #… のリンクが切れる
  sed -i '' 's/^### Canceling$/### Cancelling a session/' "$repo/docs/user-guide.en.md"
  build_guide --check --root "$repo"
  assert_status 1
  assert_contains "$OUT" "docs/user-guide.en.md: リンク先の見出しがありません: #canceling"

  cp "$ROOT/docs/user-guide.en.md" "$repo/docs/"
  printf '\nSee [the FAQ](faq.md).\n' >>"$repo/docs/user-guide.md"
  build_guide --check --root "$repo"
  assert_status 1
  assert_contains "$OUT" "docs/user-guide.md: リンク先がありません: faq.md"

  # 節を足したら、アンカー（IDS）も足す
  cp "$ROOT/docs/user-guide.md" "$repo/docs/"
  printf '\n## 付録\n\n本文\n' >>"$repo/docs/user-guide.md"
  build_guide --check --root "$repo"
  assert_status 1
  assert_contains "$OUT" "docs/user-guide.md: 見出しが IDS より多い（「付録」）"
}

# 指定した行（正規表現）から、次の見出しの手前までを出す
guide_section() {
  awk -v start="$2" -v stop="$3" '!on && $0 ~ start { on = 1; print; next } on && $0 ~ stop { exit } on { print }' "$1"
}

# 「ターミナルで実行」は一時ファイルを NSWorkspace でターミナルに開かせるだけで、Apple Events を使わない
# （ScriptRunner.swift の TerminalCommandFile）。オートメーションの許可が要るのは、ブラウザの URL を問い合わせるときだけ
test_guides_limit_automation_to_the_browser_url() {
  local runner="$ROOT/Packages/NonetKit/Sources/NonetPlatform/Actions/ScriptRunner.swift" file section terminal
  grep -q 'withApplicationAt' "$runner" || fail "ScriptRunner.swift がターミナルを NSWorkspace で開いていません。利用ガイドのオートメーションの説明を見直してください"
  if grep -qE 'osascript|NSAppleScript|AEDesc|AppleEvent' "$runner"; then
    fail "ScriptRunner.swift が Apple Events を使っています。利用ガイドのオートメーションの説明を見直してください"
  fi
  for file in docs/user-guide.md docs/user-guide.en.md site/guide.html site/en/guide.html; do
    case "$file" in
      *.md) section="$(guide_section "$ROOT/$file" '^### (オートメーションの許可を求められた|macOS asks for Automation permission)$' '^##')" ;;
      *) section="$(guide_section "$ROOT/$file" 'id="automation"' '<h[234][ >]')" ;;
    esac
    [[ -n "$section" ]] || fail "$file にオートメーションの節がありません"
    assert_contains "$section" "NONET_BROWSER_URL" "$file: オートメーションの節"
    case "$file" in
      *.en.md | site/en/*) terminal="Terminal" ;;
      *) terminal="ターミナル" ;;
    esac
    assert_not_contains "$section" "$terminal" "$file: オートメーションの節"
    # 「アクセシビリティの許可」の節などで、オートメーションとターミナルを結び付けていない
    if grep -qE "(オートメーション|Automation).*$terminal|$terminal.*(オートメーション|Automation)" "$ROOT/$file"; then
      fail "$file: ターミナルにオートメーションの許可が要るように書いています" "$(grep -nE "(オートメーション|Automation).*$terminal|$terminal.*(オートメーション|Automation)" "$ROOT/$file")"
    fi
  done
}

# グローバルのランチャーは Page.cellCount × Profile.maxPages 個まで（PresetLibrary.makeGlobalProfile）
test_guides_state_the_launcher_size() {
  local profile="$ROOT/Packages/NonetKit/Sources/NonetCore/Model/Profile.swift" cells pages total file counts
  cells="$(sed -nE 's/.*static let cellCount = ([0-9]+).*/\1/p' "$profile")"
  pages="$(sed -nE 's/.*static let maxPages = ([0-9]+).*/\1/p' "$profile")"
  [[ -n "$cells" && -n "$pages" ]] || fail "Profile.swift から cellCount と maxPages を読めません"
  total=$((cells * pages))
  for file in docs/user-guide.md site/guide.html; do
    grep -qF "最大${total}個（${pages}ページ）並べたランチャー" "$ROOT/$file" || fail "$file: ランチャーが最大${total}個（${pages}ページ）になっていません"
    grep -qF "最大${pages}ページ（${total}マス）" "$ROOT/$file" || fail "$file: 1つのプロファイルが最大${pages}ページ（${total}マス）になっていません"
    counts="$(grep -oE '最大[0-9]+個' "$ROOT/$file" | sort -u)"
    assert_eq "最大${total}個" "$counts" "$file のランチャーの数"
  done
  for file in docs/user-guide.en.md site/en/guide.html; do
    grep -qF "launcher with up to ${total} apps" "$ROOT/$file" || fail "$file: the launcher is not up to ${total} apps"
    grep -qF "(${total} buttons)" "$ROOT/$file" || fail "$file: a profile is not up to ${total} buttons"
  done
}

test_guides_cover_every_script_variable() {
  local variables name file
  variables="$(grep -oE 'NONET_[A-Z_]+' "$ROOT/Packages/NonetKit/Sources/NonetCore/Model/ScriptEnvironment.swift" | sort -u)"
  [[ -n "$variables" ]] || fail "ScriptEnvironment.swift から変数の名前を読めません"
  for file in docs/user-guide.en.md site/guide.html site/en/guide.html; do
    for name in $variables PROJECT_DIR; do
      grep -qE "<code>$name</code>|\`$name\`" "$ROOT/$file" || fail "$file に $name の説明がありません"
    done
  done
}

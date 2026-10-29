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
<footer><a href="privacy.html">プライバシー</a> Stream Deck は Corsair Memory, Inc. の商標です。</footer>
</body>
</html>
EOF
  sed -e 's/lang="ja"/lang="en"/' -e 's|href="en/"|href="../"|' -e 's|href="style.css"|href="../style.css"|' \
    -e 's|src="logo.svg"|src="../logo.svg"|' -e 's|src="script.js"|src="../script.js"|' "$SITE/index.html" >"$SITE/en/index.html"
  cp "$SITE/index.html" "$SITE/privacy.html"
  cp "$SITE/en/index.html" "$SITE/en/privacy.html"
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
  for file in index.html en/index.html privacy.html en/privacy.html style.css script.js favicon.svg; do
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
}

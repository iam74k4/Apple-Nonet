# 販売ページ（site/）と、それを確かめる scripts/check-site.sh のテスト

# 問題の無い最小のページを SITE に1つ書く: 自分の URL の canonical、日本語と英語の組の hreflang（ja・en・x-default）、
# フッターから法的な文書（プライバシー・利用規約・特商法）へのリンク。書いたら sitemap.xml も作り直す。
# 使い方: fixture_page <site/ の中の相対パス（help/index.html など）> [noindex]
fixture_page() {
  local rel="$1" robots="" lang=ja up="" lang_root="" depth ja_path en_path other_home i
  [[ "${2:-}" != noindex ]] || robots='<meta name="robots" content="noindex">'
  depth="$(printf '%s' "$rel" | tr -cd '/' | wc -c | tr -d ' ')"
  for ((i = 0; i < depth; i++)); do up+="../"; done
  case "$rel" in
    en/*)
      lang=en
      for ((i = 1; i < depth; i++)); do lang_root+="../"; done
      ja_path="${rel#en/}"
      en_path="$rel"
      other_home="$up"
      ;;
    *)
      lang_root="$up"
      ja_path="$rel"
      en_path="en/$rel"
      other_home="${up}en/"
      ;;
  esac
  url() {
    case "$1" in
      index.html) printf 'https://nonet.test/' ;;
      */index.html) printf 'https://nonet.test/%s' "${1%index.html}" ;;
      *) printf 'https://nonet.test/%s' "$1" ;;
    esac
  }
  mkdir -p "$(dirname "$SITE/$rel")"
  cat >"$SITE/$rel" <<EOF
<!doctype html>
<html lang="$lang">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>テスト</title>
<meta name="description" content="テスト用のページ">
$robots
<link rel="stylesheet" href="${up}style.css">
<link rel="canonical" href="$(url "$rel")">
<link rel="alternate" hreflang="ja" href="$(url "$ja_path")">
<link rel="alternate" hreflang="en" href="$(url "$en_path")">
<link rel="alternate" hreflang="x-default" href="$(url "$en_path")">
<script src="${up}script.js" defer></script>
</head>
<body>
<main id="main">
<h1>見出し</h1>
<a href="#main">本文</a> <a href="$other_home">English</a> <a href="https://nonet.test/">外部</a>
<img src="${up}logo.svg" alt="ロゴ">
</main>
<footer><a href="${lang_root}guide.html">ガイド</a> <a href="${lang_root}privacy.html">プライバシー</a> <a href="${lang_root}terms.html">利用規約</a> <a href="${up}tokushoho.html">特商法</a> Stream Deck は Corsair Memory, Inc. の商標です。</footer>
</body>
</html>
EOF
  write_fixture_sitemap
}

# SITE の検索に出すページ（noindex でないもの）を並べた sitemap.xml
write_fixture_sitemap() {
  local file rel
  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    while IFS= read -r file; do
      if grep -q 'content="noindex"' "$file"; then
        continue
      fi
      rel="${file#"$SITE/"}"
      case "$rel" in
        index.html) rel="" ;;
        */index.html) rel="${rel%index.html}" ;;
      esac
      printf '  <url><loc>https://nonet.test/%s</loc></url>\n' "$rel"
    done < <(find "$SITE" -type f -name '*.html' | sort)
    printf '</urlset>\n'
  } >"$SITE/sitemap.xml"
}

# 問題の無い最小のサイトを TEST_TMP/site に作る
write_fixture_site() {
  local rel
  SITE="$TEST_TMP/site"
  mkdir -p "$SITE/en"
  printf 'body { color: black; background: url("bg.svg"); }\n' >"$SITE/style.css"
  printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' >"$SITE/logo.svg"
  cp "$SITE/logo.svg" "$SITE/bg.svg"
  printf '// コメントの // は URL ではない\nconst a = "x"; // 終わり\n' >"$SITE/script.js"
  printf 'User-agent: *\nDisallow: /download\n\nSitemap: https://nonet.test/sitemap.xml\n' >"$SITE/robots.txt"
  for rel in index.html en/index.html privacy.html en/privacy.html guide.html en/guide.html terms.html en/terms.html tokushoho.html; do
    fixture_page "$rel"
  done
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

# 外部のスクリプトを読んでよいのは、購入のページ（buy.html・en/buy.html）の Paddle.js だけ。
# ほかのページの Paddle.js・購入のページのほかの外部のスクリプトや画像は止める
test_store_script_is_allowed_only_on_the_purchase_pages() {
  local paddle='<script src="https://cdn.paddle.com/paddle/v2/paddle.js" defer></script>'
  write_fixture_site
  fixture_page buy.html noindex
  fixture_page en/buy.html noindex
  printf '%s\n' "$paddle" >>"$SITE/buy.html"
  printf '%s\n' "${paddle/paddle.js/PADDLE.JS}" >>"$SITE/en/buy.html"
  check_fixture
  assert_status 0
  printf '%s\n' "$paddle" >>"$SITE/index.html"
  printf '<script src="https://cdn.paddle.com/paddle/v2/other.js"></script>\n<img src="https://cdn.paddle.com/p.gif" alt="">\n' >>"$SITE/buy.html"
  mkdir -p "$SITE/shop"
  fixture_page shop/buy.html noindex
  printf '%s\n' "$paddle" >>"$SITE/shop/buy.html"
  check_fixture
  assert_status 1
  assert_contains "$OUT" "- index.html: 外部のスクリプトを読み込んでいます（<script> の https://cdn.paddle.com/paddle/v2/paddle.js）"
  assert_contains "$OUT" "- buy.html: 外部のスクリプトを読み込んでいます（<script> の https://cdn.paddle.com/paddle/v2/other.js）"
  assert_contains "$OUT" "- buy.html: 外部の画像や埋め込みを読み込んでいます（<img> の https://cdn.paddle.com/p.gif）"
  assert_contains "$OUT" "- shop/buy.html: 外部のスクリプトを読み込んでいます"
  assert_not_contains "$OUT" "- en/buy.html:"
}

# 購入のページ: 検索に出さず、Paddle.js と buy.js だけを読み、販売ページとアプリの「購入する」がここを開く
test_purchase_pages_open_the_store_checkout() {
  local page html
  for page in buy.html en/buy.html; do
    html="$(cat "$ROOT/site/$page")"
    assert_contains "$html" '<meta name="robots" content="noindex">' "$page"
    assert_eq 1 "$(grep -c '<script src="https://cdn.paddle.com/paddle/v2/paddle.js" defer></script>' "$ROOT/site/$page")" "$page の Paddle.js"
    assert_eq 2 "$(grep -c '<script ' "$ROOT/site/$page")" "$page のスクリプトは Paddle.js と buy.js だけ"
    assert_contains "$html" "Paddle"
  done
  for page in index.html en/index.html; do
    assert_eq 2 "$(grep -c 'class="btn[^"]*" href="buy.html"' "$ROOT/site/$page")" "$page の「購入する」（価格と最後）"
  done
  assert_contains "$(cat "$ROOT/Config/Nonet.xcconfig")" 'NONET_PURCHASE_URL = https:/$()/nonet.astlog.dev/buy.html' "NONET_PURCHASE_URL"
  # Paddle.js を読むのは購入のページだけ
  assert_eq "buy.html en/buy.html" "$(grep -rlF 'cdn.paddle.com' "$ROOT/site" --include='*.html' | sed "s|^$ROOT/site/||" | sort | tr '\n' ' ' | sed 's/ $//')" \
    "Paddle.js を読むページ"
}

# 購入のページの動き（偽の DOM と偽の Paddle.js で buy.js を動かす）。node が無ければ飛ばす
test_buy_script_behaves() {
  if ! command -v node >/dev/null 2>&1; then
    printf 'node が無いので飛ばしました\n'
    return 0
  fi
  run node "$ROOT/scripts/tests/buy_script_harness.js" "$ROOT/site/buy.js"
  assert_status 0
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

# アプリが開くサイトの節（設定の「ライセンスキーが見つからないときは」: AppLinks.licenseKeyHelpAnchor）が、日英のトップページにある。
# URL は Swift で組み立てるので、check-site.sh のリンクの確かめでは見つからない
test_app_anchors_exist_on_the_site() {
  local anchor
  anchor="$(sed -nE 's/.*licenseKeyHelpAnchor = "([^"]+)".*/\1/p' "$ROOT/Packages/NonetKit/Sources/NonetUI/Settings/SettingsLicenseLink.swift")"
  [[ -n "$anchor" ]] || fail "SettingsLicenseLink.swift に licenseKeyHelpAnchor が見つかりません"
  grep -q "id=\"$anchor\"" "$ROOT/site/index.html" || fail "site/index.html に id=\"$anchor\" がありません"
  grep -q "id=\"$anchor\"" "$ROOT/site/en/index.html" || fail "site/en/index.html に id=\"$anchor\" がありません"
}

# 試すために入れた Paddle のテスト用のトークン（test_）は、公開前の --strict で止める（残すと本当の購入ができない）
test_strict_mode_fails_on_a_sandbox_paddle_token() {
  write_fixture_site
  printf '<div id="checkout" data-paddle-token="test_0123456789abcdef" data-paddle-price="pri_01abc"></div>\n' >>"$SITE/index.html"
  check_fixture
  assert_status 0
  assert_contains "$OUT" "Paddle のテスト用のトークン（test_）が入っています（--strict で失敗にする）: 1 か所"
  check_fixture --strict
  assert_status 1
  assert_contains "$OUT" "Paddle のテスト用のトークン（test_）が残っています"
}

# 埋めた Paddle の値が buy.js の決まった形でなければ、--strict で止める（公開したページが「準備中」のまま購入を開けない）
test_strict_mode_fails_on_a_malformed_paddle_value() {
  write_fixture_site
  printf '<div id="checkout" data-paddle-token="live_tooShort" data-paddle-price="pri_0123456789abcdefghijklmnop"></div>\n' >>"$SITE/index.html"
  check_fixture --strict
  assert_status 1
  assert_contains "$OUT" "Paddle のクライアント用トークン（live_ と 27 文字）の形ではありません"
  assert_not_contains "$OUT" "価格の ID（pri_ と 26 文字）の形ではありません"
  write_fixture_site
  printf '<div id="checkout" data-paddle-token="live_0123456789abcdefghijklmnopq" data-paddle-price="pri_0123456789abcdefghijklmnop"></div>\n' >>"$SITE/index.html"
  check_fixture --strict
  assert_not_contains "$OUT" "の形ではありません"
  # ' で囲んだ値・= の前後に空白がある書き方も読む（buy.js はどれでも読む）
  write_fixture_site
  printf "<div id=\"checkout\" data-paddle-token='live_short' data-paddle-price = \"pri_x\"></div>\n" >>"$SITE/index.html"
  check_fixture --strict
  assert_status 1
  assert_contains "$OUT" "トークン（live_ と 27 文字）の形ではありません"
  assert_contains "$OUT" "価格の ID（pri_ と 26 文字）の形ではありません"
  # = の前に空白のあるトークンを、価格の ID の決まりで見ない（価格の ID を貼ったトークンを通さない）。= の後のタブも読む
  write_fixture_site
  printf '<div id="checkout" data-paddle-token = "pri_0123456789abcdefghijklmnop" data-paddle-price=\t"pri_0123456789abcdefghijklmnop"></div>\n' >>"$SITE/index.html"
  check_fixture --strict
  assert_status 1
  assert_contains "$OUT" "トークン（live_ と 27 文字）の形ではありません"
  assert_not_contains "$OUT" "価格の ID（pri_ と 26 文字）の形ではありません"
}

# 検索に出すページは、自分の URL の canonical と、日英の組の hreflang（ja・en・x-default。どれも絶対の URL）を持つ
test_head_needs_canonical_and_hreflang() {
  write_fixture_site
  check_fixture
  assert_status 0
  # ページを写して作ったときの写し忘れ・相対の URL・x-default の抜け
  sed -i '' 's|<link rel="canonical" href="https://nonet.test/terms.html">|<link rel="canonical" href="https://nonet.test/privacy.html">|' "$SITE/terms.html"
  sed -i '' 's|hreflang="ja" href="https://nonet.test/privacy.html"|hreflang="ja" href="../privacy.html"|' "$SITE/en/privacy.html"
  sed -i '' '/hreflang="x-default"/d' "$SITE/en/index.html"
  # 組の無いページ（特商法）は canonical だけでよく、noindex のページは検索に出さないので何も要らない
  sed -i '' '/hreflang=/d' "$SITE/tokushoho.html"
  fixture_page thanks.html noindex
  sed -i '' '/rel="canonical"/d; /hreflang=/d' "$SITE/thanks.html"
  check_fixture
  assert_status 1
  assert_contains "$OUT" "- terms.html: canonical が https://nonet.test/terms.html ではありません（いまは https://nonet.test/privacy.html）"
  assert_contains "$OUT" "- en/privacy.html: <link rel=\"alternate\" hreflang=\"ja\" href=\"https://nonet.test/privacy.html\"> がありません"
  assert_contains "$OUT" "- en/index.html: <link rel=\"alternate\" hreflang=\"x-default\" href=\"https://nonet.test/en/\"> がありません"
  assert_not_contains "$OUT" "tokushoho.html: "
  assert_not_contains "$OUT" "thanks.html: "
}

# 利用ガイドは scripts/build-guide.py が作るので、足りないものは知らせるだけ（止めない）。ほかのページは止める
test_generated_guide_pages_are_reported_not_failed() {
  write_fixture_site
  sed -i '' '/rel="canonical"/d; s|<a href="terms.html">利用規約</a>||' "$SITE/guide.html"
  check_fixture --strict
  assert_status 0
  assert_contains "$OUT" "guide.html は scripts/build-guide.py が作るページなので止めません。scripts/build-guide.py で直すこと: <link rel=\"canonical\" href=\"https://nonet.test/guide.html\"> がありません"
  assert_contains "$OUT" "guide.html は scripts/build-guide.py が作るページなので止めません。scripts/build-guide.py でフッターに足すリンク: terms.html"
  sed -i '' 's|<a href="terms.html">利用規約</a>||' "$SITE/privacy.html"
  check_fixture
  assert_status 1
  assert_contains "$OUT" "- privacy.html: フッターに terms.html へのリンクがありません"
}

# 法的な文書（プライバシー・利用規約・特商法）は、どのページのフッターからも開ける
test_footer_links_to_the_legal_pages() {
  write_fixture_site
  sed -i '' 's|<a href="../tokushoho.html">特商法</a>||' "$SITE/en/terms.html"
  sed -i '' 's|<footer>.*</footer>|<footer>© 2026</footer>|' "$SITE/en/privacy.html"
  rm "$SITE/terms.html"
  write_fixture_sitemap
  check_fixture
  assert_status 1
  assert_contains "$OUT" "- en/terms.html: フッターに tokushoho.html へのリンクがありません"
  assert_contains "$OUT" "- en/privacy.html: フッターに privacy.html terms.html tokushoho.html へのリンクがありません"
  assert_contains "$OUT" "- 法的な文書のページがありません: terms.html"
}

# robots.txt は sitemap.xml を絶対の URL で指し、sitemap.xml は検索に出すページをすべて・それだけ並べる
test_robots_and_sitemap_match_the_pages() {
  write_fixture_site
  fixture_page thanks.html noindex
  printf 'User-agent: *\nDisallow: /download\n' >"$SITE/robots.txt"
  sed -i '' 's|  <url><loc>https://nonet.test/terms.html</loc></url>|  <url><loc>https://nonet.test/old.html</loc></url><url><loc>https://nonet.test/thanks.html</loc></url><url><loc>https://other.test/</loc></url>|' "$SITE/sitemap.xml"
  check_fixture
  assert_status 1
  assert_contains "$OUT" "- robots.txt に「Sitemap: https://nonet.test/sitemap.xml」の行がありません"
  assert_contains "$OUT" "- sitemap.xml: ページがありません: https://nonet.test/old.html"
  assert_contains "$OUT" "- sitemap.xml: このサイト（https://nonet.test/）の外の URL です: https://other.test/"
  assert_contains "$OUT" "- sitemap.xml: 検索に出さない（noindex の）ページが入っています: https://nonet.test/thanks.html"
  assert_contains "$OUT" "- sitemap.xml に terms.html（https://nonet.test/terms.html）がありません"
  rm "$SITE/sitemap.xml"
  check_fixture
  assert_contains "$OUT" "- sitemap.xml がありません"
}

# 共有の画像は、このサイトにあり、og:image:width・height と同じ大きさ。apple-touch-icon は 180×180 の PNG
test_share_images_exist_with_the_declared_size() {
  write_fixture_site
  mkdir -p "$SITE/images"
  cp "$ROOT/site/images/og-ja.png" "$SITE/images/og.png"
  cp "$ROOT/site/apple-touch-icon.png" "$SITE/apple-touch-icon.png"
  cp "$ROOT/site/apple-touch-icon.png" "$SITE/images/small.png"
  sed -i '' 's|</head>|<meta property="og:image" content="https://nonet.test/images/og.png"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><link rel="apple-touch-icon" href="apple-touch-icon.png"></head>|' "$SITE/index.html"
  check_fixture
  assert_status 0
  sed -i '' 's|images/og.png|images/small.png|' "$SITE/index.html"
  sed -i '' 's|</head>|<meta property="og:image" content="https://nonet.test/images/missing.png"><link rel="apple-touch-icon" href="../images/og.png"></head>|' "$SITE/en/index.html"
  sed -i '' 's|</head>|<meta property="og:image" content="https://cdn.other.test/og.png"></head>|' "$SITE/privacy.html"
  check_fixture
  assert_status 1
  assert_contains "$OUT" "- index.html: og:image（site/images/small.png）の大きさが 1200×630 ではありません（いまは 180×180）"
  assert_contains "$OUT" "- en/index.html: og:image の画像がありません: site/images/missing.png"
  assert_contains "$OUT" "- en/index.html: apple-touch-icon（../images/og.png）が 180×180 の PNG ではありません（いまは 1200×630）"
  assert_contains "$OUT" "- privacy.html: og:image がこのサイト（https://nonet.test/）の画像ではありません: https://cdn.other.test/og.png"
}

# 実物で確かめて埋めるところ（data-placeholder。確認済みの macOS の版）は、--strict でも止めずに知らせる
test_release_placeholders_are_reported_but_not_strict() {
  write_fixture_site
  printf '<p>確認済みの macOS: <span class="todo" data-placeholder="tested-macos">確かめた版</span></p>\n' >>"$SITE/index.html"
  check_fixture --strict
  assert_status 0
  assert_contains "$OUT" "リリースの前に実物で確かめて埋めるところ（--strict でも止めない）: index.html tested-macos"
}

# 公開する値はすべて埋めた（価格・問い合わせ先・特商法の電話番号の表記は 2026-11-15 まで、Paddle の本番のトークンと価格の ID は
# 2026-11-15）。本物のサイトは --strict で通り、残るのは実物で確かめて埋める「確認済みの macOS」の知らせだけ
test_strict_mode_passes_on_the_real_site() {
  run "$ROOT/scripts/check-site.sh" --strict
  assert_status 0
  assert_contains "$OUT" "サイトに問題はありません"
  local page
  for page in buy.html en/buy.html; do
    assert_contains "$(cat "$ROOT/site/$page")" 'data-paddle-token="live_' "$page の Paddle のトークン（本番）"
    assert_contains "$(cat "$ROOT/site/$page")" 'data-paddle-price="pri_' "$page の Paddle の価格の ID"
  done
}

# 価格（¥1,480 税込・$9.99）は、価格の表示・head の JSON-LD の offers・特商法の表記でそろっている
test_price_is_the_same_everywhere() {
  local ja en legal
  ja="$(cat "$ROOT/site/index.html")"
  en="$(cat "$ROOT/site/en/index.html")"
  legal="$(cat "$ROOT/site/tokushoho.html")"
  assert_contains "$ja" '<span class="price-amount">¥1,480</span>' "index.html の価格"
  assert_contains "$ja" '"offers": { "@type": "Offer", "price": "1480", "priceCurrency": "JPY" }' "index.html の JSON-LD"
  assert_contains "$en" '<span class="price-amount">$9.99</span>' "en/index.html の価格"
  assert_contains "$en" '"offers": { "@type": "Offer", "price": "9.99", "priceCurrency": "USD" }' "en/index.html の JSON-LD"
  assert_contains "$legal" "1,480円（税込）" "tokushoho.html の販売価格"
  assert_contains "$(cat "$ROOT/site/buy.html")" "1,480円（税込）" "buy.html の価格"
  assert_contains "$(cat "$ROOT/site/en/buy.html")" '$9.99' "en/buy.html の価格"
}

test_pages_and_assets_exist() {
  local file
  for file in index.html en/index.html privacy.html en/privacy.html guide.html en/guide.html terms.html en/terms.html \
    tokushoho.html thanks.html en/thanks.html buy.html en/buy.html buy.js 404.html en/404.html style.css script.js favicon.svg robots.txt sitemap.xml \
    apple-touch-icon.png images/og-ja.png images/og-en.png images/demo.mp4 images/demo-poster.jpg images/demo-en.mp4 images/demo-en-poster.jpg \
    images/hud-xcode.webp images/hud-cancel.webp images/hud-zoom.webp images/hud-place.webp; do
    assert_file "$ROOT/site/$file"
  done
}

# 見出しは日英で同じ話（トラックパッドが9つのボタンになる）。ほかの会社の商標（Stream Deck）は見出しと共有のタイトルに使わず、
# 説明の文とよくある質問で比べるだけにする
test_headlines_tell_the_same_story_without_a_trademark() {
  local ja en page
  ja="$(cat "$ROOT/site/index.html")"
  en="$(cat "$ROOT/site/en/index.html")"
  assert_contains "$ja" "<h1><span class=\"nowrap\">トラックパッドが、</span><span class=\"nowrap\">9つのボタンになる。</span></h1>"
  assert_contains "$en" "<h1>Your trackpad becomes nine buttons.</h1>"
  assert_contains "$ja" "<meta property=\"og:title\" content=\"Nonet — トラックパッドが、9つのボタンになる\">"
  assert_contains "$en" "<meta property=\"og:title\" content=\"Nonet — Your trackpad becomes nine buttons\">"
  for page in index.html en/index.html; do
    if grep -E '<h1|<title>|og:title|og:image:alt' "$ROOT/site/$page" | grep -q 'Stream Deck'; then
      fail "$page: 見出し・タイトル・共有の文に Stream Deck が入っています"
    fi
  done
  # 約束は、買う・設定するものが要らないかのような言い方をしない（値段も許可も要る）
  assert_contains "$ja" "機材はいらない"
  assert_contains "$ja" "覚えなくていい"
  assert_contains "$ja" "すぐに使える"
  assert_not_contains "$ja" "買わなくていい"
  assert_not_contains "$ja" "設定しなくていい"
  assert_contains "$en" "No extra hardware"
  assert_contains "$en" "Ready from the start"
  assert_not_contains "$en" "Nothing to buy"
  assert_not_contains "$en" "Nothing to set up"
  assert_contains "$ja" "カードもメールアドレスも不要"
  assert_contains "$en" "No card or email needed"
  assert_contains "$ja" "ポインタの周りに9つのアイコンが開く"
  assert_contains "$en" "nine icons open around the pointer"
  assert_contains "$ja" "14日間"
  assert_contains "$ja" "macOS 14"
}

# 持ち主が決めた販売の条件（返金・台数・アップデート・macOS の更新）を、価格・よくある質問・利用規約・特商法の表記がそろえて書く
test_pages_state_the_sales_terms() {
  local ja en terms en_terms legal
  ja="$(cat "$ROOT/site/index.html")"
  en="$(cat "$ROOT/site/en/index.html")"
  terms="$(cat "$ROOT/site/terms.html")"
  en_terms="$(cat "$ROOT/site/en/terms.html")"
  legal="$(cat "$ROOT/site/tokushoho.html")"
  for text in "購入から30日以内なら、理由を問わず全額返金" "1つのライセンスで、あなたが使うすべての Mac に" "バージョン 1.x のアップデートはすべて無料" \
    "ベータ版のうちから確かめ" "購入からの日数にかかわらず返金" "家族や同僚が使うときは、1人に1つずつ必要" "輪の外で離せば、やめる" \
    'href="guide.html"' "Takanari Okazaki が1人で作っています" "https://astlog.dev"; do
    assert_contains "$ja" "$text" "index.html"
  done
  for text in "Full refund within 30 days, no questions asked" "One license covers every Mac you use" "All 1.x updates are free" \
    "tested from the first beta" "you get a refund no matter when you bought it" "Each person needs their own license" \
    "Lift outside the ring to cancel" 'href="guide.html"' "an independent Mac developer" "https://astlog.dev"; do
    assert_contains "$en" "$text" "en/index.html"
  done
  assert_not_contains "$en" "any keyboard layout"
  for text in "1つのライセンスは、1人の利用者のためのもの" "購入から30日以内なら、理由を問わず全額を返金" "購入からの日数にかかわらず返金" \
    "バージョン 1.x のアップデートは、すべて無料" "保証するものではありません" "軽過失" "日本の法律に従って" "id=\"refunds\""; do
    assert_contains "$terms" "$text" "terms.html"
  done
  for text in "One license is for one person" "Within 30 days of purchase, you get a full refund for any reason" \
    "no matter when you bought it" "Every 1.x update is free" "provided as is" "slight negligence" "governed by the laws of Japan" "id=\"refunds\""; do
    assert_contains "$en_terms" "$text" "en/terms.html"
  done
  # 売主（Merchant of Record）は Paddle。日本の表記のページが無いので、名前・所在地・購入者向け規約へのリンクを載せる。
  # Paddle は電話番号を公開していないので、電話番号は請求があれば開示すると書く（2026-11-15 に決めた。docs/release.md §3.4）
  for text in "販売事業者" "販売代理店（Merchant of Record）" "Paddle.com Market Limited" "30 Old Bailey, London" \
    "https://www.paddle.com/legal/buyer-terms" "terms.html#refunds" "適格請求書" "Takanari Okazaki" "購入から30日以内"; do
    assert_contains "$legal" "$text" "tokushoho.html"
  done
  assert_not_contains "$legal" "TODO: 販売サービス名"
  assert_contains "$legal" "電話番号: 請求があった場合は、遅滞なく電子メールで開示します" "tokushoho.html の電話番号"
  assert_contains "$legal" "support@astlog.dev" "tokushoho.html の問い合わせ先"
  assert_not_contains "$legal" "TODO" "tokushoho.html"
}

# 操作はトラックパッドだけ（上の縁から指を下へ滑らせて開き、アイコンで離すと実行、輪の外で離すとやめる）。
# なくなった操作（トリガーキー・すぐにタップ・角に指を置く）を販売ページとダウンロードのページに書かない
test_pages_describe_only_the_trackpad_controls() {
  local page text
  for page in index.html thanks.html terms.html; do
    text="$(cat "$ROOT/site/$page")"
    case "$page" in
      terms.html) ;;
      *) assert_contains "$text" "上の縁" "$page" ;;
    esac
    for old in "トリガー" "右⌘" "右⌥" "タップ" "角に指" "長押し" "キーを押している間" "キーを押したまま" "マスを押"; do
      assert_not_contains "$text" "$old" "$page"
    done
  done
  for page in en/index.html en/thanks.html en/terms.html; do
    text="$(cat "$ROOT/site/$page")"
    case "$page" in
      en/terms.html) ;;
      *) assert_contains "$text" "top edge" "$page" ;;
    esac
    for old in "trigger" "Trigger" "right ⌘" "Right ⌘" "right ⌥" "Right ⌥" "Hold the key" "hold a key" "Hold a key" "while you hold" "corner of the trackpad" " tap"; do
      assert_not_contains "$text" "$old" "$page"
    done
  done
  assert_contains "$(cat "$ROOT/site/index.html")" "トラックパッドの上の縁から指を下へ滑らせると"
  assert_contains "$(cat "$ROOT/site/en/index.html")" "Slide a finger down from the top edge"
  assert_contains "$(cat "$ROOT/site/thanks.html")" "アイコンの輪の外まで動かして離すと、何も実行せずに閉じます"
  assert_contains "$(cat "$ROOT/site/en/thanks.html")" "move outside the ring of icons and lift"
}

# 「ダウンロード」「無料で試す」はダウンロードのページ（thanks.html）へ。そのページが /download（Worker が最新の DMG へ飛ばす）を開く。
# JavaScript が無いときは noscript の meta refresh で始める。検索には出さない
test_download_buttons_open_the_download_page() {
  local page thanks
  for page in index.html en/index.html; do
    if grep -q 'href="https://nonet.astlog.dev/download"' "$ROOT/site/$page"; then
      fail "$page: /download を直に指すボタンがあります（thanks.html を指す）"
    fi
    [[ "$(grep -c 'href="thanks.html"' "$ROOT/site/$page")" -ge 4 ]] || fail "$page: thanks.html を指すボタンが足りません（ヘッダー・ヒーロー・価格・最後）"
  done
  for thanks in thanks.html en/thanks.html; do
    page="$(cat "$ROOT/site/$thanks")"
    assert_contains "$page" "<meta name=\"robots\" content=\"noindex\">" "$thanks"
    assert_contains "$page" "<noscript><meta http-equiv=\"refresh\" content=\"1; url=https://nonet.astlog.dev/download\"></noscript>" "$thanks"
    assert_contains "$page" "<a href=\"https://nonet.astlog.dev/download\" data-download-link>" "$thanks"
    assert_contains "$page" "data-not-mac hidden" "$thanks"
    assert_contains "$page" "id=\"install\"" "$thanks"
    assert_eq 3 "$(grep -c '<li class="install-step">' "$ROOT/site/$thanks")" "$thanks の手順の数"
  done
}

# script.js が読む data-* と要素は、どれかのページにある（読まれない印や、ページに無い印を残さない）
test_script_hooks_exist_in_the_pages() {
  local attr page
  for attr in $(grep -oE '\[data-[a-z-]+\]' "$ROOT/site/script.js" | tr -d '[]' | sort -u); do
    grep -lq -- "$attr" "$ROOT"/site/*.html "$ROOT"/site/en/*.html || fail "script.js の $attr を使うページがありません"
  done
  # 言語の案内は、もう一方の言語のページを指し、自分と違う言語の印（lang）を持つ
  for page in index.html privacy.html terms.html thanks.html en/index.html en/privacy.html en/terms.html en/thanks.html; do
    case "$page" in
      en/*) grep -q 'data-lang-bar lang="ja"' "$ROOT/site/$page" || fail "$page: 言語の案内（日本語）がありません" ;;
      *) grep -q 'data-lang-bar lang="en"' "$ROOT/site/$page" || fail "$page: 言語の案内（英語）がありません" ;;
    esac
    grep -q 'data-lang-bar-content hidden' "$ROOT/site/$page" || fail "$page: 言語の案内は、JavaScript が無いときは隠しておく"
  done
}

# 言語の案内・Mac 以外の端末の案内・ダウンロードの開始・メニューの動き（偽の DOM で script.js を動かす）。node が無ければ飛ばす
test_page_script_behaves() {
  if ! command -v node >/dev/null 2>&1; then
    printf 'node が無いので飛ばしました\n'
    return 0
  fi
  run node "$ROOT/scripts/tests/page_script_harness.js" "$ROOT/site/script.js"
  assert_status 0
}

# 販売ページは絵で見せ、文は短くする（2026-11-15 に持ち主が「情報が多い」と言って減らした）。
# 本文（動画の説明・よくある質問の答えを除く、見えている文字）と、よくある質問の数が増えすぎていないか
test_top_pages_stay_short() {
  local page count chars limit
  for page in index.html en/index.html; do
    count="$(grep -c '<details id="faq-' "$ROOT/site/$page")"
    [[ "$count" -le 6 ]] || fail "$page: よくある質問が $count 個あります（6 個まで。ほかは利用ガイドへ）"
    chars="$(python3 -I - "$ROOT/site/$page" <<'PY2'
import html, re, sys
s = open(sys.argv[1], encoding="utf-8").read()
s = s[s.index("<main"):s.index("</main>")]
s = re.sub(r'<p class="visually-hidden"[^>]*>.*?</p>|<div class="answer">.*?</div>|<svg.*?</svg>|<!--.*?-->', "", s, flags=re.S)
print(len(re.sub(r"\s+", "", html.unescape(re.sub(r"<[^>]+>", " ", s)))))
PY2
)"
    case "$page" in en/*) limit=1400 ;; *) limit=800 ;; esac
    [[ "$chars" -le "$limit" ]] || fail "$page: 本文が $chars 字あります（$limit 字まで。説明は絵と利用ガイドに任せる）"
  done
}

# ヒーローは実物の収録（デモ動画）。英語のページは、アプリを英語で動かして撮った動画（demo-en.mp4。名前の札とメニューバーの日付が英語）。
# JavaScript が無いときは controls で自分で再生でき、勝手には動かない（autoplay を付けない。
# 動かすのは script.js で、止めるボタンを出し、動きを減らす設定のときは止めたまま）。使い方と機能の絵は、同じ収録から
# 名前の札が出る前のコマを切り出した静止画（文字が無いので、日本語・英語のどちらのページにも使える）。CSP は同じオリジンの動画を許す
test_pages_show_the_real_app() {
  local page html prefix image video
  for page in index.html en/index.html; do
    html="$(cat "$ROOT/site/$page")"
    case "$page" in en/*) prefix="../" video="demo-en" ;; *) prefix="" video="demo" ;; esac
    assert_contains "$html" "<video src=\"${prefix}images/${video}.mp4\" poster=\"${prefix}images/${video}-poster.jpg\" width=\"1440\" height=\"900\" muted loop playsinline controls preload=\"metadata\"></video>" "$page の動画"
    assert_not_contains "$html" "autoplay" "$page"
    assert_contains "$html" "data-video-toggle hidden" "$page の止めるボタン（JavaScript が出す）"
    assert_contains "$html" 'aria-describedby="demo-description"' "$page の動画の説明"
    for image in hud-xcode.webp hud-cancel.webp hud-zoom.webp hud-place.webp; do
      grep -qE "<img src=\"${prefix}images/${image}\" width=\"[0-9]+\" height=\"[0-9]+\" loading=\"lazy\" alt=\"[^\"]+\">" "$ROOT/site/$page" ||
        fail "$page: images/${image} を、大きさと代替テキストを付けて載せていません"
    done
  done
  assert_contains "$(cat "$ROOT/site/index.html")" "指の動きは台本どおりに入れたもの" "index.html の動画の説明"
  assert_contains "$(cat "$ROOT/site/en/index.html")" "The finger follows a script" "en/index.html の動画の説明"
  assert_not_contains "$(cat "$ROOT/site/en/index.html")" "running in Japanese" "en/index.html の動画の説明（英語で撮った動画）"
  assert_contains "$(grep -E '^  Content-Security-Policy: ' "$ROOT/site/_headers" | head -n 1)" "media-src 'self'" "_headers の CSP"
}

test_languages_link_to_each_other() {
  local name
  for name in terms thanks; do
    grep -q "href=\"en/$name.html[^\"]*\" hreflang=\"en\"" "$ROOT/site/$name.html" || fail "$name.html から英語版へのリンクがありません"
    grep -q "href=\"../$name.html[^\"]*\" hreflang=\"ja\"" "$ROOT/site/en/$name.html" || fail "en/$name.html から日本語版へのリンクがありません"
  done
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

# アプリの「利用ガイド」（NONET_SUPPORT_URL）と「プライバシー」（NONET_PRIVACY_URL）、あれば「購入する」（NONET_PURCHASE_URL）だけを書いた xcconfig。
# URL の // は xcconfig ではコメントになるので、https:/$()/… の形で書く
write_app_links_config() {
  {
    printf 'NONET_SUPPORT_URL = %s\nNONET_PRIVACY_URL = %s\n' "$2" "$3"
    [[ -z "${4:-}" ]] || printf 'NONET_PURCHASE_URL = %s\n' "$4"
  } | sed 's|://|:/$()/|' >"$1"
}

# アプリの「購入する」がこのサイトを指すなら、そのページと、英語で動くアプリが開く en/ のページがある
test_app_purchase_link_must_point_to_a_page_of_the_site() {
  local config="$TEST_TMP/Nonet.xcconfig"
  write_fixture_site
  fixture_page buy.html noindex
  write_app_links_config "$config" https://nonet.test/guide.html https://nonet.test/privacy.html https://nonet.test/buy.html
  check_app_links_fixture
  assert_status 1
  assert_contains "$OUT" "NONET_PURCHASE_URL（https://nonet.test/buy.html）の英語のページ"
  fixture_page en/buy.html noindex
  check_app_links_fixture
  assert_status 0
  write_app_links_config "$config" https://nonet.test/guide.html https://nonet.test/privacy.html https://nonet.test/purchase.html
  check_app_links_fixture
  assert_status 1
  assert_contains "$OUT" "Nonet.xcconfig の NONET_PURCHASE_URL（https://nonet.test/purchase.html）に当たるページが site/ にありません"
  # 販売サービスのページ（ほかのホスト）を指すなら、このサイトでは確かめない
  write_app_links_config "$config" https://nonet.test/guide.html https://nonet.test/privacy.html https://store.nonet.test/buy
  check_app_links_fixture
  assert_status 0
}

# アプリの設定（xcconfig）が無ければ、アプリが開く URL を確かめられないので、公開前（--strict）は止める
test_strict_mode_fails_without_the_app_config() {
  write_fixture_site
  run "$ROOT/scripts/check-site.sh" --config "$TEST_TMP/missing.xcconfig" "$SITE"
  assert_status 0
  assert_contains "$OUT" "アプリの設定（$TEST_TMP/missing.xcconfig）が無いので"
  run "$ROOT/scripts/check-site.sh" --strict --config "$TEST_TMP/missing.xcconfig" "$SITE"
  assert_status 1
  assert_contains "$OUT" "アプリの設定（$TEST_TMP/missing.xcconfig）がありません"
}

check_app_links_fixture() {
  run "$ROOT/scripts/check-site.sh" "$@" --config "$TEST_TMP/Nonet.xcconfig" "$SITE"
}

# フォルダの URL を確かめるためのページ: help/（日本語）と en/help/（英語）
write_help_pages() {
  local name
  for name in index guide privacy; do
    fixture_page "help/$name.html"
    fixture_page "en/help/$name.html"
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
  fixture_page help.html
  write_app_links_config "$config" https://nonet.test/help.html#start https://nonet.test/privacy.html
  check_app_links_fixture
  assert_status 1
  assert_contains "$OUT" "- Nonet.xcconfig の NONET_SUPPORT_URL（https://nonet.test/help.html#start）の英語のページ（https://nonet.test/en/help.html。英語で動くアプリが開く）が site/ にありません"
  assert_not_contains "$OUT" "NONET_PRIVACY_URL"
  assert_not_contains "$OUT" "に当たるページが"

  fixture_page en/help.html
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

# canonical の無いサイトでは、アプリの URL を確かめられない。canonical が無いこと自体はいつも問題にし（公開する URL が決まらない）、
# アプリの URL のほうは、ふだんは知らせるだけで、--strict（公開の前）では失敗にする
test_app_links_without_a_canonical_fail_in_strict_mode() {
  local config="$TEST_TMP/Nonet.xcconfig"
  write_fixture_site
  sed -i '' '/rel="canonical"/d' "$SITE/index.html"
  write_app_links_config "$config" https://nonet.test/help.html https://nonet.test/privacy.html
  check_app_links_fixture
  assert_status 1
  assert_contains "$OUT" "- index.html: <link rel=\"canonical\"> がありません"
  assert_contains "$OUT" "site/index.html に canonical が無いので、NONET_SUPPORT_URL（https://nonet.test/help.html）の行き先は確かめていません"
  assert_not_contains "$OUT" "に当たるページが"
  assert_not_contains "$OUT" "- site/index.html に canonical が無いので"

  check_app_links_fixture --strict
  assert_status 1
  assert_contains "$OUT" "- site/index.html に canonical が無いので、NONET_SUPPORT_URL（https://nonet.test/help.html）がこのサイトのページを指しているか確かめられません"
  assert_contains "$OUT" "- site/index.html に canonical が無いので、NONET_PRIVACY_URL（https://nonet.test/privacy.html）がこのサイトのページを指しているか確かめられません"

  # URL がまだ空（http(s) でない）なら、アプリの URL は確かめるものが無い
  printf 'NONET_SUPPORT_URL =\nNONET_PRIVACY_URL =\n' >"$config"
  check_app_links_fixture --strict
  assert_status 1
  assert_not_contains "$OUT" "NONET_SUPPORT_URL"
  assert_not_contains "$OUT" "NONET_PRIVACY_URL"
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

# # で始まるが見出しでない行（「#1」など）も段落にする（前は1行も進まずに空の段落を足し続け、止まらなかった）。
# <!-- --> の中の「## 」は見出しに数えない
test_guide_build_treats_hash_lines_as_text() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 が無いので飛ばしました\n'
    return 0
  fi
  local repo="$TEST_TMP/repo"
  mkdir -p "$repo/docs" "$repo/site/en"
  cp "$ROOT/docs/user-guide.md" "$ROOT/docs/user-guide.en.md" "$ROOT/docs/privacy.md" "$repo/docs/"
  printf '\n#1 のコツ: 上の縁から\n\n<!--\n## 書きかけの節\n-->\n' >>"$repo/docs/user-guide.md"
  build_guide --root "$repo"
  assert_status 0
  assert_contains "$(cat "$repo/site/guide.html")" "<p>#1 のコツ: 上の縁から</p>"
  assert_not_contains "$(cat "$repo/site/guide.html")" "書きかけの節"
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
  sed -i '' 's/| Open sensitivity | Standard |/| Open sensitivity | Low |/' "$repo/docs/user-guide.en.md"
  build_guide --check --root "$repo"
  assert_status 1
  assert_contains "$OUT" "site/en/guide.html が Markdown と違います"
  assert_contains "$OUT" "<td>Low</td>"
  assert_not_contains "$OUT" "--- site/guide.html"
  build_guide --root "$repo"
  assert_status 0
  build_guide --check --root "$repo"
  assert_status 0
  assert_contains "$(cat "$repo/site/en/guide.html")" "<td>Low</td>"

  # 見出しの名前を変えると、それを指す #… のリンクが切れる
  sed -i '' 's/^### Opening the buttons$/### Opening Nonet/' "$repo/docs/user-guide.en.md"
  build_guide --check --root "$repo"
  assert_status 1
  assert_contains "$OUT" "docs/user-guide.en.md: リンク先の見出しがありません: #opening-the-buttons"

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

# 1つのプロファイルは Page.cellCount × Profile.maxPages マスまで。初回のグローバルは1ページ目が「画面に置く」、
# 2ページ目が「ユーティリティ」なので、ランチャーはその残り（maxPages − 2 ページ）まで（NonetConfiguration.initial）
test_guides_state_the_launcher_size() {
  local profile="$ROOT/Packages/NonetKit/Sources/NonetCore/Model/Profile.swift" cells pages total launcher_pages launcher file counts
  cells="$(sed -nE 's/.*static let cellCount = ([0-9]+).*/\1/p' "$profile")"
  pages="$(sed -nE 's/.*static let maxPages = ([0-9]+).*/\1/p' "$profile")"
  [[ -n "$cells" && -n "$pages" ]] || fail "Profile.swift から cellCount と maxPages を読めません"
  total=$((cells * pages))
  launcher_pages=$((pages - 2))
  launcher=$((cells * launcher_pages))
  for file in docs/user-guide.md site/guide.html; do
    grep -qF "最大${launcher}個（${launcher_pages}ページ）並べたランチャー" "$ROOT/$file" || fail "$file: ランチャーが最大${launcher}個（${launcher_pages}ページ）になっていません"
    grep -qF "最大${pages}ページ（${total}マス）" "$ROOT/$file" || fail "$file: 1つのプロファイルが最大${pages}ページ（${total}マス）になっていません"
    counts="$(grep -oE '最大[0-9]+個' "$ROOT/$file" | sort -u)"
    assert_eq "最大${launcher}個" "$counts" "$file のランチャーの数"
  done
  for file in docs/user-guide.en.md site/en/guide.html; do
    # 1ページなら one page、2ページなら two pages と書く
    grep -qF "launcher with up to ${launcher} apps on ${launcher_pages} pages" "$ROOT/$file" \
      || { [[ "$launcher_pages" == 1 ]] && grep -qF "launcher with up to ${launcher} apps on one page" "$ROOT/$file"; } \
      || { [[ "$launcher_pages" == 2 ]] && grep -qF "launcher with up to ${launcher} apps on two pages" "$ROOT/$file"; } \
      || fail "$file: the launcher is not up to ${launcher} apps on ${launcher_pages} pages"
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

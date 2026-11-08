# scripts/publish.sh のテスト。偽の wrangler（上げたものを FAKE_R2_DIR に置く）と、
# Worker の代わりに FAKE_R2_DIR から答える偽の curl で動かす。Cloudflare には何も送らない

PUBLISH_PREFIX="https://nonet.astlog.dev/updates/"

# generate_appcast と同じ形の項目。DMG とデルタの大きさは RELEASES の中のファイルから取る
#   release_item <ビルド> <バージョン> [デルタの名前…]
release_item() {
  local build="$1" version="$2" name from
  shift 2
  printf '<item>\n<title>%s</title>\n<pubDate>Tue, 27 Oct 2026 10:15:00 +0900</pubDate>\n' "$version"
  printf '<sparkle:version>%s</sparkle:version>\n<sparkle:shortVersionString>%s</sparkle:shortVersionString>\n' "$build" "$version"
  printf '<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n'
  printf '<description><![CDATA[<p>%s</p>]]></description>\n' "$version"
  printf '<enclosure url="%sNonet-%s.dmg" length="%s" type="application/octet-stream" sparkle:edSignature="c2ln"/>\n' \
    "$PUBLISH_PREFIX" "$version" "$(wc -c <"$RELEASES/Nonet-$version.dmg" | tr -d '[:space:]')"
  if [[ $# -gt 0 ]]; then
    printf '<sparkle:deltas>\n'
    for name in "$@"; do
      from="${name#Nonet*-}"
      printf '<enclosure url="%s%s" sparkle:deltaFrom="%s" length="%s" type="application/octet-stream" sparkle:edSignature="c2ln"/>\n' \
        "$PUBLISH_PREFIX" "$name" "${from%.delta}" "$(wc -c <"$RELEASES/$name" | tr -d '[:space:]')"
    done
    printf '</sparkle:deltas>\n'
  fi
  printf '</item>\n'
}

write_release_appcast() {
  local file="$1"
  shift
  {
    printf '<?xml version="1.0" standalone="yes"?>\n'
    printf '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n<channel>\n<title>Nonet</title>\n'
    printf '%s\n' "$@"
    printf '</channel>\n</rss>\n'
  } >"$file"
}

# 偽のリポジトリで publish.sh を動かせる状態にする（何度呼んでも最初の状態に戻る）。
#   公開中（FAKE_R2_DIR）: 1.1.1（ビルド 41）の DMG と、それだけを載せた appcast
#   手元（NONET_RELEASES_DIR）: 1.2.0（ビルド 42）の DMG・デルタ2つ（42-41・42-40）と、42・41 を載せた appcast
# publish.sh は appcast を Worker と同じ読み方で読むのに node を使う。node が無ければこのテストを飛ばす
prepare_publish() {
  local node
  if [[ ! -e "$TEST_TMP/node-bin/node" ]]; then
    node="$(command -v node || true)"
    if [[ -z "$node" ]]; then
      printf 'node が無いので飛ばしました\n'
      exit 0
    fi
    mkdir -p "$TEST_TMP/node-bin"
    ln -s "$node" "$TEST_TMP/node-bin/node"
  fi
  use_fakes
  make_fake_repo
  mkdir -p "$REPO/cloudflare/src" "$REPO/cloudflare/scripts" "$REPO/cloudflare/node_modules/.bin"
  cp "$ROOT/cloudflare/package.json" "$ROOT/cloudflare/wrangler.toml" "$REPO/cloudflare/"
  cp "$ROOT"/cloudflare/src/*.js "$REPO/cloudflare/src/"
  cp "$ROOT/cloudflare/scripts/appcast-info.js" "$REPO/cloudflare/scripts/"
  ln -sf "$FAKES_DIR/wrangler" "$REPO/cloudflare/node_modules/.bin/wrangler"
  export PATH="$PATH:$TEST_TMP/node-bin"
  # 販売用の値のうち、appcast の URL だけを本番の場所にする（xcconfig は最後の行が効く）
  printf 'NONET_APPCAST_URL = https:/$()/nonet.astlog.dev/updates/appcast.xml\n' >>"$REPO/Config/Nonet.xcconfig"

  RELEASES="$TEST_TMP/releases"
  R2="$TEST_TMP/r2"
  rm -rf "$RELEASES" "$R2"
  mkdir -p "$RELEASES" "$R2"
  export NONET_RELEASES_DIR="$RELEASES" FAKE_R2_DIR="$R2"
  export FAKE_DOWNLOAD_LOCATION="${PUBLISH_PREFIX}Nonet-1.2.0.dmg"
  unset FAKE_WRANGLER_FAIL FAKE_WRANGLER_DROP FAKE_CURL_STATUS FAKE_CURL_HTTP_CODE
  unset FAKE_CODESIGN_VERIFY_STATUS FAKE_STAPLER_STATUS FAKE_SPCTL_STATUS

  printf 'dmg 1.1.1\n' >"$RELEASES/Nonet-1.1.1.dmg"
  printf 'dmg 1.2.0, build 42\n' >"$RELEASES/Nonet-1.2.0.dmg"
  printf 'delta 42 from 41\n' >"$RELEASES/Nonet42-41.delta"
  printf 'delta 42 from 40, a little longer\n' >"$RELEASES/Nonet42-40.delta"
  write_release_appcast "$RELEASES/appcast.xml" \
    "$(release_item 42 1.2.0 Nonet42-41.delta Nonet42-40.delta)" "$(release_item 41 1.1.1)"

  cp "$RELEASES/Nonet-1.1.1.dmg" "$R2/"
  write_release_appcast "$R2/appcast.xml" "$(release_item 41 1.1.1)"
  : >"$FAKE_LOG"
}

publish() {
  run "$REPO/scripts/publish.sh" "$@"
}

put_call() {
  printf 'r2 object put nonet-updates/%s --file %s/%s --content-type %s --remote' "$1" "$RELEASES" "$1" "$2"
}

# 止まって、何も上げないこと
assert_refused() {
  assert_failed
  assert_not_called "r2 object put" "上げる前に止まるはず"
  assert_contains "$OUT" "$1"
}

# MARK: - 引数

test_publish_help_needs_nothing() {
  run env PATH=/usr/bin:/bin "$ROOT/scripts/publish.sh" --help
  assert_status 0
  assert_contains "$OUT" "使い方: scripts/publish.sh"
  assert_contains "$OUT" "--dry-run"
  assert_contains "$OUT" "NONET_RELEASES_DIR"
  assert_contains "$OUT" "CLOUDFLARE_API_TOKEN"
  assert_contains "$OUT" "3. appcast.xml"
  assert_contains "$OUT" "codesign --verify"
  assert_contains "$OUT" "xcrun stapler validate"
  assert_contains "$OUT" "spctl -a -t open --context context:primary-signature"
  assert_contains "$OUT" "sparkle:edSignature"
}

test_publish_argument_errors() {
  prepare_publish
  local args
  for args in "" "1.2.0 1.3.0" "v1.2" "1.2.3.4" "--force 1.2.0"; do
    # shellcheck disable=SC2086
    publish $args
    assert_status 2
    assert_contains "$OUT" "scripts/publish.sh --help"
  done
  assert_not_called "wrangler"
  assert_not_called "curl"
}

# MARK: - 上げる順番と確かめ

test_publish_uploads_dmg_then_deltas_then_appcast_and_verifies() {
  prepare_publish
  cp "$R2/appcast.xml" "$TEST_TMP/published-before.xml"
  publish 1.2.0
  assert_status 0
  assert_called_in_order \
    "curl -sS --max-time 60 -H Cache-Control: no-cache -D" \
    "$(put_call Nonet-1.2.0.dmg application/x-apple-diskimage)" \
    "$(put_call Nonet42-41.delta application/octet-stream)" \
    "$(put_call Nonet42-40.delta application/octet-stream)" \
    "$(put_call appcast.xml "application/xml; charset=utf-8")"
  # /download を見るのは上げたあとだけ
  assert_called_in_order "$(put_call appcast.xml "application/xml; charset=utf-8")" "https://nonet.astlog.dev/download"
  # どの put も --remote（無いと wrangler 4 は手元の Miniflare に書くだけ）と wrangler.toml を付ける
  assert_eq "4" "$(grep -c 'r2 object put' "$FAKE_LOG")" "put の回数"
  assert_eq "4" "$(grep 'r2 object put' "$FAKE_LOG" | grep -c -- "--remote --config $REPO/cloudflare/wrangler.toml$")" "--remote と --config"
  cmp -s "$R2/appcast.xml" "$RELEASES/appcast.xml" || fail "公開中の appcast が手元のものになっていません"
  # 上げる前の公開中の appcast を控えてある（戻すとき用）
  local backups
  backups="$(find "$RELEASES/appcast-history" -name '*-before-1.2.0.xml')"
  assert_eq 1 "$(grep -c . <<<"$backups")" "控えの数"
  cmp -s "$backups" "$TEST_TMP/published-before.xml" || fail "控えが上げる前の公開中の appcast ではありません"
  cmp -s "$R2/Nonet-1.2.0.dmg" "$RELEASES/Nonet-1.2.0.dmg" || fail "DMG が上がっていません"
  assert_contains "$OUT" "appcast: ビルド 42 があります"
  assert_contains "$OUT" "/download: 302 → ${PUBLISH_PREFIX}Nonet-1.2.0.dmg"
  assert_contains "$OUT" "公開しました: Nonet 1.2.0（ビルド 42）"
}

test_publish_skips_deltas_already_uploaded_with_the_same_content() {
  prepare_publish
  cp "$RELEASES/Nonet42-41.delta" "$R2/"
  # 前に止まった公開の残り（中身が違う）は上げ直す
  printf 'stale\n' >"$R2/Nonet42-40.delta"
  cp "$RELEASES/Nonet-1.2.0.dmg" "$R2/"
  publish 1.2.0
  assert_status 0
  assert_not_called "nonet-updates/Nonet42-41.delta"
  assert_called "$(put_call Nonet42-40.delta application/octet-stream)"
  assert_called "$(put_call Nonet-1.2.0.dmg application/x-apple-diskimage)"
  assert_contains "$OUT" "飛ばす: Nonet42-41.delta（同じ中身がもう R2 にあります）"
  cmp -s "$R2/Nonet42-40.delta" "$RELEASES/Nonet42-40.delta" || fail "中身の違うデルタを上げ直していません"
}

test_publish_twice_is_harmless() {
  prepare_publish
  publish 1.2.0
  assert_status 0
  : >"$FAKE_LOG"
  publish 1.2.0
  assert_status 0
  assert_contains "$OUT" "ビルド 42 はもう公開されています"
  assert_not_called "nonet-updates/Nonet42-41.delta"
  assert_not_called "nonet-updates/Nonet42-40.delta"
  assert_called_in_order "nonet-updates/Nonet-1.2.0.dmg" "nonet-updates/appcast.xml"
}

test_publish_first_release_when_nothing_is_published() {
  prepare_publish
  rm -f "$R2"/*
  write_release_appcast "$RELEASES/appcast.xml" "$(release_item 42 1.2.0 Nonet42-41.delta Nonet42-40.delta)"
  publish 1.2.0
  assert_status 0
  assert_contains "$OUT" "公開中の appcast はまだありません（HTTP 404）"
  assert_no_file "$RELEASES/appcast-history"
  assert_called_in_order "nonet-updates/Nonet-1.2.0.dmg" "nonet-updates/Nonet42-41.delta" "nonet-updates/appcast.xml"
}

test_publish_dry_run_prints_the_plan_and_uploads_nothing() {
  prepare_publish
  cp "$R2/appcast.xml" "$TEST_TMP/published-before.xml"
  publish --dry-run 1.2.0
  assert_status 0
  assert_not_called "wrangler"
  assert_not_called "https://nonet.astlog.dev/download"
  assert_contains "$OUT" "1. Nonet-1.2.0.dmg"
  assert_contains "$OUT" "2. Nonet42-41.delta"
  assert_contains "$OUT" "3. Nonet42-40.delta"
  assert_contains "$OUT" "4. appcast.xml"
  assert_contains "$OUT" "node_modules/.bin/wrangler r2 object put nonet-updates/Nonet-1.2.0.dmg --file $RELEASES/Nonet-1.2.0.dmg --content-type 'application/x-apple-diskimage' --remote"
  assert_contains "$OUT" "r2 object put nonet-updates/appcast.xml --file $RELEASES/appcast.xml --content-type 'application/xml; charset=utf-8' --remote"
  assert_contains "$OUT" "dry run なので、何も上げずに終わります"
  cmp -s "$R2/appcast.xml" "$TEST_TMP/published-before.xml" || fail "dry run で公開中の appcast が変わりました"
  assert_no_file "$R2/Nonet-1.2.0.dmg"
  assert_no_file "$RELEASES/appcast-history"

  # dry run でも、本番で止まるものでは止まる
  rm "$RELEASES/Nonet42-40.delta"
  publish --dry-run 1.2.0
  assert_refused "appcast.xml にあるデルタ Nonet42-40.delta が $RELEASES にありません"
}

# MARK: - 上げる前に DMG と署名を確かめる

# DMG の署名・公証のステープル・Gatekeeper を、公開中のものと比べる前（ネットワークの前）に確かめる
test_publish_verifies_the_dmg_before_uploading() {
  prepare_publish
  publish 1.2.0
  assert_status 0
  local dmg="$RELEASES/Nonet-1.2.0.dmg"
  assert_called_in_order \
    "codesign --verify --strict --verbose=2 $dmg" \
    "xcrun stapler validate $dmg" \
    "spctl -a -t open --context context:primary-signature -v $dmg" \
    "curl -sS --max-time 60 -H Cache-Control: no-cache -D" \
    "$(put_call Nonet-1.2.0.dmg application/x-apple-diskimage)"
  assert_contains "$OUT" "Nonet-1.2.0.dmg: 署名・公証のステープル・Gatekeeper の評価を確かめました"
  assert_contains "$OUT" "デルタ 2 個 / Sparkle の署名あり"
}

# それぞれが通らなければ、何も上げずに（ネットワークにも触れずに）止まる。dry run でも同じ
test_publish_refuses_a_dmg_that_fails_a_check() {
  prepare_publish
  export FAKE_CODESIGN_VERIFY_STATUS=1
  publish 1.2.0
  assert_refused "DMG の署名を確かめられません（codesign --verify）: $RELEASES/Nonet-1.2.0.dmg: code object is not signed at all"
  assert_contains "$OUT" "Nonet-1.2.0.dmg は上げません"
  assert_not_contains "$OUT" "公証のチケット"
  assert_not_contains "$OUT" "Gatekeeper が"
  assert_not_called "curl"

  prepare_publish
  export FAKE_STAPLER_STATUS=1
  publish 1.2.0
  assert_refused "DMG に公証のチケットがステープルされていません（xcrun stapler validate）"
  assert_contains "$OUT" "Could not validate ticket for $RELEASES/Nonet-1.2.0.dmg"
  assert_not_contains "$OUT" "DMG の署名を確かめられません"
  assert_not_called "curl"

  prepare_publish
  export FAKE_SPCTL_STATUS=3
  publish 1.2.0
  assert_refused "Gatekeeper が DMG を受け付けません（spctl -a -t open）: $RELEASES/Nonet-1.2.0.dmg: rejected"
  assert_not_called "curl"

  # dry run でも確かめる
  prepare_publish
  export FAKE_STAPLER_STATUS=1
  publish --dry-run 1.2.0
  assert_refused "DMG に公証のチケットがステープルされていません"

  # 全部通らなければ、全部出す
  prepare_publish
  export FAKE_CODESIGN_VERIFY_STATUS=1 FAKE_STAPLER_STATUS=1 FAKE_SPCTL_STATUS=3
  publish 1.2.0
  assert_refused "DMG の署名を確かめられません"
  assert_contains "$OUT" "DMG に公証のチケットがステープルされていません"
  assert_contains "$OUT" "Gatekeeper が DMG を受け付けません"
}

# 署名の無い更新は Sparkle が受け付けないので、項目（DMG とデルタ）に sparkle:edSignature が無ければ上げない
test_publish_refuses_an_appcast_item_without_a_sparkle_signature() {
  prepare_publish
  sed -i '' '/Nonet-1.2.0.dmg/s/ sparkle:edSignature="c2ln"//' "$RELEASES/appcast.xml"
  publish 1.2.0
  assert_refused "手元の appcast.xml の項目に Sparkle の署名がありません"
  assert_contains "$OUT" "${PUBLISH_PREFIX}Nonet-1.2.0.dmg の enclosure に sparkle:edSignature がありません"
  assert_not_contains "$OUT" "Nonet42-41.delta の enclosure"
  assert_contains "$OUT" "キーチェーンに Sparkle の秘密鍵があるか"
  assert_not_called "curl"

  # 空の署名
  prepare_publish
  sed -i '' '/Nonet-1.2.0.dmg/s/sparkle:edSignature="c2ln"/sparkle:edSignature=""/' "$RELEASES/appcast.xml"
  publish 1.2.0
  assert_refused "${PUBLISH_PREFIX}Nonet-1.2.0.dmg の enclosure に sparkle:edSignature がありません"

  # デルタの署名
  prepare_publish
  sed -i '' '/Nonet42-40.delta/s/ sparkle:edSignature="c2ln"//' "$RELEASES/appcast.xml"
  publish 1.2.0
  assert_refused "${PUBLISH_PREFIX}Nonet42-40.delta の enclosure に sparkle:edSignature がありません"
  assert_not_contains "$OUT" "Nonet42-41.delta の enclosure"
  assert_not_contains "$OUT" "Nonet-1.2.0.dmg の enclosure"

  # 前の版の項目は、この版の公開には関係しない
  prepare_publish
  sed -i '' '/Nonet-1.1.1.dmg/s/ sparkle:edSignature="c2ln"//' "$RELEASES/appcast.xml"
  publish 1.2.0
  assert_status 0
}

# 開始タグが何行にも分かれていても、署名を見つける（見つけられずに止めたり、見逃したりしない）
test_publish_finds_the_signature_in_a_multiline_enclosure() {
  prepare_publish
  sed -i '' '/Nonet-1.2.0.dmg/s/ length=/\
      length=/; /Nonet-1.2.0.dmg/s/ sparkle:edSignature=/\
      sparkle:edSignature=/' "$RELEASES/appcast.xml"
  [[ "$(grep -c '^      sparkle:edSignature=' "$RELEASES/appcast.xml")" -ge 1 ]] || fail "テストの appcast が複数行になっていません"
  publish 1.2.0
  assert_status 0

  prepare_publish
  sed -i '' '/Nonet-1.2.0.dmg/s/ length=/\
      length=/; /Nonet-1.2.0.dmg/s/ sparkle:edSignature="c2ln"//' "$RELEASES/appcast.xml"
  publish 1.2.0
  assert_refused "${PUBLISH_PREFIX}Nonet-1.2.0.dmg の enclosure に sparkle:edSignature がありません"
}

# MARK: - 途中で失敗したとき

test_publish_never_uploads_the_appcast_after_a_failed_upload() {
  prepare_publish
  export FAKE_WRANGLER_FAIL=Nonet42-40.delta
  publish 1.2.0
  assert_failed
  assert_called_in_order "nonet-updates/Nonet-1.2.0.dmg" "nonet-updates/Nonet42-41.delta" "nonet-updates/Nonet42-40.delta"
  assert_not_called "nonet-updates/appcast.xml"
  assert_contains "$OUT" "Authentication error"
  assert_contains "$OUT" "Nonet42-40.delta のアップロードに失敗しました。appcast.xml はまだ上げていないので、公開中の版は変わっていません"
  assert_not_contains "$(cat "$R2/appcast.xml")" "<sparkle:version>42</sparkle:version>" "公開中の appcast が変わりました"

  prepare_publish
  export FAKE_WRANGLER_FAIL=Nonet-1.2.0.dmg
  publish 1.2.0
  assert_failed
  assert_called "nonet-updates/Nonet-1.2.0.dmg"
  assert_not_called "nonet-updates/Nonet42-41.delta"
  assert_not_called "nonet-updates/appcast.xml"

  prepare_publish
  export FAKE_WRANGLER_FAIL=appcast.xml
  publish 1.2.0
  assert_failed
  assert_contains "$OUT" "appcast.xml のアップロードに失敗しました。DMG とデルタは上がっていますが、公開中の appcast は前のままです"
  assert_not_called "https://nonet.astlog.dev/download"
}

test_publish_reports_what_the_public_urls_do_not_show() {
  # 「上げた」と言われても公開中の appcast が変わらない（違う場所に上がったなど）
  prepare_publish
  export FAKE_WRANGLER_DROP=appcast.xml
  publish 1.2.0
  assert_failed
  assert_contains "$OUT" "上げ終わりましたが、公開された中身が合いません"
  assert_contains "$OUT" "公開中の appcast にビルド 42（${PUBLISH_PREFIX}Nonet-1.2.0.dmg）がありません"
  assert_not_contains "$OUT" "公開しました"

  prepare_publish
  export FAKE_WRANGLER_DROP=Nonet-1.2.0.dmg
  publish 1.2.0
  assert_failed
  assert_contains "$OUT" "DMG の URL が HTTP 404 です: ${PUBLISH_PREFIX}Nonet-1.2.0.dmg"

  # R2 に前の中身（大きさが違う）が残った
  prepare_publish
  export FAKE_WRANGLER_DROP=Nonet-1.2.0.dmg
  printf 'old\n' >"$R2/Nonet-1.2.0.dmg"
  publish 1.2.0
  assert_failed
  assert_contains "$OUT" "DMG の Content-Length が 4 です（期待: $(wc -c <"$RELEASES/Nonet-1.2.0.dmg" | tr -d '[:space:]')）"

  prepare_publish
  export FAKE_DOWNLOAD_LOCATION="${PUBLISH_PREFIX}Nonet-1.1.1.dmg"
  publish 1.2.0
  assert_failed
  assert_contains "$OUT" "/download の行き先が ${PUBLISH_PREFIX}Nonet-1.1.1.dmg です（期待: ${PUBLISH_PREFIX}Nonet-1.2.0.dmg）"

  prepare_publish
  unset FAKE_DOWNLOAD_LOCATION
  publish 1.2.0
  assert_failed
  assert_contains "$OUT" "/download が HTTP 404 です"
}

# MARK: - 上げる前に止まる

test_publish_refuses_missing_tools_and_files() {
  prepare_publish
  rm "$REPO/cloudflare/node_modules/.bin/wrangler"
  publish 1.2.0
  assert_refused "先に cloudflare/ で npm ci を実行してください"
  assert_not_called "curl"

  prepare_publish
  rm "$RELEASES/Nonet-1.2.0.dmg" "$RELEASES/appcast.xml"
  publish 1.2.0
  assert_refused "$RELEASES に Nonet-1.2.0.dmg がありません"
  assert_contains "$OUT" "$RELEASES に appcast.xml がありません"

  prepare_publish
  export NONET_RELEASES_DIR="$TEST_TMP/no-such-dir"
  publish 1.2.0
  assert_refused "リリースのフォルダがありません: $TEST_TMP/no-such-dir"

  # アプリが別の URL を見ていたら、ここに上げても届かない
  prepare_publish
  printf 'NONET_APPCAST_URL = https:/$()/nonet.astlog.dev/updates/nonet.xml\n' >>"$REPO/Config/Nonet.xcconfig"
  publish 1.2.0
  assert_refused "Config/Nonet.xcconfig の NONET_APPCAST_URL が「https://nonet.astlog.dev/updates/nonet.xml」です"
}

test_publish_refuses_an_appcast_that_does_not_match_the_dmg() {
  # その版の項目が無い
  prepare_publish
  printf 'dmg 1.3.0\n' >"$RELEASES/Nonet-1.3.0.dmg"
  publish 1.3.0
  assert_refused "手元の appcast.xml に 1.3.0（${PUBLISH_PREFIX}Nonet-1.3.0.dmg）の項目がありません"

  # DMG を作り直したのに appcast が前のまま（length が違う）
  prepare_publish
  printf 'rebuilt\n' >>"$RELEASES/Nonet-1.2.0.dmg"
  publish 1.2.0
  assert_refused "appcast.xml の 1.2.0 の length"

  # NONET_DOWNLOAD_URL_PREFIX で別の場所を指した
  prepare_publish
  write_release_appcast "$RELEASES/appcast.xml" "$(release_item 42 1.2.0 | sed 's#https://nonet.astlog.dev/updates/#https://cdn.example.net/nonet/#')"
  publish 1.2.0
  assert_refused "1.2.0 の項目は https://cdn.example.net/nonet/Nonet-1.2.0.dmg を指しています"

  # もっと新しい項目がある（上げても /download はこの版を指さない）
  prepare_publish
  printf 'dmg 1.3.0\n' >"$RELEASES/Nonet-1.3.0.dmg"
  write_release_appcast "$RELEASES/appcast.xml" "$(release_item 43 1.3.0)" "$(release_item 42 1.2.0 Nonet42-41.delta Nonet42-40.delta)"
  publish 1.2.0
  assert_refused "最新（既定のチャンネル）なのはビルド 43"

  # デルタが無い・大きさが違う・名前が違う
  prepare_publish
  rm "$RELEASES/Nonet42-41.delta"
  publish 1.2.0
  assert_refused "appcast.xml にあるデルタ Nonet42-41.delta が $RELEASES にありません"

  prepare_publish
  printf 'more\n' >>"$RELEASES/Nonet42-40.delta"
  publish 1.2.0
  assert_refused "appcast.xml の Nonet42-40.delta の length"

  prepare_publish
  cp "$RELEASES/Nonet42-41.delta" "$RELEASES/Other42-41.delta"
  write_release_appcast "$RELEASES/appcast.xml" "$(release_item 42 1.2.0 Other42-41.delta)"
  publish 1.2.0
  assert_refused "デルタの URL が ${PUBLISH_PREFIX}Nonet42-<ビルド>.delta の形ではありません"

  # Worker（/download）が読めない appcast
  prepare_publish
  { printf '<!DOCTYPE rss>\n'; cat "$RELEASES/appcast.xml"; } >"$TEST_TMP/doctype.xml"
  mv "$TEST_TMP/doctype.xml" "$RELEASES/appcast.xml"
  publish 1.2.0
  assert_refused "手元の appcast.xml を読めません: DOCTYPE は受け付けません"
}

test_publish_refuses_when_the_published_state_is_unexpected() {
  # 公開中の appcast のほうが新しい（別の Mac から出した）
  prepare_publish
  printf 'dmg 1.3.0\n' >"$RELEASES/Nonet-1.3.0.dmg"
  write_release_appcast "$R2/appcast.xml" "$(release_item 43 1.3.0)" "$(release_item 41 1.1.1)"
  publish 1.2.0
  assert_refused "公開中の appcast にはビルド 43 まであり、手元の appcast.xml（ビルド 42 まで）より新しいです"

  # 公開中の版の DMG を、別の中身で差し替えようとしている
  prepare_publish
  write_release_appcast "$R2/appcast.xml" "$(release_item 42 1.2.0)" "$(release_item 41 1.1.1)"
  printf 'the published 1.2.0\n' >"$R2/Nonet-1.2.0.dmg"
  publish 1.2.0
  assert_refused "ビルド 42 はもう公開されていて、R2 の Nonet-1.2.0.dmg は手元のものと中身が違います"

  # 同じ版を別のビルドでもう公開している（手元の appcast が古いまま --force-local-appcast で作り直した など）
  prepare_publish
  write_release_appcast "$R2/appcast.xml" "$(release_item 41 1.2.0)"
  publish 1.2.0
  assert_refused "版 1.2.0（Nonet-1.2.0.dmg）はビルド 41 としてもう公開されています"

  # 公開中の appcast の場所が HTML のページを返す（SPA のフォールバックなど）
  prepare_publish
  printf '<!doctype html><html><body>Nonet</body></html>\n' >"$R2/appcast.xml"
  publish 1.2.0
  assert_refused "公開中の appcast を読めません: 読めないタグがあります"
  assert_contains "$OUT" "SPA のフォールバック"

  prepare_publish
  export FAKE_CURL_HTTP_CODE=503
  publish 1.2.0
  assert_refused "公開中の appcast を確かめられません（HTTP 503）"

  prepare_publish
  export FAKE_CURL_STATUS=6
  publish 1.2.0
  assert_refused "https://nonet.astlog.dev/updates/appcast.xml に届きません（curl の終了コード 6）"
}

# MARK: - 設定のずれ

# publish.sh の置き場所が、Worker の設定（wrangler.toml・http.js）と同じこと
test_publish_targets_match_the_worker_config() {
  # shellcheck source=../publish.sh
  source "$ROOT/scripts/publish.sh"
  grep -qx "bucket_name = \"$BUCKET\"" "$ROOT/cloudflare/wrangler.toml" || fail "wrangler.toml の bucket_name が $BUCKET ではありません"
  grep -qF "pattern = \"${SITE_ORIGIN#https://}\", custom_domain = true" "$ROOT/cloudflare/wrangler.toml" ||
    fail "wrangler.toml の custom domain が ${SITE_ORIGIN#https://} ではありません"
  grep -qx "export const UPDATES_ORIGIN = \"$SITE_ORIGIN\";" "$ROOT/cloudflare/src/http.js" || fail "http.js の UPDATES_ORIGIN が $SITE_ORIGIN ではありません"
  assert_eq "$SITE_ORIGIN/updates/appcast.xml" "$APPCAST_URL"
  grep -qF "\"/download\"" "$ROOT/cloudflare/wrangler.toml" || fail "run_worker_first に /download がありません"
  grep -qF "\"/updates/*\"" "$ROOT/cloudflare/wrangler.toml" || fail "run_worker_first に /updates/* がありません"
  grep -qx 'not_found_handling = "404-page"' "$ROOT/cloudflare/wrangler.toml" || fail "無いファイルに 404 を返す設定になっていません"
}

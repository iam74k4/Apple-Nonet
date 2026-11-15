# ライセンスキーの形が、Worker（cloudflare/src/license.js。Paddle の購入で自動で届けるキー）と
# nonet-license（Swift。アプリと同じ NonetCore）でずれていないかのテスト。
# 本物の nonet-license を swift build し、使い捨ての鍵の組で、Worker の作り方で署名したキーを nonet-license verify で確かめる。
# swift か node が無ければ飛ばす（ネットワークには出ない）

LICENSE_TXN="txn_01jc0aaaaaaaaaaaaaaaaaaaaa"

# nonet-license を作り、その場所を NONET_LICENSE に入れる。作れなければ失敗
build_nonet_license() {
  local package="$ROOT/Packages/NonetKit" bin_dir
  run swift build --package-path "$package" --product nonet-license
  assert_status 0
  bin_dir="$(swift build --package-path "$package" --product nonet-license --show-bin-path)"
  NONET_LICENSE="$bin_dir/nonet-license"
  assert_file "$NONET_LICENSE"
  # 使い捨ての鍵の組（リポジトリの外。issue も xcconfig を見つけないので、アプリの鍵とは照合しない）
  KEYS="$TEST_TMP/keys"
  run "$NONET_LICENSE" keygen --out "$KEYS"
  assert_status 0
}

have_swift_and_node() {
  if ! command -v swift >/dev/null 2>&1 || ! command -v node >/dev/null 2>&1; then
    printf 'swift か node が無いので飛ばしました\n'
    return 1
  fi
}

worker_sign() {
  run_split node "$ROOT/scripts/tests/license_key_harness.mjs" "$@"
}

# Worker が作ったキーを nonet-license verify が受け付け、中身（ライセンス ID・購入者・メール・秒までの発行日時）がそのまま読める
test_worker_keys_verify_with_nonet_license() {
  have_swift_and_node || return 0
  build_nonet_license
  local key
  worker_sign sign "$KEYS/nonet-license.private-key" "$KEYS/nonet-license.public-key" \
    "$LICENSE_TXN" '山田 "太郎" / Taro' taro+nonet@example.com 2026-11-15T03:04:05.738972Z
  assert_status 0
  key="$STDOUT"
  run "$NONET_LICENSE" verify --public "$KEYS/nonet-license.public-key" "$key"
  assert_status 0
  assert_contains "$OUT" "有効なライセンスです"
  assert_contains "$OUT" "ライセンス ID: ${LICENSE_TXN}"
  assert_contains "$OUT" '購入者: 山田 "太郎" / Taro'
  assert_contains "$OUT" "メール: taro+nonet@example.com"
  assert_contains "$OUT" "エディション: standard"
  assert_contains "$OUT" "発行日時: 2026-11-15T03:04:05Z"

  # 名前が無ければ（Paddle の顧客の name は null のことがある）メールアドレスが購入者になる
  worker_sign sign "$KEYS/nonet-license.private-key" "$KEYS/nonet-license.public-key" "$LICENSE_TXN" "" buyer@example.com 2026-11-15T12:04:05+09:00
  assert_status 0
  run "$NONET_LICENSE" verify --public "$KEYS/nonet-license.public-key" "$STDOUT"
  assert_status 0
  assert_contains "$OUT" "購入者: buyer@example.com"
  assert_contains "$OUT" "発行日時: 2026-11-15T03:04:05Z"

  # 別の鍵の組では通らない（verify が何でも通すのではない）
  run "$NONET_LICENSE" keygen --out "$TEST_TMP/other"
  assert_status 0
  run "$NONET_LICENSE" verify --public "$TEST_TMP/other/nonet-license.public-key" "$key"
  assert_status 1
  assert_contains "$OUT" "無効なライセンスです"
}

# nonet-license issue が作ったキーの中身を、Worker の作り方で作り直すと、JSON の部分（キーの「.」の前）が1文字も違わない
# （キーの並び・エスケープ・日付の書き方が同じ）。署名の部分は違ってよい: CryptoKit の Ed25519 の署名は毎回乱数を混ぜるが、
# Worker（WebCrypto）の署名は RFC 8032 のとおり決まった値なので、Worker は同じ取引から何度作っても同じキーになる
test_worker_and_nonet_license_write_the_same_payload() {
  have_swift_and_node || return 0
  build_nonet_license
  local name swift_key worker_key
  for name in '山田 "太郎" / Taro <x>&' 'Ünïcødé — 名前' 'buyer@example.com'; do
    run_split "$NONET_LICENSE" issue --key "$KEYS/nonet-license.private-key" --public "$KEYS/nonet-license.public-key" \
      --name "$name" --email buyer@example.com --id "$LICENSE_TXN"
    assert_status 0
    swift_key="$STDOUT"
    worker_sign resign "$KEYS/nonet-license.private-key" "$KEYS/nonet-license.public-key" "$swift_key"
    assert_status 0
    worker_key="$STDOUT"
    assert_eq "${swift_key%%.*}" "${worker_key%%.*}" "Worker で作り直したキーの JSON（${name}）"
    run "$NONET_LICENSE" verify --public "$KEYS/nonet-license.public-key" "$worker_key"
    assert_status 0
    worker_sign resign "$KEYS/nonet-license.private-key" "$KEYS/nonet-license.public-key" "$swift_key"
    assert_eq "$worker_key" "$STDOUT" "Worker は同じ中身から同じキーを作る（${name}）"
  done
}

# 返金のときは、キーと同じライセンス ID（取引の ID）で無効にする。txn_ の ID には注意を出さない
test_revoking_a_paddle_transaction_id_needs_no_warning() {
  have_swift_and_node || return 0
  build_nonet_license
  local list="$TEST_TMP/RevokedLicenses.txt" key
  printf '# 無効にしたライセンス\n' >"$list"
  run "$NONET_LICENSE" revoke --list "$list" "$LICENSE_TXN"
  assert_status 0
  assert_not_contains "$OUT" "注意"
  assert_contains "$(cat "$list")" "$(printf '%s' "$LICENSE_TXN" | shasum -a 256 | cut -d ' ' -f 1)"
  # Worker のキーを渡しても、同じ行になる（すでにある）
  worker_sign sign "$KEYS/nonet-license.private-key" "$KEYS/nonet-license.public-key" "$LICENSE_TXN" Taro taro@example.com 2026-11-15T03:04:05Z
  key="$STDOUT"
  run "$NONET_LICENSE" revoke --list "$list" "$key"
  assert_status 0
  assert_contains "$OUT" "すでに無効にしてあります"
}

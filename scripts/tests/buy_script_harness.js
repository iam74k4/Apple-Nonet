// site/buy.js（購入のページ）を、偽の DOM と偽の Paddle.js で動かして確かめる。
// 文言・トークン・価格の ID は buy.html・en/buy.html から読むので、印の名前を変えたらここでも気づく。
// 使い方: node scripts/tests/buy_script_harness.js <buy.js>（ページは buy.js と同じフォルダの site/ から読む）
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const scriptPath = process.argv[2];
assert.ok(scriptPath, "buy.js を指定してください");
const source = fs.readFileSync(scriptPath, "utf8");
const siteDir = path.dirname(scriptPath);

const LIVE_TOKEN = `live_${"a".repeat(27)}`;
const TEST_TOKEN = `test_${"b".repeat(27)}`;
const PRICE = `pri_${"0".repeat(26)}`;
// buy.js が読む文（data-text-*）。どのページにもすべてある
const TEXT_KEYS = ["textUnavailable", "textBlocked", "textClosed", "textError", "textCompleted", "textDelivered", "textCopied", "textCopyFailed"];
// 購入が済んだあとにキーを聞く先と、登録のリンクの前半（data-license-*）
const LICENSE_KEYS = ["licenseEndpoint", "licenseLink"];
const TXN = "txn_01jc0aaaaaaaaaaaaaaaaaaaaa";
const KEY = `eyJ${"a".repeat(40)}.${"b".repeat(86)}`;

// data-foo-bar → fooBar（dataset の名前）
const datasetName = (attribute) => attribute.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());

function readPage(name) {
  const html = fs.readFileSync(path.join(siteDir, name), "utf8").replace(/<!--[\s\S]*?-->/g, "");
  const box = /<div class="thanks-head" data-checkout\b([^>]*)>/.exec(html);
  assert.ok(box, `${name}: data-checkout がありません`);
  const dataset = {};
  for (const [, attribute, value] of box[1].matchAll(/\sdata-([a-z-]+)="([^"]*)"/g)) {
    dataset[datasetName(attribute)] = value;
  }
  for (const key of ["paddleToken", "paddlePrice", ...TEXT_KEYS, ...LICENSE_KEYS]) {
    assert.ok(dataset[key], `${name}: data-checkout に ${key} がありません`);
  }
  const status = /<p data-checkout-status role="status">([^<]+)<\/p>/.exec(html);
  assert.ok(status, `${name}: data-checkout-status がありません`);
  assert.ok(/<button class="btn" type="button" data-checkout-open hidden>/.test(html), `${name}: 「購入画面を開く」は最初は隠す`);
  // Paddle.js を先に読み、buy.js を後に読む（どちらも defer なので、書いた順に動く）
  const paddle = html.indexOf('<script src="https://cdn.paddle.com/paddle/v2/paddle.js" defer></script>');
  const buy = html.search(/<script src="(\.\.\/)?buy\.js" defer><\/script>/);
  assert.ok(paddle >= 0 && buy > paddle, `${name}: Paddle.js を buy.js より先に読む`);
  // キーを出す場所は最初は隠し、キー・ライセンス ID・登録のリンク・コピーのボタン・コピーの結果を持つ
  const delivery = /<div class="license-delivery" data-license hidden>([\s\S]*?)<\/div>/.exec(html);
  assert.ok(delivery, `${name}: data-license（最初は hidden）がありません`);
  for (const pattern of [
    /<code class="license-key" data-license-key><\/code>/,
    /<span data-license-id><\/span>/,
    /<a class="btn" data-license-open>[^<]+<\/a>/,
    /<button class="btn btn-secondary" type="button" data-license-copy>[^<]+<\/button>/,
    /<p class="fine" data-license-copy-status role="status"><\/p>/,
  ]) {
    assert.ok(pattern.test(delivery[1]), `${name}: data-license の中に ${pattern} がありません`);
  }
  assert.ok(!/<a [^>]*data-license-open[^>]*href=/.test(delivery[1]), `${name}: 登録のリンクの href は buy.js が付ける`);
  return { name, dataset, status: status[1] };
}

class FakeElement {
  constructor({ hidden = false, text = "" } = {}) {
    this.hidden = hidden;
    this.textContent = text;
    this.listeners = {};
  }

  addEventListener(type, listener) {
    (this.listeners[type] ||= []).push(listener);
  }

  click() {
    for (const listener of this.listeners.click || []) listener({ type: "click" });
  }
}

// Paddle.js の代わり。呼ばれた順を calls に残す
function makePaddle({ throwsOnInitialize = false } = {}) {
  const paddle = {
    calls: [],
    callback: null,
    Environment: { set: (environment) => paddle.calls.push(["Environment.set", environment]) },
    Initialize: (options) => {
      paddle.calls.push(["Initialize", options]);
      if (throwsOnInitialize) throw new Error("Paddle.Initialize() の失敗");
      paddle.callback = options.eventCallback;
    },
    Checkout: { open: (options) => paddle.calls.push(["Checkout.open", options]) },
    emit: (name, data) => paddle.callback(data === undefined ? { name } : { name, data }),
  };
  return paddle;
}

// 同じサイトの /api/license の代わり。answers は聞かれた順に返す答え（{ status, body } か Error）。尽きたら最後の答えを返し続ける
function makeServer(answers = [{ status: 200, body: { license_key: KEY, license_id: TXN } }]) {
  const server = { requests: [] };
  server.fetch = (url, options) => {
    server.requests.push({ url, options });
    const answer = answers[Math.min(server.requests.length - 1, answers.length - 1)];
    if (answer instanceof Error) return Promise.reject(answer);
    return Promise.resolve({
      ok: answer.status >= 200 && answer.status < 300,
      status: answer.status,
      json: () => (answer.body === undefined ? Promise.reject(new SyntaxError("JSON ではありません")) : Promise.resolve(answer.body)),
    });
  };
  return server;
}

// window.setTimeout の代わり。runTimers() で、待っているものを順に動かす
function makeTimers() {
  const timers = { queue: [], delays: [] };
  timers.setTimeout = (callback, delay) => {
    timers.queue.push(callback);
    timers.delays.push(delay);
  };
  return timers;
}

function makeClipboard({ fails = false } = {}) {
  const clipboard = { written: [] };
  clipboard.writeText = (text) => {
    clipboard.written.push(text);
    return fails ? Promise.reject(new Error("許可がありません")) : Promise.resolve();
  };
  return clipboard;
}

function load(
  page,
  {
    token = page.dataset.paddleToken,
    price = page.dataset.paddlePrice,
    search = "",
    paddle = makePaddle(),
    server = makeServer(),
    timers = makeTimers(),
    clipboard = makeClipboard(),
    dataset = {},
  } = {},
) {
  const box = new FakeElement();
  box.dataset = { ...page.dataset, paddleToken: token, paddlePrice: price, ...dataset };
  const status = new FakeElement({ text: page.status });
  const button = new FakeElement({ hidden: true });
  const delivery = new FakeElement({ hidden: true });
  const license = {
    "[data-license-key]": new FakeElement(),
    "[data-license-id]": new FakeElement(),
    "[data-license-open]": new FakeElement(),
    "[data-license-copy]": new FakeElement(),
    "[data-license-copy-status]": new FakeElement(),
  };
  delivery.querySelector = (selector) => license[selector] || null;
  box.querySelector = (selector) => ({ "[data-checkout-status]": status, "[data-checkout-open]": button, "[data-license]": delivery })[selector] || null;
  const document = { querySelector: (selector) => (selector === "[data-checkout]" ? box : null) };
  const window = { location: { search }, setTimeout: timers.setTimeout, navigator: clipboard ? { clipboard } : {} };
  if (paddle) window.Paddle = paddle;
  if (server) window.fetch = server.fetch;
  const context = { window, document, URLSearchParams };
  vm.createContext(context);
  vm.runInContext(source, context, { filename: scriptPath });
  return { page, paddle, status, button, delivery, license, server, timers, clipboard };
}

// 約束（Promise）の続きを動かしきる
const settle = () => new Promise((resolve) => setImmediate(resolve));
async function flush() {
  for (let index = 0; index < 5; index += 1) await settle();
}

async function runTimers(timers) {
  while (timers.queue.length > 0) {
    timers.queue.shift()();
    await flush();
  }
}

const pages = ["buy.html", "en/buy.html"].map(readPage);

// MARK: - テスト

// 2つのページは同じトークンと価格の ID を使う（片方だけ直し忘れない）
function testPagesShareTheStoreSettings() {
  const [ja, en] = pages;
  assert.equal(en.dataset.paddleToken, ja.dataset.paddleToken, "buy.html と en/buy.html のトークンが違います");
  assert.equal(en.dataset.paddlePrice, ja.dataset.paddlePrice, "buy.html と en/buy.html の価格の ID が違います");
}

// 仮の値のまま（TODO）なら、Paddle.js を呼ばずに「準備中」と出す。形の違う値も同じ
function testPlaceholdersDoNotOpenTheCheckout() {
  for (const page of pages) {
    // ページの値は、まだ仮の値（TODO）のときだけ確かめる（本物の値を入れたら開いてよい。形は check-site.sh --strict が確かめる）
    const pageValues = page.dataset.paddleToken.includes("TODO") || page.dataset.paddlePrice.includes("TODO")
      ? [[page.dataset.paddleToken, page.dataset.paddlePrice]]
      : [];
    for (const [token, price] of [
      ...pageValues,
      [LIVE_TOKEN, "pri_short"],
      ["sk_live_secret", PRICE],
      [`live_${"a".repeat(26)}!`, PRICE],
    ]) {
      const { paddle, status, button } = load(page, { token, price });
      assert.deepEqual(paddle.calls, [], `${page.name}: 仮の値で Paddle.js を呼びました（${token} / ${price}）`);
      assert.equal(status.textContent, page.dataset.textUnavailable, page.name);
      assert.equal(button.hidden, true, `${page.name}: 開けないのにボタンを出しました`);
    }
  }
}

// 本番のトークン（live_）: sandbox にせず、ブラウザの言語のオーバーレイで、価格の ID を1つ開く
function testLiveTokenOpensTheCheckout() {
  for (const page of pages) {
    const { paddle, button } = load(page, { token: LIVE_TOKEN, price: PRICE });
    assert.deepEqual(paddle.calls.map(([name]) => name), ["Initialize", "Checkout.open"], page.name);
    const options = paddle.calls[0][1];
    assert.equal(options.token, LIVE_TOKEN);
    assert.deepEqual(JSON.parse(JSON.stringify(options.checkout)), { settings: { displayMode: "overlay" } });
    assert.deepEqual(JSON.parse(JSON.stringify(paddle.calls[1][1])), { items: [{ priceId: PRICE, quantity: 1 }] });
    assert.equal(button.hidden, false, `${page.name}: 開き直すボタンを出していません`);
    button.click();
    assert.equal(paddle.calls.length, 3, `${page.name}: ボタンで開き直せません`);
  }
}

// sandbox のトークン（test_）: Initialize の前に sandbox にする
function testTestTokenUsesTheSandbox() {
  const { paddle } = load(pages[0], { token: TEST_TOKEN, price: PRICE });
  assert.deepEqual(paddle.calls.map(([name, value]) => (name === "Environment.set" ? `${name}:${value}` : name)), [
    "Environment.set:sandbox",
    "Initialize",
    "Checkout.open",
  ]);
}

// Paddle の Default payment link（?_ptxn=…）で開かれたら、その取引は Paddle.js が開く。ボタンでは同じ取引を開き直す
function testTransactionLinkIsLeftToPaddle() {
  const { paddle, button } = load(pages[0], { token: LIVE_TOKEN, price: PRICE, search: "?_ptxn=txn_01abc" });
  assert.deepEqual(paddle.calls.map(([name]) => name), ["Initialize"], "?_ptxn のときに価格の購入画面を開きました");
  button.click();
  assert.deepEqual(JSON.parse(JSON.stringify(paddle.calls[1])), ["Checkout.open", { transactionId: "txn_01abc" }]);
}

// 拡張機能などで Paddle.js が無い・Initialize が失敗したら、そう知らせて開かない
function testBlockedPaddleIsReported() {
  for (const page of pages) {
    const missing = load(page, { token: LIVE_TOKEN, price: PRICE, paddle: null });
    assert.equal(missing.status.textContent, page.dataset.textBlocked, page.name);
    assert.equal(missing.button.hidden, true);
    const failing = load(page, { token: LIVE_TOKEN, price: PRICE, paddle: makePaddle({ throwsOnInitialize: true }) });
    assert.equal(failing.status.textContent, page.dataset.textBlocked, page.name);
    assert.deepEqual(failing.paddle.calls.map(([name]) => name), ["Initialize"], `${page.name}: 失敗したのに開きました`);
    assert.equal(failing.button.hidden, true);
  }
}

// 閉じた・開けなかった・買えた、を知らせる。買えたあとに閉じても、お礼のまま
function testCheckoutEventsUpdateTheStatus() {
  for (const page of pages) {
    const { paddle, status, button } = load(page, { token: LIVE_TOKEN, price: PRICE });
    paddle.emit("checkout.loaded");
    assert.equal(status.textContent, page.status, `${page.name}: 開いただけで文を変えました`);
    paddle.emit("checkout.closed");
    assert.equal(status.textContent, page.dataset.textClosed, page.name);
    paddle.emit("checkout.payment.error");
    assert.equal(status.textContent, page.dataset.textClosed, `${page.name}: カードが通らないのは購入画面の中で直せる`);
    paddle.emit("checkout.error");
    assert.equal(status.textContent, page.dataset.textError, page.name);
    paddle.emit("checkout.completed");
    assert.equal(status.textContent, page.dataset.textCompleted, page.name);
    assert.equal(button.hidden, true, `${page.name}: 買えたあとも開くボタンを出しています`);
    paddle.emit("checkout.closed");
    paddle.emit("checkout.error");
    assert.equal(status.textContent, page.dataset.textCompleted, `${page.name}: 買えたあとのお礼を上書きしました`);
  }
}

// data-checkout の無いページでは何もしない
function testPagesWithoutTheHookAreUntouched() {
  const context = { window: { location: { search: "" }, Paddle: makePaddle() }, document: { querySelector: () => null }, URLSearchParams };
  vm.createContext(context);
  vm.runInContext(source, context, { filename: scriptPath });
  assert.deepEqual(context.window.Paddle.calls, []);
}

// 購入が済んだら、取引の ID で /api/license に聞き、キー・ライセンス ID・登録のリンク・コピーのボタンを出す
async function testCompletedPurchaseShowsTheKey() {
  for (const page of pages) {
    const { paddle, status, delivery, license, server, clipboard } = load(page, { token: LIVE_TOKEN, price: PRICE });
    paddle.emit("checkout.completed", { transaction_id: TXN, status: "completed" });
    assert.equal(status.textContent, page.dataset.textCompleted, `${page.name}: 聞いている間はメールで届くという案内`);
    await flush();
    assert.equal(server.requests.length, 1, page.name);
    assert.equal(server.requests[0].url, `${page.dataset.licenseEndpoint}?transaction_id=${TXN}`);
    assert.equal(server.requests[0].options.credentials, "same-origin");
    assert.equal(server.requests[0].options.cache, "no-store");
    assert.equal(delivery.hidden, false, `${page.name}: キーを出していません`);
    assert.equal(status.textContent, page.dataset.textDelivered, page.name);
    assert.equal(license["[data-license-key]"].textContent, KEY);
    assert.equal(license["[data-license-id]"].textContent, TXN);
    assert.equal(license["[data-license-open]"].href, `nonet://register?key=${KEY}`);
    assert.equal(page.dataset.licenseLink, "nonet://register?key=", page.name);
    license["[data-license-copy]"].click();
    await flush();
    assert.deepEqual(clipboard.written, [KEY]);
    assert.equal(license["[data-license-copy-status]"].textContent, page.dataset.textCopied, page.name);
    // もう一度 completed が来ても、聞き直さない
    paddle.emit("checkout.completed", { transaction_id: TXN });
    await flush();
    assert.equal(server.requests.length, 1, `${page.name}: 2回目の completed で聞き直しました`);
  }
}

// まだ済んでいない（409）・一時的な失敗（502・通信の失敗）は少し待って聞き直し、5回で諦める
async function testPendingTransactionIsAskedAgain() {
  const page = pages[0];
  const later = load(page, {
    token: LIVE_TOKEN,
    price: PRICE,
    server: makeServer([
      { status: 409, body: { error: "not_completed" } },
      { status: 502, body: {} },
      new TypeError("Failed to fetch"),
      { status: 200, body: { license_key: KEY, license_id: TXN } },
    ]),
  });
  later.paddle.emit("checkout.completed", { transaction_id: TXN });
  await flush();
  assert.equal(later.delivery.hidden, true);
  await runTimers(later.timers);
  assert.equal(later.server.requests.length, 4);
  assert.deepEqual(later.timers.delays, [1000, 2000, 3000]);
  assert.equal(later.delivery.hidden, false, "聞き直して返ってきたキーを出していません");

  const never = load(page, { token: LIVE_TOKEN, price: PRICE, server: makeServer([{ status: 409, body: { error: "not_completed" } }]) });
  never.paddle.emit("checkout.completed", { transaction_id: TXN });
  await flush();
  await runTimers(never.timers);
  assert.equal(never.server.requests.length, 6, "最初の1回と、聞き直す5回");
  assert.deepEqual(never.timers.delays, [1000, 2000, 3000, 5000, 8000]);
  assert.equal(never.delivery.hidden, true);
  assert.equal(never.status.textContent, page.dataset.textCompleted, "諦めたらメールで届くという案内のまま");
}

// 設定していない（503）・無い取引（404）・おかしな答えは聞き直さず、メールで届くという案内のまま
async function testFailuresKeepTheEmailMessage() {
  for (const page of pages) {
    for (const answer of [
      { status: 503, body: { error: "unavailable" } },
      { status: 404, body: { error: "not_found" } },
      { status: 400, body: { error: "invalid_transaction_id" } },
      { status: 200, body: { license_key: KEY, license_id: "txn_01jc0bbbbbbbbbbbbbbbbbbbbb" } },
      { status: 200, body: { license_key: "not-a-key", license_id: TXN } },
      { status: 200, body: { license_key: `${KEY}<img>`, license_id: TXN } },
      { status: 200, body: undefined },
    ]) {
      const { paddle, status, delivery, server, timers } = load(page, { token: LIVE_TOKEN, price: PRICE, server: makeServer([answer]) });
      paddle.emit("checkout.completed", { transaction_id: TXN });
      await flush();
      await runTimers(timers);
      assert.equal(server.requests.length, answer.body === undefined ? 6 : 1, `${page.name}: ${JSON.stringify(answer)} の聞き直しの回数`);
      assert.equal(delivery.hidden, true, `${page.name}: ${JSON.stringify(answer)} でキーを出しました`);
      assert.equal(status.textContent, page.dataset.textCompleted, page.name);
    }
  }
}

// 取引の ID が無い・形が違う・聞く先が同じサイトのパスでない・fetch が無いときは聞かない
async function testLicenseIsRequestedOnlyWhenSafe() {
  const page = pages[0];
  for (const [data, dataset, server] of [
    [undefined, {}, makeServer()],
    [{}, {}, makeServer()],
    [{ transaction_id: "txn_01abc" }, {}, makeServer()],
    [{ transaction_id: `${TXN}&x=1` }, {}, makeServer()],
    [{ transaction_id: TXN }, { licenseEndpoint: "//other.test/api/license" }, makeServer()],
    [{ transaction_id: TXN }, { licenseEndpoint: "api/license" }, makeServer()],
    [{ transaction_id: TXN }, { licenseEndpoint: "" }, makeServer()],
    [{ transaction_id: TXN }, {}, null],
  ]) {
    const loaded = load(page, { token: LIVE_TOKEN, price: PRICE, dataset, server });
    loaded.paddle.emit("checkout.completed", data);
    await flush();
    assert.equal(loaded.status.textContent, page.dataset.textCompleted);
    assert.equal(loaded.delivery.hidden, true);
    if (server) assert.equal(server.requests.length, 0, `${JSON.stringify(data)} ${JSON.stringify(dataset)} で聞きました`);
  }
}

// クリップボードに書けないときは、選んでコピーするよう知らせる
async function testCopyFailureIsReported() {
  const page = pages[1];
  for (const clipboard of [null, makeClipboard({ fails: true })]) {
    const { paddle, license } = load(page, { token: LIVE_TOKEN, price: PRICE, clipboard });
    paddle.emit("checkout.completed", { transaction_id: TXN });
    await flush();
    license["[data-license-copy]"].click();
    await flush();
    assert.equal(license["[data-license-copy-status]"].textContent, page.dataset.textCopyFailed);
  }
}

const tests = [
  testPagesShareTheStoreSettings,
  testPlaceholdersDoNotOpenTheCheckout,
  testLiveTokenOpensTheCheckout,
  testTestTokenUsesTheSandbox,
  testTransactionLinkIsLeftToPaddle,
  testBlockedPaddleIsReported,
  testCheckoutEventsUpdateTheStatus,
  testPagesWithoutTheHookAreUntouched,
  testCompletedPurchaseShowsTheKey,
  testPendingTransactionIsAskedAgain,
  testFailuresKeepTheEmailMessage,
  testLicenseIsRequestedOnlyWhenSafe,
  testCopyFailureIsReported,
];
(async () => {
  let failed = 0;
  for (const test of tests) {
    try {
      await test();
    } catch (error) {
      failed += 1;
      console.error(`FAIL ${test.name}: ${error.message}`);
    }
  }
  if (failed > 0) process.exit(1);
  console.log(`buy.js: ${tests.length} 件すべて通りました`);
})();

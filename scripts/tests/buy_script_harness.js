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
const TEXT_KEYS = ["textUnavailable", "textBlocked", "textClosed", "textError", "textCompleted"];

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
  for (const key of ["paddleToken", "paddlePrice", ...TEXT_KEYS]) {
    assert.ok(dataset[key], `${name}: data-checkout に ${key} がありません`);
  }
  const status = /<p data-checkout-status role="status">([^<]+)<\/p>/.exec(html);
  assert.ok(status, `${name}: data-checkout-status がありません`);
  assert.ok(/<button class="btn" type="button" data-checkout-open hidden>/.test(html), `${name}: 「購入画面を開く」は最初は隠す`);
  // Paddle.js を先に読み、buy.js を後に読む（どちらも defer なので、書いた順に動く）
  const paddle = html.indexOf('<script src="https://cdn.paddle.com/paddle/v2/paddle.js" defer></script>');
  const buy = html.search(/<script src="(\.\.\/)?buy\.js" defer><\/script>/);
  assert.ok(paddle >= 0 && buy > paddle, `${name}: Paddle.js を buy.js より先に読む`);
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
    emit: (name) => paddle.callback({ name }),
  };
  return paddle;
}

function load(page, { token = page.dataset.paddleToken, price = page.dataset.paddlePrice, search = "", paddle = makePaddle() } = {}) {
  const box = new FakeElement();
  box.dataset = { ...page.dataset, paddleToken: token, paddlePrice: price };
  const status = new FakeElement({ text: page.status });
  const button = new FakeElement({ hidden: true });
  box.querySelector = (selector) => ({ "[data-checkout-status]": status, "[data-checkout-open]": button })[selector] || null;
  const document = { querySelector: (selector) => (selector === "[data-checkout]" ? box : null) };
  const window = { location: { search } };
  if (paddle) window.Paddle = paddle;
  const context = { window, document, URLSearchParams };
  vm.createContext(context);
  vm.runInContext(source, context, { filename: scriptPath });
  return { page, paddle, status, button };
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

const tests = [
  testPagesShareTheStoreSettings,
  testPlaceholdersDoNotOpenTheCheckout,
  testLiveTokenOpensTheCheckout,
  testTestTokenUsesTheSandbox,
  testTransactionLinkIsLeftToPaddle,
  testBlockedPaddleIsReported,
  testCheckoutEventsUpdateTheStatus,
  testPagesWithoutTheHookAreUntouched,
];
let failed = 0;
for (const test of tests) {
  try {
    test();
  } catch (error) {
    failed += 1;
    console.error(`FAIL ${test.name}: ${error.message}`);
  }
}
if (failed > 0) process.exit(1);
console.log(`buy.js: ${tests.length} 件すべて通りました`);

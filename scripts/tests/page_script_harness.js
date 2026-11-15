// site/script.js のうち HUD のデモ以外（言語の案内・Mac 以外の端末の案内・ダウンロードの開始・共有のボタン・メニュー）を、
// 偽の DOM と時計で動かして確かめる。文言・リンク・data-* はページの HTML から読むので、印の名前を変えたらここでも気づく。
// HUD のデモは demo_harness.js。
// 使い方: node scripts/tests/page_script_harness.js <script.js>（ページは script.js と同じフォルダの site/ から読む）
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const scriptPath = process.argv[2];
assert.ok(scriptPath, "script.js を指定してください");
const source = fs.readFileSync(scriptPath, "utf8");
const siteDir = path.dirname(scriptPath);

const AGENTS = {
  mac: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
  iphone: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
  android: "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36",
  windows: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
};

// MARK: - ページから読むもの

function readPage(name) {
  const html = fs.readFileSync(path.join(siteDir, name), "utf8").replace(/<!--[\s\S]*?-->/g, "");
  const match = (pattern, what) => {
    const found = pattern.exec(html);
    assert.ok(found, `${name}: ${what} がありません`);
    return found;
  };
  const page = { name, lang: match(/<html lang="([a-z]+)">/, "<html lang>")[1] };
  const bar = /<div class="lang-bar" data-lang-bar lang="([a-z]+)" aria-live="polite">/.exec(html);
  if (bar) {
    assert.ok(/data-lang-bar-content hidden/.test(html), `${name}: 言語の案内は最初は隠す`);
    assert.ok(/data-lang-bar-close/.test(html), `${name}: 言語の案内を閉じるボタンがありません`);
    page.bar = { lang: bar[1] };
  }
  page.notMac = (html.match(/data-not-mac hidden/g) || []).length;
  const share = /data-share data-share-url="([^"]+)" data-label-share="([^"]+)" data-label-copied="([^"]+)">([^<]+)</.exec(html);
  if (share) {
    page.share = { url: share[1], labelShare: share[2], labelCopied: share[3], text: share[4] };
    assert.ok(/data-share-status/.test(html), `${name}: 共有の結果を出すところ（data-share-status）がありません`);
  }
  if (/data-download /.test(html)) {
    page.download = {
      delay: Number(match(/data-download data-download-delay="(\d+)"/, "data-download-delay")[1]),
      href: match(/<a href="([^"]+)" data-download-link>/, "data-download-link")[1],
      heading: match(/<h1 data-download-heading data-text-not-mac="([^"]+)">([^<]+)<\/h1>/, "data-download-heading"),
    };
  }
  page.menu = /<details class="menu" data-menu>/.test(html);
  return page;
}

// MARK: - 偽の DOM

class FakeElement {
  constructor({ hidden = false, lang = "", dataset = {}, text = "", href = "" } = {}) {
    this.hidden = hidden;
    this.lang = lang;
    this.dataset = dataset;
    this.textContent = text;
    this.href = href;
    this.open = false;
    this.focused = false;
    this.parentNode = null;
    this.children = [];
    this.listeners = {};
    this.selectors = {};
  }
  add(selector, child) {
    const list = this.selectors[selector] || [];
    list.push(child);
    this.selectors[selector] = list;
    if (!this.children.includes(child)) this.children.push(child);
    child.parentNode = this;
    return child;
  }
  // 子にはせず、querySelector で見つかるようにだけする（document から、深い子孫を探すとき）
  register(selector, element) {
    this.selectors[selector] = (this.selectors[selector] || []).concat(element);
    return element;
  }
  querySelector(selector) {
    return (this.selectors[selector] || [])[0] || null;
  }
  querySelectorAll(selector) {
    return this.selectors[selector] || [];
  }
  contains(other) {
    return other === this || this.children.some((child) => child.contains(other));
  }
  addEventListener(type, listener) {
    (this.listeners[type] = this.listeners[type] || []).push(listener);
  }
  dispatch(type, event = {}) {
    (this.listeners[type] || []).forEach((listener) => listener(event));
  }
  focus() {
    this.focused = true;
  }
}

function makeClock() {
  let now = 0;
  let nextID = 1;
  const timers = new Map();
  return {
    setTimeout(fn, ms) {
      const id = nextID++;
      timers.set(id, { at: now + (ms || 0), fn });
      return id;
    },
    clearTimeout(id) {
      timers.delete(id);
    },
    advance(ms) {
      const until = now + ms;
      for (;;) {
        const due = [...timers].filter(([, t]) => t.at <= until).sort((a, b) => a[1].at - b[1].at)[0];
        if (!due) break;
        timers.delete(due[0]);
        now = due[1].at;
        due[1].fn();
      }
      now = until;
    },
  };
}

function makeStorage(mode, initial = {}) {
  const values = new Map(Object.entries(initial));
  if (mode === "throws") {
    const fail = () => {
      throw new Error("SecurityError");
    };
    return { getItem: fail, setItem: fail, values };
  }
  return {
    getItem: (key) => (values.has(key) ? values.get(key) : null),
    setItem: (key, value) => values.set(key, String(value)),
    values,
  };
}

// ページの印だけを持つ偽の document を作り、script.js を動かす
function load(page, { agent = "mac", languages = ["en-US"], hint, maxTouchPoints = 0, storage, hash = "", share, clipboard } = {}) {
  const clock = makeClock();
  const document = new FakeElement();
  document.documentElement = new FakeElement({ lang: page.lang });
  document.hidden = false;
  const header = document.add(".site-header .brand", new FakeElement());

  const parts = { header };
  if (page.bar) {
    const bar = document.add("[data-lang-bar]", new FakeElement({ lang: page.bar.lang }));
    parts.barContent = bar.add("[data-lang-bar-content]", new FakeElement({ hidden: true }));
    parts.barClose = bar.add("[data-lang-bar-close]", new FakeElement());
  }
  parts.notes = [];
  for (let i = 0; i < page.notMac; i++) {
    const note = document.add("[data-not-mac]", new FakeElement({ hidden: true }));
    parts.notes.push(note);
    if (page.share && i === 0) {
      const { url, labelShare, labelCopied, text } = page.share;
      parts.shareButton = note.add("[data-share-button]", new FakeElement({ dataset: { shareUrl: url, labelShare, labelCopied }, text }));
      parts.shareStatus = note.add("[data-share-status]", new FakeElement());
      document.register("[data-share]", parts.shareButton);
    }
  }
  if (page.download) {
    const box = document.add("[data-download]", new FakeElement({ dataset: { downloadDelay: String(page.download.delay) } }));
    parts.downloadLink = box.add("[data-download-link]", new FakeElement({ href: page.download.href }));
    parts.heading = box.add(
      "[data-download-heading]",
      new FakeElement({ dataset: { textNotMac: page.download.heading[1] }, text: page.download.heading[2] }),
    );
    parts.status = box.add("[data-download-status]", new FakeElement());
  }
  if (page.menu) {
    const menu = document.add("[data-menu]", new FakeElement());
    parts.menu = menu;
    parts.menuSummary = menu.add("summary", new FakeElement());
    parts.menuLinks = [menu.add("a", new FakeElement()), menu.add("a", new FakeElement())];
  }

  const assigned = [];
  const navigator = { userAgent: AGENTS[agent] || agent, languages, language: languages[0], maxTouchPoints };
  if (hint !== undefined) navigator.userAgentData = { platform: hint };
  const shared = [];
  if (share) navigator.share = (data) => (shared.push(data), Promise.resolve());
  const copied = [];
  if (clipboard) navigator.clipboard = { writeText: (text) => (copied.push(text), Promise.resolve()) };

  const context = {
    document,
    navigator,
    localStorage: storage || makeStorage(),
    location: { hash, assign: (url) => assigned.push(url) },
    setTimeout: clock.setTimeout,
    clearTimeout: clock.clearTimeout,
    matchMedia: () => ({ matches: false, addEventListener() {} }),
    Promise,
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(source, context, { filename: scriptPath });
  return { clock, document, parts, assigned, shared, copied };
}

const flush = () => new Promise((resolve) => setImmediate(resolve));

// MARK: - テスト

const pages = ["index.html", "en/index.html", "privacy.html", "en/privacy.html", "terms.html", "en/terms.html", "thanks.html", "en/thanks.html"].map(readPage);
const byName = (name) => pages.find((page) => page.name === name);

function testLanguageBarOnJapanesePages() {
  for (const page of pages.filter((p) => p.lang === "ja")) {
    assert.ok(page.bar, `${page.name}: 言語の案内がありません`);
    assert.strictEqual(page.bar.lang, "en", `${page.name}: 日本語のページは英語を案内する`);
    assert.strictEqual(load(page, { languages: ["en-US", "en"] }).parts.barContent.hidden, false, `${page.name}: 英語のブラウザに出す`);
    assert.strictEqual(load(page, { languages: ["fr-FR"] }).parts.barContent.hidden, false, `${page.name}: 日本語を読まないブラウザに出す`);
    assert.strictEqual(load(page, { languages: ["ja-JP", "en-US"] }).parts.barContent.hidden, true, `${page.name}: 日本語のブラウザには出さない`);
    assert.strictEqual(load(page, { languages: ["en-US", "ja"] }).parts.barContent.hidden, true, `${page.name}: 日本語も読むなら出さない`);
  }
}

function testLanguageBarOnEnglishPages() {
  for (const page of pages.filter((p) => p.lang === "en")) {
    assert.strictEqual(page.bar.lang, "ja", `${page.name}: 英語のページは日本語を案内する`);
    assert.strictEqual(load(page, { languages: ["ja-JP", "ja", "en"] }).parts.barContent.hidden, false, `${page.name}: 日本語が最初のブラウザに出す`);
    assert.strictEqual(load(page, { languages: ["en-US", "ja"] }).parts.barContent.hidden, true, `${page.name}: 英語が最初なら出さない`);
    assert.strictEqual(load(page, { languages: ["fr-FR"] }).parts.barContent.hidden, true, `${page.name}: 日本語を選んでいないブラウザには出さない`);
  }
}

function testLanguageBarRemembersDismissal() {
  const page = byName("index.html");
  const storage = makeStorage();
  const first = load(page, { languages: ["en-US"], storage });
  first.parts.barClose.dispatch("click");
  assert.strictEqual(first.parts.barContent.hidden, true, "閉じたら消える");
  assert.ok(first.parts.header.focused, "フォーカスはロゴへ移す");
  assert.strictEqual(storage.values.get("nonet.languageBarDismissed"), "1", "閉じたことを覚える");
  assert.strictEqual(load(page, { languages: ["en-US"], storage }).parts.barContent.hidden, true, "閉じたあとは出さない");
  assert.strictEqual(load(byName("en/terms.html"), { languages: ["ja"], storage }).parts.barContent.hidden, true, "ほかのページでも出さない");

  // localStorage が使えなくても、出して閉じられる
  const blocked = load(page, { languages: ["en-US"], storage: makeStorage("throws") });
  assert.strictEqual(blocked.parts.barContent.hidden, false);
  blocked.parts.barClose.dispatch("click");
  assert.strictEqual(blocked.parts.barContent.hidden, true);
}

function testNotMacNotes() {
  const page = byName("index.html");
  assert.ok(page.notMac >= 1, "index.html に Mac 以外の端末の案内がありません");
  const shown = (options) => load(page, options).parts.notes.every((note) => note.hidden === false);
  assert.ok(shown({ agent: "iphone" }), "iPhone には出す");
  assert.ok(shown({ agent: "android" }), "Android には出す");
  assert.ok(shown({ agent: "windows" }), "Windows には出す");
  assert.ok(shown({ agent: "mac", maxTouchPoints: 5 }), "Mac と名乗る iPad には出す");
  assert.ok(shown({ agent: "mac", hint: "Windows" }), "userAgentData の platform が Mac 以外なら出す");
  assert.ok(!shown({ agent: "mac" }), "Mac には出さない");
  assert.ok(!shown({ agent: "windows", hint: "macOS" }), "userAgentData の platform を優先する");
  assert.ok(!shown({ agent: "SomeBrowser/1.0" }), "分からない端末には出さない（ダウンロードを止めない）");
}

function testDownloadPageStartsOnMacOnly() {
  for (const name of ["thanks.html", "en/thanks.html"]) {
    const page = byName(name);
    assert.ok(page.download, `${name}: data-download がありません`);
    assert.strictEqual(page.download.href, "https://nonet.astlog.dev/download", `${name}: /download を開く`);

    const mac = load(page, { agent: "mac" });
    assert.deepStrictEqual(mac.assigned, [], `${name}: すぐには移動しない（ページを先に見せる）`);
    mac.clock.advance(page.download.delay);
    assert.deepStrictEqual(mac.assigned, [page.download.href], `${name}: Mac ではダウンロードを始める`);
    assert.ok(mac.parts.notes.every((note) => note.hidden), `${name}: Mac には案内を出さない`);

    const phone = load(page, { agent: "iphone" });
    phone.clock.advance(60_000);
    assert.deepStrictEqual(phone.assigned, [], `${name}: Mac 以外ではダウンロードしない`);
    assert.strictEqual(phone.parts.heading.textContent, page.download.heading[1], `${name}: 見出しを替える`);
    assert.strictEqual(phone.parts.status.hidden, true, `${name}: 「始めました」の文を隠す`);
    assert.ok(phone.parts.notes.every((note) => note.hidden === false), `${name}: 案内を出す`);

    const switched = load(page, { agent: "mac", hash: "#install" });
    switched.clock.advance(60_000);
    assert.deepStrictEqual(switched.assigned, [], `${name}: 言語を切り替えて来たとき（#install）はもう一度始めない`);
  }
}

async function testShareButton() {
  const page = byName("index.html");
  assert.ok(page.share, "index.html に共有のボタンがありません");
  const withShare = load(page, { agent: "iphone", share: true, clipboard: true });
  assert.strictEqual(withShare.parts.shareButton.textContent, page.share.labelShare, "共有できる端末では共有の文言にする");
  withShare.parts.shareButton.dispatch("click");
  assert.deepStrictEqual(withShare.shared.map((data) => data.url), [page.share.url]);

  const copyOnly = load(page, { agent: "windows", clipboard: true });
  assert.strictEqual(copyOnly.parts.shareButton.textContent, page.share.text);
  copyOnly.parts.shareButton.dispatch("click");
  await flush();
  assert.deepStrictEqual(copyOnly.copied, [page.share.url], "URL をコピーする");
  assert.strictEqual(copyOnly.parts.shareStatus.textContent, page.share.labelCopied, "コピーしたことを知らせる");

  const neither = load(page, { agent: "android" });
  assert.strictEqual(neither.parts.shareButton.hidden, true, "共有もコピーもできなければボタンを出さない");
}

function testMenuCloses() {
  const page = byName("index.html");
  assert.ok(page.menu, "index.html に狭い画面のメニューがありません");
  const d = load(page);
  d.parts.menu.open = true;
  d.parts.menuLinks[0].dispatch("click");
  assert.strictEqual(d.parts.menu.open, false, "リンクを押したら閉じる");

  d.parts.menu.open = true;
  d.parts.menu.dispatch("keydown", { key: "Escape" });
  assert.strictEqual(d.parts.menu.open, false, "Esc で閉じる");
  assert.ok(d.parts.menuSummary.focused, "閉じたらメニューのボタンへフォーカスを戻す");

  d.parts.menu.open = true;
  d.document.dispatch("click", { target: d.parts.menuSummary });
  assert.strictEqual(d.parts.menu.open, true, "メニューの中を押しても閉じない");
  d.document.dispatch("click", { target: d.parts.header });
  assert.strictEqual(d.parts.menu.open, false, "外を押したら閉じる");
}

function testPagesWithoutHooksAreUntouched() {
  assert.doesNotThrow(() => load({ name: "empty", lang: "ja", notMac: 0, menu: false }, { languages: [] }));
}

(async () => {
  const tests = [
    testLanguageBarOnJapanesePages,
    testLanguageBarOnEnglishPages,
    testLanguageBarRemembersDismissal,
    testNotMacNotes,
    testDownloadPageStartsOnMacOnly,
    testShareButton,
    testMenuCloses,
    testPagesWithoutHooksAreUntouched,
  ];
  for (const test of tests) {
    await test();
  }
  console.log(`${tests.length} 件のページのスクリプトのテストが通りました`);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});

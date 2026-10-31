// site/script.js（HUD のデモ）を、偽の DOM と時計で動かして確かめる。
// 文言とマスはページの HTML から読むので、日本語と英語のページの両方を試せる。
// 使い方: node scripts/tests/demo_harness.js <ページの HTML> <script.js>
"use strict";

const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const [pagePath, scriptPath] = process.argv.slice(2);
const html = fs.readFileSync(pagePath, "utf8");
const source = fs.readFileSync(scriptPath, "utf8");

// MARK: - ページから読むもの

const figureTag = html.match(/<figure class="demo" data-demo([^>]*)>/);
assert.ok(figureTag, "data-demo の figure がありません");
const figureData = {};
for (const [, name, value] of figureTag[1].matchAll(/data-([a-z-]+)="([^"]*)"/g)) {
  figureData[name.replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = value;
}
for (const key of ["captionRun", "captionCancel", "labelPause", "labelPlay"]) {
  assert.ok(figureData[key], `figure に data-${key} がありません`);
}
const cellsInPage = [...html.matchAll(/<div class="cell( on)?" data-cell data-label="([^"]+)"/g)].map((m) => ({
  on: Boolean(m[1]),
  label: m[2],
}));
assert.strictEqual(cellsInPage.length, 9, "マスは9個");
const staticIndex = cellsInPage.findIndex((cell) => cell.on);
assert.ok(staticIndex >= 0, "静止画で光らせるマスがありません");
const staticCaption = (html.match(/<figcaption data-demo-caption>([^<]+)<\/figcaption>/) || [])[1];
assert.ok(staticCaption, "data-demo-caption の figcaption がありません");

// MARK: - 偽の DOM

class FakeClassList {
  constructor(names = []) {
    this.names = new Set(names);
  }
  add(...names) {
    names.forEach((n) => this.names.add(n));
  }
  remove(...names) {
    names.forEach((n) => this.names.delete(n));
  }
  contains(name) {
    return this.names.has(name);
  }
  toggle(name, force) {
    const on = force === undefined ? !this.names.has(name) : Boolean(force);
    if (on) this.names.add(name);
    else this.names.delete(name);
    return on;
  }
}

class FakeElement {
  constructor({ classes = [], dataset = {}, text = "" } = {}) {
    this.classList = new FakeClassList(classes);
    this.dataset = dataset;
    this.style = {};
    this.textContent = text;
    this.hidden = false;
    this.offsetWidth = 100;
    this.listeners = {};
    this.selectors = {};
  }
  setAttribute() {}
  removeAttribute(name) {
    if (name === "style") this.style = {};
  }
  addEventListener(type, listener) {
    (this.listeners[type] = this.listeners[type] || []).push(listener);
  }
  dispatch(type, event = {}) {
    (this.listeners[type] || []).forEach((listener) => listener(event));
  }
  querySelector(selector) {
    return this.selectors[selector] || null;
  }
  querySelectorAll(selector) {
    return this.selectors[selector] || [];
  }
}

// MARK: - 偽の時計

function makeClock() {
  let now = 0;
  let nextID = 1;
  const timers = new Map();
  return {
    setTimeout(fn, ms) {
      const id = nextID++;
      timers.set(id, { at: now + ms, fn });
      return id;
    },
    clearTimeout(id) {
      timers.delete(id);
    },
    pending: () => timers.size,
    now: () => now,
    // 指定の時刻まで、期限の来たタイマーを順に動かす
    advanceTo(time) {
      for (;;) {
        let next = null;
        for (const [id, timer] of timers) {
          if (timer.at <= time && (!next || timer.at < next.timer.at)) next = { id, timer };
        }
        if (!next) break;
        timers.delete(next.id);
        now = next.timer.at;
        next.timer.fn();
      }
      now = time;
    },
  };
}

function load({ reduceMotion = false, withDemo = true } = {}) {
  const clock = makeClock();
  const cells = cellsInPage.map((cell) => new FakeElement({ classes: ["cell"].concat(cell.on ? ["on"] : []), dataset: { label: cell.label } }));
  const demo = new FakeElement({ classes: ["demo"], dataset: { ...figureData } });
  const finger = new FakeElement({ classes: ["finger"] });
  const trail = new FakeElement({ classes: ["trail"] });
  const ripple = new FakeElement({ classes: ["ripple"] });
  const toastText = new FakeElement({ text: cellsInPage[0].label });
  const caption = new FakeElement({ text: staticCaption });
  const toggle = new FakeElement({ classes: ["demo-toggle"] });
  toggle.hidden = true;
  demo.selectors = {
    "[data-cell]": cells,
    ".finger": finger,
    ".trail": trail,
    ".ripple": ripple,
    "[data-toast-text]": toastText,
    "[data-demo-caption]": caption,
    "[data-demo-toggle]": toggle,
  };

  const motion = new FakeElement();
  motion.matches = reduceMotion;
  const observers = [];
  const document = new FakeElement();
  document.hidden = false;
  document.selectors = { "[data-demo]": withDemo ? demo : null };

  const context = {
    document,
    setTimeout: clock.setTimeout,
    clearTimeout: clock.clearTimeout,
    matchMedia: () => motion,
    IntersectionObserver: class {
      constructor(callback) {
        observers.push(callback);
      }
      observe() {}
    },
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(source, context, { filename: scriptPath });

  const highlighted = () => cells.flatMap((cell, i) => (cell.classList.contains("on") ? [i] : []));
  const is = (name) => demo.classList.contains(name);
  const setVisible = (visible) => observers.forEach((callback) => callback([{ isIntersecting: visible }]));
  const fired = () => cells.flatMap((cell, i) => (cell.classList.contains("fire") ? [i] : []));
  return { clock, demo, cells, finger, trail, ripple, toastText, caption, toggle, motion, document, highlighted, fired, is, setVisible };
}

// MARK: - テスト

// 指の位置（トラックパッドの %）。外枠は左右 11%・奥 17%・手前 15%（GridMapper.cancelFrame）
const TOP_ROW = `${Math.round((17 + 68 / 6) * 100) / 100}%`; // 上の段のマスの中心
const MIDDLE_ROW = "51%";

function testOpensFromTheTopEdgeRunsThenCancelsInTheFrame() {
  const d = load();
  assert.ok(d.is("is-live"), "読み込んだら動き出す");
  assert.strictEqual(d.toggle.hidden, false, "一時停止のボタンを出す");
  assert.strictEqual(d.toggle.textContent, figureData.labelPause);
  assert.strictEqual(d.caption.textContent, figureData.captionRun);
  assert.deepStrictEqual(d.highlighted(), [], "最初は何も光らない");
  assert.ok(!d.is("hud-open") && !d.is("finger-down"));
  assert.ok(!d.is("key-down"), "キーの絵はもう無い");

  // 実行する
  d.clock.advanceTo(450);
  assert.ok(d.is("finger-down") && d.is("slide-in"), "上の縁に指を置く");
  assert.ok(!d.is("hud-open"), "置いただけでは開かない");
  assert.strictEqual(d.finger.style.left, "50%");
  assert.strictEqual(d.finger.style.top, "4%", "指は上の縁");
  assert.strictEqual(d.trail.style.height, "4%", "滑らせた跡は上の縁から指まで");

  d.clock.advanceTo(950);
  assert.ok(d.is("hud-open"), "下へ滑らせると開く");
  assert.ok(d.is("in-frame"), "開いた直後の指は上の外枠にいるので「離すとやめる」");
  assert.deepStrictEqual(d.highlighted(), [], "外枠ではマスは光らない");
  assert.strictEqual(d.finger.style.top, "12%");
  assert.ok(d.ripple.classList.contains("buzz"), "開くと振動する");

  d.clock.advanceTo(1700);
  assert.ok(!d.is("in-frame") && !d.is("slide-in"), "マスに入ると外枠を出る");
  assert.deepStrictEqual(d.highlighted(), [1], "指の下（上の段の中央）が光る");
  assert.strictEqual(d.finger.style.top, TOP_ROW);
  assert.strictEqual(d.trail.style.height, TOP_ROW, "跡は指について行く");

  d.clock.advanceTo(2500);
  assert.deepStrictEqual(d.highlighted(), [0], "指を左へ滑らせると左上のマスが光る");
  assert.strictEqual(d.finger.style.left, "24%");

  d.clock.advanceTo(3350);
  assert.ok(!d.is("finger-down"), "マスで指を離す");
  assert.deepStrictEqual(d.fired(), [0], "離したマスを実行する");

  d.clock.advanceTo(3600);
  assert.ok(!d.is("hud-open"), "実行すると HUD が閉じる");
  assert.ok(d.is("toast-show"), "実行したマスを知らせる");
  assert.strictEqual(d.toastText.textContent, cellsInPage[0].label);

  d.clock.advanceTo(4500);
  assert.ok(!d.is("toast-show"));

  // やめる
  d.clock.advanceTo(5100);
  assert.strictEqual(d.caption.textContent, figureData.captionCancel, "続けて、やめ方の説明");
  assert.deepStrictEqual(d.fired(), []);
  assert.deepStrictEqual(d.highlighted(), []);

  d.clock.advanceTo(5250);
  assert.strictEqual(d.finger.style.top, "4%", "もう一度、上の縁から");

  d.clock.advanceTo(5750);
  assert.ok(d.is("hud-open") && d.is("in-frame"), "開く");

  d.clock.advanceTo(7200);
  assert.ok(!d.is("in-frame"));
  assert.deepStrictEqual(d.highlighted(), [4], "中央のマスへ");
  assert.strictEqual(d.finger.style.top, MIDDLE_ROW);

  d.clock.advanceTo(8000);
  assert.ok(d.is("in-frame"), "右の外枠へ滑らせると、マスが暗くなり「離すとやめる」");
  assert.deepStrictEqual(d.highlighted(), [], "外枠ではマスは光らない");
  assert.strictEqual(d.finger.style.left, "94.5%");
  assert.strictEqual(d.finger.style.top, MIDDLE_ROW);

  d.clock.advanceTo(9050);
  assert.ok(!d.is("finger-down"), "外枠で指を離す");

  d.clock.advanceTo(9400);
  assert.ok(!d.is("hud-open") && !d.is("in-frame"), "何も実行せずに閉じる");
  assert.ok(!d.is("toast-show"), "知らせも出ない");
  assert.deepStrictEqual(d.fired(), [], "どのマスも実行しない");
  assert.strictEqual(d.toastText.textContent, cellsInPage[0].label);

  d.clock.advanceTo(10700);
  assert.strictEqual(d.caption.textContent, figureData.captionRun, "最初からくり返す");
  assert.ok(!d.is("hud-open") && !d.is("toast-show"));
  assert.ok(d.clock.pending() > 0);
}

function testPauseShowsTheStaticPicture() {
  const d = load();
  d.clock.advanceTo(2500);
  d.toggle.dispatch("click");
  assert.ok(!d.is("is-live"), "止めると静止画に戻る");
  assert.deepStrictEqual(d.highlighted(), [staticIndex]);
  assert.strictEqual(d.caption.textContent, staticCaption);
  assert.strictEqual(d.toggle.textContent, figureData.labelPlay);
  assert.deepStrictEqual(d.finger.style, {}, "指は中央のマス（CSS の既定）に戻る");
  assert.deepStrictEqual(d.trail.style, {}, "跡は上の縁から中央のマスまで（CSS の既定）");
  for (const name of ["hud-open", "finger-down", "slide-in", "in-frame", "toast-show"]) {
    assert.ok(!d.is(name), `静止画では ${name} を外す`);
  }
  assert.strictEqual(d.clock.pending(), 0, "タイマーを残さない");

  d.toggle.dispatch("click");
  assert.ok(d.is("is-live"), "もう一度押すと動く");
  assert.strictEqual(d.toggle.textContent, figureData.labelPause);
}

function testReducedMotionStartsPaused() {
  const d = load({ reduceMotion: true });
  assert.ok(!d.is("is-live"), "動きを減らす設定では動かさない");
  assert.strictEqual(d.toggle.textContent, figureData.labelPlay);
  assert.strictEqual(d.toggle.hidden, false, "自分で動かせる");
  assert.strictEqual(d.clock.pending(), 0);

  d.motion.dispatch("change", { matches: false });
  assert.ok(d.is("is-live"), "設定を戻したら動く");
}

function testStopsWhileOffScreenOrHidden() {
  const d = load();
  d.setVisible(false);
  assert.ok(!d.is("is-live"), "画面の外では止める");
  assert.strictEqual(d.clock.pending(), 0);
  d.setVisible(true);
  assert.ok(d.is("is-live"));

  d.document.hidden = true;
  d.document.dispatch("visibilitychange");
  assert.ok(!d.is("is-live"), "タブが隠れたら止める");
  d.document.hidden = false;
  d.document.dispatch("visibilitychange");
  assert.ok(d.is("is-live"));
}

function testPagesWithoutTheDemoAreUntouched() {
  assert.doesNotThrow(() => load({ withDemo: false }));
}

const tests = [
  testOpensFromTheTopEdgeRunsThenCancelsInTheFrame,
  testPauseShowsTheStaticPicture,
  testReducedMotionStartsPaused,
  testStopsWhileOffScreenOrHidden,
  testPagesWithoutTheDemoAreUntouched,
];
for (const test of tests) {
  test();
}
console.log(`${tests.length} 件のデモのテストが通りました: ${pagePath}`);

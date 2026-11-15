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
const cellsInPage = [...html.matchAll(/<div class="cell slot-[0-7c]( on)?" data-cell data-label="([^"]+)"/g)].map((m) => ({
  on: Boolean(m[1]),
  label: m[2],
}));
assert.strictEqual(cellsInPage.length, 9, "マスは9個");
const staticIndex = cellsInPage.findIndex((cell) => cell.on);
assert.ok(staticIndex >= 0, "静止画で光らせるマスがありません");
const staticCaption = (html.match(/<figcaption data-demo-caption>([^<]+)<\/figcaption>/) || [])[1];
assert.ok(staticCaption, "data-demo-caption の figcaption がありません");
const staticLabel = (html.match(/<span class="hud-label" data-hud-label>([^<]+)<\/span>/) || [])[1];
assert.ok(staticLabel, "data-hud-label の名前の帯がありません");
assert.strictEqual(staticLabel, cellsInPage[staticIndex].label, "静止画の名前は、光らせているアイコンのもの");

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
  const pointer = new FakeElement({ classes: ["pointer"] });
  const label = new FakeElement({ classes: ["hud-label"], text: staticLabel });
  const finger = new FakeElement({ classes: ["finger"] });
  const trail = new FakeElement({ classes: ["trail"] });
  const ripple = new FakeElement({ classes: ["ripple"] });
  const toastText = new FakeElement({ text: cellsInPage[0].label });
  const caption = new FakeElement({ text: staticCaption });
  const toggle = new FakeElement({ classes: ["demo-toggle"] });
  toggle.hidden = true;
  demo.selectors = {
    "[data-cell]": cells,
    ".pointer": pointer,
    "[data-hud-label]": label,
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
  return { clock, demo, cells, pointer, label, finger, trail, ripple, toastText, caption, toggle, motion, document, highlighted, fired, is, setVisible };
}

// MARK: - テスト

// 指の位置（トラックパッドの %）とポインタの位置（HUD の正方形の %）。script.js の OPENED・TRAVEL・RING・DIAGONAL と同じ値で計算する
const RING = 40.3;
const DIAGONAL = 28.5;
const fingerFor = ({ x, y }) => ({ x: 50 + (x - 50) / 1.3, y: 12 + (y - 50) / 2 });
const pct = (value) => `${Math.round(value * 100) / 100}%`;
const BOTTOM = { x: 50, y: 50 + RING }; // 下のアイコン（マス 7）
const BOTTOM_RIGHT = { x: 50 + DIAGONAL, y: 50 + DIAGONAL }; // 右下のアイコン（マス 8）
const OUTSIDE = { x: 50, y: 106 }; // 輪の外（下）

function testOpensFromTheTopEdgeRunsThenCancelsOutsideTheRing() {
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
  assert.strictEqual(d.trail.style.height, "0px", "滑らせた跡は、まだ無い");

  d.clock.advanceTo(950);
  assert.ok(d.is("hud-open"), "下へ滑らせると開く");
  assert.ok(!d.is("in-frame"), "開いた直後はアイコンを薄くしない（まだ何も向けていない）");
  assert.deepStrictEqual(d.highlighted(), [], "まだ何も光らない");
  assert.strictEqual(d.finger.style.top, "12%");
  assert.strictEqual(d.pointer.style.left, "50%");
  assert.strictEqual(d.pointer.style.top, "50%", "ポインタは円の中心");
  assert.ok(d.pointer.classList.contains("jump"), "ポインタは滑らせずに中心へ置く");
  assert.strictEqual(d.trail.style.height, "12px", "跡は上の縁から指まで（8% × 150px）");
  assert.ok(d.ripple.classList.contains("buzz"), "開くと振動する");

  d.clock.advanceTo(1700);
  assert.ok(!d.is("slide-in"), "アイコンに向けたら、入ってきた跡を消す");
  assert.deepStrictEqual(d.highlighted(), [7], "指を下へ滑らせると、下のアイコンに白い円");
  assert.strictEqual(d.pointer.style.top, pct(BOTTOM.y), "ポインタは下のアイコンの上");
  assert.ok(!d.pointer.classList.contains("jump"), "ポインタは滑らせて動く");
  assert.strictEqual(d.finger.style.top, pct(fingerFor(BOTTOM).y), "指は開いたところから、ポインタの動きの分だけ下");
  assert.strictEqual(d.finger.style.left, "50%");

  d.clock.advanceTo(2500);
  assert.deepStrictEqual(d.highlighted(), [8], "右へ滑らせると右下のアイコンへ");
  assert.strictEqual(d.pointer.style.left, pct(BOTTOM_RIGHT.x));
  assert.strictEqual(d.finger.style.left, pct(fingerFor(BOTTOM_RIGHT).x));
  assert.strictEqual(d.finger.style.top, pct(fingerFor(BOTTOM_RIGHT).y));
  assert.ok(/rotate\(-\d+deg\)/.test(d.trail.style.transform), "跡は右下へ向く");

  assert.ok(!d.is("label-show"), "移った直後は名前はまだ出ない");

  d.clock.advanceTo(3100);
  assert.ok(d.is("label-show"), "向けたまま 0.6 秒止めると名前が出る");
  assert.strictEqual(d.label.textContent, cellsInPage[8].label, "名前は向けているアイコンのもの");
  assert.strictEqual(d.label.style.left, pct(BOTTOM_RIGHT.x), "名前はそのアイコンの下");

  d.clock.advanceTo(3750);
  assert.ok(!d.is("finger-down"), "アイコンで指を離す");
  assert.deepStrictEqual(d.fired(), [8], "離したアイコンを実行する");

  d.clock.advanceTo(4000);
  assert.ok(!d.is("hud-open"), "実行すると HUD が閉じる");
  assert.ok(!d.is("label-show"), "閉じれば名前も消える");
  assert.ok(d.is("toast-show"), "実行したマスを知らせる");
  assert.strictEqual(d.toastText.textContent, cellsInPage[8].label);

  d.clock.advanceTo(4900);
  assert.ok(!d.is("toast-show"));

  // やめる
  d.clock.advanceTo(5500);
  assert.strictEqual(d.caption.textContent, figureData.captionCancel, "続けて、やめ方の説明");
  assert.deepStrictEqual(d.fired(), []);
  assert.deepStrictEqual(d.highlighted(), []);

  d.clock.advanceTo(5650);
  assert.strictEqual(d.finger.style.top, "4%", "もう一度、上の縁から");

  d.clock.advanceTo(6150);
  assert.ok(d.is("hud-open") && !d.is("in-frame"), "開く。薄くしない");
  assert.strictEqual(d.pointer.style.top, "50%");

  d.clock.advanceTo(7000);
  assert.deepStrictEqual(d.highlighted(), [7], "下のアイコンへ");

  d.clock.advanceTo(7900);
  assert.ok(d.is("in-frame"), "輪の外まで動かすと、全部のアイコンが薄くなる");
  assert.deepStrictEqual(d.highlighted(), [], "輪の外では何も光らない");
  assert.ok(!d.is("label-show"), "外へ出せば名前は出ない");
  assert.strictEqual(d.pointer.style.top, pct(OUTSIDE.y), "ポインタは輪の外（下）");
  assert.strictEqual(d.finger.style.top, pct(fingerFor(OUTSIDE).y));
  assert.ok(parseFloat(d.finger.style.top) < 100, "指はトラックパッドの中");

  d.clock.advanceTo(9050);
  assert.ok(!d.is("finger-down"), "輪の外で指を離す");

  d.clock.advanceTo(9350);
  assert.ok(!d.is("hud-open") && !d.is("in-frame"), "何も実行せずに閉じる");
  assert.ok(!d.is("toast-show"), "知らせも出ない");
  assert.deepStrictEqual(d.fired(), [], "どのマスも実行しない");
  assert.strictEqual(d.toastText.textContent, cellsInPage[8].label);

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
  assert.deepStrictEqual(d.finger.style, {}, "指は静止画の位置（CSS の既定）に戻る");
  assert.deepStrictEqual(d.trail.style, {}, "跡は静止画の長さと向き（CSS の既定）");
  assert.deepStrictEqual(d.pointer.style, {}, "ポインタは静止画のアイコンの上（CSS の既定）");
  assert.deepStrictEqual(d.label.style, {}, "名前の帯は静止画のアイコンの下（CSS の既定）");
  assert.strictEqual(d.label.textContent, staticLabel, "名前は静止画のもの");
  for (const name of ["hud-open", "finger-down", "slide-in", "in-frame", "toast-show", "label-show"]) {
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
  testOpensFromTheTopEdgeRunsThenCancelsOutsideTheRing,
  testPauseShowsTheStaticPicture,
  testReducedMotionStartsPaused,
  testStopsWhileOffScreenOrHidden,
  testPagesWithoutTheDemoAreUntouched,
];
for (const test of tests) {
  test();
}
console.log(`${tests.length} 件のデモのテストが通りました: ${pagePath}`);

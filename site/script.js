// HUD のデモを動かす。JavaScript が無いとき・動きを減らす設定のときは静止画のまま。
// 文言は HTML の data-* から読むので、日本語と英語のページで共通に使える
(() => {
  "use strict";

  const demo = document.querySelector("[data-demo]");
  if (!demo) return;

  const cells = Array.from(demo.querySelectorAll("[data-cell]"));
  const finger = demo.querySelector(".finger");
  const ripple = demo.querySelector(".ripple");
  const toastText = demo.querySelector("[data-toast-text]");
  const caption = demo.querySelector("[data-demo-caption]");
  const toggle = demo.querySelector("[data-demo-toggle]");
  if (cells.length !== 9 || !finger || !ripple || !toastText || !caption || !toggle) return;

  const staticCaption = caption.textContent;
  const staticHighlight = cells.findIndex((cell) => cell.classList.contains("on"));
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  let timers = [];
  let pausedByUser = reduceMotion.matches;
  let onScreen = true;
  let running = false;

  const later = (ms, action) => {
    timers.push(window.setTimeout(action, ms));
  };

  const clearTimers = () => {
    timers.forEach((id) => window.clearTimeout(id));
    timers = [];
  };

  const setState = (name, on) => demo.classList.toggle(name, on);

  // トラックパッドの 3×3 の中心。指の位置はトラックパッドの絶対位置で決まる
  const moveFinger = (index, { jump = false } = {}) => {
    const column = index % 3;
    const row = Math.floor(index / 3);
    finger.classList.toggle("jump", jump);
    finger.style.left = `${((column + 0.5) / 3) * 100}%`;
    finger.style.top = `${((row + 0.5) / 3) * 100}%`;
  };

  const highlight = (index) => {
    cells.forEach((cell, i) => cell.classList.toggle("on", i === index));
  };

  // マスの境界をまたいだときの振動
  const buzz = () => {
    ripple.style.left = finger.style.left;
    ripple.style.top = finger.style.top;
    ripple.classList.remove("buzz");
    void ripple.offsetWidth;
    ripple.classList.add("buzz");
  };

  const fire = (index) => {
    const cell = cells[index];
    cell.classList.remove("fire");
    void cell.offsetWidth;
    cell.classList.add("fire");
  };

  const showToast = (index) => {
    toastText.textContent = cells[index].dataset.label || "";
    setState("toast-show", true);
  };

  // HUD を出さずに即実行する速押し
  const tap = (index) => {
    moveFinger(index, { jump: true });
    setState("finger-down", true);
    later(170, () => {
      setState("finger-down", false);
      fire(index);
      showToast(index);
    });
  };

  const resetScene = () => {
    ["hud-open", "key-down", "finger-down", "toast-show"].forEach((name) => setState(name, false));
    highlight(-1);
    moveFinger(4, { jump: true });
  };

  const scene = () => {
    clearTimers();
    resetScene();
    caption.textContent = demo.dataset.captionHud || staticCaption;

    // 迷ったとき: 指を置いて止まる → HUD → 指でなぞる → キーを離して実行
    later(500, () => setState("key-down", true));
    later(800, () => {
      moveFinger(4, { jump: true });
      setState("finger-down", true);
    });
    later(1150, () => {
      finger.classList.remove("jump");
      setState("hud-open", true);
      highlight(4);
    });
    later(1900, () => moveFinger(5));
    later(2060, () => {
      highlight(5);
      buzz();
    });
    later(2700, () => moveFinger(2));
    later(2860, () => {
      highlight(2);
      buzz();
    });
    later(3800, () => {
      setState("key-down", false);
      fire(2);
    });
    later(4050, () => {
      setState("finger-down", false);
      setState("hud-open", false);
      showToast(2);
    });
    later(4900, () => setState("toast-show", false));

    // 慣れたら: 押してすぐタップ（HUD は出ない）。押したまま続けて実行できる
    later(5600, () => {
      caption.textContent = demo.dataset.captionTap || staticCaption;
      highlight(-1);
      setState("key-down", true);
    });
    later(5850, () => tap(0));
    later(6700, () => setState("toast-show", false));
    later(7000, () => tap(8));
    later(7850, () => setState("toast-show", false));
    later(8200, () => setState("key-down", false));
    later(9400, scene);
  };

  const start = () => {
    if (running) return;
    running = true;
    setState("is-live", true);
    scene();
  };

  const stop = () => {
    running = false;
    clearTimers();
    setState("is-live", false);
    ["hud-open", "key-down", "finger-down", "toast-show"].forEach((name) => setState(name, false));
    finger.removeAttribute("style");
    finger.classList.remove("jump");
    ripple.classList.remove("buzz");
    cells.forEach((cell) => cell.classList.remove("fire"));
    highlight(staticHighlight);
    caption.textContent = staticCaption;
  };

  const update = () => {
    const shouldRun = !pausedByUser && onScreen && !document.hidden;
    if (shouldRun) start();
    else stop();
    toggle.textContent = pausedByUser ? demo.dataset.labelPlay : demo.dataset.labelPause;
  };

  toggle.hidden = false;
  toggle.addEventListener("click", () => {
    pausedByUser = !pausedByUser;
    update();
  });

  reduceMotion.addEventListener("change", (event) => {
    pausedByUser = event.matches;
    update();
  });

  document.addEventListener("visibilitychange", update);

  if ("IntersectionObserver" in window) {
    new IntersectionObserver((entries) => {
      onScreen = entries.some((entry) => entry.isIntersecting);
      update();
    }).observe(demo);
  }

  update();
})();

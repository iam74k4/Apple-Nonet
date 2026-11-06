// 販売ページのスクリプト。どれも、JavaScript が無くてもページが使える上での上乗せ:
//   - HUD のデモを動かす（上の縁から開いて実行・外枠で離してやめる。JavaScript が無いとき・動きを減らす設定のときは静止画のまま）
//   - 言語の案内: 日本語のページを日本語を読まないブラウザで、英語のページを日本語を最初に選んだブラウザで
//     開いたときだけ、もう一方の言語のページがあることを知らせる（自動では移動しない。閉じたら覚える）
//   - Mac 以外の端末（iPhone・Android・Windows など）: ダウンロードの代わりに案内を出す
//   - ダウンロードのページ（thanks.html）: Mac ならダウンロードを始める
//   - 狭い画面のメニュー（<details>）: 中のリンクを押したら閉じる
// 文言とリンクは HTML（data-* と要素の中身）から読むので、日本語と英語のページで共通に使える。
// 外へは通信しない。URL は HTML から読む（scripts/check-site.sh が、このファイルに URL の文字列を書くことを禁じている）
(() => {
  "use strict";

  const doc = document;
  const nav = window.navigator || {};

  // MARK: 端末

  // "mac" | "other" | "unknown"。分からないときは Mac として扱う（ダウンロードを止めない）
  const platform = () => {
    const hint = nav.userAgentData && nav.userAgentData.platform;
    if (typeof hint === "string" && hint !== "") {
      return hint === "macOS" ? "mac" : "other";
    }
    const agent = String(nav.userAgent || "");
    // iPhone の User-Agent も「like Mac OS X」を含むので、先に見る
    if (/iPhone|iPad|iPod|Android|Windows|CrOS|Linux/.test(agent)) return "other";
    if (/Macintosh|Mac OS X/.test(agent)) {
      // iPadOS の Safari は、デスクトップ用の表示では Mac と名乗る。Mac にタッチの画面は無い
      return (nav.maxTouchPoints || 0) > 1 ? "other" : "mac";
    }
    return "unknown";
  };

  // localStorage は使えないことがある（プライベートブラウズ・ブロックの設定）。そのときは覚えないだけ
  const storage = {
    get(key) {
      try {
        return window.localStorage.getItem(key);
      } catch (error) {
        return null;
      }
    },
    set(key, value) {
      try {
        window.localStorage.setItem(key, value);
      } catch (error) {
        // 覚えられなくても、閉じることはできる
      }
    },
  };

  // MARK: HUD のデモ

  // 上の縁から指を下へ滑らせて開き（ポインタの周りに9つのアイコン）、指を滑らせてポインタを向け、アイコンで離して実行する。
  // 続けて、もう一度開いてアイコンの輪の外まで動かし、離して何も実行せずに閉じる
  const setUpDemo = () => {
    const demo = doc.querySelector("[data-demo]");
    if (!demo) return;

    const cells = Array.from(demo.querySelectorAll("[data-cell]"));
    const pointer = demo.querySelector(".pointer");
    const label = demo.querySelector("[data-hud-label]");
    const finger = demo.querySelector(".finger");
    const trail = demo.querySelector(".trail");
    const ripple = demo.querySelector(".ripple");
    const toastText = demo.querySelector("[data-toast-text]");
    const caption = demo.querySelector("[data-demo-caption]");
    const toggle = demo.querySelector("[data-demo-toggle]");
    if (cells.length !== 9 || !pointer || !label || !finger || !trail || !ripple || !toastText || !caption || !toggle) return;

    const staticCaption = caption.textContent;
    const staticLabel = label.textContent;
    const staticHighlight = cells.findIndex((cell) => cell.classList.contains("on"));
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const states = ["hud-open", "finger-down", "slide-in", "in-frame", "toast-show", "label-show"];
    // 向けたまま止めてから名前が出るまで（アプリの HUDLayout.labelDelay と同じ）
    const LABEL_DELAY = 600;

    // HUD の円（正方形の %）。8つのアイコンは中心から RING の円の上に 45° おき、真ん中に 9つ目。
    // アプリの RadialLayout（鍵の円 108 / 外枠 134）と同じ割合。style.css の --ring・--ring-diagonal と合わせる
    const RING = 40.3;
    const DIAGONAL = 28.5; // RING × cos 45°
    const CENTER = { x: 50, y: 50 };
    // マスの番号（左上から右へ、上の行から）→ そのアイコンの位置（ポインタを向けるところ）
    const KEYS = [
      { x: 50 - DIAGONAL, y: 50 - DIAGONAL }, { x: 50, y: 50 - RING }, { x: 50 + DIAGONAL, y: 50 - DIAGONAL },
      { x: 50 - RING, y: 50 }, CENTER, { x: 50 + RING, y: 50 },
      { x: 50 - DIAGONAL, y: 50 + DIAGONAL }, { x: 50, y: 50 + RING }, { x: 50 + DIAGONAL, y: 50 + DIAGONAL },
    ];
    const OUTSIDE_BELOW = { x: 50, y: 106 }; // アイコンの輪の外（下。輪の縁は正方形の縁）。越えると全部が薄くなる。画面の中に収まる位置

    // 指の位置（トラックパッドの左上からの %）
    const EDGE = { x: 50, y: 4 }; // 上の縁に指を置いたところ
    const OPENED = { x: 50, y: 12 }; // 下へ滑らせて開いたところ。ポインタはここで円の中心に来る
    // 指の動き（トラックパッドの %）をポインタの動き（HUD の %）にする倍率。トラックパッドは横長なので縦は大きめ
    const TRAVEL = { x: 1.3, y: 2 };
    const fingerFor = (point) => ({
      x: OPENED.x + (point.x - CENTER.x) / TRAVEL.x,
      y: OPENED.y + (point.y - CENTER.y) / TRAVEL.y,
    });
    // トラックパッドの図の大きさ（style.css の .trackpad）。滑らせた跡の長さと向きに使う
    const PAD = { width: 240, height: 150 };

    const percent = (value) => `${Math.round(value * 100) / 100}%`;

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

    // 指を動かし、上の縁に置いたところからの跡を指まで伸ばす。jump のときは滑らせずに、その場に置く
    const place = ({ x, y }, { jump = false } = {}) => {
      finger.classList.toggle("jump", jump);
      trail.classList.toggle("jump", jump);
      finger.style.left = percent(x);
      finger.style.top = percent(y);
      const dx = ((x - EDGE.x) / 100) * PAD.width;
      const dy = ((y - EDGE.y) / 100) * PAD.height;
      trail.style.height = `${Math.round(Math.hypot(dx, dy))}px`;
      trail.style.transform = `translateX(-50%) rotate(${Math.round((-Math.atan2(dx, dy) * 180) / Math.PI)}deg)`;
    };

    // ポインタを動かす（HUD の正方形の %）。jump は開いたときに円の中心へ置くとき
    const movePointer = ({ x, y }, { jump = false } = {}) => {
      pointer.classList.toggle("jump", jump);
      pointer.style.left = percent(x);
      pointer.style.top = percent(y);
    };

    // 指を滑らせてポインタを向ける。指が動いた分だけポインタが動く
    const pointAt = (point) => {
      place(fingerFor(point));
      movePointer(point);
    };

    const highlight = (index) => {
      cells.forEach((cell, i) => cell.classList.toggle("on", i === index));
      // 別のアイコンへ移ったら名前は消える
      setState("label-show", false);
    };

    // 向けたまま止めたアイコンの名前を、そのアイコンの下に出す
    const showLabel = (index) => {
      const point = KEYS[index];
      label.textContent = cells[index].dataset.label || "";
      label.style.left = percent(point.x);
      label.style.top = `calc(${percent(point.y)} + 22px)`;
      setState("label-show", true);
    };

    // 振動（開いたとき・アイコンが替わったとき・実行したとき。何も実行せずに閉じたときは2回）
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

    const clearFire = () => cells.forEach((cell) => cell.classList.remove("fire"));

    const showToast = (index) => {
      toastText.textContent = cells[index].dataset.label || "";
      setState("toast-show", true);
    };

    // 上の縁に指を置き、下へ滑らせると開く。開くとポインタは円の中心に来て、アイコンは全部はっきり見える
    // （まだ何も向けていない。このまま離せば何もしない）
    const openFromTopEdge = (at) => {
      later(at, () => {
        place(EDGE, { jump: true });
        setState("finger-down", true);
        setState("slide-in", true);
      });
      later(at + 300, () => place(OPENED));
      later(at + 520, () => {
        movePointer(CENTER, { jump: true });
        setState("hud-open", true);
        buzz();
      });
    };

    const resetScene = () => {
      states.forEach((name) => setState(name, false));
      highlight(-1);
      clearFire();
      place(EDGE, { jump: true });
      movePointer(CENTER, { jump: true });
    };

    const scene = () => {
      clearTimers();
      resetScene();
      caption.textContent = demo.dataset.captionRun || staticCaption;

      // 実行する: 上の縁から開く → 指を滑らせて下のアイコン、右下のアイコンへ向ける → そこで離す
      openFromTopEdge(400);
      later(1500, () => pointAt(KEYS[7]));
      later(1660, () => {
        setState("slide-in", false);
        highlight(7);
        buzz();
      });
      later(2300, () => pointAt(KEYS[8]));
      later(2460, () => {
        highlight(8);
        buzz();
      });
      // 向けたまま止めると、そのアイコンの名前が出る
      later(2460 + LABEL_DELAY, () => showLabel(8));
      later(3700, () => {
        setState("finger-down", false);
        fire(8);
        buzz();
      });
      later(3900, () => {
        setState("hud-open", false);
        setState("label-show", false);
        showToast(8);
      });
      later(4800, () => setState("toast-show", false));

      // やめる: もう一度開く → 下のアイコンを通って輪の外まで動かす（全部が薄くなる）→ 離すと、何も実行せずに閉じる
      later(5400, () => {
        caption.textContent = demo.dataset.captionCancel || staticCaption;
        highlight(-1);
        clearFire();
      });
      openFromTopEdge(5600);
      later(6800, () => pointAt(KEYS[7]));
      later(6960, () => {
        setState("slide-in", false);
        highlight(7);
        buzz();
      });
      later(7700, () => pointAt(OUTSIDE_BELOW));
      later(7860, () => {
        highlight(-1);
        setState("in-frame", true);
      });
      later(9000, () => {
        setState("finger-down", false);
        buzz();
      });
      later(9180, buzz);
      later(9300, () => {
        setState("hud-open", false);
        setState("in-frame", false);
      });
      later(10600, scene);
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
      states.forEach((name) => setState(name, false));
      [finger, trail, pointer, label].forEach((element) => {
        element.removeAttribute("style");
        element.classList.remove("jump");
      });
      ripple.classList.remove("buzz");
      clearFire();
      highlight(staticHighlight);
      label.textContent = staticLabel;
      caption.textContent = staticCaption;
    };

    const update = () => {
      const shouldRun = !pausedByUser && onScreen && !doc.hidden;
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

    doc.addEventListener("visibilitychange", update);

    if ("IntersectionObserver" in window) {
      new IntersectionObserver((entries) => {
        onScreen = entries.some((entry) => entry.isIntersecting);
        update();
      }).observe(demo);
    }

    update();
  };

  // MARK: 言語の案内

  const LANGUAGE_BAR_DISMISSED = "nonet.languageBarDismissed";

  // "ja-JP" → "ja"
  const primaryLanguage = (tag) => String(tag || "").toLowerCase().split("-")[0];

  const preferredLanguages = () => {
    const list = nav.languages && nav.languages.length ? Array.from(nav.languages) : [nav.language];
    return list.map(primaryLanguage).filter((language) => language !== "");
  };

  const setUpLanguageBar = () => {
    const bar = doc.querySelector("[data-lang-bar]");
    if (!bar) return;
    const content = bar.querySelector("[data-lang-bar-content]");
    const close = bar.querySelector("[data-lang-bar-close]");
    const pageLanguage = primaryLanguage(doc.documentElement && doc.documentElement.lang);
    const offered = primaryLanguage(bar.lang);
    if (!content || !close || !pageLanguage || !offered || offered === pageLanguage) return;
    if (storage.get(LANGUAGE_BAR_DISMISSED) === "1") return;

    const languages = preferredLanguages();
    if (languages.length === 0) return;
    // 日本語のページ（英語を案内する）: 日本語を1つも選んでいないブラウザに知らせる（フランス語などのブラウザにも。
    //   日本語より英語のほうが読める見込みが高い）。日本語も選んでいれば、日本語のまま読める
    // 英語のページ（日本語を案内する）: 日本語をいちばんに選んでいるブラウザに知らせる
    const show = offered === "en" ? !languages.includes(pageLanguage) : languages[0] === offered;
    if (!show) return;

    content.hidden = false;
    close.addEventListener("click", () => {
      content.hidden = true;
      storage.set(LANGUAGE_BAR_DISMISSED, "1");
      // 押したボタンが消えるので、フォーカスを本文の手前（ロゴ）に移す
      const brand = doc.querySelector(".site-header .brand");
      if (brand && typeof brand.focus === "function") brand.focus();
    });
  };

  // MARK: Mac 以外の端末とダウンロード

  const setUpShareButtons = () => {
    doc.querySelectorAll("[data-share]").forEach((button) => {
      const url = button.dataset.shareUrl;
      const status = button.parentNode && button.parentNode.querySelector("[data-share-status]");
      const canShare = typeof nav.share === "function";
      const canCopy = Boolean(nav.clipboard && typeof nav.clipboard.writeText === "function");
      if (!url || (!canShare && !canCopy)) {
        // 共有もコピーもできなければ、ボタンは出さない（案内の文に URL がある）
        button.hidden = true;
        return;
      }
      if (canShare && button.dataset.labelShare) button.textContent = button.dataset.labelShare;
      button.addEventListener("click", () => {
        if (canShare) {
          // 共有の画面を閉じたときも reject になるので、何もしない
          Promise.resolve(nav.share({ url })).catch(() => {});
          return;
        }
        Promise.resolve(nav.clipboard.writeText(url)).then(
          () => {
            if (status) status.textContent = button.dataset.labelCopied || "";
          },
          () => {},
        );
      });
    });
  };

  const setUpDownload = (kind) => {
    const box = doc.querySelector("[data-download]");
    if (!box) return;
    const link = box.querySelector("[data-download-link]");
    if (!link || !link.href) return;

    if (kind === "other") {
      // DMG は Mac でしか開けない。見出しを替え、ダウンロードは始めない（案内は [data-not-mac] が出す）
      const heading = box.querySelector("[data-download-heading]");
      const status = box.querySelector("[data-download-status]");
      if (heading && heading.dataset.textNotMac) heading.textContent = heading.dataset.textNotMac;
      if (status) status.hidden = true;
      return;
    }
    // 言語を切り替えて来たとき（#install）は、もう始めてあるので始めない
    if (window.location && window.location.hash === "#install") return;
    const delay = Number(box.dataset.downloadDelay) || 0;
    window.setTimeout(() => window.location.assign(link.href), delay);
  };

  const setUpPlatform = () => {
    const kind = platform();
    if (kind === "other") {
      doc.querySelectorAll("[data-not-mac]").forEach((note) => {
        note.hidden = false;
      });
    }
    setUpShareButtons();
    setUpDownload(kind);
  };

  // MARK: 狭い画面のメニュー

  const setUpMenus = () => {
    const menus = Array.from(doc.querySelectorAll("[data-menu]"));
    if (menus.length === 0) return;
    menus.forEach((menu) => {
      menu.querySelectorAll("a").forEach((link) => {
        link.addEventListener("click", () => {
          menu.open = false;
        });
      });
      menu.addEventListener("keydown", (event) => {
        if (event.key !== "Escape" || !menu.open) return;
        menu.open = false;
        const summary = menu.querySelector("summary");
        if (summary && typeof summary.focus === "function") summary.focus();
      });
    });
    // 外を押したら閉じる
    doc.addEventListener("click", (event) => {
      menus.forEach((menu) => {
        if (menu.open && !menu.contains(event.target)) menu.open = false;
      });
    });
  };

  setUpDemo();
  setUpLanguageBar();
  setUpPlatform();
  setUpMenus();
})();

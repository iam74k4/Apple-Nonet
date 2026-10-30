// 販売ページのスクリプト。どれも、JavaScript が無くてもページが使える上での上乗せ:
//   - HUD のデモを動かす（JavaScript が無いとき・動きを減らす設定のときは静止画のまま）
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

  const setUpDemo = () => {
    const demo = doc.querySelector("[data-demo]");
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

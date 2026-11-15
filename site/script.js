// 販売ページのスクリプト。どれも、JavaScript が無くてもページが使える上での上乗せ:
//   - ヒーローの動画（実物の収録）を自動で動かし、止めるボタンを出す（JavaScript が無いときは動画の controls のまま）
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

  // MARK: 収録の動画

  // ヒーローの動画（実物の収録）。JavaScript が無いときは controls のまま（自動では動かない）。
  // あれば controls を外して自動で動かし、左下のボタンで止められるようにする（動きを減らす設定のときは止めたまま始める）。
  // 画面の外にある間は止めておく。見る人が止めたら、画面に戻っても動かさない
  const setUpVideo = () => {
    const figure = doc.querySelector("[data-video]");
    if (!figure) return;
    const video = figure.querySelector("video");
    const toggle = figure.querySelector("[data-video-toggle]");
    if (!video || !toggle) return;
    const reduce =
      typeof window.matchMedia === "function" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let wanted = !reduce;
    let visible = true;
    const icon = toggle.querySelector("use");
    const render = () => {
      toggle.setAttribute("aria-label", (wanted ? figure.dataset.labelPause : figure.dataset.labelPlay) || "");
      if (icon) icon.setAttribute("href", wanted ? "#i-pause" : "#i-play");
    };
    const apply = () => {
      if (!(wanted && visible)) {
        video.pause();
        return;
      }
      const playing = video.play();
      // 自動再生を止めるブラウザの設定（省電力など）では、再生のボタンを見せて待つ
      if (playing && typeof playing.catch === "function") {
        playing.catch(() => {
          wanted = false;
          render();
        });
      }
    };
    video.controls = false;
    video.removeAttribute("controls");
    toggle.hidden = false;
    toggle.addEventListener("click", () => {
      wanted = !wanted;
      render();
      apply();
    });
    if (typeof window.IntersectionObserver === "function") {
      new window.IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          visible = entry.isIntersecting;
        });
        apply();
      }).observe(video);
    }
    render();
    apply();
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

  setUpVideo();
  setUpLanguageBar();
  setUpPlatform();
  setUpMenus();
})();

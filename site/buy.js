// 購入のページ（buy.html・en/buy.html）のスクリプト。先に読み込んだ Paddle.js で、購入画面（オーバーレイ）を開く。
//   - トークンと価格の ID は HTML の data-paddle-token・data-paddle-price から読む。test_ のトークンなら sandbox で開く
//   - ?_ptxn=… で開かれたとき（Paddle の Default payment link）は、その取引の購入画面を Paddle.js が自分で開くので、ここでは開かない
//   - 仮の値のまま・Paddle.js を読めなかったときは、開かずに data-text-* の文を出す
//   - 閉じたら「購入画面を開く」で開き直せる。開けなかったときはそう知らせる。購入が済んだら、お礼と、キーがメールで届くことを出す
//   - 購入が済んだら、取引の ID で同じサイトの data-license-endpoint（Worker の /api/license。docs/release.md 3.2）にキーを聞き、
//     返ってきたらキー・コピーのボタン・「Nonet に登録する」（data-license-link + キー）を出す。まだ済んでいなければ少し待って聞き直す。
//     聞けない（設定していない・失敗した）ときは、メールで届くという案内のまま
// 文言は HTML（data-text-*）から読むので、日本語と英語のページで共通に使える。
// URL は書かない（scripts/check-site.sh が、このファイルに URL の文字列を書くことを禁じている。聞く先も HTML から読む）
(() => {
  "use strict";

  const box = document.querySelector("[data-checkout]");
  if (!box) return;
  const status = box.querySelector("[data-checkout-status]");
  const button = box.querySelector("[data-checkout-open]");
  const token = box.dataset.paddleToken || "";
  const price = box.dataset.paddlePrice || "";

  // data-text-unavailable などの文を出す
  const say = (key, target = status) => {
    const text = box.dataset[key];
    if (target && text) target.textContent = text;
  };

  // Paddle の形（クライアント用のトークンは live_ か test_ と 27 文字、価格の ID は pri_ と 26 文字）でなければ、仮の値のまま
  if (!/^(live|test)_[A-Za-z0-9]{27}$/.test(token) || !/^pri_[a-z0-9]{26}$/.test(price)) {
    say("textUnavailable");
    return;
  }
  // 拡張機能やネットワークで Paddle.js が止められた
  const paddle = window.Paddle;
  if (!paddle || typeof paddle.Initialize !== "function" || !paddle.Checkout) {
    say("textBlocked");
    return;
  }

  const transaction = new URLSearchParams(window.location.search).get("_ptxn");
  let completed = false;
  const open = () => {
    paddle.Checkout.open(transaction ? { transactionId: transaction } : { items: [{ priceId: price, quantity: 1 }] });
  };

  // MARK: 購入が済んだあと、キーを見せる

  // 取引の ID（txn_ と 26 文字）とライセンスキー（License.swift と同じ形）
  const TRANSACTION_ID = /^txn_[a-z0-9]{26}$/;
  const LICENSE_KEY = /^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{86}$/;
  // 支払いの直後は、Paddle が取引を済ませるまで数秒かかる。聞き直すまでの間（ミリ秒）。合わせて20秒ほどで諦める
  const RETRY_DELAYS = [1000, 2000, 3000, 5000, 8000];
  const delivery = box.querySelector("[data-license]");
  const endpoint = box.dataset.licenseEndpoint || "";
  const registerLink = box.dataset.licenseLink || "";

  const showLicense = (key, transactionId) => {
    const field = delivery.querySelector("[data-license-key]");
    const id = delivery.querySelector("[data-license-id]");
    const register = delivery.querySelector("[data-license-open]");
    const copy = delivery.querySelector("[data-license-copy]");
    const copyStatus = delivery.querySelector("[data-license-copy-status]");
    if (field) field.textContent = key;
    if (id) id.textContent = transactionId;
    if (register) {
      if (registerLink) register.href = registerLink + key;
      else register.hidden = true;
    }
    if (copy) {
      copy.addEventListener("click", () => {
        const clipboard = window.navigator && window.navigator.clipboard;
        if (!clipboard || typeof clipboard.writeText !== "function") {
          say("textCopyFailed", copyStatus);
          return;
        }
        clipboard.writeText(key).then(() => say("textCopied", copyStatus), () => say("textCopyFailed", copyStatus));
      });
    }
    delivery.hidden = false;
    say("textDelivered");
  };

  // 同じサイトの聞く先だけに聞く（/ で始まり、// ではないもの）。fetch が無い古いブラウザでは聞かない
  const requestLicense = (transactionId) => {
    if (!delivery || !/^\/(?!\/)/.test(endpoint) || typeof window.fetch !== "function" || !TRANSACTION_ID.test(transactionId || "")) return;
    let attempt = 0;
    const retry = () => {
      if (attempt < RETRY_DELAYS.length) window.setTimeout(ask, RETRY_DELAYS[attempt++]);
    };
    const ask = () => {
      window
        .fetch(`${endpoint}?transaction_id=${transactionId}`, { headers: { accept: "application/json" }, cache: "no-store", credentials: "same-origin" })
        .then((response) => {
          // 409: まだ済んでいない。502・504 など: 一時的な失敗。どちらも聞き直す。
          // 400・404・503（設定していない）: 聞き直しても変わらないので、メールで届くという案内のまま
          if (!response.ok) {
            if (response.status === 409 || (response.status >= 500 && response.status !== 503)) retry();
            return;
          }
          return response.json().then((result) => {
            const key = result && result.license_key;
            if (typeof key === "string" && LICENSE_KEY.test(key) && result.license_id === transactionId) showLicense(key, transactionId);
          });
        })
        .catch(retry);
    };
    ask();
  };

  try {
    if (token.startsWith("test_")) paddle.Environment.set("sandbox");
    paddle.Initialize({
      token,
      // 言語はブラウザの言語（Paddle.js の既定）。アプリはどの言語でも日本語のページ（NONET_PURCHASE_URL）を開くため
      checkout: { settings: { displayMode: "overlay" } },
      eventCallback: (event) => {
        switch (event && event.name) {
          case "checkout.completed":
            if (completed) break;
            completed = true;
            say("textCompleted");
            if (button) button.hidden = true;
            requestLicense(event.data && event.data.transaction_id);
            break;
          case "checkout.closed":
            if (!completed) say("textClosed");
            break;
          // 購入画面そのものを開けなかった（トークン・価格の ID・ドメインの承認など）。カードが通らなかったとき（checkout.payment.error）は、
          // 購入画面の中で直せるので、ここでは何も言わない
          case "checkout.error":
            if (!completed) say("textError");
            break;
        }
      },
    });
  } catch (error) {
    say("textBlocked");
    return;
  }

  if (button) {
    button.hidden = false;
    button.addEventListener("click", open);
  }
  if (!transaction) open();
})();

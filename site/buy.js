// 購入のページ（buy.html・en/buy.html）のスクリプト。先に読み込んだ Paddle.js で、購入画面（オーバーレイ）を開く。
//   - トークンと価格の ID は HTML の data-paddle-token・data-paddle-price から読む。test_ のトークンなら sandbox で開く
//   - ?_ptxn=… で開かれたとき（Paddle の Default payment link）は、その取引の購入画面を Paddle.js が自分で開くので、ここでは開かない
//   - 仮の値のまま・Paddle.js を読めなかったときは、開かずに data-text-* の文を出す
//   - 閉じたら「購入画面を開く」で開き直せる。開けなかったときはそう知らせる。購入が済んだら、お礼と、キーがメールで届くことを出す
// 文言は HTML（data-text-*）から読むので、日本語と英語のページで共通に使える。
// URL は書かない（scripts/check-site.sh が、このファイルに URL の文字列を書くことを禁じている）
(() => {
  "use strict";

  const box = document.querySelector("[data-checkout]");
  if (!box) return;
  const status = box.querySelector("[data-checkout-status]");
  const button = box.querySelector("[data-checkout-open]");
  const token = box.dataset.paddleToken || "";
  const price = box.dataset.paddlePrice || "";

  // data-text-unavailable などの文を出す
  const say = (key) => {
    const text = box.dataset[key];
    if (status && text) status.textContent = text;
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

  try {
    if (token.startsWith("test_")) paddle.Environment.set("sandbox");
    paddle.Initialize({
      token,
      // 言語はブラウザの言語（Paddle.js の既定）。アプリはどの言語でも日本語のページ（NONET_PURCHASE_URL）を開くため
      checkout: { settings: { displayMode: "overlay" } },
      eventCallback: (event) => {
        switch (event && event.name) {
          case "checkout.completed":
            completed = true;
            say("textCompleted");
            if (button) button.hidden = true;
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

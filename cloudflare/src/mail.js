// メールを送る。送り方は小さな形（send(message)）にまとめ、いまは Resend の HTTPS の API だけを実装する
// （別のサービスにするときは、同じ形の mailer を作って createMailer で選ぶ）。
// 差出人は Nonet <support@astlog.dev>、返信先も support@astlog.dev（Cloudflare Email Routing で開発者に届く）。
// 文面は docs/release.md 3.1 の例と同じ（日本語のあとに英語）。

export const MAIL_FROM = "Nonet <support@astlog.dev>";
export const SUPPORT_ADDRESS = "support@astlog.dev";
const RESEND_ENDPOINT = "https://api.resend.com/emails";
const MAIL_TIMEOUT_MS = 8000;

// retryable: 時間をおけば通るかもしれない（Paddle に送り直してもらう）。どちらにしても通知には 2xx 以外を返す
export class MailError extends Error {
  constructor(message, { retryable = true } = {}) {
    super(message);
    this.retryable = retryable;
  }
}

// env の RESEND_API_KEY で送る mailer。無ければ null（licensing.js が 503 にする）
export function createMailer(env, fetchImpl = (...args) => fetch(...args)) {
  const apiKey = env.RESEND_API_KEY;
  if (typeof apiKey !== "string" || apiKey.trim() === "") {
    return null;
  }
  return resendMailer(apiKey.trim(), fetchImpl);
}

// message: { to, subject, text, html, idempotencyKey }。
// idempotencyKey が同じ送信は、Resend が 24 時間のうちは1通にまとめる（Paddle が通知を送り直しても、二重に届きにくい）
export function resendMailer(apiKey, fetchImpl) {
  return {
    async send({ to, subject, text, html, idempotencyKey }) {
      const headers = { authorization: `Bearer ${apiKey}`, "content-type": "application/json" };
      if (idempotencyKey) {
        headers["idempotency-key"] = idempotencyKey;
      }
      let response;
      try {
        response = await fetchImpl(RESEND_ENDPOINT, {
          method: "POST",
          headers,
          body: JSON.stringify({ from: MAIL_FROM, to: [to], reply_to: SUPPORT_ADDRESS, subject, text, html }),
          signal: AbortSignal.timeout(MAIL_TIMEOUT_MS),
        });
      } catch (error) {
        throw new MailError(`Resend に届きません: ${error.message}`);
      }
      if (response.ok) {
        const body = await response.json().catch(() => ({}));
        return { id: typeof body?.id === "string" ? body.id : null, duplicate: false };
      }
      const body = await response.json().catch(() => ({}));
      const name = typeof body?.name === "string" ? body.name : "";
      // 同じ idempotencyKey で中身の違う送信（顧客の名前が変わった、など）。24 時間のうちに一度は送ってある
      if (response.status === 409 && name === "invalid_idempotent_request") {
        return { id: null, duplicate: true };
      }
      const retryable = response.status === 409 || response.status === 429 || response.status >= 500;
      throw new MailError(`Resend が ${response.status} を返しました${name ? `（${name}）` : ""}`, { retryable });
    },
  };
}

// 購入者に送るライセンスキーのメール
export function licenseEmail({ key, licenseID }) {
  const link = `nonet://register?key=${key}`;
  const subject = "Nonet のライセンスキー / Your Nonet license key";
  const text = `Nonet をご購入いただきありがとうございます。

Nonet を入れた Mac で、次のリンクを開くと登録できます。

Nonet に登録する: ${link}

リンクを開けないときは、メニューバーの Nonet のアイコンから「ライセンスキーを入力…」を選び、次のライセンスキーを貼り付けて「登録」を押してください。

ライセンスキー:
${key}

ライセンス ID: ${licenseID}（問い合わせのときにお知らせください。登録には使えません）

1つのライセンスで、あなたが使うすべての Mac に使えます。キーはこの Mac の中だけで確認され、ネットワークには送られません。

----

Thank you for buying Nonet.

On a Mac with Nonet installed, open this link to register:

Register in Nonet: ${link}

If the link doesn't open, choose "Enter License Key…" from the Nonet icon in the menu bar, paste the license key below, and click "Register".

License key:
${key}

License ID: ${licenseID} (mention it when you contact us; it can't be used to register)

One license covers every Mac you use. The key is verified on your Mac only and is never sent over the network.

----
Nonet https://nonet.astlog.dev/
${SUPPORT_ADDRESS}（このメールに返信できます / You can reply to this email）
`;
  const html = `<!doctype html>
<html><head><meta charset="utf-8"><title>${escapeHtml(subject)}</title></head>
<body>
<div lang="ja">
<p>Nonet をご購入いただきありがとうございます。</p>
<p>Nonet を入れた Mac で、次のリンクを開くと登録できます。</p>
<p><a href="${escapeHtml(link)}">Nonet に登録する</a></p>
<p>リンクを開けないときは、メニューバーの Nonet のアイコンから「ライセンスキーを入力…」を選び、次のライセンスキーを貼り付けて「登録」を押してください。</p>
<p>ライセンスキー:<br><code>${escapeHtml(key)}</code></p>
<p>ライセンス ID: ${escapeHtml(licenseID)}（問い合わせのときにお知らせください。登録には使えません）</p>
<p>1つのライセンスで、あなたが使うすべての Mac に使えます。キーはこの Mac の中だけで確認され、ネットワークには送られません。</p>
</div>
<hr>
<div lang="en">
<p>Thank you for buying Nonet.</p>
<p>On a Mac with Nonet installed, open this link to register:</p>
<p><a href="${escapeHtml(link)}">Register in Nonet</a></p>
<p>If the link doesn't open, choose “Enter License Key…” from the Nonet icon in the menu bar, paste the license key below, and click “Register”.</p>
<p>License key:<br><code>${escapeHtml(key)}</code></p>
<p>License ID: ${escapeHtml(licenseID)} (mention it when you contact us; it can't be used to register)</p>
<p>One license covers every Mac you use. The key is verified on your Mac only and is never sent over the network.</p>
</div>
<hr>
<p><a href="https://nonet.astlog.dev/">Nonet</a> · ${SUPPORT_ADDRESS}（このメールに返信できます / You can reply to this email）</p>
</body></html>
`;
  return { subject, text, html };
}

// 返金・チャージバックが承認されたときに、開発者に送る知らせ（キーを無効にし忘れないように。docs/release.md 3.5）
export function revocationReminderEmail({ transactionID, adjustmentID, action, type }) {
  const subject = `[Nonet] ${action === "chargeback" ? "チャージバック" : "返金"}: ${transactionID} を無効にする`;
  const text = `Paddle で ${action}（${type || "種類は不明"}）が承認されました。

取引（ライセンス ID）: ${transactionID}
調整: ${adjustmentID}

全額の返金・チャージバックなら、ライセンスを無効にして、次のリリースに入れてください（docs/release.md 3.5）:

  cd Packages/NonetKit
  swift run nonet-license revoke ${transactionID}

一部だけの返金で、キーを使い続けてもらうときは何もしなくてよい。
`;
  return { subject, text, html: `<!doctype html><html><head><meta charset="utf-8"></head><body><pre>${escapeHtml(text)}</pre></body></html>` };
}

export function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]);
}

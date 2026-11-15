// Paddle Billing: 通知（Webhook）の署名の確かめ方と、取引・顧客を読む API。
// 署名と API の決まりは developer.paddle.com（Webhooks › Signature verification・API reference）による（2026-11-15 に確かめた）。

// 取引の ID（txn_ と 26 文字）。ライセンス ID にもそのまま使う（docs/release.md 3.2）
export const TRANSACTION_ID_PATTERN = /^txn_[a-z0-9]{26}$/;
export const PRICE_ID_PATTERN = /^pri_[a-z0-9]{26}$/;
// 署名の時刻のずれの許容（秒）。Paddle の SDK と資料の既定と同じ
export const SIGNATURE_TOLERANCE_SECONDS = 5;
// 1回の API の呼び出しを待つ上限。Paddle は通知の応答が遅いと失敗として送り直す
const API_TIMEOUT_MS = 8000;

export class PaddleApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

// API キーの種類で、本番か sandbox かを決める（sandbox のキーは sandbox の URL でしか使えない）。どちらでもなければ null
export function paddleApiBase(apiKey) {
  if (typeof apiKey !== "string") {
    return null;
  }
  if (apiKey.startsWith("pdl_live_")) {
    return "https://api.paddle.com";
  }
  if (apiKey.startsWith("pdl_sdbx_")) {
    return "https://sandbox-api.paddle.com";
  }
  return null;
}

// Paddle-Signature: ts=<UNIX 時刻>;h1=<16進>。秘密を入れ替えている間は h1 が2つ以上来ることがある。読めなければ null
export function parseSignatureHeader(header) {
  if (typeof header !== "string" || header.length > 1024) {
    return null;
  }
  let timestamp = null;
  const signatures = [];
  for (const part of header.split(";")) {
    const equals = part.indexOf("=");
    if (equals < 0) {
      continue;
    }
    const name = part.slice(0, equals).trim();
    const value = part.slice(equals + 1).trim();
    if (name === "ts" && /^\d{1,12}$/.test(value)) {
      timestamp = Number(value);
    } else if (name === "h1" && /^[0-9a-f]{64}$/i.test(value)) {
      signatures.push(value.toLowerCase());
    }
  }
  return timestamp === null || signatures.length === 0 ? null : { timestamp, signatures };
}

// 本文は受け取ったまま（解釈し直さない）の文字列。`${ts}:${本文}` を、通知先の秘密（pdl_ntfset_…）で HMAC-SHA256 したものと比べる。
// 比べるのは crypto.subtle.verify（かかる時間が中身によらない比べ方）。
// 返すのは { ok: true } か { ok: false, reason }（reason はログ用。応答には書かない）
export async function verifyPaddleSignature(header, rawBody, secret, nowSeconds, toleranceSeconds = SIGNATURE_TOLERANCE_SECONDS) {
  const parsed = parseSignatureHeader(header);
  if (parsed === null) {
    return { ok: false, reason: "Paddle-Signature が無いか、読めません" };
  }
  if (Math.abs(nowSeconds - parsed.timestamp) > toleranceSeconds) {
    return { ok: false, reason: `Paddle-Signature の時刻が ${toleranceSeconds} 秒より大きくずれています（ts=${parsed.timestamp}）` };
  }
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  const signed = encoder.encode(`${parsed.timestamp}:${rawBody}`);
  for (const signature of parsed.signatures) {
    if (await crypto.subtle.verify("HMAC", key, hexBytes(signature), signed)) {
      return { ok: true };
    }
  }
  return { ok: false, reason: "Paddle-Signature の署名が一致しません" };
}

function hexBytes(hex) {
  const bytes = new Uint8Array(hex.length / 2);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

// 取引の明細に、この価格の ID があるか（items[].price.id。念のため items[].price_id も見る）
export function transactionHasPrice(transaction, priceId) {
  const items = Array.isArray(transaction?.items) ? transaction.items : [];
  return items.some((item) => item?.price?.id === priceId || item?.price_id === priceId);
}

export class PaddleClient {
  constructor(apiKey, fetchImpl = (...args) => fetch(...args)) {
    this.apiKey = apiKey;
    this.base = paddleApiBase(apiKey);
    this.fetch = fetchImpl;
  }

  // 取引（顧客を含める）。無ければ null。顧客が含まれていなければ（include が効かなかった）、顧客を別に引く
  async transactionWithCustomer(transactionId) {
    const transaction = await this.get(`/transactions/${transactionId}?include=customer`);
    if (transaction === null) {
      return null;
    }
    if (!transaction.customer && typeof transaction.customer_id === "string" && /^ctm_[a-z0-9]+$/.test(transaction.customer_id)) {
      transaction.customer = await this.get(`/customers/${transaction.customer_id}`);
    }
    return transaction;
  }

  // GET して data を返す。404 は null。ほかの失敗は PaddleApiError（status はログと、送り直すかの判断に使う）
  async get(path) {
    let response;
    try {
      response = await this.fetch(`${this.base}${path}`, {
        headers: { authorization: `Bearer ${this.apiKey}`, accept: "application/json", "paddle-version": "1" },
        signal: AbortSignal.timeout(API_TIMEOUT_MS),
      });
    } catch (error) {
      throw new PaddleApiError(`Paddle の API に届きません（${path.split("?")[0]}）: ${error.message}`, 0);
    }
    if (response.status === 404) {
      return null;
    }
    if (!response.ok) {
      // 本文の error.code（forbidden・authentication_malformed など）だけをログに残す
      const code = await response.json().then((body) => body?.error?.code, () => undefined);
      throw new PaddleApiError(`Paddle の API が ${response.status} を返しました（${path.split("?")[0]}${code ? `、${code}` : ""}）`, response.status);
    }
    const body = await response.json().catch(() => null);
    if (body === null || typeof body.data !== "object" || body.data === null) {
      throw new PaddleApiError(`Paddle の API の応答を読めません（${path.split("?")[0]}）`, response.status);
    }
    return body.data;
  }
}

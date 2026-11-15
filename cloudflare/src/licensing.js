// ライセンスキーを自動で届ける（docs/release.md 3.2）。
//   POST /api/paddle/webhook  Paddle の通知。transaction.completed でキーを作って購入者にメールで送り、
//                             返金・チャージバックの承認（adjustment.created・adjustment.updated）で開発者に知らせる
//   GET  /api/license?transaction_id=txn_…  購入のページ（buy.js）が、購入が済んだ直後にキーを見せるために使う
// キーのライセンス ID は Paddle の取引の ID（txn_…）。発行日時は取引の billed_at（無ければ created_at）。
// Ed25519 の署名は決まった値になるので、同じ取引からは何度作っても同じキーになる。何も保存しない。
// GET は、推測できない取引の ID を知っている人なら、その購入者のキーを取れる（ID を知っているのは購入者と Paddle と開発者だけ）。
//
// 設定（秘密は wrangler secret put、ほかは wrangler.toml の [vars]）が1つでも欠けていれば、どちらも 503 を返して何もしない。
// ページとアップデートの配布は、設定が無くても今までどおり動く。
//   PADDLE_API_KEY              秘密。transaction.read と customer.read だけの API キー。pdl_live_ なら本番、pdl_sdbx_ なら sandbox
//   PADDLE_NOTIFICATION_SECRET  秘密。通知先の秘密（pdl_ntfset_…）。Webhook だけが使う
//   LICENSE_PRIVATE_KEY         秘密。nonet-license keygen の秘密鍵（ファイルの中身の base64）
//   RESEND_API_KEY              秘密。Resend の API キー（送信だけの権限）。Webhook だけが使う
//   LICENSE_PUBLIC_KEY          [vars]。アプリに入れる公開鍵（Config/Nonet.xcconfig の NONET_LICENSE_PUBLIC_KEY と同じ）
//   PADDLE_PRICE_ID             [vars]。Nonet の価格の ID（site/buy.html の data-paddle-price と同じ）。ほかの商品の取引には何もしない

import { FILE_SECURITY_HEADERS, textResponse } from "./http.js";
import { importPrivateKey, importPublicKey, issueLicenseKey, licenseInfo, LicenseError } from "./license.js";
import { createMailer, licenseEmail, MailError, revocationReminderEmail, SUPPORT_ADDRESS } from "./mail.js";
import {
  PaddleApiError,
  PaddleClient,
  paddleApiBase,
  PRICE_ID_PATTERN,
  TRANSACTION_ID_PATTERN,
  transactionHasPrice,
  verifyPaddleSignature,
} from "./paddle.js";

export const WEBHOOK_PATH = "/api/paddle/webhook";
export const LICENSE_PATH = "/api/license";
// Paddle の通知の本文はふつう数 KB。桁違いに大きければ読まない
export const MAX_WEBHOOK_BYTES = 256 * 1024;

const LOOKUP_SETTINGS = ["PADDLE_API_KEY", "LICENSE_PRIVATE_KEY", "LICENSE_PUBLIC_KEY", "PADDLE_PRICE_ID"];
const WEBHOOK_SETTINGS = [...LOOKUP_SETTINGS, "PADDLE_NOTIFICATION_SECRET", "RESEND_API_KEY"];
// 返金の知らせを送る調整（adjustment）の種類
const REVOKING_ACTIONS = new Set(["refund", "chargeback"]);

// wrangler.toml の run_worker_first の "/api/*"
export function isLicensingPath(pathname) {
  return pathname.startsWith("/api/");
}

export async function handleLicensing(request, env, pathname) {
  if (pathname === WEBHOOK_PATH) {
    return handleWebhook(request, env);
  }
  if (pathname === LICENSE_PATH) {
    return handleLookup(request, env);
  }
  return textResponse(404, "Not Found");
}

// MARK: - 設定

class NotConfigured extends Error {}

// 足りない設定の名前（値はログに出さない）
export function missingSettings(env, names) {
  return names.filter((name) => typeof env[name] !== "string" || env[name].trim() === "");
}

async function loadSettings(env, names) {
  const missing = missingSettings(env, names);
  if (missing.length > 0) {
    throw new NotConfigured(`設定がありません: ${missing.join(", ")}`);
  }
  const apiKey = env.PADDLE_API_KEY.trim();
  if (paddleApiBase(apiKey) === null) {
    throw new NotConfigured("PADDLE_API_KEY が pdl_live_ でも pdl_sdbx_ でもありません");
  }
  const priceId = env.PADDLE_PRICE_ID.trim();
  if (!PRICE_ID_PATTERN.test(priceId)) {
    throw new NotConfigured("PADDLE_PRICE_ID が価格の ID（pri_ と 26 文字）ではありません");
  }
  let privateKey;
  let publicKey;
  try {
    privateKey = await importPrivateKey(env.LICENSE_PRIVATE_KEY);
    publicKey = await importPublicKey(env.LICENSE_PUBLIC_KEY);
  } catch (error) {
    throw new NotConfigured(`ライセンスの鍵を読めません: ${error.message}`);
  }
  // 秘密鍵がアプリの公開鍵と対でなければ、Paddle に問い合わせる前に止める（キーを作るときにも、もう一度確かめる）
  if (!(await keysMatch(privateKey, publicKey))) {
    throw new NotConfigured("LICENSE_PRIVATE_KEY が LICENSE_PUBLIC_KEY（アプリに入れる公開鍵）と対応していません");
  }
  const settings = { paddle: new PaddleClient(apiKey), priceId, keys: { privateKey, publicKey } };
  if (names.includes("RESEND_API_KEY")) {
    settings.mailer = createMailer(env);
    settings.notificationSecret = env.PADDLE_NOTIFICATION_SECRET.trim();
  }
  return settings;
}

async function keysMatch(privateKey, publicKey) {
  const probe = new TextEncoder().encode("nonet-license-key-pair");
  const signature = await crypto.subtle.sign({ name: "Ed25519" }, privateKey, probe);
  return crypto.subtle.verify({ name: "Ed25519" }, publicKey, signature, probe);
}

// MARK: - キー

// 取引（API で読んだもの。顧客を含む）から、キーとライセンスの中身を作る。キーは取引だけで決まる
async function licenseFor(transaction, keys) {
  const customer = transaction.customer ?? {};
  const info = licenseInfo({
    licenseID: transaction.id,
    licensee: customer.name,
    email: customer.email,
    issuedAt: transaction.billed_at ?? transaction.created_at,
  });
  return { info, key: await issueLicenseKey(info, keys) };
}

// API で取引を読み、Nonet の済んだ取引ならそれを返す。
// { transaction } か { outcome: "not_found" | "other_product" | "not_completed" }
async function completedNonetTransaction(settings, transactionId) {
  const transaction = await settings.paddle.transactionWithCustomer(transactionId);
  if (transaction === null || transaction.id !== transactionId) {
    return { outcome: "not_found" };
  }
  if (!transactionHasPrice(transaction, settings.priceId)) {
    return { outcome: "other_product" };
  }
  if (transaction.status !== "completed") {
    return { outcome: "not_completed", status: transaction.status };
  }
  return { transaction };
}

// MARK: - GET /api/license

async function handleLookup(request, env) {
  if (request.method !== "GET") {
    return jsonResponse(405, { error: "method_not_allowed" }, { allow: "GET" });
  }
  const transactionId = new URL(request.url).searchParams.get("transaction_id") ?? "";
  if (!TRANSACTION_ID_PATTERN.test(transactionId)) {
    return jsonResponse(400, { error: "invalid_transaction_id" });
  }
  let settings;
  try {
    settings = await loadSettings(env, LOOKUP_SETTINGS);
  } catch (error) {
    return unavailable(LICENSE_PATH, error);
  }
  try {
    const found = await completedNonetTransaction(settings, transactionId);
    switch (found.outcome) {
      case "not_found":
      case "other_product":
        return jsonResponse(404, { error: "not_found" });
      case "not_completed":
        // 支払いの直後（paid）は、Paddle が数秒で completed にする。buy.js は少し待って聞き直す
        if (["draft", "ready", "billed", "paid"].includes(found.status)) {
          return jsonResponse(409, { error: "not_completed" }, { "retry-after": "2" });
        }
        return jsonResponse(404, { error: "not_found" });
    }
    const { info, key } = await licenseFor(found.transaction, settings.keys);
    return jsonResponse(200, { license_key: key, license_id: info.licenseID });
  } catch (error) {
    return failed(LICENSE_PATH, error);
  }
}

// MARK: - POST /api/paddle/webhook

async function handleWebhook(request, env) {
  if (request.method !== "POST") {
    return textResponse(405, "Method Not Allowed", { allow: "POST" });
  }
  let settings;
  try {
    settings = await loadSettings(env, WEBHOOK_SETTINGS);
  } catch (error) {
    return unavailable(WEBHOOK_PATH, error);
  }
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > MAX_WEBHOOK_BYTES) {
    return textResponse(413, "Payload Too Large");
  }
  // 署名は受け取ったままの本文で確かめる（JSON として読み直したものではない）
  const rawBody = await request.text();
  if (new TextEncoder().encode(rawBody).length > MAX_WEBHOOK_BYTES) {
    return textResponse(413, "Payload Too Large");
  }
  const verified = await verifyPaddleSignature(
    request.headers.get("paddle-signature"),
    rawBody,
    settings.notificationSecret,
    Math.floor(Date.now() / 1000),
  );
  if (!verified.ok) {
    console.error(`${WEBHOOK_PATH}: ${verified.reason}`);
    return textResponse(401, "Unauthorized");
  }
  let notification;
  try {
    notification = JSON.parse(rawBody);
  } catch {
    console.error(`${WEBHOOK_PATH}: 署名は合っているが、本文が JSON ではありません`);
    return textResponse(400, "Bad Request");
  }
  try {
    switch (notification?.event_type) {
      case "transaction.completed":
        return await deliverLicense(notification, settings);
      case "adjustment.created":
      case "adjustment.updated":
        return await remindToRevoke(notification, settings);
      default:
        return ignored(notification, "受け持たない種類の通知");
    }
  } catch (error) {
    return failed(WEBHOOK_PATH, error, notification);
  }
}

async function deliverLicense(notification, settings) {
  const data = notification.data ?? {};
  if (!TRANSACTION_ID_PATTERN.test(data.id ?? "")) {
    return ignored(notification, "取引の ID がありません");
  }
  // 通知の中身でほかの商品だと分かれば、API を呼ばずに終える。最後は API で読んだ取引で決める
  if (!transactionHasPrice(data, settings.priceId)) {
    return ignored(notification, "Nonet の価格の取引ではありません");
  }
  const found = await completedNonetTransaction(settings, data.id);
  if (found.outcome === "not_found" || found.outcome === "other_product") {
    return ignored(notification, found.outcome === "not_found" ? "API で取引が見つかりません" : "Nonet の価格の取引ではありません");
  }
  if (found.outcome === "not_completed") {
    // 通知は completed なのに API ではまだ。少し後で送り直してもらう
    console.error(`${WEBHOOK_PATH}: ${data.id} は API ではまだ ${found.status} です（送り直しを待つ）`);
    return textResponse(503, "Service Unavailable", { "retry-after": "60" });
  }
  const { info, key } = await licenseFor(found.transaction, settings.keys);
  const message = licenseEmail({ key, licenseID: info.licenseID });
  // 同じ取引のメールは、Paddle が送り直しても Resend が 24 時間のうちは1通にまとめる
  const sent = await settings.mailer.send({ to: info.email, ...message, idempotencyKey: `nonet-license/${info.licenseID}` });
  console.log(`${WEBHOOK_PATH}: ${info.licenseID} のライセンスキーを送りました${sent.duplicate ? "（24 時間のうちに送ったものと同じ取引）" : ""}`);
  return textResponse(200, "OK");
}

async function remindToRevoke(notification, settings) {
  const adjustment = notification.data ?? {};
  if (!REVOKING_ACTIONS.has(adjustment.action) || adjustment.status !== "approved") {
    return ignored(notification, `承認された返金・チャージバックではありません（${adjustment.action}・${adjustment.status}）`);
  }
  if (!TRANSACTION_ID_PATTERN.test(adjustment.transaction_id ?? "") || typeof adjustment.id !== "string") {
    return ignored(notification, "取引か調整の ID がありません");
  }
  // 調整には価格が無いので、取引を読んで Nonet のものかを確かめる
  const transaction = await settings.paddle.get(`/transactions/${adjustment.transaction_id}`);
  if (transaction === null || !transactionHasPrice(transaction, settings.priceId)) {
    return ignored(notification, "Nonet の価格の取引ではありません");
  }
  const message = revocationReminderEmail({
    transactionID: adjustment.transaction_id,
    adjustmentID: adjustment.id,
    action: adjustment.action,
    type: adjustment.type,
  });
  await settings.mailer.send({ to: SUPPORT_ADDRESS, ...message, idempotencyKey: `nonet-revoke/${adjustment.id}` });
  console.log(`${WEBHOOK_PATH}: ${adjustment.transaction_id} の${adjustment.action}を開発者に知らせました`);
  return textResponse(200, "OK");
}

// MARK: - 応答

// 受け持たない通知にも 2xx を返す（返さないと Paddle が送り直し続ける）
function ignored(notification, reason) {
  console.log(`${WEBHOOK_PATH}: ${notification?.event_type ?? "（種類なし）"}（${notification?.notification_id ?? "-"}）は何もしません: ${reason}`);
  return textResponse(200, "Ignored");
}

// 設定が無い・正しくない。Workers Logs（ダッシュボードの Workers › nonet › Logs）に理由を残す
function unavailable(path, error) {
  console.error(`${path}: ${error.message}`);
  if (path === LICENSE_PATH) {
    return jsonResponse(503, { error: "unavailable" });
  }
  return textResponse(503, "Service Unavailable");
}

// Paddle の API かメールの失敗。2xx 以外を返すので、Paddle は通知を送り直す（そのぶん、メールが二重に届くことがある）
function failed(path, error, notification) {
  const known = error instanceof PaddleApiError || error instanceof MailError || error instanceof LicenseError || error instanceof NotConfigured;
  const id = notification?.notification_id ? `（${notification.notification_id}）` : "";
  console.error(`${path}${id}: ${known ? error.message : `思わぬ失敗: ${error?.stack ?? error}`}`);
  if (path === LICENSE_PATH) {
    return jsonResponse(502, { error: "upstream" });
  }
  return textResponse(error instanceof LicenseError ? 500 : 502, error instanceof LicenseError ? "Internal Server Error" : "Bad Gateway");
}

function jsonResponse(status, body, extraHeaders = {}) {
  return new Response(`${JSON.stringify(body)}\n`, {
    status,
    headers: {
      ...FILE_SECURITY_HEADERS,
      "content-type": "application/json; charset=utf-8",
      // キーを写させない（ブラウザにも途中のキャッシュにも）
      "cache-control": "no-store",
      "x-robots-tag": "noindex",
      ...extraHeaders,
    },
  });
}

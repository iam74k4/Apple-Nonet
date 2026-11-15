// ライセンスキーを届ける: Paddle の通知（/api/paddle/webhook）と購入のページ（/api/license）、キーの形（src/licensing.js・license.js・paddle.js・mail.js）。
// Paddle の API と Resend は、globalThis.fetch を偽物に差し替えて答える（ネットワークには出ない）
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, test } from "node:test";

import {
  decodeKeyMaterial,
  decodeLicenseKey,
  encodeLicenseInfo,
  importPrivateKey,
  importPublicKey,
  issueLicenseKey,
  LICENSE_KEY_PATTERN,
  licenseInfo,
  secondsTimestamp,
  signLicense,
  verifyLicense,
} from "../src/license.js";
import { licenseEmail } from "../src/mail.js";
import { paddleApiBase, parseSignatureHeader, verifyPaddleSignature } from "../src/paddle.js";
import { call, makeEnv, SITE_DIR } from "./support.js";

const ROOT = join(SITE_DIR, "..");
const TXN = "txn_01jc0aaaaaaaaaaaaaaaaaaaaa";
const OTHER_TXN = "txn_01jc0bbbbbbbbbbbbbbbbbbbbb";
const PRICE = "pri_01m7eed1e4msh3ebqy6qavp81p";
const OTHER_PRICE = "pri_01aaaaaaaaaaaaaaaaaaaaaaaa";
const CUSTOMER = "ctm_01jc0cccccccccccccccccccc";
const SECRET = "pdl_ntfset_01jc0dddddddddddddddddddd_testsecret";
// RFC 8032 の Ed25519 のテストベクタ 1（秘密鍵の種・公開鍵・空のメッセージの署名）
const RFC8032 = {
  seed: "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
  publicKey: "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
  signature:
    "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
};
const PRIVATE_KEY = Buffer.from(RFC8032.seed, "hex").toString("base64");
const PUBLIC_KEY = Buffer.from(RFC8032.publicKey, "hex").toString("base64");

let errors;
let logs;
let fetchCalls;
let routes;
const originalFetch = globalThis.fetch;
const originalError = console.error;
const originalLog = console.log;

beforeEach(() => {
  errors = [];
  logs = [];
  fetchCalls = [];
  routes = defaultRoutes();
  console.error = (...args) => errors.push(args.join(" "));
  console.log = (...args) => logs.push(args.join(" "));
  globalThis.fetch = async (input, init = {}) => {
    const url = typeof input === "string" ? input : input.url;
    const headers = new Headers(init.headers ?? {});
    const call = { url, method: init.method ?? "GET", headers, body: init.body ?? null };
    fetchCalls.push(call);
    const handler = routes.find(([pattern]) => (typeof pattern === "string" ? url === pattern : pattern.test(url)));
    if (handler === undefined) {
      throw new Error(`テストの外への通信: ${url}`);
    }
    return handler[1](call);
  };
});
afterEach(() => {
  globalThis.fetch = originalFetch;
  console.error = originalError;
  console.log = originalLog;
});

function json(status, body) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

function transaction(overrides = {}) {
  return {
    id: TXN,
    status: "completed",
    customer_id: CUSTOMER,
    created_at: "2026-11-15T03:04:00.123456Z",
    updated_at: "2026-11-15T03:04:09.999999Z",
    billed_at: "2026-11-15T03:04:05.738972Z",
    items: [{ price: { id: PRICE, product_id: "pro_01aaaaaaaaaaaaaaaaaaaaaaaa" }, quantity: 1 }],
    customer: { id: CUSTOMER, name: "山田 太郎", email: "taro@example.com" },
    ...overrides,
  };
}

let paddleTransaction;
let resendResponse;

function defaultRoutes() {
  paddleTransaction = transaction();
  resendResponse = () => json(200, { id: "email-1" });
  return [
    [/^https:\/\/(sandbox-)?api\.paddle\.com\/transactions\//, ({ url }) => {
      const id = new URL(url).pathname.split("/").pop();
      return paddleTransaction !== null && id === paddleTransaction.id ? json(200, { data: paddleTransaction, meta: {} }) : json(404, { error: { code: "not_found" } });
    }],
    [/^https:\/\/(sandbox-)?api\.paddle\.com\/customers\//, () => json(200, { data: { id: CUSTOMER, name: null, email: "buyer@example.com" } })],
    ["https://api.resend.com/emails", () => resendResponse()],
  ];
}

function licensingEnv(overrides = {}) {
  return {
    ...makeEnv(),
    PADDLE_API_KEY: "pdl_live_apikey_01jc0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    PADDLE_NOTIFICATION_SECRET: SECRET,
    LICENSE_PRIVATE_KEY: PRIVATE_KEY,
    LICENSE_PUBLIC_KEY: PUBLIC_KEY,
    PADDLE_PRICE_ID: PRICE,
    RESEND_API_KEY: "re_test_key",
    ...overrides,
  };
}

function signature(body, { secret = SECRET, ts = Math.floor(Date.now() / 1000) } = {}) {
  return `ts=${ts};h1=${createHmac("sha256", secret).update(`${ts}:${body}`).digest("hex")}`;
}

function notification(eventType, data) {
  return JSON.stringify({ event_id: "evt_01jc0fffffffffffffffffffff", event_type: eventType, occurred_at: "2026-11-15T03:04:06.000000Z", notification_id: "ntf_01jc0ggggggggggggggggggggg", data });
}

function postWebhook(env, body, { header = signature(body), headers = {} } = {}) {
  return call(env, "/api/paddle/webhook", { method: "POST", body, headers: { "content-type": "application/json", ...(header === null ? {} : { "paddle-signature": header }), ...headers } });
}

const mails = () => fetchCalls.filter(({ url }) => url === "https://api.resend.com/emails").map((call) => ({ ...JSON.parse(call.body), idempotencyKey: call.headers.get("idempotency-key") }));
const paddleCalls = () => fetchCalls.filter(({ url }) => url.includes("paddle.com"));

// MARK: - キーの形

describe("キーの形（nonet-license と同じ）", () => {
  test("秘密鍵（32 バイトの種）を PKCS#8 で読み、RFC 8032 のテストベクタと同じ署名になる", async () => {
    const privateKey = await importPrivateKey(PRIVATE_KEY);
    const signature = new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, privateKey, new Uint8Array()));
    assert.equal(Buffer.from(signature).toString("hex"), RFC8032.signature);
  });

  test("JSON はキーを並べ替え、/ をエスケープせず、日付は秒まで。email が無ければ項目ごと書かない", () => {
    const info = licenseInfo({ licenseID: TXN, licensee: "山田 / \"Taro\"", email: "a+b@example.com", issuedAt: "2026-11-15T03:04:05.999999Z" });
    assert.equal(
      encodeLicenseInfo(info),
      `{"edition":"standard","email":"a+b@example.com","issuedAt":"2026-11-15T03:04:05Z","licenseID":"${TXN}","licensee":"山田 / \\"Taro\\"","product":"com.iam74k4.Nonet"}`,
    );
    const withoutEmail = licenseInfo({ licenseID: TXN, licensee: "Taro", issuedAt: "2026-11-15T03:04:05Z" });
    assert.equal(encodeLicenseInfo(withoutEmail), `{"edition":"standard","issuedAt":"2026-11-15T03:04:05Z","licenseID":"${TXN}","licensee":"Taro","product":"com.iam74k4.Nonet"}`);
  });

  test("名前が無ければメールアドレスを登録者にし、制御文字は空白にする", () => {
    assert.equal(licenseInfo({ licenseID: TXN, licensee: null, email: " taro@example.com ", issuedAt: "2026-11-15T03:04:05Z" }).licensee, "taro@example.com");
    assert.equal(licenseInfo({ licenseID: TXN, licensee: "  ", email: "taro@example.com", issuedAt: "2026-11-15T03:04:05Z" }).licensee, "taro@example.com");
    assert.equal(licenseInfo({ licenseID: TXN, licensee: "Taro\nYamada\u2028", email: null, issuedAt: "2026-11-15T03:04:05Z" }).licensee, "Taro Yamada");
    assert.throws(() => licenseInfo({ licenseID: TXN, licensee: null, email: null, issuedAt: "2026-11-15T03:04:05Z" }));
    assert.throws(() => licenseInfo({ licenseID: TXN, licensee: "Taro", email: "not an email", issuedAt: "2026-11-15T03:04:05Z" }));
    assert.throws(() => licenseInfo({ licenseID: " ", licensee: "Taro", issuedAt: "2026-11-15T03:04:05Z" }));
  });

  test("発行日時は RFC 3339 を UTC の秒にそろえる（小数は切り捨て）", () => {
    assert.equal(secondsTimestamp("2026-11-15T03:04:05Z"), "2026-11-15T03:04:05Z");
    assert.equal(secondsTimestamp("2026-11-15T03:04:05.999999Z"), "2026-11-15T03:04:05Z");
    assert.equal(secondsTimestamp("2026-11-15T12:04:05.5+09:00"), "2026-11-15T03:04:05Z");
    for (const value of [null, "", "2026-11-15", "2026-11-15 03:04:05Z", "2026-13-45T99:00:00Z"]) {
      assert.throws(() => secondsTimestamp(value), String(value));
    }
  });

  test("同じ中身なら同じキー（Ed25519 は決まった値）。アプリの公開鍵で通り、中身を読み戻せる", async () => {
    const keys = { privateKey: await importPrivateKey(PRIVATE_KEY), publicKey: await importPublicKey(PUBLIC_KEY) };
    const info = licenseInfo({ licenseID: TXN, licensee: "Taro", email: "taro@example.com", issuedAt: "2026-11-15T03:04:05Z" });
    const key = await issueLicenseKey(info, keys);
    assert.match(key, LICENSE_KEY_PATTERN);
    assert.equal(await issueLicenseKey(info, keys), key);
    assert.equal(await verifyLicense(key, keys.publicKey), true);
    assert.deepEqual(decodeLicenseKey(key), JSON.parse(encodeLicenseInfo(info)));
    // 1文字でも変えると通らない
    const tampered = key.replace(/^eyJ./, (prefix) => `eyJ${prefix[3] === "A" ? "B" : "A"}`);
    assert.equal(await verifyLicense(tampered, keys.publicKey), false);
  });

  test("秘密鍵がアプリの公開鍵と対になっていなければ、キーを出さない", async () => {
    const other = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
    const otherPublic = Buffer.from(await crypto.subtle.exportKey("raw", other.publicKey)).toString("base64");
    const keys = { privateKey: await importPrivateKey(PRIVATE_KEY), publicKey: await importPublicKey(otherPublic) };
    const info = licenseInfo({ licenseID: TXN, licensee: "Taro", issuedAt: "2026-11-15T03:04:05Z" });
    await assert.rejects(issueLicenseKey(info, keys), /対応していません/);
  });

  test("鍵の base64 は nonet-license と同じく、base64url・空白・改行も読み、32 バイトでなければ断る", () => {
    const urlSafe = PRIVATE_KEY.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    assert.deepEqual(decodeKeyMaterial(`${urlSafe.slice(0, 10)}\n ${urlSafe.slice(10)}\n`), decodeKeyMaterial(PRIVATE_KEY));
    for (const value of [undefined, "", "abc", Buffer.alloc(31).toString("base64"), Buffer.alloc(33).toString("base64"), "!!!!"]) {
      assert.equal(decodeKeyMaterial(value), null, String(value));
    }
  });

  test("メールの文面に、登録のリンク・キー・ライセンス ID・すべての Mac・Mac の中だけで確かめることを、日本語と英語で書く", () => {
    const key = `eyJ${"a".repeat(40)}.${"b".repeat(86)}`;
    const { subject, text, html } = licenseEmail({ key, licenseID: TXN });
    assert.match(subject, /Nonet/);
    for (const part of [`nonet://register?key=${key}`, `ライセンスキー:\n${key}`, `ライセンス ID: ${TXN}`, "すべての Mac", "Mac の中だけで確認", `License key:\n${key}`, `License ID: ${TXN}`, "every Mac you use", "on your Mac only"]) {
      assert.ok(text.includes(part), part);
    }
    assert.ok(text.indexOf("ご購入") < text.indexOf("Thank you"), "日本語が先");
    assert.ok(html.includes(`<a href="nonet://register?key=${key}">Nonet に登録する</a>`));
    assert.ok(html.includes(`<a href="nonet://register?key=${key}">Register in Nonet</a>`));
  });
});

// MARK: - Paddle の署名

describe("Paddle-Signature", () => {
  const body = notification("transaction.completed", { id: TXN });
  const now = 1_794_000_000;

  test("正しい署名は通り、本文・秘密・時刻のどれかが違えば通らない", async () => {
    const header = signature(body, { ts: now });
    assert.deepEqual(await verifyPaddleSignature(header, body, SECRET, now), { ok: true });
    assert.equal((await verifyPaddleSignature(header, `${body} `, SECRET, now)).ok, false, "本文を変えた");
    assert.equal((await verifyPaddleSignature(header, body, `${SECRET}x`, now)).ok, false, "別の秘密");
    assert.equal((await verifyPaddleSignature(signature(body, { ts: now + 1 }).replace(`ts=${now + 1}`, `ts=${now}`), body, SECRET, now)).ok, false, "時刻を差し替えた");
  });

  test("時刻のずれは前後 5 秒まで", async () => {
    for (const [ts, ok] of [[now - 5, true], [now + 5, true], [now - 6, false], [now + 6, false], [now - 3600, false]]) {
      const result = await verifyPaddleSignature(signature(body, { ts }), body, SECRET, now);
      assert.equal(result.ok, ok, `ts=${ts - now}`);
    }
  });

  test("秘密を入れ替えている間の h1 が2つの署名は、どちらかが合えば通る", async () => {
    const good = signature(body, { ts: now }).split(";h1=")[1];
    const header = `ts=${now};h1=${"0".repeat(64)};h1=${good}`;
    assert.equal((await verifyPaddleSignature(header, body, SECRET, now)).ok, true);
  });

  test("読めないヘッダは通さない", async () => {
    for (const header of [null, "", "garbage", `ts=${now}`, `h1=${"a".repeat(64)}`, `ts=abc;h1=${"a".repeat(64)}`, `ts=${now};h1=xyz`]) {
      assert.equal((await verifyPaddleSignature(header, body, SECRET, now)).ok, false, String(header));
    }
    assert.deepEqual(parseSignatureHeader(` ts=${now} ; h1=${"A".repeat(64)} `), { timestamp: now, signatures: ["a".repeat(64)] });
  });

  test("API キーの種類で本番か sandbox かを決める", () => {
    assert.equal(paddleApiBase("pdl_live_apikey_x"), "https://api.paddle.com");
    assert.equal(paddleApiBase("pdl_sdbx_apikey_x"), "https://sandbox-api.paddle.com");
    assert.equal(paddleApiBase("sk_live_x"), null);
    assert.equal(paddleApiBase(undefined), null);
  });
});

// MARK: - 設定が無いとき

describe("設定が無いとき", () => {
  test("どの設定が欠けても、Webhook と /api/license は 503 を返し、外に通信しない", async () => {
    for (const name of ["PADDLE_API_KEY", "PADDLE_NOTIFICATION_SECRET", "LICENSE_PRIVATE_KEY", "LICENSE_PUBLIC_KEY", "PADDLE_PRICE_ID", "RESEND_API_KEY"]) {
      const env = licensingEnv({ [name]: undefined });
      const body = notification("transaction.completed", transaction());
      const webhook = await postWebhook(env, body);
      assert.equal(webhook.status, 503, name);
      const lookupNeeds = !["PADDLE_NOTIFICATION_SECRET", "RESEND_API_KEY"].includes(name);
      const lookup = await call(env, `/api/license?transaction_id=${TXN}`);
      assert.equal(lookup.status, lookupNeeds ? 503 : 200, `${name}: /api/license`);
      if (lookupNeeds) {
        assert.deepEqual(await lookup.json(), { error: "unavailable" });
      }
    }
    assert.equal(mails().length, 0);
    assert.ok(errors.every((line) => !line.includes(PRIVATE_KEY) && !line.includes(SECRET)), "秘密をログに出さない");
  });

  test("形の違う設定（API キー・価格・鍵）も 503", async () => {
    for (const overrides of [{ PADDLE_API_KEY: "sk_live_x" }, { PADDLE_PRICE_ID: "pri_TODO" }, { LICENSE_PRIVATE_KEY: "abc" }, { LICENSE_PUBLIC_KEY: "abc" }]) {
      const response = await call(licensingEnv(overrides), `/api/license?transaction_id=${TXN}`);
      assert.equal(response.status, 503, JSON.stringify(overrides));
    }
    assert.equal(fetchCalls.length, 0);
  });

  test("秘密鍵がアプリの公開鍵と対でなければ 503（Paddle に問い合わせず、キーもメールも出さない）", async () => {
    const other = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
    const otherPublic = Buffer.from(await crypto.subtle.exportKey("raw", other.publicKey)).toString("base64");
    const env = licensingEnv({ LICENSE_PUBLIC_KEY: otherPublic });
    assert.equal((await call(env, `/api/license?transaction_id=${TXN}`)).status, 503);
    assert.equal((await postWebhook(env, notification("transaction.completed", transaction()))).status, 503);
    assert.equal(fetchCalls.length, 0);
    assert.ok(errors.some((line) => line.includes("対応していません")));
  });

  test("秘密が無くても、ページとほかの Worker のパスは今までどおり", async () => {
    const env = makeEnv();
    assert.equal((await call(env, "/")).status, 200);
    assert.equal((await call(env, "/api/license?transaction_id=" + TXN)).status, 503);
    assert.equal((await call(env, "/api/nothing")).status, 404);
    assert.equal(fetchCalls.length, 0);
  });
});

// MARK: - Webhook

describe("POST /api/paddle/webhook", () => {
  test("transaction.completed: 取引と顧客を API で読み、キーを購入者にメールで送る", async () => {
    const env = licensingEnv();
    const response = await postWebhook(env, notification("transaction.completed", transaction()));
    assert.equal(response.status, 200);
    assert.deepEqual(paddleCalls().map(({ url }) => url), [`https://api.paddle.com/transactions/${TXN}?include=customer`]);
    assert.equal(paddleCalls()[0].headers.get("authorization"), `Bearer ${env.PADDLE_API_KEY}`);
    const [mail] = mails();
    assert.equal(mails().length, 1);
    assert.deepEqual(mail.to, ["taro@example.com"]);
    assert.equal(mail.from, "Nonet <support@astlog.dev>");
    assert.equal(mail.reply_to, "support@astlog.dev");
    assert.equal(mail.idempotencyKey, `nonet-license/${TXN}`);
    assert.equal(fetchCalls.find(({ url }) => url.includes("resend")).headers.get("authorization"), "Bearer re_test_key");
    const key = /^ライセンスキー:\n(\S+)$/m.exec(mail.text)[1];
    assert.equal(await verifyLicense(key, await importPublicKey(PUBLIC_KEY)), true);
    assert.deepEqual(decodeLicenseKey(key), {
      edition: "standard",
      email: "taro@example.com",
      issuedAt: "2026-11-15T03:04:05Z",
      licenseID: TXN,
      licensee: "山田 太郎",
      product: "com.iam74k4.Nonet",
    });
    assert.deepEqual(errors, []);
  });

  test("顧客の名前が無ければメールアドレスを登録者にする。API が顧客を含めなかったときは、顧客を別に引く", async () => {
    paddleTransaction = transaction({ customer: undefined });
    const response = await postWebhook(licensingEnv(), notification("transaction.completed", transaction()));
    assert.equal(response.status, 200);
    assert.deepEqual(paddleCalls().map(({ url }) => new URL(url).pathname), [`/transactions/${TXN}`, `/customers/${CUSTOMER}`]);
    const [mail] = mails();
    assert.deepEqual(mail.to, ["buyer@example.com"]);
    const key = /^ライセンスキー:\n(\S+)$/m.exec(mail.text)[1];
    assert.equal(decodeLicenseKey(key).licensee, "buyer@example.com");
  });

  test("sandbox の API キーなら sandbox の API を使う", async () => {
    await postWebhook(licensingEnv({ PADDLE_API_KEY: "pdl_sdbx_apikey_01jc0eeeeeeeeeeeeeeeeeeeeeeeeee" }), notification("transaction.completed", transaction()));
    assert.match(paddleCalls()[0].url, /^https:\/\/sandbox-api\.paddle\.com\/transactions\//);
  });

  test("署名が無い・違う・古い通知は 401 で、何もしない", async () => {
    const env = licensingEnv();
    const body = notification("transaction.completed", transaction());
    const stale = signature(body, { ts: Math.floor(Date.now() / 1000) - 60 });
    for (const header of [null, "ts=1;h1=00", signature(body, { secret: "pdl_ntfset_other" }), stale, signature(`${body}\n`)]) {
      const response = await postWebhook(env, body, { header });
      assert.equal(response.status, 401, String(header));
    }
    assert.equal(fetchCalls.length, 0);
    assert.equal(errors.length, 5);
  });

  test("ほかの商品・ほかの種類の通知には 200 を返し、何もしない（Paddle が送り直し続けないように）", async () => {
    const env = licensingEnv();
    const cases = [
      notification("transaction.completed", transaction({ items: [{ price: { id: OTHER_PRICE }, quantity: 1 }] })),
      notification("transaction.paid", transaction({ status: "paid" })),
      notification("transaction.created", transaction({ status: "draft" })),
      notification("customer.updated", { id: CUSTOMER }),
      notification("transaction.completed", { id: "not-a-transaction" }),
      JSON.stringify({ event_type: "transaction.completed" }),
    ];
    for (const body of cases) {
      const response = await postWebhook(env, body);
      assert.equal(response.status, 200, body);
      assert.equal(await response.text(), "Ignored\n");
    }
    assert.equal(fetchCalls.length, 0, "ほかの商品の通知で API もメールも呼ばない");
  });

  test("通知の中身が Nonet でも、API で読んだ取引がほかの商品なら送らない", async () => {
    paddleTransaction = transaction({ items: [{ price: { id: OTHER_PRICE }, quantity: 1 }] });
    const response = await postWebhook(licensingEnv(), notification("transaction.completed", transaction()));
    assert.equal(response.status, 200);
    assert.equal(mails().length, 0);
  });

  test("API ではまだ済んでいなければ 503（Paddle が少し後で送り直す）", async () => {
    paddleTransaction = transaction({ status: "paid" });
    const response = await postWebhook(licensingEnv(), notification("transaction.completed", transaction()));
    assert.equal(response.status, 503);
    assert.equal(mails().length, 0);
  });

  test("Paddle の API・メールが失敗したら 2xx 以外を返す（Paddle が送り直す）", async () => {
    const env = licensingEnv();
    const body = notification("transaction.completed", transaction());
    routes[0][1] = () => json(500, { error: { code: "internal_error" } });
    assert.equal((await postWebhook(env, body)).status, 502);
    routes[0][1] = () => {
      throw new TypeError("fetch failed");
    };
    assert.equal((await postWebhook(env, body)).status, 502);
    routes = defaultRoutes();
    resendResponse = () => json(403, { name: "validation_error", message: "The astlog.dev domain is not verified." });
    assert.equal((await postWebhook(env, body)).status, 502);
    resendResponse = () => json(500, { name: "application_error" });
    assert.equal((await postWebhook(env, body)).status, 502);
    assert.ok(errors.some((line) => line.includes("Resend が 403 を返しました（validation_error）")), errors.join("\n"));
    assert.ok(errors.some((line) => line.includes("internal_error")));
  });

  test("同じ取引のメールを 24 時間のうちに中身を変えて送り直そうとしたら（Resend の 409）、送ったものとして 200", async () => {
    resendResponse = () => json(409, { name: "invalid_idempotent_request" });
    const response = await postWebhook(licensingEnv(), notification("transaction.completed", transaction()));
    assert.equal(response.status, 200);
    resendResponse = () => json(409, { name: "concurrent_idempotent_requests" });
    assert.equal((await postWebhook(licensingEnv(), notification("transaction.completed", transaction()))).status, 502);
  });

  test("POST のほかは 405、大きすぎる本文は 413、JSON でない本文は 400", async () => {
    const env = licensingEnv();
    const get = await call(env, "/api/paddle/webhook");
    assert.equal(get.status, 405);
    assert.equal(get.headers.get("allow"), "POST");
    const huge = "x".repeat(256 * 1024 + 1);
    assert.equal((await postWebhook(env, huge)).status, 413);
    assert.equal((await postWebhook(env, "not json")).status, 400);
    assert.equal(fetchCalls.length, 0);
  });

  test("承認された返金・チャージバックは、開発者に nonet-license revoke を知らせる", async () => {
    const env = licensingEnv();
    const adjustment = { id: "adj_01jc0hhhhhhhhhhhhhhhhhhhhh", action: "refund", type: "full", status: "approved", transaction_id: TXN, customer_id: CUSTOMER };
    const response = await postWebhook(env, notification("adjustment.updated", adjustment));
    assert.equal(response.status, 200);
    const [mail] = mails();
    assert.deepEqual(mail.to, ["support@astlog.dev"]);
    assert.ok(mail.subject.includes(TXN));
    assert.ok(mail.text.includes(`swift run nonet-license revoke ${TXN}`));
    assert.ok(mail.text.includes("full"));
    assert.equal(mail.idempotencyKey, `nonet-revoke/${adjustment.id}`);
    assert.deepEqual(paddleCalls().map(({ url }) => new URL(url).pathname), [`/transactions/${TXN}`]);

    fetchCalls = [];
    const chargeback = await postWebhook(env, notification("adjustment.created", { ...adjustment, action: "chargeback" }));
    assert.equal(chargeback.status, 200);
    assert.match(mails()[0].subject, /チャージバック/);
  });

  test("承認待ち・却下・返金でない調整・ほかの商品の返金は知らせない", async () => {
    const env = licensingEnv();
    const adjustment = { id: "adj_01jc0hhhhhhhhhhhhhhhhhhhhh", action: "refund", type: "full", status: "approved", transaction_id: TXN };
    for (const data of [{ ...adjustment, status: "pending_approval" }, { ...adjustment, status: "rejected" }, { ...adjustment, action: "credit" }]) {
      assert.equal((await postWebhook(env, notification("adjustment.created", data))).status, 200);
    }
    assert.equal(fetchCalls.length, 0);
    paddleTransaction = transaction({ items: [{ price: { id: OTHER_PRICE }, quantity: 1 }] });
    assert.equal((await postWebhook(env, notification("adjustment.updated", adjustment))).status, 200);
    assert.equal(mails().length, 0);
  });
});

// MARK: - GET /api/license

describe("GET /api/license", () => {
  test("済んだ Nonet の取引なら、Webhook のメールと同じキーを返す（写させない）", async () => {
    const env = licensingEnv();
    const response = await call(env, `/api/license?transaction_id=${TXN}`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.match(response.headers.get("content-type"), /^application\/json/);
    assert.equal(response.headers.get("x-content-type-options"), "nosniff");
    const body = await response.json();
    assert.equal(body.license_id, TXN);
    assert.match(body.license_key, LICENSE_KEY_PATTERN);
    // 何度聞いても同じキー。通知で送るキーとも同じ
    assert.equal((await (await call(env, `/api/license?transaction_id=${TXN}`)).json()).license_key, body.license_key);
    await postWebhook(env, notification("transaction.completed", transaction()));
    assert.ok(mails()[0].text.includes(body.license_key));
    assert.equal(mails().length, 1, "GET ではメールを送らない");
  });

  test("取引の ID の形でなければ 400（Paddle に問い合わせない）", async () => {
    for (const query of ["", "?transaction_id=", "?transaction_id=txn_short", "?transaction_id=TXN_01JC0AAAAAAAAAAAAAAAAAAAAA", `?transaction_id=${TXN}/../x`, `?id=${TXN}`]) {
      const response = await call(licensingEnv(), `/api/license${query}`);
      assert.equal(response.status, 400, query);
    }
    assert.equal(fetchCalls.length, 0);
  });

  test("無い取引・ほかの商品・取り消した取引は 404、まだ済んでいなければ 409", async () => {
    const env = licensingEnv();
    assert.equal((await call(env, `/api/license?transaction_id=${OTHER_TXN}`)).status, 404);
    paddleTransaction = transaction({ items: [{ price: { id: OTHER_PRICE }, quantity: 1 }] });
    assert.equal((await call(env, `/api/license?transaction_id=${TXN}`)).status, 404);
    paddleTransaction = transaction({ status: "canceled" });
    assert.equal((await call(env, `/api/license?transaction_id=${TXN}`)).status, 404);
    for (const status of ["paid", "billed", "ready"]) {
      paddleTransaction = transaction({ status });
      const response = await call(env, `/api/license?transaction_id=${TXN}`);
      assert.equal(response.status, 409, status);
      assert.equal(response.headers.get("retry-after"), "2");
    }
    assert.equal(mails().length, 0);
  });

  test("Paddle の API が失敗したら 502、GET のほかは 405", async () => {
    routes[0][1] = () => json(401, { error: { code: "authentication_malformed" } });
    const response = await call(licensingEnv(), `/api/license?transaction_id=${TXN}`);
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: "upstream" });
    assert.ok(errors.some((line) => line.includes("authentication_malformed")));
    const post = await call(licensingEnv(), `/api/license?transaction_id=${TXN}`, { method: "POST" });
    assert.equal(post.status, 405);
    assert.equal(post.headers.get("allow"), "GET");
  });
});

// MARK: - 設定の値が、アプリとページと同じこと

describe("wrangler.toml の [vars]", () => {
  const toml = readFileSync(join(ROOT, "cloudflare", "wrangler.toml"), "utf8");
  const vars = Object.fromEntries([...toml.split(/^\[vars\]$/m)[1].matchAll(/^([A-Z_]+) = "([^"]*)"$/gm)].map((match) => [match[1], match[2]]));

  test("LICENSE_PUBLIC_KEY は、アプリに入れる公開鍵（Config/Nonet.xcconfig の NONET_LICENSE_PUBLIC_KEY）と同じ", () => {
    const config = readFileSync(join(ROOT, "Config", "Nonet.xcconfig"), "utf8");
    const line = /^NONET_LICENSE_PUBLIC_KEY\s*=\s*(.*)$/m.exec(config);
    assert.ok(line, "xcconfig に NONET_LICENSE_PUBLIC_KEY がありません");
    // xcconfig では // から後ろがコメントなので、公開鍵の // は /$()/ と書く（docs/release.md 1.6）
    const appKey = line[1].replace(/\$\(\)/g, "").replace(/\s*\/\/.*$/, "").trim();
    assert.equal(decodeKeyMaterial(vars.LICENSE_PUBLIC_KEY)?.length, 32);
    assert.equal(vars.LICENSE_PUBLIC_KEY, appKey);
  });

  test("PADDLE_PRICE_ID は、購入のページの価格の ID と同じ", () => {
    for (const page of ["buy.html", "en/buy.html"]) {
      const html = readFileSync(join(SITE_DIR, page), "utf8");
      assert.equal(/data-paddle-price="([^"]*)"/.exec(html)?.[1], vars.PADDLE_PRICE_ID, page);
    }
  });

  test("秘密の値は wrangler.toml に書かない", () => {
    for (const name of ["PADDLE_API_KEY", "PADDLE_NOTIFICATION_SECRET", "LICENSE_PRIVATE_KEY", "RESEND_API_KEY"]) {
      assert.equal(vars[name], undefined, name);
    }
    assert.ok(/run_worker_first = \[.*"\/api\/\*".*\]/.test(toml), "run_worker_first に /api/* がありません");
  });

  test("購入のページの data-license-endpoint は、Worker の /api/license を指す", () => {
    for (const page of ["buy.html", "en/buy.html"]) {
      const html = readFileSync(join(SITE_DIR, page), "utf8");
      assert.equal(/data-license-endpoint="([^"]*)"/.exec(html)?.[1], "/api/license", page);
    }
  });
});

// 送る前の確かめとして、テストで作ったキーが署名どおりか（signLicense だけで作っても同じ）
test("signLicense と issueLicenseKey は同じキーを作る", async () => {
  const privateKey = await importPrivateKey(PRIVATE_KEY);
  const publicKey = await importPublicKey(PUBLIC_KEY);
  const info = licenseInfo({ licenseID: TXN, licensee: "Taro", issuedAt: "2026-11-15T03:04:05Z" });
  assert.equal(await signLicense(info, privateKey), await issueLicenseKey(info, { privateKey, publicKey }));
});

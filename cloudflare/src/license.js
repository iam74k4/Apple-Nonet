// ライセンスキーを作る（アプリの NonetCore/Licensing/License.swift と nonet-license issue と同じ形）。
//   キー = base64url(LicenseInfo の JSON) + "." + base64url(Ed25519 の署名)
// JSON は nonet-license と1バイトも違わないようにする（キーを並べ替え、/ はエスケープせず、日付は秒までの ISO 8601）。
// WebCrypto の Ed25519 の署名は RFC 8032 のとおり決まった値になるので、同じ取引からは何度作っても同じキーになる（保存しなくてよい）。
// nonet-license issue（CryptoKit）の署名は毎回乱数を混ぜるので、手で発行したキーは、中身が同じでも署名の部分が違う（どちらも有効）。
// 形がずれていないことは scripts/tests/license_test.sh が、nonet-license verify と issue で確かめる。

export const PRODUCT_ID = "com.iam74k4.Nonet";
export const EDITION = "standard";
const KEY_LENGTH = 32;
// Ed25519 の秘密鍵（32 バイトの種）を WebCrypto に渡す PKCS#8 の前半（RFC 8410）。
// nonet-license の鍵は CryptoKit の rawRepresentation（種そのもの）なので、これを前に付けて読む
const PKCS8_ED25519_PREFIX = Uint8Array.from([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20]);
// 登録者の名前の長さの上限（文字）。Paddle の名前は購入者が入れるので、念のため
const LICENSEE_LIMIT = 200;

// ライセンスキーの形（License.swift の LicenseCoding.keyParts と同じ。JSON は「{"」で始まるので eyJ、署名は 86 文字）
export const LICENSE_KEY_PATTERN = /^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{86}$/;

export class LicenseError extends Error {}

// LicenseInfo（License.swift）。email が無ければ項目ごと書かない（Swift の Optional と同じ）
export function licenseInfo({ licenseID, licensee, email = null, issuedAt }) {
  const id = typeof licenseID === "string" ? licenseID.trim() : "";
  if (id === "") {
    throw new LicenseError("ライセンス ID が空です");
  }
  const address = typeof email === "string" && email.trim() !== "" ? email.trim() : null;
  if (address !== null && (!address.includes("@") || /\s/.test(address))) {
    // 値はログに出さない（購入者の情報）
    throw new LicenseError("顧客のメールアドレスが、メールアドレスの形ではありません");
  }
  // 名前が無い（Paddle の顧客の name は null のことがある）ときは、nonet-license issue の手順と同じくメールアドレスにする
  const name = cleanLicensee(licensee) || address;
  if (!name) {
    throw new LicenseError("登録者の名前もメールアドレスもありません");
  }
  const info = { licenseID: id, product: PRODUCT_ID, licensee: name, edition: EDITION, issuedAt: secondsTimestamp(issuedAt) };
  if (address !== null) {
    info.email = address;
  }
  return info;
}

// 制御文字（改行・タブ・U+2028 など）は空白にし、前後の空白を除き、長すぎれば切る。アプリは登録者を1行で見せる
function cleanLicensee(value) {
  if (typeof value !== "string") {
    return "";
  }
  const text = value.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, " ").trim();
  return [...text].slice(0, LICENSEE_LIMIT).join("").trim();
}

// RFC 3339 の日時（Paddle の billed_at など。秒の小数・時差つきでもよい）を、キーに入れる「2026-11-15T03:04:05Z」にする。
// 秒の小数は切り捨てる（nonet-license issue と同じ。キーには秒までしか入らない）
export function secondsTimestamp(value) {
  const text = typeof value === "string" ? value.trim() : "";
  const match = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$/i.exec(text);
  if (match === null) {
    throw new LicenseError(`日時の形ではありません: ${value}`);
  }
  const milliseconds = Date.parse(`${match[1]}${match[2].toUpperCase()}`);
  if (!Number.isFinite(milliseconds)) {
    throw new LicenseError(`日時を読めません: ${value}`);
  }
  return new Date(milliseconds).toISOString().replace(/\.\d{3}Z$/, "Z");
}

// nonet-license と同じ JSON（JSONEncoder の .sortedKeys と .withoutEscapingSlashes）。
// JSON.stringify は / をエスケープせず、ASCII の外の文字もそのまま書き、制御文字の書き方も JSONEncoder と同じ
export function encodeLicenseInfo(info) {
  const sorted = {};
  for (const name of Object.keys(info).sort()) {
    sorted[name] = info[name];
  }
  return JSON.stringify(sorted);
}

export function base64url(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// 鍵の base64（nonet-license の鍵のファイルと同じ。標準の base64 でも base64url でもよく、空白・改行は無視する）。
// 32 バイトでなければ null
export function decodeKeyMaterial(text) {
  if (typeof text !== "string") {
    return null;
  }
  const compact = text.replace(/\s+/g, "").replace(/-/g, "+").replace(/_/g, "/").replace(/=+$/, "");
  if (compact === "" || !/^[A-Za-z0-9+/]+$/.test(compact) || compact.length % 4 === 1) {
    return null;
  }
  let binary;
  try {
    binary = atob(compact + "=".repeat((4 - (compact.length % 4)) % 4));
  } catch {
    return null;
  }
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  return bytes.length === KEY_LENGTH ? bytes : null;
}

export async function importPrivateKey(privateKeyBase64) {
  const seed = decodeKeyMaterial(privateKeyBase64);
  if (seed === null) {
    throw new LicenseError("秘密鍵が 32 バイトの base64 ではありません");
  }
  const pkcs8 = new Uint8Array(PKCS8_ED25519_PREFIX.length + seed.length);
  pkcs8.set(PKCS8_ED25519_PREFIX);
  pkcs8.set(seed, PKCS8_ED25519_PREFIX.length);
  return crypto.subtle.importKey("pkcs8", pkcs8, { name: "Ed25519" }, false, ["sign"]);
}

export async function importPublicKey(publicKeyBase64) {
  const raw = decodeKeyMaterial(publicKeyBase64);
  if (raw === null) {
    throw new LicenseError("公開鍵が 32 バイトの base64 ではありません");
  }
  return crypto.subtle.importKey("raw", raw, { name: "Ed25519" }, false, ["verify"]);
}

// 署名は JSON のバイト列そのものに対して行う（LicenseSigner.sign と同じ）
export async function signLicense(info, privateKey) {
  const payload = new TextEncoder().encode(encodeLicenseInfo(info));
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, privateKey, payload));
  return `${base64url(payload)}.${base64url(signature)}`;
}

// キーの署名がこの公開鍵で通るか（アプリの LicenseVerifier と同じく、JSON のバイト列で確かめる）
export async function verifyLicense(key, publicKey) {
  if (typeof key !== "string" || !LICENSE_KEY_PATTERN.test(key)) {
    return false;
  }
  const [payload, signature] = key.split(".").map(decodeBase64url);
  if (payload === null || signature === null || signature.length !== 64) {
    return false;
  }
  return crypto.subtle.verify({ name: "Ed25519" }, publicKey, signature, payload);
}

// キーの中身（JSON）。読めなければ null
export function decodeLicenseKey(key) {
  if (typeof key !== "string" || !LICENSE_KEY_PATTERN.test(key)) {
    return null;
  }
  const payload = decodeBase64url(key.split(".")[0]);
  if (payload === null) {
    return null;
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(payload));
  } catch {
    return null;
  }
}

function decodeBase64url(text) {
  if (!/^[A-Za-z0-9_-]+$/.test(text) || text.length % 4 === 1) {
    return null;
  }
  const base64 = text.replace(/-/g, "+").replace(/_/g, "/");
  try {
    return Uint8Array.from(atob(base64 + "=".repeat((4 - (base64.length % 4)) % 4)), (character) => character.charCodeAt(0));
  } catch {
    return null;
  }
}

// 秘密鍵で作ったキーが、アプリに入れる公開鍵で通ることを確かめてから渡す（nonet-license issue と同じ守り。
// 秘密の変数に別の鍵を入れてしまっても、だれも登録できないキーを配らない）
export async function issueLicenseKey(info, { privateKey, publicKey }) {
  const key = await signLicense(info, privateKey);
  if (!(await verifyLicense(key, publicKey))) {
    throw new LicenseError("LICENSE_PRIVATE_KEY が LICENSE_PUBLIC_KEY（アプリに入れる公開鍵）と対応していません");
  }
  return key;
}

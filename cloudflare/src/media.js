// 販売ページの動画（site/images/*.mp4。ヒーローのデモ動画）を、範囲の要求（Range）に答えて返す。
// 静的なアセットは Range を無視して、いつも全体を 200 で返す（2026-11-15 に本番で確かめた）。Safari（とくに iPhone）は
// 動画を Range で少しずつ読み、206 が返らないと再生しないことがあるので、動画だけは Worker を通す（wrangler.toml の
// run_worker_first の "/images/*.mp4"）。中身とヘッダ（CSP・ETag・Cache-Control）はアセットの応答をそのまま使い、
// 要る範囲を切り出すだけにする。ほかの画像とページは、これまでどおり Worker を通らない。

import { UNSATISFIABLE, parseRange } from "./updates.js";

// 動画のパス（/images/ の直下の .mp4）。ほかは扱わない
export function isMediaPath(pathname) {
  return /^\/images\/[A-Za-z0-9._-]+\.mp4$/.test(pathname);
}

// 切り出すために全体を読む上限。ページの動画は 1MB に満たない（AstLog の動画の上限も 10MB）。
// これより大きなものは、読まずにアセットの応答（200 の全体）をそのまま返す
export const MAX_MEDIA_BYTES = 10 * 1024 * 1024;

// アセットには Range・If-Range を外して渡す。メソッドと条件つきのヘッダ（If-None-Match）はそのまま渡し、
// 304・404・405 と HEAD はアセットの側の決まりに任せる（src/site.js と同じ）。
// 200 の全体が返ったときだけ、Range に従って 206（範囲がファイルの外なら 416）にする
export async function serveMedia(request, env) {
  const forwarded = new Headers(request.headers);
  forwarded.delete("range");
  forwarded.delete("if-range");
  const asset = await env.ASSETS.fetch(new Request(request.url, { method: request.method, headers: forwarded }));
  if (asset.status !== 200) {
    return asset;
  }
  const declared = Number(asset.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_MEDIA_BYTES) {
    return asset;
  }
  const headers = new Headers(asset.headers);
  headers.set("accept-ranges", "bytes");
  if (request.method === "HEAD" || asset.body === null) {
    return new Response(null, { status: 200, headers });
  }
  const bytes = new Uint8Array(await asset.arrayBuffer());
  const rangeHeader = request.headers.get("range");
  const range =
    rangeHeader !== null && ifRangeAllows(request.headers.get("if-range"), headers.get("etag"))
      ? parseRange(rangeHeader, bytes.length)
      : null;
  if (range === UNSATISFIABLE) {
    headers.set("content-range", `bytes */${bytes.length}`);
    headers.set("content-length", "0");
    headers.set("cache-control", "no-store");
    return new Response(null, { status: 416, headers });
  }
  if (range === null) {
    headers.set("content-length", String(bytes.length));
    return new Response(bytes, { status: 200, headers });
  }
  const part = bytes.subarray(range.start, range.end + 1);
  headers.set("content-range", `bytes ${range.start}-${range.end}/${bytes.length}`);
  headers.set("content-length", String(part.length));
  return new Response(part, { status: 206, headers });
}

// If-Range が今の中身の ETag（強い比較）を指すときだけ Range に従う。アセットには Last-Modified が無いので、
// 日付と弱い ETag のときは、全体を 200 で返す（RFC 9110 13.1.5）
function ifRangeAllows(ifRange, etag) {
  if (ifRange === null) {
    return true;
  }
  const value = ifRange.trim();
  return etag !== null && !value.startsWith("W/") && value === etag;
}

// ページの動画（src/media.js）: アセットの全体から、Range の範囲を切り出して 206 で返す。
// Safari は動画を Range で読み、206 が返らないと再生しないことがある（静的なアセットは Range に答えない）
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, test } from "node:test";

import { MAX_MEDIA_BYTES, isMediaPath } from "../src/media.js";
import { bodyBytes, call, makeEnv, SITE_DIR } from "./support.js";

const VIDEO = "/images/demo-en.mp4";
const bytes = new Uint8Array(readFileSync(join(SITE_DIR, VIDEO)));
const size = bytes.length;

describe("ページの動画の範囲の要求", () => {
  test("Range が無ければ全体を 200 で、Accept-Ranges を付けて返す（ヘッダはアセットのもの）", async () => {
    const response = await call(makeEnv(), VIDEO);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("accept-ranges"), "bytes");
    assert.equal(response.headers.get("content-type"), "video/mp4");
    assert.equal(response.headers.get("content-length"), String(size));
    assert.equal(response.headers.get("x-content-type-options"), "nosniff");
    assert.match(response.headers.get("etag"), /^"[0-9a-f]+"$/);
    assert.deepEqual(await bodyBytes(response), bytes);
  });

  test("Safari が最初に送る bytes=0-1 に、2バイトを 206 で返す", async () => {
    const env = makeEnv();
    const response = await call(env, VIDEO, { headers: { range: "bytes=0-1" } });
    assert.equal(response.status, 206);
    assert.equal(response.headers.get("content-range"), `bytes 0-1/${size}`);
    assert.equal(response.headers.get("content-length"), "2");
    assert.deepEqual(await bodyBytes(response), bytes.subarray(0, 2));
    // アセットには Range を渡さない（全体を受け取って切り出す）
    assert.equal(env.ASSETS.requests[0].headers.get("range"), null);
  });

  test("始めだけ・末尾の長さの範囲と、終わりがファイルの外の範囲", async () => {
    const env = makeEnv();
    const open = await call(env, VIDEO, { headers: { range: "bytes=1000-" } });
    assert.equal(open.status, 206);
    assert.equal(open.headers.get("content-range"), `bytes 1000-${size - 1}/${size}`);
    assert.deepEqual(await bodyBytes(open), bytes.subarray(1000));
    const suffix = await call(env, VIDEO, { headers: { range: "bytes=-10" } });
    assert.equal(suffix.status, 206);
    assert.deepEqual(await bodyBytes(suffix), bytes.subarray(size - 10));
    const beyondEnd = await call(env, VIDEO, { headers: { range: `bytes=${size - 5}-${size + 100}` } });
    assert.equal(beyondEnd.status, 206);
    assert.equal(beyondEnd.headers.get("content-range"), `bytes ${size - 5}-${size - 1}/${size}`);
    assert.equal((await bodyBytes(beyondEnd)).length, 5);
  });

  test("ファイルの外から始まる範囲は 416（Content-Range に大きさ）", async () => {
    const response = await call(makeEnv(), VIDEO, { headers: { range: `bytes=${size}-` } });
    assert.equal(response.status, 416);
    assert.equal(response.headers.get("content-range"), `bytes */${size}`);
    assert.equal(response.headers.get("cache-control"), "no-store");
  });

  test("読めない Range と複数の範囲は無視して全体を 200 で返す", async () => {
    for (const range of ["bytes=5-2", "items=0-1", "bytes=0-1,4-5"]) {
      const response = await call(makeEnv(), VIDEO, { headers: { range } });
      assert.equal(response.status, 200, range);
      assert.equal((await bodyBytes(response)).length, size, range);
    }
  });

  test("If-Range が今の ETag なら範囲で、違う ETag・弱い ETag・日付なら全体で返す", async () => {
    const env = makeEnv();
    const etag = (await call(env, VIDEO, { method: "HEAD" })).headers.get("etag");
    const same = await call(env, VIDEO, { headers: { range: "bytes=0-1", "if-range": etag } });
    assert.equal(same.status, 206);
    for (const ifRange of ['"0000"', `W/${etag}`, "Sun, 15 Nov 2026 13:00:00 GMT"]) {
      const other = await call(env, VIDEO, { headers: { range: "bytes=0-1", "if-range": ifRange } });
      assert.equal(other.status, 200, ifRange);
      assert.equal((await bodyBytes(other)).length, size, ifRange);
    }
  });

  test("HEAD は本文なしの 200 で Accept-Ranges と大きさを返し、If-None-Match はアセットの 304 のまま", async () => {
    const env = makeEnv();
    const head = await call(env, VIDEO, { method: "HEAD" });
    assert.equal(head.status, 200);
    assert.equal(head.body, null);
    assert.equal(head.headers.get("accept-ranges"), "bytes");
    assert.equal(head.headers.get("content-length"), String(size));
    const revalidated = await call(env, VIDEO, { headers: { "if-none-match": head.headers.get("etag"), range: "bytes=0-1" } });
    assert.equal(revalidated.status, 304);
  });

  test("無い動画はアセットの 404 ページ", async () => {
    const response = await call(makeEnv(), "/images/no-such-video.mp4");
    assert.equal(response.status, 404);
  });

  test("上限より大きなものは読まずに、アセットの応答をそのまま返す", async () => {
    const env = makeEnv();
    env.ASSETS = {
      fetch: async () =>
        new Response("x", { status: 200, headers: { "content-type": "video/mp4", "content-length": String(MAX_MEDIA_BYTES + 1) } }),
    };
    const response = await call(env, VIDEO, { headers: { range: "bytes=0-1" } });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("accept-ranges"), null);
  });
});

describe("Worker を通す動画のパス", () => {
  test("/images/ の直下の .mp4 だけを扱う", () => {
    assert.ok(isMediaPath("/images/demo.mp4"));
    assert.ok(isMediaPath("/images/demo-en.mp4"));
    for (const path of ["/images/hud-xcode.webp", "/images/demo-poster.jpg", "/images/a/b.mp4", "/demo.mp4", "/images/.mp4x"]) {
      assert.ok(!isMediaPath(path), path);
    }
  });

  test("販売ページの動画はどれも、run_worker_first と isMediaPath に入っている（Range に答える）", () => {
    const toml = readFileSync(join(SITE_DIR, "..", "cloudflare", "wrangler.toml"), "utf8");
    const line = /^run_worker_first\s*=\s*\[(.*)\]$/m.exec(toml);
    assert.ok(line !== null && line[1].includes('"/images/*.mp4"'), "run_worker_first に /images/*.mp4 がありません");
    for (const page of ["index.html", "en/index.html"]) {
      const html = readFileSync(join(SITE_DIR, page), "utf8");
      const sources = [...html.matchAll(/<video src="([^"]+)"/g)].map((match) => new URL(match[1], `https://x/${page}`).pathname);
      assert.ok(sources.length > 0, `${page} に動画がありません`);
      for (const source of sources) {
        assert.ok(isMediaPath(source), `${page} の ${source} は Range に答えるパスではありません`);
      }
    }
  });
});

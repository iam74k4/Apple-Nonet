// /updates/<名前>: R2 のリリースのファイルを返す（src/updates.js）
import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { parseRange, UNSATISFIABLE, updateFileType } from "../src/updates.js";
import { bodyBytes, call, fixture, makeEnv } from "./support.js";

const DMG = new Uint8Array(1000).map((_, index) => index % 251);
const UPLOADED = new Date("2026-10-27T01:15:00.123Z");
const LAST_MODIFIED = "Tue, 27 Oct 2026 01:15:00 GMT";

function envWithRelease() {
  const env = makeEnv();
  env.UPDATES.put("appcast.xml", fixture("appcast.xml"), UPLOADED)
    .put("Nonet-1.2.0.dmg", DMG, UPLOADED)
    .put("Nonet42-41.delta", "delta", UPLOADED);
  return env;
}

function assertFileHeaders(response) {
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
  assert.equal(response.headers.get("content-security-policy"), "default-src 'none'; frame-ancestors 'none'; sandbox");
}

describe("配るファイル", () => {
  test("appcast.xml を XML として、写しを毎回確かめさせて返す", async () => {
    const env = envWithRelease();
    const response = await call(env, "/updates/appcast.xml");
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "application/xml; charset=utf-8");
    assert.equal(response.headers.get("cache-control"), "no-cache");
    assert.equal(response.headers.get("etag"), `"${env.UPDATES.objects.get("appcast.xml").etag}"`);
    assert.equal(response.headers.get("last-modified"), LAST_MODIFIED);
    assert.equal(response.headers.get("content-length"), String(Buffer.byteLength(fixture("appcast.xml"))));
    assert.equal(response.headers.get("accept-ranges"), "bytes");
    assertFileHeaders(response);
    assert.equal(await response.text(), fixture("appcast.xml"));
  });

  test("DMG とデルタは拡張子ごとの Content-Type で、immutable にしない", async () => {
    const env = envWithRelease();
    const dmg = await call(env, "/updates/Nonet-1.2.0.dmg");
    assert.equal(dmg.status, 200);
    assert.equal(dmg.headers.get("content-type"), "application/x-apple-diskimage");
    assert.equal(dmg.headers.get("content-length"), "1000");
    assert.equal(dmg.headers.get("cache-control"), "no-cache");
    assert.deepEqual(await bodyBytes(dmg), DMG);
    assertFileHeaders(dmg);

    const delta = await call(env, "/updates/Nonet42-41.delta");
    assert.equal(delta.status, 200);
    assert.equal(delta.headers.get("content-type"), "application/octet-stream");
    assert.equal(await delta.text(), "delta");
  });

  test("HEAD はヘッダだけを返し、本文を R2 から取らない", async () => {
    const env = envWithRelease();
    const response = await call(env, "/updates/Nonet-1.2.0.dmg", { method: "HEAD" });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-length"), "1000");
    assert.equal(response.headers.get("content-type"), "application/x-apple-diskimage");
    assert.equal(response.body, null);
    assert.deepEqual(env.UPDATES.calls, [["head", "Nonet-1.2.0.dmg"]]);
  });

  test("R2 に無いファイルは 404（サイトのページではなく、写しも残させない）", async () => {
    const env = envWithRelease();
    for (const path of ["/updates/Nonet-9.9.9.dmg", "/updates/Nonet99-98.delta"]) {
      const response = await call(env, path);
      assert.equal(response.status, 404, path);
      assert.equal(response.headers.get("content-type"), "text/plain; charset=utf-8");
      assert.equal(response.headers.get("cache-control"), "no-store");
      assertFileHeaders(response);
    }
    assert.equal(env.ASSETS.requests.length, 0);
  });

  test("初めてのリリースの前は appcast.xml も 404（release.sh が --first-release を求める合図）", async () => {
    const env = makeEnv();
    const response = await call(env, "/updates/appcast.xml");
    assert.equal(response.status, 404);
    assert.doesNotMatch(await response.text(), /<html/i);
  });

  test("/updates と /updates/ は一覧を出さずに 404", async () => {
    const env = envWithRelease();
    for (const path of ["/updates", "/updates/"]) {
      const response = await call(env, path);
      assert.equal(response.status, 404, path);
    }
    assert.deepEqual(env.UPDATES.calls, []);
  });
});

describe("名前の決まり", () => {
  test("release.sh が作る名前だけを通す", () => {
    for (const name of ["appcast.xml", "Nonet-1.2.dmg", "Nonet-1.2.0.dmg", "Nonet-10.20.30.dmg", "Nonet42-41.delta", "Nonet100-9.delta"]) {
      assert.notEqual(updateFileType(name), null, name);
    }
    for (const name of [
      "",
      "Appcast.xml",
      "appcast.xml.bak",
      ".appcast.xml",
      "nonet-1.2.0.dmg",
      "Nonet-1.2.0.DMG",
      "Nonet-1.dmg",
      "Nonet-1.2.3.4.dmg",
      "Nonet-1.2.0.dmg.exe",
      "Nonet-1.2.0.md",
      "Nonet-1.2.0.html",
      "Nonet042-41.delta",
      "Nonet42-41.delta.tmp",
      "Nonet-42-41.delta",
      "old_updates/Nonet-1.0.dmg",
      "../appcast.xml",
      "a/appcast.xml",
      "%2e%2e%2fappcast.xml",
      "appcast.xml%00",
      "Nonet-1.2.0.dmg?x",
    ]) {
      assert.equal(updateFileType(name), null, name);
    }
  });

  test("パスを細工しても、決まりに合わない名前で R2 を読まない", async () => {
    const env = envWithRelease();
    // 決まりの外の名前で置かれたものがあっても出さない
    env.UPDATES.put("../secret", "secret").put("a/appcast.xml", "secret").put("old_updates/Nonet-1.0.dmg", "secret");
    const attempts = [
      "/updates/%2e%2e/secret",
      "/updates/..%2fsecret",
      "/updates/%2e%2e%2fsecret",
      "/updates/a%2fappcast.xml",
      "/updates/a%2Fappcast.xml",
      "/updates/a/appcast.xml",
      "/updates//appcast.xml",
      "/updates/./appcast.xml/",
      "/updates/appcast.xml/",
      "/updates/old_updates/Nonet-1.0.dmg",
      "/updates/%5c..%5csecret",
      "/updates/..%5csecret",
      "/updates/appcast%2exml",
      "/updates/Nonet-1.2.0.dmg%00",
      "/updates/Nonet-1.2.0.dmg%20",
    ];
    for (const path of attempts) {
      const response = await call(env, path);
      assert.equal(response.status, 404, path);
      assert.doesNotMatch(await response.text(), /secret/, path);
    }
    assert.deepEqual(env.UPDATES.calls, []);
  });

  test("\\ と ../ は URL として先に解かれ、/updates/ の外のパスとして扱われる（R2 は読まない）", async () => {
    const env = envWithRelease();
    env.UPDATES.put("secret", "secret");
    for (const path of ["/updates/..\\secret", "/updates/../secret", "/updates/%2e%2e/%2e%2e/secret", "/updates\\..\\secret"]) {
      const response = await call(env, path);
      assert.equal(response.status, 404, path);
      assert.doesNotMatch(await response.text(), /^secret/, path);
    }
    assert.deepEqual(env.UPDATES.calls, []);
  });

  test("バケットの一覧は出さない", async () => {
    const env = envWithRelease();
    for (const path of ["/updates/", "/updates/?list-type=2", "/updates/*", "/updates/?prefix="]) {
      await call(env, path);
    }
    assert.equal(env.UPDATES.calls.some(([operation]) => operation === "list"), false);
  });
});

describe("メソッド", () => {
  test("GET と HEAD のほかは 405 と Allow", async () => {
    const env = envWithRelease();
    for (const method of ["POST", "PUT", "DELETE", "PATCH", "OPTIONS"]) {
      const response = await call(env, "/updates/appcast.xml", { method });
      assert.equal(response.status, 405, method);
      assert.equal(response.headers.get("allow"), "GET, HEAD");
      assertFileHeaders(response);
    }
    assert.deepEqual(env.UPDATES.calls, []);
  });
});

describe("条件つきの要求（304）", () => {
  test("If-None-Match が今の ETag と同じなら 304（弱い比較・並び・* も）", async () => {
    const env = envWithRelease();
    const etag = `"${env.UPDATES.objects.get("appcast.xml").etag}"`;
    for (const value of [etag, `W/${etag}`, `"other", ${etag}`, "*"]) {
      const response = await call(env, "/updates/appcast.xml", { headers: { "if-none-match": value } });
      assert.equal(response.status, 304, value);
      assert.equal(response.body, null);
      assert.equal(response.headers.get("etag"), etag);
      assert.equal(response.headers.get("cache-control"), "no-cache");
      assert.equal(response.headers.get("last-modified"), LAST_MODIFIED);
    }
    assert.equal(env.UPDATES.calls.some(([operation]) => operation === "get"), false);
  });

  test("ETag が違えば 200。If-None-Match があれば If-Modified-Since は見ない", async () => {
    const env = envWithRelease();
    const response = await call(env, "/updates/appcast.xml", {
      headers: { "if-none-match": '"old"', "if-modified-since": "Fri, 01 Jan 2100 00:00:00 GMT" },
    });
    assert.equal(response.status, 200);
  });

  test("If-Modified-Since は秒の単位で比べる", async () => {
    const env = envWithRelease();
    const same = await call(env, "/updates/Nonet-1.2.0.dmg", { headers: { "if-modified-since": LAST_MODIFIED } });
    assert.equal(same.status, 304);
    const later = await call(env, "/updates/Nonet-1.2.0.dmg", { headers: { "if-modified-since": "Wed, 28 Oct 2026 00:00:00 GMT" } });
    assert.equal(later.status, 304);
    const earlier = await call(env, "/updates/Nonet-1.2.0.dmg", { headers: { "if-modified-since": "Tue, 27 Oct 2026 01:14:59 GMT" } });
    assert.equal(earlier.status, 200);
    const broken = await call(env, "/updates/Nonet-1.2.0.dmg", { headers: { "if-modified-since": "yesterday" } });
    assert.equal(broken.status, 200);
  });

  test("上げ直して中身が変わったら、前の ETag では 304 にならない", async () => {
    const env = envWithRelease();
    const before = `"${env.UPDATES.objects.get("Nonet-1.2.0.dmg").etag}"`;
    env.UPDATES.put("Nonet-1.2.0.dmg", "rebuilt", new Date("2026-10-28T00:00:00Z"));
    const response = await call(env, "/updates/Nonet-1.2.0.dmg", { headers: { "if-none-match": before } });
    assert.equal(response.status, 200);
    assert.equal(await response.text(), "rebuilt");
  });
});

describe("範囲の要求（DMG とデルタの続きから）", () => {
  test("bytes=始め-終わり は 206 と Content-Range", async () => {
    const env = envWithRelease();
    const response = await call(env, "/updates/Nonet-1.2.0.dmg", { headers: { range: "bytes=10-19" } });
    assert.equal(response.status, 206);
    assert.equal(response.headers.get("content-range"), "bytes 10-19/1000");
    assert.equal(response.headers.get("content-length"), "10");
    assert.deepEqual(await bodyBytes(response), DMG.slice(10, 20));
  });

  test("bytes=始め- と bytes=-末尾、ファイルを超える終わりは切り詰める", async () => {
    const env = envWithRelease();
    const open = await call(env, "/updates/Nonet-1.2.0.dmg", { headers: { range: "bytes=990-" } });
    assert.equal(open.status, 206);
    assert.equal(open.headers.get("content-range"), "bytes 990-999/1000");
    assert.deepEqual(await bodyBytes(open), DMG.slice(990));

    const suffix = await call(env, "/updates/Nonet-1.2.0.dmg", { headers: { range: "bytes=-5" } });
    assert.equal(suffix.headers.get("content-range"), "bytes 995-999/1000");
    assert.deepEqual(await bodyBytes(suffix), DMG.slice(995));

    const beyond = await call(env, "/updates/Nonet-1.2.0.dmg", { headers: { range: "bytes=500-999999" } });
    assert.equal(beyond.headers.get("content-range"), "bytes 500-999/1000");
    assert.equal(beyond.headers.get("content-length"), "500");

    const longSuffix = await call(env, "/updates/Nonet-1.2.0.dmg", { headers: { range: "bytes=-5000" } });
    assert.equal(longSuffix.headers.get("content-range"), "bytes 0-999/1000");
  });

  test("ファイルの外の範囲は 416 と Content-Range: bytes */大きさ", async () => {
    const env = envWithRelease();
    for (const range of ["bytes=1000-", "bytes=5000-6000", "bytes=-0"]) {
      const response = await call(env, "/updates/Nonet-1.2.0.dmg", { headers: { range } });
      assert.equal(response.status, 416, range);
      assert.equal(response.headers.get("content-range"), "bytes */1000");
      assert.equal(response.body, null);
    }
  });

  test("読めない形と複数の範囲は無視して全体を 200 で返す", async () => {
    const env = envWithRelease();
    for (const range of ["bytes=0-1,4-5", "items=0-1", "bytes=5-2", "bytes=-", "bytes=a-b", "bytes 0-1"]) {
      const response = await call(env, "/updates/Nonet-1.2.0.dmg", { headers: { range } });
      assert.equal(response.status, 200, range);
      assert.equal(response.headers.get("content-length"), "1000", range);
    }
  });

  test("HEAD と Range は 206 のヘッダだけ", async () => {
    const env = envWithRelease();
    const response = await call(env, "/updates/Nonet-1.2.0.dmg", { method: "HEAD", headers: { range: "bytes=0-99" } });
    assert.equal(response.status, 206);
    assert.equal(response.headers.get("content-length"), "100");
    assert.equal(response.body, null);
  });

  test("If-Range が今の中身を指すときだけ範囲に従う", async () => {
    const env = envWithRelease();
    const etag = `"${env.UPDATES.objects.get("Nonet-1.2.0.dmg").etag}"`;
    const cases = [
      [etag, 206],
      ['"old"', 200],
      [`W/${etag}`, 200],
      [LAST_MODIFIED, 206],
      ["Mon, 26 Oct 2026 00:00:00 GMT", 200],
    ];
    for (const [ifRange, status] of cases) {
      const response = await call(env, "/updates/Nonet-1.2.0.dmg", { headers: { range: "bytes=0-9", "if-range": ifRange } });
      assert.equal(response.status, status, ifRange);
    }
  });

  test("parseRange の境目", () => {
    assert.deepEqual(parseRange("bytes=0-0", 1), { start: 0, end: 0 });
    assert.deepEqual(parseRange("BYTES=0-", 3), { start: 0, end: 2 });
    assert.equal(parseRange("bytes=0-", 0), UNSATISFIABLE);
    assert.equal(parseRange("bytes=-1", 0), UNSATISFIABLE);
    assert.equal(parseRange("bytes=99999999999999999999-", 10), UNSATISFIABLE);
    assert.equal(parseRange("bytes=1-2, 3-4", 10), null);
  });
});

describe("読んでいる間の差し替え", () => {
  test("head のあとに上げ直されたら、新しい中身と ETag で返す（古いヘッダに新しい本文を付けない）", async () => {
    const env = envWithRelease();
    env.UPDATES.afterHead = (bucket) => bucket.put("Nonet-1.2.0.dmg", "rebuilt", new Date("2026-10-28T00:00:00Z"));
    const response = await call(env, "/updates/Nonet-1.2.0.dmg");
    assert.equal(response.status, 200);
    assert.equal(await response.text(), "rebuilt");
    assert.equal(response.headers.get("etag"), `"${env.UPDATES.objects.get("Nonet-1.2.0.dmg").etag}"`);
    assert.equal(response.headers.get("content-length"), "7");
  });

  test("head と get の間に消されたら 404", async () => {
    const env = envWithRelease();
    env.UPDATES.afterHead = (bucket) => bucket.objects.delete("Nonet-1.2.0.dmg");
    const response = await call(env, "/updates/Nonet-1.2.0.dmg");
    assert.equal(response.status, 404);
  });
});

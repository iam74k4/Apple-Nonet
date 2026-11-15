// /download: appcast の最新の DMG へのリダイレクト（src/download.js）
import assert from "node:assert/strict";
import { afterEach, beforeEach, describe, test } from "node:test";

import { ownDiskImageName } from "../src/download.js";
import { call, fixture, makeEnv } from "./support.js";

let errors;
const originalError = console.error;
beforeEach(() => {
  errors = [];
  console.error = (...args) => errors.push(args.join(" "));
});
afterEach(() => {
  console.error = originalError;
});

function envWith(appcastXml, dmgs = ["Nonet-1.2.0.dmg"]) {
  const env = makeEnv();
  if (appcastXml !== null) {
    env.UPDATES.put("appcast.xml", appcastXml);
  }
  for (const name of dmgs) {
    env.UPDATES.put(name, "dmg");
  }
  return env;
}

function appcastWithNewest(url) {
  return fixture("appcast.xml").replace("https://nonet.astlog.dev/updates/Nonet-1.2.0.dmg", url);
}

const EMPTY_APPCAST =
  '<?xml version="1.0" standalone="yes"?>\n<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n    <channel>\n        <title>Nonet</title>\n    </channel>\n</rss>\n';

describe("リダイレクト", () => {
  test("既定のチャンネルで最新の DMG へ 302、写しは残させない", async () => {
    const env = envWith(fixture("appcast.xml"));
    const response = await call(env, "/download");
    assert.equal(response.status, 302);
    assert.equal(response.headers.get("location"), "https://nonet.astlog.dev/updates/Nonet-1.2.0.dmg");
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.equal(response.headers.get("x-content-type-options"), "nosniff");
    assert.deepEqual(errors, []);
  });

  test("HEAD も 302（本文なし）", async () => {
    const env = envWith(fixture("appcast.xml"));
    const response = await call(env, "/download", { method: "HEAD" });
    assert.equal(response.status, 302);
    assert.equal(response.body, null);
    assert.equal(response.headers.get("location"), "https://nonet.astlog.dev/updates/Nonet-1.2.0.dmg");
  });

  test("クエリが付いていても同じ", async () => {
    const env = envWith(fixture("appcast.xml"));
    const response = await call(env, "/download?from=ja");
    assert.equal(response.headers.get("location"), "https://nonet.astlog.dev/updates/Nonet-1.2.0.dmg");
  });

  test("GET と HEAD のほかは 405", async () => {
    const env = envWith(fixture("appcast.xml"));
    const response = await call(env, "/download", { method: "POST" });
    assert.equal(response.status, 405);
    assert.equal(response.headers.get("allow"), "GET, HEAD");
  });
});

describe("まだ出していないとき", () => {
  for (const [name, xml] of [
    ["appcast が無い", null],
    ["項目が無い", EMPTY_APPCAST],
    ["ベータの項目しか無い", fixture("appcast.xml").replace(/<item>\s*<title>1\.2\.0[\s\S]*<\/item>/, "")],
  ]) {
    test(`${name}: サイトの 404 ページを 404 で返す`, async () => {
      const env = envWith(xml, []);
      const response = await call(env, "/download");
      assert.equal(response.status, 404);
      assert.equal(response.headers.get("cache-control"), "no-store");
      assert.match(response.headers.get("content-type"), /^text\/html/);
      assert.match(await response.text(), /ページが見つかりません/);
      assert.deepEqual(env.ASSETS.requests.map(({ pathname }) => pathname), ["/404.html"]);
      assert.equal(response.headers.get("location"), null);
    });
  }

  test("HEAD なら本文なしの 404", async () => {
    const env = envWith(null, []);
    const response = await call(env, "/download", { method: "HEAD" });
    assert.equal(response.status, 404);
    assert.equal(response.body, null);
  });
});

describe("こちらの誤りは 503（ほかの場所へは飛ばさない）", () => {
  test("appcast が壊れている", async () => {
    const env = envWith("<html><body>Not Found</body></html>");
    const response = await call(env, "/download");
    assert.equal(response.status, 503);
    assert.equal(response.headers.get("location"), null);
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.match(errors.join("\n"), /appcast.xml を読めません/);
  });

  test("appcast が大きすぎる", async () => {
    const env = envWith(fixture("appcast.xml").replace("<title>Nonet</title>", `<title>${"x".repeat(1024 * 1024)}</title>`));
    const response = await call(env, "/download");
    assert.equal(response.status, 503);
  });

  test("最新の DMG が R2 に無い（appcast を先に上げてしまった）", async () => {
    const env = envWith(fixture("appcast.xml"), ["Nonet-1.1.1.dmg"]);
    const response = await call(env, "/download");
    assert.equal(response.status, 503);
    assert.match(errors.join("\n"), /Nonet-1\.2\.0\.dmg が R2 にありません/);
  });

  const outside = [
    "https://evil.example/Nonet-1.2.0.dmg",
    "https://evil.example/updates/Nonet-1.2.0.dmg",
    "https://nonet.astlog.dev.evil.example/updates/Nonet-1.2.0.dmg",
    "https://nonet.astlog.dev@evil.example/updates/Nonet-1.2.0.dmg",
    "http://nonet.astlog.dev/updates/Nonet-1.2.0.dmg",
    "//evil.example/updates/Nonet-1.2.0.dmg",
    "/updates/Nonet-1.2.0.dmg",
    "https://NONET.astlog.dev/updates/Nonet-1.2.0.dmg",
    "https://nonet.astlog.dev:8443/updates/Nonet-1.2.0.dmg",
    "https://nonet.astlog.dev/updates/../download",
    "https://nonet.astlog.dev/updates/%2e%2e/evil.dmg",
    "https://nonet.astlog.dev/updates/x/Nonet-1.2.0.dmg",
    "https://nonet.astlog.dev/updates/Nonet-1.2.0.dmg?next=https://evil.example/",
    "https://nonet.astlog.dev/updates/Nonet-1.2.0.dmg#x",
    "https://nonet.astlog.dev/updates/Nonet42-41.delta",
    "https://nonet.astlog.dev/updates/appcast.xml",
    "https://nonet.astlog.dev/download",
    "javascript:alert(1)",
  ];
  for (const url of outside) {
    test(`最新の項目の URL が ${url}`, async () => {
      const env = envWith(appcastWithNewest(url.replaceAll("&", "&amp;")));
      const response = await call(env, "/download");
      assert.equal(response.status, 503);
      assert.equal(response.headers.get("location"), null);
      assert.match(errors.join("\n"), /DMG ではありません/);
    });
  }

  test("ownDiskImageName は /updates/ の DMG の名前だけを返す", () => {
    assert.equal(ownDiskImageName("https://nonet.astlog.dev/updates/Nonet-1.2.0.dmg"), "Nonet-1.2.0.dmg");
    assert.equal(ownDiskImageName("https://nonet.astlog.dev/updates/Nonet-1.2.dmg"), "Nonet-1.2.dmg");
    for (const url of outside) {
      assert.equal(ownDiskImageName(url), null, url);
    }
    assert.equal(ownDiskImageName(null), null);
  });
});

describe("R2 が一時的に失敗したとき", () => {
  test("/download は例外のページではなく 503 と Retry-After で返し、理由をログに残す", async () => {
    const env = envWith(fixture("appcast.xml"));
    env.UPDATES.get = async () => {
      throw new Error("R2 internal error");
    };
    const response = await call(env, "/download");
    assert.equal(response.status, 503);
    assert.equal(response.headers.get("retry-after"), "300");
    assert.ok(errors.some((line) => line.includes("R2 internal error")));
  });

  test("/updates/* も 503 と Retry-After で返す", async () => {
    const env = envWith(fixture("appcast.xml"));
    env.UPDATES.head = async () => {
      throw new Error("R2 internal error");
    };
    const response = await call(env, "/updates/Nonet-1.2.0.dmg");
    assert.equal(response.status, 503);
    assert.equal(response.headers.get("retry-after"), "5");
    assert.ok(errors.some((line) => line.includes("R2 internal error")));
  });
});

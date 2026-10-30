// 販売ページ: Worker が引くトップ（src/site.js）と、site/_headers の CSP・404 ページが今のページに合っているか
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, test } from "node:test";

import { call, makeEnv, ORIGIN, SITE_DIR } from "./support.js";

describe("トップのページ", () => {
  test("/ は index.html を、/en/ は en/index.html を 200 で返す（リダイレクトしない）", async () => {
    const env = makeEnv();
    const ja = await call(env, "/");
    assert.equal(ja.status, 200);
    assert.match(await ja.text(), /<html lang="ja">/);
    const en = await call(env, "/en/?utm_source=x");
    assert.equal(en.status, 200);
    assert.match(await en.text(), /<html lang="en">/);
    assert.deepEqual(env.ASSETS.requests.map(({ pathname }) => pathname), ["/index.html", "/en/index.html"]);
  });

  test("メソッドと条件つきのヘッダをアセットにそのまま渡す（HEAD・304）", async () => {
    const env = makeEnv();
    const head = await call(env, "/", { method: "HEAD" });
    assert.equal(head.status, 200);
    assert.equal(head.body, null);
    const etag = head.headers.get("etag");
    const revalidated = await call(env, "/", { headers: { "if-none-match": etag } });
    assert.equal(revalidated.status, 304);
    assert.equal(env.ASSETS.requests[0].method, "HEAD");
  });

  test("/en は /en/ へ 301（クエリは残す）", async () => {
    const env = makeEnv();
    const response = await call(env, "/en?ref=app");
    assert.equal(response.status, 301);
    assert.equal(response.headers.get("location"), "/en/?ref=app");
    assert.equal(env.ASSETS.requests.length, 0);
  });

  test("run_worker_first から外れたパスが来ても、アセットの決まり（404 ページ）に任せる", async () => {
    const env = makeEnv();
    const response = await call(env, "/no-such-page");
    assert.equal(response.status, 404);
    assert.match(await response.text(), /ページが見つかりません/);
  });
});

// --- site/_headers の CSP が、今のページで何も止めないこと（ブラウザで開く代わりに、HTML を見て確かめる）

function siteFiles(extension) {
  const files = [];
  const walk = (directory) => {
    for (const name of readdirSync(directory)) {
      const path = join(directory, name);
      if (statSync(path).isDirectory()) {
        walk(path);
      } else if (name.endsWith(extension)) {
        files.push(path);
      }
    }
  };
  walk(SITE_DIR);
  return files.sort();
}

function headerRules() {
  const rules = new Map();
  let current = null;
  for (const raw of readFileSync(join(SITE_DIR, "_headers"), "utf8").split("\n")) {
    const line = raw.trim();
    if (line === "" || line.startsWith("#")) {
      continue;
    }
    if (line.startsWith("/")) {
      current = new Map();
      rules.set(line, current);
    } else if (line.startsWith("! ")) {
      current.set(line.slice(2).toLowerCase(), null);
    } else {
      const separator = line.indexOf(":");
      current.set(line.slice(0, separator).trim().toLowerCase(), line.slice(separator + 1).trim());
    }
  }
  return rules;
}

function parsePolicy(value) {
  const directives = new Map();
  for (const part of value.split(";")) {
    const [name, ...sources] = part.trim().split(/\s+/);
    if (name) {
      directives.set(name, sources);
    }
  }
  return directives;
}

const pagePolicy = parsePolicy(headerRules().get("/*").get("content-security-policy"));

function sourcesFor(directive) {
  const fallbacks = {
    "script-src-elem": ["script-src-elem", "script-src", "default-src"],
    "style-src-elem": ["style-src-elem", "style-src", "default-src"],
    "style-src-attr": ["style-src-attr", "style-src", "default-src"],
    "img-src": ["img-src", "default-src"],
    "font-src": ["font-src", "default-src"],
    "frame-src": ["frame-src", "child-src", "default-src"],
    "media-src": ["media-src", "default-src"],
  };
  for (const name of fallbacks[directive]) {
    if (pagePolicy.has(name)) {
      return pagePolicy.get(name);
    }
  }
  return [];
}

// 同じオリジンの相対の URL か（'self' で通る）
function isSameOrigin(url, page) {
  return new URL(url, `${ORIGIN}/${page}`).origin === ORIGIN;
}

describe("site/_headers", () => {
  test("ページ全体に nosniff・Referrer-Policy・Permissions-Policy・frame-ancestors 'none' を付ける", () => {
    const all = headerRules().get("/*");
    assert.equal(all.get("x-content-type-options"), "nosniff");
    assert.equal(all.get("referrer-policy"), "strict-origin-when-cross-origin");
    assert.match(all.get("permissions-policy"), /camera=\(\)/);
    assert.deepEqual(pagePolicy.get("frame-ancestors"), ["'none'"]);
    assert.deepEqual(pagePolicy.get("default-src"), ["'none'"]);
    assert.equal(sourcesFor("script-src-elem").includes("'unsafe-inline'"), false);
  });

  for (const file of siteFiles(".html")) {
    const page = relative(SITE_DIR, file);
    test(`${page} は CSP で止まるものを使っていない`, () => {
      const html = readFileSync(file, "utf8").replace(/<!--[\s\S]*?-->/g, "");
      for (const [, attributes, body] of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)) {
        const src = /\ssrc="([^"]+)"/.exec(attributes);
        assert.ok(src !== null && body.trim() === "", `${page}: インラインのスクリプトは使えない（script-src 'self'）`);
        assert.ok(isSameOrigin(src[1], page) && sourcesFor("script-src-elem").includes("'self'"), `${page}: ${src[1]}`);
      }
      assert.doesNotMatch(html, /\son[a-z]+\s*=/i, `${page}: イベント属性（onclick など）は使えない`);
      assert.doesNotMatch(html, /href\s*=\s*["']?\s*javascript:/i, `${page}: javascript: の URL は使えない`);
      if (/<style[\s>]/i.test(html)) {
        assert.ok(sourcesFor("style-src-elem").includes("'unsafe-inline'"), `${page}: <style> は style-src-elem で止まる`);
      }
      if (/\sstyle\s*=/i.test(html)) {
        assert.ok(sourcesFor("style-src-attr").includes("'unsafe-inline'"), `${page}: style 属性が style-src-attr で止まる`);
      }
      for (const [, rel, href] of html.matchAll(/<link\b[^>]*\brel="([^"]+)"[^>]*\bhref="([^"]+)"/g)) {
        const directive = { stylesheet: "style-src-elem", icon: "img-src" }[rel];
        if (directive !== undefined) {
          assert.ok(isSameOrigin(href, page) && sourcesFor(directive).includes("'self'"), `${page}: <link rel=${rel}> ${href}`);
        }
      }
      for (const [, tag, src] of html.matchAll(/<(img|iframe|video|audio|source|embed|object)\b[^>]*\b(?:src|data)="([^"]+)"/g)) {
        const directive = { img: "img-src", iframe: "frame-src", video: "media-src", audio: "media-src", source: "media-src" }[tag] ?? "default-src";
        assert.ok(directive !== "default-src" && isSameOrigin(src, page) && sourcesFor(directive).includes("'self'"), `${page}: <${tag}> ${src}`);
      }
      for (const [, href] of html.matchAll(/<base\b[^>]*\bhref="([^"]+)"/g)) {
        assert.ok(isSameOrigin(href, page) && pagePolicy.get("base-uri")?.includes("'self'"), `${page}: <base href="${href}">`);
      }
      assert.doesNotMatch(html, /<form\b/i, `${page}: フォームは form-action 'none' で止まる`);
    });
  }

  test("style.css は外のフォントや画像を読まない（font-src・img-src の 'self' の外）", () => {
    for (const file of siteFiles(".css")) {
      const css = readFileSync(file, "utf8");
      for (const [, url] of css.matchAll(/url\(\s*["']?([^"')]+)/g)) {
        assert.ok(url.startsWith("#") || isSameOrigin(url, relative(SITE_DIR, file)), url);
      }
      assert.doesNotMatch(css, /@import/);
    }
  });

  test("script.js は eval や外への通信を使わない（script-src に 'unsafe-eval' も connect-src も無い）", () => {
    const script = readFileSync(join(SITE_DIR, "script.js"), "utf8");
    assert.doesNotMatch(script, /\beval\(|new Function\(|\bfetch\(|XMLHttpRequest|WebSocket|EventSource/);
    assert.doesNotMatch(script, /setAttribute\(\s*["']style["']/);
  });

  test("favicon.svg は中の <style> だけを許す CSP に差し替える", () => {
    const favicon = headerRules().get("/favicon.svg");
    assert.equal(favicon.get("content-security-policy"), "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; sandbox");
  });
});

// --- 404 ページ: 無いパスならどの深さでも出るので、リンクと読み込みがどこから開いても届くこと

describe("404 ページ", () => {
  const cases = [
    ["404.html", ["/no-such-page", "/a/b/c/", "/download"]],
    ["en/404.html", ["/en/no-such-page", "/en/a/b/c/"]],
  ];
  for (const [page, paths] of cases) {
    test(`${page} のリンクは、どの深さで出ても site/ のファイルを指す`, () => {
      const html = readFileSync(join(SITE_DIR, page), "utf8").replace(/<!--[\s\S]*?-->/g, "");
      const base = /<base\s+href="([^"]+)">/.exec(html);
      assert.ok(base !== null, `${page} に <base> がありません`);
      assert.doesNotMatch(html, /\s(?:href|src)="#/, `${page}: <base> の下では # だけのリンクがトップを指してしまう`);
      const urls = [...html.matchAll(/<(?!base\b)[a-z]+\b[^>]*\s(?:href|src)="([^"]+)"/g)].map((match) => match[1]);
      assert.ok(urls.length >= 4, `${page}: リンクが少なすぎます`);
      for (const path of paths) {
        const documentUrl = new URL(path, ORIGIN);
        const baseUrl = new URL(base[1], documentUrl);
        for (const url of urls) {
          const target = new URL(url, baseUrl);
          assert.equal(target.origin, ORIGIN, `${page} を ${path} で開いたとき: ${url}`);
          let file = join(SITE_DIR, decodeURIComponent(target.pathname));
          if (target.pathname.endsWith("/")) {
            file = join(file, "index.html");
          }
          assert.ok(existsSync(file), `${page} を ${path} で開いたとき: ${url} → ${target.pathname} がありません`);
        }
      }
    });
  }

  test("英語の 404 ページは英語のトップへ、日本語の 404 ページは日本語のトップへ戻す", () => {
    const ja = readFileSync(join(SITE_DIR, "404.html"), "utf8");
    const en = readFileSync(join(SITE_DIR, "en", "404.html"), "utf8");
    assert.match(ja, /<a class="btn" href="\.\/">/);
    assert.match(en, /<a class="btn" href="\.\.\/en\/">/);
    assert.match(ja, /<meta name="robots" content="noindex">/);
    assert.match(en, /<meta name="robots" content="noindex">/);
  });
});

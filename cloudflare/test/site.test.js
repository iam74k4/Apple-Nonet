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

const rules = headerRules();
const pagePolicy = parsePolicy(rules.get("/*").get("content-security-policy"));
// 購入のページ（Paddle.js で購入画面を開く）。この2つだけ CSP を差し替える
const PURCHASE_PAGES = ["buy.html", "en/buy.html"];
const PADDLE_SCRIPT = "https://cdn.paddle.com/paddle/v2/paddle.js";

// ページに付く CSP。そのページのルールが CSP を差し替えていれば（! で外して付け直す）そちら、無ければ /* のもの
function policyFor(page) {
  const value = rules.get(`/${page}`)?.get("content-security-policy");
  return value ? parsePolicy(value) : pagePolicy;
}

function sourcesFor(directive, policy = pagePolicy) {
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
    if (policy.has(name)) {
      return policy.get(name);
    }
  }
  return [];
}

// 同じオリジンの相対の URL か（'self' で通る）
function isSameOrigin(url, page) {
  return new URL(url, `${ORIGIN}/${page}`).origin === ORIGIN;
}

// ソースの一覧で通るか（同じオリジンなら 'self'、ほかはそのオリジンが書いてある）
function isAllowed(url, page, sources) {
  const target = new URL(url, `${ORIGIN}/${page}`);
  return target.origin === ORIGIN ? sources.includes("'self'") : sources.includes(target.origin);
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
      const policy = policyFor(page);
      const sources = (directive) => sourcesFor(directive, policy);
      for (const [, attributes, body] of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)) {
        // 検索エンジン向けの構造化データ（JSON-LD）は、ブラウザが実行しないデータなので script-src に関係しない。
        // その形のものだけを許し、中身が JSON として読めることを確かめる
        if (/^\s+type="application\/ld\+json"$/.test(attributes)) {
          assert.doesNotThrow(() => JSON.parse(body), `${page}: JSON-LD が JSON として読めません`);
          continue;
        }
        const src = /\ssrc="([^"]+)"/.exec(attributes);
        assert.ok(src !== null && body.trim() === "", `${page}: インラインのスクリプトは使えない（script-src 'self'）`);
        assert.ok(isAllowed(src[1], page, sources("script-src-elem")), `${page}: ${src[1]}`);
      }
      assert.doesNotMatch(html, /\son[a-z]+\s*=/i, `${page}: イベント属性（onclick など）は使えない`);
      assert.doesNotMatch(html, /href\s*=\s*["']?\s*javascript:/i, `${page}: javascript: の URL は使えない`);
      if (/<style[\s>]/i.test(html)) {
        assert.ok(sources("style-src-elem").includes("'unsafe-inline'"), `${page}: <style> は style-src-elem で止まる`);
      }
      if (/\sstyle\s*=/i.test(html)) {
        assert.ok(sources("style-src-attr").includes("'unsafe-inline'"), `${page}: style 属性が style-src-attr で止まる`);
      }
      for (const [, rel, href] of html.matchAll(/<link\b[^>]*\brel="([^"]+)"[^>]*\bhref="([^"]+)"/g)) {
        const directive = { stylesheet: "style-src-elem", icon: "img-src", "apple-touch-icon": "img-src" }[rel];
        if (directive !== undefined) {
          assert.ok(isSameOrigin(href, page) && sources(directive).includes("'self'"), `${page}: <link rel=${rel}> ${href}`);
        }
      }
      for (const [, tag, src] of html.matchAll(/<(img|iframe|video|audio|source|embed|object)\b[^>]*\b(?:src|data)="([^"]+)"/g)) {
        const directive = { img: "img-src", iframe: "frame-src", video: "media-src", audio: "media-src", source: "media-src" }[tag] ?? "default-src";
        assert.ok(directive !== "default-src" && isSameOrigin(src, page) && sources(directive).includes("'self'"), `${page}: <${tag}> ${src}`);
      }
      for (const [, href] of html.matchAll(/<base\b[^>]*\bhref="([^"]+)"/g)) {
        assert.ok(isSameOrigin(href, page) && policy.get("base-uri")?.includes("'self'"), `${page}: <base href="${href}">`);
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

  test("script.js と buy.js は eval や外への通信を使わない（script-src に 'unsafe-eval' も connect-src も無い）", () => {
    for (const name of ["script.js", "buy.js"]) {
      const script = readFileSync(join(SITE_DIR, name), "utf8");
      assert.doesNotMatch(script, /\beval\(|new Function\(|\bfetch\(|XMLHttpRequest|WebSocket|EventSource/, name);
      assert.doesNotMatch(script, /setAttribute\(\s*["']style["']/, name);
    }
  });

  test("外のスクリプトを許すのは購入のページだけで、許すのは Paddle.js だけ", () => {
    for (const file of siteFiles(".html")) {
      const page = relative(SITE_DIR, file);
      const policy = policyFor(page);
      const outside = sourcesFor("script-src-elem", policy).filter((source) => source.startsWith("https:"));
      assert.deepEqual(outside, PURCHASE_PAGES.includes(page) ? ["https://cdn.paddle.com"] : [], page);
      assert.equal(sourcesFor("script-src-elem", policy).includes("'unsafe-inline'"), false, page);
      assert.equal(sourcesFor("script-src-elem", policy).includes("'unsafe-eval'"), false, page);
      const html = readFileSync(file, "utf8");
      assert.equal(html.includes(PADDLE_SCRIPT), PURCHASE_PAGES.includes(page), `${page}: Paddle.js を読むのは購入のページだけ`);
    }
  });

  test("購入のページの CSP は、Paddle の購入画面に要るものだけを足す（2つのページで同じ）", () => {
    const raw = readFileSync(join(SITE_DIR, "_headers"), "utf8");
    const [ja, en] = PURCHASE_PAGES.map((page) => rules.get(`/${page}`));
    assert.ok(ja && en, "_headers に /buy.html と /en/buy.html のルールがありません");
    assert.deepEqual([...en], [...ja]);
    for (const page of PURCHASE_PAGES) {
      // /* の CSP と Permissions-Policy を外してから付け直す（付け足すと2つの CSP が両方効いて、厳しいほうで止まる）
      assert.match(raw, new RegExp(`^/${page.replace(".", "\\.")}\n  ! Content-Security-Policy\n  ! Permissions-Policy\n`, "m"), page);
    }
    const policy = policyFor("buy.html");
    assert.deepEqual(policy.get("default-src"), ["'none'"]);
    assert.deepEqual(policy.get("script-src"), ["'self'", "https://cdn.paddle.com"]);
    assert.deepEqual(policy.get("frame-src"), ["https://buy.paddle.com", "https://sandbox-buy.paddle.com", "https://cdn.paddle.com", "https://sandbox-cdn.paddle.com"]);
    assert.deepEqual(policy.get("style-src-elem"), ["'self'", "'unsafe-inline'", "https://cdn.paddle.com", "https://sandbox-cdn.paddle.com"]);
    assert.deepEqual(policy.get("img-src"), ["'self'"]);
    assert.equal(policy.has("connect-src"), false, "connect-src は要らない（購入画面の通信は枠の中のページが行う）");
    // ほかは /* と同じ
    for (const name of ["style-src-attr", "font-src", "manifest-src", "base-uri", "form-action", "frame-ancestors"]) {
      assert.deepEqual(policy.get(name), pagePolicy.get(name), name);
    }
    // 決済（Apple Pay など）は Paddle の購入画面の枠にだけ許し、ほかの機能は /* と同じく止める
    const permissions = ja.get("permissions-policy");
    assert.match(permissions, /(^|, )payment=\("https:\/\/buy\.paddle\.com" "https:\/\/sandbox-buy\.paddle\.com"\)(,|$)/);
    assert.equal(permissions.replace(/payment=\([^)]*\)/, "payment=()"), rules.get("/*").get("permissions-policy"));
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

// --- 検索と共有: robots.txt・sitemap.xml・構造化データ・og:image が、Worker とアセットの決まりのまま届くこと

function workerFirstPaths() {
  const toml = readFileSync(join(SITE_DIR, "..", "cloudflare", "wrangler.toml"), "utf8");
  const line = /^run_worker_first\s*=\s*\[(.*)\]$/m.exec(toml);
  assert.ok(line !== null, "wrangler.toml に run_worker_first がありません");
  return [...line[1].matchAll(/"([^"]+)"/g)].map((match) => match[1]);
}

function isNoindex(html) {
  return /<meta name="robots" content="[^"]*noindex/.test(html);
}

// site/ の中の HTML のパス（index.html はフォルダの URL）
function pagePath(file) {
  const rel = relative(SITE_DIR, file).split("\\").join("/");
  return `/${rel.replace(/(^|\/)index\.html$/, "$1")}`;
}

describe("検索と共有", () => {
  test("robots.txt は Worker が DMG・appcast を返すパスをクロールさせず、sitemap.xml を絶対の URL で指す", () => {
    const robots = readFileSync(join(SITE_DIR, "robots.txt"), "utf8");
    assert.match(robots, /^User-agent: \*$/m);
    assert.match(robots, /^Disallow: \/download$/m);
    assert.match(robots, /^Disallow: \/updates\/$/m);
    assert.match(robots, new RegExp(`^Sitemap: ${ORIGIN}/sitemap.xml$`, "m"));
    // 隠すのは Worker のパスだけ（ページはクロールさせる）
    for (const [, path] of robots.matchAll(/^Disallow: (\S+)$/gm)) {
      assert.ok(workerFirstPaths().some((worker) => worker === path || worker === `${path}*`), `Disallow: ${path} は Worker のパスではありません`);
    }
  });

  test("sitemap.xml の URL はどれも、Worker とアセットから 200 の HTML で返る（リダイレクトしない）", async () => {
    const sitemap = readFileSync(join(SITE_DIR, "sitemap.xml"), "utf8");
    const urls = new Set([...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g), ...sitemap.matchAll(/\shref="([^"]+)"/g)].map((match) => match[1]));
    assert.ok(urls.size >= 9, "sitemap.xml の URL が少なすぎます");
    for (const url of urls) {
      assert.ok(url.startsWith(`${ORIGIN}/`), url);
      const response = await call(makeEnv(), new URL(url).pathname);
      assert.equal(response.status, 200, url);
      assert.match(response.headers.get("content-type"), /^text\/html/, url);
      assert.equal(isNoindex(await response.text()), false, `${url} は noindex なので sitemap.xml に入れない`);
    }
  });

  test("検索に出すページは、すべて sitemap.xml にある", () => {
    const listed = new Set([...readFileSync(join(SITE_DIR, "sitemap.xml"), "utf8").matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1]));
    for (const file of siteFiles(".html")) {
      if (!isNoindex(readFileSync(file, "utf8"))) {
        assert.ok(listed.has(ORIGIN + pagePath(file)), `${relative(SITE_DIR, file)} が sitemap.xml にありません`);
      }
    }
  });

  for (const page of ["index.html", "en/index.html"]) {
    test(`${page} の構造化データ（SoftwareApplication）はページと同じ言語・URL で、価格が決まるまで offers を書かない`, () => {
      const html = readFileSync(join(SITE_DIR, page), "utf8");
      const blocks = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
      assert.equal(blocks.length, 1, `${page}: JSON-LD は1つ`);
      const data = JSON.parse(blocks[0][1]);
      const lang = /<html lang="([a-z]+)">/.exec(html)[1];
      const canonical = /<link rel="canonical" href="([^"]+)">/.exec(html)[1];
      assert.equal(data["@context"], "https://schema.org");
      assert.equal(data["@type"], "SoftwareApplication");
      assert.equal(data.name, "Nonet");
      assert.equal(data.inLanguage, lang);
      assert.equal(data.url, canonical);
      assert.equal(data.applicationCategory, "UtilitiesApplication");
      assert.match(data.operatingSystem, /macOS 14/);
      assert.equal(data.downloadUrl, `${ORIGIN}/download`);
      assert.ok(existsSync(join(SITE_DIR, new URL(data.image).pathname)), `${page}: ${data.image} がありません`);
      if ("offers" in data) {
        // 価格を足したら、仮の値ではなく本物の値段と通貨を書く
        assert.match(String(data.offers.price), /^\d+(\.\d+)?$/);
        assert.match(data.offers.priceCurrency, /^[A-Z]{3}$/);
      }
    });
  }

  test("共有の画像（og:image）と apple-touch-icon は、このサイトの PNG", async () => {
    for (const file of siteFiles(".html")) {
      const html = readFileSync(file, "utf8");
      const image = /<meta property="og:image" content="([^"]+)">/.exec(html);
      if (image === null) {
        continue;
      }
      assert.ok(image[1].startsWith(`${ORIGIN}/images/`), `${relative(SITE_DIR, file)}: ${image[1]}`);
      const response = await call(makeEnv(), new URL(image[1]).pathname);
      assert.equal(response.status, 200, image[1]);
      const bytes = new Uint8Array(await response.arrayBuffer());
      assert.deepEqual([...bytes.slice(0, 4)], [0x89, 0x50, 0x4e, 0x47], `${image[1]} は PNG`);
    }
    const icon = await call(makeEnv(), "/apple-touch-icon.png");
    assert.equal(icon.status, 200);
  });
});

// --- ダウンロードのページ（thanks.html）: 開くのは Worker の /download だけ（ほかのサイトへは飛ばない）

describe("ダウンロードのページ", () => {
  for (const page of ["thanks.html", "en/thanks.html"]) {
    test(`${page} は検索に出さず、Worker の /download だけを開く`, async () => {
      const html = readFileSync(join(SITE_DIR, page), "utf8");
      assert.ok(isNoindex(html), `${page} は noindex`);
      const refresh = /<noscript><meta http-equiv="refresh" content="(\d+); url=([^"]+)"><\/noscript>/.exec(html);
      assert.ok(refresh !== null, `${page}: JavaScript が無いときのダウンロード（noscript の meta refresh）がありません`);
      const link = /<a href="([^"]+)" data-download-link>/.exec(html);
      assert.ok(link !== null, `${page}: data-download-link がありません`);
      for (const url of [refresh[2], link[1]]) {
        assert.equal(url, `${ORIGIN}/download`);
      }
      assert.ok(workerFirstPaths().includes("/download"), "/download は Worker が答える（run_worker_first）");
      const response = await call(makeEnv(), `/${page}`);
      assert.equal(response.status, 200);
    });
  }

  test("販売ページのボタンはダウンロードのページを指し、DMG を直に落とさない", () => {
    for (const page of ["index.html", "en/index.html"]) {
      const html = readFileSync(join(SITE_DIR, page), "utf8");
      assert.doesNotMatch(html, /href="https:\/\/nonet\.astlog\.dev\/(download|updates\/)/, page);
      assert.match(html, /<a class="btn" href="thanks\.html">/, page);
    }
  });
});

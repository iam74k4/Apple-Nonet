// テストの道具。本物の R2 と静的アセットの代わりに、同じ形の小さな偽物を使う（追加の依存は入れない）。
//   FakeBucket  R2 のバインディング（head / get と onlyIf・range）。呼ばれた操作を calls に残す。list は呼ばれたら失敗する
//   FakeAssets  ASSETS のバインディング。../site のファイルを html_handling = "none"・not_found_handling = "404-page" と
//               同じ決まりで返す（ファイルがあれば 200、無ければいちばん近い 404.html を 404）

import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";

import worker from "../src/index.js";

export const SITE_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "site");
export const FIXTURES_DIR = join(dirname(fileURLToPath(import.meta.url)), "fixtures");
export const ORIGIN = "https://nonet.astlog.dev";

export function fixture(name) {
  return readFileSync(join(FIXTURES_DIR, name), "utf8");
}

export class FakeBucket {
  constructor() {
    this.objects = new Map();
    this.calls = [];
    // head のあとに中身を差し替える（差し替えの競合を再現する）。一度呼んだら消える
    this.afterHead = null;
  }

  put(key, content, uploaded = new Date("2026-10-27T01:15:00.123Z")) {
    const bytes = typeof content === "string" ? new TextEncoder().encode(content) : new Uint8Array(content);
    const etag = createHash("md5").update(bytes).digest("hex");
    this.objects.set(key, { key, bytes, etag, uploaded });
    return this;
  }

  async head(key) {
    this.calls.push(["head", key]);
    const stored = this.objects.get(key);
    const result = stored === undefined ? null : describe(stored);
    if (this.afterHead !== null) {
      const hook = this.afterHead;
      this.afterHead = null;
      hook(this);
    }
    return result;
  }

  async get(key, options = {}) {
    this.calls.push(["get", key, options]);
    const stored = this.objects.get(key);
    if (stored === undefined) {
      return null;
    }
    const object = describe(stored);
    if (options.onlyIf?.etagMatches !== undefined && options.onlyIf.etagMatches !== stored.etag) {
      return object; // 本物と同じく、条件に合わなければ本文の無い R2Object
    }
    let bytes = stored.bytes;
    if (options.range !== undefined) {
      const { offset = 0, length = stored.bytes.length - offset } = options.range;
      bytes = stored.bytes.slice(offset, offset + length);
      object.range = { offset, length: bytes.length };
    }
    return Object.assign(object, {
      body: new Blob([bytes]).stream(),
      text: async () => new TextDecoder().decode(bytes),
      arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
    });
  }

  async list() {
    this.calls.push(["list"]);
    throw new Error("バケットの一覧は出さない");
  }
}

function describe(stored) {
  return {
    key: stored.key,
    size: stored.bytes.length,
    etag: stored.etag,
    httpEtag: `"${stored.etag}"`,
    uploaded: stored.uploaded,
    httpMetadata: {},
  };
}

const CONTENT_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".webp": "image/webp",
  ".mp4": "video/mp4",
  ".txt": "text/plain; charset=utf-8",
  ".xml": "application/xml",
};

export class FakeAssets {
  constructor(siteDir = SITE_DIR) {
    this.siteDir = siteDir;
    this.requests = [];
  }

  async fetch(input) {
    const request = input instanceof Request ? input : new Request(input);
    const { pathname } = new URL(request.url);
    this.requests.push({ method: request.method, pathname, headers: request.headers });
    const file = this.fileFor(pathname);
    if (file !== null) {
      return this.respond(request, file, 200);
    }
    return this.respond(request, this.nearest404(pathname), 404);
  }

  fileFor(pathname) {
    if (pathname.endsWith("/") || pathname.includes("..") || pathname.split("/").includes("_headers")) {
      return null;
    }
    const file = join(this.siteDir, pathname);
    return existsSync(file) && statSync(file).isFile() ? file : null;
  }

  nearest404(pathname) {
    let directory = pathname.endsWith("/") ? pathname : pathname.slice(0, pathname.lastIndexOf("/") + 1);
    for (;;) {
      const candidate = join(this.siteDir, directory, "404.html");
      if (existsSync(candidate)) {
        return candidate;
      }
      if (directory === "/") {
        return null;
      }
      directory = directory.slice(0, directory.slice(0, -1).lastIndexOf("/") + 1);
    }
  }

  respond(request, file, status) {
    if (file === null) {
      return new Response(null, { status: 404 });
    }
    const body = readFileSync(file);
    const etag = `"${createHash("sha256").update(body).digest("hex").slice(0, 32)}"`;
    const headers = new Headers({
      "content-type": CONTENT_TYPES[extname(file)] ?? "application/octet-stream",
      "cache-control": "public, max-age=0, must-revalidate",
      etag,
      "content-length": String(body.length),
      // site/_headers の代わり（本物はアセットの側で付く）
      "x-content-type-options": "nosniff",
    });
    if (status === 200 && request.headers.get("if-none-match") === etag) {
      return new Response(null, { status: 304, headers });
    }
    return new Response(request.method === "HEAD" ? null : body, { status, headers });
  }
}

export function makeEnv() {
  return { UPDATES: new FakeBucket(), ASSETS: new FakeAssets() };
}

// path は「/updates/appcast.xml」のような要求の行のまま（URL として正規化される前の形）を渡す
export function call(env, path, init = {}) {
  return worker.fetch(new Request(ORIGIN + path, init), env);
}

export async function bodyBytes(response) {
  return new Uint8Array(await response.arrayBuffer());
}

// /updates/<名前>: R2（UPDATES）に置いたリリースのファイルを返す。
// 置くのは scripts/publish.sh で、置くものは scripts/release.sh が NONET_RELEASES_DIR に作るものだけ:
//   appcast.xml            Sparkle のフィード（リリースノートは --embed-release-notes で中に入っている）
//   Nonet-<版>.dmg         配る DMG（版は release.sh と同じ 1.2 か 1.2.3 の形）
//   Nonet<新>-<旧>.delta   generate_appcast が作る差分（<新>・<旧> はビルド番号）
// それ以外の名前は R2 に問い合わせずに 404 にする。キーは1つの名前だけで、/ や .. や %xx は通らないので、
// 名前を細工してほかのキーを読ませることも、バケットの一覧を出すこともできない。

import { FILE_SECURITY_HEADERS, isReadMethod, methodNotAllowed, notFound, textResponse } from "./http.js";

const FILE_TYPES = [
  { pattern: /^appcast\.xml$/, contentType: "application/xml; charset=utf-8" },
  { pattern: /^Nonet-\d{1,9}\.\d{1,9}(?:\.\d{1,9})?\.dmg$/, contentType: "application/x-apple-diskimage" },
  { pattern: /^Nonet[1-9]\d{0,8}-[1-9]\d{0,8}\.delta$/, contentType: "application/octet-stream" },
];

// 配ってよい名前なら Content-Type を、そうでなければ null を返す
export function updateFileType(name) {
  for (const { pattern, contentType } of FILE_TYPES) {
    if (pattern.test(name)) {
      return contentType;
    }
  }
  return null;
}

export function isDiskImageName(name) {
  return updateFileType(name) === "application/x-apple-diskimage";
}

export async function handleUpdates(request, env, pathname) {
  if (!isReadMethod(request.method)) {
    return methodNotAllowed();
  }
  // /updates と /updates/ は一覧を出さずに 404
  const name = pathname.startsWith("/updates/") ? pathname.slice("/updates/".length) : "";
  const contentType = updateFileType(name);
  if (contentType === null) {
    return notFound();
  }
  return serveObject(request, env.UPDATES, name, contentType);
}

// head で大きさと ETag を知ってから、条件つきの要求（304）と範囲（206・416）を決め、
// 本文は「head と同じ ETag のときだけ」取る。間に差し替えられたら（失敗したリリースの上げ直しなど）、
// 古いヘッダに新しい中身を付けて返さないよう、最初からやり直す
async function serveObject(request, bucket, key, contentType) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const head = await bucket.head(key);
    if (head === null) {
      return notFound();
    }
    const headers = objectHeaders(head, contentType);
    if (isNotModified(request.headers, head)) {
      return new Response(null, { status: 304, headers });
    }

    let range = null;
    const rangeHeader = request.headers.get("range");
    if (rangeHeader !== null && ifRangeAllows(request.headers.get("if-range"), head)) {
      range = parseRange(rangeHeader, head.size);
      if (range === UNSATISFIABLE) {
        headers.set("content-range", `bytes */${head.size}`);
        headers.set("cache-control", "no-store");
        return new Response(null, { status: 416, headers });
      }
    }
    const length = range === null ? head.size : range.end - range.start + 1;
    headers.set("content-length", String(length));
    if (range !== null) {
      headers.set("content-range", `bytes ${range.start}-${range.end}/${head.size}`);
    }
    const status = range === null ? 200 : 206;
    if (request.method === "HEAD") {
      return new Response(null, { status, headers });
    }

    const options = { onlyIf: { etagMatches: head.etag } };
    if (range !== null) {
      options.range = { offset: range.start, length };
    }
    const object = await bucket.get(key, options);
    if (object === null) {
      return notFound();
    }
    // 条件に合わなかった（head のあとに差し替えられた）ときは本文の無い R2Object が返る
    if (!("body" in object) || object.body === null) {
      continue;
    }
    return new Response(object.body, { status, headers });
  }
  return textResponse(503, "Service Unavailable", { "retry-after": "5" });
}

// Cache-Control は、どのファイルも「写しを使う前に毎回確かめる」（no-cache）。
// - appcast.xml: Sparkle が定期的に読み、release.sh が新旧を比べるために取る。古い写しが出ると
//   リリースが届かず、release.sh が古い項目を元に appcast を作り直してしまう
// - DMG とデルタ: 名前は版ごとだが、一意とは限らない。失敗したリリースを同じ版で作り直すと、
//   同じ名前で中身（と appcast の EdDSA の署名）が変わる。immutable や長い max-age で古い中身が残ると、
//   Sparkle が署名の不一致でアップデートを断る。ETag で確かめれば、変わっていないときは 304 で済む
function objectHeaders(object, contentType) {
  return new Headers({
    ...FILE_SECURITY_HEADERS,
    "content-type": contentType,
    "cache-control": "no-cache",
    etag: object.httpEtag,
    "last-modified": object.uploaded.toUTCString(),
    "accept-ranges": "bytes",
  });
}

// If-None-Match があればそれだけで決める（弱い比較）。無ければ If-Modified-Since（秒の単位）
export function isNotModified(requestHeaders, object) {
  const ifNoneMatch = requestHeaders.get("if-none-match");
  if (ifNoneMatch !== null) {
    return etagListMatches(ifNoneMatch, object.httpEtag);
  }
  const ifModifiedSince = requestHeaders.get("if-modified-since");
  if (ifModifiedSince !== null) {
    const since = Date.parse(ifModifiedSince);
    return !Number.isNaN(since) && wholeSeconds(object.uploaded) <= since;
  }
  return false;
}

function etagListMatches(list, etag) {
  if (list.trim() === "*") {
    return true;
  }
  const wanted = stripWeak(etag);
  const tags = list.match(/(?:W\/)?"[^"]*"/g) ?? [];
  return tags.some((tag) => stripWeak(tag) === wanted);
}

function stripWeak(tag) {
  return tag.startsWith("W/") ? tag.slice(2) : tag;
}

function wholeSeconds(date) {
  return Math.floor(date.getTime() / 1000) * 1000;
}

// If-Range が今の中身を指すときだけ Range に従う。違えば（途中まで落とした DMG が差し替わっていたら）
// 全体を 200 で返し、古い前半と新しい後半をつながせない。ETag は強い比較、日付は Last-Modified と同じときだけ
export function ifRangeAllows(ifRange, object) {
  if (ifRange === null) {
    return true;
  }
  const value = ifRange.trim();
  if (value.startsWith('"')) {
    return value === object.httpEtag;
  }
  if (value.startsWith("W/")) {
    return false;
  }
  const date = Date.parse(value);
  return !Number.isNaN(date) && date === wholeSeconds(object.uploaded);
}

export const UNSATISFIABLE = Symbol("unsatisfiable");

// Range: bytes=始め-終わり / bytes=始め- / bytes=-末尾の長さ（1つだけ）。
// 読めない形と複数の範囲は無視して全体を返す（RFC 9110 14.2 で許されている）。
// 範囲がファイルの外なら UNSATISFIABLE（416）
export function parseRange(value, size) {
  const match = /^bytes=(\d*)-(\d*)$/i.exec(value.trim());
  if (match === null) {
    return null;
  }
  const [, first, last] = match;
  if (first === "" && last === "") {
    return null;
  }
  if (first === "") {
    const suffix = Number(last);
    if (suffix === 0 || size === 0) {
      return UNSATISFIABLE;
    }
    return { start: Math.max(0, size - suffix), end: size - 1 };
  }
  const start = Number(first);
  // 終わりが始めより前（bytes=5-2）は読めない形として無視する
  if (last !== "" && Number(last) < start) {
    return null;
  }
  if (start >= size) {
    return UNSATISFIABLE;
  }
  const end = last === "" ? size - 1 : Math.min(Number(last), size - 1);
  return { start, end };
}

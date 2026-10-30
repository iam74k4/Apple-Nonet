// /download: 販売ページの「ダウンロード」が指す固定の URL。R2 の appcast.xml を読み、
// 既定のチャンネルで最新の項目の DMG へ 302 で飛ばす（リリースのたびにページを書き換えなくてよい）。
//
// - まだ何も出していない（appcast が無い・項目が無い）: サイトの 404 ページを 404 で返す。
//   ボタンを押した人には「見つからない」のページが出る。発売前はページの TODO（--strict）で止まるので、
//   ふつうはここに来ない
// - appcast が読めない・最新の項目の URL がこのサイトの /updates/ の DMG ではない・その DMG が R2 に無い:
//   503（こちらの設定の誤り）。ほかの場所へは飛ばさない（appcast を書き換えられても、
//   別のサイトへ連れて行く踏み台にさせない）。古い版にも戻さない（気づけるように、ログに理由を残す）

import { newestDefaultItem, parseAppcast } from "./appcast.js";
import { FILE_SECURITY_HEADERS, UPDATES_PREFIX, isReadMethod, methodNotAllowed, notFound, textResponse } from "./http.js";
import { isDiskImageName, updateFileType } from "./updates.js";

export const APPCAST_KEY = "appcast.xml";
// 無料プランの CPU は1回 10ms。ふつうの appcast は数十 KB なので、桁違いに大きければ読まずに止める
const MAX_APPCAST_BYTES = 1024 * 1024;

export async function handleDownload(request, env) {
  if (!isReadMethod(request.method)) {
    return methodNotAllowed();
  }
  const appcast = await env.UPDATES.get(APPCAST_KEY);
  if (appcast === null) {
    return notReleasedYet(request, env);
  }
  if (appcast.size > MAX_APPCAST_BYTES) {
    return unavailable(`appcast.xml が大きすぎます（${appcast.size} バイト）`);
  }

  let items;
  try {
    items = parseAppcast(await appcast.text());
  } catch (error) {
    return unavailable(`appcast.xml を読めません: ${error.message}`);
  }
  const newest = newestDefaultItem(items);
  if (newest === null) {
    return notReleasedYet(request, env);
  }
  const name = ownDiskImageName(newest.url);
  if (name === null) {
    return unavailable(`最新の項目（sparkle:version ${newest.version}）の URL が ${UPDATES_PREFIX} の DMG ではありません: ${newest.url}`);
  }
  if ((await env.UPDATES.head(name)) === null) {
    return unavailable(`最新の項目（sparkle:version ${newest.version}）の ${name} が R2 にありません`);
  }
  return new Response(null, {
    status: 302,
    headers: {
      ...FILE_SECURITY_HEADERS,
      location: UPDATES_PREFIX + name,
      // 新しい版を出したらすぐに切り替わるよう、写しを残させない
      "cache-control": "no-store",
    },
  });
}

// https://nonet.astlog.dev/updates/Nonet-<版>.dmg の形ならファイル名を、そうでなければ null を返す。
// 名前は /updates/* と同じ決まり（1つの名前だけ。/ や ? や %xx は通らない）なので、
// 前半が同じなら URL 全体がこのサイトの /updates/ の下に決まる
export function ownDiskImageName(url) {
  if (typeof url !== "string" || !url.startsWith(UPDATES_PREFIX)) {
    return null;
  }
  const name = url.slice(UPDATES_PREFIX.length);
  return updateFileType(name) !== null && isDiskImageName(name) ? name : null;
}

// サイトの 404 ページ（site/404.html）を 404 で返す。ページが無ければ文字だけの 404
async function notReleasedYet(request, env) {
  const page = new URL("/404.html", request.url);
  const asset = await env.ASSETS.fetch(new Request(page, { method: request.method }));
  if (!asset.ok) {
    return notFound();
  }
  const headers = new Headers(asset.headers);
  headers.set("cache-control", "no-store");
  headers.delete("etag");
  return new Response(request.method === "HEAD" ? null : asset.body, { status: 404, headers });
}

function unavailable(reason) {
  // Workers Logs（[observability]）に残る。ダッシュボードの Workers › nonet › Logs で見られる
  console.error(`/download: ${reason}`);
  return textResponse(503, "Service Unavailable", { "retry-after": "300" });
}

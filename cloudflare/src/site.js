// 販売ページのうち、Worker が引くところ。ほかのページ（/privacy.html など）は Worker を通らない。
// html_handling = "none" では、フォルダの URL が index.html を引かないので、/ と /en/ だけここで引く。
// /en（末尾の / なし）は /en/ へ飛ばす。/en/ のページは ../style.css のように相対の URL で読むので、
// /en のまま返すとスタイルとスクリプトが外れる

import { FILE_SECURITY_HEADERS } from "./http.js";

const DIRECTORY_INDEXES = new Map([
  ["/", "/index.html"],
  ["/en/", "/en/index.html"],
]);

export function isDirectoryIndex(pathname) {
  return DIRECTORY_INDEXES.has(pathname);
}

// 要求のメソッドとヘッダ（If-None-Match など）はそのまま渡し、304・HEAD・405 はアセットの側に任せる
export function serveDirectoryIndex(request, env, pathname) {
  const url = new URL(request.url);
  url.pathname = DIRECTORY_INDEXES.get(pathname);
  return env.ASSETS.fetch(new Request(url, request));
}

export function redirectToDirectory(request, pathname) {
  const url = new URL(request.url);
  return new Response(null, {
    status: 301,
    headers: {
      ...FILE_SECURITY_HEADERS,
      location: `${pathname}/${url.search}`,
      "cache-control": "public, max-age=86400",
    },
  });
}

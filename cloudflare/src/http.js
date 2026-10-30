// Worker が自分で作る応答（/updates/*・/download・/en のリダイレクト）の共通の部品。
// site/_headers はアセットの応答にしか付かないので、ここで付ける。

export const UPDATES_ORIGIN = "https://nonet.astlog.dev";
// appcast と DMG・デルタの URL の前半。scripts/release.sh の NONET_DOWNLOAD_URL_PREFIX の既定（appcast と同じ場所）と同じ
export const UPDATES_PREFIX = `${UPDATES_ORIGIN}/updates/`;

// 配るのはファイルで、文書ではない。直に開かれても、中身を嗅いで HTML として描かせず、
// スクリプトも外の読み込みも走らせない（AstLog の画像の応答と同じ約束）
export const FILE_SECURITY_HEADERS = {
  "x-content-type-options": "nosniff",
  "content-security-policy": "default-src 'none'; frame-ancestors 'none'; sandbox",
  "referrer-policy": "strict-origin-when-cross-origin",
};

export function isReadMethod(method) {
  return method === "GET" || method === "HEAD";
}

// 読むだけの場所なので GET と HEAD だけ。ほかは 405 と Allow
export function methodNotAllowed() {
  return textResponse(405, "Method Not Allowed", { allow: "GET, HEAD" });
}

// 無いものは 404。appcast の 404 は scripts/release.sh が「まだ公開していない」と読むので、
// 写しを残させない（初めてアップロードしたあとに古い 404 が出ないように）
export function notFound() {
  return textResponse(404, "Not Found");
}

export function textResponse(status, text, extraHeaders = {}) {
  return new Response(`${text}\n`, {
    status,
    headers: {
      ...FILE_SECURITY_HEADERS,
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
      ...extraHeaders,
    },
  });
}

// HEAD には本文を付けない（ヘッダは GET と同じ）
export function withoutBodyFor(request, response) {
  if (request.method !== "HEAD" || response.body === null) {
    return response;
  }
  return new Response(null, { status: response.status, headers: response.headers });
}

// nonet.astlog.dev の Worker の入口。
// ここに来るのは wrangler.toml の run_worker_first に書いたパスだけで、ほかは静的なアセット（../site）が直に返す。
// 全体の作りは docs/hosting.md。

import { handleDownload } from "./download.js";
import { withoutBodyFor } from "./http.js";
import { handleLicensing, isLicensingPath } from "./licensing.js";
import { isMediaPath, serveMedia } from "./media.js";
import { isDirectoryIndex, redirectToDirectory, serveDirectoryIndex } from "./site.js";
import { handleUpdates } from "./updates.js";

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    if (pathname === "/updates" || pathname.startsWith("/updates/")) {
      return withoutBodyFor(request, await handleUpdates(request, env, pathname));
    }
    // ライセンスキーを届ける（Paddle の通知と購入のページ）。設定が無ければ 503（src/licensing.js）
    if (isLicensingPath(pathname)) {
      return handleLicensing(request, env, pathname);
    }
    if (pathname === "/download") {
      return withoutBodyFor(request, await handleDownload(request, env));
    }
    if (pathname === "/en") {
      return redirectToDirectory(request, pathname);
    }
    if (isDirectoryIndex(pathname)) {
      return serveDirectoryIndex(request, env, pathname);
    }
    // ページの動画は Range に答える（Safari が 206 を要る。src/media.js）
    if (isMediaPath(pathname)) {
      return serveMedia(request, env);
    }
    // run_worker_first を変えて、ここに来るパスが増えたとき。アセットの決まり（404.html など）に任せる
    return env.ASSETS.fetch(request);
  },
};

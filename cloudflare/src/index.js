// nonet.astlog.dev の Worker の入口。
// ここに来るのは wrangler.toml の run_worker_first に書いたパスだけで、ほかは静的なアセット（../site）が直に返す。
// 全体の作りは docs/hosting.md。

import { handleDownload } from "./download.js";
import { withoutBodyFor } from "./http.js";
import { isDirectoryIndex, redirectToDirectory, serveDirectoryIndex } from "./site.js";
import { handleUpdates } from "./updates.js";

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    if (pathname === "/updates" || pathname.startsWith("/updates/")) {
      return withoutBodyFor(request, await handleUpdates(request, env, pathname));
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
    // run_worker_first を変えて、ここに来るパスが増えたとき。アセットの決まり（404.html など）に任せる
    return env.ASSETS.fetch(request);
  },
};

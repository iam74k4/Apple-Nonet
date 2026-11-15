// scripts/appcast-info.js（scripts/publish.sh が appcast を読む道具）の出力の形
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

import { FIXTURES_DIR } from "./support.js";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "..", "scripts", "appcast-info.js");

function run(...args) {
  return spawnSync(process.execPath, [SCRIPT, ...args], { encoding: "utf8" });
}

function withFile(content, body) {
  const dir = mkdtempSync(join(tmpdir(), "nonet-appcast-info-"));
  try {
    const file = join(dir, "appcast.xml");
    writeFileSync(file, content);
    return body(file);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

describe("appcast-info.js", () => {
  test("項目・デルタ・既定のチャンネルの最新をタブ区切りで出す", () => {
    const result = run(join(FIXTURES_DIR, "appcast.xml"));
    assert.equal(result.status, 0, result.stderr);
    const prefix = "https://nonet.astlog.dev/updates/";
    assert.deepEqual(result.stdout.trimEnd().split("\n"), [
      ["item", "43", "1.3.0", "0", `${prefix}Nonet-1.3.0.dmg`, "18934272"].join("\t"),
      ["delta", "43", `${prefix}Nonet43-42.delta`, "612352", "42"].join("\t"),
      ["item", "42", "1.2.0", "1", `${prefix}Nonet-1.2.0.dmg`, "18874368"].join("\t"),
      ["delta", "42", `${prefix}Nonet42-41.delta`, "524288", "41"].join("\t"),
      ["delta", "42", `${prefix}Nonet42-40.delta`, "786432", "40"].join("\t"),
      ["item", "41", "1.1.1", "1", `${prefix}Nonet-1.1.1.dmg`, "18612224"].join("\t"),
      ["delta", "41", `${prefix}Nonet41-40.delta`, "262144", "40"].join("\t"),
      ["item", "40", "1.1", "1", `${prefix}Nonet-1.1.dmg`, "18350080"].join("\t"),
      ["newest", "42", `${prefix}Nonet-1.2.0.dmg`].join("\t"),
    ]);
  });

  test("無い値は「-」。既定のチャンネルの項目が無ければ newest を出さない", () => {
    const xml =
      '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>' +
      "<item><sparkle:channel>beta</sparkle:channel><sparkle:version>7</sparkle:version><enclosure url=\"https://nonet.astlog.dev/updates/Nonet-7.0.dmg\"/></item>" +
      "</channel></rss>";
    withFile(xml, (file) => {
      const result = run(file);
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stdout, ["item", "7", "-", "0", "https://nonet.astlog.dev/updates/Nonet-7.0.dmg", "-"].join("\t") + "\n");
    });
  });

  test("/download が読めない appcast（DOCTYPE・HTML・1 MB より大きい）は 1 で終わり、理由だけを出す", () => {
    const cases = [
      ["<!DOCTYPE rss><rss/>", "DOCTYPE は受け付けません"],
      ["<!doctype html><html></html>", "読めないタグがあります"],
      [`<rss>${" ".repeat(1024 * 1024)}</rss>`, "大きすぎます"],
    ];
    for (const [xml, reason] of cases) {
      withFile(xml, (file) => {
        const result = run(file);
        assert.equal(result.status, 1);
        assert.equal(result.stdout, "");
        assert.match(result.stderr, new RegExp(reason));
      });
    }
  });

  test("引数が違えば 2、ファイルが無ければ 1", () => {
    assert.equal(run().status, 2);
    assert.equal(run("a", "b").status, 2);
    assert.equal(run(join(FIXTURES_DIR, "no-such.xml")).status, 1);
  });
});

// scripts/publish.sh が使う。appcast.xml を Worker の /download と同じパーサー（src/appcast.js）で読み、
// 中身を1行ずつタブ区切りで標準出力に出す。/download が読めない appcast は、ここでも読めずに止まる。
//   item    <sparkle:version> <shortVersionString> <既定のチャンネルなら 1、ほかは 0> <enclosure の url> <length>
//   delta   <その項目の sparkle:version> <url> <length> <sparkle:deltaFrom>
//   newest  <sparkle:version> <url>      既定のチャンネルで最新の項目（/download が飛ばす先）。無ければ出さない
// 値が無いところは「-」。読めない・/download の上限より大きいときは、理由だけを標準エラーに出して 1 で終わる。
// 使い方: node cloudflare/scripts/appcast-info.js <appcast.xml>

import { readFileSync, statSync } from "node:fs";

import { newestDefaultItem, parseAppcast } from "../src/appcast.js";
import { MAX_APPCAST_BYTES } from "../src/download.js";

function field(value) {
  if (value === null || value === undefined || value === "") {
    return "-";
  }
  // タブと改行は区切りと見分けられなくなるので空白にする
  return String(value).replace(/[\t\r\n]/g, " ");
}

function line(...values) {
  return values.map(field).join("\t");
}

function main(args) {
  if (args.length !== 1) {
    process.stderr.write("使い方: node cloudflare/scripts/appcast-info.js <appcast.xml>\n");
    return 2;
  }
  const [file] = args;
  let size;
  let xml;
  try {
    size = statSync(file).size;
    xml = readFileSync(file, "utf8");
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    return 1;
  }
  if (size > MAX_APPCAST_BYTES) {
    process.stderr.write(`大きすぎます（${size} バイト。/download が読むのは ${MAX_APPCAST_BYTES} バイトまで）\n`);
    return 1;
  }
  let items;
  try {
    items = parseAppcast(xml);
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    return 1;
  }
  const lines = [];
  for (const item of items) {
    lines.push(line("item", item.version, item.shortVersion, item.channel === null ? "1" : "0", item.url, item.length));
    for (const delta of item.deltas) {
      lines.push(line("delta", item.version, delta.url, delta.length, delta.deltaFrom));
    }
  }
  const newest = newestDefaultItem(items);
  if (newest !== null) {
    lines.push(line("newest", newest.version, newest.url));
  }
  process.stdout.write(lines.map((entry) => `${entry}\n`).join(""));
  return 0;
}

process.exitCode = main(process.argv.slice(2));

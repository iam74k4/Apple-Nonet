// appcast.xml の読み方と、Sparkle と同じ版の比べ方（src/appcast.js）
import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { AppcastError, compareVersions, newestDefaultItem, parseAppcast } from "../src/appcast.js";
import { fixture } from "./support.js";

const RSS_OPEN = '<?xml version="1.0" standalone="yes"?>\n<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n<channel>\n<title>Nonet</title>\n';
const RSS_CLOSE = "</channel>\n</rss>\n";

function appcast(...items) {
  return RSS_OPEN + items.join("\n") + RSS_CLOSE;
}

function item({ version, channel, url = `https://nonet.astlog.dev/updates/Nonet-${version}.dmg`, extra = "" }) {
  return [
    "<item>",
    `<title>${version}</title>`,
    channel === undefined ? "" : `<sparkle:channel>${channel}</sparkle:channel>`,
    `<sparkle:version>${version}</sparkle:version>`,
    `<sparkle:shortVersionString>${version}</sparkle:shortVersionString>`,
    extra,
    `<enclosure url="${url}" length="10" type="application/octet-stream" sparkle:edSignature="c2ln"/>`,
    "</item>",
  ].join("\n");
}

describe("generate_appcast が書く appcast", () => {
  test("項目ごとに版・チャンネル・DMG の URL を読む（デルタの enclosure は数えない）", () => {
    const items = parseAppcast(fixture("appcast.xml"));
    assert.deepEqual(
      items.map(({ version, shortVersion, channel, url, length, minimumSystemVersion }) => ({
        version,
        shortVersion,
        channel,
        url,
        length,
        minimumSystemVersion,
      })),
      [
        { version: "43", shortVersion: "1.3.0", channel: "beta", url: "https://nonet.astlog.dev/updates/Nonet-1.3.0.dmg", length: "18934272", minimumSystemVersion: "14.0" },
        { version: "42", shortVersion: "1.2.0", channel: null, url: "https://nonet.astlog.dev/updates/Nonet-1.2.0.dmg", length: "18874368", minimumSystemVersion: "14.0" },
        { version: "41", shortVersion: "1.1.1", channel: null, url: "https://nonet.astlog.dev/updates/Nonet-1.1.1.dmg", length: "18612224", minimumSystemVersion: "14.0" },
        { version: "40", shortVersion: "1.1", channel: null, url: "https://nonet.astlog.dev/updates/Nonet-1.1.dmg", length: "18350080", minimumSystemVersion: "14.0" },
      ],
    );
  });

  test("項目ごとのデルタ（<sparkle:deltas> の enclosure）を読む。無ければ空", () => {
    const items = parseAppcast(fixture("appcast.xml"));
    assert.deepEqual(
      items.map((entry) => entry.deltas),
      [
        [{ url: "https://nonet.astlog.dev/updates/Nonet43-42.delta", length: "612352", deltaFrom: "42" }],
        [
          { url: "https://nonet.astlog.dev/updates/Nonet42-41.delta", length: "524288", deltaFrom: "41" },
          { url: "https://nonet.astlog.dev/updates/Nonet42-40.delta", length: "786432", deltaFrom: "40" },
        ],
        [{ url: "https://nonet.astlog.dev/updates/Nonet41-40.delta", length: "262144", deltaFrom: "40" }],
        [],
      ],
    );
  });

  test("既定のチャンネルで最新は 42（ベータの 43 は選ばない）", () => {
    const newest = newestDefaultItem(parseAppcast(fixture("appcast.xml")));
    assert.equal(newest.version, "42");
    assert.equal(newest.url, "https://nonet.astlog.dev/updates/Nonet-1.2.0.dmg");
  });

  test("署名の無い appcast（コメントの無いもの）も同じに読む", () => {
    const unsigned = fixture("appcast.xml")
      .replace(/<!-- sparkle-sign-warning:[\s\S]*?-->\n/, "\n")
      .replace(/<!-- sparkle-signatures:[\s\S]*?-->\n/, "");
    assert.equal(newestDefaultItem(parseAppcast(unsigned)).version, "42");
  });

  test("並び順ではなく版で選ぶ（10 は 9 より新しい）", () => {
    const items = parseAppcast(appcast(item({ version: "9" }), item({ version: "10" }), item({ version: "2" })));
    assert.equal(newestDefaultItem(items).version, "10");
  });

  test("CDATA で書いた版も読む（黙って飛ばして、古い版へ送らない）", () => {
    const cdata = [
      "<item>",
      "<sparkle:version><![CDATA[44]]></sparkle:version>",
      "<sparkle:shortVersionString><![CDATA[1.4.0]]></sparkle:shortVersionString>",
      '<enclosure url="https://nonet.astlog.dev/updates/Nonet-1.4.0.dmg" length="10" type="application/octet-stream" sparkle:edSignature="c2ln"/>',
      "</item>",
    ].join("\n");
    const items = parseAppcast(appcast(item({ version: "43" }), cdata));
    assert.equal(newestDefaultItem(items).version, "44");
    assert.equal(newestDefaultItem(items).shortVersion, "1.4.0");
  });

  test("項目が無い・既定のチャンネルの項目が無いときは null", () => {
    assert.equal(newestDefaultItem(parseAppcast(appcast())), null);
    assert.equal(newestDefaultItem(parseAppcast(appcast(item({ version: "5", channel: "beta" })))), null);
    // 中身が空の sparkle:channel も既定のチャンネルではない（Sparkle と同じ）
    assert.equal(newestDefaultItem(parseAppcast(appcast(item({ version: "5", channel: "" })))), null);
  });

  test("macOS 以外の項目（sparkle:os）と、ダウンロードの無い項目は選ばない", () => {
    const windows = '<item><sparkle:version>9</sparkle:version><enclosure url="https://nonet.astlog.dev/updates/Nonet-9.0.dmg" sparkle:os="windows"/></item>';
    const informational = "<item><sparkle:version>8</sparkle:version><link>https://nonet.astlog.dev/</link></item>";
    const items = parseAppcast(appcast(windows, informational, item({ version: "7" })));
    assert.equal(newestDefaultItem(items).version, "7");
  });

  test("古い書き方: enclosure の sparkle:version 属性を要素より先に読む", () => {
    const legacy = '<item><title>1.0</title><enclosure url="https://nonet.astlog.dev/updates/Nonet-1.0.dmg" sparkle:version="12" length="1" type="application/octet-stream"/></item>';
    const both = '<item><sparkle:version>3</sparkle:version><enclosure url="https://nonet.astlog.dev/updates/Nonet-1.1.dmg" sparkle:version="13"/></item>';
    const items = parseAppcast(appcast(legacy, both));
    assert.deepEqual(items.map((entry) => entry.version), ["12", "13"]);
    assert.equal(newestDefaultItem(items).version, "13");
  });

  test("item の直下だけを見る（informationalUpdate の中の sparkle:version とデルタは数えない）", () => {
    const nested = item({
      version: "21",
      extra: "<sparkle:informationalUpdate><sparkle:version>99</sparkle:version><sparkle:belowVersion>20</sparkle:belowVersion></sparkle:informationalUpdate>",
    }).replace("<item>\n<title>21</title>", "<item>\n<title>21</title>\n<sparkle:deltas><enclosure url=\"https://evil.example/x.delta\" sparkle:deltaFrom=\"20\"/></sparkle:deltas>");
    const [parsed] = parseAppcast(appcast(nested));
    assert.equal(parsed.version, "21");
    assert.equal(parsed.url, "https://nonet.astlog.dev/updates/Nonet-21.dmg");
  });

  test("属性の実体参照を解く", () => {
    const [parsed] = parseAppcast(appcast(item({ version: "5", url: "https://nonet.astlog.dev/updates/Nonet-5.0.dmg?a=1&amp;b=&#50;" })));
    assert.equal(parsed.url, "https://nonet.astlog.dev/updates/Nonet-5.0.dmg?a=1&b=2");
  });
});

describe("appcast として読めないもの", () => {
  const broken = {
    空: "",
    HTML: "<!doctype html><html><body>Not Found</body></html>",
    "rss ではない": '<feed xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel/></feed>',
    "名前空間が違う": '<rss xmlns:sparkle="http://example.com/sparkle" version="2.0"><channel></channel></rss>',
    "channel が無い": '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"></rss>',
    閉じていない: `${RSS_OPEN}<item><sparkle:version>1</sparkle:version>`,
    "閉じタグが合わない": `${RSS_OPEN}<item></channel></item></rss>`,
    DOCTYPE: `<!DOCTYPE rss [<!ENTITY x "y">]>${RSS_OPEN}${RSS_CLOSE}`,
    "知らない実体": `${RSS_OPEN}<item><title>&nbsp;</title></item>${RSS_CLOSE}`,
    "裸の &": `${RSS_OPEN}<item><title>A & B</title></item>${RSS_CLOSE}`,
    "裸の <": `${RSS_OPEN}<item><title>a < b</title></item>${RSS_CLOSE}`,
    "外の要素が2つ": `${RSS_OPEN}${RSS_CLOSE}<rss/>`,
    "外に文字": `${RSS_OPEN}${RSS_CLOSE}garbage`,
  };
  for (const [name, xml] of Object.entries(broken)) {
    test(name, () => {
      assert.throws(() => parseAppcast(xml), AppcastError);
    });
  }
});

describe("版の比べ方（Sparkle の SUVersionComparisonTest.m と同じ答え）", () => {
  const ascending = [
    ["1.0", "1.1"],
    ["0.1", "0.1.2"],
    ["1.5.5-335d3e2", "1.5.6-b252311"],
    ["1.5.5", "1.5.6a1"],
    ["1.1.0b1", "1.1.0b2"],
    ["1.1.1b2", "1.1.2b1"],
    ["1.1.1b2", "1.1.2a1"],
    ["1.0a1", "1.0b1"],
    ["1.0b1", "1.0"],
    ["0.9", "1.0a1"],
    ["1.0b", "1.0b2"],
    ["1.0b10", "1.0b11"],
    ["1.0b9", "1.0b10"],
    ["1.0rc", "1.0"],
    ["1.0b", "1.0"],
    ["1.0pre1", "1.0"],
    ["1.0 (1234)", "1.0 (1235)"],
    ["1.0b1 (1234)", "1.0 (1234)"],
    ["1.0b5 (1234)", "1.0b5 (1235)"],
    ["1.0b5 (1234)", "1.0.1b5 (1234)"],
    ["1.0.1b5 (1234)", "1.0.1b6 (1234)"],
    ["2.0.0.2429", "2.0.0.2430"],
    ["1.1.1.1818", "2.0.0.2430"],
    ["3.3 (5847)", "3.3.1b1 (5902)"],
    ["201210251627", "201211051041"],
    // Nonet のビルド番号（整数）。文字の順ではなく数で比べる
    ["9", "10"],
    ["41", "42"],
    ["99", "100"],
  ];
  const equal = [
    ["1.0", "1.0"],
    ["1.0", "1.0.0"],
    ["1.5.5-335d3e2", "1.5.5-a655360"],
    ["1.5-335d3e2", "1.5.0-335d3e2"],
    ["1.0pre1", "1.0.0pre1"],
    ["3.3 (5847)", "3.3.0 (5847)"],
    ["1.1.1.1818", "1.1.1.1818.0"],
    ["3.3b1 (5902)", "3.3.0b1 (5902)"],
    ["201210251627.0", "201210251627"],
  ];

  for (const [older, newer] of ascending) {
    test(`${older} < ${newer}`, () => {
      assert.equal(compareVersions(older, newer), -1);
      assert.equal(compareVersions(newer, older), 1);
    });
  }
  for (const [a, b] of equal) {
    test(`${a} = ${b}`, () => {
      assert.equal(compareVersions(a, b), 0);
      assert.equal(compareVersions(b, a), 0);
    });
  }
  test("2.0 > 1.1、0.1 > 0.0.1", () => {
    assert.equal(compareVersions("2.0", "1.1"), 1);
    assert.equal(compareVersions("0.1", "0.0.1"), 1);
  });
});

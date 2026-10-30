// appcast.xml を読み、既定のチャンネルで最新の項目を選ぶ（/download が使う）。
// 読む形は、固定した Sparkle（project.yml の 2.6.0 以上。いまは 2.10.1 に解決）の generate_appcast が書くもの:
//
//   <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
//    <channel>
//     <item>
//      <title>1.2.0</title> <pubDate>…</pubDate>
//      <sparkle:channel>beta</sparkle:channel>          （--channel を付けたときだけ。付いた項目は既定のチャンネルではない）
//      <sparkle:version>42</sparkle:version>            （ビルド番号。新旧はこれで比べる）
//      <sparkle:shortVersionString>1.2.0</sparkle:shortVersionString>
//      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
//      <description><![CDATA[ 埋め込んだリリースノート ]]></description>
//      <enclosure url="https://…/Nonet-1.2.0.dmg" length="…" type="application/octet-stream" sparkle:edSignature="…"/>
//      <sparkle:deltas> <enclosure url="https://…/Nonet42-41.delta" sparkle:deltaFrom="41" …/> </sparkle:deltas>
//     </item>
//    </channel>
//   </rss>
//   <!-- sparkle-signatures: … -->                      （appcast に署名したとき）
//
// 古い書き方の enclosure の sparkle:version 属性も読む（Sparkle 本体と同じく、属性が先、要素が後）。
// 版を見るのは item の直下の要素だけ。<sparkle:deltas> の中の enclosure と、
// <sparkle:informationalUpdate> の中の <sparkle:version> は数えない。
// Workers には XML のパーサーが無いので、この形に足りるだけの小さなパーサーを持つ。DOCTYPE（実体の定義）は受け付けない。

const SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle";

export class AppcastError extends Error {}

// 項目の配列を返す。appcast として読めなければ AppcastError
export function parseAppcast(xml) {
  const root = parseXml(xml);
  if (root.name !== "rss") {
    throw new AppcastError(`いちばん外の要素が <rss> ではありません（<${root.name}>）`);
  }
  if (root.attributes["xmlns:sparkle"] !== SPARKLE_NAMESPACE) {
    throw new AppcastError("xmlns:sparkle が Sparkle の名前空間ではありません");
  }
  const channel = root.children.find((child) => child.name === "channel");
  if (channel === undefined) {
    throw new AppcastError("<channel> がありません");
  }
  return channel.children.filter((child) => child.name === "item").map(readItem);
}

function readItem(item) {
  const enclosure = childNamed(item, "enclosure");
  const versionElement = childNamed(item, "sparkle:version");
  const channelElement = childNamed(item, "sparkle:channel");
  const minimumSystemElement = childNamed(item, "sparkle:minimumSystemVersion");
  const version = enclosure?.attributes["sparkle:version"] ?? versionElement?.text ?? null;
  return {
    version: version === null ? null : version.trim(),
    shortVersion: childNamed(item, "sparkle:shortVersionString")?.text.trim() ?? null,
    // 要素があれば、中身が空でも既定のチャンネルではない（Sparkle も同じ扱い）
    channel: channelElement === undefined ? null : channelElement.text.trim(),
    minimumSystemVersion: minimumSystemElement?.text.trim() ?? null,
    url: enclosure?.attributes.url?.trim() ?? null,
    length: enclosure?.attributes.length ?? null,
    os: enclosure?.attributes["sparkle:os"] ?? null,
  };
}

function childNamed(element, name) {
  return element.children.find((child) => child.name === name);
}

// 既定のチャンネル・macOS 向け・ダウンロードできる（enclosure の url がある）項目のうち、
// sparkle:version が最大のもの。無ければ null。
// sparkle:minimumSystemVersion では絞らない（ブラウザから相手の macOS の版は分からない。
// 動く版はページに書いてあり、Sparkle は入れたあとに自分で確かめる）
export function newestDefaultItem(items) {
  let newest = null;
  for (const item of items) {
    if (item.channel !== null || item.url === null || !item.version) {
      continue;
    }
    if (item.os !== null && item.os !== "macos") {
      continue;
    }
    if (newest === null || compareVersions(item.version, newest.version) > 0) {
      newest = item;
    }
  }
  return newest;
}

// --- 版の比べ方: Sparkle の SUStandardVersionComparator（Sparkle/SUStandardVersionComparator.m）を写したもの。
// 数字・文字・区切り（. や記号や空白）の塊に分け、塊ごとに比べる。- から後ろは見ない。
// 「1.0」と「1.0.0」が同じになるよう、先頭の数字と . の並びの長さをそろえてから比べる。
// 戻り値は a が新しければ 1、古ければ -1、同じなら 0

const NUMBER = "number";
const STRING = "string";
const PERIOD = "period";
const PUNCTUATION = "punctuation";
const WHITESPACE = "whitespace";
const DASH = "dash";

function characterType(character) {
  if (character === ".") return PERIOD;
  if (character === "-") return DASH;
  if (/^[0-9]/.test(character)) return NUMBER;
  if (/^\s/u.test(character)) return WHITESPACE;
  if (/^\p{P}/u.test(character)) return PUNCTUATION;
  return STRING;
}

function isSeparator(type) {
  return type === PERIOD || type === PUNCTUATION || type === WHITESPACE;
}

function isSameTypeClass(typeA, typeB) {
  if (typeA === NUMBER || typeA === STRING || typeA === DASH) {
    return typeA === typeB;
  }
  return isSeparator(typeB);
}

function splitVersion(version) {
  const characters = Array.from(version);
  const parts = [];
  if (characters.length === 0) {
    return parts;
  }
  let part = characters[0];
  let previousType = characterType(part);
  for (const character of characters.slice(1)) {
    const type = characterType(character);
    if (type === DASH) {
      break;
    }
    if (type !== previousType || isSeparator(previousType)) {
      parts.push(part);
      part = character;
    } else {
      part += character;
    }
    previousType = type;
  }
  parts.push(part);
  return parts;
}

function countLeadingNumberAndPeriodParts(parts) {
  let count = 0;
  for (const part of parts) {
    const type = characterType(part);
    if (type !== NUMBER && type !== PERIOD) {
      break;
    }
    count++;
  }
  return count;
}

function balanceParts(partsA, partsB) {
  const countA = countLeadingNumberAndPeriodParts(partsA);
  const countB = countLeadingNumberAndPeriodParts(partsB);
  const [shorter, shorterCount, longer, longerCount] =
    countA < countB ? [partsA, countA, partsB, countB] : [partsB, countB, partsA, countA];
  for (let index = shorterCount; index < longerCount; index++) {
    shorter.splice(index, 0, characterType(longer[index]) === PERIOD ? "." : "0");
  }
}

export function compareVersions(versionA, versionB) {
  const partsA = splitVersion(versionA);
  const partsB = splitVersion(versionB);
  balanceParts(partsA, partsB);

  const shared = Math.min(partsA.length, partsB.length);
  for (let index = 0; index < shared; index++) {
    const partA = partsA[index];
    const partB = partsB[index];
    const typeA = characterType(partA);
    const typeB = characterType(partB);
    if (isSameTypeClass(typeA, typeB)) {
      if (typeA === NUMBER) {
        const valueA = BigInt(partA);
        const valueB = BigInt(partB);
        if (valueA !== valueB) {
          return valueA > valueB ? 1 : -1;
        }
      } else if (typeA === STRING && partA !== partB) {
        return partA > partB ? 1 : -1;
      }
    } else if (typeA !== STRING && typeB === STRING) {
      return 1;
    } else if (typeA === STRING && typeB !== STRING) {
      return -1;
    } else {
      // 片方が数字で、もう片方が区切り。数字のほうを新しいとみなす
      return typeA === NUMBER ? 1 : -1;
    }
  }
  if (partsA.length !== partsB.length) {
    const aIsLonger = partsA.length > partsB.length;
    const extra = aIsLonger ? partsA[shared] : partsB[shared];
    // 余った塊が文字（1.0b など）なら短いほうが新しい。数字や区切りなら長いほうが新しい
    const longerWins = characterType(extra) !== STRING;
    return aIsLonger === longerWins ? 1 : -1;
  }
  return 0;
}

// --- 小さな XML のパーサー。要素・属性・文字（実体は XML の5つと数値の文字参照だけ）を読む。
// コメント・CDATA（リリースノート）・処理命令（<?xml …?>）は読み飛ばす。CDATA の中に <item> などの字が
// あっても要素として数えない

const TOKEN =
  /<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>|<!DOCTYPE|<\/([A-Za-z_][\w.:-]*)\s*>|<([A-Za-z_][\w.:-]*)((?:\s+[A-Za-z_][\w.:-]*\s*=\s*(?:"[^"<]*"|'[^'<]*'))*)\s*(\/?)>|</g;
const ATTRIBUTE = /([A-Za-z_][\w.:-]*)\s*=\s*(?:"([^"<]*)"|'([^'<]*)')/g;

function parseXml(xml) {
  const document = { name: "#document", attributes: {}, children: [], text: "" };
  const stack = [document];
  let position = 0;
  TOKEN.lastIndex = 0;
  for (let match = TOKEN.exec(xml); match !== null; match = TOKEN.exec(xml)) {
    appendText(stack.at(-1), xml.slice(position, match.index));
    position = TOKEN.lastIndex;
    const [token, closeName, openName, attributeText, selfClosing] = match;
    if (token === "<") {
      throw new AppcastError(`読めないタグがあります（${xml.slice(match.index, match.index + 40)}）`);
    }
    if (token === "<!DOCTYPE") {
      throw new AppcastError("DOCTYPE は受け付けません");
    }
    if (closeName !== undefined) {
      const open = stack.pop();
      if (stack.length === 0 || open.name !== closeName) {
        throw new AppcastError(`閉じタグ </${closeName}> が開いた要素と合いません`);
      }
      continue;
    }
    if (openName === undefined) {
      continue; // コメント・CDATA・処理命令
    }
    const element = { name: openName, attributes: readAttributes(attributeText), children: [], text: "" };
    const parent = stack.at(-1);
    if (parent === document && document.children.length > 0) {
      throw new AppcastError("いちばん外の要素が2つ以上あります");
    }
    parent.children.push(element);
    if (selfClosing !== "/") {
      stack.push(element);
    }
  }
  appendText(stack.at(-1), xml.slice(position));
  if (stack.length !== 1) {
    throw new AppcastError(`<${stack.at(-1).name}> が閉じられていません`);
  }
  if (document.children.length !== 1) {
    throw new AppcastError("要素がありません");
  }
  if (document.text.trim() !== "") {
    throw new AppcastError("要素の外に文字があります");
  }
  return document.children[0];
}

function readAttributes(text) {
  const attributes = {};
  ATTRIBUTE.lastIndex = 0;
  for (let match = ATTRIBUTE.exec(text); match !== null; match = ATTRIBUTE.exec(text)) {
    attributes[match[1]] = decodeEntities(match[2] ?? match[3]);
  }
  return attributes;
}

function appendText(element, raw) {
  if (raw.length > 0) {
    element.text += decodeEntities(raw);
  }
}

const NAMED_ENTITIES = { lt: "<", gt: ">", amp: "&", quot: '"', apos: "'" };

function decodeEntities(text) {
  return text.replace(/&([^;&\s]*);?/g, (entity, body) => {
    if (!entity.endsWith(";")) {
      throw new AppcastError(`; で終わらない & があります（${entity}）`);
    }
    if (Object.hasOwn(NAMED_ENTITIES, body)) {
      return NAMED_ENTITIES[body];
    }
    const numeric = /^#(?:x([0-9A-Fa-f]{1,6})|([0-9]{1,7}))$/.exec(body);
    if (numeric !== null) {
      const codePoint = numeric[1] !== undefined ? Number.parseInt(numeric[1], 16) : Number(numeric[2]);
      if (codePoint > 0 && codePoint <= 0x10ffff) {
        return String.fromCodePoint(codePoint);
      }
    }
    throw new AppcastError(`知らない実体参照です（${entity}）`);
  });
}

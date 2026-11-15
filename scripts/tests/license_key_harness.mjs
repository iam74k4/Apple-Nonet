// Worker（cloudflare/src/license.js）のキーの作り方を、手元の鍵で動かす。scripts/tests/license_test.sh が、
// できたキーを本物の nonet-license（Swift）で確かめるために使う。ネットワークには出ない。
// 使い方:
//   node license_key_harness.mjs sign <秘密鍵のファイル> <公開鍵のファイル> <ライセンス ID> <名前（空なら無し）> <メール> <発行日時（RFC 3339）>
//       Worker と同じく LicenseInfo を作って署名し、公開鍵で確かめてからキーを出す
//   node license_key_harness.mjs resign <秘密鍵のファイル> <公開鍵のファイル> <キー>
//       キーの中身（nonet-license issue が作ったもの）を読み、Worker の作り方で署名し直したキーを出す
import { readFileSync } from "node:fs";

import { decodeLicenseKey, importPrivateKey, importPublicKey, issueLicenseKey, licenseInfo } from "../../cloudflare/src/license.js";

const [command, privateKeyFile, publicKeyFile, ...rest] = process.argv.slice(2);
const keys = {
  privateKey: await importPrivateKey(readFileSync(privateKeyFile, "utf8")),
  publicKey: await importPublicKey(readFileSync(publicKeyFile, "utf8")),
};

let info;
switch (command) {
  case "sign": {
    const [licenseID, licensee, email, issuedAt] = rest;
    info = licenseInfo({ licenseID, licensee: licensee === "" ? null : licensee, email, issuedAt });
    break;
  }
  case "resign": {
    const decoded = decodeLicenseKey(rest[0]);
    if (decoded === null) {
      console.error("キーを読めません");
      process.exit(1);
    }
    info = licenseInfo({ licenseID: decoded.licenseID, licensee: decoded.licensee, email: decoded.email ?? null, issuedAt: decoded.issuedAt });
    break;
  }
  default:
    console.error(`知らないコマンドです: ${command}`);
    process.exit(2);
}
process.stdout.write(`${await issueLicenseKey(info, keys)}\n`);

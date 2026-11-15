// 担当: keys-license
// nonet-license keygen --out <dir>            鍵を作る（秘密鍵は 600 で保存）
// nonet-license issue --key <private> --name <licensee> [--email <email>] [--public <base64>] [--skip-app-key-check]   キーを発行する
//     （アプリに入れる公開鍵 Config/Nonet.xcconfig の NONET_LICENSE_PUBLIC_KEY と、秘密鍵の隣の公開鍵か --public で検証してから）
// nonet-license verify --public <base64> <licenseKey>                        キーを検証する
// nonet-license revoke <licenseID|licenseKey> [--list <file>]               ライセンスを無効にする（一覧 RevokedLicenses.txt に足す）
// 中身は NonetCore の LicenseTool（テストのためにそちらに置いている）
import Foundation
import NonetCore

exit(LicenseTool.run(Array(CommandLine.arguments.dropFirst()), io: .live))

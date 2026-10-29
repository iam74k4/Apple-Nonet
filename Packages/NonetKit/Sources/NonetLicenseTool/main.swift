// 担当: keys-license
// nonet-license keygen --out <dir>            鍵を作る（秘密鍵は 600 で保存）
// nonet-license issue --key <private> --name <licensee> [--email <email>]   キーを発行する
// nonet-license verify --public <base64> <licenseKey>                        キーを検証する
// 中身は NonetCore の LicenseTool（テストのためにそちらに置いている）
import Foundation
import NonetCore

exit(LicenseTool.run(Array(CommandLine.arguments.dropFirst()), io: .live))

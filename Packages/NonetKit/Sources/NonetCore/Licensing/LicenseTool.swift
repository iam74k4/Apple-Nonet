// 担当: keys-license
// nonet-license（NonetLicenseTool）の中身。テストできるようにここに置き、アプリには見せない（package）。
// 開発者だけが使う道具なので、文言はローカライズしない
import Foundation

package enum LicenseToolCommand: Equatable {
    case help
    case keygen(outputDirectory: String)
    case issue(privateKeyPath: String, licensee: String, email: String?, edition: String?, licenseID: String?, publicKey: String?, skipAppKeyCheck: Bool = false)
    case verify(publicKey: String, licenseKey: String)
    /// target はライセンス ID かライセンスキー。listPath は一覧のファイル（無ければリポジトリの中を探す）
    case revoke(target: String, listPath: String?)
}

package struct LicenseToolUsageError: Error, Equatable {
    package var message: String

    package init(_ message: String) {
        self.message = message
    }
}

/// 続けられない問題（終了コード 1）
private struct LicenseToolFailure: Error {
    var message: String
}

/// ファイルと標準出力。テストでは差し替える
package struct LicenseToolIO {
    package var currentDirectory: () -> String
    package var fileExists: (String) -> Bool
    package var readFile: (String) throws -> String
    /// 途中のフォルダも作る。すでにあれば何もしない
    package var createDirectory: (String) throws -> Void
    /// 新しいファイルを作る。すでにあれば失敗する（上書きしない）
    package var createNewFile: (_ path: String, _ contents: String, _ permissions: UInt16) throws -> Void
    /// ファイルを書き換える（無効にしたライセンスの一覧）。既定は書かずに失敗する（.live だけが本物のファイルに書く）
    package var replaceFile: (_ path: String, _ contents: String) throws -> Void
    /// ファイルの権限（下位 9 ビット）。分からなければ nil（既定。.live だけが本物のファイルを調べる）
    package var filePermissions: (String) -> UInt16? = { _ in nil }
    package var standardOutput: (String) -> Void
    package var standardError: (String) -> Void
    package var now: () -> Date
    package var makeLicenseID: () -> String
    package var generateKeyPair: () -> (privateKeyBase64: String, publicKeyBase64: String)

    package init(
        currentDirectory: @escaping () -> String,
        fileExists: @escaping (String) -> Bool,
        readFile: @escaping (String) throws -> String,
        createDirectory: @escaping (String) throws -> Void,
        createNewFile: @escaping (_ path: String, _ contents: String, _ permissions: UInt16) throws -> Void,
        standardOutput: @escaping (String) -> Void,
        standardError: @escaping (String) -> Void,
        now: @escaping () -> Date,
        makeLicenseID: @escaping () -> String,
        generateKeyPair: @escaping () -> (privateKeyBase64: String, publicKeyBase64: String) = LicenseSigner.generateKeyPair,
        replaceFile: @escaping (_ path: String, _ contents: String) throws -> Void = { _, _ in throw CocoaError(.fileWriteNoPermission) }
    ) {
        self.currentDirectory = currentDirectory
        self.fileExists = fileExists
        self.readFile = readFile
        self.createDirectory = createDirectory
        self.createNewFile = createNewFile
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.now = now
        self.makeLicenseID = makeLicenseID
        self.generateKeyPair = generateKeyPair
        self.replaceFile = replaceFile
    }

    package static var live: LicenseToolIO {
        var io = LicenseToolIO(
            currentDirectory: { FileManager.default.currentDirectoryPath },
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            readFile: { try String(contentsOfFile: $0, encoding: .utf8) },
            createDirectory: { try FileManager.default.createDirectory(atPath: $0, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) },
            createNewFile: LicenseTool.createNewFile,
            // write(_: Data) は書けないと Objective-C の例外で落ちるので、throws の方を使う
            standardOutput: { try? FileHandle.standardOutput.write(contentsOf: Data($0.utf8)) },
            standardError: { try? FileHandle.standardError.write(contentsOf: Data($0.utf8)) },
            now: { Date() },
            makeLicenseID: { UUID().uuidString },
            replaceFile: { path, contents in try Data(contents.utf8).write(to: URL(fileURLWithPath: path), options: .atomic) }
        )
        io.filePermissions = { path in
            (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber).map { UInt16(truncating: $0) & 0o777 }
        }
        return io
    }
}

package enum LicenseTool {
    package static let privateKeyFileName = "nonet-license.private-key"
    package static let publicKeyFileName = "nonet-license.public-key"
    /// アプリに入れる公開鍵の置き場所（リポジトリの根から）と、その名前
    package static let configPath = "Config/Nonet.xcconfig"
    package static let configKeyName = "NONET_LICENSE_PUBLIC_KEY"
    /// アプリに入れる、無効にしたライセンスの一覧（リポジトリの根から）
    package static let revocationListPath = "Packages/NonetKit/Sources/NonetCore/Resources/RevokedLicenses.txt"

    package static let exitSuccess: Int32 = 0
    package static let exitFailure: Int32 = 1
    package static let exitUsage: Int32 = 2

    package static let usage = """
    使い方:
      nonet-license keygen --out <フォルダ>
          Ed25519 の鍵を作る。<フォルダ>/\(privateKeyFileName)（パーミッション 600）と
          <フォルダ>/\(publicKeyFileName) を書き、公開鍵を表示する。既存のファイルは上書きしない
      nonet-license issue --key <秘密鍵のファイル> --name <購入者> [--email <メール>] [--edition <エディション>] [--id <ライセンス ID>] [--public <公開鍵の base64 かファイル>] [--skip-app-key-check]
          ライセンスキーを発行して表示する。エディションの既定は standard、ID の既定は新しい UUID。
          発行したキーを、アプリに入れる公開鍵（今いるフォルダから上にたどって見つけた \(configPath) の
          \(configKeyName)）と、秘密鍵と同じフォルダの \(publicKeyFileName) で検証し、どちらかと合わなければ発行しない。
          --public を付けたときは、その公開鍵で検証する。それがアプリに入れる公開鍵と違うときも発行しない。
          --skip-app-key-check を付けると、アプリに入れる公開鍵とは照合しない（前の鍵の組で作った古い版のアプリ向けに発行するときだけ）
      nonet-license verify --public <公開鍵の base64 かファイル> <ライセンスキー>
          ライセンスキーを検証して中身を表示する。キーの前後に「License key:」などの文が付いていてもよい
      nonet-license revoke <ライセンス ID かライセンスキー> [--list <一覧のファイル>]
          ライセンスを無効にする（返金したとき・キーが公開されてしまったとき）。ライセンス ID の SHA-256 を、
          今いるフォルダから上にたどって見つけた \(revocationListPath)（--list で指定もできる）に足す。
          アプリが受け付けなくなるのは、一覧をコミットして出す次のリリースから
      nonet-license help
          この説明を表示する

    公開鍵のファイルに .xcconfig を渡すと、その \(configKeyName) を使う。
    終了コード: 0 成功、1 失敗、2 使い方の誤り

    """

    /// 引数（コマンド名は除く）を実行し、終了コードを返す
    package static func run(_ arguments: [String], io: LicenseToolIO) -> Int32 {
        let command: LicenseToolCommand
        do {
            command = try parse(arguments)
        } catch {
            io.standardError("エラー: \(error.message)\n\n\(usage)")
            return exitUsage
        }
        switch command {
        case .help:
            io.standardOutput(usage)
            return exitSuccess
        case .keygen(let outputDirectory):
            return keygen(outputDirectory: outputDirectory, io: io)
        case .issue(let privateKeyPath, let licensee, let email, let edition, let licenseID, let publicKey, let skipAppKeyCheck):
            return issue(
                privateKeyPath: privateKeyPath, licensee: licensee, email: email, edition: edition, licenseID: licenseID,
                publicKey: publicKey, skipAppKeyCheck: skipAppKeyCheck, io: io
            )
        case .verify(let publicKey, let licenseKey):
            return verify(publicKey: publicKey, licenseKey: licenseKey, io: io)
        case .revoke(let target, let listPath):
            return revoke(target: target, listPath: listPath, io: io)
        }
    }

    // MARK: - 引数

    package static func parse(_ arguments: [String]) throws(LicenseToolUsageError) -> LicenseToolCommand {
        guard let name = arguments.first else {
            throw LicenseToolUsageError("コマンドを指定してください")
        }
        let rest = Array(arguments.dropFirst())
        if ["help", "-h", "--help"].contains(name) || rest.contains(where: { $0 == "-h" || $0 == "--help" }) {
            return .help
        }
        switch name {
        case "keygen":
            let parsed = try parseOptions(rest, allowed: ["out"])
            try expectPositionals(parsed.positionals, count: 0, command: name)
            let outputDirectory = try required("out", in: parsed.options)
            guard !outputDirectory.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw LicenseToolUsageError("--out が空です")
            }
            return .keygen(outputDirectory: outputDirectory)
        case "issue":
            let parsed = try parseOptions(rest, allowed: ["key", "name", "email", "edition", "id", "public"], flags: ["skip-app-key-check"])
            try expectPositionals(parsed.positionals, count: 0, command: name)
            return .issue(
                privateKeyPath: try required("key", in: parsed.options),
                licensee: try required("name", in: parsed.options),
                email: parsed.options["email"],
                edition: parsed.options["edition"],
                licenseID: parsed.options["id"],
                publicKey: parsed.options["public"],
                skipAppKeyCheck: parsed.flags.contains("skip-app-key-check")
            )
        case "verify":
            let parsed = try parseOptions(rest, allowed: ["public"])
            guard let licenseKey = parsed.positionals.first else {
                throw LicenseToolUsageError("検証するライセンスキーを指定してください")
            }
            try expectPositionals(parsed.positionals, count: 1, command: name)
            return .verify(publicKey: try required("public", in: parsed.options), licenseKey: licenseKey)
        case "revoke":
            let parsed = try parseOptions(rest, allowed: ["list"])
            guard let target = parsed.positionals.first, !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LicenseToolUsageError("無効にするライセンス ID かライセンスキーを指定してください")
            }
            try expectPositionals(parsed.positionals, count: 1, command: name)
            return .revoke(target: target, listPath: parsed.options["list"])
        default:
            throw LicenseToolUsageError("不明なコマンドです: \(name)")
        }
    }

    /// "--name value" と "--name=value" を読む。flags は値を取らないオプション（"--name" だけ）。"--" の後はすべて位置引数
    private static func parseOptions(
        _ arguments: [String], allowed: Set<String>, flags allowedFlags: Set<String> = []
    ) throws(LicenseToolUsageError) -> (options: [String: String], flags: Set<String>, positionals: [String]) {
        var options: [String: String] = [:]
        var flags: Set<String> = []
        var positionals: [String] = []
        var index = 0
        var onlyPositionals = false
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if onlyPositionals || !argument.hasPrefix("--") {
                positionals.append(argument)
                continue
            }
            if argument == "--" {
                onlyPositionals = true
                continue
            }
            let body = argument.dropFirst(2)
            if allowedFlags.contains(String(body)) {
                guard flags.insert(String(body)).inserted else {
                    throw LicenseToolUsageError("--\(body) が2回指定されています")
                }
                continue
            }
            let name: String
            let value: String
            if let equals = body.firstIndex(of: "=") {
                name = String(body[..<equals])
                value = String(body[body.index(after: equals)...])
            } else {
                name = String(body)
                guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                    throw LicenseToolUsageError("--\(name) の値を指定してください")
                }
                value = arguments[index]
                index += 1
            }
            guard allowed.contains(name) else {
                throw LicenseToolUsageError("不明なオプションです: --\(name)")
            }
            guard options[name] == nil else {
                throw LicenseToolUsageError("--\(name) が2回指定されています")
            }
            options[name] = value
        }
        return (options, flags, positionals)
    }

    private static func required(_ name: String, in options: [String: String]) throws(LicenseToolUsageError) -> String {
        guard let value = options[name] else {
            throw LicenseToolUsageError("--\(name) を指定してください")
        }
        return value
    }

    private static func expectPositionals(_ positionals: [String], count: Int, command: String) throws(LicenseToolUsageError) {
        guard positionals.count <= count else {
            throw LicenseToolUsageError("\(command) には余分な引数があります: \(positionals[count])")
        }
    }

    // MARK: - コマンド

    private static func keygen(outputDirectory: String, io: LicenseToolIO) -> Int32 {
        let directory = absolutePath(outputDirectory, io: io)
        let privatePath = join(directory, privateKeyFileName)
        let publicPath = join(directory, publicKeyFileName)
        for path in [privatePath, publicPath] where io.fileExists(path) {
            io.standardError("エラー: すでにあるので上書きしません: \(path)\n")
            return exitFailure
        }
        guard let keys = configSafeKeyPair(io: io) else {
            io.standardError("エラー: xcconfig に書ける公開鍵を作れませんでした\n")
            return exitFailure
        }
        do {
            try io.createDirectory(directory)
            try io.createNewFile(privatePath, keys.privateKeyBase64 + "\n", 0o600)
            try io.createNewFile(publicPath, keys.publicKeyBase64 + "\n", 0o644)
        } catch {
            io.standardError("エラー: 鍵を保存できません: \(error.localizedDescription)\n")
            return exitFailure
        }
        io.standardOutput(keys.publicKeyBase64 + "\n")
        var notes = """
        公開鍵（上の1行）を Config/Nonet.xcconfig の NONET_LICENSE_PUBLIC_KEY に設定してください。
        秘密鍵: \(privatePath)（パーミッション 600）
        秘密鍵は git にコミットしないでください。リポジトリの外の安全な場所に置き、バックアップを取ってください。
        秘密鍵をなくすと、同じ公開鍵で検証できるキーを発行できなくなります。

        """
        if let repository = enclosingRepository(of: directory, io: io) {
            notes += "警告: 秘密鍵を git リポジトリ（\(repository)）の中に作りました。リポジトリの外に移してください。\n"
        }
        io.standardError(notes)
        return exitSuccess
    }

    /// xcconfig は行の途中の「//」から後をコメントとして捨てる。公開鍵が切り詰められないよう、「//」を含まない鍵を選ぶ（約1%が含む）
    static func configSafeKeyPair(io: LicenseToolIO) -> (privateKeyBase64: String, publicKeyBase64: String)? {
        for _ in 0..<100 {
            let keys = io.generateKeyPair()
            if !keys.publicKeyBase64.contains("//") {
                return keys
            }
        }
        return nil
    }

    private static func issue(
        privateKeyPath: String, licensee: String, email: String?, edition: String?, licenseID: String?,
        publicKey: String?, skipAppKeyCheck: Bool, io: LicenseToolIO
    ) -> Int32 {
        let licensee = licensee.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let edition = (edition ?? "standard").trimmingCharacters(in: .whitespacesAndNewlines)
        let licenseID = (licenseID ?? io.makeLicenseID()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !licensee.isEmpty else {
            io.standardError("エラー: --name が空です\n")
            return exitUsage
        }
        if let email, email.isEmpty || !email.contains("@") || email.contains(where: \.isWhitespace) {
            io.standardError("エラー: --email がメールアドレスではありません: \(email)\n")
            return exitUsage
        }
        guard !edition.isEmpty, !licenseID.isEmpty else {
            io.standardError("エラー: --edition と --id は空にできません\n")
            return exitUsage
        }

        let privateKeyFile = absolutePath(privateKeyPath, io: io)
        // keygen は本人だけが読める権限で、リポジトリの外に作る。控えから戻したときなどに広がっていれば知らせる
        if let permissions = io.filePermissions(privateKeyFile), permissions & 0o077 != 0 {
            io.standardError("注意: 秘密鍵のファイルを本人以外も読めます（権限 \(String(permissions, radix: 8))）。chmod 600 \(privateKeyFile) にしてください\n")
        }
        if let repository = enclosingRepository(of: (privateKeyFile as NSString).deletingLastPathComponent, io: io) {
            io.standardError("注意: 秘密鍵が git の作業ツリー（\(repository)）の中にあります。コミットしないよう、リポジトリの外へ移してください\n")
        }
        let signer: LicenseSigner
        do {
            signer = try LicenseSigner(privateKeyBase64: try io.readFile(privateKeyFile))
        } catch let error as LicenseError {
            io.standardError("エラー: \(message(for: error))\n")
            return exitFailure
        } catch {
            io.standardError("エラー: 秘密鍵を読めません: \(error.localizedDescription)\n")
            return exitFailure
        }

        // 32 バイトなら何でも秘密鍵として読めてしまう（公開鍵のファイルでも）。アプリに入れる公開鍵で検証できるキーだけを渡す
        let checks: [PublicKeyCheck]
        do {
            checks = try publicKeyChecks(publicKey, privateKeyPath: privateKeyPath, skipAppKeyCheck: skipAppKeyCheck, signer: signer, io: io)
        } catch let error as LicenseToolFailure {
            io.standardError("エラー: \(error.message)\n")
            return exitFailure
        } catch let error as LicenseError {
            io.standardError("エラー: \(message(for: error))\n")
            return exitFailure
        } catch {
            io.standardError("エラー: 公開鍵を読めません: \(error.localizedDescription)\n")
            return exitFailure
        }

        // キーには秒までしか入らないので、表示と一致するようにそろえる
        let issuedAt = Date(timeIntervalSince1970: io.now().timeIntervalSince1970.rounded(.down))
        let info = LicenseInfo(licenseID: licenseID, licensee: licensee, email: email, edition: edition, issuedAt: issuedAt)
        do {
            let key = try signer.sign(info)
            for check in checks where (try? check.verifier.verify(key)) != info {
                io.standardError("エラー: \(check.mismatch)\n")
                return exitFailure
            }
            io.standardOutput(key + "\n")
            io.standardError("発行しました: \(describe(info))\n")
            return exitSuccess
        } catch let error as LicenseError {
            io.standardError("エラー: \(message(for: error))\n")
            return exitFailure
        } catch {
            io.standardError("エラー: 署名できません: \(error.localizedDescription)\n")
            return exitFailure
        }
    }

    private static func verify(publicKey: String, licenseKey: String, io: LicenseToolIO) -> Int32 {
        let publicKeyText: String
        do {
            publicKeyText = try readPublicKey(publicKey, io: io)
        } catch let error as LicenseToolFailure {
            io.standardError("エラー: \(error.message)\n")
            return exitFailure
        } catch {
            io.standardError("エラー: 公開鍵を読めません: \(error.localizedDescription)\n")
            return exitFailure
        }
        do {
            let info = try LicenseVerifier(publicKeyBase64: publicKeyText).verify(licenseKey)
            io.standardOutput("有効なライセンスです\n\(describe(info))\n")
            return exitSuccess
        } catch let error as LicenseError {
            io.standardError("無効なライセンスです: \(message(for: error))\n")
            return exitFailure
        } catch {
            io.standardError("エラー: \(error.localizedDescription)\n")
            return exitFailure
        }
    }

    /// ライセンス ID（キーならその中の ID）の SHA-256 を一覧に足す。すでにあれば何もしない
    private static func revoke(target: String, listPath: String?, io: LicenseToolIO) -> Int32 {
        let licenseID: String
        do {
            licenseID = try revokedLicenseID(target, io: io)
        } catch let error as LicenseToolFailure {
            io.standardError("エラー: \(error.message)\n")
            return exitFailure
        } catch {
            io.standardError("エラー: \(error.localizedDescription)\n")
            return exitFailure
        }
        guard let path = listPath.map({ absolutePath($0, io: io) }) ?? findInRepository(revocationListPath, io: io) else {
            io.standardError("エラー: \(revocationListPath) が見つかりません（リポジトリの中で動かすか、--list で一覧のファイルを指定してください）\n")
            return exitFailure
        }
        let text: String
        do {
            text = try io.readFile(path)
        } catch {
            io.standardError("エラー: 一覧を読めません: \(path): \(error.localizedDescription)\n")
            return exitFailure
        }
        let hash = LicenseRevocationList.hash(of: licenseID)
        if LicenseRevocationList(text: text).hashes.contains(hash) {
            io.standardOutput(hash + "\n")
            io.standardError("すでに無効にしてあります: ライセンス ID \(licenseID)（\(path)）\n")
            return exitSuccess
        }
        // 返金の記録と同じ日付にする（ISO8601FormatStyle の既定は UTC で、日本の朝は前の日になる）
        let date = io.now().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        var updated = text
        if !updated.isEmpty, !updated.hasSuffix("\n") {
            updated += "\n"
        }
        // ID は書かない（一覧はリポジトリとアプリに入る）。日付だけ添える
        updated += "\(hash)  # \(date)\n"
        do {
            try io.replaceFile(path, updated)
        } catch {
            io.standardError("エラー: 一覧に書けません: \(path): \(error.localizedDescription)\n")
            return exitFailure
        }
        io.standardOutput(hash + "\n")
        io.standardError("""
        無効にしました: ライセンス ID \(licenseID)
        一覧: \(path)
        一覧をコミットして、次のリリースに入れてください。アプリがこのキーを受け付けなくなるのは、その版からです（それまでの版では使えるままです）。

        """)
        return exitSuccess
    }

    /// 無効にするライセンス ID。キー（eyJ を含む）なら中の ID（署名は確かめない。ID を足すだけで、ほかのキーには効かない）
    private static func revokedLicenseID(_ target: String, io: LicenseToolIO) throws -> String {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(LicenseCoding.keyPrefix) {
            guard let key = LicenseCoding.licenseKey(in: trimmed), let parts = LicenseCoding.keyParts(key),
                  let info = try? LicenseCoding.decode(parts.payload) else {
                throw LicenseToolFailure(message: "ライセンスキーを読めません。キー全体か、ライセンス ID を指定してください")
            }
            io.standardError("キーの中身:\n\(describe(info))\n")
            let licenseID = info.licenseID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !licenseID.isEmpty else {
                throw LicenseToolFailure(message: "キーのライセンス ID が空です")
            }
            return licenseID
        }
        guard !trimmed.contains(where: \.isNewline) else {
            throw LicenseToolFailure(message: "ライセンス ID に改行が入っています")
        }
        // issue が作る ID は UUID。注文番号などを書くと、どのキーにも効かない（--id で決めた ID なら、このままでよい）
        if UUID(uuidString: trimmed) == nil {
            io.standardError("注意: 「\(trimmed)」は UUID の形ではありません。注文番号ではなく、ライセンス ID かキー全体を指定してください（issue の --id で決めた ID なら、このままで構いません）\n")
        }
        return trimmed
    }

    // MARK: - 補助

    /// --public の値（ファイルがあればその中身、無ければ base64 そのもの）。.xcconfig のファイルなら、その NONET_LICENSE_PUBLIC_KEY
    private static func readPublicKey(_ value: String, io: LicenseToolIO) throws -> String {
        guard io.fileExists(value) else { return value }
        guard value.hasSuffix(".xcconfig") else { return try io.readFile(value) }
        guard let key = try appPublicKey(inConfig: value, io: io) else {
            throw LicenseToolFailure(message: "\(value) の \(configKeyName) が空です")
        }
        return key
    }

    /// 発行したキーを検証する公開鍵と、合わなかったときの説明
    private struct PublicKeyCheck {
        var verifier: LicenseVerifier
        var mismatch: String
    }

    private static let pairMismatch = "秘密鍵と公開鍵が対応していません。--key に公開鍵のファイルや別の秘密鍵を指定していないか確かめてください"

    /// issue で照合する公開鍵:
    /// - --public があれば、それ。アプリに入れる公開鍵と違えば発行しない（--skip-app-key-check なら照合しない）
    /// - 無ければ、アプリに入れる公開鍵（Config/Nonet.xcconfig）と、秘密鍵と同じフォルダの公開鍵のファイルのうち、あるものすべて。
    ///   同じフォルダの公開鍵は秘密鍵と必ず合うので、それだけでは「アプリで使えるキーか」は分からない
    /// どれも無ければ警告して、秘密鍵自身の公開鍵で確かめる
    private static func publicKeyChecks(
        _ publicKey: String?, privateKeyPath: String, skipAppKeyCheck: Bool, signer: LicenseSigner, io: LicenseToolIO
    ) throws -> [PublicKeyCheck] {
        let config = skipAppKeyCheck ? nil : findConfig(io: io)
        let appKey = try config.flatMap { try appPublicKey(inConfig: $0, io: io) }
        if skipAppKeyCheck {
            io.standardError("注意: --skip-app-key-check のため、アプリの公開鍵（\(configPath) の \(configKeyName)）とは照合していません\n")
        } else if let config, appKey == nil {
            io.standardError("注意: \(config) の \(configKeyName) が空のため、アプリの公開鍵とは照合していません\n")
        }
        if let publicKey {
            let given = try readPublicKey(publicKey, io: io)
            let verifier = try LicenseVerifier(publicKeyBase64: given)
            // 鍵の組を作り直したのに xcconfig が前の鍵のまま（またはその逆）だと、アプリで使えないキーを配ってしまう
            if let config, let appKey, LicenseCoding.decodeKeyMaterial(appKey) != LicenseCoding.decodeKeyMaterial(given) {
                throw LicenseToolFailure(
                    message: "--public の公開鍵が、アプリに入れる公開鍵（\(config) の \(configKeyName)）と違うため、発行しません。"
                        + "このキーはいまのアプリでは使えません。xcconfig と --public が keygen で作った同じ組かを確かめてください"
                        + "（前の鍵の組で作った古い版のアプリ向けに発行するときだけ --skip-app-key-check を付けてください）"
                )
            }
            return [PublicKeyCheck(verifier: verifier, mismatch: pairMismatch)]
        }
        var checks: [PublicKeyCheck] = []
        if let config, let appKey {
            checks.append(PublicKeyCheck(
                verifier: try LicenseVerifier(publicKeyBase64: appKey),
                mismatch: "秘密鍵が、アプリに入れる公開鍵（\(config) の \(configKeyName)）と対応していません。"
                    + "発行してもアプリで使えないキーになります。--key の秘密鍵と、xcconfig に入れた公開鍵が keygen で作った同じ組かを確かめてください"
            ))
        } else if config == nil, !skipAppKeyCheck {
            io.standardError("注意: \(configPath) が見つからないため、アプリの公開鍵とは照合していません（リポジトリの中で動かすか、--public で xcconfig を指定できます）\n")
        }
        let directory = (absolutePath(privateKeyPath, io: io) as NSString).deletingLastPathComponent
        let sibling = join(directory, publicKeyFileName)
        if io.fileExists(sibling) {
            checks.append(PublicKeyCheck(verifier: try LicenseVerifier(publicKeyBase64: try io.readFile(sibling)), mismatch: pairMismatch))
        }
        if checks.isEmpty {
            io.standardError("警告: 公開鍵が見つからないため、アプリの公開鍵と合うか確かめていません（--public で指定できます）\n")
            checks.append(PublicKeyCheck(verifier: try LicenseVerifier(publicKeyBase64: signer.publicKeyBase64), mismatch: pairMismatch))
        }
        return checks
    }

    /// 今いるフォルダから上にたどって見つけた Config/Nonet.xcconfig（swift run はリポジトリの中の Packages/NonetKit で動かす）
    private static func findConfig(io: LicenseToolIO) -> String? {
        findInRepository(configPath, io: io)
    }

    /// 今いるフォルダから上にたどって見つけた、リポジトリの根からの relativePath
    private static func findInRepository(_ relativePath: String, io: LicenseToolIO) -> String? {
        var current = absolutePath(".", io: io)
        while true {
            let candidate = join(current, relativePath)
            if io.fileExists(candidate) {
                return candidate
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty {
                return nil
            }
            current = parent
        }
    }

    /// xcconfig の NONET_LICENSE_PUBLIC_KEY。空なら nil。
    /// 公開鍵でなければ LicenseToolFailure。base64 の公開鍵の約1%は「//」を含み、xcconfig ではそこから後ろがコメントになって切れるので、
    /// そのときは /$()/ と書くように伝える（Sparkle の generate_keys の鍵は選び直せないため、書き方で避ける）
    private static func appPublicKey(inConfig path: String, io: LicenseToolIO) throws -> String? {
        guard let entry = xcconfigValue(configKeyName, in: try io.readFile(path)) else { return nil }
        if !entry.value.isEmpty, (try? LicenseVerifier(publicKeyBase64: entry.value)) != nil {
            return entry.value
        }
        let uncut = entry.raw.replacingOccurrences(of: "$()", with: "")
        if uncut.contains("//"), (try? LicenseVerifier(publicKeyBase64: uncut)) != nil {
            throw LicenseToolFailure(message: "\(path) の \(configKeyName) が「//」の所で切れています（xcconfig では // から後ろがコメントになります）。公開鍵の「//」を「/$()/」と書いてください")
        }
        if entry.value.isEmpty {
            return nil
        }
        throw LicenseToolFailure(message: "\(path) の \(configKeyName) が Ed25519 の公開鍵（base64 で 44 文字）になっていません: \(entry.value)")
    }

    /// xcconfig の値。Xcode と同じく // から後ろはコメント、$() は空文字。同じキーが何度もあれば最後のもの。無ければ nil。
    /// raw は // で切る前の、= から後ろ（切れているかを見分けるため）
    static func xcconfigValue(_ key: String, in text: String) -> (value: String, raw: String)? {
        var found: (value: String, raw: String)?
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { continue }
            let rest = trimmed.dropFirst(key.count)
            guard let equals = rest.firstIndex(of: "="), rest[..<equals].allSatisfy(\.isWhitespace) else { continue }
            let raw = String(rest[rest.index(after: equals)...])
            var value = raw
            if let comment = value.range(of: "//") {
                value = String(value[..<comment.lowerBound])
            }
            value = value.replacingOccurrences(of: "$()", with: "")
            found = (value.trimmingCharacters(in: .whitespaces), raw.trimmingCharacters(in: .whitespaces))
        }
        return found
    }

    /// アプリの Bundle.module に頼らない（ツール単体でも動くように）
    package static func message(for error: LicenseError) -> String {
        switch error {
        case .malformed: "ライセンスキーの形式が正しくありません"
        case .invalidSignature: "署名が一致しません（改ざんされているか、別の鍵で発行されたキーです）"
        case .wrongProduct: "Nonet のライセンスキーではありません（product が \(LicenseInfo.productID) ではありません）"
        case .invalidPublicKey: "公開鍵が正しくありません（32 バイトの Ed25519 公開鍵の base64 を指定してください）"
        case .invalidPrivateKey: "秘密鍵が正しくありません（keygen で作った \(privateKeyFileName) を指定してください）"
        case .revoked: "無効にしたライセンスです（\(revocationListPath) にあります）"
        }
    }

    private static func describe(_ info: LicenseInfo) -> String {
        var lines = [
            "ライセンス ID: \(info.licenseID)",
            "購入者: \(info.licensee)",
        ]
        if let email = info.email {
            lines.append("メール: \(email)")
        }
        lines.append("エディション: \(info.edition)")
        lines.append("発行日時: \(info.issuedAt.formatted(.iso8601))")
        return lines.joined(separator: "\n")
    }

    private static func absolutePath(_ path: String, io: LicenseToolIO) -> String {
        let absolute = path.hasPrefix("/") ? path : join(io.currentDirectory(), path)
        return ScriptEnvironment.normalizedPath(absolute)
    }

    private static func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    /// directory を含む git の作業ツリーの場所
    private static func enclosingRepository(of directory: String, io: LicenseToolIO) -> String? {
        var current = directory
        while true {
            if io.fileExists(join(current, ".git")) {
                return current
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty {
                return nil
            }
            current = parent
        }
    }

    /// O_EXCL で作るので、既存のファイルを上書きせず、権限の広いファイルが一瞬でもできることもない
    static func createNewFile(_ path: String, contents: String, permissions: UInt16) throws {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(permissions))
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        // umask で削られた分を戻す
        guard fchmod(descriptor, mode_t(permissions)) == 0 else { throw posixError() }
        let bytes = Array(contents.utf8)
        var written = 0
        while written < bytes.count {
            let result = bytes[written...].withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            if result < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            written += result
        }
        guard fsync(descriptor) == 0 else { throw posixError() }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

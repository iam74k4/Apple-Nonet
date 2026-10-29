// 担当: keys-license
// nonet-license（NonetLicenseTool）の中身。テストできるようにここに置き、アプリには見せない（package）。
// 開発者だけが使う道具なので、文言はローカライズしない
import Foundation

package enum LicenseToolCommand: Equatable {
    case help
    case keygen(outputDirectory: String)
    case issue(privateKeyPath: String, licensee: String, email: String?, edition: String?, licenseID: String?, publicKey: String?)
    case verify(publicKey: String, licenseKey: String)
}

package struct LicenseToolUsageError: Error, Equatable {
    package var message: String

    package init(_ message: String) {
        self.message = message
    }
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
        generateKeyPair: @escaping () -> (privateKeyBase64: String, publicKeyBase64: String) = LicenseSigner.generateKeyPair
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
    }

    package static var live: LicenseToolIO {
        LicenseToolIO(
            currentDirectory: { FileManager.default.currentDirectoryPath },
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            readFile: { try String(contentsOfFile: $0, encoding: .utf8) },
            createDirectory: { try FileManager.default.createDirectory(atPath: $0, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) },
            createNewFile: LicenseTool.createNewFile,
            // write(_: Data) は書けないと Objective-C の例外で落ちるので、throws の方を使う
            standardOutput: { try? FileHandle.standardOutput.write(contentsOf: Data($0.utf8)) },
            standardError: { try? FileHandle.standardError.write(contentsOf: Data($0.utf8)) },
            now: { Date() },
            makeLicenseID: { UUID().uuidString }
        )
    }
}

package enum LicenseTool {
    package static let privateKeyFileName = "nonet-license.private-key"
    package static let publicKeyFileName = "nonet-license.public-key"

    package static let exitSuccess: Int32 = 0
    package static let exitFailure: Int32 = 1
    package static let exitUsage: Int32 = 2

    package static let usage = """
    使い方:
      nonet-license keygen --out <フォルダ>
          Ed25519 の鍵を作る。<フォルダ>/\(privateKeyFileName)（パーミッション 600）と
          <フォルダ>/\(publicKeyFileName) を書き、公開鍵を表示する。既存のファイルは上書きしない
      nonet-license issue --key <秘密鍵のファイル> --name <購入者> [--email <メール>] [--edition <エディション>] [--id <ライセンス ID>] [--public <公開鍵の base64 かファイル>]
          ライセンスキーを発行して表示する。エディションの既定は standard、ID の既定は新しい UUID。
          発行したキーを公開鍵（既定は秘密鍵と同じフォルダの \(publicKeyFileName)）で検証し、合わなければ発行しない
      nonet-license verify --public <公開鍵の base64 かファイル> <ライセンスキー>
          ライセンスキーを検証して中身を表示する
      nonet-license help
          この説明を表示する

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
        case .issue(let privateKeyPath, let licensee, let email, let edition, let licenseID, let publicKey):
            return issue(
                privateKeyPath: privateKeyPath, licensee: licensee, email: email, edition: edition, licenseID: licenseID,
                publicKey: publicKey, io: io
            )
        case .verify(let publicKey, let licenseKey):
            return verify(publicKey: publicKey, licenseKey: licenseKey, io: io)
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
            let parsed = try parseOptions(rest, allowed: ["key", "name", "email", "edition", "id", "public"])
            try expectPositionals(parsed.positionals, count: 0, command: name)
            return .issue(
                privateKeyPath: try required("key", in: parsed.options),
                licensee: try required("name", in: parsed.options),
                email: parsed.options["email"],
                edition: parsed.options["edition"],
                licenseID: parsed.options["id"],
                publicKey: parsed.options["public"]
            )
        case "verify":
            let parsed = try parseOptions(rest, allowed: ["public"])
            guard let licenseKey = parsed.positionals.first else {
                throw LicenseToolUsageError("検証するライセンスキーを指定してください")
            }
            try expectPositionals(parsed.positionals, count: 1, command: name)
            return .verify(publicKey: try required("public", in: parsed.options), licenseKey: licenseKey)
        default:
            throw LicenseToolUsageError("不明なコマンドです: \(name)")
        }
    }

    /// "--name value" と "--name=value" を読む。"--" の後はすべて位置引数
    private static func parseOptions(_ arguments: [String], allowed: Set<String>) throws(LicenseToolUsageError) -> (options: [String: String], positionals: [String]) {
        var options: [String: String] = [:]
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
        return (options, positionals)
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
        publicKey: String?, io: LicenseToolIO
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

        let signer: LicenseSigner
        do {
            signer = try LicenseSigner(privateKeyBase64: try io.readFile(absolutePath(privateKeyPath, io: io)))
        } catch let error as LicenseError {
            io.standardError("エラー: \(message(for: error))\n")
            return exitFailure
        } catch {
            io.standardError("エラー: 秘密鍵を読めません: \(error.localizedDescription)\n")
            return exitFailure
        }

        // 32 バイトなら何でも秘密鍵として読めてしまう（公開鍵のファイルでも）。アプリに入れる公開鍵で検証できるキーだけを渡す
        let verifier: LicenseVerifier
        do {
            if let publicKeyText = try publicKeyForIssue(publicKey, privateKeyPath: privateKeyPath, io: io) {
                verifier = try LicenseVerifier(publicKeyBase64: publicKeyText)
            } else {
                io.standardError("警告: 公開鍵が見つからないため、アプリの公開鍵と合うか確かめていません（--public で指定できます）\n")
                verifier = try LicenseVerifier(publicKeyBase64: signer.publicKeyBase64)
            }
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
            guard (try? verifier.verify(key)) == info else {
                io.standardError("エラー: 秘密鍵と公開鍵が対応していません。--key に公開鍵のファイルや別の秘密鍵を指定していないか確かめてください\n")
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

    // MARK: - 補助

    /// --public の値（ファイルがあればその中身、無ければ base64 そのもの）
    private static func readPublicKey(_ value: String, io: LicenseToolIO) throws -> String {
        io.fileExists(value) ? try io.readFile(value) : value
    }

    /// issue で照合する公開鍵。--public が無ければ秘密鍵と同じフォルダの公開鍵のファイル。どちらも無ければ nil
    private static func publicKeyForIssue(_ publicKey: String?, privateKeyPath: String, io: LicenseToolIO) throws -> String? {
        if let publicKey {
            return try readPublicKey(publicKey, io: io)
        }
        let directory = (absolutePath(privateKeyPath, io: io) as NSString).deletingLastPathComponent
        let sibling = join(directory, publicKeyFileName)
        return io.fileExists(sibling) ? try io.readFile(sibling) : nil
    }

    /// アプリの Bundle.module に頼らない（ツール単体でも動くように）
    package static func message(for error: LicenseError) -> String {
        switch error {
        case .malformed: "ライセンスキーの形式が正しくありません"
        case .invalidSignature: "署名が一致しません（改ざんされているか、別の鍵で発行されたキーです）"
        case .wrongProduct: "Nonet のライセンスキーではありません（product が \(LicenseInfo.productID) ではありません）"
        case .invalidPublicKey: "公開鍵が正しくありません（32 バイトの Ed25519 公開鍵の base64 を指定してください）"
        case .invalidPrivateKey: "秘密鍵が正しくありません（keygen で作った \(privateKeyFileName) を指定してください）"
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

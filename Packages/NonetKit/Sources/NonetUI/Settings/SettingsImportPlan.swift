// 担当: ui-settings
// プロファイルの読み込みを、実際に設定へ入れる前に写しで試した結果。置き換わるものや、何かを実行するマスがあれば先に確かめる
import Foundation
import NonetCore

struct SettingsImportPlan: Identifiable, Equatable {
    /// 読み込む前に中身を見せるマスと、それがあるプロファイルの名前
    struct ReviewedCell: Equatable {
        var profileName: String
        var cell: Cell
        /// Return と同じ働きのキー（Return・Enter・⌃M・⌃J・⌃C など、今のキー配列で改行や Enter の文字になるもの）か ⌃ の付いたキーを押す。
        /// コマンドの実行やメッセージの送信になりうるので、確かめるときに目立たせる
        var pressesSubmitKey = false
    }

    let id = UUID()
    /// 読み込むファイルの名前（確かめるときに出す。1行にして長ければ切る）
    var fileName: String
    /// 読み込む中身（メニュー項目の長いショートカットは除いたもの）
    var document: ConfigurationStore.ImportedProfiles
    /// 写しに読み込んだときの結果
    var result: NonetConfiguration.ImportResult
    /// 置き換わる自分のアプリのプロファイルの名前（設定の並び順）
    var replacedNames: [String]
    /// 読み込まれるプロファイルの、スクリプト・キー入力・メニュー項目・AI・Mac の中のファイルを開く URL のマス（ファイルの並び順。数に上限は無い）。
    /// どれもその人の権限で動くので、何も置き換わらなくても読み込む前に中身をすべて見せて確かめる
    var reviewedCells: [ReviewedCell]

    /// keys は Return と同じ働きのキーを見分けるのに使う、今のキー配列（テストでは偽物）
    init(
        document: ConfigurationStore.ImportedProfiles,
        configuration: NonetConfiguration,
        fileName: String,
        keys: (any SettingsKeyCharacterTranslating)? = nil
    ) {
        self.fileName = SettingsText.singleLine(fileName, limit: SettingsText.importFileNameLimit)
        let document = Self.withoutLongMenuShortcuts(document)
        self.document = document
        var preview = configuration
        result = preview.importProfiles(document)
        let replacedIDs = Set(Self.importedApps(in: document).compactMap { app in
            Self.existingProfile(for: app, in: configuration)?.id
        })
        replacedNames = configuration.profiles.filter { replacedIDs.contains($0.id) }.map(\.name)
        // 共通マスはファイルでプロファイルの後ろにある。どのアプリでも出るので、ほかのマスと同じく中身を見せる
        let sources: [(name: String, cells: [Cell?])] = Self.usedProfiles(in: document).map { profile in
            (profile.name, profile.pages.flatMap(\.cells))
        } + [(SettingsText.sharedCellsName, document.sharedCells.cells)]
        reviewedCells = sources.flatMap { source -> [ReviewedCell] in
            source.cells.compactMap { cell -> ReviewedCell? in
                guard let cell, Self.needsReview(cell.action) else { return nil }
                return ReviewedCell(profileName: source.name, cell: cell, pressesSubmitKey: Self.pressesSubmitKey(cell.action, keys: keys))
            }
        }
    }

    /// 今の設定を上書きする（グローバルのページ・同じアプリのプロファイル・共通マス）。
    /// 共通マスは、今は無くても、どのアプリでもその位置のマスの代わりに出るので置き換えとみなす
    var replacesExisting: Bool { result.replacedGlobal || !replacedNames.isEmpty || result.replacedSharedCells }

    /// 新しく加わるアプリのプロファイルがある
    var addsProfiles: Bool { result.added > 0 }

    /// 読み込まれるプロファイルに、中身を見せるマスがある
    var hasReviewedCells: Bool { !reviewedCells.isEmpty }

    /// 読み込む前に確かめる（置き換わるものがあるか、何かを実行するマスがある）
    var needsConfirmation: Bool { replacesExisting || hasReviewedCells }

    /// 置き換えるものを除いた中身（新しいアプリのプロファイルだけ加えるとき。共通マスも入れない）。設定はその時点のもので決める
    func newProfilesOnly(in configuration: NonetConfiguration) -> ConfigurationStore.ImportedProfiles {
        let profiles = document.profiles.filter { profile in
            guard let app = profile.app else { return false }
            return Self.existingProfile(for: app, in: configuration) == nil
        }
        return ConfigurationStore.ImportedProfiles(profiles: profiles, unreadableCount: document.unreadableCount)
    }

    /// 読み込みで実際に使われるプロファイルか共通マスが、スクリプトのマスを含む（読み込んだ後の知らせ）
    static func containsScripts(in document: ConfigurationStore.ImportedProfiles) -> Bool {
        let sharedScript = document.sharedCells.cells.contains { cell in
            if case .script = cell?.action { return true }
            return false
        }
        return sharedScript || containsScripts(usedProfiles(in: document))
    }

    static func containsScripts(_ profiles: [Profile]) -> Bool {
        profiles.contains { profile in
            profile.pages.contains { page in
                page.cells.contains { cell in
                    if case .script = cell?.action { return true }
                    return false
                }
            }
        }
    }

    // MARK: 中身を見せるマス

    /// 読み込む前に中身を見せるアクション。スクリプト、キー入力（短くても、⌃R・r・m・⌃M のように履歴のコマンドを実行できる）、
    /// メニュー項目（ショートカットのキーも見せる）、AI（選択テキストを渡し、結果で置き換えうる）、
    /// ショートカット.app のショートカット（何でも実行できる）、
    /// Finder で選んだファイルを動かす（ゴミ箱に入れる・名前を変える・複製する・移す）、
    /// Mac の中のファイルを開く URL（.command や .app も開ける）と、別のものを動かす URL（ショートカットの実行・ssh・共有フォルダなど）
    static func needsReview(_ action: Action) -> Bool {
        switch action {
        case .script, .keystroke, .menuItem, .ai, .shortcut:
            true
        case .file(let file):
            // Finder で選んだファイルをゴミ箱に入れる・名前を変える・複製する・移す。開くだけなら見せない（ダブルクリックと同じ）
            file.operation.changesFiles
        case .openURL(let url):
            opensLocalFile(url.url) || opensAnotherTool(url.url)
        case .launchApp, .screenCapture:
            // 撮影のキーは、撮る範囲を利用者が選ぶか、macOS の撮影の画面が出るだけ（画面全体を撮るのも、ファイルかクリップボードに入るだけ）
            false
        }
    }

    /// 開くと別のものを動かす・つなぐスキーム（ウェブや、アプリ固有のリンクは含めない）
    static let toolSchemes: Set<String> = ["shortcuts", "ssh", "telnet", "smb", "afp", "vnc", "ftp", "sftp", "applescript"]

    /// ショートカットの実行・ssh・共有フォルダなど、別のものを動かす URL か
    static func opensAnotherTool(_ url: String) -> Bool {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = text.firstIndex(of: ":") else { return false }
        return toolSchemes.contains(text[..<colon].lowercased())
    }

    /// キー入力かメニュー項目のショートカットが、Return と同じ働きのキーか ⌃ の付いたキーを押す
    static func pressesSubmitKey(_ action: Action, keys translator: (any SettingsKeyCharacterTranslating)?) -> Bool {
        switch action {
        case .keystroke(let keys):
            pressesSubmitKey(keys, keys: translator)
        case .menuItem(let menu):
            menu.keyEquivalent.map { pressesSubmitKey($0, keys: translator) } ?? false
        case .script, .ai, .openURL, .launchApp, .shortcut, .file, .screenCapture:
            false
        }
    }

    /// Return・Enter のキーコード（kVK_Return・kVK_Powerbook_KeypadEnter・kVK_ANSI_KeypadEnter）
    static let submitKeyCodes: Set<UInt16> = [36, 52, 76]
    /// Return と同じ働きの文字（CR・LF・ETX（Enter））
    static let submitScalars: Set<Unicode.Scalar> = ["\r", "\n", "\u{3}"]

    /// Return と同じ働きのキーを押すか。キー配列に頼らずに決まるもの（Return・Enter のキー、⌃ の付いたキー、改行の文字）に加え、
    /// 今のキー配列でその打鍵が入力する文字（UCKeyTranslate）が CR・LF・ETX なら押すとみなす（⌥ などで改行になるキー配列もある）
    static func pressesSubmitKey(_ keys: KeySequence, keys translator: (any SettingsKeyCharacterTranslating)?) -> Bool {
        keys.chords.contains { chord in
            // ⌃M（CR）・⌃J（LF）・⌃C（ETX）・⌃O（行を実行）など。⌃ の付いたキーはすべて目立たせる
            if chord.modifiers.contains(.control) { return true }
            switch chord.key {
            case .special(let key):
                return key == .returnKey
            case .keyCode(let code):
                if submitKeyCodes.contains(code) { return true }
            case .character(let character):
                if character.unicodeScalars.contains(where: submitScalars.contains) { return true }
                // 修飾キーの無い文字は、その文字のまま入力される
                if chord.modifiers.isEmpty { return false }
            }
            guard let typed = translator?.characters(for: chord) else { return false }
            return typed.unicodeScalars.contains(where: submitScalars.contains)
        }
    }

    // MARK: 注意が要るスクリプトの行

    /// ネットワークから取ってきたものを実行する・隠したものを実行する・ファイルを消す、のに使われる命令。行に含まれていれば目立たせる
    static let suspiciousPatterns: [(name: String, regex: Regex<Substring>)] = [
        ("curl", #/(?i)\bcurl\b/#),
        ("wget", #/(?i)\bwget\b/#),
        ("base64", #/(?i)\bbase64\b/#),
        ("eval", #/(?i)\beval\b/#),
        // 「| sh」「|bash」「| sudo /bin/zsh」「| /usr/bin/env bash」
        ("| sh", #/(?i)\|\s*(?:sudo\s+)?(?:\S*/)?(?:env\s+)?(?:ba|z|da|k|c|tc|fi)?sh\b/#),
        ("osascript", #/(?i)\bosascript\b/#),
    ]

    /// 行に含まれる、注意が要る命令の名前（suspiciousPatterns と rm -rf）。無ければ空
    static func suspiciousTerms(in line: String) -> [String] {
        var terms = suspiciousPatterns.filter { line.contains($0.regex) }.map(\.name)
        if removesRecursively(line) {
            terms.append("rm -rf")
        }
        return terms
    }

    /// rm に、再帰（-r・-R）と強制（-f）の両方のオプションが付いている（「rm -rf」「rm -fr」「rm -r -f」「rm -Rf」）
    static func removesRecursively(_ line: String) -> Bool {
        line.matches(of: #/\brm\s+((?:-\S+\s+)*-\S+)/#).contains { match in
            let options = match.output.1.split(whereSeparator: \.isWhitespace).filter { $0.hasPrefix("-") && !$0.hasPrefix("--") }
            let letters = options.joined()
            return (letters.contains("r") || letters.contains("R")) && letters.contains("f")
        }
    }

    /// / や ~ で始まるか file: の URL（開くときにファイルの場所として扱う。URLNormalizer と同じ決まり）
    static func opensLocalFile(_ url: String) -> Bool {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("~") || (text.hasPrefix("/") && !text.hasPrefix("//")) {
            return true
        }
        return text.lowercased().hasPrefix("file:")
    }

    /// メニュー項目のショートカットは1打だけ残す。メニューから読んだものは必ず1打なので、それより長いものは
    /// メニューを押すように見せて任意のキーを打つためのもの。捨てても、メニューを押して同じ項目を選べる
    static func withoutLongMenuShortcuts(_ document: ConfigurationStore.ImportedProfiles) -> ConfigurationStore.ImportedProfiles {
        var document = document
        for profile in document.profiles.indices {
            for page in document.profiles[profile].pages.indices {
                for slot in document.profiles[profile].pages[page].cells.indices {
                    document.profiles[profile].pages[page].cells[slot] = withoutLongMenuShortcut(document.profiles[profile].pages[page].cells[slot])
                }
            }
        }
        for position in document.sharedCells.occupiedPositions {
            document.sharedCells[position] = withoutLongMenuShortcut(document.sharedCells[position])
        }
        return document
    }

    private static func withoutLongMenuShortcut(_ cell: Cell?) -> Cell? {
        guard var cell, case .menuItem(var menu) = cell.action,
              let keys = menu.keyEquivalent, keys.chords.count != 1 else { return cell }
        menu.keyEquivalent = nil
        cell.action = .menuItem(menu)
        return cell
    }

    // MARK: 読み込みの決まり

    /// 読み込みで使われるプロファイル。グローバルや同じアプリが重なっていれば最初のものだけ、bundle ID の無いアプリは除く
    /// （NonetConfiguration.importProfiles と同じ決まり）
    static func usedProfiles(in document: ConfigurationStore.ImportedProfiles) -> [Profile] {
        var seen = Set<String>()
        var hasGlobal = false
        return document.profiles.filter { profile in
            guard let app = profile.app else {
                defer { hasGlobal = true }
                return !hasGlobal
            }
            let key = bundleIDKey(app.bundleID)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    /// ファイルの中のアプリ。同じアプリが重なっていれば最初のものだけ（読み込みと同じ決まり）
    private static func importedApps(in document: ConfigurationStore.ImportedProfiles) -> [AppReference] {
        usedProfiles(in: document).compactMap(\.app)
    }

    /// 有効・無効にかかわらず、同じアプリのプロファイル（読み込みはこれを置き換える）
    private static func existingProfile(for app: AppReference, in configuration: NonetConfiguration) -> Profile? {
        let key = bundleIDKey(app.bundleID)
        guard !key.isEmpty else { return nil }
        return configuration.profiles.first { $0.app.map { bundleIDKey($0.bundleID) == key } == true }
    }

    /// bundle ID は大文字と小文字を区別しない（NonetConfiguration と同じ）
    private static func bundleIDKey(_ bundleID: String) -> String {
        bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

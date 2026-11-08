// 担当: ui-settings
// プロファイルの読み込みを、実際に設定へ入れる前に写しで試した結果。置き換わるものや、何かを実行するマスがあれば先に確かめる
import AppKit
import NonetCore

struct SettingsImportPlan: Identifiable, Equatable {
    /// 読み込む前に中身を見せるマスと、それがあるプロファイルの名前
    struct ReviewedCell: Equatable {
        var profileName: String
        var cell: Cell
        /// Return と同じ働きのキー（Return・Enter・⌃M・⌃J・⌃C など、今のキー配列で改行や Enter の文字になるもの）か ⌃ の付いたキーを押す。
        /// コマンドの実行やメッセージの送信になりうるので、確かめるときに目立たせる
        var pressesSubmitKey = false
        /// マスのあるアプリのプロファイルのアプリ（グローバルなら nil）。ファイルの中の名前だけでなく bundle ID も見せる
        var app: AppReference? = nil
        /// この Mac にある、app の bundle ID のアプリの名前（表示名・CFBundleDisplayName・CFBundleName の、今の言語と元の言語）。
        /// 無ければ空。ファイルの中の名前がどれとも違えば目立たせる（最初のものを見せる）
        var installedAppNames: [String] = []
        /// キーコードで書いたキーを含むキー入力が、今のキー配列で打つ文字（⌘・⌃ の付かないキーをすべて、順に）。無ければ nil。
        /// 「keyCode(8)」のような表記では何を打つか分からず、文字と混ぜて書いた命令も見つけられないので、つなげて文字にして見せる。
        var keyCodeText: String? = nil
        /// キー入力を、打ち方の決まりを変えて打ったもの（textsTyped。キーコードを含まなくても）。注意が要る命令は、このどれかにあれば知らせる
        var typedTexts: [String] = []
        /// 文字を打ち、それを消す・打つ場所を動かす・補完するキー（⌫・矢印・Tab・Esc など）も押す（editsTypedText）。
        /// 打たれる文字はアプリ（シェルの決まり・履歴・補完）によって変わり、見せる文字のとおりとは限らないので、目立たせる
        var editsTypedText = false
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
        keys: (any SettingsKeyCharacterTranslating)? = nil,
        installedAppNames: (String) -> [String] = SettingsImportPlan.lookUpInstalledAppNames
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
        // アプリの名前は、プロファイルごとに1回だけ調べる
        let sources: [(name: String, app: AppReference?, installed: [String], cells: [Cell?])] = Self.usedProfiles(in: document).map { profile in
            (profile.name, profile.app, profile.app.map { installedAppNames($0.bundleID) } ?? [], profile.pages.flatMap(\.cells))
        }
        reviewedCells = sources.flatMap { source -> [ReviewedCell] in
            source.cells.compactMap { cell -> ReviewedCell? in
                guard let cell, Self.needsReview(cell.action) else { return nil }
                return ReviewedCell(
                    profileName: source.name,
                    cell: cell,
                    pressesSubmitKey: Self.pressesSubmitKey(cell.action, keys: keys),
                    app: source.app,
                    installedAppNames: source.installed,
                    keyCodeText: Self.textTypedByKeyCodes(cell.action, keys: keys),
                    typedTexts: Self.textsTyped(cell.action, keys: keys) ?? [],
                    editsTypedText: Self.editsTypedText(cell.action, keys: keys)
                )
            }
        }
    }

    /// 今の設定を上書きする（グローバルのページ・同じアプリのプロファイル）
    var replacesExisting: Bool { result.replacedGlobal || !replacedNames.isEmpty }

    /// 新しく加わるアプリのプロファイルがある
    var addsProfiles: Bool { result.added > 0 }

    /// 読み込まれるプロファイルに、中身を見せるマスがある
    var hasReviewedCells: Bool { !reviewedCells.isEmpty }

    /// 読み込む前に確かめる（置き換わるものがあるか、何かを実行するマスがある）
    var needsConfirmation: Bool { replacesExisting || hasReviewedCells }

    /// 置き換えるものを除いた中身（新しいアプリのプロファイルだけ加えるとき）。設定はその時点のもので決める
    func newProfilesOnly(in configuration: NonetConfiguration) -> ConfigurationStore.ImportedProfiles {
        let profiles = document.profiles.filter { profile in
            guard let app = profile.app else { return false }
            return Self.existingProfile(for: app, in: configuration) == nil
        }
        return ConfigurationStore.ImportedProfiles(profiles: profiles, unreadableCount: document.unreadableCount)
    }

    /// 読み込みで実際に使われるプロファイルが、スクリプトのマスを含む（読み込んだ後の知らせ）
    static func containsScripts(in document: ConfigurationStore.ImportedProfiles) -> Bool {
        containsScripts(usedProfiles(in: document))
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
    /// Finder で選んだファイルを動かす（ゴミ箱に入れる・名前を変える・複製する）、
    /// Mac の中のファイルを開く URL（.command や .app も開ける）と、別のものを動かす URL（ショートカットの実行・ssh・共有フォルダなど）
    static func needsReview(_ action: Action) -> Bool {
        switch action {
        case .script, .keystroke, .menuItem, .ai, .shortcut:
            true
        case .file:
            // Finder で選んだファイルをゴミ箱に入れる・名前を変える・複製する
            true
        case .openURL(let url):
            !opensWebOrMail(url.url)
        case .launchApp, .placeWindow:
            false
        }
    }

    /// この Mac にある、その bundle ID のアプリの名前の候補（表示名、今の言語と元の言語の CFBundleDisplayName・CFBundleName）。
    /// 無ければ空。プロファイルの名前は前面のアプリの名前や Info.plist の名前から付くので、どれかと同じなら名乗り違いではない
    static func lookUpInstalledAppNames(_ bundleID: String) -> [String] {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return [] }
        var names: [String] = []
        func add(_ name: String?) {
            guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, !names.contains(name) else { return }
            names.append(name)
        }
        let display = FileManager.default.displayName(atPath: url.path)
        add(display.hasSuffix(".app") ? String(display.dropLast(4)) : display)
        let bundle = Bundle(url: url)
        for info in [bundle?.localizedInfoDictionary, bundle?.infoDictionary] {
            add(info?["CFBundleDisplayName"] as? String)
            add(info?["CFBundleName"] as? String)
        }
        return names
    }

    /// 確かめずに読み込んでよいスキーム（ウェブのページとメールの宛先）
    static let webSchemes: Set<String> = ["http", "https", "mailto"]

    /// ウェブのページかメールの宛先を開く URL か（スキームを省いたホストも、開くときに http(s) を補うので含める）。
    /// ほかのスキームは、どれが何を動かすかがアプリしだいで数え上げられない（ショートカットの実行・共有フォルダへの接続など）ので、
    /// Mac の中のファイルと同じく、読み込む前に見せる
    static func opensWebOrMail(_ url: String) -> Bool {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if opensLocalFile(text) { return false }
        if text.hasPrefix("//") || !SettingsURLCheck.hasScheme(text) { return true }
        guard let colon = text.firstIndex(of: ":") else { return true }
        return webSchemes.contains(text[..<colon].lowercased())
    }

    /// キーコードで書いたキーを含むキー入力が、今のキー配列で打つ文字（⌘・⌃ の付かないキーを、文字で書いたものも含めて順に）。
    /// ⌫・⌦・矢印は、打った文字を消したり、打つ場所を動かしたりする（TypedText）。見せるのは、ターミナルと標準の入力欄の
    /// 決まり（Home・End は打つ場所を動かさない）で打ったもの。キーコードを含まない・文字にならなければ nil
    static func textTypedByKeyCodes(_ action: Action, keys translator: (any SettingsKeyCharacterTranslating)?) -> String? {
        guard case .keystroke(let sequence) = action, translator != nil,
              sequence.chords.contains(where: { if case .keyCode = $0.key { true } else { false } }) else { return nil }
        return textsTyped(action, keys: translator)?.first
    }

    /// 打ち方の決まりを変えて打ったものをすべて（最初は見せるもの）。注意が要る命令は、このどれかに入っていれば知らせる。
    /// アプリによって Home・End や ⌥⌫ の働きが違い、どれか1つの決まりで打ったものだけを見ると、別の決まりのアプリで打つ命令を隠せる
    /// （「rm」Home ⌦ ⏎ は、Home で行の頭へ移るアプリでは「m」、移らないターミナルでは rm を打つ）。
    /// 消すキーを使わずに打ったもの（raw）と、⏎ が改行を入れるだけのもの（fish の続きの行・エディタ）も見る。
    /// ここで写せないもの（シェルの履歴・補完・語の決まり）は、editsTypedText で目立たせる
    static func textsTyped(_ action: Action, keys translator: (any SettingsKeyCharacterTranslating)?) -> [String]? {
        guard case .keystroke(let sequence) = action else { return nil }
        let rules: [TypedText.Rules] = [
            .init(homeEndMove: false, optionByWord: true),
            .init(homeEndMove: false, optionByWord: false),
            .init(homeEndMove: true, optionByWord: true),
            .init(homeEndMove: true, optionByWord: false),
            .init(homeEndMove: false, optionByWord: true, returnSendsLine: false),
            .raw,
        ]
        var texts: [String] = []
        for rule in rules {
            var typed = TypedText(rules: rule)
            for chord in sequence.chords where chord.modifiers.isDisjoint(with: [.command, .control]) {
                let byWord = chord.modifiers.contains(.option)
                if let characters = translator?.characters(for: chord) {
                    // キーコードの ⌫ や矢印は、制御文字として返る
                    for character in characters { typed.type(character, byWord: byWord) }
                } else if case .character(let text) = chord.key {
                    for character in text { typed.type(character, byWord: byWord) }
                } else if case .special(let key) = chord.key {
                    typed.press(key, byWord: byWord)
                }
                // 文字を打たないキー（修飾キー・消音・英数・かな・↑↓・Esc・F キーなど）は何もしない。区切りにすると、
                // 「r」修飾キー「m」が「r m」に見えて、実際に打つ「rm」を見逃す
            }
            let text = String(typed.characters)
            if !text.isEmpty, !texts.contains(text) { texts.append(text) }
        }
        return texts.isEmpty ? nil : texts
    }

    /// 文字を打ち、それを消す・打つ場所を動かす・補完するキー（⌫・⌦・矢印・Home・End・Page Up/Down・Esc・Tab）も押すか。
    /// キーコードで書いたそれらのキー（制御文字になる）も数える。⌘・⌃ の付いたキーは数えない（⌃ は pressesSubmitKey で目立たせる）
    static func editsTypedText(_ action: Action, keys translator: (any SettingsKeyCharacterTranslating)?) -> Bool {
        guard case .keystroke(let sequence) = action else { return false }
        let editKeys: Set<SpecialKey> = [.delete, .forwardDelete, .leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end, .pageUp, .pageDown, .escape, .tab]
        var typesText = false
        var edits = false
        for chord in sequence.chords where chord.modifiers.isDisjoint(with: [.command, .control]) {
            let text: String?
            if let characters = translator?.characters(for: chord) {
                text = characters
            } else if case .character(let character) = chord.key {
                text = character
            } else {
                text = nil
            }
            if let text {
                for scalar in text.unicodeScalars {
                    switch scalar.value {
                    // Return と同じ文字は、消す・動かすキーではない
                    case 0x0D, 0x0A, 0x03:
                        break
                    case 0x00..<0x20, 0x7F:
                        edits = true
                    default:
                        typesText = true
                    }
                }
            } else if case .special(let key) = chord.key {
                if editKeys.contains(key) { edits = true }
                if key == .space { typesText = true }
            }
        }
        return typesText && edits
    }

    /// 1行の入力欄で打った結果。打つ場所（cursor）に文字を入れ、⌫・⌦ で消し、←→（と、決まりによって Home・End）で打つ場所を動かす。
    /// ⌥ を付けた ←→⌫⌦ は、決まりによって語ごと。Space・Tab は語の区切り。Return は行を送る（送った行は、後の ⌫ や ← では変わらない）。
    /// 消してから打った文字（「x」⌫「rm」）や、戻って前に打った文字（「m」←「r」）も、実際に打つ並びにして命令を探す
    struct TypedText {
        struct Rules {
            /// Home・End で打つ場所を行の頭・終わりへ動かす（ターミナルや標準の入力欄は動かさない）
            var homeEndMove: Bool
            /// ⌥ を付けた ←→⌫⌦ を語ごとにする
            var optionByWord: Bool
            /// ⏎ で行を送る（送った行は後の ⌫ や ← では変わらない）。false なら、区切りを入れて同じ行を打ち続ける
            var returnSendsLine = true
            /// ⌫・⌦・矢印などを効かせる。false なら、打った文字をそのまま並べる
            var appliesEdits = true

            static let raw = Rules(homeEndMove: false, optionByWord: false, appliesEdits: false)
        }

        let rules: Rules
        /// Return で送った行（区切りの空白つき）
        private var sent: [Character] = []
        private var line: [Character] = []
        private var cursor = 0

        init(rules: Rules) {
            self.rules = rules
        }

        var characters: [Character] { sent + line }

        mutating func type(_ character: Character, byWord: Bool) {
            switch character.unicodeScalars.first?.value ?? 0 {
            case 0x08:
                press(.delete, byWord: byWord)
            case 0x7F:
                press(.forwardDelete, byWord: byWord)
            case 0x0D, 0x0A, 0x03:
                press(.returnKey, byWord: byWord)
            case 0x09:
                press(.tab, byWord: byWord)
            case 0x1C:
                press(.leftArrow, byWord: byWord)
            case 0x1D:
                press(.rightArrow, byWord: byWord)
            case 0x01:
                press(.home, byWord: byWord)
            case 0x04:
                press(.end, byWord: byWord)
            case 0x00..<0x20:
                // ほかの制御文字（↑↓・Esc など）は文字を打たない
                break
            default:
                insert(character)
            }
        }

        mutating func press(_ key: SpecialKey, byWord: Bool) {
            let byWord = byWord && rules.optionByWord
            switch key {
            case .space, .tab:
                insert(" ")
            case .returnKey where rules.returnSendsLine:
                sent += line + [" "]
                line = []
                cursor = 0
            case .returnKey:
                cursor = line.count
                insert(" ")
            case _ where !rules.appliesEdits:
                break
            case .delete:
                let start = byWord ? wordStart(before: cursor) : max(0, cursor - 1)
                line.removeSubrange(start..<cursor)
                cursor = start
            case .forwardDelete:
                let end = byWord ? wordEnd(after: cursor) : min(line.count, cursor + 1)
                line.removeSubrange(cursor..<end)
            case .leftArrow:
                cursor = byWord ? wordStart(before: cursor) : max(0, cursor - 1)
            case .rightArrow:
                cursor = byWord ? wordEnd(after: cursor) : min(line.count, cursor + 1)
            case .home where rules.homeEndMove:
                cursor = 0
            case .end where rules.homeEndMove:
                cursor = line.count
            default:
                break
            }
        }

        private mutating func insert(_ character: Character) {
            line.insert(character, at: cursor)
            cursor += 1
        }

        private func wordStart(before position: Int) -> Int {
            var index = position
            while index > 0, line[index - 1].isWhitespace { index -= 1 }
            while index > 0, !line[index - 1].isWhitespace { index -= 1 }
            return index
        }

        private func wordEnd(after position: Int) -> Int {
            var index = position
            while index < line.count, line[index].isWhitespace { index += 1 }
            while index < line.count, !line[index].isWhitespace { index += 1 }
            return index
        }
    }

    /// キー入力かメニュー項目のショートカットが、Return と同じ働きのキーか ⌃ の付いたキーを押す
    static func pressesSubmitKey(_ action: Action, keys translator: (any SettingsKeyCharacterTranslating)?) -> Bool {
        switch action {
        case .keystroke(let keys):
            pressesSubmitKey(keys, keys: translator)
        case .menuItem(let menu):
            menu.keyEquivalent.map { pressesSubmitKey($0, keys: translator) } ?? false
        case .script, .ai, .openURL, .launchApp, .shortcut, .file, .placeWindow:
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

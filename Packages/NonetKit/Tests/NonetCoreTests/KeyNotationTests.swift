import Testing
@testable import NonetCore

@Suite struct KeyNotationTests {
    private static func char(_ character: String, _ modifiers: ModifierSet = []) -> KeyChord {
        KeyChord(.character(character), modifiers: modifiers)
    }

    private static func special(_ special: SpecialKey, _ modifiers: ModifierSet = []) -> KeyChord {
        KeyChord(.special(special), modifiers: modifiers)
    }

    // MARK: - 表示

    static let displayCases: [(KeyChord, String)] = [
        (char("b", .command), "⌘B"),
        (char("4", [.shift, .command]), "⇧⌘4"),
        (char("4", [.command, .shift]), "⇧⌘4"),
        (char("a", [.command, .shift, .option, .control]), "⌃⌥⇧⌘A"),
        (char("c", [.control, .command]), "⌃⌘C"),
        (char("e", [.option]), "⌥E"),
        (char("q"), "Q"),
        (char("["), "["),
        (char("[", .command), "⌘["),
        (char("\\", .command), "⌘\\"),
        (char(",", .command), "⌘,"),
        (char(".", .command), "⌘."),
        (char("+", .command), "⌘+"),
        (char("-", .command), "⌘-"),
        (char("=", [.shift, .command]), "⇧⌘="),
        (char("1", .shift), "⇧1"),
        (char("/", [.shift, .command]), "⇧⌘/"),
        (char("`", .command), "⌘`"),
        (char("¥"), "¥"),
        (char("ü", .option), "⌥Ü"),
        (char("ß"), "ß"),
        (char("f", .function), "fn F"),
        (char("e", [.function, .control]), "fn ⌃E"),
        (special(.leftArrow, [.function, .control]), "fn ⌃←"),
        (special(.returnKey), "↩"),
        (special(.returnKey, .command), "⌘↩"),
        (special(.tab, [.control, .shift]), "⌃⇧⇥"),
        (special(.space, [.control, .command]), "⌃⌘Space"),
        (special(.delete, .command), "⌘⌫"),
        (special(.forwardDelete), "⌦"),
        (special(.escape, [.option, .command]), "⌥⌘⎋"),
        (special(.leftArrow), "←"),
        (special(.rightArrow, .command), "⌘→"),
        (special(.upArrow, .shift), "⇧↑"),
        (special(.downArrow), "↓"),
        (special(.home), "↖"),
        (special(.end, .shift), "⇧↘"),
        (special(.pageUp), "⇞"),
        (special(.pageDown, .option), "⌥⇟"),
        (special(.f1), "F1"),
        (special(.f12, .command), "⌘F12"),
        (special(.f20), "F20"),
        (special(.eisu), "英数"),
        (special(.kana, .command), "⌘かな"),
        (KeyChord(.keyCode(53), modifiers: .command), "⌘keyCode(53)"),
        (KeyChord(.keyCode(0)), "keyCode(0)"),
        // メニューのキーで使われる制御文字
        (char(" ", .control), "⌃Space"),
        (char("\r", .command), "⌘↩"),
        (char("\u{3}"), "↩"),
        (char("\t"), "⇥"),
        (char("\u{8}", .command), "⌘⌫"),
        (char("\u{7F}"), "⌫"),
        (char("\u{1B}"), "⎋"),
        (char("\u{1}"), "U+0001"),
        (char("\u{F700}", .command), "⌘U+F700"),
        // 前の文字にくっつく文字（そのまま書くと ⌘ と1文字になってしまう）
        (char("\u{301}", .command), "⌘U+0301"),
        (char("\u{FE0F}"), "U+FE0F"),
        (char("\u{FE0E}", .option), "⌥U+FE0E"),
        (char("\u{1F3FB}", .shift), "⇧U+1F3FB"),
        (char("\u{903}"), "U+0903"),
        (char("\u{20DD}", .function), "fn U+20DD"),
        (char("\u{200D}", .command), "⌘U+200D"),
        // 後ろの空白とくっつく文字
        (char("\u{D4E}", .command), "⌘U+0D4E"),
        // 複数の符号位置でも1文字として立つものはそのまま
        (char("e\u{301}", .command), "⌘E\u{301}"),
        (char("❤\u{FE0E}"), "❤\u{FE0E}"),
    ]

    @Test func escapedCharactersStayOneCharacterAfterTheModifiers() throws {
        for character in ["\u{301}", "\u{FE0F}", "\u{1F3FB}", "\u{903}", "\u{D4E}"] {
            let display = KeyChord(.character(character), modifiers: .command).displayString
            #expect(display.hasPrefix("⌘U+"))
            let parsed = try #require(KeySequence(parsing: display))
            #expect(parsed.chords == [Self.char(character, .command)])
        }
    }

    @Test(arguments: displayCases)
    func chordDisplay(chord: KeyChord, expected: String) {
        #expect(chord.displayString == expected)
    }

    @Test func sequenceDisplay() {
        let copyURL = KeySequence.sequence(.key("l", .command), .key("c", .command))
        #expect(copyURL.displayString == "⌘L → ⌘C")
        #expect(KeySequence.key("4", [.shift, .command]).displayString == "⇧⌘4")
        #expect(KeySequence.special(.rightArrow).displayString == "→")
        let arrows = KeySequence.sequence(.special(.rightArrow), .special(.rightArrow, .command))
        #expect(arrows.displayString == "→ → ⌘→")
        #expect(KeySequence([]).displayString == "")
    }

    @Test func presetShortcutUppercasesInput() {
        // KeySequence.key は英字を小文字で持つ
        #expect(KeySequence.key("B", .command) == KeySequence([KeyChord(.character("b"), modifiers: .command)]))
        #expect(KeySequence.key("B", .command).displayString == "⌘B")
    }

    // MARK: - 読み取り

    static let parseCases: [(String, [KeyChord])] = [
        // 表示と同じ書式
        ("⌘B", [char("b", .command)]),
        ("⇧⌘4", [char("4", [.shift, .command])]),
        ("⌘L → ⌘C", [char("l", .command), char("c", .command)]),
        ("fn ⌃←", [special(.leftArrow, [.function, .control])]),
        ("fn F", [char("f", .function)]),
        ("⌘keyCode(53)", [KeyChord(.keyCode(53), modifiers: .command)]),
        // 修飾キーの順・空白・小文字
        ("⌘⇧4", [char("4", [.shift, .command])]),
        ("⌘⌃⌥⇧a", [char("a", [.command, .shift, .option, .control])]),
        ("  ⌘ b  ", [char("b", .command)]),
        ("⌘l→⌘c", [char("l", .command), char("c", .command)]),
        ("⌘L->⌘C", [char("l", .command), char("c", .command)]),
        ("⌘L -> ⌘C", [char("l", .command), char("c", .command)]),
        ("⌘L, ⌘C", [char("l", .command), char("c", .command)]),
        ("⌘L,⌘C,⌘V", [char("l", .command), char("c", .command), char("v", .command)]),
        ("⌘L\n→\n⌘C", [char("l", .command), char("c", .command)]),
        // 英語の修飾キー
        ("cmd+b", [char("b", .command)]),
        ("Cmd+Shift+4", [char("4", [.shift, .command])]),
        ("command + option + esc", [special(.escape, [.command, .option])]),
        ("opt+e", [char("e", .option)]),
        ("alt+e", [char("e", .option)]),
        ("ctrl+opt+cmd+space", [special(.space, [.control, .option, .command])]),
        ("Control+Tab", [special(.tab, .control)]),
        ("fn+f", [char("f", .function)]),
        ("cmd+l -> cmd+c", [char("l", .command), char("c", .command)]),
        ("cmd+k, cmd+s", [char("k", .command), char("s", .command)]),
        ("⌘+C", [char("c", .command)]),
        ("shift ⌘ 4", [char("4", [.shift, .command])]),
        // 区切りや記号と紛らわしい文字
        ("command+backslash", [char("\\", .command)]),
        ("command+\\", [char("\\", .command)]),
        ("command+[", [char("[", .command)]),
        ("command+]", [char("]", .command)]),
        ("shift+1", [char("1", .shift)]),
        ("command+comma", [char(",", .command)]),
        ("command+,", [char(",", .command)]),
        ("cmd+,", [char(",", .command)]),
        ("⌘,", [char(",", .command)]),
        ("command+period", [char(".", .command)]),
        ("command+.", [char(".", .command)]),
        ("command+plus", [char("+", .command)]),
        ("cmd++", [char("+", .command)]),
        ("cmd + +", [char("+", .command)]),
        ("⌘+", [char("+", .command)]),
        ("⌘++", [char("+", .command)]),
        ("+", [char("+")]),
        ("command+minus", [char("-", .command)]),
        ("⌘-", [char("-", .command)]),
        ("⌘- -> ⌘=", [char("-", .command), char("=", .command)]),
        ("⌘-->⌘=", [char("-", .command), char("=", .command)]),
        (",", [char(",")]),
        (", → ,", [char(","), char(",")]),
        (",,,", [char(","), char(",")]),
        ("→", [special(.rightArrow)]),
        ("→ → →", [special(.rightArrow), special(.rightArrow)]),
        ("⌘→ → ⌘←", [special(.rightArrow, .command), special(.leftArrow, .command)]),
        ("⌘+ → +", [char("+", .command), char("+")]),
        ("⌘+ → →", [char("+", .command), special(.rightArrow)]),
        ("⌘, → ⌘.", [char(",", .command), char(".", .command)]),
        ("cmd+,, cmd+.", [char(",", .command), char(".", .command)]),
        // キーの名前
        ("Return", [special(.returnKey)]),
        ("cmd+enter", [special(.returnKey, .command)]),
        ("⌘Space", [special(.space, .command)]),
        ("⌃⌘スペース", [special(.space, [.control, .command])]),
        ("⌃␣", [special(.space, .control)]),
        ("backspace", [special(.delete)]),
        ("forwardDelete", [special(.forwardDelete)]),
        ("esc", [special(.escape)]),
        ("cmd+left", [special(.leftArrow, .command)]),
        ("cmd+downArrow", [special(.downArrow, .command)]),
        ("pgup", [special(.pageUp)]),
        ("PageDown", [special(.pageDown)]),
        ("home", [special(.home)]),
        ("end", [special(.end)]),
        ("f5", [special(.f5)]),
        ("shift+F13", [special(.f13, .shift)]),
        ("英数", [special(.eisu)]),
        ("かな", [special(.kana)]),
        ("eisu", [special(.eisu)]),
        ("⏎", [special(.returnKey)]),
        ("keyCode53", [KeyChord(.keyCode(53))]),
        ("cmd+keycode( 65535 )", [KeyChord(.keyCode(65535), modifiers: .command)]),
        ("U+0001", [char("\u{1}")]),
        ("🌐E", [char("e", .function)]),
        ("globe+e", [char("e", .function)]),
        ("ü", [char("ü")]),
        ("Ü", [char("ü")]),
        ("⌥ß", [char("ß", .option)]),
        ("ー", [char("ー")]),
        // コピーした表記に付いてくる異体字セレクタ（↩ ↖ ↘ などは絵文字の見た目もある）
        ("⌥⌘↩\u{FE0E}", [special(.returnKey, [.option, .command])]),
        ("⌘↩\u{FE0F}", [special(.returnKey, .command)]),
        ("↖\u{FE0E}", [special(.home)]),
        ("⇧↘\u{FE0F}", [special(.end, .shift)]),
        ("⌘\u{FE0E}↑", [special(.upArrow, .command)]),
        ("⌘L →\u{FE0E} ⌘C", [char("l", .command), char("c", .command)]),
        ("→\u{FE0E} → ⌘→\u{FE0F}", [special(.rightArrow), special(.rightArrow, .command)]),
        ("🌐\u{FE0F}E", [char("e", .function)]),
        ("⌘U+FE0F", [char("\u{FE0F}", .command)]),
        ("⌘❤\u{FE0E}", [char("❤\u{FE0E}", .command)]),
        ("⌘👍\u{1F3FB}", [char("👍\u{1F3FB}", .command)]),
    ]

    @Test(arguments: parseCases)
    func parse(text: String, expected: [KeyChord]) {
        #expect(KeySequence(parsing: text)?.chords == expected)
    }

    static let rejectedCases: [String] = [
        "",
        "   ",
        "\n",
        "⌘",
        "⇧⌘",
        "cmd",
        "cmd+shift",
        "fn",
        "⌘C →",
        "⌘C ->",
        "⌘C,",
        "→ ⌘C",
        ", ⌘C",
        "⌘C ⌘V",
        "⌘C⌘V",
        "⌘CV",
        "C⌘",
        "abc",
        "cmdc",
        "hyper+c",
        "cmd+foo",
        "F21",
        "F0",
        "⌘12",
        "keyCode(70000)",
        "keyCode()",
        "keyCode(",
        "keyCode(5",
        "keyCodeX",
        "U+12",
        "U+1234567",
        "⌘->⌘=",
        "⌘C,,⌘V",
        "\u{1}",
        "⌘\u{200B}",
        "cmd-c",
        // 単独の結合文字や異体字セレクタは U+XXXX と書く
        "\u{301}",
        "\u{FE0F}",
        "\u{1F3FB}",
        "⌘\u{FE0F}",
    ]

    @Test(arguments: rejectedCases)
    func rejects(text: String) {
        #expect(KeySequence(parsing: text) == nil)
    }

    @Test func rejectsVeryLongInput() {
        let text = Array(repeating: "⌘C", count: 600).joined(separator: ",")
        #expect(KeySequence(parsing: text) == nil)
        let shorter = Array(repeating: "⌘C", count: 300).joined(separator: ",")
        #expect(KeySequence(parsing: shorter)?.chords.count == 300)
    }

    @Test func handlesPathologicalPlusChainsQuickly() {
        // つなぎと「+」キーの読み分けが指数的に増えないこと
        let chain = String(repeating: "⌘+", count: 400) + "x"
        #expect(KeySequence(parsing: chain)?.chords == [Self.char("x", .command)])
        #expect(KeySequence(parsing: String(repeating: "⌘+", count: 400) + "x ⌘") == nil)
        // 「+」をどちらで読んでも「,」が続くので、両方の読み方が最後まで残る
        let ambiguous = String(repeating: "⌘+ , , ", count: 120)
        #expect(KeySequence(parsing: ambiguous + "⌘") == nil)
        #expect(KeySequence(parsing: ambiguous + "x") != nil)
    }

    // MARK: - 往復

    @Test func roundTripsEverySpecialKeyWithEveryModifierCombination() throws {
        for special in SpecialKey.allCases {
            for modifiers in Self.allModifierCombinations {
                let sequence = KeySequence([KeyChord(.special(special), modifiers: modifiers)])
                let parsed = try #require(KeySequence(parsing: sequence.displayString), "\(sequence.displayString)")
                #expect(parsed == sequence, "\(sequence.displayString)")
            }
        }
    }

    @Test func roundTripsEveryCharacterWithEveryModifierCombination() throws {
        for character in Self.characters {
            for modifiers in Self.allModifierCombinations {
                let sequence = KeySequence([KeyChord(.character(character), modifiers: modifiers)])
                let parsed = try #require(KeySequence(parsing: sequence.displayString), "\(sequence.displayString)")
                #expect(parsed == sequence, "\(sequence.displayString)")
            }
        }
    }

    @Test func roundTripsKeyCodes() throws {
        for code: UInt16 in [0, 1, 53, 127, 255, 1000, .max] {
            let sequence = KeySequence([KeyChord(.keyCode(code), modifiers: [.command, .option])])
            #expect(KeySequence(parsing: sequence.displayString) == sequence)
        }
    }

    @Test func roundTripsGeneratedSequences() throws {
        var generator = KeyNotationRandom(seed: 0x4E6F_6E65_74)
        let keys = Self.characters.map(Key.character) + SpecialKey.allCases.map(Key.special) + [.keyCode(53), .keyCode(0)]
        for _ in 0..<3000 {
            let length = Int.random(in: 1...5, using: &generator)
            let chords = (0..<length).map { _ in
                KeyChord(
                    keys[Int.random(in: keys.indices, using: &generator)],
                    modifiers: Self.allModifierCombinations[Int.random(in: Self.allModifierCombinations.indices, using: &generator)]
                )
            }
            let sequence = KeySequence(chords)
            let parsed = try #require(KeySequence(parsing: sequence.displayString), "\(sequence.displayString)")
            #expect(parsed == sequence, "\(sequence.displayString)")
        }
    }

    @Test func roundTripsSequencesMadeOfSeparatorLikeKeys() throws {
        // 区切りと同じ記号のキーばかりを並べても、往復できること
        let pieces: [KeyChord] = [
            Self.char(","), Self.char("+"), Self.char("-"), Self.char(">"), Self.special(.rightArrow),
            Self.char("+", .command), Self.char(",", .command), Self.special(.rightArrow, .command),
            Self.char("+", .function), Self.char("-", .shift),
        ]
        var generator = KeyNotationRandom(seed: 42)
        for _ in 0..<3000 {
            let chords = (0..<Int.random(in: 1...6, using: &generator)).map { _ in pieces[Int.random(in: pieces.indices, using: &generator)] }
            let sequence = KeySequence(chords)
            let parsed = try #require(KeySequence(parsing: sequence.displayString), "\(sequence.displayString)")
            #expect(parsed == sequence, "\(sequence.displayString)")
        }
    }

    @Test func displayIsStableAfterParsing() throws {
        // 寛容な書き方も、読んだ後は決まった表記になる
        for text in ["cmd+shift+4", "⌘⇧4", "Shift+Command+4", "⌘ ⇧ 4"] {
            #expect(try #require(KeySequence(parsing: text)).displayString == "⇧⌘4")
        }
        #expect(try #require(KeySequence(parsing: "cmd+l, cmd+c")).displayString == "⌘L → ⌘C")
    }

    // MARK: - 生成するデータ

    static let allModifierCombinations: [ModifierSet] = (0..<32).map { ModifierSet(rawValue: UInt8($0)) }

    /// 小文字の英字・数字・ASCII の記号・JIS や欧州の配列にある文字・見えない文字・前後にくっつく文字
    static let characters: [String] = {
        var characters = (UInt8(ascii: "a")...UInt8(ascii: "z")).map { String(UnicodeScalar($0)) }
        characters += (0...9).map(String.init)
        characters += "`-=[]\\;',./~!@#$%^&*()_+{}|:\"<>?".map(String.init)
        characters += ["¥", "ü", "ö", "ä", "é", "ç", "ñ", "ß", "ø", "å", "ー", "か", "な", "英", "§", "±", "«", "€", "´", "¨"]
        characters += ["\u{1}", "\u{1F}", "\u{0}", "\u{F700}", "\u{3000}", "\u{200B}", "\u{85}"]
        // 結合文字（Mn / Mc / Me）・異体字セレクタ・肌の色・ZWJ・後ろにくっつく文字（Prepend）
        characters += ["\u{301}", "\u{308}", "\u{3099}", "\u{903}", "\u{20DD}", "\u{FE0E}", "\u{FE0F}", "\u{E0100}", "\u{1F3FB}", "\u{200D}", "\u{D4E}"]
        // 複数の符号位置でできた1文字
        characters += ["e\u{301}", "❤\u{FE0E}", "👍\u{1F3FB}"]
        return characters
    }()
}

/// テスト用の決まった乱数
private struct KeyNotationRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

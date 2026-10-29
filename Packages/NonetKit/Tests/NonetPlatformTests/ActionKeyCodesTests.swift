import Carbon.HIToolbox
import CoreGraphics
import NonetCore
@testable import NonetPlatform
import Testing

@Suite("キーコードとフラグ")
struct ActionKeyCodesTests {
    @Test("特殊キーは kVK の値になる", arguments: [
        (SpecialKey.returnKey, 0x24), (.tab, 0x30), (.space, 0x31), (.delete, 0x33), (.forwardDelete, 0x75),
        (.escape, 0x35), (.leftArrow, 0x7B), (.rightArrow, 0x7C), (.downArrow, 0x7D), (.upArrow, 0x7E),
        (.home, 0x73), (.end, 0x77), (.pageUp, 0x74), (.pageDown, 0x79),
        (.f1, 0x7A), (.f2, 0x78), (.f3, 0x63), (.f4, 0x76), (.f5, 0x60), (.f6, 0x61), (.f7, 0x62), (.f8, 0x64),
        (.f9, 0x65), (.f10, 0x6D), (.f11, 0x67), (.f12, 0x6F), (.f13, 0x69), (.f14, 0x6B), (.f15, 0x71),
        (.f16, 0x6A), (.f17, 0x40), (.f18, 0x4F), (.f19, 0x50), (.f20, 0x5A),
        (.eisu, 0x66), (.kana, 0x68),
    ])
    func specialKeyCode(key: SpecialKey, expected: Int) {
        #expect(VirtualKeyTable.keyCode(for: key) == CGKeyCode(expected))
    }

    @Test("特殊キーのコードは重ならず、逆引きできる")
    func specialKeysAreDistinctAndReversible() {
        let codes = SpecialKey.allCases.map(VirtualKeyTable.keyCode(for:))
        #expect(Set(codes).count == SpecialKey.allCases.count)
        for key in SpecialKey.allCases {
            #expect(VirtualKeyTable.specialKey(forKeyCode: VirtualKeyTable.keyCode(for: key)) == key)
        }
        #expect(VirtualKeyTable.specialKey(forKeyCode: CGKeyCode(kVK_ANSI_A)) == nil)
    }

    @Test("矢印は fn とテンキーのフラグ、F キーなどは fn のフラグを持つ")
    func implicitFlags() {
        for arrow in [SpecialKey.leftArrow, .rightArrow, .upArrow, .downArrow] {
            let flags = VirtualKeyTable.implicitFlags(forKeyCode: VirtualKeyTable.keyCode(for: arrow))
            #expect(flags.contains(.maskSecondaryFn))
            #expect(flags.contains(.maskNumericPad))
        }
        let functionKeys: [SpecialKey] = [.f1, .f5, .f12, .f20, .home, .end, .pageUp, .pageDown, .forwardDelete]
        for key in functionKeys {
            let flags = VirtualKeyTable.implicitFlags(forKeyCode: VirtualKeyTable.keyCode(for: key))
            #expect(flags.contains(.maskSecondaryFn), "\(key)")
            #expect(!flags.contains(.maskNumericPad), "\(key)")
        }
        for key in [SpecialKey.returnKey, .tab, .space, .delete, .escape, .eisu, .kana] {
            #expect(VirtualKeyTable.implicitFlags(forKeyCode: VirtualKeyTable.keyCode(for: key)).isEmpty, "\(key)")
        }
        #expect(VirtualKeyTable.implicitFlags(forKeyCode: CGKeyCode(kVK_ANSI_A)).isEmpty)
        #expect(VirtualKeyTable.implicitFlags(forKeyCode: CGKeyCode(kVK_ANSI_Keypad5)) == .maskNumericPad)
    }

    @Test("修飾キーのフラグは指定したものだけ")
    func modifierFlags() {
        let none = VirtualKeyTable.flags(for: [])
        #expect(!none.contains(.maskCommand))
        #expect(!none.contains(.maskShift))
        #expect(!none.contains(.maskAlternate))
        #expect(!none.contains(.maskControl))
        #expect(!none.contains(.maskSecondaryFn))

        let all = VirtualKeyTable.flags(for: [.command, .shift, .option, .control, .function])
        #expect(all.contains([.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]))

        let command = VirtualKeyTable.flags(for: .command)
        #expect(command.contains(.maskCommand))
        #expect(!command.contains(.maskShift))
        // 左⌘のデバイスビット
        #expect(command.rawValue & 0x08 != 0)

        let option = VirtualKeyTable.flags(for: .option)
        #expect(option.contains(.maskAlternate))
        #expect(!option.contains(.maskCommand))
        #expect(VirtualKeyTable.flags(for: .function) .contains(.maskSecondaryFn))
    }

    private static let fakeLayout = KeyboardLayoutMap(
        base: ["a": 0, "b": 11, "1": 18, "/": 44, "[": 33, " ": 49],
        shifted: ["A": 0, "!": 18, "?": 44],
        command: ["a": 0, "b": 11, "1": 18, "/": 44, "[": 33]
    )

    private func stroke(_ chord: KeyChord) throws -> KeyStroke {
        try KeyStrokeResolver.stroke(for: chord, keyboardType: ActionKeyboardType.ansi) { character, preferCommand, _ in
            Self.fakeLayout.match(character, preferCommandTable: preferCommand)
        }
    }

    @Test("文字はキー配列で探し、修飾キーはそのまま付ける")
    func resolvesCharacters() throws {
        let commandB = try stroke(KeyChord(.character("b"), modifiers: .command))
        #expect(commandB.keyCode == 11)
        #expect(commandB.flags.contains(.maskCommand))
        #expect(!commandB.flags.contains(.maskShift))

        let shiftCommandOne = try stroke(KeyChord(.character("1"), modifiers: [.command, .shift]))
        #expect(shiftCommandOne.keyCode == 18)
        #expect(shiftCommandOne.flags.contains([.maskCommand, .maskShift]))
    }

    @Test("大文字は同じキー（⇧は足さない）、⇧でしか出ない記号は⇧を足す")
    func uppercaseAndShiftedCharacters() throws {
        let upper = try stroke(KeyChord(.character("A"), modifiers: .command))
        #expect(upper.keyCode == 0)
        #expect(!upper.flags.contains(.maskShift))

        let question = try stroke(KeyChord(.character("?"), modifiers: .command))
        #expect(question.keyCode == 44)
        #expect(question.flags.contains([.maskCommand, .maskShift]))
    }

    @Test("打てない文字や2文字以上は NonetError")
    func unknownCharacterThrows() {
        #expect(throws: NonetError.self) { try stroke(KeyChord(.character("é"), modifiers: .command)) }
        #expect(throws: NonetError.self) { try stroke(KeyChord(.character("ab"))) }
        #expect(throws: NonetError.self) { try stroke(KeyChord(.character(""))) }
    }

    @Test("特殊キーとキーコードはそのまま。矢印や F キーには暗黙のフラグが付く")
    func specialAndRawKeys() throws {
        let left = try stroke(KeyChord(.special(.leftArrow), modifiers: .command))
        #expect(left.keyCode == CGKeyCode(kVK_LeftArrow))
        #expect(left.flags.contains([.maskCommand, .maskSecondaryFn, .maskNumericPad]))

        let f5 = try stroke(KeyChord(.special(.f5)))
        #expect(f5.keyCode == CGKeyCode(kVK_F5))
        #expect(f5.flags.contains(.maskSecondaryFn))

        let raw = try stroke(KeyChord(.keyCode(UInt16(kVK_ANSI_Keypad1)), modifiers: .control))
        #expect(raw.keyCode == CGKeyCode(kVK_ANSI_Keypad1))
        #expect(raw.flags.contains([.maskControl, .maskNumericPad]))

        let eisu = try stroke(KeyChord(.special(.eisu)))
        #expect(eisu.keyCode == CGKeyCode(kVK_JIS_Eisu))
        #expect(!eisu.flags.contains(.maskCommand))
    }

    @Test("キーコードはイベントに付けるのと同じキーボードの種類で探し、その種類を持つ")
    func strokeCarriesKeyboardType() throws {
        // JIS では ¥ のキーがあり、] は別の位置にある（ABC 配列の実際の並び）
        let ansi = KeyboardLayoutMap(base: ["]": 0x1E, "\\": 0x2A], shifted: [:], command: [:])
        let jis = KeyboardLayoutMap(base: ["]": 0x2A, "¥": 0x5D], shifted: [:], command: [:])
        var askedTypes: [UInt32] = []
        let resolve = { (chord: KeyChord, keyboardType: UInt32) throws -> KeyStroke in
            try KeyStrokeResolver.stroke(for: chord, keyboardType: keyboardType) { character, preferCommand, type in
                askedTypes.append(type)
                return (type == ActionKeyboardType.jis ? jis : ansi).match(character, preferCommandTable: preferCommand)
            }
        }

        let yen = try resolve(KeyChord(.character("¥")), ActionKeyboardType.jis)
        #expect(yen.keyCode == 0x5D)
        #expect(yen.keyboardType == ActionKeyboardType.jis)
        #expect(throws: NonetError.self) { try resolve(KeyChord(.character("¥")), ActionKeyboardType.ansi) }

        let bracketJIS = try resolve(KeyChord(.character("]"), modifiers: .command), ActionKeyboardType.jis)
        let bracketANSI = try resolve(KeyChord(.character("]"), modifiers: .command), ActionKeyboardType.ansi)
        #expect(bracketJIS.keyCode == 0x2A)
        #expect(bracketANSI.keyCode == 0x1E)
        #expect(bracketANSI.keyboardType == ActionKeyboardType.ansi)
        #expect(askedTypes == [ActionKeyboardType.jis, ActionKeyboardType.ansi, ActionKeyboardType.jis, ActionKeyboardType.ansi])

        // 文字以外もキーボードの種類を持つ（イベントに付ける）
        let f5 = try KeyStrokeResolver.stroke(for: KeyChord(.special(.f5)), keyboardType: ActionKeyboardType.iso) { _, _, _ in nil }
        #expect(f5.keyboardType == ActionKeyboardType.iso)
    }

    @Test("イベントは起動時ではなく、キーコードを選んだときのキーボードの種類で作る")
    func eventsUseStrokeKeyboardType() throws {
        // 起動したときは ANSI の外付けキーボード、今は JIS の内蔵キーボード
        let source = try #require(CGEventSource(stateID: .privateState))
        source.keyboardType = CGEventSourceKeyboardType(ActionKeyboardType.ansi)
        let stroke = KeyStroke(
            keyCode: CGKeyCode(kVK_JIS_Yen),
            flags: VirtualKeyTable.flags(for: [.command, .shift]),
            keyboardType: ActionKeyboardType.jis
        )
        let (down, up) = try #require(KeyEventFactory.events(for: stroke, source: source))
        for event in [down, up] {
            #expect(event.getIntegerValueField(.keyboardEventKeyboardType) == Int64(ActionKeyboardType.jis))
            #expect(event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_JIS_Yen))
            #expect(event.flags.contains([.maskCommand, .maskShift]))
            #expect(!event.flags.contains(.maskAlternate))
            #expect(SyntheticKeyEvent.isSynthetic(event))
        }
        #expect(down.type == .keyDown)
        #expect(up.type == .keyUp)
    }

    @Test("イベントに入る文字は、キー配列で探した文字と同じ（ANSI / ISO / JIS を切り替えても）")
    @MainActor
    func eventCharactersMatchLookup() throws {
        guard KeyboardLayoutResolver.isLayoutAvailable else { return }
        let resolver = KeyboardLayoutResolver()
        let source = try #require(CGEventSource(stateID: .privateState))
        // イベントの文字を決めるキー配列が、探すのに使うキー配列と違う環境（入力メソッドの指定など）では確かめられない
        guard let a = resolver.match("a", preferCommandTable: false, keyboardType: ActionKeyboardType.ansi),
              Self.characters(of: KeyStroke(keyCode: a.keyCode, flags: [], keyboardType: ActionKeyboardType.ansi), source: source) == "a"
        else { return }

        var checked = 0
        for keyboardType in ActionKeyboardType.all {
            for character in ["]", "[", "\\", "¥", "_", "@", "a", "1"] {
                guard let match = resolver.match(character, preferCommandTable: false, keyboardType: keyboardType),
                      !match.needsShift
                else { continue }
                // 起動したときの種類は別のもの
                source.keyboardType = CGEventSourceKeyboardType(keyboardType == ActionKeyboardType.jis ? ActionKeyboardType.ansi : ActionKeyboardType.jis)
                let stroke = KeyStroke(keyCode: match.keyCode, flags: [], keyboardType: keyboardType)
                #expect(Self.characters(of: stroke, source: source) == character, "\(character) (\(keyboardType))")
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    private static func characters(of stroke: KeyStroke, source: CGEventSource) -> String? {
        guard let (down, _) = KeyEventFactory.events(for: stroke, source: source) else { return nil }
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        down.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: length)
    }

    @Test("送るキーは、渡したキーボードの種類で決める")
    @MainActor
    func keySenderStrokesUseGivenKeyboardType() throws {
        guard KeyboardLayoutResolver.isLayoutAvailable else { return }
        let sender = KeySender()
        for keyboardType in ActionKeyboardType.all {
            let strokes = try sender.strokes(for: KeySequence([KeyChord(.character("c"), modifiers: .command), KeyChord(.special(.returnKey))]), keyboardType: keyboardType)
            #expect(strokes.count == 2)
            #expect(strokes.allSatisfy { $0.keyboardType == keyboardType })
            #expect(strokes.first?.flags.contains(.maskCommand) == true)
        }
    }

    @Test("Nonet が送るイベントには印が付き、見分けられる")
    func syntheticMarker() throws {
        let source = CGEventSource(stateID: .privateState)
        let event = try #require(CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true))
        #expect(!SyntheticKeyEvent.isSynthetic(event))
        event.setIntegerValueField(.eventSourceUserData, value: SyntheticKeyEvent.userData)
        #expect(SyntheticKeyEvent.isSynthetic(event))
    }
}

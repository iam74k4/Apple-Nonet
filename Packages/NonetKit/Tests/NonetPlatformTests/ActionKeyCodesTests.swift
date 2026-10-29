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
        try KeyStrokeResolver.stroke(for: chord) { character, preferCommand in
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

    @Test("Nonet が送るイベントには印が付き、見分けられる")
    func syntheticMarker() throws {
        let source = CGEventSource(stateID: .privateState)
        let event = try #require(CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true))
        #expect(!SyntheticKeyEvent.isSynthetic(event))
        event.setIntegerValueField(.eventSourceUserData, value: SyntheticKeyEvent.userData)
        #expect(SyntheticKeyEvent.isSynthetic(event))
    }
}

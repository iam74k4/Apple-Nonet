import Carbon.HIToolbox
import NonetCore
@testable import NonetPlatform
import Testing

@Suite("メニュー項目のショートカットを読む")
struct ActionMenuShortcutTests {
    @Test("AXMenuItemCmdModifiers のビット", arguments: [
        (0, ModifierSet.command),
        (1, [.command, .shift]),
        (2, [.command, .option]),
        (3, [.command, .shift, .option]),
        (4, [.command, .control]),
        (7, [.command, .shift, .option, .control]),
        (8, []),
        (9, [.shift]),
        (12, [.control]),
        (14, [.control, .option]),
        (0x18, [.function]),
        (0x10, [.command, .function]),
    ] as [(Int, ModifierSet)])
    func modifierMask(mask: Int, expected: ModifierSet) {
        #expect(MenuShortcutDecoder.modifiers(fromAXMask: mask) == expected)
    }

    @Test("グリフ（kMenu*Glyph）からキー", arguments: [
        (0x02, Key.special(.tab)), (0x03, .special(.tab)), (0x04, .keyCode(UInt16(kVK_ANSI_KeypadEnter))),
        (0x09, .special(.space)), (0x0A, .special(.forwardDelete)), (0x0B, .special(.returnKey)),
        (0x0D, .special(.returnKey)), (0x17, .special(.delete)), (0x1B, .special(.escape)),
        (0x1C, .keyCode(UInt16(kVK_ANSI_KeypadClear))), (0x62, .special(.pageUp)), (0x64, .special(.leftArrow)),
        (0x65, .special(.rightArrow)), (0x66, .special(.home)), (0x67, .keyCode(UInt16(kVK_Help))),
        (0x68, .special(.upArrow)), (0x69, .special(.end)), (0x6A, .special(.downArrow)), (0x6B, .special(.pageDown)),
        (0x6F, .special(.f1)), (0x7A, .special(.f12)), (0x87, .special(.f13)), (0x89, .special(.f15)),
        (0x8D, .special(.eisu)), (0x8E, .special(.kana)), (0x8F, .special(.f16)), (0x92, .special(.f19)),
    ] as [(Int, Key)])
    func glyphs(glyph: Int, expected: Key) {
        #expect(MenuShortcutDecoder.key(fromGlyph: glyph) == expected)
    }

    @Test("F1〜F12 のグリフは連番")
    func functionKeyGlyphs() throws {
        for index in 0 ..< 12 {
            let key = try #require(SpecialKey(rawValue: "f\(index + 1)"))
            #expect(MenuShortcutDecoder.key(fromGlyph: 0x6F + index) == .special(key))
        }
    }

    @Test("修飾キーや飾りのグリフはキーではない", arguments: [0x00, 0x05, 0x06, 0x07, 0x11, 0x12, 0x14, 0x61, 0x63, 0x6E, 0x8C, 0xFF])
    func nonKeyGlyphs(glyph: Int) {
        #expect(MenuShortcutDecoder.key(fromGlyph: glyph) == nil)
    }

    @Test("仮想キーコードは名前のあるキーに、それ以外はキーコードのまま")
    func virtualKeys() {
        #expect(MenuShortcutDecoder.key(fromVirtualKey: kVK_Return) == .special(.returnKey))
        #expect(MenuShortcutDecoder.key(fromVirtualKey: kVK_F5) == .special(.f5))
        #expect(MenuShortcutDecoder.key(fromVirtualKey: kVK_JIS_Kana) == .special(.kana))
        #expect(MenuShortcutDecoder.key(fromVirtualKey: kVK_ANSI_Keypad3) == .keyCode(UInt16(kVK_ANSI_Keypad3)))
        #expect(MenuShortcutDecoder.key(fromVirtualKey: -1) == nil)
        #expect(MenuShortcutDecoder.key(fromVirtualKey: 70_000) == nil)
    }

    @Test("文字の形の特殊キー（制御文字・NSEvent の F キーなど）")
    func specialCharacters() {
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\r") == .returnKey)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{3}") == .returnKey)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\t") == .tab)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: " ") == .space)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{8}") == .delete)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{7F}") == .delete)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{1B}") == .escape)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{F700}") == .upArrow)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{F703}") == .rightArrow)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{F704}") == .f1)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{F717}") == .f20)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{F718}") == nil)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{F728}") == .forwardDelete)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{F729}") == .home)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{F72B}") == .end)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{F72C}") == .pageUp)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "\u{F72D}") == .pageDown)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "c") == nil)
        #expect(MenuShortcutDecoder.specialKey(fromCharacter: "") == nil)
    }

    @Test("文字のショートカットは小文字にして修飾キーを付ける")
    func characterShortcuts() {
        #expect(MenuShortcutDecoder.keySequence(cmdChar: "C", modifiers: 0, virtualKey: nil, glyph: nil) == .key("c", .command))
        #expect(MenuShortcutDecoder.keySequence(cmdChar: "Z", modifiers: 1, virtualKey: nil, glyph: nil) == .key("z", [.command, .shift]))
        #expect(MenuShortcutDecoder.keySequence(cmdChar: ",", modifiers: nil, virtualKey: nil, glyph: nil) == .key(",", .command))
        #expect(MenuShortcutDecoder.keySequence(cmdChar: "F", modifiers: 0x18, virtualKey: nil, glyph: nil) == .key("f", .function))
        #expect(MenuShortcutDecoder.keySequence(cmdChar: "?", modifiers: 0, virtualKey: nil, glyph: nil) == .key("?", .command))
    }

    @Test("文字が無ければグリフ、次に文字の形の特殊キー、最後に仮想キーコード")
    func fallbackOrder() {
        // Delete（⌘⌫）: 文字は空でグリフが入る
        #expect(MenuShortcutDecoder.keySequence(cmdChar: "", modifiers: 0, virtualKey: nil, glyph: 0x17) == .special(.delete, .command))
        // グリフと文字の形の矢印が両方ある
        #expect(MenuShortcutDecoder.keySequence(cmdChar: "\u{F702}", modifiers: 2, virtualKey: nil, glyph: 0x64) == .special(.leftArrow, [.command, .option]))
        #expect(MenuShortcutDecoder.keySequence(cmdChar: "\u{F702}", modifiers: 0, virtualKey: nil, glyph: nil) == .special(.leftArrow, .command))
        #expect(MenuShortcutDecoder.keySequence(cmdChar: nil, modifiers: 8, virtualKey: kVK_F7, glyph: nil) == .special(.f7))
        #expect(MenuShortcutDecoder.keySequence(cmdChar: nil, modifiers: 0, virtualKey: kVK_ANSI_Keypad5, glyph: 0) == KeySequence([KeyChord(.keyCode(UInt16(kVK_ANSI_Keypad5)), modifiers: .command)]))
    }

    @Test("ショートカットの無い項目は nil（仮想キーコード 0 だけなら無いとみなす）")
    func noShortcut() {
        #expect(MenuShortcutDecoder.keySequence(cmdChar: nil, modifiers: nil, virtualKey: nil, glyph: nil) == nil)
        #expect(MenuShortcutDecoder.keySequence(cmdChar: "", modifiers: 0, virtualKey: 0, glyph: 0) == nil)
        #expect(MenuShortcutDecoder.keySequence(cmdChar: nil, modifiers: 0, virtualKey: nil, glyph: 0x11) == nil)
    }
}

import Carbon.HIToolbox
import CoreGraphics
@testable import NonetPlatform
import Testing

@Suite("キー配列から仮想キーコードを探す")
struct ActionKeyboardLayoutTests {
    /// US 配列のような偽物。⌘の表だけ別の並び（Dvorak - QWERTY ⌘ のような）にもできる
    private static func translator(commandTable: [CGKeyCode: String]? = nil) -> (CGKeyCode, UInt32) -> String? {
        let base: [CGKeyCode: String] = [0: "a", 11: "b", 8: "c", 18: "1", 19: "2", 44: "/", 49: " ", 36: "\r", 83: "1", 69: "+", 24: "="]
        let shifted: [CGKeyCode: String] = [0: "A", 11: "B", 8: "C", 18: "!", 19: "@", 44: "?", 24: "+", 49: " "]
        return { code, state in
            switch state {
            case KeyboardLayoutMap.ModifierState.shift: shifted[code]
            case KeyboardLayoutMap.ModifierState.command: (commandTable ?? base)[code]
            default: base[code]
            }
        }
    }

    @Test("本体のキーをテンキーより優先する")
    func prefersMainKeysOverKeypad() {
        let map = KeyboardLayoutMap(translate: Self.translator())
        #expect(map.base["1"] == 18)
        // "+" は本体では⇧が要り、テンキーでは要らない。修飾キーなしの表ではテンキーしか無い
        #expect(map.base["+"] == 69)
        #expect(map.shifted["+"] == 24)
    }

    @Test("テンキーは探す順の最後")
    func searchOrderPutsKeypadLast() {
        let order = KeyboardLayoutMap.searchOrder
        #expect(order.count == 128)
        #expect(Set(order).count == 128)
        let firstKeypad = order.firstIndex { VirtualKeyTable.keypadCodes.contains($0) }
        let lastMain = order.lastIndex { !VirtualKeyTable.keypadCodes.contains($0) }
        #expect(firstKeypad != nil)
        if let firstKeypad, let lastMain { #expect(lastMain < firstKeypad) }
    }

    @Test("同じ文字は最初に見つかったキー")
    func firstCodeWins() {
        let table = KeyboardLayoutMap.table(modifierState: 0) { code, _ in code == 5 || code == 3 ? "x" : nil }
        #expect(table["x"] == 3)
    }

    @Test("探す順: そのまま → 小文字 → ⇧付き")
    func matchOrder() {
        let map = KeyboardLayoutMap(translate: Self.translator())
        #expect(map.match("a", preferCommandTable: false) == .init(keyCode: 0, needsShift: false))
        #expect(map.match("A", preferCommandTable: false) == .init(keyCode: 0, needsShift: false))
        #expect(map.match("?", preferCommandTable: false) == .init(keyCode: 44, needsShift: true))
        #expect(map.match("@", preferCommandTable: true) == .init(keyCode: 19, needsShift: true))
        #expect(map.match(" ", preferCommandTable: false) == .init(keyCode: 49, needsShift: false))
        #expect(map.match("é", preferCommandTable: false) == nil)
    }

    @Test("⌘付きは⌘のときの並びを優先する")
    func commandTableWins() {
        // ⌘のときは a と b のキーが入れ替わる配列
        let map = KeyboardLayoutMap(translate: Self.translator(commandTable: [0: "b", 11: "a", 8: "c"]))
        #expect(map.match("a", preferCommandTable: false)?.keyCode == 0)
        #expect(map.match("a", preferCommandTable: true)?.keyCode == 11)
        // ⌘の表に無い文字は普通の表で探す
        #expect(map.match("1", preferCommandTable: true)?.keyCode == 18)
    }

    @Test("⌘のときだけラテン文字になる配列（ロシア語など）でも ⌘C が打てる")
    func nonLatinLayoutWithCommand() {
        let translate: (CGKeyCode, UInt32) -> String? = { code, state in
            let cyrillic: [CGKeyCode: String] = [0: "ф", 8: "с", 9: "м"]
            let latin: [CGKeyCode: String] = [0: "a", 8: "c", 9: "v"]
            return state == KeyboardLayoutMap.ModifierState.command ? latin[code] : cyrillic[code]
        }
        let map = KeyboardLayoutMap(translate: translate)
        #expect(map.match("c", preferCommandTable: true)?.keyCode == 8)
        #expect(map.match("c", preferCommandTable: false) == nil)
        #expect(map.match("ф", preferCommandTable: false)?.keyCode == 0)
    }

    @Test("この Mac の今のキー配列で英字と数字が見つかり、⌘付きでも同じ文字のキーになる")
    @MainActor
    func currentLayoutLettersAndDigits() {
        // キー配列を読めない環境（CI の一部など）では確かめられない
        guard KeyboardLayoutResolver.isLayoutAvailable else { return }
        let resolver = KeyboardLayoutResolver()
        let characters = "abcdefghijklmnopqrstuvwxyz0123456789".map(String.init)
        var codes = Set<CGKeyCode>()
        for character in characters {
            let match = resolver.match(character, preferCommandTable: false)
            #expect(match != nil, "\(character)")
            #expect(match?.needsShift == false, "\(character)")
            if let match { codes.insert(match.keyCode) }
            #expect(resolver.match(character, preferCommandTable: true) != nil, "⌘\(character)")
        }
        // 36文字はすべて別のキー
        #expect(codes.count == characters.count)
        #expect(codes.allSatisfy { !VirtualKeyTable.keypadCodes.contains($0) })
    }

    @Test("この Mac の今のキー配列でも、大文字は同じキーで⇧は足さない")
    @MainActor
    func currentLayoutUppercase() {
        guard KeyboardLayoutResolver.isLayoutAvailable else { return }
        let resolver = KeyboardLayoutResolver()
        let lower = resolver.match("q", preferCommandTable: false)
        let upper = resolver.match("Q", preferCommandTable: false)
        #expect(lower != nil)
        #expect(upper?.keyCode == lower?.keyCode)
        #expect(upper?.needsShift == false)
    }
}

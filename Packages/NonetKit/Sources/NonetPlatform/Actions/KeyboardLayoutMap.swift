// 担当: platform-actions
import AppKit
import Carbon.HIToolbox

/// キー配列から作った「文字 → 仮想キーコード」の表
struct KeyboardLayoutMap: Equatable {
    struct Match: Equatable {
        var keyCode: CGKeyCode
        /// 修飾キーなしでは出ない文字で、⇧を足すと出る
        var needsShift: Bool
    }

    /// UCKeyTranslate に渡す修飾キーの状態（EventModifiers を 8 ビット右にずらした値）
    enum ModifierState {
        static let none: UInt32 = 0
        static let command: UInt32 = UInt32(cmdKey >> 8) & 0xFF
        static let shift: UInt32 = UInt32(shiftKey >> 8) & 0xFF
    }

    var base: [String: CGKeyCode]
    var shifted: [String: CGKeyCode]
    /// ⌘を押したときの表。ロシア語や「Dvorak - QWERTY ⌘」では ⌘ のときだけ別の並びになる
    var command: [String: CGKeyCode]

    init(base: [String: CGKeyCode], shifted: [String: CGKeyCode], command: [String: CGKeyCode]) {
        self.base = base
        self.shifted = shifted
        self.command = command
    }

    /// translate(キーコード, 修飾キーの状態) はそのキーで入力される文字
    init(translate: (CGKeyCode, UInt32) -> String?) {
        base = Self.table(modifierState: ModifierState.none, translate: translate)
        shifted = Self.table(modifierState: ModifierState.shift, translate: translate)
        command = Self.table(modifierState: ModifierState.command, translate: translate)
    }

    /// 探す順。テンキーは本体のキーで見つからないときだけ使う
    static let searchOrder: [CGKeyCode] = {
        let all = (0 ..< 128).map { CGKeyCode($0) }
        return all.filter { !VirtualKeyTable.keypadCodes.contains($0) } + all.filter { VirtualKeyTable.keypadCodes.contains($0) }
    }()

    static func table(modifierState: UInt32, translate: (CGKeyCode, UInt32) -> String?) -> [String: CGKeyCode] {
        var table: [String: CGKeyCode] = [:]
        for code in searchOrder {
            guard let text = translate(code, modifierState), !text.isEmpty, table[text] == nil else { continue }
            table[text] = code
        }
        return table
    }

    /// プリセットは修飾キーなしの文字（英字は小文字）＋修飾キーで書く。
    /// それで見つからない文字（"A" や US 配列の "?"）は小文字・⇧付きの順で探す
    func match(_ character: String, preferCommandTable: Bool) -> Match? {
        let lower = character.lowercased()
        let candidates = lower == character ? [character] : [character, lower]
        let tables = preferCommandTable ? [command, base] : [base]
        for table in tables {
            for candidate in candidates {
                if let code = table[candidate] { return Match(keyCode: code, needsShift: false) }
            }
        }
        if let code = shifted[character] { return Match(keyCode: code, needsShift: true) }
        return nil
    }
}

/// 今のキー配列で文字の仮想キーコードを探す。表はキー配列ごとにとっておき、入力ソースが変わったら作り直す
@MainActor
final class KeyboardLayoutResolver {
    private var cache: [String: KeyboardLayoutMap] = [:]
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cache.removeAll() }
        }
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    /// 今使っているキーボードの種類（LMGetKbdType）。最後に打たれたキーボードで変わる
    static func currentKeyboardType() -> UInt32 {
        UInt32(LMGetKbdType())
    }

    /// 今のキー配列で探し、無ければ ASCII を打てるキー配列（ABC など）で探す。
    /// keyboardType は送るイベントに付けるのと同じ値にする（JIS の ¥ や _ のように、種類でキーの文字が変わる）
    func match(_ character: String, preferCommandTable: Bool, keyboardType: UInt32) -> KeyboardLayoutMap.Match? {
        for layout in Self.currentLayouts(keyboardType: keyboardType) {
            if let match = map(for: layout).match(character, preferCommandTable: preferCommandTable) {
                return match
            }
        }
        return nil
    }

    /// 今のキー配列が読めるか（テスト用）
    static var isLayoutAvailable: Bool { !currentLayouts(keyboardType: currentKeyboardType()).isEmpty }

    private func map(for layout: KeyboardLayoutData) -> KeyboardLayoutMap {
        let key = "\(layout.id)#\(layout.keyboardType)"
        if let cached = cache[key] { return cached }
        let map = layout.data.withUnsafeBytes { raw -> KeyboardLayoutMap in
            guard let pointer = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return KeyboardLayoutMap(base: [:], shifted: [:], command: [:])
            }
            return KeyboardLayoutMap { code, state in
                Self.translate(layout: pointer, keyCode: code, modifierState: state, keyboardType: layout.keyboardType)
            }
        }
        cache[key] = map
        return map
    }

    private struct KeyboardLayoutData {
        var id: String
        var data: Data
        var keyboardType: UInt32
    }

    /// 入力メソッド（日本語入力など）が指定するキー配列、今のキー配列、ASCII を打てるキー配列の順。
    /// 文字の表（uchr）を持たないものは飛ばす
    private static func currentLayouts(keyboardType: UInt32) -> [KeyboardLayoutData] {
        // Copy した参照は1回だけ受け取る（lazy で2度受け取ると解放しすぎる）
        let override = TISCopyInputMethodKeyboardLayoutOverride()?.takeRetainedValue()
        let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        var primary: KeyboardLayoutData?
        for source in [override, current].compactMap({ $0 }) {
            if let data = layoutData(of: source, keyboardType: keyboardType) {
                primary = data
                break
            }
        }
        var layouts: [KeyboardLayoutData] = []
        if let primary { layouts.append(primary) }
        if let ascii, let data = layoutData(of: ascii, keyboardType: keyboardType), data.id != primary?.id {
            layouts.append(data)
        }
        return layouts
    }

    private static func layoutData(of source: TISInputSource, keyboardType: UInt32) -> KeyboardLayoutData? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        guard !data.isEmpty else { return nil }
        let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "unknown"
        return KeyboardLayoutData(id: id, data: data, keyboardType: keyboardType)
    }

    private static func translate(
        layout: UnsafePointer<UCKeyboardLayout>,
        keyCode: CGKeyCode,
        modifierState: UInt32,
        keyboardType: UInt32
    ) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDown),
            modifierState,
            keyboardType,
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

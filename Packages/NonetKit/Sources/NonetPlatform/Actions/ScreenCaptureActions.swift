// 担当: platform-actions
// スクリーンショットと画面収録。macOS のスクリーンショットのキーボードショートカットを送る。
// 画面を読むのは macOS のスクリーンショットの仕組み（Nonet ではない）なので、画面収録の許可は増えない。
// 利用者がシステム設定でショートカットを変えていれば、そのキーを送る（com.apple.symbolichotkeys を読むだけ）
import AppKit
import NonetCore

/// キーを送る（テストでは偽物にする）
@MainActor
protocol KeySending {
    func send(_ sequence: KeySequence) async throws
}

extension KeySender: KeySending {}

/// システム設定のショートカット（com.apple.symbolichotkeys の AppleSymbolicHotKeys）のうち、スクリーンショットのもの
enum SystemHotKeys {
    /// AppleSymbolicHotKeys のキー（番号）
    enum Identifier: Int {
        /// 画面全体をファイルに保存する（既定は ⇧⌘3）
        case saveScreen = 28
        /// 画面全体をクリップボードにコピーする（⌃⇧⌘3）
        case copyScreen = 29
        /// 選んだ範囲をファイルに保存する（⇧⌘4）
        case saveArea = 30
        /// 選んだ範囲をクリップボードにコピーする（⌃⇧⌘4）
        case copyArea = 31
        /// スクリーンショットと収録のオプション（⇧⌘5）
        case options = 184
    }

    struct HotKey: Equatable {
        var keyCode: UInt16
        var modifiers: ModifierSet
    }

    enum Lookup: Equatable {
        case hotKey(HotKey)
        /// システム設定でオフにされているか、キーが割り当てられていない
        case disabled
    }

    /// 何も変えていない Mac の割り当て（キーコードはキー配列によらない仮想キーコード。3 = 0x14、4 = 0x15、5 = 0x17）
    static func defaultHotKey(_ id: Identifier) -> HotKey {
        switch id {
        case .saveScreen: HotKey(keyCode: 0x14, modifiers: [.shift, .command])
        case .copyScreen: HotKey(keyCode: 0x14, modifiers: [.control, .shift, .command])
        case .saveArea: HotKey(keyCode: 0x15, modifiers: [.shift, .command])
        case .copyArea: HotKey(keyCode: 0x15, modifiers: [.control, .shift, .command])
        case .options: HotKey(keyCode: 0x17, modifiers: [.shift, .command])
        }
    }

    /// 割り当てを調べる。table は AppleSymbolicHotKeys（読めなければ nil）。項目が無い・読めない形のときは、何も変えていない Mac の割り当て
    static func lookup(_ id: Identifier, in table: [String: Any]?) -> Lookup {
        guard let entry = table?[String(id.rawValue)] as? [String: Any] else { return .hotKey(defaultHotKey(id)) }
        if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue { return .disabled }
        guard let value = entry["value"] as? [String: Any],
              (value["type"] as? String).map({ $0 == "standard" }) ?? true,
              let parameters = value["parameters"] as? [Any], parameters.count >= 3,
              let code = (parameters[1] as? NSNumber)?.intValue,
              let flags = (parameters[2] as? NSNumber)?.intValue else { return .hotKey(defaultHotKey(id)) }
        // キーを割り当てていない（65535）なら、送るものが無い
        guard (0...0x7F).contains(code) else { return .disabled }
        return .hotKey(HotKey(keyCode: UInt16(code), modifiers: modifiers(fromCocoaFlags: flags)))
    }

    /// NSEvent.ModifierFlags の値（AppleSymbolicHotKeys に書かれる形）から修飾キー
    static func modifiers(fromCocoaFlags flags: Int) -> ModifierSet {
        var result: ModifierSet = []
        let flags = UInt(bitPattern: flags)
        if flags & NSEvent.ModifierFlags.control.rawValue != 0 { result.insert(.control) }
        if flags & NSEvent.ModifierFlags.option.rawValue != 0 { result.insert(.option) }
        if flags & NSEvent.ModifierFlags.shift.rawValue != 0 { result.insert(.shift) }
        if flags & NSEvent.ModifierFlags.command.rawValue != 0 { result.insert(.command) }
        if flags & NSEvent.ModifierFlags.function.rawValue != 0 { result.insert(.function) }
        return result
    }

    /// 今のシステム設定のショートカット
    static func currentTable() -> [String: Any]? {
        CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any]
    }
}

@MainActor
final class ScreenCaptureRunner {
    /// ウインドウを撮るときの、範囲を選ぶ画面を出してから Space を送るまで。早すぎると Space が効かず、範囲の選択のままになる
    static let windowSwitchDelay: Duration = .milliseconds(300)
    /// 画面収録を止めるキー（macOS 標準）
    static let stopRecordingChord = KeyChord(.special(.escape), modifiers: [.control, .command])

    private let keys: any KeySending
    private let table: () -> [String: Any]?
    private let sleep: (Duration) async throws -> Void

    init(
        keys: any KeySending,
        table: @escaping () -> [String: Any]? = SystemHotKeys.currentTable,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.keys = keys
        self.table = table
        self.sleep = sleep
    }

    func run(_ action: ScreenCaptureAction) async throws {
        if action.mode == .stopRecording {
            try await keys.send(KeySequence([Self.stopRecordingChord]))
            return
        }
        let id = Self.identifier(for: action)
        guard case .hotKey(let hotKey) = SystemHotKeys.lookup(id, in: table()) else {
            throw NonetError.actionFailed(String(localized: "macOS のスクリーンショットのキーボードショートカットがオフです。システム設定 › キーボード › キーボードショートカット › スクリーンショット で確かめてください", bundle: .nonetActions))
        }
        try await keys.send(KeySequence([KeyChord(.keyCode(hotKey.keyCode), modifiers: hotKey.modifiers)]))
        if action.mode == .window {
            // 範囲を選ぶ画面で Space を押すと、ウインドウを選ぶ画面になる
            try await sleep(Self.windowSwitchDelay)
            try await keys.send(KeySequence([KeyChord(.special(.space))]))
        }
    }

    /// 送るショートカット（stopRecording は固定のキーなので、ここには来ない）
    static func identifier(for action: ScreenCaptureAction) -> SystemHotKeys.Identifier {
        let clipboard = action.toClipboard && action.mode.supportsClipboard
        switch action.mode {
        case .area, .window: return clipboard ? .copyArea : .saveArea
        case .fullScreen: return clipboard ? .copyScreen : .saveScreen
        case .toolbar, .stopRecording: return .options
        }
    }
}

// 担当: platform-actions
import AppKit
import Carbon.HIToolbox
import NonetCore

/// Nonet が送るキーイベントに付ける印（kCGEventSourceUserData）
public enum SyntheticKeyEvent {
    /// "Nonet" の ASCII
    public static let userData: Int64 = 0x4E_6F_6E_65_74

    /// Nonet が送ったイベントか。イベントタップはこれを「ほかのキーが押された」として扱わない
    public static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == userData
    }
}

/// 1打分の仮想キーコードとフラグ
struct KeyStroke: Equatable {
    var keyCode: CGKeyCode
    var flags: CGEventFlags
    /// キーコードを選んだときのキーボードの種類（ANSI / ISO / JIS）。
    /// 受け取るアプリはイベントのこの値でキーコードを文字にするので、同じ値でイベントを作る
    var keyboardType: UInt32
}

enum KeyStrokeResolver {
    /// lookup(文字, ⌘の表を優先するか, キーボードの種類) はキー配列での位置
    static func stroke(
        for chord: KeyChord,
        keyboardType: UInt32,
        lookup: (String, Bool, UInt32) -> KeyboardLayoutMap.Match?
    ) throws -> KeyStroke {
        var modifiers = chord.modifiers
        let keyCode: CGKeyCode
        switch chord.key {
        case .character(let character):
            guard character.count == 1, let match = lookup(character, modifiers.contains(.command), keyboardType) else {
                throw NonetError.actionFailed(
                    String(localized: "「\(character)」は今のキー配列では入力できません", bundle: .nonetActions)
                )
            }
            keyCode = match.keyCode
            if match.needsShift { modifiers.insert(.shift) }
        case .special(let key):
            keyCode = VirtualKeyTable.keyCode(for: key)
        case .keyCode(let code):
            keyCode = CGKeyCode(code)
        }
        return KeyStroke(
            keyCode: keyCode,
            flags: VirtualKeyTable.flags(for: modifiers).union(VirtualKeyTable.implicitFlags(forKeyCode: keyCode)),
            keyboardType: keyboardType
        )
    }
}

enum KeyEventFactory {
    /// 押す・離すのイベント。イベントの文字は作るときにソースのキーボードの種類で決まるので、
    /// ソースの種類を合わせてから作り、イベントの値にも入れる
    static func events(for stroke: KeyStroke, source: CGEventSource?) -> (down: CGEvent, up: CGEvent)? {
        source?.keyboardType = CGEventSourceKeyboardType(stroke.keyboardType)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: false)
        else { return nil }
        for event in [down, up] {
            event.flags = stroke.flags
            event.setIntegerValueField(.keyboardEventKeyboardType, value: Int64(stroke.keyboardType))
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticKeyEvent.userData)
        }
        return (down, up)
    }
}

/// 前面アプリにキーを送る。トリガーキーを押したままでも混ざらないよう、
/// 自前の状態を持つイベントソースから、フラグを明示したイベントを HID の位置に流す
@MainActor
final class KeySender {
    static let chordInterval: Duration = .milliseconds(40)
    /// 押してから離すまで。短すぎると取りこぼすアプリがある
    static let holdDuration: Duration = .milliseconds(8)

    private let layouts = KeyboardLayoutResolver()
    private let source: CGEventSource?

    init() {
        let source = CGEventSource(stateID: .privateState)
        source?.userData = SyntheticKeyEvent.userData
        // 既定では送った直後の 0.25 秒、本物のキー入力が止められる。トリガーを離したことを取りこぼさないようにする
        source?.localEventsSuppressionInterval = 0
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        self.source = source
    }

    /// 順に送る。どれか1つでも今のキー配列で打てなければ、何も送らずに NonetError を投げる
    func send(_ sequence: KeySequence) async throws {
        guard !sequence.chords.isEmpty else { return }
        guard CGPreflightPostEventAccess() else {
            throw NonetError.permissionDenied(ActionText.accessibility)
        }
        // 外付けキーボードを使い分けると種類は途中で変わる。送るたびに1回だけ読み、キーコードを探すのにもイベントにも使う
        let strokes = try strokes(for: sequence, keyboardType: KeyboardLayoutResolver.currentKeyboardType())
        for (index, stroke) in strokes.enumerated() {
            if index > 0 { try await Task.sleep(for: Self.chordInterval) }
            try await post(stroke)
        }
    }

    /// 送るキーを今のキー配列で決める（送りはしない）
    func strokes(for sequence: KeySequence, keyboardType: UInt32) throws -> [KeyStroke] {
        try sequence.chords.map { chord in
            try KeyStrokeResolver.stroke(for: chord, keyboardType: keyboardType) { [layouts] character, preferCommand, type in
                layouts.match(character, preferCommandTable: preferCommand, keyboardType: type)
            }
        }
    }

    private func post(_ stroke: KeyStroke) async throws {
        guard let (down, up) = KeyEventFactory.events(for: stroke, source: source) else {
            throw NonetError.actionFailed(String(localized: "キーを送れませんでした", bundle: .nonetActions))
        }
        down.post(tap: .cghidEventTap)
        // 取り消されても「離す」は必ず送る（押しっぱなしにしない）
        try? await Task.sleep(for: Self.holdDuration)
        up.post(tap: .cghidEventTap)
    }
}

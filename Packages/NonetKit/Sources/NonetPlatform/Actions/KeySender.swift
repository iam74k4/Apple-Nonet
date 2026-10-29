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
}

enum KeyStrokeResolver {
    /// lookup(文字, ⌘の表を優先するか) はキー配列での位置
    static func stroke(
        for chord: KeyChord,
        lookup: (String, Bool) -> KeyboardLayoutMap.Match?
    ) throws -> KeyStroke {
        var modifiers = chord.modifiers
        let keyCode: CGKeyCode
        switch chord.key {
        case .character(let character):
            guard character.count == 1, let match = lookup(character, modifiers.contains(.command)) else {
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
            flags: VirtualKeyTable.flags(for: modifiers).union(VirtualKeyTable.implicitFlags(forKeyCode: keyCode))
        )
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
        source?.keyboardType = CGEventSourceKeyboardType(LMGetKbdType())
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
        let strokes = try sequence.chords.map { chord in
            try KeyStrokeResolver.stroke(for: chord) { [layouts] character, preferCommand in
                layouts.match(character, preferCommandTable: preferCommand)
            }
        }
        for (index, stroke) in strokes.enumerated() {
            if index > 0 { try await Task.sleep(for: Self.chordInterval) }
            try await post(stroke)
        }
    }

    private func post(_ stroke: KeyStroke) async throws {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: false)
        else {
            throw NonetError.actionFailed(String(localized: "キーを送れませんでした", bundle: .nonetActions))
        }
        for event in [down, up] {
            event.flags = stroke.flags
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticKeyEvent.userData)
        }
        down.post(tap: .cghidEventTap)
        // 取り消されても「離す」は必ず送る（押しっぱなしにしない）
        try? await Task.sleep(for: Self.holdDuration)
        up.post(tap: .cghidEventTap)
    }
}

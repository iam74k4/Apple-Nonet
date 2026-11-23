// 担当: platform-actions
// 再生・音量・明るさのキーを送る（MediaAction）。キーボードの F キーの段のキーと同じ、システムの特別なイベント
// （NSEvent.EventType.systemDefined、subtype 8。IOKit の NX_KEYTYPE_*）を HID の位置に送るので、どのアプリが前面でも効き、
// macOS の音量・明るさの表示も出る。アクセシビリティの許可（キー入力と同じ）で送れる
import AppKit
import NonetCore

enum MediaKeyCode {
    /// IOKit の ev_keymap.h（NX_KEYTYPE_*）
    static func code(for key: MediaKey) -> Int {
        switch key {
        case .volumeUp: 0
        case .volumeDown: 1
        case .brightnessUp: 2
        case .brightnessDown: 3
        case .mute: 7
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
    }

    /// systemDefined のイベントの data1: 上位 16 ビットがキー、次の 8 ビットが押す（0xA）・離す（0xB）
    static func data1(for key: MediaKey, down: Bool) -> Int {
        (code(for: key) << 16) | ((down ? 0xA : 0xB) << 8)
    }
}

@MainActor
enum MediaKeySender {
    /// 押す・離すを、MediaKey.steps 回送る
    static func send(_ key: MediaKey) throws {
        for _ in 0..<max(key.steps, 1) {
            for down in [true, false] {
                guard let event = NSEvent.otherEvent(
                    with: .systemDefined,
                    location: .zero,
                    modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: 0,
                    context: nil,
                    subtype: 8,
                    data1: MediaKeyCode.data1(for: key, down: down),
                    data2: -1
                ), let cgEvent = event.cgEvent else {
                    throw NonetError.actionFailed(String(localized: "再生・音量・明るさのキーを送れませんでした", bundle: .module))
                }
                cgEvent.setIntegerValueField(.eventSourceUserData, value: OwnEventFilter.userData)
                cgEvent.post(tap: .cghidEventTap)
            }
        }
    }
}

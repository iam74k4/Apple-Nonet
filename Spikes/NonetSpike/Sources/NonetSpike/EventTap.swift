import CoreGraphics

/// 全イベントを受けるイベントタップ。handler が false を返したイベントは前面アプリに届かない
final class EventTap {
    enum Location: String, CaseIterable, Identifiable {
        case hid = "HID"
        case session = "セッション"

        var id: Self { self }
    }

    /// メインスレッドで呼ばれる
    var handler: ((CGEventType, CGEvent) -> Bool)?
    var onDisabled: ((CGEventType) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isInstalled: Bool { tap != nil }

    func install(at location: Location) -> Bool {
        uninstall()
        guard let tap = CGEvent.tapCreate(
            tap: location == .hid ? .cghidEventTap : .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask.max,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            onDisabled?(type)
            return Unmanaged.passUnretained(event)
        }
        let pass = handler?(type, event) ?? true
        return pass ? Unmanaged.passUnretained(event) : nil
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}

/// イベントの種類（rawValue）。CGEventType に無いジェスチャー系は NSEvent.EventType の値
enum EventKind {
    static func name(_ raw: UInt32) -> String {
        switch raw {
        case 1: "左押下"
        case 2: "左離す"
        case 3: "右押下"
        case 4: "右離す"
        case 5: "移動"
        case 6: "左ドラッグ"
        case 7: "右ドラッグ"
        case 10: "キー押下"
        case 11: "キー離す"
        case 12: "修飾キー"
        case 18: "回転"
        case 19: "ジェスチャー開始"
        case 20: "ジェスチャー終了"
        case 22: "スクロール"
        case 25: "他ボタン押下"
        case 26: "他ボタン離す"
        case 27: "他ボタンドラッグ"
        case 29: "ジェスチャー"
        case 30: "拡大縮小"
        case 31: "スワイプ"
        case 32: "スマートズーム"
        case 34: "感圧"
        case 37: "直接タッチ"
        default: "type\(raw)"
        }
    }

    /// トリガー押下中に前面アプリへ渡したくない、ポインタ・ジェスチャー系のイベント
    static func isPointer(_ raw: UInt32) -> Bool {
        switch raw {
        case 1...7, 22, 25...27, 18...20, 29...34, 37: true
        default: false
        }
    }

    static func isMove(_ raw: UInt32) -> Bool {
        raw == 5 || raw == 6 || raw == 7 || raw == 27
    }

    /// ボタンを押したイベントならボタン番号
    static func downButton(_ raw: UInt32, _ event: CGEvent) -> Int64? {
        switch raw {
        case 1: 0
        case 3: 1
        case 25: event.getIntegerValueField(.mouseEventButtonNumber)
        default: nil
        }
    }

    /// ボタンを離したイベントならボタン番号
    static func upButton(_ raw: UInt32, _ event: CGEvent) -> Int64? {
        switch raw {
        case 2: 0
        case 4: 1
        case 26: event.getIntegerValueField(.mouseEventButtonNumber)
        default: nil
        }
    }
}

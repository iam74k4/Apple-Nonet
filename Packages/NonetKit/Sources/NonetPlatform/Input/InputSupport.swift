// 担当: platform-input
import Foundation
import os

let inputLogger = Logger(subsystem: "com.iam74k4.Nonet", category: "platform-input")

/// 画面に出る文言
enum InputText {
    static var accessibility: String {
        String(localized: "アクセシビリティ", bundle: .module)
    }

    static var multitouchUnavailable: String {
        String(localized: "トラックパッドの指の位置を読み取れません", bundle: .module)
    }
}

/// NotificationCenter の登録。解放されるときに必ず外す（deinit がメインアクターの外で動いても安全なように分けてある）
final class NotificationObservation {
    private let center: NotificationCenter
    private let token: NSObjectProtocol

    /// handler はメインスレッドで呼ばれる
    init(center: NotificationCenter, name: Notification.Name, handler: @escaping @MainActor (Notification) -> Void) {
        self.center = center
        token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated { handler(notification) }
        }
    }

    deinit {
        center.removeObserver(token)
    }
}

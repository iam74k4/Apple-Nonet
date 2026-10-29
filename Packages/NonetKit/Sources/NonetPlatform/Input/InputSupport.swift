// 担当: platform-input
import Foundation
import os

let inputLogger = Logger(subsystem: "com.iam74k4.Nonet", category: "platform-input")

/// 画面に出る文言。NonetPlatform にはまだリソース（Bundle.module）が無いので bundle を指定していない。
/// 統合時に NonetPlatform に Localizable.xcstrings を足したら `bundle: .module` を付ける
enum InputText {
    static var accessibility: String {
        String(localized: "アクセシビリティ")
    }

    static var multitouchUnavailable: String {
        String(localized: "トラックパッドの指の位置を読み取れません")
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

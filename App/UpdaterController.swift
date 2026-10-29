import Foundation
import Sparkle

/// Sparkle によるアップデート。配信先が未設定なら何もしない
@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController?

    init() {
        controller = AppInfo.hasUpdateFeed
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

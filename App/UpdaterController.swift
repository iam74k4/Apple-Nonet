import AppKit
import NonetUI
import Sparkle

/// Sparkle によるアップデート。配信先が未設定なら何もしない。
/// Nonet はメニューバーに常駐して前面にならないので、定期の確認で見つかったアップデートは
/// Sparkle の画面（ほかのアプリの後ろに隠れてしまう）ではなく、メニューバーのアイコンの印と
/// メニューの「アップデートがあります…」で控えめに知らせる（Sparkle がそのまま前に出せるのは、起動の直後だけ）
@MainActor
final class UpdaterController: NSObject {
    /// 控えめな知らせを出す・消す（アイコンの印と、メニューの「アップデートがあります…」）
    var onUpdateAvailableChange: ((Bool) -> Void)?

    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        if AppInfo.hasUpdateFeed {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        }
    }

    var isAvailable: Bool { controller != nil }

    /// メニューの「アップデートを確認」「アップデートがあります…」。見つかっているときは Sparkle がその画面を出す
    func checkForUpdates() {
        // Sparkle の画面がほかのアプリの後ろに出ないよう、先に前面にする
        NSApplication.shared.activate()
        controller?.checkForUpdates(nil)
    }
}

extension UpdaterController: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// 起動の直後など、Sparkle がそのまま前に出せるときだけ任せる。ほかはメニューで知らせる
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated {
            if handleShowingUpdate {
                NSApplication.shared.activate()
            } else {
                onUpdateAvailableChange?(true)
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { onUpdateAvailableChange?(false) }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            onUpdateAvailableChange?(false)
            // Sparkle の画面のために前面にした。閉じた後も前面のままだと、打鍵が Nonet に届き、キー入力のマスも
            // 「前面のアプリが変わった」で止まる。画面が閉じきってから、ほかに Nonet のウィンドウが無ければ前のアプリに返す
            ShellActivation.handBackAfterClosingWindow(delay: 0.5)
        }
    }
}

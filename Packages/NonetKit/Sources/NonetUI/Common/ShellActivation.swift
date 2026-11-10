// 担当: ui-shell
import AppKit

/// 設定や案内のウィンドウを閉じた後、前面を前に使っていたアプリに返す。
/// Nonet は Dock に出ないので、閉じた後も前面のままだと、キーのウィンドウが無いまま打鍵が Nonet に届き続ける
/// （キー入力のマスを実行しても、前に使っていたアプリではなく Nonet に打ってしまう）
@MainActor
public enum ShellActivation {
    struct WindowState: Equatable {
        var isVisible: Bool
        var canBecomeKey: Bool
    }

    static func state(of window: NSWindow) -> WindowState {
        WindowState(isVisible: window.isVisible, canBecomeKey: window.canBecomeKey)
    }

    /// 前面を返すか。Nonet が前面で、見えていてキーになれるウィンドウ（ほかの設定や案内、AI の結果のパネル）が1つも無いとき。
    /// HUD・トーストのパネルとメニューバーのアイコンはキーにならないので数えない
    nonisolated static func shouldHandBack(isActive: Bool, windows: [WindowState]) -> Bool {
        isActive && !windows.contains { $0.isVisible && $0.canBecomeKey }
    }

    /// ウィンドウが閉じるときに呼ぶ。閉じた直後に別のウィンドウを開くことがある（案内の「設定を開く」）ので、
    /// 今の処理が終わってから確かめる
    public static func handBackAfterClosingWindow(delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) {
            MainActor.assumeIsolated { handBackIfNoWindowIsOpen() }
        }
    }

    public static func handBackIfNoWindowIsOpen() {
        let app = NSApplication.shared
        guard shouldHandBack(isActive: app.isActive, windows: app.windows.map(state(of:))) else { return }
        // 次のアプリ（ふつうは前に使っていたアプリ）が前面になる。メニューバーのアイコンは残り、
        // HUD のパネルは次に出すときに（Nonet を前面にせずに）また見えるようになる
        app.hide(nil)
    }
}

// 担当: ui-shell
// メインメニューの「終了」（⌘Q）を確かめる。設定のウインドウを閉じるつもりで ⌘Q を押すと、Nonet が終わって
// トラックパッドから HUD が開かなくなるため。メニューバーの「Nonet を終了」は、はっきり選んだのですぐ終わる
import AppKit

/// 確かめるときの答え
struct ShellQuitAnswer: Equatable {
    var quits: Bool
    /// 「次回から確認しない」にチェックを付けた
    var stopsAsking: Bool
}

@MainActor
public final class ShellQuitConfirmation {
    /// 「次回から確認しない」を覚えるキー
    static let skipKey = "com.iam74k4.Nonet.skipQuitConfirmation"

    /// 覚える場所（nil ならメモリだけ。Debug の --config-dir など）
    private let defaults: UserDefaults?
    private var skipsInMemory = false
    /// 尋ねる（テストでは偽物にする）。答えを渡す
    var ask: (@escaping (ShellQuitAnswer) -> Void) -> Void = ShellQuitConfirmation.runAlert
    /// 終了する（テストでは数える）
    var terminate: () -> Void = { NSApplication.shared.terminate(nil) }

    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
    }

    /// 「次回から確認しない」にした
    var skipsConfirmation: Bool {
        defaults?.bool(forKey: Self.skipKey) ?? skipsInMemory
    }

    /// ⌘Q。確かめないことにしていれば、すぐ終わる
    public func quit() {
        guard !skipsConfirmation else {
            terminate()
            return
        }
        ask { [weak self] answer in
            guard let self, answer.quits else { return }
            if answer.stopsAsking {
                if let defaults = self.defaults {
                    defaults.set(true, forKey: Self.skipKey)
                } else {
                    self.skipsInMemory = true
                }
            }
            self.terminate()
        }
    }

    static var title: String {
        String(localized: "Nonet を終了しますか？", bundle: .module)
    }

    static var message: String {
        String(localized: "終了すると、もう一度 Nonet を開くまで、トラックパッドを強く押し込んでも HUD が開かなくなります。ウインドウを閉じるだけなら ⌘W を使ってください。", bundle: .module)
    }

    static var quitButton: String {
        // メニュー項目の「終了」（Quit Nonet）とは別の言葉にする（ボタンは Quit）
        String(localized: "shell.quitConfirmation.quit", defaultValue: "終了", bundle: .module)
    }

    static var suppressionTitle: String {
        String(localized: "次回から確認しない", bundle: .module)
    }

    /// キーのウインドウ（設定・案内）に重ねて尋ねる。無ければ単独で
    private static func runAlert(_ done: @escaping (ShellQuitAnswer) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: quitButton)
        alert.addButton(withTitle: String(localized: "キャンセル", bundle: .module))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = suppressionTitle
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            done(ShellQuitAnswer(
                quits: response == .alertFirstButtonReturn,
                stopsAsking: alert.suppressionButton?.state == .on
            ))
        }
        if let window = NSApp.keyWindow, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            NSApp.activate()
            finish(alert.runModal())
        }
    }
}

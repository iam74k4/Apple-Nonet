#if DEBUG
import AppKit
import NonetCore
import NonetUI

/// 見た目の確認用（DEBUG ビルドだけ）。起動引数:
/// --config-dir <dir>  設定の置き場所（空のフォルダなら初回起動になる）。試用の記録もメモリだけに置く
/// --show-settings [profiles|general|license|about]  --show-onboarding
/// --preview-hud  --preview-toast  --preview-result  --simulate-expired-trial  --snapshot <dir>
@MainActor
final class DebugPreview {
    private let controller: NonetController
    private let hud: HUDWindowController
    private let license: LicenseManager
    private let services: NonetServices
    private var toastTimer: Timer?
    private var toastIndex = 0

    init(controller: NonetController, hud: HUDWindowController, license: LicenseManager, services: NonetServices) {
        self.controller = controller
        self.hud = hud
        self.license = license
        self.services = services
    }

    /// 20日前に試用を始めたことにした LicenseManager（保存はしない）
    static func expiredTrialLicense(verifier: LicenseVerifier?) -> LicenseManager {
        let storage = MemoryLicenseStorage(trialStartDate: Date().addingTimeInterval(-20 * 24 * 60 * 60))
        return LicenseManager(verifier: verifier, storage: storage, now: { Date() })
    }

    /// いま試用を始めたことにした LicenseManager（保存はしない）
    static func temporaryLicense(verifier: LicenseVerifier?) -> LicenseManager {
        LicenseManager(verifier: verifier, storage: MemoryLicenseStorage(trialStartDate: nil), now: { Date() })
    }

    /// 前面アプリの最初のページを、中央のマスをハイライトして出したままにする
    func showHUD() {
        let configuration = controller.configuration
        let pages = configuration.resolvedPages(frontmostBundleID: services.frontmostApp.current?.app.bundleID)
        guard let page = pages.first else { return }
        let trigger = configuration.settings.trigger
        let model = HUDModel(
            title: page.profileName,
            pageIndex: 0,
            pageCount: pages.count,
            cells: page.cells.map { cell in
                cell.map { HUDCell(title: $0.title, icon: $0.icon, detail: Self.detail(for: $0.action)) }
            },
            highlightedIndex: 4,
            hint: String(localized: "\(trigger.symbol)を離して実行"),
            banner: license.canExecuteActions ? nil : String(localized: "試用期間が終了しました")
        )
        hud.show(model, position: configuration.settings.hudPosition)
    }

    /// 成功・案内・失敗のトーストを3秒ごとに順に出す
    func startToasts() {
        showNextToast()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.showNextToast() }
        }
        toastTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func showResult() {
        hud.showResult(ResultModel(
            title: String(localized: "ページを要約"),
            text: String(localized: """
            この記事は、MacBook のトラックパッドを 3×3 のボタンとして使うアイデアを紹介しています。

            ・トリガーキーを押している間だけ、トラックパッドが9つのボタンになる
            ・慣れたらすぐにタップして実行し、迷ったときだけ HUD で確かめる
            ・前面のアプリに合わせて9マスが切り替わり、1つのアプリに最大3ページまで置ける

            設定は Mac の中だけに保存され、アカウントも要りません。
            """),
            icon: .symbol("sparkles")
        ))
    }

    /// 0.5・3.4・6.4 秒後に表示中のウィンドウを書き出し、終わったらアプリを終える（トーストは3秒ごとに替わる）
    func snapshotWindowsAndQuit(to directory: URL) {
        let delays: [TimeInterval] = [0.5, 3.4, 6.4]
        for (round, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    Self.snapshotWindows(to: directory, round: round + 1)
                    if round == delays.count - 1 {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
    }

    /// 自分のウィンドウを中から描く（画面の収録の許可は要らない）。タイトルバーも含める
    private static func snapshotWindows(to directory: URL, round: Int) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("snapshot: \(error.localizedDescription)")
            return
        }
        for (index, window) in NSApplication.shared.windows.enumerated() where window.isVisible {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let kind = String(describing: type(of: window))
            let url = directory.appendingPathComponent("round\(round)-\(index)-\(kind).png")
            do {
                try rep.representation(using: .png, properties: [:])?.write(to: url)
                print("snapshot: \(url.lastPathComponent) frame=\(NSStringFromRect(window.frame)) level=\(window.level.rawValue)")
            } catch {
                print("snapshot: \(error.localizedDescription)")
            }
        }
    }

    private func showNextToast() {
        let toasts = [
            ToastModel(title: String(localized: "ビルド"), detail: "⌘B", icon: .symbol("play.fill"), style: .success),
            ToastModel(title: String(localized: "Nonet を無効にしました"), style: .info),
            ToastModel(
                title: String(localized: "スクリプトが失敗しました"),
                detail: "zsh:1: command not found: claude\nPATH を ~/.zprofile に書いてください",
                icon: .symbol("terminal"),
                style: .failure
            ),
        ]
        hud.showToast(toasts[toastIndex % toasts.count])
        toastIndex += 1
    }

    private static func detail(for action: Action) -> String? {
        switch action {
        case .keystroke(let keys): keys.displayString
        case .menuItem(let item): item.keyEquivalent?.displayString
        default: nil
        }
    }
}

/// 保存しない試用の記録
private final class MemoryLicenseStorage: LicenseStorage {
    var trialStartDate: Date?
    var licenseKey: String?

    init(trialStartDate: Date?) {
        self.trialStartDate = trialStartDate
    }
}
#endif

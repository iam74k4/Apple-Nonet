#if DEBUG
import AppKit
import NonetCore
import NonetUI

/// 見た目の確認用（DEBUG ビルドだけ）。起動引数:
/// --config-dir <dir>  設定の置き場所（空のフォルダなら初回起動になる）。試用の記録もメモリだけに置く
/// --show-settings [profiles|general|license]  --show-onboarding
/// --preview-hud [--preview-app <bundle ID>] [--preview-backdrop <画像>]  --preview-toast  --preview-result
/// --simulate-expired-trial  --snapshot <dir>
@MainActor
final class DebugPreview {
    private let controller: NonetController
    private let hud: HUDWindowController
    private let license: LicenseManager
    private let services: NonetServices
    private var toastTimer: Timer?
    private var hudTimer: Timer?
    private var toastIndex = 0
    private var backdrop: NSWindow?

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

    /// 前面アプリの最初のページの HUD を出したままにし、3秒ごとに状態を替える（--snapshot の各回で1つずつ写る）:
    /// 1. 中央のマスで指を止めている 2. 指が外枠にある（離すとやめる） 3. 少し長く止めるマスを止めている途中 4. 止め終えた
    /// 5. 指が右の外枠にあり、止めると次のページ（ページが1つなら、外枠にあるだけ）
    /// 6. 下の帯で止めてグローバルの層へ移った（押し出し・紺の台・層の名前） 7. 上の帯で止めてアプリの層へ戻った
    /// （6・7 は前面のアプリにプロファイルがあるときだけ。無ければ 2 と同じ）
    /// 8. 下の帯で止めたが、層が1つで切り替える先が無い（案内。前面のアプリにプロファイルが無いときだけ。あれば 2 と同じ）
    func showHUD(bundleID: String? = nil, backdrop image: URL? = nil) {
        previewBundleID = bundleID
        if let image {
            showBackdrop(image)
        }
        showHUDState(0)
        var state = 0
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                state += 1
                self?.showHUDState(state % Self.hudStateCount)
            }
        }
        hudTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static let hudStateCount = 8
    /// --preview-app で選んだアプリ。nil なら前面のアプリ
    private var previewBundleID: String?

    /// 画面いっぱいに絵を敷く（HUD の下、ほかのウィンドウの上）。マウスは素通しする
    private func showBackdrop(_ url: URL) {
        guard let screen = NSScreen.main, let image = NSImage(contentsOf: url) else { return }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSImageView(frame: screen.frame)
        view.image = image
        view.imageScaling = .scaleAxesIndependently
        window.contentView = view
        window.orderFrontRegardless()
        backdrop = window
    }
    /// 少し長く止めるマスの例に使う位置（ページに少し長く止めるマスが無ければ、この位置のマスをそうみなす）
    private static let previewHoldCell = 7

    private func showHUDState(_ state: Int) {
        let configuration = controller.configuration
        let pages = configuration.resolvedPages(frontmostBundleID: previewBundleID ?? services.frontmostApp.current?.app.bundleID)
        guard let first = pages.first else { return }
        // アプリのプロファイルがあれば、アプリの層とグローバルの層の2つ（ControllerPresentation と同じ分け方）
        let layerStart = pages.firstIndex { $0.profileID != first.profileID }
        let showsGlobal = state == 5 && layerStart != nil
        let page = showsGlobal ? pages[layerStart!] : first
        let layer: HUDLayer? = layerStart == nil ? nil : (showsGlobal ? .global : .app)
        let layerPageCount = layerStart.map { showsGlobal ? pages.count - $0 : $0 } ?? pages.count
        let lastTurn: PageEdge? = layerStart == nil ? nil : (state == 5 ? .down : state == 6 ? .up : nil)
        let holdIndex = page.cells.firstIndex { $0?.requiresHold == true } ?? Self.previewHoldCell
        let cells = page.cells.enumerated().map { index, cell in
            cell.map {
                HUDCell(
                    title: $0.title,
                    icon: $0.icon,
                    detail: Self.detail(for: $0.action),
                    requiresHold: $0.requiresHold || index == holdIndex
                )
            }
        }
        let since = ProcessInfo.processInfo.systemUptime
        let edgePaging = state == 4 && layerPageCount > 1
            ? HUDEdgePaging(edge: .right, since: since, duration: SessionConfiguration.defaultEdgePageDwell)
            : nil
        let (highlight, inFrame, hold): (Int?, Bool, HUDHold?) = switch state {
        case 1, 4, 5, 6, 7: (nil, true, nil)
        case 2: (holdIndex, false, HUDHold(cellIndex: holdIndex, since: since, duration: SessionConfiguration.defaultHoldDwell, isReady: false))
        case 3: (holdIndex, false, HUDHold(cellIndex: holdIndex, since: since, duration: SessionConfiguration.defaultHoldDwell, isReady: true))
        default: (4, false, nil)
        }
        let model = HUDModel(
            title: page.title,
            pageIndex: 0,
            pageCount: layerPageCount,
            cells: cells,
            highlightedIndex: highlight,
            isFingerInFrame: inFrame,
            hold: hold,
            edgePaging: edgePaging,
            isPractice: controller.isPracticeMode,
            banner: license.canExecuteActions ? nil : ControllerPresentation.trialEndedBanner,
            layer: layer,
            lastTurn: lastTurn,
            scale: configuration.settings.hudScale.factor,
            edgeHint: state == 7
                ? ControllerPresentation.layerHint(configuration: configuration, pages: pages, frontmostBundleID: previewBundleID ?? services.frontmostApp.current?.app.bundleID)
                : nil
        )
        hud.show(model)
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

            ・トラックパッドのどこかを強く押し込んで少し止めると、トラックパッドが9つのボタンになる
            ・指を滑らせて選び、マスで離すと実行し、外枠で離すと何もせずに閉じる
            ・前面のアプリに合わせて9マスが切り替わり、1つのアプリに最大3ページまで置ける

            設定は Mac の中だけに保存され、アカウントも要りません。
            """),
            icon: .symbol("sparkles")
        ))
    }

    /// 0.5・3.4・6.4・9.4 秒後に表示中のウィンドウを書き出し、終わったらアプリを終える（トーストと HUD の状態は3秒ごとに替わる。
    /// HUD の3回目は、少し長く止めるマスを止め始めて 0.4 秒のところ）
    func snapshotWindowsAndQuit(to directory: URL) {
        let delays: [TimeInterval] = [0.5, 3.4, 6.4, 9.4]
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

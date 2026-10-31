// 担当: ui-shell。見た目の確認用。NONET_RENDER_SHOTS=<フォルダ> のときだけ PNG を書き出す（普段の swift test では動かない）。
// 文言は実際の画面と同じところ（ControllerPresentation・プリセット・カタログ）から引く。日本語をそのまま書くと、英語で描いても日本語のまま出る
import AppKit
import Foundation
import NonetCore
@testable import NonetUI
import SwiftUI
import Testing

private let shotsDirectory = ProcessInfo.processInfo.environment["NONET_RENDER_SHOTS"]

@Suite("画面の書き出し（NONET_RENDER_SHOTS）", .enabled(if: shotsDirectory != nil))
@MainActor
struct ShellRenderTests {
    static let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

    /// 既定の引数に使うので、メインアクターに縛らない
    nonisolated static let releaseHint = ControllerPresentation.hint(fireMode: .onTriggerRelease, trigger: .rightCommand, isPracticeMode: false)

    @Test("HUD")
    func hud() throws {
        let xcode = try #require(PresetLibrary.preset(forBundleID: ShellFixtures.xcode))
        let global = PresetLibrary.makeGlobalProfile(installedBundleIDs: Set(PresetLibrary.launcherCandidates.map(\.bundleID)))
        let models: [(String, HUDModel)] = [
            ("hud-xcode", Self.hudModel(title: "Xcode", page: xcode.pages[0], highlighted: 4, pageCount: 1)),
            // HUD で選ぶマス（クリーン）を速押しして出た HUD。光ったマスにも印が見える
            ("hud-xcode-hud-only", Self.hudModel(title: "Xcode", page: xcode.pages[0], highlighted: 7, pageCount: 1)),
            ("hud-launcher-pages", Self.hudModel(title: L10n.globalName, page: global.pages[0], highlighted: 2, pageIndex: 1, pageCount: 3)),
            // 長い方の案内（練習中・指を離して実行）
            ("hud-practice", Self.hudModel(
                title: "Xcode",
                page: xcode.pages[0],
                highlighted: 2,
                pageCount: 1,
                hint: ControllerPresentation.hint(fireMode: .onFingerLift, trigger: .rightCommand, isPracticeMode: true)
            )),
            ("hud-empty-banner", HUDModel(
                title: "とても長い名前のアプリケーションのプロファイル（テスト用の長いタイトル）",
                pageIndex: 0,
                pageCount: 2,
                cells: [
                    HUDCell(title: "選択範囲を要約してクリップボードへコピー", icon: .symbol("sparkles"), detail: "⌥⇧⌘⌃K → ⌘C → ⌘V"),
                    nil, nil, nil, nil, nil, nil, nil,
                    HUDCell(title: "T", icon: .text("あ"), detail: nil),
                ],
                highlightedIndex: 5,
                hint: Self.releaseHint,
                banner: ControllerPresentation.trialEndedBanner
            )),
        ]
        for (name, model) in models {
            let size = HUDLayout.size(for: model)
            let margin = HUDLayout.shadowMargin
            let store = HUDStore()
            store.model = model
            try Self.render(
                HUDRootView(store: store).background(Color(white: 0.82)),
                size: CGSize(width: size.width + margin * 2, height: size.height + margin * 2),
                appearance: .aqua,
                name: name
            )
        }
    }

    @Test("トースト")
    func toasts() throws {
        let xcode = try #require(PresetLibrary.preset(forBundleID: ShellFixtures.xcode))
        let cells = xcode.pages[0].cells.compactMap { $0 }
        let build = try #require(cells.first { $0.title == L10n.core("ビルド") })
        let script = try #require(cells.first { $0.action.kind == .script })
        let toasts: [(String, ToastModel)] = [
            ("toast-success", ToastModel(title: build.title, detail: "⌘B", icon: build.icon, style: .success)),
            ("toast-info", ToastModel(title: L10n.ui("Nonet は無効です"), style: .info)),
            ("toast-app", ToastModel(title: "Safari", icon: .app(bundleID: ShellFixtures.safari), style: .success)),
            // スクリプトのエラー出力は zsh のまま（訳さない）
            ("toast-failure", ToastModel(
                title: script.title,
                detail: "zsh:1: command not found: claude\n" + NonetError.timedOut.localizedDescription,
                icon: script.icon,
                style: .failure
            )),
            // 試用期間が終わったあとにマスを押したとき（NonetController と同じ文言）
            ("toast-failure-license", ToastModel(
                title: build.title,
                detail: NonetError.licenseRequired.localizedDescription,
                icon: build.icon,
                style: .failure
            )),
            ("toast-failure-menu", ToastModel(
                title: build.title,
                detail: NonetError.menuItemNotFound("Product › Build").localizedDescription,
                icon: build.icon,
                style: .failure
            )),
        ]
        let measurer = NSHostingController(rootView: HUDToastView(toast: ToastModel(title: "")))
        for (name, toast) in toasts {
            measurer.rootView = HUDToastView(toast: toast)
            let fitting = measurer.sizeThatFits(in: CGSize(width: HUDToastLayout.maxWidth, height: 400))
            let margin = HUDToastLayout.shadowMargin
            let store = HUDToastStore()
            store.toast = toast
            try Self.render(
                HUDToastRootView(store: store).background(Color(white: 0.82)),
                size: CGSize(width: min(ceil(fitting.width), HUDToastLayout.maxWidth) + margin * 2, height: ceil(fitting.height) + margin * 2),
                appearance: .aqua,
                name: name
            )
        }
    }

    @Test("結果のパネル")
    func result() throws {
        let text = """
        この記事は、MacBook のトラックパッドを 3×3 のボタンとして使うアイデアを紹介しています。

        ・トリガーキーを押している間だけ、トラックパッドが9つのボタンになる
        ・慣れたらすぐにタップして実行し、迷ったときだけ HUD で確かめる
        ・前面のアプリに合わせて9マスが切り替わり、1つのアプリに最大3ページまで置ける

        設定は Mac の中だけに保存され、アカウントも要りません。
        """
        let screen = HUDScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
        for (suffix, appearance) in Self.appearances {
            for (name, body) in [("result", text), ("result-long", String(repeating: text + "\n\n", count: 6))] {
                let store = HUDResultStore()
                store.model = ResultModel(title: L10n.core("要約"), text: body, icon: .symbol("sparkles"))
                let size = HUDResultLayout.panelSize(textHeight: HUDResultLayout.textHeight(of: body), screen: screen)
                try Self.render(
                    HUDResultView(store: store, onCopy: {}, onClose: {})
                        .background(Color(nsColor: .windowBackgroundColor)),
                    size: size,
                    appearance: appearance,
                    name: "\(name)-\(suffix)"
                )
            }
        }
    }

    @Test("初回起動")
    func onboarding() throws {
        let allPresets = Set(PresetLibrary.apps.map(\.app.bundleID) + PresetLibrary.launcherCandidates.map(\.bundleID))
        for (suffix, appearance) in Self.appearances {
            // 1. 許可待ち・許可済み・起動したときの許可の案内（トラックパッドも無い）
            let waiting = Self.onboardingModel(installed: allPresets, granted: false)
            try Self.renderOnboarding(waiting.0, appearance: appearance, name: "onboarding-1-welcome-\(suffix)")
            let granted = Self.onboardingModel(installed: allPresets, granted: true)
            try Self.renderOnboarding(granted.0, appearance: appearance, name: "onboarding-1-granted-\(suffix)")
            let reminder = Self.onboardingModel(installed: allPresets, granted: false, trackpad: false)
            reminder.0.purpose = .permission(remindsAtLaunch: true)
            try Self.renderOnboarding(reminder.0, appearance: appearance, name: "onboarding-1-reminder-\(suffix)")

            // 2. アプリを選ぶ（多い・もう一度見る・無い）
            granted.0.next()
            granted.0.toggle(ShellFixtures.safari)
            try Self.renderOnboarding(granted.0, appearance: appearance, name: "onboarding-2-apps-\(suffix)")
            let rerun = Self.onboardingModel(installed: allPresets, granted: true, isFirstLaunchGuide: false)
            // Xcode は無効にし、Safari は消してある
            rerun.1.controller.update { configuration in
                if let xcode = configuration.appProfile(forBundleID: ShellFixtures.xcode)?.id {
                    configuration.updateProfile(id: xcode) { $0.isEnabled = false }
                }
                if let safari = configuration.appProfile(forBundleID: ShellFixtures.safari)?.id {
                    configuration.removeProfile(id: safari)
                }
            }
            rerun.0.next()
            try Self.renderOnboarding(rerun.0, appearance: appearance, name: "onboarding-2-rerun-\(suffix)")
            let none = Self.onboardingModel(installed: [], granted: true)
            none.0.next()
            try Self.renderOnboarding(none.0, appearance: appearance, name: "onboarding-2-empty-\(suffix)")

            // 3. 試してみる（HUD から・違うマス・すぐにタップ・HUD から押した・成功と角の紹介・角を試す・試せない）
            granted.0.applySelection()
            try Self.renderOnboarding(granted.0, appearance: appearance, name: "onboarding-3-practice-\(suffix)")
            let page = try #require(granted.0.practicePage)
            let wrong = (0..<Page.cellCount).first { $0 != page.hudTarget.index && page.titles[$0] != nil } ?? 0
            granted.0.handleExecution(ShellFixtures.record(index: wrong, date: Date().addingTimeInterval(60), title: page.titles[wrong] ?? "", fastTap: false))
            try Self.renderOnboarding(granted.0, appearance: appearance, name: "onboarding-3-wrong-\(suffix)")
            granted.0.handleExecution(ShellFixtures.record(index: page.hudTarget.index, date: Date().addingTimeInterval(61), fastTap: false))
            try Self.renderOnboarding(granted.0, appearance: appearance, name: "onboarding-3-quicktap-\(suffix)")
            granted.0.handleExecution(ShellFixtures.record(index: page.quickTapTarget.index, date: Date().addingTimeInterval(62), fastTap: false))
            try Self.renderOnboarding(granted.0, appearance: appearance, name: "onboarding-3-usedhud-\(suffix)")
            granted.0.handleExecution(ShellFixtures.record(index: page.quickTapTarget.index, date: Date().addingTimeInterval(63), fastTap: true))
            try Self.renderOnboarding(granted.0, appearance: appearance, name: "onboarding-3-success-\(suffix)")
            granted.0.tryCornerActivation()
            try Self.renderOnboarding(granted.0, appearance: appearance, name: "onboarding-3-corner-\(suffix)")
            granted.0.handleExecution(ShellFixtures.record(index: 4, date: Date().addingTimeInterval(64), fastTap: false))
            try Self.renderOnboarding(granted.0, appearance: appearance, name: "onboarding-3-corner-done-\(suffix)")
            waiting.0.next()
            waiting.0.applySelection()
            try Self.renderOnboarding(waiting.0, appearance: appearance, name: "onboarding-3-blocked-\(suffix)")
            // 無効で、しかも許可も無い: 先に「有効にする」を出す
            waiting.1.controller.update { $0.settings.isEnabled = false }
            try Self.renderOnboarding(waiting.0, appearance: appearance, name: "onboarding-3-blocked-disabled-\(suffix)")

            // 4. 完了（アイコンが見えない・ログイン時に起動の許可待ちも）
            granted.0.next()
            try Self.renderOnboarding(granted.0, appearance: appearance, name: "onboarding-4-done-\(suffix)")
            granted.0.back()
            granted.0.statusItemVisibility = { false }
            granted.0.next()
            granted.1.loginItem.failure = NonetError.permissionDenied("")
            _ = granted.0.finish()
            try Self.renderOnboarding(granted.0, appearance: appearance, name: "onboarding-4-done-notes-\(suffix)")
            granted.0.close()
            waiting.0.close()
            reminder.0.close()
        }
    }

    @Test("メニューバーのアイコン")
    func menuBarIcons() throws {
        for (suffix, background, tint) in [("light", NSColor(white: 0.93, alpha: 1), NSColor.black), ("dark", NSColor(white: 0.16, alpha: 1), NSColor.white)] {
            let scale: CGFloat = 8
            let canvas = MenuBarIconGeometry.canvas
            let states = MenuBarIconState.allCases
            let size = CGSize(width: (canvas.width * scale + 24) * CGFloat(states.count) + 24, height: canvas.height * scale + 48)
            let image = NSImage(size: size, flipped: false) { rect in
                background.setFill()
                rect.fill()
                for (index, state) in states.enumerated() {
                    let icon = MenuBarIconRenderer.image(for: state)
                    let tinted = NSImage(size: icon.size, flipped: false) { iconRect in
                        icon.draw(in: iconRect)
                        tint.set()
                        iconRect.fill(using: .sourceAtop)
                        return true
                    }
                    let alpha: CGFloat = state == .disabled ? 0.5 : 1
                    tinted.draw(
                        in: CGRect(x: 24 + CGFloat(index) * (canvas.width * scale + 24), y: 24, width: canvas.width * scale, height: canvas.height * scale),
                        from: .zero,
                        operation: .sourceOver,
                        fraction: alpha
                    )
                }
                return true
            }
            try Self.write(image, name: "menubar-icons-\(suffix)")
        }
    }

    // MARK: - 部品

    static func hudModel(title: String, page: Page, highlighted: Int?, pageIndex: Int = 0, pageCount: Int, hint: String = releaseHint) -> HUDModel {
        HUDModel(
            title: title,
            pageIndex: pageIndex,
            pageCount: pageCount,
            cells: page.cells.map { cell in
                cell.map { cell in
                    let detail: String? = if case .keystroke(let keys) = cell.action { keys.displayString } else { nil }
                    return HUDCell(title: cell.title, icon: cell.icon, detail: detail, requiresHUD: cell.requiresHUD)
                }
            },
            highlightedIndex: highlighted,
            hint: hint
        )
    }

    /// 前面のアプリは Xcode（練習の図に Xcode のボタンが並ぶ）
    static func onboardingModel(installed: Set<String>, granted: Bool, isFirstLaunchGuide: Bool = true, trackpad: Bool = true) -> (OnboardingModel, ShellControllerHarness) {
        let harness = ShellControllerHarness(installed: installed, accessibilityGranted: granted)
        harness.frontmost.current = ShellFixtures.running(ShellFixtures.xcode, name: "Xcode")
        harness.touchSource.isAvailable = trackpad
        harness.controller.start()
        let model = OnboardingModel(
            controller: harness.controller,
            license: harness.license,
            permissions: harness.permissions,
            installedApps: harness.installedApps,
            frontmostApp: harness.frontmost,
            touchSource: harness.touchSource,
            loginItem: harness.loginItem,
            isFirstLaunchGuide: isFirstLaunchGuide
        )
        model.announce = { _ in }
        model.scheduleAfter = { _, _ in }
        return (model, harness)
    }

    static func renderOnboarding(_ model: OnboardingModel, appearance: NSAppearance.Name, name: String) throws {
        try render(
            OnboardingView(model: model, onOpenSettings: {}, onFinish: {})
                .background(Color(nsColor: .windowBackgroundColor)),
            size: OnboardingLayout.windowSize,
            appearance: appearance,
            name: name
        )
    }

    /// 画面に出さないウィンドウに置いて、本物の AppKit の部品で描く
    static func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, name: String) throws {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // SwiftUI の更新（画像の読み込みなど）を流す
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: try url(name))
    }

    static func write(_ image: NSImage, name: String) throws {
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: try url(name))
    }

    static func url(_ name: String) throws -> URL {
        let directory = URL(fileURLWithPath: try #require(shotsDirectory), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(name).png")
    }
}

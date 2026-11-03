// 担当: ui-shell（クラス名・init・show は契約）
import AppKit
import NonetCore
import SwiftUI

/// 初回起動のウィンドウ（権限 → 試してみる）
@MainActor
public final class OnboardingWindowController {
    /// 練習の画面の「設定を開く」と「ライセンスキーを入力…」。nil なら「設定を開く」は出さない
    public var onOpenSettings: ((SettingsTab) -> Void)?
    /// 案内を閉じたとき（「設定を開く」で閉じたときは呼ばない。設定のウィンドウが開くので）。メニューバーのアイコンの場所を見せる
    public var onComplete: (() -> Void)?
    /// メニューバーのアイコンが見えているか（練習の画面で、見えなければ見つけ方を文で伝える）
    public var isStatusItemVisible: () -> Bool {
        get { model.statusItemVisibility }
        set { model.statusItemVisibility = newValue }
    }
    /// 案内をどうして開いたか。show() の前に入れる
    public var purpose: OnboardingPurpose {
        get { model.purpose }
        set { model.purpose = newValue }
    }
    /// 「今後表示しない」を覚える場所（purpose が .permission(remindsAtLaunch: true) のときに出す）
    public var reminderPreference: OnboardingReminderPreference? {
        get { model.reminder }
        set { model.reminder = newValue }
    }
    /// アクセシビリティが許可されたときにウィンドウを前に出す（テストではウィンドウを出さずに数える）
    var raiseWindow: () -> Void = {}
    /// ウィンドウを閉じたときに、ほかに Nonet のウィンドウが無ければ前面を前のアプリに返す（テストでは数える）
    var handBackActivation: () -> Void = { ShellActivation.handBackAfterClosingWindow() }

    let model: OnboardingModel
    private let controller: NonetController
    private let onFinish: () -> Void
    private var window: NSWindow?
    private let windowDelegate = OnboardingWindowDelegate()
    private var permissionTimer: Timer?
    private var executionObserver: ShellObserver<ExecutionRecord?>?
    private var cancellationObserver: ShellObserver<CancellationRecord?>?
    private var didFinish = false
    /// 「設定を開く」で閉じる（アイコンの場所は見せない）
    private var isClosingForSettings = false

    /// license: 試用期間が終わっていて練習できないことを知らせ、ライセンスキーを登録したら知らせを消すために見る。
    /// onFinish: ウィンドウを閉じたとき（完了・途中で閉じたとき）
    public init(controller: NonetController, services: NonetServices, license: LicenseManager? = nil, onFinish: @escaping () -> Void) {
        self.controller = controller
        self.onFinish = onFinish
        model = OnboardingModel(
            controller: controller,
            license: license,
            permissions: services.permissions,
            frontmostApp: services.frontmostApp,
            touchSource: services.touchSource,
            loginItem: services.loginItem
        )
        raiseWindow = { [weak self] in self?.bringToFront() }
        // ライセンスの登録は設定で行い、案内は開いたまま戻ってこられるようにする
        model.onOpenSettings = { [weak self] tab in self?.onOpenSettings?(tab) }
    }

    public func show() {
        let window = self.window ?? makeWindow()
        if self.window == nil {
            self.window = window
            didFinish = false
            window.center()
            startWatching()
        }
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        // アプリが前面にならなかったときはキーにならない（キーになったら通知で知る）
        model.setWindowKey(window.isKeyWindow)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingLayout.windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Nonet へようこそ", bundle: .module)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        let view = OnboardingView(
            model: model,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onFinish: { [weak self] in self?.complete() }
        )
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(OnboardingLayout.windowSize)
        windowDelegate.onClose = { [weak self] in self?.windowDidClose() }
        windowDelegate.onOcclusionChange = { [weak self] visible in self?.model.setWindowVisible(visible) }
        windowDelegate.onKeyChange = { [weak self] isKey in self?.model.setWindowKey(isKey) }
        window.delegate = windowDelegate
        return window
    }

    /// 許可を1秒ごとに確かめ、練習の記録を見張る
    private func startWatching() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPermission() }
        }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        executionObserver = ShellObserver({ [weak self] in
            self?.controller.lastExecution
        }, onChange: { [weak self] record in
            self?.model.handleExecution(record)
        })
        cancellationObserver = ShellObserver({ [weak self] in
            self?.controller.lastCancellation
        }, onChange: { [weak self] record in
            self?.model.handleCancellation(record)
        })
    }

    /// 許可されたら、システム設定の後ろに隠れたウィンドウを前に出す（Nonet は Dock にも ⌘Tab にも出ないので、自分では探せない）
    func checkPermission() {
        if model.pollPermission() {
            raiseWindow()
        }
    }

    private func bringToFront() {
        guard let window else { return }
        // ほかのアプリが前面のときは前面にしてもらえないことがあるので、まずウィンドウだけでも前に出す
        window.orderFrontRegardless()
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        model.setWindowKey(window.isKeyWindow)
    }

    /// 「設定を開く」。「ログイン時に起動」を反映し、閉じて設定の「プロファイル」を開く。反映できなければ、知らせを出して開いたままにする
    func openSettings() {
        guard model.finish() else { return }
        isClosingForSettings = true
        let open = onOpenSettings
        window?.close()
        open?(.profiles)
    }

    /// 「完了」「スキップ」。「ログイン時に起動」を反映して閉じる（アイコンの場所は windowDidClose で見せる）
    func complete() {
        guard model.finish() else { return }
        window?.close()
    }

    #if DEBUG
    /// 見た目の確認用（App の --onboarding-step）。welcome・practice のどちらか
    public func previewStep(_ name: String) {
        let steps: [String: OnboardingStep] = ["welcome": .welcome, "practice": .practice]
        guard let step = steps[name] else { return }
        model.preview(step)
    }
    #endif

    /// ウィンドウが閉じたとき（テストからはウィンドウを出さずに呼ぶ）
    func windowDidClose() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        executionObserver?.cancel()
        cancellationObserver?.cancel()
        executionObserver = nil
        // 閉じるボタンで閉じたときも、練習の画面で見せていた「ログイン時に起動」の選択は反映する（知らせはもう出せない）
        _ = model.finish()
        model.close()
        window?.delegate = nil
        window = nil
        handBackActivation()
        guard !didFinish else { return }
        didFinish = true
        // どう閉じても（閉じるボタンでも）、アイコンの場所を見せる。Nonet は Dock に出ないので、ここで覚えてもらう
        if !isClosingForSettings {
            onComplete?()
        }
        onFinish()
    }
}

private final class OnboardingWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (@MainActor () -> Void)?
    var onOcclusionChange: (@MainActor (Bool) -> Void)?
    var onKeyChange: (@MainActor (Bool) -> Void)?

    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { onClose?() }
    }

    /// ほかのウィンドウに完全に隠れた・しまった・画面がロックされたときは見えていない
    func windowDidChangeOcclusionState(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let window = notification.object as? NSWindow else { return }
            onOcclusionChange?(window.occlusionState.contains(.visible))
        }
    }

    /// ほかのアプリに切り替えたときもキーでなくなる（一部が見えていても練習モードにしない）
    func windowDidBecomeKey(_ notification: Notification) {
        MainActor.assumeIsolated { onKeyChange?(true) }
    }

    func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated { onKeyChange?(false) }
    }
}

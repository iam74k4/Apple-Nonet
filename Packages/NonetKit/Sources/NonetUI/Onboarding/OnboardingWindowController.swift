// 担当: ui-shell（クラス名・init・show は契約）
import AppKit
import NonetCore
import SwiftUI

/// 初回起動のウィンドウ（権限 → アプリを選ぶ → 試してみる → 完了）
@MainActor
public final class OnboardingWindowController {
    /// 完了の画面の「設定を開く」。nil ならボタンを出さない
    public var onOpenSettings: ((SettingsTab) -> Void)?

    /// このプロセスで、初回の選択でプロファイルを作り直したか（もう一度見るときは作り直さない）
    private static var hasReplacedProfiles = false

    private let controller: NonetController
    private let model: OnboardingModel
    private let onFinish: () -> Void
    private var window: NSWindow?
    private let windowDelegate = OnboardingWindowDelegate()
    private var permissionTimer: Timer?
    private var executionObserver: ShellObserver<ExecutionRecord?>?
    private var didFinish = false

    /// onFinish: ウィンドウを閉じたとき（完了・途中で閉じたとき）
    public init(controller: NonetController, services: NonetServices, onFinish: @escaping () -> Void) {
        self.controller = controller
        self.onFinish = onFinish
        model = OnboardingModel(
            controller: controller,
            permissions: services.permissions,
            installedApps: services.installedApps,
            replacesProfiles: controller.isFirstLaunch && !Self.hasReplacedProfiles
        )
        model.onSelectionApplied = { [weak model] in
            if model?.replacesProfiles == true {
                Self.hasReplacedProfiles = true
            }
        }
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
            onFinish: { [weak self] in self?.window?.close() }
        )
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(OnboardingLayout.windowSize)
        windowDelegate.onClose = { [weak self] in self?.windowDidClose() }
        windowDelegate.onOcclusionChange = { [weak self] visible in self?.model.setWindowVisible(visible) }
        window.delegate = windowDelegate
        return window
    }

    /// 許可を1秒ごとに確かめ、練習の記録を見張る
    private func startWatching() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.pollPermission() }
        }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        executionObserver = ShellObserver({ [weak self] in
            self?.controller.lastExecution
        }, onChange: { [weak self] record in
            self?.model.handleExecution(record)
        })
    }

    private func openSettings() {
        let open = onOpenSettings
        window?.close()
        open?(.profiles)
    }

    private func windowDidClose() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        executionObserver?.cancel()
        executionObserver = nil
        model.close()
        window?.delegate = nil
        window = nil
        guard !didFinish else { return }
        didFinish = true
        onFinish()
    }
}

private final class OnboardingWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (@MainActor () -> Void)?
    var onOcclusionChange: (@MainActor (Bool) -> Void)?

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
}

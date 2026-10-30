// 担当: ui-shell（クラス名・init は契約）
import AppKit
import NonetCore
import SwiftUI

/// メニューバーのアイコンとメニュー。アイコンは NonetController と LicenseManager の変化に合わせて変え、
/// メニューは開くたびに今の状態から作り直す
@MainActor
public final class MenuBarController {
    /// 「アクセシビリティを許可…」で呼ぶ（App は案内の許可の画面を開く）。nil なら初回の案内を開く
    public var onRequestAccessibility: (() -> Void)?
    /// 「◯◯のボタンを編集…」で呼ぶ。開くアプリ（グローバルなら nil）を渡す。nil なら設定の「プロファイル」を開く
    public var onEditButtons: ((AppReference?) -> Void)?
    /// 前面のアプリ（Nonet を数えない）。「◯◯のボタンを編集…」の◯◯を決める。nil ならいつもグローバル
    public var frontmostApp: (@MainActor () -> AppReference?)?
    /// 購入ページ（「Nonet を購入…」）と利用ガイド（「利用ガイド」）。無いページの項目は出さない
    public var links = AppLinks()
    /// ページを開く（テストでは数える）
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// 定期の確認でアップデートが見つかった（App が Sparkle から受けて入れる）。
    /// アイコンに印を付け、メニューに「アップデートがあります…」を出す
    public var isUpdateAvailable = false {
        didSet {
            // @Observable ではないので、見張りに頼らずここでアイコンを描き直す
            if isUpdateAvailable != oldValue {
                applyIcon(currentState())
            }
        }
    }

    private let controller: NonetController
    private let license: LicenseManager
    private let onOpenSettings: (SettingsTab) -> Void
    private let onOpenOnboarding: () -> Void
    private let onCheckForUpdates: (() -> Void)?

    /// メニューバーのアイコン（テストから見た目を確かめる）
    let statusItem: NSStatusItem
    /// メニューバーのメニュー（テストから項目を押す）
    let menu = NSMenu()
    private let menuDelegate = MenuBarMenuDelegate()
    private let actionTarget = MenuBarActionTarget()
    private var observer: ShellObserver<MenuBarState>?
    private let callout = MenuBarCallout()

    public init(
        controller: NonetController,
        license: LicenseManager,
        onOpenSettings: @escaping (SettingsTab) -> Void,
        onOpenOnboarding: @escaping () -> Void,
        onCheckForUpdates: (() -> Void)?
    ) {
        self.controller = controller
        self.license = license
        self.onOpenSettings = onOpenSettings
        self.onOpenOnboarding = onOpenOnboarding
        self.onCheckForUpdates = onCheckForUpdates
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.behavior = []

        menu.autoenablesItems = false
        menu.delegate = menuDelegate
        statusItem.menu = menu
        menuDelegate.onNeedsUpdate = { [weak self] in self?.rebuildMenu() }

        observer = ShellObserver({ [weak self] in
            self?.currentState() ?? MenuBarState(status: .stopped, isEnabled: false, entitlement: .expired)
        }, onChange: { [weak self] state in
            self?.applyIcon(state)
        })
    }

    private func currentState() -> MenuBarState {
        MenuBarState(
            controller: controller,
            license: license,
            canCheckForUpdates: onCheckForUpdates != nil,
            isUpdateAvailable: isUpdateAvailable,
            frontApp: frontmostApp?(),
            links: links
        )
    }

    // MARK: - アイコンの場所を見せる

    /// メニューバーのアイコンが見えているか（項目が多くてノッチの陰に隠れたり、メニューバーを整理するアプリに隠されたりしていない）
    public var isStatusItemVisible: Bool {
        guard statusItem.isVisible, let button = statusItem.button, let window = button.window, window.isVisible,
              window.occlusionState.contains(.visible) else { return false }
        let frame = window.frame
        let screens = NSScreen.screens.map { screen in
            MenuBarItemVisibility.Screen(
                frame: screen.frame,
                hasNotch: screen.safeAreaInsets.top > 0,
                auxiliaryTopRightArea: screen.auxiliaryTopRightArea
            )
        }
        return MenuBarItemVisibility.isVisible(itemFrame: frame, screens: screens)
    }

    /// 初回の案内を終えたときに、メニューバーのアイコンを数回光らせ、その下に短い吹き出しを出す
    public func pointAtStatusItem() {
        guard let button = statusItem.button, isStatusItemVisible else { return }
        let text = String(localized: "Nonet はここにいます", bundle: .module)
        callout.show(text: text, below: button)
        HUDAccessibility.announce(text)
    }

    private func applyIcon(_ state: MenuBarState) {
        guard let button = statusItem.button else { return }
        let iconState = MenuBarModel.buttonIconState(for: state)
        button.image = MenuBarIconRenderer.image(for: iconState)
        button.appearsDisabled = iconState == .disabled
        let description = MenuBarModel.accessibilityDescription(for: state)
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }

    /// メニューを開く直前に呼ばれる
    private func rebuildMenu() {
        // 日付が変わっていれば試用の残り日数を更新する
        license.refresh()
        let state = currentState()
        applyIcon(state)
        menu.removeAllItems()
        for entry in MenuBarModel.entries(for: state) {
            menu.addItem(makeItem(entry))
        }
    }

    private func makeItem(_ entry: MenuBarEntry) -> NSMenuItem {
        switch entry {
        case .separator:
            return .separator()
        case .status(let text, let iconState):
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = NSImage(systemSymbolName: Self.statusSymbol(iconState), accessibilityDescription: nil)
            return item
        case .notice(let text):
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.view = MenuBarNoticeView(text: text)
            return item
        case .dismissNotice:
            return actionItem(entry) { [weak self] in self?.controller.dismissNotice() }
        case .requestAccessibility:
            return actionItem(entry) { [weak self] in
                guard let self else { return }
                if let request = self.onRequestAccessibility {
                    request()
                } else {
                    self.onOpenOnboarding()
                }
            }
        case .toggleEnabled(let isOn):
            let item = actionItem(entry) { [weak self] in
                self?.controller.update { $0.settings.isEnabled.toggle() }
            }
            item.state = isOn ? .on : .off
            return item
        case .openSettings:
            let item = actionItem(entry) { [weak self] in self?.onOpenSettings(.general) }
            item.keyEquivalent = ","
            return item
        case .editButtons(let target):
            return actionItem(entry) { [weak self] in
                guard let self else { return }
                if let edit = self.onEditButtons {
                    edit(target.app)
                } else {
                    self.onOpenSettings(.profiles)
                }
            }
        case .showOnboarding:
            return actionItem(entry) { [weak self] in self?.onOpenOnboarding() }
        case .userGuide:
            return actionItem(entry) { [weak self] in
                guard let self, let url = self.links.support else { return }
                self.openURL(url)
            }
        case .license, .enterLicenseKey:
            return actionItem(entry) { [weak self] in self?.onOpenSettings(.license) }
        case .trialInfo(let text):
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        case .purchase:
            return actionItem(entry) { [weak self] in
                guard let self, let url = self.links.purchase else { return }
                self.openURL(url)
            }
        case .checkForUpdates, .updateAvailable:
            // 見つかっているときは、Sparkle がその知らせの画面を出す
            return actionItem(entry) { [weak self] in self?.onCheckForUpdates?() }
        case .quit:
            let item = actionItem(entry) { NSApplication.shared.terminate(nil) }
            item.keyEquivalent = "q"
            return item
        }
    }

    private func actionItem(_ entry: MenuBarEntry, _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: entry.title, action: #selector(MenuBarActionTarget.runAction(_:)), keyEquivalent: "")
        item.target = actionTarget
        item.representedObject = MenuBarAction(action)
        item.isEnabled = true
        return item
    }

    private static func statusSymbol(_ state: MenuBarIconState) -> String {
        switch state {
        case .normal, .updateAvailable: "checkmark.circle"
        case .disabled: "pause.circle"
        case .attention: "exclamationmark.triangle"
        }
    }
}

/// NSMenuDelegate は NSObject が要るので、MenuBarController（契約で NSObject ではない）の代わりに受ける
private final class MenuBarMenuDelegate: NSObject, NSMenuDelegate {
    var onNeedsUpdate: (@MainActor () -> Void)?

    func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { onNeedsUpdate?() }
    }
}

/// メニュー項目の動作（representedObject に入れる）
private final class MenuBarAction {
    let run: @MainActor () -> Void

    init(_ run: @escaping @MainActor () -> Void) {
        self.run = run
    }
}

private final class MenuBarActionTarget: NSObject {
    /// perform(_:) という名前にすると、#selector が NSObject の performSelector: を指してしまい、押しても動かない
    @objc func runAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuBarAction else { return }
        MainActor.assumeIsolated { action.run() }
    }
}

/// 知らせ（設定ファイルが壊れていた など）は長いことがあるので、折り返して出す
private final class MenuBarNoticeView: NSView {
    private static let width: CGFloat = 280
    private static let insets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)

    init(text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = Self.width - Self.insets.left - Self.insets.right
        label.isSelectable = false
        let labelSize = label.fittingSize
        let height = ceil(labelSize.height) + Self.insets.top + Self.insets.bottom
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: height))
        label.frame = NSRect(
            x: Self.insets.left,
            y: Self.insets.bottom,
            width: Self.width - Self.insets.left - Self.insets.right,
            height: ceil(labelSize.height)
        )
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

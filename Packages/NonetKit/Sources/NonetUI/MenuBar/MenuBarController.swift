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
    /// 「最近の実行」で選んだボタンを設定で開く
    public var onShowRun: ((ExecutionRecord) -> Void)?
    /// 早見表で押したマスを設定で開く（プロファイルの id と、プロファイル内のページとマス）。nil なら設定の「プロファイル」を開く
    public var onShowCell: ((UUID, CellAddress) -> Void)?
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
    /// メニューの先頭の早見表。最初にメニューを開いたときに作り、開くたびに中身だけ入れ直す（開くのを遅くしない）
    private(set) var cheatSheetItem: NSMenuItem?
    /// 「このアプリでは使わない」でオフにする前の使い方（アプリのプロファイルの id ごと。nil はプロファイルが無く、オフにするときに作った）。
    /// もう一度選んだときに、そのとおりに戻す
    private var modesBeforeTurningOff: [UUID: ProfileMode?] = [:]

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
        menuDelegate.onHighlight = { [weak self] item in self?.highlightChanged(item) }
        menuDelegate.onClose = { [weak self] in self?.cheatSheetView?.resetPointerState() }

        observer = ShellObserver({ [weak self] in
            self?.currentState() ?? MenuBarState(status: .stopped, isEnabled: false, entitlement: .expired)
        }, onChange: { [weak self] state in
            self?.applyIcon(state)
        })
        // 早見表のビュー（SwiftUI）を最初に作って描くのは数十ミリ秒かかるので、最初にメニューを開くときに待たせないよう、起動の後の手すきに作っておく
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated { self?.prepareCheatSheet() }
        }
    }

    /// メニューの「このアプリでは使わない」。オフにするときにプロファイルが無ければ、空のページで作る（グローバルのボタンを使っていたアプリに、
    /// プリセットのボタンを足さない）。戻すときは、オフにする前の使い方に戻す（オフにするときに作ったプロファイルは、空のままなら消す）。
    /// ほかで（設定画面で）オフにしたものは、ボタンのあるプロファイルならそれを、無ければグローバルを使う
    private func toggleTurnedOff(_ app: AppReference, isOn: Bool) {
        controller.update { configuration in
            let existing = OnboardingModel.profile(forBundleID: app.bundleID, in: configuration.profiles)
            if isOn {
                if let existing, existing.mode == .off, let remembered = modesBeforeTurningOff.removeValue(forKey: existing.id) {
                    let isEmpty = existing.pages.allSatisfy { page in page.cells.allSatisfy { $0 == nil } && page.name == nil }
                    if let mode = remembered {
                        configuration.setAppMode(mode, for: app)
                    } else if isEmpty {
                        configuration.removeProfile(id: existing.id)
                    } else {
                        configuration.setAppMode(.profile, for: app)
                    }
                    return
                }
                // 戻すときは、ボタンのあるプロファイルならそれを、無ければグローバルを使う
                let hasButtons = existing?.pages.contains { page in page.cells.contains { $0 != nil } } ?? false
                configuration.setAppMode(hasButtons ? .profile : .global, for: app)
            } else {
                guard let id = configuration.setAppMode(.off, for: app) else { return }
                modesBeforeTurningOff[id] = .some(existing?.mode)
            }
        }
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
        callout.show(text: String(localized: "Nonet はここにいます", bundle: .module), below: button)
        // 吹き出しは VoiceOver から見えないので、「ここ」ではなく場所を言う
        HUDAccessibility.announce(Self.statusItemLocationAnnouncement)
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

    /// 初回の案内を終えたときに VoiceOver で読む文
    static var statusItemLocationAnnouncement: String {
        String(localized: "Nonet のアイコンは、メニューバーの右側にあります", bundle: .module)
    }

    /// メニューを開く直前に呼ばれる
    private func rebuildMenu() {
        // 吹き出しの光らせ方が、開いたメニューのアイコンの強調を消さないよう、吹き出しはしまう
        callout.hide()
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
        case .cheatSheet(let sheet):
            guard sheet.turnedOffText == nil else {
                // 知らせだけ（押せない）。すぐ下の「このアプリでは使わない」で戻せる
                let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                return item
            }
            return cheatSheetMenuItem(sheet)
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
        case .turnOffInApp(let app, let isOn):
            let item = actionItem(entry) { [weak self] in
                self?.toggleTurnedOff(app, isOn: isOn)
            }
            item.state = isOn ? NSControl.StateValue.on : NSControl.StateValue.off
            return item
        case .recentRuns(let records):
            let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: entry.title)
            for record in records {
                let run = NSMenuItem(title: MenuBarModel.recentRunTitle(record, in: controller.configuration), action: #selector(MenuBarActionTarget.runAction(_:)), keyEquivalent: "")
                run.setAccessibilityLabel(MenuBarModel.recentRunAccessibilityLabel(record, in: controller.configuration))
                run.target = actionTarget
                run.representedObject = MenuBarAction { [weak self] in
                    guard let self else { return }
                    if let show = self.onShowRun {
                        show(record)
                    } else {
                        self.onOpenSettings(.profiles)
                    }
                }
                submenu.addItem(run)
            }
            item.submenu = submenu
            return item
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

    // MARK: - 早見表

    /// 早見表のビュー（テストから押す）
    var cheatSheetView: MenuBarCheatSheetView? {
        cheatSheetItem?.view as? MenuBarCheatSheetView
    }

    /// 早見表の項目。2回目からは作り直さず、中身を今の前面のアプリのものにする。
    /// マスはビューの中の透明なボタンで押す。キーボードで項目を選んで Return を押すと、見ているページを設定で開く
    private func cheatSheetMenuItem(_ sheet: MenuBarCheatSheet) -> NSMenuItem {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let density = MenuBarCheatSheetLayout.density(forVisibleScreenHeight: screen?.visibleFrame.height)
        let increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if let item = cheatSheetItem, let view = item.view as? MenuBarCheatSheetView {
            view.update(sheet: sheet, density: density, increasedContrast: increasedContrast)
            item.title = sheet.title
            return item
        }
        let view = MenuBarCheatSheetView(sheet: sheet, density: density, increasedContrast: increasedContrast)
        let item = NSMenuItem(title: sheet.title, action: #selector(MenuBarActionTarget.runAction(_:)), keyEquivalent: "")
        item.target = actionTarget
        item.representedObject = MenuBarAction { [weak self, weak view] in
            guard let self, let location = view?.store.sheet.pageLocation else { return }
            self.showCell(location)
        }
        item.isEnabled = true
        item.view = view
        view.onOpen = { [weak self] location in self?.openFromCheatSheet(location) }
        // 項目の名前（VoiceOver と文字で選ぶとき）を見ているページに合わせる
        view.onPageChange = { [weak item, weak view] in
            guard let item, let view else { return }
            item.title = view.store.sheet.title
        }
        cheatSheetItem = item
        return item
    }

    private func prepareCheatSheet() {
        guard cheatSheetItem == nil, let sheet = currentState().cheatSheet, sheet.turnedOffText == nil else { return }
        cheatSheetMenuItem(sheet).view?.layoutSubtreeIfNeeded()
    }

    /// 早見表のマスを押した。メニューを閉じ、閉じ終わってから設定を開く（メニューの項目を選んだときと同じ順）
    private func openFromCheatSheet(_ location: MenuBarCellLocation) {
        menu.cancelTracking()
        // メニューが開いている間は動かない（イベントを追う間の run loop の mode では動かない）
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated { self?.showCell(location) }
        }
    }

    private func showCell(_ location: MenuBarCellLocation) {
        if let show = onShowCell {
            show(location.profileID, location.address)
        } else {
            onOpenSettings(.profiles)
        }
    }

    /// キーボードで早見表の行に来たときだけ枠を描く（ポインタで乗ったときはマスのハイライトで足りる）
    private func highlightChanged(_ item: NSMenuItem?) {
        guard let view = cheatSheetView else { return }
        let isKeyboard = NSApplication.shared.currentEvent?.type == .keyDown
        view.store.isKeyboardHighlighted = item != nil && item === cheatSheetItem && isKeyboard
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
    var onHighlight: (@MainActor (NSMenuItem?) -> Void)?
    var onClose: (@MainActor () -> Void)?

    func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { onNeedsUpdate?() }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        MainActor.assumeIsolated { onHighlight?(item) }
    }

    func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated { onClose?() }
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

// 担当: ui-settings（クラス名・init・show は契約。App が使う）
import AppKit
import NonetCore
import SwiftUI
import UniformTypeIdentifiers

public enum SettingsTab: String, CaseIterable, Sendable {
    /// プロファイルと9マスの編集
    case profiles
    /// トリガーや HUD など全体の設定
    case general
    case license
    case about
}

/// 販売サイトのページ。Info.plist の値（未設定なら nil で、そのリンクは出さない）
public struct AppLinks: Equatable, Sendable {
    /// 購入ページ
    public var purchase: URL?
    /// 利用ガイドとサポート
    public var support: URL?
    /// プライバシーポリシー
    public var privacy: URL?

    public init(purchase: URL? = nil, support: URL? = nil, privacy: URL? = nil) {
        self.purchase = purchase
        self.support = support
        self.privacy = privacy
    }
}

/// 設定ウィンドウ。1つのウィンドウを使い回し、閉じても状態（選んでいたプロファイルなど）は残す
@MainActor
public final class SettingsWindowController {
    static let minimumSize = NSSize(width: 860, height: 560)
    static let defaultSize = NSSize(width: 1120, height: 720)
    static let frameAutosaveName = "NonetSettingsWindow"

    let model: SettingsModel
    /// 位置と大きさを覚える（テストでは UserDefaults に書かないよう false にする）
    var autosavesFrame = true
    private var window: NSWindow?
    private var coordinator: SettingsWindowCoordinator?

    /// onCheckForUpdates: アップデートの確認（無ければボタンを出さない）
    public init(
        controller: NonetController,
        license: LicenseManager,
        services: NonetServices,
        links: AppLinks,
        onCheckForUpdates: (() -> Void)?
    ) {
        model = SettingsModel(
            controller: controller,
            license: license,
            services: services,
            links: links,
            onCheckForUpdates: onCheckForUpdates
        )
    }

    public func show(tab: SettingsTab = .profiles) {
        let window = loadWindow()
        select(tab)
        window.makeKeyAndOrderFront(nil)
        // メニューバー常駐のアプリ（LSUIElement）は、前に出さないとウィンドウがほかのアプリの後ろに隠れる
        NSApp.activate()
        // ほかのアプリを使っている最中などで前に出せなかったときも、ウィンドウは見えるようにする
        window.orderFrontRegardless()
    }

    func select(_ tab: SettingsTab) {
        model.selectTab(tab)
        window?.title = tab.title
        window?.toolbar?.selectedItemIdentifier = SettingsWindowCoordinator.identifier(for: tab)
    }

    /// ウィンドウ（まだ無ければ作る。画面には出さない）
    func loadWindow() -> NSWindow {
        window ?? makeWindow()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumSize
        // 前に開いていた操作スペースへ移らず、今の操作スペース（フルスクリーンのアプリの上を含む）に出す
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // 中身を入れる前に delegate を付ける。中身が先にウィンドウの undoManager を尋ねると、
        // ウィンドウが自分のものを作って使い続け、設定の undoManager（マスの変更の取り消し）に届かない
        let coordinator = SettingsWindowCoordinator(owner: self, window: window)
        window.delegate = coordinator
        let hosting = NSHostingController(rootView: SettingsRootView(model: model))
        // 中身の大きさに合わせてウィンドウを縮めたり広げたりしない（最小の大きさだけ守る）
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting
        window.setContentSize(Self.defaultSize)
        window.center()
        if autosavesFrame {
            // 保存した位置と大きさがあれば戻す（無ければ上の中央のまま）
            window.setFrameAutosaveName(Self.frameAutosaveName)
        }

        let toolbar = NSToolbar(identifier: "NonetSettingsToolbar")
        toolbar.delegate = coordinator
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        model.files = coordinator

        self.coordinator = coordinator
        self.window = window
        return window
    }
}

/// ツールバー（タブ）・ウィンドウの出来事・ファイルの選択パネル
@MainActor
final class SettingsWindowCoordinator: NSObject, NSToolbarDelegate, NSWindowDelegate, SettingsFileChoosing {
    private weak var owner: SettingsWindowController?
    private weak var window: NSWindow?

    init(owner: SettingsWindowController, window: NSWindow) {
        self.owner = owner
        self.window = window
    }

    static func identifier(for tab: SettingsTab) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("NonetSettings.\(tab.rawValue)")
    }

    private static func tab(for identifier: NSToolbarItem.Identifier) -> SettingsTab? {
        SettingsTab.allCases.first { self.identifier(for: $0) == identifier }
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(Self.identifier(for:))
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = Self.tab(for: itemIdentifier) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        item.toolTip = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }

    @objc private func selectTab(_ sender: NSToolbarItem) {
        guard let tab = Self.tab(for: sender.itemIdentifier) else { return }
        owner?.select(tab)
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        owner?.model.windowDidBecomeKey()
    }

    func windowDidResignKey(_ notification: Notification) {
        owner?.model.windowDidResignKey()
    }

    func windowWillClose(_ notification: Notification) {
        // 打ちかけの欄を確定させる
        window?.makeFirstResponder(nil)
        owner?.model.windowWillClose()
    }

    /// 編集 › 取り消す（⌘Z）がマスの変更も元に戻せるよう、設定の undoManager を使う
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        owner?.model.undoManager
    }

    // MARK: SettingsFileChoosing

    private var profileDocumentType: UTType {
        UTType(filenameExtension: ConfigurationStore.profileDocumentExtension) ?? .json
    }

    func chooseExportDestination(suggestedName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.title = String(localized: "プロファイルの書き出し", bundle: .module)
        panel.allowedContentTypes = [profileDocumentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = Self.fileName(for: suggestedName)
        return await run(panel)
    }

    func chooseImportSource() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "プロファイルの読み込み", bundle: .module)
        panel.allowedContentTypes = [profileDocumentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return await run(panel)
    }

    func chooseApplication() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "アプリを選ぶ", bundle: .module)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        return await run(panel)
    }

    /// 設定ウィンドウにシートとして出す（ウィンドウが無ければ単独で）。
    /// プロファイルの追加のシートが開いていれば、その上に重ねる（ウィンドウに出すと、シートが閉じるまで待たされる）
    private func run(_ panel: NSSavePanel) async -> URL? {
        let response: NSApplication.ModalResponse
        if let window, window.isVisible {
            response = await panel.beginSheetModal(for: window.attachedSheet ?? window)
        } else {
            response = panel.runModal()
        }
        return response == .OK ? panel.url : nil
    }

    /// ファイル名に使えない文字を除いた「名前.nonetprofile」
    nonisolated static func fileName(for name: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.newlines).union(.controlCharacters))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? "Nonet" : cleaned
        return "\(base).\(ConfigurationStore.profileDocumentExtension)"
    }
}

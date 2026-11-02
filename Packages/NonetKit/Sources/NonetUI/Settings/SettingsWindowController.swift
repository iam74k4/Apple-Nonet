// 担当: ui-settings（クラス名・init・show は契約。App が使う）
import AppKit
import NonetCore
import SwiftUI
import UniformTypeIdentifiers

public enum SettingsTab: String, CaseIterable, Sendable {
    /// プロファイルと9マスの編集
    case profiles
    /// 開き方の説明や HUD など全体の設定
    case general
    /// ライセンス・書き出しと読み込み・バージョンとアップデート・利用ガイド・アンインストール（タブの名前は「Nonet」）
    case license
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

    /// 利用ガイドとプライバシーポリシーを、アプリの画面の言語（language。Bundle.main.preferredLocalizations.first）のページにする。
    /// サイトは日本語のページが /、英語のページが /en/ の下にある（guide.html ↔ en/guide.html）。購入ページはそのまま
    public func localized(language: String?) -> AppLinks {
        var links = self
        links.support = support.map { Self.page($0, language: language) }
        links.privacy = privacy.map { Self.page($0, language: language) }
        return links
    }

    /// 英語なら、パスの最後の部品の前に en/ を入れる（https://nonet.astlog.dev/guide.html → https://nonet.astlog.dev/en/guide.html、
    /// /guide/ → /en/guide/、/ → /en/）。クエリとフラグメントはそのまま。
    /// 英語でないとき、すでに en の下のページ、http(s) でない URL は変えない
    static func page(_ url: URL, language: String?) -> URL {
        guard let language, Locale.Language(identifier: language).languageCode == .english,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return url }
        let path = components.percentEncodedPath
        guard !path.split(separator: "/").contains("en") else { return url }
        // 最後の部品（末尾の / を含む）と、その前（/ で終わる）に分ける
        let trailingSlash = path.hasSuffix("/") ? "/" : ""
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let directory: Substring
        let last: Substring
        if let slash = trimmed.lastIndex(of: "/") {
            directory = trimmed[...slash]
            last = trimmed[trimmed.index(after: slash)...]
        } else {
            directory = "/"
            last = Substring(trimmed)
        }
        components.percentEncodedPath = last.isEmpty ? "\(directory)en/" : "\(directory)en/\(last)\(trailingSlash)"
        return components.url ?? url
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
    /// ウィンドウを閉じたときに、ほかに Nonet のウィンドウが無ければ前面を前のアプリに返す（テストでは数える）
    var handBackActivation: () -> Void = { ShellActivation.handBackAfterClosingWindow() }
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

    /// アプリを終える前に、打ちかけの欄と記録中のキーを確定させる（AppDelegate.applicationWillTerminate で、controller.stop() より先に呼ぶ）
    public func commitPendingEdits() {
        // 打っている欄を確定させる（windowWillClose と同じ）
        window?.makeFirstResponder(nil)
        model.applicationWillTerminate()
    }

    func select(_ tab: SettingsTab) {
        model.selectTab(tab)
        showInWindow(tab)
    }

    /// 実行したマスを選んで開く間（秒）。それより前に実行したマスは、直したいマスとは限らない
    static let recentExecutionWindow: TimeInterval = 60

    /// メニューバーの「Xcode のボタンを編集…」「Pages のボタンを作る…」「グローバルのボタンを編集…」。
    /// プロファイルのタブで app のプロファイルを選んで開く（無ければプリセットで作る）。app が nil ならグローバル。
    /// 直前（recentExecutionWindow 秒以内）にそのプロファイルのマスを実行していれば、そのページとマスを選ぶ
    public func showButtons(for app: AppReference?, now: Date = Date()) {
        _ = loadWindow()
        selectButtons(for: app, now: now)
        show(tab: .profiles)
    }

    /// メニューの「最近の実行」。そのボタンのプロファイル・ページ・マスを選んで開く。
    /// プロファイルが分からない・もう無いときは、名前で探し、それでも無ければプロファイルのタブを開くだけ
    public func showRun(_ record: ExecutionRecord) {
        _ = loadWindow()
        selectRun(record)
        show(tab: .profiles)
    }

    /// showRun の、ウィンドウを出さない部分（テストする）
    func selectRun(_ record: ExecutionRecord) {
        select(.profiles)
        let profiles = model.configuration.profiles
        guard let profile = profiles.first(where: { $0.id == record.profileID })
            ?? profiles.first(where: { $0.name == record.profileName }) else { return }
        let address = profile.pages.indices.contains(record.address.page) ? record.address : nil
        model.showProfile(id: profile.id, at: address)
    }

    /// showButtons の、ウィンドウを出さない部分（テストする）
    func selectButtons(for app: AppReference?, now: Date) {
        select(.profiles)
        let configuration = model.configuration
        if let app, OnboardingModel.profile(forBundleID: app.bundleID, in: configuration.profiles) == nil {
            // 作ったプロファイルを選ぶ（プリセットがあれば、その中身で作る）
            model.addProfile(for: app)
        } else {
            let profile = app.flatMap { OnboardingModel.profile(forBundleID: $0.bundleID, in: configuration.profiles) }
                ?? configuration.globalProfile
            model.showProfile(id: profile.id, at: Self.recentAddress(of: model.controller.lastExecution, in: profile, now: now))
        }
    }

    /// record がそのプロファイルで少し前に実行したマスなら、その場所。プロファイルは名前で見分ける（記録に id が無いため）
    static func recentAddress(of record: ExecutionRecord?, in profile: Profile, now: Date) -> CellAddress? {
        guard let record, record.profileName == profile.name else { return nil }
        let elapsed = now.timeIntervalSince(record.date)
        guard elapsed >= 0, elapsed <= recentExecutionWindow,
              profile.pages.indices.contains(record.address.page),
              (0..<Page.cellCount).contains(record.address.index) else { return nil }
        return record.address
    }

    /// ウィンドウの題名とツールバーの選択を合わせる（元に戻すでプロファイルのタブに移ったときも、ここを通る）
    private func showInWindow(_ tab: SettingsTab) {
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
        model.onTabChange = { [weak self] tab in self?.showInWindow(tab) }

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
        owner?.handBackActivation()
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

    func chooseFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "移動先のフォルダを選ぶ", bundle: .module)
        panel.prompt = String(localized: "選ぶ", bundle: .module)
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
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

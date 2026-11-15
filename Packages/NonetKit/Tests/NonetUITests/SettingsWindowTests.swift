// 担当: ui-settings
// ウィンドウの組み立て（画面には出さない）
import AppKit
import NonetCore
@testable import NonetUI
import Testing

@Suite @MainActor struct SettingsWindowTests {
    private func makeController(_ h: SettingsHarness) -> SettingsWindowController {
        let controller = SettingsWindowController(
            controller: h.controller,
            license: h.license,
            services: h.services,
            links: AppLinks(),
            onCheckForUpdates: nil
        )
        controller.autosavesFrame = false
        return controller
    }

    @Test func buildsOneReusableWindowWithTabs() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = makeController(h)
        let window = controller.loadWindow()
        #expect(controller.loadWindow() === window)
        #expect(!window.isReleasedWhenClosed)
        #expect(window.styleMask.contains([.titled, .closable, .miniaturizable, .resizable]))
        #expect(window.contentMinSize.width >= 860)
        #expect(window.contentMinSize.height >= 560)
        #expect(!window.isVisible)
        let toolbar = try #require(window.toolbar)
        #expect(toolbar.items.map(\.label) == [L10n.ui("プロファイル"), L10n.ui("一般"), "Nonet"])
        #expect(window.delegate != nil)
        #expect(controller.model.files != nil)
    }

    /// 前に開いていた操作スペース（フルスクリーンのアプリの外）へ移らず、今の操作スペースに出す
    @Test func theWindowOpensOnTheCurrentSpace() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let window = makeController(h).loadWindow()
        #expect(window.collectionBehavior.contains(.moveToActiveSpace))
        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    /// 編集 › 取り消す（⌘Z）はウィンドウの undoManager に届く。マスの変更を元に戻せるよう、設定の undoManager を返す
    /// 終了ではウィンドウが閉じないので、AppDelegate が stop() の前に打ちかけの欄と記録中のキーを確定させ、一緒に書く
    @Test func quittingCommitsTypingAndRecordingBeforeTheLastSave() throws {
        let h = try SettingsHarness()
        let window = makeController(h)
        let model = window.model
        model.createCell(kind: .shortcut, at: 1)
        let shortcutID = try #require(model.selectedCell?.id)
        let buffer = SettingsDraftBuffer(value: "", delay: .seconds(60)) { name in
            model.updateAction(ofCell: shortcutID, as: ShortcutAction.self) { $0.name = name }
        }
        buffer.registry = model.pendingEdits
        buffer.edit("翻訳")
        model.createCell(kind: .keystroke, at: 3)
        let keystrokeID = try #require(model.selectedCell?.id)
        model.beginRecording(cellID: keystrokeID)
        model.handleKeyDown(keyCode: 0x0B, characters: "b", flags: .command)

        // AppDelegate.applicationWillTerminate と同じ順
        window.commitPendingEdits()
        h.controller.stop()
        let saved = try #require(try h.store.load())
        #expect(saved.globalProfile.pages[0].cells[1]?.action == .shortcut(ShortcutAction(name: "翻訳")))
        #expect(saved.globalProfile.pages[0].cells[3]?.action == .keystroke(.key("b", .command)))
        #expect(!h.controller.isRecordingKeys)
    }

    @Test func undoGoesThroughTheSettingsUndoManager() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = makeController(h)
        let window = controller.loadWindow()
        #expect(window.undoManager === controller.model.undoManager)
        // 中身（SwiftUI）の欄も、応答の連なりで同じものに届く
        #expect(window.contentView?.undoManager === controller.model.undoManager)
    }

    /// 編集メニューの「取り消す」（宛先なしの undo:）は、ウィンドウからマスの変更の取り消しに届く
    @Test func theWindowsUndoActionUndoesCellChanges() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = makeController(h)
        let window = controller.loadWindow()
        controller.model.undoManager.groupsByEvent = false
        let safari = try #require(controller.model.selectedCell)
        controller.model.clearCell(at: 0)
        #expect(window.tryToPerform(Selector(("undo:")), with: nil))
        #expect(controller.model.selectedCell == safari)
        #expect(window.tryToPerform(Selector(("redo:")), with: nil))
        #expect(controller.model.selectedCell == nil)
    }

    /// ほかのタブで元に戻すとプロファイルのタブに移る。ウィンドウの題名とツールバーの選択も合わせる
    @Test func undoingFromAnotherTabSelectsTheProfilesTab() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = makeController(h)
        let window = controller.loadWindow()
        controller.model.undoManager.groupsByEvent = false
        controller.model.clearCell(at: 0)
        controller.select(.general)
        #expect(window.title == L10n.ui("一般"))
        controller.model.undoManager.undo()
        #expect(controller.model.tab == .profiles)
        #expect(window.title == L10n.ui("プロファイル"))
        #expect(window.toolbar?.selectedItemIdentifier == SettingsWindowCoordinator.identifier(for: .profiles))
    }

    @Test func selectingATabUpdatesTitleAndToolbar() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = makeController(h)
        let window = controller.loadWindow()
        controller.select(.license)
        #expect(controller.model.tab == .license)
        #expect(window.title == "Nonet")
        #expect(window.toolbar?.selectedItemIdentifier == SettingsWindowCoordinator.identifier(for: .license))
        controller.select(.general)
        #expect(window.title == L10n.ui("一般"))
    }

    @Test func closingTheWindowStopsKeyRecording() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = makeController(h)
        let window = controller.loadWindow()
        controller.model.createCell(kind: .keystroke, at: 1)
        let id = try #require(controller.model.selectedCell?.id)
        controller.model.beginRecording(cellID: id)
        #expect(h.controller.isRecordingKeys)
        window.delegate?.windowWillClose?(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(!h.controller.isRecordingKeys)
    }

    /// 閉じたら、ほかに Nonet のウィンドウが無ければ前面を前のアプリに返す（キーのウィンドウが無いまま Nonet を前面に残さない）
    @Test func closingTheWindowHandsBackActivation() throws {
        _ = NSApplication.shared
        let h = try SettingsHarness()
        let controller = makeController(h)
        var handBacks = 0
        controller.handBackActivation = { handBacks += 1 }
        let window = controller.loadWindow()
        window.close()
        #expect(handBacks == 1)
    }
}

/// ⌘, と「Nonet について」と、Finder で開いた .nonetprofile（ウインドウは画面に出さない）
@Suite @MainActor struct SettingsWindowMainMenuTests {
    /// もう開いていれば、⌘, はタブを替えずに前に出すだけ。閉じていれば一般のタブで開く
    @Test func settingsKeepsTheCurrentTabWhenOpen() {
        for tab in SettingsTab.allCases {
            #expect(SettingsWindowController.mainMenuSettingsTab(isOpen: true, current: tab) == tab)
            #expect(SettingsWindowController.mainMenuSettingsTab(isOpen: false, current: tab) == .general)
        }
    }

    /// 「Nonet について」は「Nonet」のタブの、情報の欄まで送る
    @Test func aboutOpensTheAboutSection() throws {
        let h = try SettingsHarness()
        #expect(!h.model.wantsAboutScroll)
        h.model.showAbout()
        #expect(h.model.tab == .license)
        #expect(h.model.wantsAboutScroll)
    }

    @Test func onlyProfileDocumentsAreImported() {
        #expect(SettingsWindowController.isProfileDocument(URL(fileURLWithPath: "/tmp/Xcode.nonetprofile")))
        #expect(SettingsWindowController.isProfileDocument(URL(fileURLWithPath: "/tmp/Xcode.NonetProfile")))
        #expect(!SettingsWindowController.isProfileDocument(URL(fileURLWithPath: "/tmp/key.nonetlicense")))
        #expect(!SettingsWindowController.isProfileDocument(URL(string: "nonet://register?key=x")!))
        #expect(!SettingsWindowController.isProfileDocument(URL(string: "https://example.com/a.nonetprofile")!))
    }

    private func exportXcode(_ h: SettingsHarness) throws -> URL {
        let xcode = try #require(h.model.appProfiles.first { $0.app?.bundleID == SettingsFixtures.xcode.bundleID })
        let url = h.directory.appending(path: "Xcode.\(ConfigurationStore.profileDocumentExtension)")
        try ConfigurationStore.exportData(profiles: [xcode]).write(to: url)
        return url
    }

    /// .nonetprofile は「読み込む…」と同じ道で読み込む（同じアプリのプロファイルが置き換わるので、先に確かめる）
    @Test func openingAProfileDocumentImportsIt() throws {
        let h = try SettingsHarness()
        let url = try exportXcode(h)
        h.model.openProfileDocument(url)
        guard case .importProfiles(let plan)? = h.model.confirmation else {
            Issue.record("読み込みを確かめていない: \(String(describing: h.model.confirmation))")
            return
        }
        #expect(plan.fileName == url.lastPathComponent)
        #expect(plan.replacesExisting)
    }

    /// シートが開いていれば閉じてから、少し待って確かめる（シートは1つずつしか出せない）
    @Test func openingAProfileDocumentClosesOtherSheetsFirst() throws {
        let h = try SettingsHarness()
        let url = try exportXcode(h)
        h.model.isCleaningUpProfiles = true
        h.model.openProfileDocument(url)
        #expect(!h.model.isCleaningUpProfiles)
        #expect(h.model.confirmation == nil)
        h.scheduler.advance(by: SettingsModel.sheetHandOverDelay)
        guard case .importProfiles? = h.model.confirmation else {
            Issue.record("読み込みを確かめていない")
            return
        }
    }
}

/// 利用ガイドとプライバシーポリシーは、画面が英語ならサイトの en/ の下のページを開く
@Suite struct SettingsLinksTests {
    static let site = "https://nonet.astlog.dev"

    @Test(arguments: [
        ("https://nonet.astlog.dev/guide.html", "https://nonet.astlog.dev/en/guide.html"),
        ("https://nonet.astlog.dev/privacy.html", "https://nonet.astlog.dev/en/privacy.html"),
        ("https://nonet.astlog.dev/guide.html?from=app#scripts", "https://nonet.astlog.dev/en/guide.html?from=app#scripts"),
        ("https://nonet.astlog.dev/guide/", "https://nonet.astlog.dev/en/guide/"),
        ("https://nonet.astlog.dev/", "https://nonet.astlog.dev/en/"),
        ("https://nonet.astlog.dev", "https://nonet.astlog.dev/en/"),
        ("https://nonet.astlog.dev/docs/guide.html", "https://nonet.astlog.dev/docs/en/guide.html"),
        // すでに英語のページ
        ("https://nonet.astlog.dev/en/guide.html", "https://nonet.astlog.dev/en/guide.html"),
        ("https://nonet.astlog.dev/en/", "https://nonet.astlog.dev/en/"),
        // サイトのページでないもの
        ("mailto:support@example.com", "mailto:support@example.com"),
    ])
    func englishPages(url: String, expected: String) {
        #expect(Self.page(url, language: "en") == expected)
    }

    @Test func otherLanguagesKeepThePage() {
        let guide = "\(Self.site)/guide.html"
        #expect(Self.page(guide, language: "ja") == guide)
        #expect(Self.page(guide, language: "ja-JP") == guide)
        #expect(Self.page(guide, language: nil) == guide)
        #expect(Self.page(guide, language: "") == guide)
        #expect(Self.page(guide, language: "en-GB") == "\(Self.site)/en/guide.html")
        // 日本語でなければ英語のページ（サイトに日本語と英語のページしか無い）
        #expect(Self.page(guide, language: "de") == "\(Self.site)/en/guide.html")
    }

    /// 英語の画面では、購入ページ・プライバシーポリシーも英語のページ（Config/Nonet.xcconfig の値）
    @Test func theShippedPagesOpenInEnglish() {
        let links = AppLinks(
            purchase: URL(string: "\(Self.site)/buy.html"),
            support: URL(string: "\(Self.site)/guide.html"),
            privacy: URL(string: "\(Self.site)/privacy.html")
        ).localized(language: "en")
        #expect(links.purchase?.absoluteString == "\(Self.site)/en/buy.html")
        #expect(links.privacy?.absoluteString == "\(Self.site)/en/privacy.html")
        #expect(links.support?.absoluteString == "\(Self.site)/en/guide.html")
    }

    @Test func onlyTheGuideAndPrivacyPolicyChange() throws {
        let links = AppLinks(
            purchase: URL(string: "https://store.example.com/nonet"),
            support: URL(string: "\(Self.site)/guide.html"),
            privacy: URL(string: "\(Self.site)/privacy.html")
        )
        let english = links.localized(language: "en")
        // 販売サービスのページ（ほかのホスト）はそのまま
        #expect(english.purchase == links.purchase)
        // 同じサイトの購入ページは、英語のページにする（日本語のページは円の税込の価格）
        let ownBuyPage = AppLinks(purchase: URL(string: "\(Self.site)/buy.html"), support: URL(string: "\(Self.site)/guide.html"))
        #expect(ownBuyPage.localized(language: "en").purchase == URL(string: "\(Self.site)/en/buy.html"))
        #expect(ownBuyPage.localized(language: "ja").purchase == URL(string: "\(Self.site)/buy.html"))
        #expect(english.support == URL(string: "\(Self.site)/en/guide.html"))
        #expect(english.privacy == URL(string: "\(Self.site)/en/privacy.html"))
        #expect(links.localized(language: "ja") == links)
        #expect(AppLinks().localized(language: "en") == AppLinks())
    }

    static func page(_ url: String, language: String?) -> String? {
        URL(string: url).map { AppLinks.page($0, language: language).absoluteString }
    }
}

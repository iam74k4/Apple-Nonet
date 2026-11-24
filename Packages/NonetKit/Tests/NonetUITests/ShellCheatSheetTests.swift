// 担当: ui-shell
// メニューの先頭の早見表（MenuBarCheatSheet の選び方とページ、MenuBarController の並びと押したときの動き、設定で開く場所）
import AppKit
import NonetCore
@testable import NonetUI
import Testing

@Suite("メニューの早見表")
@MainActor
struct ShellCheatSheetTests {
    static let xcode = SettingsFixtures.xcode

    static func xcodeProfile(_ configuration: NonetConfiguration) throws -> Profile {
        try #require(configuration.appProfile(forBundleID: xcode.bundleID))
    }

    /// メニューの外に置いた RunLoop.perform（メニューが閉じてから動くもの）を動かす
    static func drainDefaultRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    // MARK: - どのページとマスを出すか

    @Test("前面のアプリのプロファイルの最初のページ（トリガーを押したときと同じ resolvedPages）")
    func frontAppProfile() throws {
        let configuration = SettingsFixtures.configuration()
        let profile = try Self.xcodeProfile(configuration)
        let sheet = MenuBarCheatSheet(frontApp: Self.xcode, configuration: configuration)
        #expect(sheet.pages == configuration.resolvedPages(frontmostBundleID: Self.xcode.bundleID))
        #expect(sheet.pageIndex == 0)
        #expect(sheet.currentPage?.profileID == profile.id)
        #expect(sheet.title == L10n.ui("\(profile.name) のマス"))
        #expect(sheet.turnedOffText == nil)
        for index in 0..<Page.cellCount {
            #expect(sheet.cell(at: index) == profile.pages[0].cells[index])
            #expect(sheet.cellTitle(at: index) == profile.pages[0].cells[index].map(SettingsGrid.displayTitle(for:)))
            // ヘルプは、押すと実行ではなく設定で開くことを言う
            if let title = sheet.cellTitle(at: index) {
                // ⌥クリックで実行できることも言う
                #expect(sheet.cellTooltip(at: index) == L10n.ui("クリックすると、設定で「\(title)」を開いて編集します。⌥クリックで、前面のアプリに向けて実行します"))
            } else {
                #expect(sheet.cellTooltip(at: index) == L10n.ui("空きマスです。クリックすると、設定でアクションを入れられます"))
            }
        }
        #expect(sheet.location(ofCell: 4) == MenuBarCellLocation(profileID: profile.id, address: CellAddress(page: 0, index: 4)))
        #expect(sheet.location(ofCell: Page.cellCount) == nil)
        #expect(sheet.cell(at: -1) == nil)
    }

    @Test("プロファイルが無い・グローバルを使う・アプリが分からないときはグローバル", arguments: [
        "noProfile", "usesGlobal", "unknownApp",
    ])
    func globalFallback(_ situation: String) {
        let configuration = SettingsFixtures.configuration()
        var front: AppReference? = Self.xcode
        switch situation {
        case "noProfile": front = SettingsFixtures.figma
        // Safari のプロファイルは無効（グローバルを使う）
        case "usesGlobal": front = SettingsFixtures.safari
        default: front = nil
        }
        let sheet = MenuBarCheatSheet(frontApp: front, configuration: configuration)
        let global = configuration.globalProfile
        #expect(sheet.currentPage?.profileID == global.id)
        #expect(sheet.title == L10n.ui("グローバルのマス"))
        #expect(sheet.cell(at: 0) == global.pages[0].cells[0])
        // 空きマスも開ける
        #expect(sheet.cell(at: 1) == nil)
        #expect(sheet.cellTitle(at: 1) == nil)
        #expect(sheet.location(ofCell: 1) == MenuBarCellLocation(profileID: global.id, address: CellAddress(page: 0, index: 1)))
        #expect(sheet.turnedOffText == nil)
    }

    @Test("「このアプリでは使わない」アプリでは、マスの代わりに短い1行")
    func turnedOffApp() throws {
        var configuration = SettingsFixtures.configuration()
        let name = try Self.xcodeProfile(configuration).name
        configuration.setAppMode(.off, for: Self.xcode)
        let sheet = MenuBarCheatSheet(frontApp: Self.xcode, configuration: configuration)
        #expect(sheet.turnedOffText == L10n.ui("\(name) では Nonet を使いません"))
        #expect(sheet.pages.isEmpty)
        #expect(sheet.location(ofCell: 0) == nil)
        #expect(MenuBarEntry.cheatSheet(sheet).title == sheet.turnedOffText)
    }

    @Test("ページ: ‹ › で移り、端で止まる。つなげたグローバルのページでは見出しと開く場所がグローバルになる")
    func pages() throws {
        var configuration = SettingsFixtures.configuration()
        let xcodeID = try Self.xcodeProfile(configuration).id
        while try Self.xcodeProfile(configuration).pages.count < 2 {
            _ = configuration.addPage(profileID: xcodeID)
        }
        configuration.renamePage(at: 1, profileID: xcodeID, to: "デバッグ")
        let appPages = try Self.xcodeProfile(configuration).pages.count
        let globalPages = configuration.globalProfile.pages.count
        var sheet = MenuBarCheatSheet(frontApp: Self.xcode, configuration: configuration)
        #expect(sheet.pageCount == appPages + globalPages)
        #expect(sheet.globalPagesStart == appPages)
        #expect(sheet.belowPageStart == nil)
        #expect(!sheet.canShowPreviousPage)
        #expect(sheet.canShowNextPage)
        #expect(sheet.pageDescription == L10n.ui("\(sheet.pageCount) ページ中 \(1) ページ目"))
        #expect(sheet.accessibilityLabel == L10n.ui("\(sheet.title)、\(sheet.pageDescription)"))

        sheet.showPreviousPage()
        #expect(sheet.pageIndex == 0)
        sheet.showNextPage()
        #expect(sheet.pageIndex == 1)
        #expect(sheet.title == "\(L10n.ui("\(try Self.xcodeProfile(configuration).name) のマス")) · デバッグ")
        #expect(sheet.location(ofCell: 2) == MenuBarCellLocation(profileID: xcodeID, address: CellAddress(page: 1, index: 2)))

        sheet.showPage(appPages)
        #expect(sheet.title == L10n.ui("グローバルのマス"))
        let global = configuration.globalProfile
        #expect(sheet.location(ofCell: 0) == MenuBarCellLocation(profileID: global.id, address: CellAddress(page: 0, index: 0)))
        #expect(sheet.cell(at: 0) == global.pages[0].cells[0])

        sheet.showPage(99)
        #expect(sheet.pageIndex == sheet.pageCount - 1)
        #expect(!sheet.canShowNextPage)
        sheet.showNextPage()
        #expect(sheet.pageIndex == sheet.pageCount - 1)
        sheet.showPage(-3)
        #expect(sheet.pageIndex == 0)
    }

    @Test("ページが1枚なら何ページ目かは言わない")
    func singlePage() {
        let sheet = MenuBarCheatSheet(frontApp: nil, configuration: SettingsFixtures.configuration())
        #expect(sheet.pageCount == 1)
        #expect(!sheet.canShowPreviousPage && !sheet.canShowNextPage)
        #expect(sheet.accessibilityLabel == sheet.title)
    }

    @Test("VoiceOver: マスは位置と名前（設定のグリッドと同じ読み方）、ヒントは設定で開くこと")
    func accessibilityText() throws {
        let configuration = SettingsFixtures.configuration()
        let profile = try Self.xcodeProfile(configuration)
        let sheet = MenuBarCheatSheet(frontApp: Self.xcode, configuration: configuration)
        for index in 0..<Page.cellCount {
            #expect(sheet.accessibilityLabel(ofCell: index) == SettingsGrid.accessibilityLabel(index: index, cell: profile.pages[0].cells[index]))
        }
        #expect(MenuBarCheatSheet.cellHint == L10n.ui("設定で開きます。操作の一覧の「前面のアプリで実行」で実行できます"))
        #expect(MenuBarCheatSheet.emptyCellHint == L10n.ui("設定で開きます"))
        #expect(MenuBarCheatSheet.runActionName == L10n.ui("前面のアプリで実行"))
        #expect(MenuBarCheatSheet.previousPageTitle == L10n.ui("前のページ"))
        #expect(MenuBarCheatSheet.nextPageTitle == L10n.ui("次のページ"))
    }

    // MARK: - メニューの並び

    @Test("早見表は状態の行（と許可・知らせ）のすぐ下。無ければ出さない")
    func entryPosition() {
        let sheet = MenuBarCheatSheet(frontApp: nil, configuration: SettingsFixtures.configuration())
        var state = ShellMenuState.make()
        #expect(!MenuBarModel.entries(for: state).contains { if case .cheatSheet = $0 { true } else { false } })
        state.cheatSheet = sheet
        let entries = MenuBarModel.entries(for: state)
        #expect(Array(entries.prefix(4)) == [.status(L10n.ui("動作中"), .normal), .separator, .cheatSheet(sheet), .separator])
        #expect(MenuBarEntry.cheatSheet(sheet).title == sheet.title)

        var blocked = ShellMenuState.make(.needsAccessibility, notice: "設定ファイルが壊れていたので退避しました")
        blocked.cheatSheet = sheet
        let blockedEntries = MenuBarModel.entries(for: blocked)
        #expect(Array(blockedEntries.prefix(6)) == [
            .status(L10n.ui("アクセシビリティの許可が必要です"), .attention),
            .requestAccessibility,
            .notice("設定ファイルが壊れていたので退避しました"),
            .dismissNotice,
            .separator,
            .cheatSheet(sheet),
        ])
    }

    @Test("許可が無い・無効にしているときも早見表を出す（見るだけなので）")
    func shownWithoutPermissionOrWhenDisabled() throws {
        let harness = ShellControllerHarness(installed: [ShellFixtures.xcode], accessibilityGranted: false)
        harness.controller.start()
        harness.controller.update { $0.settings.isEnabled = false }
        let xcode = AppReference(bundleID: ShellFixtures.xcode, name: "Xcode")
        let state = MenuBarState(controller: harness.controller, license: harness.license, canCheckForUpdates: false, frontApp: xcode)
        let sheet = try #require(state.cheatSheet)
        #expect(sheet == MenuBarCheatSheet(frontApp: xcode, configuration: harness.controller.configuration))
        #expect(sheet.currentPage?.profileID == harness.controller.configuration.appProfile(forBundleID: ShellFixtures.xcode)?.id)
        #expect(MenuBarModel.entries(for: state).contains(.cheatSheet(sheet)))
    }

    // MARK: - 寸法

    @Test("寸法: 下のページの前でも、ページの点を少し離す")
    func belowPageDots() throws {
        // 下のページは最後に並び、その前でも点を少し離す（グローバルの最初のページの前と同じ）
        var configuration = SettingsFixtures.configuration()
        let globalID = configuration.globalProfile.id
        configuration.addPage(PageTemplate.utilities.makePage(), profileID: globalID)
        configuration.addPage(profileID: globalID)
        let sheet = MenuBarCheatSheet(frontApp: SettingsFixtures.notes, configuration: configuration)
        #expect(sheet.pageCount == 3)
        #expect(sheet.globalPagesStart == nil)
        #expect(sheet.belowPageStart == 2)
        // 下のページを見ているときは、見出しに下向きの矢印を添え、VoiceOver でも言う
        var shown = sheet
        #expect(!shown.isBelowPage)
        shown.showPage(2)
        #expect(shown.isBelowPage)
        #expect(shown.accessibilityLabel.hasSuffix(L10n.ui("下のページ")))
        let layout = MenuBarCheatSheetLayout(sheet: sheet, density: .regular)
        let metrics = MenuBarCheatSheetLayout.dotMetrics
        let offsets = layout.dotOffsets
        #expect(offsets[1] - offsets[0] == metrics.dotSize + metrics.dotSpacing)
        #expect(offsets[2] - offsets[1] == metrics.dotSize + metrics.dotSpacing + metrics.pageGroupGap)
    }

    @Test("寸法: マスは重ならずに収まり、見出しは ‹ › と重ならない。低い画面ではマスを低くする")
    func layout() {
        #expect(MenuBarCheatSheetLayout.density(forVisibleScreenHeight: 875) == .regular)
        #expect(MenuBarCheatSheetLayout.density(forVisibleScreenHeight: 776) == .regular)
        #expect(MenuBarCheatSheetLayout.density(forVisibleScreenHeight: 615) == .compact)
        #expect(MenuBarCheatSheetLayout.density(forVisibleScreenHeight: nil) == .regular)

        let regular = MenuBarCheatSheetLayout(density: .regular, pageCount: 4, globalPagesStart: 2)
        let compact = MenuBarCheatSheetLayout(density: .compact, pageCount: 4, globalPagesStart: 2)
        // メニューの大事な行を押し出さない大きさ
        #expect(regular.width == MenuBarCheatSheetLayout.preferredWidth)
        #expect(regular.height <= 180)
        #expect(compact.height < regular.height - 30)
        for layout in [regular, compact, MenuBarCheatSheetLayout(width: 360, density: .regular)] {
            let bounds = CGRect(origin: .zero, size: layout.size)
            let cells = (0..<Page.cellCount).map(layout.cellFrame)
            for (index, cell) in cells.enumerated() {
                #expect(bounds.contains(cell))
                #expect(layout.gridFrame.contains(cell))
                for other in cells[(index + 1)...] {
                    #expect(!cell.intersects(other))
                }
            }
            #expect(!layout.titleFrame.intersects(layout.gridFrame))
            if let previous = layout.previousButtonFrame, let next = layout.nextButtonFrame, let dots = layout.dotsFrame {
                #expect(layout.titleFrame.maxX <= previous.minX)
                #expect(previous.maxX <= dots.minX && dots.maxX <= next.minX)
                #expect(bounds.contains(next))
                #expect(abs(next.maxX - layout.gridFrame.maxX) < 0.001)
            }
        }
        // メニューが広ければマスも広がる。狭くはしない
        #expect(MenuBarCheatSheetLayout(width: 360, density: .regular).cellFrame(0).width > regular.cellFrame(0).width)
        // HUD の輪と同じ向き: 上のマスは真ん中の上、左上のマスは左上
        #expect(regular.cellFrame(1).midX == regular.cellFrame(4).midX && regular.cellFrame(1).midY < regular.cellFrame(4).midY)
        #expect(regular.cellFrame(0).midX < regular.cellFrame(4).midX && regular.cellFrame(0).midY < regular.cellFrame(4).midY)
        #expect(MenuBarCheatSheetLayout(width: 100, density: .regular).width == MenuBarCheatSheetLayout.preferredWidth)
        // ページの点は HUD と同じく、グローバルの最初のページの前を少し空ける
        let offsets = regular.dotOffsets
        #expect(offsets.count == 4)
        #expect(offsets[2] - offsets[1] > offsets[1] - offsets[0])
        #expect(MenuBarCheatSheetLayout(density: .regular).previousButtonFrame == nil)
    }

    // MARK: - メニューに置いたとき

    static func makeMenuBar(_ harness: ShellControllerHarness, front: AppReference?, opened: @escaping (SettingsTab) -> Void = { _ in }) -> MenuBarController {
        let menuBar = MenuBarController(
            controller: harness.controller,
            license: harness.license,
            onOpenSettings: opened,
            onOpenOnboarding: {},
            onCheckForUpdates: nil
        )
        menuBar.frontmostApp = { front }
        return menuBar
    }

    /// Xcode のプロファイルを2ページにする（グローバルのページもつながる）
    static func twoPageHarness() throws -> (ShellControllerHarness, UUID) {
        let harness = ShellControllerHarness(installed: [ShellFixtures.xcode])
        harness.controller.start()
        let id = try #require(harness.controller.configuration.appProfile(forBundleID: ShellFixtures.xcode)?.id)
        harness.controller.update { configuration in
            while (configuration.profile(id: id)?.pages.count ?? 3) < 2 {
                _ = configuration.addPage(profileID: id)
            }
        }
        return (harness, id)
    }

    @Test("マスを押すと、メニューを閉じてから設定でそのプロファイルのページとマスを開く。‹ › はページを変えるだけ")
    func pressingCellsOpensSettings() throws {
        let (harness, xcodeID) = try Self.twoPageHarness()
        var shown: [MenuBarCellLocation] = []
        var opened: [SettingsTab] = []
        let xcode = AppReference(bundleID: ShellFixtures.xcode, name: "Xcode")
        let menuBar = Self.makeMenuBar(harness, front: xcode, opened: { opened.append($0) })
        defer { NSStatusBar.system.removeStatusItem(menuBar.statusItem) }
        menuBar.onShowCell = { shown.append(MenuBarCellLocation(profileID: $0, address: $1)) }
        let menu = menuBar.menu
        menu.delegate?.menuNeedsUpdate?(menu)

        // 状態の行と区切りのすぐ下
        let item = try #require(menuBar.cheatSheetItem)
        #expect(menu.index(of: item) == 2)
        #expect(item.isEnabled)
        let view = try #require(menuBar.cheatSheetView)
        #expect(item.title == view.store.sheet.title)
        #expect(view.frame.width >= MenuBarCheatSheetLayout.preferredWidth)
        #expect(view.autoresizingMask.contains(.width))

        #expect(view.cellButtons[4].accessibilityPerformPress())
        // メニューが閉じるまで（イベントを追う間）は開かない
        #expect(shown.isEmpty)
        Self.drainDefaultRunLoop()
        #expect(shown == [MenuBarCellLocation(profileID: xcodeID, address: CellAddress(page: 0, index: 4))])

        // ‹ は最初のページでは押せない。› で次のページへ（メニューは開いたまま、何も開かない）
        #expect(!view.previousButton.accessibilityPerformPress())
        #expect(view.nextButton.accessibilityPerformPress())
        Self.drainDefaultRunLoop()
        #expect(shown.count == 1)
        #expect(view.store.sheet.pageIndex == 1)
        #expect(item.title == view.store.sheet.title)
        #expect(view.pageIndicator.accessibilityValue() as? String == view.store.sheet.pageDescription)
        #expect(view.previousButton.isAccessibilityEnabled())

        #expect(view.cellButtons[8].accessibilityPerformPress())
        Self.drainDefaultRunLoop()
        #expect(shown.last == MenuBarCellLocation(profileID: xcodeID, address: CellAddress(page: 1, index: 8)))

        // キーボードで早見表の行を選んで Return: 見ているページを開く
        #expect(NSApplication.shared.sendAction(try #require(item.action), to: item.target, from: item))
        #expect(shown.last == MenuBarCellLocation(profileID: xcodeID, address: CellAddress(page: 1, index: 0)))

        // 開き直すと最初のページに戻る（項目とビューは使い回す）
        menu.delegate?.menuNeedsUpdate?(menu)
        #expect(menuBar.cheatSheetItem === item)
        #expect(menuBar.cheatSheetView === view)
        #expect(view.store.sheet.pageIndex == 0)
        #expect(!view.previousButton.isAccessibilityEnabled())

        // 開くものを受け取らなければ、設定の「プロファイル」を開く
        menuBar.onShowCell = nil
        #expect(view.cellButtons[0].accessibilityPerformPress())
        Self.drainDefaultRunLoop()
        #expect(opened == [.profiles])
        #expect(shown.count == 3)
    }

    @Test("最初にメニューを開くときに待たせないよう、起動の後の手すきに早見表を作っておき、開いたらそれを使う")
    func preparedAfterLaunch() throws {
        let harness = ShellControllerHarness(installed: [ShellFixtures.xcode])
        harness.controller.start()
        let menuBar = Self.makeMenuBar(harness, front: AppReference(bundleID: ShellFixtures.xcode, name: "Xcode"))
        defer { NSStatusBar.system.removeStatusItem(menuBar.statusItem) }
        #expect(menuBar.cheatSheetItem == nil)
        Self.drainDefaultRunLoop()
        let item = try #require(menuBar.cheatSheetItem)
        #expect(menuBar.menu.items.isEmpty)
        menuBar.menu.delegate?.menuNeedsUpdate?(menuBar.menu)
        #expect(menuBar.menu.items.contains(item))
    }

    @Test("ポインタ: 離した場所のマスを押す（押したまま滑らせて離したときも）。外で離せば何もしない。乗っているマスを描き分ける")
    func pointerEvents() throws {
        let configuration = SettingsFixtures.configuration()
        let view = MenuBarCheatSheetView(sheet: MenuBarCheatSheet(frontApp: Self.xcode, configuration: configuration), density: .regular, increasedContrast: false)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        var opened: [MenuBarCellLocation] = []
        view.onOpen = { opened.append($0) }

        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type,
                location: view.convert(point, to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ))
        }
        let layout = view.store.layout
        let button = view.cellButtons[2]
        let center = CGPoint(x: layout.cellFrame(2).midX, y: layout.cellFrame(2).midY)
        #expect(view.hitTest(view.convert(center, to: view.superview)) === button)
        // 見出しやすき間のクリックは、描くだけの SwiftUI に渡さない
        let title = CGPoint(x: layout.titleFrame.minX + 4, y: layout.titleFrame.midY)
        #expect(view.hitTest(view.convert(title, to: view.superview)) === view)

        // 押したまま滑らせてきて離した（mouseDown が無い）
        button.mouseUp(with: try event(.leftMouseUp, at: center))
        let profile = try Self.xcodeProfile(configuration)
        #expect(opened == [MenuBarCellLocation(profileID: profile.id, address: CellAddress(page: 0, index: 2))])

        button.mouseDown(with: try event(.leftMouseDown, at: center))
        #expect(view.store.pressed == .cell(2))
        // 外へ出て離せば押さない
        let outside = CGPoint(x: layout.cellFrame(0).midX, y: layout.cellFrame(0).midY)
        button.mouseDragged(with: try event(.leftMouseDragged, at: outside))
        #expect(view.store.pressed == nil)
        button.mouseUp(with: try event(.leftMouseUp, at: outside))
        #expect(opened.count == 1)

        button.mouseEntered(with: try event(.mouseMoved, at: center))
        #expect(view.store.hovered == .cell(2))
        button.mouseExited(with: try event(.mouseMoved, at: outside))
        #expect(view.store.hovered == nil)

        view.store.hovered = .cell(4)
        view.resetPointerState()
        #expect(view.store.hovered == nil)

        // ⌥クリックは、中身のあるマスなら設定で開かずに実行する（空きマスはふつうのクリックと同じく設定で開く）
        var ran: [MenuBarCellLocation] = []
        view.onRun = { ran.append($0) }
        func optionUp(_ index: Int) throws -> NSEvent {
            let point = CGPoint(x: layout.cellFrame(index).midX, y: layout.cellFrame(index).midY)
            return try #require(NSEvent.mouseEvent(
                with: .leftMouseUp, location: view.convert(point, to: nil), modifierFlags: [.option],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
        }
        button.mouseUp(with: try optionUp(2))
        #expect(ran == [MenuBarCellLocation(profileID: profile.id, address: CellAddress(page: 0, index: 2))])
        #expect(opened.count == 1)
        if let empty = (0..<Page.cellCount).first(where: { view.store.sheet.cell(at: $0) == nil }) {
            view.cellButtons[empty].mouseUp(with: try optionUp(empty))
            #expect(ran.count == 1)
            #expect(opened.last == MenuBarCellLocation(profileID: profile.id, address: CellAddress(page: 0, index: empty)))
        }
        // VoiceOver の「前面のアプリで実行」も同じ
        let action = try #require(button.accessibilityCustomActions()?.first)
        #expect(action.handler?() == true)
        #expect(ran.count == 2)
    }

    @Test("⌥だけを押したクリックが実行。ほかの修飾キーと一緒ならふつうのクリック")
    func alternateClick() {
        #expect(MenuBarCheatSheetButton.isAlternateClick([.option]))
        #expect(MenuBarCheatSheetButton.isAlternateClick([.option, .capsLock]))
        #expect(!MenuBarCheatSheetButton.isAlternateClick([]))
        #expect(!MenuBarCheatSheetButton.isAlternateClick([.option, .command]))
        #expect(!MenuBarCheatSheetButton.isAlternateClick([.option, .shift]))
    }

    @Test("VoiceOver: ‹・何ページ目か・›・9マスの順に読み、描くだけの SwiftUI は読まない")
    func accessibilityTree() throws {
        let configuration = SettingsFixtures.configuration()
        let multi = MenuBarCheatSheet(frontApp: Self.xcode, configuration: configuration)
        #expect(multi.pageCount > 1)
        let view = MenuBarCheatSheetView(sheet: multi, density: .regular, increasedContrast: false)
        let children = try #require(view.accessibilityChildren() as? [NSView])
        // マスのボタンは、見ているページのボタンの数（ここでは 9）だけ読む。12 のページのために用意した残りは隠してある
        let shown = Array(view.cellButtons.prefix(Page.cellCount))
        #expect(children == [view.previousButton, view.pageIndicator, view.nextButton] + shown)
        let restAreHidden = view.cellButtons.dropFirst(Page.cellCount).allSatisfy { $0.isHidden }
        #expect(restAreHidden)
        #expect(view.accessibilityLabel() == multi.accessibilityLabel)
        #expect(view.accessibilityRole() == .group)
        for (index, button) in shown.enumerated() {
            #expect(button.accessibilityRole() == .button)
            #expect(button.accessibilityLabel() == multi.accessibilityLabel(ofCell: index))
            // 中身のあるマスには「前面のアプリで実行」の操作がある（⌥クリックと同じ）
            let hasCell = multi.cell(at: index) != nil
            #expect(button.accessibilityHelp() == (hasCell ? MenuBarCheatSheet.cellHint : MenuBarCheatSheet.emptyCellHint))
            #expect((button.accessibilityCustomActions() ?? []).map(\.name) == (hasCell ? [MenuBarCheatSheet.runActionName] : []))
        }
        #expect(view.previousButton.accessibilityLabel() == MenuBarCheatSheet.previousPageTitle)
        #expect(view.nextButton.accessibilityLabel() == MenuBarCheatSheet.nextPageTitle)

        // ページが1枚なら ‹ › は無い
        view.update(sheet: MenuBarCheatSheet(frontApp: nil, configuration: configuration), density: .compact, increasedContrast: true)
        let single = try #require(view.accessibilityChildren() as? [NSView])
        #expect(single == Array(view.cellButtons.prefix(Page.cellCount)))
        #expect(view.previousButton.isHidden && view.nextButton.isHidden)
        #expect(view.frame.size == MenuBarCheatSheetLayout(density: .compact).size)
        #expect(view.store.increasedContrast)
    }

    @Test("「このアプリでは使わない」アプリでは、押せない1行だけ")
    func turnedOffRow() throws {
        let harness = ShellControllerHarness(installed: [ShellFixtures.xcode])
        harness.controller.start()
        let xcode = AppReference(bundleID: ShellFixtures.xcode, name: "Xcode")
        harness.controller.update { $0.setAppMode(.off, for: xcode) }
        let menuBar = Self.makeMenuBar(harness, front: xcode)
        defer { NSStatusBar.system.removeStatusItem(menuBar.statusItem) }
        let menu = menuBar.menu
        menu.delegate?.menuNeedsUpdate?(menu)
        let name = try #require(harness.controller.configuration.profiles.first { $0.app?.bundleID == ShellFixtures.xcode }).name
        let row = try #require(menu.items.first { $0.title == L10n.ui("\(name) では Nonet を使いません") })
        #expect(!row.isEnabled)
        #expect(row.view == nil)
        #expect(menu.index(of: row) == 2)
        #expect(!menu.items.contains { $0.view is MenuBarCheatSheetView })
    }

    // MARK: - 設定で開く

    @Test("設定: そのプロファイルのページとマスを選んで開く。もう無いプロファイルならタブだけ")
    func settingsSelectsTheCell() throws {
        _ = NSApplication.shared
        let harness = try SettingsHarness()
        let xcode = try #require(harness.xcodeProfile)
        harness.controller.update { _ = $0.addPage(profileID: xcode.id) }
        let window = ShellEditButtonsTests.makeWindow(harness)
        window.model.selectTab(.general)

        window.selectCell(profileID: xcode.id, address: CellAddress(page: 1, index: 7))
        #expect(window.model.tab == .profiles)
        #expect(window.model.selectedProfile.id == xcode.id)
        #expect(window.model.pageIndex == 1)
        #expect(window.model.selectedIndex == 7)

        let global = harness.controller.configuration.globalProfile
        window.selectCell(profileID: global.id, address: CellAddress(page: 0, index: 1))
        #expect(window.model.selectedProfile.id == global.id)
        #expect(window.model.selectedIndex == 1)

        // 無いページは、プロファイルだけ選ぶ
        window.selectCell(profileID: xcode.id, address: CellAddress(page: 5, index: 3))
        #expect(window.model.selectedProfile.id == xcode.id)
        #expect(window.model.pageIndex == 0)

        window.model.selectTab(.general)
        window.selectCell(profileID: UUID(), address: CellAddress(page: 0, index: 0))
        #expect(window.model.tab == .profiles)
        #expect(window.model.selectedProfile.id == xcode.id)
    }

    /// ボタンの数が 9 でないページも、升目の外周に HUD の円と同じ向きで並べる。12 のページがあれば、どのページも高さは同じ
    @Test func otherButtonCountsAreLaidOutAroundTheGrid() {
        for pageLayout in PageLayout.allCases {
            let layout = MenuBarCheatSheetLayout(density: .regular, pageLayout: pageLayout)
            let cells = (0..<pageLayout.slotCount).map(layout.cellFrame)
            for (index, cell) in cells.enumerated() {
                #expect(cell.width > 0 && layout.gridFrame.contains(cell), "\(pageLayout) \(index)")
                for other in cells[(index + 1)...] {
                    #expect(!cell.intersects(other), "\(pageLayout) \(index)")
                }
            }
            #expect(layout.cellFrame(pageLayout.slotCount) == .zero)
        }
        // 4: 上・右・下・左
        let four = MenuBarCheatSheetLayout(density: .regular, pageLayout: .four)
        #expect(four.cellFrame(0).midY < four.cellFrame(1).midY && four.cellFrame(1).midX > four.cellFrame(3).midX)
        let nine = MenuBarCheatSheetLayout(density: .regular, pageLayout: .nine, gridSide: 4)
        let twelve = MenuBarCheatSheetLayout(density: .regular, pageLayout: .twelve)
        #expect(nine.height == twelve.height)
        #expect(MenuBarCheatSheetLayout(density: .regular).height < twelve.height)
    }
}

// 担当: ui-settings
// 設定ウィンドウの状態と操作。設定の変更はすべて NonetController.update を通す（その場で保存・反映される）
import AppKit
import NonetCore
import Observation

/// 画面に一時的に出す知らせ（読み込みの結果・ライセンスの登録など）
struct SettingsMessage: Equatable {
    var text: String
    var isError: Bool
}

/// 書き出し・読み込みのファイルを選ぶ（テストでは偽物にする）
@MainActor
protocol SettingsFileChoosing: AnyObject {
    func chooseExportDestination(suggestedName: String) async -> URL?
    func chooseImportSource() async -> URL?
    /// 一覧に無いアプリを選ぶ
    func chooseApplication() async -> URL?
}

@MainActor
@Observable
final class SettingsModel {
    enum RightPanel: Equatable {
        case inspector
        /// メニューから割り当て
        case menus
    }

    /// 確かめてから行う操作
    enum Confirmation: Identifiable, Equatable {
        case deleteProfile(id: UUID, name: String)
        case removePage(profileID: UUID, index: Int)
        case deactivateLicense
        /// 読み込むと今のプロファイルやグローバルのページが置き換わる
        case importProfiles(SettingsImportPlan)

        var id: String {
            switch self {
            case .deleteProfile(let id, _): "profile-\(id)"
            case .removePage(let id, let index): "page-\(id)-\(index)"
            case .deactivateLicense: "license"
            case .importProfiles(let plan): "import-\(plan.id)"
            }
        }
    }

    /// 「このマスをテスト実行」の結果。record が nil の間は実行中
    struct TestRun: Equatable {
        var cellID: UUID
        var record: ExecutionRecord?
    }

    @ObservationIgnored let controller: NonetController
    @ObservationIgnored let license: LicenseManager
    @ObservationIgnored let services: NonetServices
    let links: AppLinks
    @ObservationIgnored let onCheckForUpdates: (() -> Void)?
    @ObservationIgnored weak var files: (any SettingsFileChoosing)?
    @ObservationIgnored var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// 変えるときは selectTab(_:)（打ちかけの確定とキーの記録の終わりをそこで行う）
    private(set) var tab: SettingsTab = .profiles

    // MARK: プロファイルの選択
    private(set) var selectedProfileID: UUID?
    private(set) var selectedPage = 0
    private(set) var selectedIndex: Int? = 0
    var rightPanel: RightPanel = .inspector
    var isAddingProfile = false
    var confirmation: Confirmation?
    private(set) var lastTestRun: TestRun?
    /// グリッドの下に出す短い知らせ（「空いているマスがありません」など）
    var gridMessage: String?
    /// 書き出し・読み込みの結果
    var fileMessage: SettingsMessage?

    // MARK: キーの記録
    private(set) var recorder = SettingsKeyRecorder()
    private(set) var recordingCellID: UUID?
    @ObservationIgnored private let keyMonitor = SettingsKeyEventMonitor()

    // MARK: 一般
    private(set) var loginItemEnabled = false
    var loginItemError: String?

    // MARK: ライセンス
    var licenseKeyInput = ""
    var licenseMessage: SettingsMessage?

    // MARK: 読み込みに時間のかかる一覧
    let menuBrowser: SettingsMenuBrowser
    let shortcutList: SettingsShortcutList
    private(set) var installedApps: [AppReference] = []
    @ObservationIgnored private var installedAppsLoaded = false
    /// 種類を切り替える前の中身（マスの id ごと）。戻したときに失わないように
    @ObservationIgnored private var rememberedActions: [UUID: [ActionKind: Action]] = [:]
    @ObservationIgnored private var testTask: Task<Void, Never>?
    /// 確定を待っている入力欄（種類やタブを変える前に確定させる）
    @ObservationIgnored let pendingEdits = SettingsPendingEdits()

    init(controller: NonetController, license: LicenseManager, services: NonetServices, links: AppLinks, onCheckForUpdates: (() -> Void)?) {
        self.controller = controller
        self.license = license
        self.services = services
        self.links = links
        self.onCheckForUpdates = onCheckForUpdates
        menuBrowser = SettingsMenuBrowser(menus: services.menus)
        shortcutList = SettingsShortcutList(shortcuts: services.shortcuts)
        loginItemEnabled = services.loginItem.isEnabled
    }

    // MARK: - 見ているもの

    var configuration: NonetConfiguration { controller.configuration }
    var settings: GlobalSettings { configuration.settings }
    var appProfiles: [Profile] { configuration.profiles.filter { !$0.isGlobal } }

    /// 選んでいるプロファイル。消えていればグローバル
    var selectedProfile: Profile {
        selectedProfileID.flatMap(configuration.profile(id:)) ?? configuration.globalProfile
    }

    var pageIndex: Int {
        min(max(selectedPage, 0), max(selectedProfile.pages.count - 1, 0))
    }

    var currentPage: Page {
        let pages = selectedProfile.pages
        return pages.indices.contains(pageIndex) ? pages[pageIndex] : .empty
    }

    var selectedAddress: CellAddress? {
        selectedIndex.map { CellAddress(page: pageIndex, index: $0) }
    }

    var selectedCell: Cell? {
        selectedAddress.flatMap { SettingsGrid.cell(at: $0, in: selectedProfile) }
    }

    var canAddPage: Bool { selectedProfile.pages.count < Profile.maxPages }
    var canRemovePage: Bool { selectedProfile.pages.count > 1 }

    // MARK: - タブ

    func selectTab(_ tab: SettingsTab) {
        guard tab != self.tab else { return }
        // 記録中のまま離れると、ほかのタブで打ったキー（ライセンスキーの貼り付けなど）が記録に入ってしまう
        pendingEdits.flushAll()
        finishRecording()
        self.tab = tab
        if tab == .license {
            license.refresh()
        }
    }

    // MARK: - プロファイル

    func selectProfile(_ id: UUID?) {
        let id = id ?? configuration.globalProfile.id
        guard id != selectedProfile.id || selectedProfileID == nil else { return }
        finishRecording()
        selectedProfileID = id
        selectedPage = 0
        selectedIndex = 0
        gridMessage = nil
        if rightPanel == .menus {
            menuBrowser.refreshApps(preferredBundleID: selectedProfile.app?.bundleID)
        }
    }

    func addProfile(for app: AppReference) {
        var added: UUID?
        controller.update { added = $0.addAppProfile(for: app, preset: PresetLibrary.preset(forBundleID: app.bundleID)) }
        isAddingProfile = false
        if let added {
            selectProfile(added)
        }
    }

    func requestDeleteProfile(_ id: UUID) {
        guard let profile = configuration.profile(id: id), !profile.isGlobal else { return }
        confirmation = .deleteProfile(id: id, name: profile.name)
    }

    func deleteProfile(_ id: UUID) {
        let before = appProfiles
        guard let position = before.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedProfile.id == id
        controller.update { $0.removeProfile(id: id) }
        rememberedActions = rememberedActions.filter { cellID, _ in
            configuration.profiles.contains { SettingsGrid.address(ofCell: cellID, in: $0) != nil }
        }
        guard wasSelected else { return }
        let remaining = appProfiles
        let next = remaining.isEmpty ? nil : remaining[min(position, remaining.count - 1)]
        selectedProfileID = nil
        selectProfile(next?.id)
    }

    func setProfileEnabled(_ id: UUID, _ enabled: Bool) {
        controller.update { $0.updateProfile(id: id) { $0.isEnabled = enabled } }
    }

    func moveProfiles(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        controller.update { $0.moveAppProfiles(fromOffsets: offsets, toOffset: destination) }
    }

    // MARK: - ページ

    func selectPage(_ index: Int) {
        guard selectedProfile.pages.indices.contains(index), index != pageIndex else { return }
        finishRecording()
        selectedPage = index
        gridMessage = nil
    }

    func addPage() {
        let profileID = selectedProfile.id
        var added: Int?
        controller.update { added = $0.addPage(profileID: profileID) }
        if let added {
            finishRecording()
            selectedPage = added
            selectedIndex = 0
        }
    }

    /// 空のページはすぐ消す。マスがあれば確かめる
    func requestRemovePage(_ index: Int) {
        let profile = selectedProfile
        guard profile.pages.count > 1, profile.pages.indices.contains(index) else { return }
        if profile.pages[index].cells.allSatisfy({ $0 == nil }) {
            removePage(index, profileID: profile.id)
        } else {
            confirmation = .removePage(profileID: profile.id, index: index)
        }
    }

    func removePage(_ index: Int, profileID: UUID) {
        finishRecording()
        controller.update { $0.removePage(at: index, profileID: profileID) }
        guard profileID == selectedProfile.id else { return }
        if selectedPage > index || selectedPage >= selectedProfile.pages.count {
            selectedPage = max(selectedPage - 1, 0)
        }
    }

    // MARK: - マス

    func selectCell(_ index: Int?) {
        let index = index.map { min(max($0, 0), Page.cellCount - 1) }
        guard index != selectedIndex else { return }
        finishRecording()
        selectedIndex = index
        gridMessage = nil
    }

    func moveSelection(_ direction: SettingsGridDirection) {
        guard let current = selectedIndex else {
            selectCell(0)
            return
        }
        selectCell(SettingsGrid.neighbor(of: current, direction))
    }

    func clearCell(at index: Int) {
        let profileID = selectedProfile.id
        let address = CellAddress(page: pageIndex, index: index)
        guard SettingsGrid.cell(at: address, in: selectedProfile) != nil else { return }
        if recordingCellID == SettingsGrid.cell(at: address, in: selectedProfile)?.id {
            cancelRecording()
        }
        controller.update { $0.setCell(nil, at: address, profileID: profileID) }
    }

    /// 次の空きマスに写す。空きが無ければ知らせる
    func duplicateCell(at index: Int) {
        let profile = selectedProfile
        let address = CellAddress(page: pageIndex, index: index)
        guard var copy = SettingsGrid.cell(at: address, in: profile) else { return }
        guard let target = SettingsGrid.nextEmptyAddress(after: address, in: profile) else {
            gridMessage = String(localized: "空いているマスがありません。マスを空けるか、ページを追加してください", bundle: .module)
            return
        }
        copy.id = UUID()
        controller.update { $0.setCell(copy, at: target, profileID: profile.id) }
        finishRecording()
        selectedPage = target.page
        selectedIndex = target.index
    }

    /// 空きマスに種類を選んでマスを作る
    func createCell(kind: ActionKind, at index: Int) {
        let profileID = selectedProfile.id
        let address = CellAddress(page: pageIndex, index: index)
        guard SettingsGrid.isEmpty(address, in: selectedProfile) else { return }
        // 右クリックで作るときも、記録中のマスから離れるので記録を終える
        finishRecording()
        let cell = SettingsCellEditing.newCell(kind: kind)
        controller.update { $0.setCell(cell, at: address, profileID: profileID) }
        selectedIndex = index
        gridMessage = nil
    }

    /// ドラッグで落とされたもの。受け取れたら true
    @discardableResult
    func handleDrop(_ payload: SettingsDragPayload, onto index: Int) -> Bool {
        let target = CellAddress(page: pageIndex, index: index)
        switch payload {
        case .cell(let profileID, let source) where profileID == selectedProfile.id:
            guard source != target else { return false }
            swapCells(source, target)
            return true
        case .menuItem(let id):
            guard let entry = menuBrowser.entry(id: id) else { return false }
            assignMenuItem(entry.node, to: target)
            return true
        default:
            return false
        }
    }

    /// ページの見出しに落とされたマスを、そのページの最初の空きマスへ移す。受け取れたら true
    @discardableResult
    func handleDrop(_ payload: SettingsDragPayload, ontoPage page: Int) -> Bool {
        let profile = selectedProfile
        guard case .cell(let profileID, let source) = payload, profileID == profile.id, source.page != page,
              profile.pages.indices.contains(page),
              let empty = SettingsGrid.firstEmptyIndex(in: profile.pages[page]) else { return false }
        swapCells(source, CellAddress(page: page, index: empty))
        return true
    }

    func swapCells(_ source: CellAddress, _ destination: CellAddress) {
        let profileID = selectedProfile.id
        controller.update { $0.swapCells(source, destination, profileID: profileID) }
        finishRecording()
        selectedPage = destination.page
        selectedIndex = destination.index
    }

    /// メニュー項目を割り当てる。address が nil なら選んでいる空きマスか、最初の空きマス
    func assignMenuItem(_ item: MenuItemNode, to address: CellAddress? = nil) {
        let profile = selectedProfile
        guard let target = address
            ?? SettingsGrid.assignmentTarget(selected: selectedAddress, currentPage: pageIndex, in: profile) else {
            gridMessage = String(localized: "空いているマスがありません。マスを空けるか、ページを追加してください", bundle: .module)
            return
        }
        let existing = SettingsGrid.cell(at: target, in: profile)
        if let existing, existing.id == recordingCellID {
            cancelRecording()
        }
        let cell = SettingsCellEditing.assigningMenuItem(item, app: menuBrowser.selectedApp?.app, to: existing)
        controller.update { $0.setCell(cell, at: target, profileID: profile.id) }
        selectedPage = target.page
        selectedIndex = target.index
        gridMessage = nil
    }

    // MARK: - インスペクタ

    /// id のマスを書き換える（入れ替えた後でも同じマスに届くよう、場所ではなく id で探す）
    func updateCell(id: UUID, _ transform: (inout Cell) -> Void) {
        for profile in configuration.profiles {
            guard let address = SettingsGrid.address(ofCell: id, in: profile),
                  var cell = SettingsGrid.cell(at: address, in: profile) else { continue }
            let original = cell
            transform(&cell)
            cell.id = original.id
            guard cell != original else { return }
            controller.update { $0.setCell(cell, at: address, profileID: profile.id) }
            return
        }
    }

    func changeKind(ofCell id: UUID, to kind: ActionKind) {
        // 打ちかけを先に確定させ、切り替える前の中身として覚えておく
        pendingEdits.flushAll()
        guard let cell = cell(id: id), cell.action.kind != kind else { return }
        if recordingCellID == id {
            cancelRecording()
        }
        rememberedActions[id, default: [:]][cell.action.kind] = cell.action
        let remembered = rememberedActions[id]?[kind]
        updateCell(id: id) { $0 = SettingsCellEditing.changingKind(of: $0, to: kind, remembered: remembered) }
    }

    /// アクションを差し替える（自動で付いた名前とアイコンは合わせる）
    func replaceAction(ofCell id: UUID, with action: Action) {
        updateCell(id: id) { $0 = SettingsCellEditing.replacingAction(action, in: $0) }
    }

    /// 今の中身を読んで、その一部だけを書き換える。種類が変わっていれば何もしない。
    /// 入力欄の確定は少し遅れて届くので、描画したときの中身を丸ごと書き戻すと、その間に変えた設定や種類を戻してしまう
    func updateAction<Content: SettingsActionContent>(ofCell id: UUID, as type: Content.Type, _ transform: (inout Content) -> Void) {
        updateCell(id: id) { cell in
            if let updated = SettingsCellEditing.updatingContent(of: cell, as: type, transform) {
                cell = updated
            }
        }
    }

    func chooseApp(_ app: AppReference, forCell id: UUID) {
        updateCell(id: id) { $0 = SettingsCellEditing.choosingApp(app, in: $0) }
    }

    func cell(id: UUID) -> Cell? {
        for profile in configuration.profiles {
            if let address = SettingsGrid.address(ofCell: id, in: profile) {
                return SettingsGrid.cell(at: address, in: profile)
            }
        }
        return nil
    }

    private func location(ofCell id: UUID) -> (profile: Profile, cell: Cell)? {
        for profile in configuration.profiles {
            if let address = SettingsGrid.address(ofCell: id, in: profile), let cell = SettingsGrid.cell(at: address, in: profile) {
                return (profile, cell)
            }
        }
        return nil
    }

    // MARK: - テスト実行

    func startTestRun(cellID: UUID) {
        testTask?.cancel()
        testTask = Task { [weak self] in
            await self?.runTest(cellID: cellID)
        }
    }

    func runTest(cellID: UUID) async {
        guard let (profile, cell) = location(ofCell: cellID) else { return }
        lastTestRun = TestRun(cellID: cellID, record: nil)
        let record = await controller.testRun(cell, profileID: profile.id)
        // 結果を待つ間に別のマスを試していたら、古い結果は出さない
        guard lastTestRun?.cellID == cellID else { return }
        lastTestRun = TestRun(cellID: cellID, record: record)
    }

    func testRun(for cellID: UUID) -> TestRun? {
        lastTestRun?.cellID == cellID ? lastTestRun : nil
    }

    // MARK: - キーの記録

    var isRecording: Bool { recorder.isRecording }

    /// 記録欄とそのボタンのある場所。ここの外をクリックしたら記録を終える
    var recorderArea: NSView? {
        get { keyMonitor.recorderArea }
        set { keyMonitor.recorderArea = newValue }
    }

    func beginRecording(cellID: UUID) {
        finishRecording()
        guard cell(id: cellID) != nil else { return }
        recorder.start()
        recordingCellID = cellID
        controller.isRecordingKeys = true
        keyMonitor.start(
            keyDown: { [weak self] keyCode, characters, flags in
                self?.handleKeyDown(keyCode: keyCode, characters: characters, flags: flags)
            },
            flagsChanged: { [weak self] flags in
                self?.handleFlagsChanged(flags)
            },
            click: { [weak self] insideRecorder in
                self?.handleClick(insideRecorder: insideRecorder)
            }
        )
    }

    /// 記録中のクリック。記録欄の外（ほかの欄・ボタン・別のウィンドウ）なら、押したキーを保存して記録を終える。
    /// 続けると、ほかの欄に打つ文字まで記録に入ってしまう
    func handleClick(insideRecorder: Bool) {
        guard !insideRecorder else { return }
        finishRecording()
    }

    func handleKeyDown(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags) {
        apply(recorder.keyDown(keyCode: keyCode, characters: characters, flags: flags))
    }

    func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        recorder.flagsChanged(flags)
    }

    func appendEscapeToRecording() {
        apply(recorder.appendEscape())
    }

    func removeLastRecordedChord() {
        recorder.removeLast()
    }

    /// 記録を終え、押したキーがあれば保存する
    func finishRecording() {
        guard recorder.isRecording else { return }
        apply(recorder.finish())
    }

    /// 何も変えずに記録をやめる
    func cancelRecording() {
        guard recorder.isRecording || recordingCellID != nil else { return }
        recorder.cancel()
        endRecording()
    }

    private func apply(_ outcome: SettingsKeyRecorder.Outcome) {
        switch outcome {
        case .recording:
            break
        case .finished(let keys):
            if let id = recordingCellID {
                updateAction(ofCell: id, as: KeySequence.self) { $0 = keys }
            }
            endRecording()
        case .cancelled:
            endRecording()
        }
    }

    private func endRecording() {
        keyMonitor.stop()
        recordingCellID = nil
        controller.isRecordingKeys = false
    }

    // MARK: - 一般

    func setSetting<Value: Equatable>(_ keyPath: WritableKeyPath<GlobalSettings, Value>, _ value: Value) {
        guard settings[keyPath: keyPath] != value else { return }
        controller.update { $0.settings[keyPath: keyPath] = value }
    }

    var triggerWarning: String? {
        SettingsText.triggerWarning(trigger: settings.trigger, isJISKeyboard: services.isJISKeyboard)
    }

    func refreshLoginItem() {
        loginItemEnabled = services.loginItem.isEnabled
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        do {
            try services.loginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            settingsLog.error("ログイン時に起動を変えられませんでした: \(error.localizedDescription, privacy: .public)")
            let reason = error.localizedDescription
            loginItemError = enabled
                ? String(localized: "ログイン時に起動するように設定できませんでした（\(reason)）", bundle: .module)
                : String(localized: "ログイン時に起動しないように設定できませんでした（\(reason)）", bundle: .module)
        }
        loginItemEnabled = services.loginItem.isEnabled
    }

    // MARK: - 状態の帯

    var statusBanner: SettingsStatusBanner? {
        SettingsStatusBanner(status: controller.status)
    }

    func perform(_ action: SettingsStatusBanner.Action) {
        switch action {
        case .requestAccessibility:
            services.permissions.requestAccessibility()
        case .openAccessibilitySettings:
            services.permissions.openAccessibilitySettings()
        case .recheck:
            break
        case .enable:
            setSetting(\.isEnabled, true)
        }
        controller.refreshPermissions()
    }

    // MARK: - 書き出しと読み込み

    func exportProfiles(_ profiles: [Profile], suggestedName: String) async {
        guard let files, let url = await files.chooseExportDestination(suggestedName: suggestedName) else { return }
        exportProfiles(profiles, to: url)
    }

    func exportProfiles(_ profiles: [Profile], to url: URL) {
        do {
            let data = try ConfigurationStore.exportData(profiles: profiles)
            try data.write(to: url, options: .atomic)
            fileMessage = SettingsMessage(
                text: String(localized: "\(profiles.count)個のプロファイルを「\(url.lastPathComponent)」に書き出しました。", bundle: .module),
                isError: false
            )
        } catch {
            settingsLog.error("プロファイルを書き出せませんでした: \(error.localizedDescription, privacy: .public)")
            fileMessage = SettingsMessage(text: SettingsText.fileError(error, reading: false), isError: true)
        }
    }

    func importProfiles() async {
        guard let files, let url = await files.chooseImportSource() else { return }
        importProfiles(from: url)
    }

    /// ファイルを読み、今のプロファイルやグローバルのページが置き換わるなら先に確かめる（元に戻せないため）
    func importProfiles(from url: URL) {
        let document: ConfigurationStore.ImportedProfiles
        do {
            let data = try Data(contentsOf: url)
            document = try ConfigurationStore.importDocument(from: data)
        } catch {
            settingsLog.error("プロファイルを読み込めませんでした: \(error.localizedDescription, privacy: .public)")
            fileMessage = SettingsMessage(text: SettingsText.fileError(error, reading: true), isError: true)
            return
        }
        let plan = SettingsImportPlan(document: document, configuration: configuration, fileName: url.lastPathComponent)
        if plan.replacesExisting {
            confirmation = .importProfiles(plan)
        } else {
            applyImport(document)
        }
    }

    /// 置き換えるものは読まず、新しいアプリのプロファイルだけ加える
    func importNewProfilesOnly(_ plan: SettingsImportPlan) {
        confirmation = nil
        applyImport(plan.newProfilesOnly(in: configuration))
    }

    private func applyImport(_ document: ConfigurationStore.ImportedProfiles) {
        finishRecording()
        var result = NonetConfiguration.ImportResult()
        controller.update { result = $0.importProfiles(document) }
        fileMessage = SettingsMessage(
            text: SettingsText.importSummary(result, containsScripts: SettingsImportPlan.containsScripts(document.profiles)),
            isError: result.appliedCount == 0
        )
    }

    // MARK: - アプリの一覧

    func loadInstalledAppsIfNeeded() {
        guard !installedAppsLoaded else { return }
        installedApps = services.installedApps.installedApps()
        installedAppsLoaded = true
    }

    /// 一覧を出すたびに読み直す（Nonet は何週間も動き続けるので、後で入れたアプリも出す）。
    /// 実際のサービスは30秒覚えているので、続けて開いても重くない
    func reloadInstalledApps() {
        installedAppsLoaded = false
        loadInstalledAppsIfNeeded()
    }

    // MARK: - メニューから割り当て

    func showMenus(_ show: Bool) {
        if show {
            finishRecording()
            rightPanel = .menus
            menuBrowser.refreshApps(preferredBundleID: selectedProfile.app?.bundleID)
        } else {
            rightPanel = .inspector
        }
    }

    // MARK: - ライセンス

    func activateLicense() {
        let key = licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try license.activate(licenseKey: key)
            licenseKeyInput = ""
            licenseMessage = SettingsMessage(text: String(localized: "登録しました。ご購入ありがとうございます。", bundle: .module), isError: false)
        } catch {
            let text = (error as? LicenseError)?.errorDescription ?? error.localizedDescription
            licenseMessage = SettingsMessage(text: text, isError: true)
        }
    }

    func deactivateLicense() {
        license.deactivate()
        licenseMessage = SettingsMessage(text: String(localized: "登録を解除しました。", bundle: .module), isError: false)
    }

    // MARK: - 確認

    func confirm(_ confirmation: Confirmation) {
        self.confirmation = nil
        switch confirmation {
        case .deleteProfile(let id, _):
            deleteProfile(id)
        case .removePage(let profileID, let index):
            removePage(index, profileID: profileID)
        case .deactivateLicense:
            deactivateLicense()
        case .importProfiles(let plan):
            applyImport(plan.document)
        }
    }

    // MARK: - ウィンドウ

    /// 開き直したときや、ほかのアプリから戻ったとき。閉じるときに止めた読み込みを続け、古くなった一覧を読み直す
    /// （使い回すウィンドウでは onAppear がもう一度呼ばれないため、ここで行う）
    func windowDidBecomeKey() {
        controller.refreshPermissions()
        refreshLoginItem()
        license.refresh()
        // ショートカット.app で作ってから戻ってきたときに、見つからないと言わないように
        shortcutList.markStale()
        if case .shortcut? = selectedCell?.action {
            shortcutList.loadIfNeeded()
        }
        if rightPanel == .menus {
            menuBrowser.resume(preferredBundleID: selectedProfile.app?.bundleID)
        }
    }

    /// ほかのアプリに移ったら記録を終える（記録中はトリガーキーが効かないため）
    func windowDidResignKey() {
        finishRecording()
    }

    func windowWillClose() {
        pendingEdits.flushAll()
        finishRecording()
        cancelRecording()
        menuBrowser.cancel()
        shortcutList.cancel()
        confirmation = nil
        isAddingProfile = false
    }
}

/// ショートカット.app のショートカットの名前（読むのに時間がかかる）
@MainActor
@Observable
final class SettingsShortcutList {
    enum State: Equatable {
        case idle
        case loading
        case loaded([String])
    }

    private(set) var state: State = .idle
    /// 読み込んだ一覧を出したまま、読み直している
    private(set) var isRefreshing = false
    @ObservationIgnored private let shortcuts: any ShortcutsProviding
    @ObservationIgnored private var task: Task<Void, Never>?
    /// 読み込んだ一覧が古いかもしれない（ウィンドウに戻ってきたとき）
    @ObservationIgnored private var isStale = false

    init(shortcuts: any ShortcutsProviding) {
        self.shortcuts = shortcuts
    }

    /// まだ読んでいないか、古くなっていれば読む
    func loadIfNeeded() {
        switch state {
        case .idle:
            reload()
        case .loaded where isStale && !isRefreshing:
            reload()
        case .loaded, .loading:
            break
        }
    }

    func markStale() {
        isStale = true
    }

    /// 読み直す。読み込んだ一覧があれば、読み終わるまでそれを出しておく（見つからないという注意がちらつかないよう）
    func reload() {
        task?.cancel()
        isStale = false
        if case .loaded = state {
            isRefreshing = true
        } else {
            state = .loading
        }
        task = Task { [weak self, shortcuts] in
            let names = await shortcuts.shortcutNames()
            guard !Task.isCancelled, let self else { return }
            var seen = Set<String>()
            self.state = .loaded(names.filter { !$0.isEmpty && seen.insert($0).inserted }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending })
            self.isRefreshing = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if state == .loading {
            state = .idle
        }
        if isRefreshing {
            isRefreshing = false
            isStale = true
        }
    }

    /// 終わるまで待つ（テスト用）
    func waitUntilLoaded() async {
        await task?.value
    }
}

/// 記録中だけ、このアプリに来たキーを横取りする（ほかの欄やメニューのショートカットに渡さない）。
/// クリックは横取りせず、記録欄の外かどうかを知らせる
@MainActor
final class SettingsKeyEventMonitor {
    private var monitor: Any?
    /// 記録欄とそのボタンのある場所（SwiftUI の背景に置いた NSView）
    weak var recorderArea: NSView?

    func start(
        keyDown: @escaping (UInt16, String?, NSEvent.ModifierFlags) -> Void,
        flagsChanged: @escaping (NSEvent.ModifierFlags) -> Void,
        click: @escaping (_ insideRecorder: Bool) -> Void
    ) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            switch event.type {
            case .keyDown:
                // 押しっぱなしで同じキーが何度も入らないように
                if !event.isARepeat {
                    let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers
                    keyDown(event.keyCode, characters, event.modifierFlags)
                }
                return nil
            case .flagsChanged:
                flagsChanged(event.modifierFlags)
                return event
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                click(Self.contains(self?.recorderArea, locationInWindow: event.locationInWindow, of: event.window))
                return event
            default:
                return event
            }
        }
    }

    /// window の locationInWindow が area の中か。area が別のウィンドウにあれば外
    static func contains(_ area: NSView?, locationInWindow: NSPoint, of window: NSWindow?) -> Bool {
        guard let area, let window, area.window === window else { return false }
        return area.bounds.contains(area.convert(locationInWindow, from: nil))
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

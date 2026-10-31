// 担当: ui-settings
// たくさん作り込む人のための操作: プロファイルの複製・プリセットに戻す・マスのコピーと貼り付け・ほかのプロファイルへのコピー・
// 隣のマスとの入れ替え・ページの名前・キーボードでの移動・以前の設定に戻す
import AppKit
import NonetCore
import UniformTypeIdentifiers

/// 「以前の設定に戻す」の一覧の1行
struct SettingsBackupEntry: Equatable, Identifiable {
    var backup: ConfigurationBackup
    /// 控えのアプリのプロファイルの数。読めなければ nil
    var appProfileCount: Int?

    var id: String { backup.id }
}

extension NSPasteboard.PasteboardType {
    /// マスのコピー（Cell の JSON）。設定画面の中だけで使い、文字としては書かない（貼り付けた先の欄に JSON が入らないように）
    static let nonetCell = NSPasteboard.PasteboardType("com.iam74k4.nonet.cell")
}

extension UTType {
    static let nonetCell = UTType(exportedAs: "com.iam74k4.nonet.cell", conformingTo: .data)
}

extension SettingsModel {
    // MARK: - プロファイルの複製

    /// 「複製して別のアプリに使う…」: プロファイルを追加するシートを、このプロファイルを写すために開く
    func beginDuplicatingProfile(_ id: UUID) {
        guard configuration.profile(id: id) != nil else { return }
        finishRecording()
        isAddingProfile = true
        duplicatingProfileID = id
    }

    /// ページを写した、app のプロファイルを作って選ぶ。元に戻せる
    func duplicateProfile(_ sourceID: UUID, for app: AppReference) {
        pendingEdits.flushAll()
        finishRecording()
        closeEditGroup()
        var created: UUID?
        controller.update { created = $0.duplicateProfile(id: sourceID, for: app) }
        guard let created else {
            gridMessage = String(localized: "「\(app.name.isEmpty ? app.bundleID : app.name)」のプロファイルはすでにあります", bundle: .module)
            return
        }
        let actionName = String(localized: "プロファイルの複製", bundle: .module)
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: undoTarget(for: created)) { [weak self] _ in
            self?.deleteProfile(created, actionName: actionName, makesBackup: false)
        }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
        selectProfile(created)
    }

    // MARK: - プリセットに戻す

    /// そのプロファイルのアプリのプリセット。グローバルやプリセットの無いアプリは nil。
    /// この Mac で動かないアクション（AI・Claude Code）は入れない（初回の設定やプロファイルの追加と同じ）
    func preset(forProfile id: UUID) -> AppPreset? {
        guard let app = configuration.profile(id: id)?.app else { return nil }
        return PresetLibrary.preset(forBundleID: app.bundleID, capabilities: resolvedPresetCapabilities ?? services.presetEnvironment.capabilities)
    }

    /// 確かめるシートを出している間に、claude を調べ終えるのを待っておく（調べ終える前は Claude Code のマスが入らないため）
    func requestResetProfile(_ id: UUID) {
        guard let profile = configuration.profile(id: id), preset(forProfile: id) != nil else { return }
        confirmation = .resetProfile(id: id, name: profile.name)
        resolvedPresetCapabilities = nil
        let environment = services.presetEnvironment
        presetCapabilitiesTask?.cancel()
        presetCapabilitiesTask = Task { [weak self] in
            let capabilities = await environment.resolvedCapabilities()
            guard !Task.isCancelled else { return }
            self?.resolvedPresetCapabilities = capabilities
        }
    }

    /// プロファイルのページをプリセットの中身にする。戻す前の設定を控えに残し、元に戻せるようにする
    func resetProfileToPreset(_ id: UUID) {
        guard let preset = preset(forProfile: id) else { return }
        // 次に戻すときは、そのときに調べ直す（AI を使えるようになった・claude を入れたなど）
        presetCapabilitiesTask?.cancel()
        presetCapabilitiesTask = nil
        resolvedPresetCapabilities = nil
        pendingEdits.flushAll()
        finishRecording()
        closeEditGroup()
        backupStore?.makeBackup(of: configuration, reason: .beforeResettingProfile)
        replacePages(ofProfile: id, actionName: String(localized: "プリセットに戻す", bundle: .module)) {
            $0.resetProfile(id: id, to: preset)
        }
    }

    /// プロファイルのページをまとめて変え、変える前のページに戻せるようにする（やり直しも同じ道を通る）
    private func replacePages(ofProfile id: UUID, actionName: String, _ change: (inout NonetConfiguration) -> Void) {
        guard let before = configuration.profile(id: id)?.pages else { return }
        controller.update(change)
        guard let after = configuration.profile(id: id)?.pages, after != before else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: undoTarget(for: id)) { [weak self] _ in
            guard let self else { return }
            self.pendingEdits.flushAll()
            self.finishRecording()
            self.replacePages(ofProfile: id, actionName: actionName) { configuration in
                configuration.updateProfile(id: id) { $0.pages = before }
            }
            self.reveal(CellAddress(page: 0, index: self.selectedIndex ?? 0), profileID: id)
        }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
    }

    // MARK: - マスのコピーと貼り付け

    /// ⌘C。中身のあるマスなら pasteboard に書いて true
    @discardableResult
    func copyCell(at index: Int, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let data = cellData(at: index) else { return false }
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .nonetCell)
    }

    /// onCopyCommand に渡すもの（SwiftUI がペーストボードに書く）
    func cellItemProviders(at index: Int) -> [NSItemProvider] {
        guard let data = cellData(at: index) else { return [] }
        return [NSItemProvider(item: data as NSData, typeIdentifier: UTType.nonetCell.identifier)]
    }

    private func cellData(at index: Int) -> Data? {
        guard let cell = SettingsGrid.cell(at: CellAddress(page: pageIndex, index: index), in: selectedProfile) else { return nil }
        return try? JSONEncoder().encode(cell)
    }

    func canPasteCell(from pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.availableType(from: [.nonetCell]) != nil
    }

    /// ⌘V。コピーしたマスを index に入れる（新しい id で）。中身のあるマスなら置き換え、グリッドの下でも元に戻せるようにする
    func pasteCell(at index: Int, from pasteboard: NSPasteboard = .general) {
        guard let data = pasteboard.data(forType: .nonetCell), var cell = try? JSONDecoder().decode(Cell.self, from: data) else { return }
        cell.id = UUID()
        let profileID = selectedProfile.id
        let address = CellAddress(page: pageIndex, index: index)
        let existing = SettingsGrid.cell(at: address, in: selectedProfile)
        if let existing, existing.id == recordingCellID {
            cancelRecording()
        }
        finishRecording()
        selectCell(index)
        changeCells(
            String(localized: "マスの貼り付け", bundle: .module),
            notice: existing == nil ? nil : String(localized: "マスを貼り付けたもので置き換えました", bundle: .module),
            profileID: profileID,
            at: [address]
        ) {
            $0.setCell(cell, at: address, profileID: profileID)
        }
        gridMessage = nil
    }

    // MARK: - ほかのプロファイルにコピー

    /// コピー先に選べるプロファイル（今のプロファイル以外。グローバルが先頭）
    var copyTargets: [Profile] {
        configuration.profiles.filter { $0.id != selectedProfile.id }
    }

    /// index のマスを、ほかのプロファイルの最初の空きマスへ写す。空きが無ければ知らせる。グリッドの下から元に戻せる
    func copyCell(at index: Int, toProfile targetID: UUID) {
        guard var cell = SettingsGrid.cell(at: CellAddress(page: pageIndex, index: index), in: selectedProfile),
              let target = configuration.profile(id: targetID), targetID != selectedProfile.id else { return }
        guard let address = SettingsGrid.assignmentTarget(selected: nil, currentPage: 0, in: target) else {
            gridMessage = String(localized: "「\(target.name)」に空いているマスがありません。マスを空けるか、ページを追加してください。", bundle: .module)
            return
        }
        cell.id = UUID()
        let pageTitle = SettingsText.pageTitle(index: address.page, name: target.pages[address.page].name)
        changeCells(
            String(localized: "ほかのプロファイルにコピー", bundle: .module),
            notice: String(localized: "「\(target.name)」の\(pageTitle)にコピーしました", bundle: .module),
            profileID: targetID,
            at: [address]
        ) {
            $0.setCell(cell, at: address, profileID: targetID)
        }
        gridMessage = nil
    }

    // MARK: - 隣のマスと入れ替え

    /// その向きに隣のマスがある（端では入れ替えられない）
    func canSwapCell(at index: Int, _ direction: SettingsGridDirection) -> Bool {
        SettingsGrid.neighbor(of: index, direction) != index
    }

    /// 隣のマスと入れ替える（⌥⌘＋矢印キー・右クリック・VoiceOver）。入れ替えた先を選ぶ
    func swapCell(at index: Int, _ direction: SettingsGridDirection) {
        let neighbor = SettingsGrid.neighbor(of: index, direction)
        guard neighbor != index else { return }
        swapCells(CellAddress(page: pageIndex, index: index), CellAddress(page: pageIndex, index: neighbor))
    }

    // MARK: - ページ

    /// ページの名前を変える（空なら名前を外す）。元に戻せる
    func renamePage(_ index: Int, to name: String) {
        let profileID = selectedProfile.id
        guard selectedProfile.pages.indices.contains(index) else { return }
        renamingPage = nil
        let before = selectedProfile.pages[index].name
        let after = Page.normalizedName(name)
        guard before != after else { return }
        setPageName(after, at: index, profileID: profileID)
    }

    private func setPageName(_ name: String?, at index: Int, profileID: UUID) {
        guard let pages = configuration.profile(id: profileID)?.pages, pages.indices.contains(index) else { return }
        let before = pages[index].name
        guard before != name else { return }
        closeEditGroup()
        controller.update { $0.renamePage(at: index, profileID: profileID, to: name) }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: undoTarget(for: profileID)) { [weak self] _ in
            self?.setPageName(before, at: index, profileID: profileID)
            self?.reveal(CellAddress(page: index, index: self?.selectedIndex ?? 0), profileID: profileID)
        }
        undoManager.setActionName(String(localized: "ページの名前の変更", bundle: .module))
        undoManager.endUndoGrouping()
    }

    /// ページの名前の欄を出す（ページの見出しのダブルクリック・右クリック）。そのページも選ぶ
    func beginRenamingPage(_ index: Int) {
        guard selectedProfile.pages.indices.contains(index) else { return }
        selectPage(index)
        renamingPage = index
    }

    /// ⌘1〜⌘3
    func selectPageByShortcut(_ number: Int) {
        selectPage(number - 1)
    }

    // MARK: - キーボード

    /// グリッドで Return: 選んでいるマスの表示名の欄に移る（空きマスなら何もしないで false）
    @discardableResult
    func focusNameField() -> Bool {
        guard selectedCell != nil else { return false }
        if rightPanel != .inspector {
            showMenus(false)
        }
        nameFieldFocusRequest += 1
        return true
    }

    /// ⌘F: 絞り込みの欄を出して移る
    func focusFilter() {
        guard tab == .profiles else { return }
        isFilterRequested = true
        filterFocusRequest += 1
    }

    /// アプリのプロファイルがこれ以上あると、絞り込みの欄をいつも出す
    static let filterThreshold = 8

    var showsProfileFilter: Bool {
        appProfiles.count >= Self.filterThreshold || isFilterRequested || !profileQuery.isEmpty
    }

    /// 絞り込みを終える（Esc・×）
    func clearFilter() {
        profileQuery = ""
        isFilterRequested = false
    }

    var searchResults: SettingsSearchResults {
        SettingsProfileSearch.results(for: profileQuery, in: configuration)
    }

    /// 絞り込みの結果のマスを選ぶ
    func reveal(_ match: SettingsCellMatch) {
        selectProfile(match.profileID)
        selectPage(match.address.page)
        selectCell(match.address.index)
    }

    // MARK: - 以前の設定に戻す

    /// 「以前の設定に戻す…」の一覧を開く
    func showBackups() {
        pendingEdits.flushAll()
        finishRecording()
        reloadBackups()
        isShowingBackups = true
    }

    func reloadBackups() {
        guard let store = backupStore else {
            backupEntries = []
            return
        }
        backupEntries = store.backups().map { backup in
            let configuration = try? store.loadBackup(backup)
            return SettingsBackupEntry(backup: backup, appProfileCount: configuration.map { $0.profiles.filter { !$0.isGlobal }.count })
        }
    }


    /// 控えの設定に戻す。今の設定は控えに残すので、戻したことも同じ一覧から戻せる。マスの取り消しは場所が合わなくなるので忘れる
    func restoreBackup(_ backup: ConfigurationBackup) {
        guard let store = backupStore else { return }
        let restored: NonetConfiguration
        do {
            restored = try store.loadBackup(backup)
        } catch {
            settingsLog.error("控えを読めませんでした: \(error.localizedDescription, privacy: .public)")
            fileMessage = SettingsMessage(text: SettingsText.fileError(error, reading: true), isError: true)
            return
        }
        pendingEdits.flushAll()
        finishRecording()
        editGroup = nil
        store.makeBackup(of: configuration, reason: .beforeRestoring)
        controller.replaceConfiguration(restored)
        undoManager.removeAllActions()
        isShowingBackups = false
        undoNotice = nil
        resetSelection()
        fileMessage = SettingsMessage(
            text: String(localized: "\(SettingsText.backupDate(backup.date))の設定に戻しました。戻す前の設定も「以前の設定に戻す」に残しています。", bundle: .module),
            isError: false
        )
    }
}

// 担当: ui-settings
// 共通マス（すべてのアプリの同じ位置に出るマス）の編集。サイドバーの「共通マス」の行は、共通マスを1ページにしたプロファイル
// （id は SharedCells.profileID）として、ほかのプロファイルと同じグリッド・インスペクタ・元に戻すで編集する。
// ほかのプロファイルのグリッドでは、共通マスのある位置にそのマスを薄く出し、その場では編集しない（プロファイルのマスは残る）
import Foundation
import NonetCore

extension SettingsModel {
    // MARK: - 見ているもの

    /// サイドバーの「共通マス」の行を選んでいる
    var isSharedCellsSelected: Bool { selectedProfileID == SharedCells.profileID }

    /// 共通マスを1ページにしたプロファイル（設定には無い。グリッドとインスペクタで編集するための形）
    var sharedCellsProfile: Profile {
        Profile(id: SharedCells.profileID, kind: .global, pages: [configuration.sharedCells.page])
    }

    /// 設定のプロファイルか、共通マスの行のプロファイル
    func editableProfile(id: UUID) -> Profile? {
        id == SharedCells.profileID ? sharedCellsProfile : configuration.profile(id: id)
    }

    /// マスを id で探すときの範囲（設定のプロファイルと共通マス）
    var editableProfiles: [Profile] {
        configuration.profiles + [sharedCellsProfile]
    }

    /// 選んでいるプロファイルのグリッドで、index の位置に代わりに出ている共通マス。共通マスの行を選んでいるときは nil
    func sharedCell(at index: Int) -> Cell? {
        guard !isSharedCellsSelected else { return nil }
        return configuration.sharedCells[index]
    }

    /// 選んでいるプロファイルのその場所に、共通マスが代わりに出ている（その場所はプロファイルのマスとして編集しない）
    func isCoveredByShared(_ address: CellAddress) -> Bool {
        sharedCell(at: address.index) != nil
    }

    /// 選んでいるプロファイルの、グリッドに出ている形（共通マスを重ねたもの）。空きマスを探すときはこちらを使う（共通マスの位置には置かない）
    var displayedProfile: Profile {
        isSharedCellsSelected ? selectedProfile : displayed(selectedProfile)
    }

    /// プロファイルのページに共通マスを重ねたもの
    func displayed(_ profile: Profile) -> Profile {
        var profile = profile
        for page in profile.pages.indices {
            profile.pages[page].cells = configuration.sharedCells.overlaying(profile.pages[page].cells)
        }
        return profile
    }

    // MARK: - 操作

    /// 「共通マスを編集」: 共通マスの行に移り、その位置を選ぶ
    func editSharedCell(at index: Int) {
        if tab != .profiles {
            selectTab(.profiles)
        }
        selectProfile(SharedCells.profileID)
        selectCell(index)
    }

    /// 「共通マスにする」を出せるか（共通マスの行ではなく、中身のあるプロファイルのマス）
    func canMakeShared(at index: Int) -> Bool {
        let address = CellAddress(page: pageIndex, index: index)
        return !isSharedCellsSelected && !isCoveredByShared(address) && SettingsGrid.cell(at: address, in: selectedProfile) != nil
    }

    /// 「共通マスにする」: 選んでいるプロファイルのマスを、同じ位置の共通マスに写す。その位置にもう共通マスがあれば確かめる
    func requestMakeShared(at index: Int) {
        let address = CellAddress(page: pageIndex, index: index)
        let profile = selectedProfile
        guard !isSharedCellsSelected, SettingsGrid.cell(at: address, in: profile) != nil else { return }
        if configuration.sharedCells[index] != nil {
            confirmation = .replaceSharedCell(profileID: profile.id, address: address)
        } else {
            makeShared(at: address, profileID: profile.id)
        }
    }

    /// プロファイルのマスを、同じ位置の共通マスに写す（新しい id で）。プロファイルのマスは消さない（共通マスをやめると戻る）。元に戻せる
    func makeShared(at address: CellAddress, profileID: UUID) {
        guard profileID != SharedCells.profileID,
              let profile = configuration.profile(id: profileID),
              var cell = SettingsGrid.cell(at: address, in: profile) else { return }
        pendingEdits.flushAll()
        finishRecording()
        cell.id = UUID()
        let target = CellAddress(page: 0, index: address.index)
        changeCells(
            Self.makeSharedActionName,
            notice: String(localized: "共通マスにしました。すべてのアプリの同じ位置に出ます。", bundle: .module),
            profileID: SharedCells.profileID,
            at: [target]
        ) {
            $0.setSharedCell(cell, at: address.index)
        }
        gridMessage = nil
    }

    /// 「共通マスをやめる」: その位置の共通マスを外す。各プロファイルのその位置のマスがまた出る。元に戻せる
    func stopSharing(at index: Int) {
        guard let shared = configuration.sharedCells[index] else { return }
        if recordingCellID == shared.id {
            cancelRecording()
        }
        pendingEdits.flushAll()
        finishRecording()
        changeCells(
            Self.stopSharingActionName,
            notice: String(localized: "共通マスをやめました。各アプリのマスに戻ります。", bundle: .module),
            profileID: SharedCells.profileID,
            at: [CellAddress(page: 0, index: index)]
        ) {
            $0.setSharedCell(nil, at: index)
        }
        gridMessage = nil
    }

    /// すべての書き出し（共通マスも入れる）
    func exportAllProfiles(suggestedName: String) async {
        await exportProfiles(configuration.profiles, sharedCells: configuration.sharedCells, suggestedName: suggestedName)
    }

    static var makeSharedActionName: String {
        String(localized: "共通マスにする", bundle: .module)
    }

    static var stopSharingActionName: String {
        String(localized: "共通マスをやめる", bundle: .module)
    }
}

extension SettingsText {
    /// サイドバーの行と見出しの名前
    static var sharedCellsName: String {
        String(localized: "共通マス", bundle: .module)
    }

    /// 共通マスの行の見出しの下の説明
    static var sharedCellsDescription: String {
        String(localized: "ここに置いたマスは、すべてのアプリのすべてのページの同じ位置に出ます", bundle: .module)
    }

    /// ほかのプロファイルで共通マスの位置を選んだときの説明
    static var sharedCellNote: String {
        String(localized: "このマスは共通マスです。共通マスで変えると、すべてのアプリで変わります。", bundle: .module)
    }

    /// グリッドのマスの小さな印
    static var sharedBadge: String {
        String(localized: "settings.grid.sharedBadge", defaultValue: "共通", bundle: .module)
    }

    /// 共通マスの位置のマスの VoiceOver の値（HUD でも使う）
    static var sharedCellAccessibilityValue: String {
        String(localized: "sharedButton.accessibilityValue", defaultValue: "共通マス", bundle: .module)
    }

    /// 見出しなどに出すプロファイルの名前。共通マスの行は「共通マス」
    static func profileName(_ profile: Profile) -> String {
        profile.id == SharedCells.profileID ? sharedCellsName : profile.name
    }
}

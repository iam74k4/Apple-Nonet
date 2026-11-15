// 担当: ui-settings
// 「プロファイルを整理…」: アプリのプロファイルをまとめて消す（確認は1回、控えは1つ、⌘Z で全部戻る）
import AppKit
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite @MainActor struct SettingsProfileCleanupTests {
    /// Xcode・Safari に、Figma とメモを足した4つのアプリのプロファイル
    private func harness() throws -> SettingsHarness {
        let h = try SettingsHarness()
        h.model.undoManager.groupsByEvent = false
        h.controller.update { configuration in
            configuration.addAppProfile(for: SettingsFixtures.figma, preset: nil)
            configuration.addAppProfile(for: SettingsFixtures.notes, preset: nil)
        }
        return h
    }

    private func ids(_ h: SettingsHarness) -> [UUID] {
        h.model.appProfiles.map(\.id)
    }

    @Test func severalProfilesAreDeletedWithOneBackupAndOneUndo() throws {
        let h = try harness()
        let before = h.model.appProfiles
        #expect(before.count == 4)
        // 2番目と4番目を消す
        let removed: Set<UUID> = [before[1].id, before[3].id]
        h.model.deleteProfiles(removed)
        #expect(ids(h) == [before[0].id, before[2].id])
        #expect(try h.saved()?.profiles.filter { !$0.isGlobal }.map(\.id) == [before[0].id, before[2].id])
        // 控えは1つだけ（控えの数には上限がある）
        #expect(h.store.backups().map(\.reason) == [.beforeDeletingProfile])
        #expect(try h.store.loadBackup(h.store.backups()[0]).profiles.filter { !$0.isGlobal }.count == 4)
        #expect(h.model.undoNotice?.text == L10n.ui("\(2)個のプロファイルを削除しました"))
        #expect(h.model.undoManager.undoActionName == L10n.ui("プロファイルの削除"))

        // 1回の取り消しで、すべて元の位置に戻る
        h.model.undoManager.undo()
        #expect(h.model.appProfiles == before)
        #expect(!h.model.undoManager.canUndo)
        // やり直すと、また消える（控えは増やさない）
        h.model.undoManager.redo()
        #expect(ids(h) == [before[0].id, before[2].id])
        #expect(h.store.backups().count == 1)
        h.model.undoManager.undo()
        #expect(h.model.appProfiles == before)
    }

    @Test func theNoticeUndoesTheWholeBatch() throws {
        let h = try harness()
        let before = h.model.appProfiles
        h.model.deleteProfiles(Set(before.map(\.id)))
        #expect(h.model.appProfiles.isEmpty)
        // 選んでいたプロファイルを消したら、グローバルに移る
        #expect(h.model.selectedProfile.isGlobal)
        h.model.undoFromNotice()
        #expect(h.model.appProfiles == before)
    }

    /// 選んでいたプロファイルを消したら、消したものの最初の位置にあるプロファイルを選ぶ
    @Test func theSelectionMovesToTheNextProfile() throws {
        let h = try harness()
        let before = h.model.appProfiles
        h.model.selectProfile(before[1].id)
        h.model.deleteProfiles([before[1].id, before[2].id])
        #expect(h.model.selectedProfile.id == before[3].id)
    }

    /// 1つだけなら、ふだんの削除と同じ（知らせも同じ）
    @Test func oneProfileIsAnOrdinaryDelete() throws {
        let h = try harness()
        let xcode = try #require(h.xcodeProfile)
        h.model.deleteProfiles([xcode.id])
        #expect(h.xcodeProfile == nil)
        #expect(h.model.undoNotice?.text == L10n.ui("「\(xcode.name)」のプロファイルを削除しました"))
        // グローバルや無い id は消さない
        let count = h.model.appProfiles.count
        h.model.deleteProfiles([h.model.configuration.globalProfile.id, UUID()])
        #expect(h.model.appProfiles.count == count)
        #expect(h.model.configuration.profiles.contains { $0.isGlobal })
    }

    /// 消した後に同じアプリのプロファイルを作っていたら、それだけ戻さずに知らせる
    @Test func profilesThatWereRecreatedStayAsTheyAre() throws {
        let h = try harness()
        let before = h.model.appProfiles
        let figma = try #require(before.first { $0.app?.bundleID == SettingsFixtures.figma.bundleID })
        let notes = try #require(before.first { $0.app?.bundleID == SettingsFixtures.notes.bundleID })
        h.model.deleteProfiles([figma.id, notes.id])
        h.controller.update { $0.addAppProfile(for: SettingsFixtures.figma, preset: nil) }
        h.model.undoManager.undo()
        #expect(h.model.appProfiles.contains { $0.id == notes.id })
        #expect(!h.model.appProfiles.contains { $0.id == figma.id })
        #expect(h.model.gridMessage == L10n.ui("「\(figma.name)」のプロファイルがすでにあるため、元に戻せませんでした"))
    }

    /// 「見つからないアプリを選択」: この Mac のアプリの一覧に無いアプリのプロファイル。一覧が空なら（まだ読んでいない）どれも選ばない
    @Test func missingAppsAreThoseNotInstalled() throws {
        let h = try harness()
        let profiles = h.model.appProfiles
        let installed = [SettingsFixtures.xcode, AppReference(bundleID: "COM.APPLE.SAFARI", name: "Safari")]
        let missing = SettingsProfileCleanupSheet.missingProfileIDs(profiles, installed: installed)
        let missingIDs = Set(profiles.filter { [SettingsFixtures.figma.bundleID, SettingsFixtures.notes.bundleID].contains($0.app?.bundleID) }.map(\.id))
        #expect(missing == missingIDs)
        #expect(SettingsProfileCleanupSheet.missingProfileIDs(profiles, installed: []).isEmpty)
    }
}

/// アイコンの候補の VoiceOver の名前は、記号の名前（"folder.badge.plus"）のままにしない
@Suite struct SettingsIconAccessibilityTests {
    @Test func symbolsHaveReadableNames() {
        for symbol in SettingsIconLibrary.allSymbols {
            let name = SettingsIconLibrary.accessibilityName(symbol)
            #expect(!name.isEmpty)
            #expect(!name.contains("."), "\(symbol) → \(name)")
        }
        #expect(SettingsIconLibrary.accessibilityName("no.such.symbol.xyz") == "no such symbol xyz")
    }
}

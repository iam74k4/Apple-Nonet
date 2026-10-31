// 担当: ui-settings。インスペクタの「すぐのタップでは実行しない（HUD で選んだときだけ）」（Cell.requiresHUD）
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite @MainActor struct SettingsHUDOnlyTests {
    private func harness() throws -> SettingsHarness {
        let h = try SettingsHarness()
        h.model.undoManager.groupsByEvent = false
        return h
    }

    @Test func theCheckboxTurnsTheFlagOnAndOffAndIsSaved() throws {
        let h = try harness()
        let safari = try #require(h.model.selectedProfile.pages[0].cells[0])
        #expect(!safari.requiresHUD)

        h.model.setRequiresHUD(true, ofCell: safari.id)
        #expect(h.model.selectedProfile.pages[0].cells[0]?.requiresHUD == true)
        #expect(try h.saved()?.globalProfile.pages[0].cells[0]?.requiresHUD == true)
        // ほかの中身は変えない
        #expect(h.model.selectedProfile.pages[0].cells[0]?.action == safari.action)
        #expect(h.model.selectedProfile.pages[0].cells[0]?.title == safari.title)

        h.model.setRequiresHUD(false, ofCell: safari.id)
        #expect(try h.saved()?.globalProfile.pages[0].cells[0]?.requiresHUD == false)
    }

    @Test func turningTheFlagOnCanBeUndone() throws {
        let h = try harness()
        let safari = try #require(h.model.selectedProfile.pages[0].cells[0])
        h.model.setRequiresHUD(true, ofCell: safari.id)
        h.model.closeEditGroup()
        #expect(h.model.undoManager.canUndo)
        h.model.undoManager.undo()
        #expect(h.model.selectedProfile.pages[0].cells[0]?.requiresHUD == false)
    }

    /// 種類を切り替えても、アクションを差し替えても印は残る（マスの性質で、アクションの中身ではない）
    @Test func changingTheActionKeepsTheFlag() throws {
        let h = try harness()
        let safari = try #require(h.model.selectedProfile.pages[0].cells[0])
        h.model.setRequiresHUD(true, ofCell: safari.id)
        h.model.changeKind(ofCell: safari.id, to: .openURL)
        #expect(h.model.selectedProfile.pages[0].cells[0]?.action.kind == .openURL)
        #expect(h.model.selectedProfile.pages[0].cells[0]?.requiresHUD == true)
    }

    /// 1文の説明なので「。」で終えない
    @Test func theWording() {
        #expect(SettingsText.hudOnlyTitle == L10n.ui("すぐのタップでは実行しない（HUD で選んだときだけ）"))
        #expect(SettingsText.hudOnlyDetail == L10n.ui("すぐにタップすると HUD が出てこのマスが光り、もう一度タップすると実行します"))
        #expect(!SettingsText.hudOnlyDetail.hasSuffix("。"))
    }

    /// グリッドのマスと HUD のマスは、同じ値を VoiceOver で読む。印の無いマスは何も読まない
    @Test func theBadgeIsReadAsAValue() {
        #expect(HUDOnlyMark.accessibilityValue(requiresHUD: true) == L10n.ui("HUD で選んだときだけ実行"))
        #expect(HUDOnlyMark.accessibilityValue(requiresHUD: false).isEmpty)
    }
}

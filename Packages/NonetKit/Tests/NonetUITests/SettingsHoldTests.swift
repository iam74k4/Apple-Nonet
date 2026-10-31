// 担当: ui-settings。インスペクタの「少し長く止めてから実行」（Cell.requiresHold）
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
        #expect(!safari.requiresHold)

        h.model.setRequiresHold(true, ofCell: safari.id)
        #expect(h.model.selectedProfile.pages[0].cells[0]?.requiresHold == true)
        #expect(try h.saved()?.globalProfile.pages[0].cells[0]?.requiresHold == true)
        // ほかの中身は変えない
        #expect(h.model.selectedProfile.pages[0].cells[0]?.action == safari.action)
        #expect(h.model.selectedProfile.pages[0].cells[0]?.title == safari.title)

        h.model.setRequiresHold(false, ofCell: safari.id)
        #expect(try h.saved()?.globalProfile.pages[0].cells[0]?.requiresHold == false)
    }

    @Test func turningTheFlagOnCanBeUndone() throws {
        let h = try harness()
        let safari = try #require(h.model.selectedProfile.pages[0].cells[0])
        h.model.setRequiresHold(true, ofCell: safari.id)
        h.model.closeEditGroup()
        #expect(h.model.undoManager.canUndo)
        h.model.undoManager.undo()
        #expect(h.model.selectedProfile.pages[0].cells[0]?.requiresHold == false)
    }

    /// 種類を切り替えても、アクションを差し替えても印は残る（マスの性質で、アクションの中身ではない）
    @Test func changingTheActionKeepsTheFlag() throws {
        let h = try harness()
        let safari = try #require(h.model.selectedProfile.pages[0].cells[0])
        h.model.setRequiresHold(true, ofCell: safari.id)
        h.model.changeKind(ofCell: safari.id, to: .openURL)
        #expect(h.model.selectedProfile.pages[0].cells[0]?.action.kind == .openURL)
        #expect(h.model.selectedProfile.pages[0].cells[0]?.requiresHold == true)
    }

    /// 名前は「。」で終えない。説明は2文なので、どちらの文も「。」で終える。トラックパッドに「押す」「長押し」と言わない
    @Test func theWording() {
        #expect(SettingsText.holdTitle == L10n.ui("少し長く止めてから実行"))
        #expect(!SettingsText.holdTitle.hasSuffix("。"))
        #expect(SettingsText.holdDetail == L10n.ui("このマスで指を少し長く止めてから離したときだけ実行します。HUD のマスの縁が一周したら、離すと実行します。"))
        #expect(!L10n.ui("このマスで指を少し長く止めてから離したときだけ実行します。HUD のマスの縁が一周したら、離すと実行します。").contains("長押し"))
    }

    /// グリッドのマスと HUD のマスは、同じ値を VoiceOver で読む。印の無いマスは何も読まない
    @Test func theBadgeIsReadAsAValue() {
        #expect(HoldMark.accessibilityValue(requiresHold: true) == L10n.ui("少し長く止めてから実行"))
        #expect(HoldMark.accessibilityValue(requiresHold: false).isEmpty)
    }
}

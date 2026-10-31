// 担当: ui-shell。少し長く止めてから実行するマス（HUDCell.requiresHold）の印と読み上げ
import CoreGraphics
import NonetCore
@testable import NonetUI
import Testing

@Suite("HUD: HUD で選ぶマスの印")
@MainActor
struct ShellHoldMarkTests {
    static func model(highlighted: Int?) -> HUDModel {
        let cells: [HUDCell?] = [
            HUDCell(title: "ミュート", icon: .symbol("mic.slash"), detail: "⇧⌘A"),
            nil, nil, nil, nil, nil, nil, nil,
            HUDCell(title: "録画", icon: .symbol("record.circle"), detail: "⇧⌘R", requiresHold: true),
        ]
        return HUDModel(title: "Zoom", pageIndex: 0, pageCount: 1, cells: cells, highlightedIndex: highlighted, hint: "⌘を離して実行")
    }

    @Test func theFlagIsOffByDefault() {
        #expect(!HUDCell(title: "t", icon: .symbol("star")).requiresHold)
    }

    /// すぐにタップして HUD が出たとき、なぜ実行しなかったかが分かるように、光ったマスの読み上げに添える
    @Test func theHighlightedHUDOnlyCellSaysItRunsOnlyFromTheHUD() {
        let record = L10n.ui("\("録画")、\("⇧⌘R")、\(L10n.ui("右下"))")
        #expect(HUDAnnouncement.highlighted(in: Self.model(highlighted: 8)) == L10n.ui("\(record)、\(L10n.ui("少し長く止めてから実行"))"))
        // 印の無いマスはこれまでどおり
        #expect(HUDAnnouncement.highlighted(in: Self.model(highlighted: 0)) == L10n.ui("\("ミュート")、\("⇧⌘A")、\(L10n.ui("左上"))"))
        let moved = HUDAnnouncement.announcement(from: Self.model(highlighted: 0), to: Self.model(highlighted: 8))
        #expect(moved?.hasSuffix(L10n.ui("少し長く止めてから実行")) == true)
    }

    /// 印を付けても HUD の大きさは変わらない。印は HUD の大きさの設定に合わせる
    @Test func theBadgeDoesNotChangeTheLayout() {
        #expect(HUDLayout.size(for: Self.model(highlighted: 8)) == CGSize(width: 368, height: 214))
        #expect(HUDMetrics(scale: 1.5).badgeSize == HUDMetrics(scale: 1).badgeSize * 1.5)
    }
}

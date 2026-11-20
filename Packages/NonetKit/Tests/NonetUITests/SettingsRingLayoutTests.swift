// 担当: ui-settings
// 設定の編集の輪（SettingsRingLayout）の寸法と、輪の外の行き先（SettingsPageMap.destinations）
import CoreGraphics
import NonetCore
@testable import NonetUI
import Testing

@Suite struct SettingsRingLayoutTests {
    /// 名前の枠（台の下）。台どうし・台と名前・名前どうしが重ならないかを見る
    static func plateRect(_ layout: SettingsRingLayout, _ index: Int) -> CGRect {
        let center = layout.plateCenter(index)
        let r = SettingsRingLayout.selectionRadius
        return CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
    }

    static func labelRect(_ layout: SettingsRingLayout, _ index: Int) -> CGRect? {
        guard layout.labelLines > 0 else { return nil }
        let center = layout.plateCenter(index)
        let width = layout.keyWidth(of: index)
        return CGRect(
            x: center.x - width / 2,
            y: center.y + SettingsRingLayout.plateRadius + SettingsRingLayout.labelGap,
            width: width,
            height: CGFloat(layout.labelLines) * SettingsRingLayout.lineHeight
        )
    }

    /// 設定の窓の中央の列: 最小の窓（860×560）・開いたとき（1120×720）・大きな窓
    static let sizes = [
        CGSize(width: 292, height: 340), CGSize(width: 552, height: SettingsRingLayout.maxHeight),
        CGSize(width: 640, height: SettingsRingLayout.maxHeight), CGSize(width: 420, height: 300), CGSize(width: 292, height: SettingsRingLayout.minHeight),
    ]

    /// 円（中心と半径）と四角が重なる（四角の中で円の中心にいちばん近い点が、半径より近い）
    static func circle(_ center: CGPoint, _ radius: CGFloat, overlaps rect: CGRect) -> Bool {
        let x = min(max(center.x, rect.minX), rect.maxX)
        let y = min(max(center.y, rect.minY), rect.maxY)
        return hypot(center.x - x, center.y - y) < radius
    }

    /// 台（選択の輪の円）どうし・台とほかの鍵の名前・名前どうしが重ならない。鍵と行き先は枠の中
    @Test(arguments: sizes)
    func keysDoNotOverlapAndStayInside(size: CGSize) {
        let layout = SettingsRingLayout(size: size)
        let bounds = CGRect(origin: .zero, size: size)
        let r = SettingsRingLayout.selectionRadius
        var overlaps: [String] = []
        for a in 0..<Page.cellCount {
            #expect(bounds.contains(layout.keyFrame(a).insetBy(dx: 0.5, dy: 0.5)), "\(size) マス \(a)")
            for b in 0..<Page.cellCount where b != a {
                if b > a, hypot(layout.plateCenter(a).x - layout.plateCenter(b).x, layout.plateCenter(a).y - layout.plateCenter(b).y) < 2 * r {
                    overlaps.append("台 \(a)・台 \(b)")
                }
                if let label = Self.labelRect(layout, b), Self.circle(layout.plateCenter(a), r, overlaps: label) {
                    overlaps.append("台 \(a)・名前 \(b)")
                }
                if b > a, let la = Self.labelRect(layout, a), let lb = Self.labelRect(layout, b), la.intersects(lb) {
                    overlaps.append("名前 \(a)・名前 \(b)")
                }
            }
        }
        #expect(overlaps.isEmpty, "\(size): \(overlaps)")
        for edge in [PageEdge.up, .down, .left, .right] {
            #expect(bounds.contains(layout.edgePoint(edge)), "\(size) \(edge)")
        }
    }

    /// 開いたときの大きさでは名前を2行、最小の窓では1行。名前を出せないほど小さくても、隣の選択の輪が重ならない半径より小さくしない
    @Test func labelsFollowTheWindowSize() {
        #expect(SettingsRingLayout(size: CGSize(width: 552, height: SettingsRingLayout.maxHeight)).labelLines == 2)
        #expect(SettingsRingLayout(size: CGSize(width: 292, height: 340)).labelLines == 1)
        let tiny = SettingsRingLayout(size: CGSize(width: 200, height: 200))
        #expect(tiny.labelLines == 0)
        #expect(tiny.radius >= SettingsRingLayout.minRadius)
        #expect(2 * tiny.radius * 0.3827 >= 2 * SettingsRingLayout.selectionRadius)
        // 枠の高さは、最小の半径が入る高さから、最大の半径と2行の名前が入る高さまで
        #expect(SettingsRingLayout(size: CGSize(width: 640, height: SettingsRingLayout.maxHeight)).radius == SettingsRingLayout.maxRadius)
        #expect(SettingsRingLayout(size: CGSize(width: 640, height: SettingsRingLayout.minHeight)).radius == SettingsRingLayout.minRadius)
    }

    /// 輪の上と下の行き先: グローバルの真ん中のページは下に下のページ。下のページは上で真ん中の最初のページへ戻る。
    /// アプリのページは上にグローバル、下にグローバルの下のページ。左右は出さない（ページは輪の下の点で切り替える）
    @Test func destinationsMatchTheHUD() throws {
        var global = Profile(kind: .global, pages: [PresetLibrary.makeWindowPlacementPage(), Page(name: "ランチャー"), PresetLibrary.makeUtilityPage()])
        global.pages[1].cells[0] = SettingsFixtures.launch(SettingsFixtures.safari)
        let map = SettingsPageMap(profile: global, global: global)
        #expect(map.centerPages == [0, 1])
        let first = map.destinations(at: 0, globalName: "Global")
        #expect(first[.down] == .page(index: 2, title: L10n.core("ユーティリティ")))
        #expect(first[.up] == nil && first[.left] == nil && first[.right] == nil)
        let below = map.destinations(at: 2, globalName: "Global")
        #expect(below[.up] == .page(index: 0, title: L10n.core("画面に置く")))
        #expect(below[.down] == nil)

        let app = Profile(kind: .app(SettingsFixtures.xcode), pages: [Page(cells: [SettingsFixtures.launch(SettingsFixtures.safari)])])
        let appDestinations = SettingsPageMap(profile: app, global: global).destinations(at: 0, globalName: "Global")
        #expect(appDestinations[.up] == .global(SettingsPageMap.GlobalPage(index: 0, title: L10n.core("画面に置く")), title: "Global"))
        #expect(appDestinations[.down] == .global(SettingsPageMap.GlobalPage(index: 2, title: L10n.core("ユーティリティ")), title: L10n.core("ユーティリティ")))
        #expect(appDestinations[.left] == nil)
    }
}

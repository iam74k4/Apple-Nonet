// 担当: ui-settings
// 設定の編集の輪の寸法。HUD と同じ並び（RadialLayout: 真ん中と、上から時計回りに8つ。左上のマスは左上の鍵）で、
// 鍵の円の半径を使える大きさに合わせて決める。輪の上と下には、そこで止めると開くページの名前を置く（HUD で矢印が出る向き）
import CoreGraphics
import NonetCore

struct SettingsRingLayout: Equatable {
    /// 台の半径（HUD の台 18 より少し大きい。設定ではクリックして選ぶので）
    static let plateRadius: CGFloat = 20
    /// 選んでいるマスの輪・ドロップ先の円の半径（台の外に少し空けて囲む）
    static let selectionRadius: CGFloat = 25
    /// 台と名前の間
    static let labelGap: CGFloat = 3
    /// 名前の1行の高さ
    static let lineHeight: CGFloat = 15
    /// 上と下の行き先（名前の1行）の行の高さ
    static let edgeHeight: CGFloat = 28
    /// 窓の端と左右の鍵の間
    static let edgeMargin: CGFloat = 6
    /// 鍵（台と名前）の幅の上限と下限
    static let maxKeyWidth: CGFloat = 100
    static let minKeyWidth: CGFloat = 2 * selectionRadius
    /// 鍵の円の半径の上限（大きな窓でも鍵が離れすぎない。HUD の鍵の円 108 と台 18 の比に近い）
    static let maxRadius: CGFloat = 132
    /// 鍵の円の半径の下限: 隣の鍵（45° 離れる）の選択の輪が重ならない（selectionRadius / sin 22.5°）
    static let minRadius: CGFloat = (selectionRadius / 0.3827).rounded(.up)
    /// 名前を2行・1行出せる鍵の円の半径。これより小さいと、左右の鍵の名前が斜め下の鍵の台に重なる
    /// （名前の下端 = 台の下 + 間 + 行の高さ が、斜めの鍵の台の上端 0.707R − 25 より上にあること）
    static let twoLineRadius: CGFloat = 118
    static let oneLineRadius: CGFloat = 92

    /// 輪の枠の高さの下限と上限（下限は名前を出さない最小の半径、上限は2行の名前で最大の半径が入る高さ。それより高くしても空くだけ）
    static var minHeight: CGFloat { height(radius: minRadius, lines: 0) }
    static var maxHeight: CGFloat { height(radius: maxRadius, lines: 2) }

    var size: CGSize
    /// 鍵の円の半径
    var radius: CGFloat
    /// 名前の行数（0 ならアイコンだけ。名前はヘルプと VoiceOver で読む）
    var labelLines: Int
    var keyWidth: CGFloat

    init(size: CGSize) {
        self.size = size
        let fit = Self.fit(size: size)
        radius = fit.radius
        labelLines = fit.lines
        keyWidth = Self.keyWidthFor(radius: fit.radius)
    }

    /// 半径と名前の行数で要る、輪の枠の高さ
    static func height(radius: CGFloat, lines: Int) -> CGFloat {
        2 * edgeHeight + selectionRadius + 2 * radius + plateRadius + labelHeight(lines: lines)
    }

    static func labelHeight(lines: Int) -> CGFloat {
        lines == 0 ? 0 : labelGap + CGFloat(lines) * lineHeight
    }

    /// 名前を2行・1行・0行の順に試し、入る半径と行数を返す
    private static func fit(size: CGSize) -> (radius: CGFloat, lines: Int) {
        func radius(lines: Int) -> CGFloat {
            // 縦: 上の行き先・上の鍵の選択の輪の上端から、下の鍵の名前の下端・下の行き先まで
            let vertical = (size.height - 2 * edgeHeight - selectionRadius - plateRadius - labelHeight(lines: lines)) / 2
            // 横: 左右の鍵の台が窓の端の手前に入る（左右の鍵の名前は、入る幅に絞る: keyWidth(of:)）。斜めの鍵の名前も入る
            let half: CGFloat = size.width / 2 - edgeMargin
            var radius: CGFloat = min(vertical, half - selectionRadius, maxRadius)
            for _ in 0..<2 {
                let diagonal: CGFloat = (half - keyWidthFor(radius: radius) / 2) / 0.707
                radius = min(radius, diagonal)
            }
            return max(radius, 0)
        }
        let two = radius(lines: 2)
        if two >= twoLineRadius { return (two, 2) }
        let one = radius(lines: 1)
        if one >= oneLineRadius { return (one, 1) }
        return (max(radius(lines: 0), minRadius), 0)
    }

    /// 鍵の幅: 上の鍵の名前が斜めの鍵の台にかからない（0.707R − 選択の輪 の2倍まで）
    static func keyWidthFor(radius: CGFloat) -> CGFloat {
        min(max(2 * (0.707 * radius - selectionRadius), minKeyWidth), maxKeyWidth)
    }

    /// 名前の高さ（間を含む）
    var labelHeight: CGFloat {
        Self.labelHeight(lines: labelLines)
    }

    /// 輪の中心。上の行き先の下に、上の鍵の選択の輪が入るように置く。全体を縦の真ん中に寄せる
    var center: CGPoint {
        let content = Self.height(radius: radius, lines: labelLines)
        let top = max((size.height - content) / 2, 0)
        return CGPoint(x: size.width / 2, y: top + Self.edgeHeight + Self.selectionRadius + radius)
    }

    /// マスの台の中心
    func plateCenter(_ index: Int) -> CGPoint {
        let position = RadialLayout.position(ofCell: index) ?? (0, 0)
        let unit = radius / CGFloat(RadialLayout.keyRadius)
        return CGPoint(x: center.x + CGFloat(position.x) * unit, y: center.y + CGFloat(position.y) * unit)
    }

    /// マスの鍵の幅。左右の鍵は、窓の端まで入る幅に絞る（選択の輪より狭くはしない）
    func keyWidth(of index: Int) -> CGFloat {
        guard index == 3 || index == 5 else { return keyWidth }
        let room = 2 * (size.width / 2 - Self.edgeMargin - radius)
        return max(min(keyWidth, room), 2 * Self.selectionRadius)
    }

    /// マスの鍵（選択の輪と名前）の枠
    func keyFrame(_ index: Int) -> CGRect {
        let plate = plateCenter(index)
        let width = keyWidth(of: index)
        return CGRect(
            x: plate.x - width / 2,
            y: plate.y - Self.selectionRadius,
            width: width,
            height: 2 * Self.selectionRadius + max(labelHeight - (Self.selectionRadius - Self.plateRadius), 0)
        )
    }

    /// 上と下の行き先を置く位置（その中心）。輪の上と下の行（左右の行き先は置かない。ページは輪の下の点で切り替える）
    func edgePoint(_ edge: PageEdge) -> CGPoint {
        let c = center
        switch edge {
        case .down: return CGPoint(x: c.x, y: c.y + radius + Self.plateRadius + labelHeight + Self.edgeHeight / 2)
        case .up, .left, .right: return CGPoint(x: c.x, y: c.y - radius - Self.selectionRadius - Self.edgeHeight / 2)
        }
    }
}

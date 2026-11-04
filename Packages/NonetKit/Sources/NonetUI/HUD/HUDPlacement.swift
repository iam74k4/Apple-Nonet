// 担当: ui-shell
import AppKit
import NonetCore

/// ディスプレイ1台分の座標。AppKit のグローバル座標（原点は主画面の左下、y は上向き）
struct HUDScreenGeometry: Equatable {
    var frame: CGRect
    /// メニューバーと Dock を除いた範囲
    var visibleFrame: CGRect

    @MainActor
    static func current() -> [HUDScreenGeometry] {
        NSScreen.screens.map { HUDScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }
}

/// HUD・トースト・結果のパネルをどこに出すか。NSScreen に触れない純粋な計算
enum HUDPlacement {
    /// 画面の端から空ける幅
    static let edgeMargin: CGFloat = 8
    /// トーストの下端と、画面の使える範囲の下端との間
    static let toastBottomInset: CGFloat = 80
    /// カーソルのある画面。境界上や画面の外（画面の構成が変わった直後など）なら一番近い画面
    static func screenIndex(containing point: CGPoint, in screens: [HUDScreenGeometry]) -> Int? {
        if let index = screens.firstIndex(where: { contains($0.frame, point) }) {
            return index
        }
        return screens.indices.min { distance(from: point, to: screens[$0].frame) < distance(from: point, to: screens[$1].frame) }
    }

    static func screen(containing point: CGPoint, in screens: [HUDScreenGeometry]) -> HUDScreenGeometry? {
        screenIndex(containing: point, in: screens).map { screens[$0] }
    }

    /// HUD の見た目の枠（影の余白を含まない）。円の中心が開いたときのポインタに来るように置く（枠の上側が円、下に帯の分）。
    /// 画面の使える範囲（端の余白を除く）に収める（収まらなければ寄せ、NonetController がポインタを円の中心へ動かす）
    static func hudFrame(size: CGSize, metrics: HUDMetrics, cursor: CGPoint, screen: HUDScreenGeometry) -> CGRect {
        // AppKit の座標（y は上向き）: 枠の上端は円の中心から outerRadius 上
        let top = cursor.y + metrics.outerRadius
        return frame(size: size, centeredAt: CGPoint(x: cursor.x, y: top - size.height / 2), in: screen)
    }

    /// 大きさが変わるとき: 円（枠の上側）を動かさないよう上端をそろえて下へ伸び縮みさせ、画面の使える範囲に収める
    static func resized(_ frame: CGRect, to size: CGSize, in screen: HUDScreenGeometry) -> CGRect {
        let rect = CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        return integral(clamp(rect, into: screen.visibleFrame.insetBy(dx: edgeMargin, dy: edgeMargin)))
    }

    /// HUD の枠（AppKit の座標）の中の、円を囲む正方形を、ポインタの座標（主画面の左上が原点、y が下向き）にする。
    /// 円は枠の上側（帯はその下）。NonetController はこの正方形の中心からの向きと距離でマスを選ぶ
    static func mapFrame(hudFrame: CGRect, metrics: HUDMetrics, primaryScreen: CGRect) -> CGRect {
        CGRect(x: hudFrame.minX, y: primaryScreen.maxY - hudFrame.maxY, width: metrics.circleSide, height: metrics.circleSide)
    }

    /// 設定の「HUD の大きさ」で画面の使える範囲（端の余白と影の余白を除く）からはみ出すなら、収まるところまで倍率を下げる
    static func fitted(_ model: HUDModel, in screen: HUDScreenGeometry) -> HUDModel {
        var result = model
        result.scale = fittedScale(for: model, in: screen)
        return result
    }

    static func fittedScale(for model: HUDModel, in screen: HUDScreenGeometry) -> Double {
        let requested = HUDMetrics(scale: model.scale).scale
        var unscaled = model
        unscaled.scale = 1
        let size = HUDLayout.size(for: unscaled)
        let available = screen.visibleFrame.insetBy(dx: edgeMargin + HUDLayout.shadowMargin, dy: edgeMargin + HUDLayout.shadowMargin)
        guard size.width > 0, size.height > 0, available.width > 0, available.height > 0 else { return requested }
        return min(requested, available.width / size.width, available.height / size.height)
    }

    /// center を中心にした枠を、画面の使える範囲（端の余白を除く）に収める
    static func frame(size: CGSize, centeredAt center: CGPoint, in screen: HUDScreenGeometry) -> CGRect {
        let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        return integral(clamp(rect, into: screen.visibleFrame.insetBy(dx: edgeMargin, dy: edgeMargin)))
    }

    /// トーストは画面の下の中央
    static func toastFrame(size: CGSize, screen: HUDScreenGeometry) -> CGRect {
        let visible = screen.visibleFrame
        let rect = CGRect(
            x: visible.midX - size.width / 2,
            y: visible.minY + toastBottomInset,
            width: size.width,
            height: size.height
        )
        return integral(clamp(rect, into: visible.insetBy(dx: edgeMargin, dy: edgeMargin)))
    }

    /// rect を bounds の中に収める。bounds より大きい向きは bounds の中央にそろえる
    static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        var result = rect
        if rect.width > bounds.width {
            result.origin.x = bounds.midX - rect.width / 2
        } else {
            result.origin.x = min(max(rect.minX, bounds.minX), bounds.maxX - rect.width)
        }
        if rect.height > bounds.height {
            result.origin.y = bounds.midY - rect.height / 2
        } else {
            result.origin.y = min(max(rect.minY, bounds.minY), bounds.maxY - rect.height)
        }
        return result
    }

    /// 文字がにじまないように、原点を整数の座標にする
    private static func integral(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width, height: rect.height)
    }

    /// 左と下の辺は含み、右と上の辺は含まない（隣り合う画面で重ならないように）
    private static func contains(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX && point.y >= frame.minY && point.y < frame.maxY
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

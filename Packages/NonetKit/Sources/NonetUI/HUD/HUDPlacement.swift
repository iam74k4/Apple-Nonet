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
    /// ポインタ（矢印）が占める大きさ。先端が左上で、右下へ伸びる。アクセシビリティで少し大きくしたポインタも収まる大きさにする
    static let pointerSize = CGSize(width: 24, height: 32)
    /// HUD とポインタの間
    static let pointerGap: CGFloat = 8
    /// 「画面の下」のとき、HUD の下端と画面の使える範囲の下端との間
    static let bottomInset: CGFloat = 40

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

    /// HUD の見た目の枠（影の余白を含まない）。中央なら使える範囲の中央。
    /// カーソルの近くなら、カーソルのすぐ下（入らなければすぐ上）に、カーソルに重ならないよう置く（横はカーソルを中心に）。
    /// どちらにも入らなければカーソルを中心に置く（重なるポインタは pointerParkingSpot で寄せる）。どれも使える範囲に収める
    static func hudFrame(size: CGSize, position: HUDPosition, cursor: CGPoint, screen: HUDScreenGeometry) -> CGRect {
        switch position {
        case .screenBottom:
            let visible = screen.visibleFrame
            return frame(size: size, centeredAt: CGPoint(x: visible.midX, y: visible.minY + bottomInset + size.height / 2), in: screen)
        case .screenCenter:
            return frame(size: size, centeredAt: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY), in: screen)
        case .nearCursor:
            let bounds = screen.visibleFrame.insetBy(dx: edgeMargin, dy: edgeMargin)
            // AppKit の座標は y が上向き。ポインタは先端（cursor）から下へ pointerSize.height 伸びる
            let belowTop = cursor.y - pointerSize.height - pointerGap
            if belowTop - size.height >= bounds.minY {
                return frame(size: size, centeredAt: CGPoint(x: cursor.x, y: belowTop - size.height / 2), in: screen)
            }
            let aboveBottom = cursor.y + pointerGap
            if aboveBottom + size.height <= bounds.maxY {
                return frame(size: size, centeredAt: CGPoint(x: cursor.x, y: aboveBottom + size.height / 2), in: screen)
            }
            return frame(size: size, centeredAt: cursor, in: screen)
        }
    }

    /// ポインタ（先端が point）の矢印が占める範囲
    static func pointerRect(at point: CGPoint) -> CGRect {
        CGRect(x: point.x, y: point.y - pointerSize.height, width: pointerSize.width, height: pointerSize.height)
    }

    /// 9マスを開いている間、止めたポインタが HUD に重なるなら、HUD のすぐ外の寄せ先（AppKit の座標）。重ならなければ nil。
    /// 9マスは指の位置で選び、ポインタは使わない。HUD の上に残ると、光っているマスと別のマスを指して見えるので、閉じるまで外へ寄せる。
    /// 寄せ先は、下か上の近いほう（ポインタの横の位置はそのまま）。どちらにも入らなければ右か左
    static func pointerParkingSpot(cursor: CGPoint, hudFrame: CGRect, screen: HUDScreenGeometry) -> CGPoint? {
        let keepOut = hudFrame.insetBy(dx: -pointerGap, dy: -pointerGap)
        guard pointerRect(at: cursor).intersects(keepOut) else { return nil }
        let bounds = screen.frame
        let x = min(max(cursor.x, bounds.minX), bounds.maxX - pointerSize.width)
        let below = CGPoint(x: x, y: keepOut.minY)
        let above = CGPoint(x: x, y: keepOut.maxY + pointerSize.height)
        let vertical = [below, above]
            .filter { $0.y - pointerSize.height >= bounds.minY && $0.y <= bounds.maxY }
            .min { abs($0.y - cursor.y) < abs($1.y - cursor.y) }
        if let vertical { return vertical }
        let y = min(max(cursor.y, bounds.minY + pointerSize.height), bounds.maxY)
        let right = CGPoint(x: keepOut.maxX, y: y)
        if right.x + pointerSize.width <= bounds.maxX { return right }
        let left = CGPoint(x: keepOut.minX - pointerSize.width, y: y)
        return left.x >= bounds.minX ? left : nil
    }

    /// AppKit のグローバル座標（主画面の左下が原点、y が上向き）を、ポインタを動かす座標（主画面の左上が原点、y が下向き）にする
    static func quartzPoint(_ point: CGPoint, primaryScreen: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreen.maxY - point.y)
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

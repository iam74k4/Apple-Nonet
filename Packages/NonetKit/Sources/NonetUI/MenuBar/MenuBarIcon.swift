// 担当: ui-shell
import AppKit

/// メニューバーのアイコンの形。モックのロゴ（角の丸い 3×3、中央が塗り）を 18pt に縮めたもの。
/// 座標は左上が原点（y は下向き）
enum MenuBarIconGeometry {
    static let canvas = CGSize(width: 18, height: 18)
    static let inset: CGFloat = 1
    static let cellSize: CGFloat = 4
    static let gap: CGFloat = 2
    static let lineWidth: CGFloat = 1.2
    static let cornerRadius: CGFloat = 1.2
    /// 塗りつぶす中央のマス
    static let centerIndex = 4
    /// 印（右上のマスの代わりに描く）と、まわりに空ける輪
    static let badgeRadius: CGFloat = 3
    static let badgeCutoutRadius: CGFloat = 4

    /// 9つのマス。左上から右へ、上の行から
    static func cellRects() -> [CGRect] {
        (0..<9).map { index in
            let row = CGFloat(index / 3)
            let column = CGFloat(index % 3)
            return CGRect(
                x: inset + column * (cellSize + gap),
                y: inset + row * (cellSize + gap),
                width: cellSize,
                height: cellSize
            )
        }
    }

    static var gridBounds: CGRect {
        cellRects().reduce(CGRect.null) { $0.union($1) }
    }

    /// 右上のマスの中心に重ね、キャンバスからはみ出さない位置
    static var badgeCenter: CGPoint {
        CGPoint(x: canvas.width - badgeRadius, y: badgeRadius)
    }

    static func filledCells(for state: MenuBarIconState) -> Set<Int> {
        switch state {
        case .normal, .attention, .updateAvailable: [centerIndex]
        case .disabled: []
        }
    }

    /// 印の形。アップデートは点、確かめてほしいことは「!」にして、「新しいものがある」と「手を貸してほしい」を見分けられるようにする
    /// （点だけだと、右上のマスが光っているようにも見える）。意味はツールチップ・VoiceOver とメニューの状態の行で伝える
    static func badge(for state: MenuBarIconState) -> MenuBarIconBadge? {
        switch state {
        case .attention: .exclamation
        case .updateAvailable: .dot
        case .normal, .disabled: nil
        }
    }

    static func showsBadge(for state: MenuBarIconState) -> Bool {
        badge(for: state) != nil
    }

    /// 「!」の縦棒。右上のマスを切り抜いた輪の中に収める
    static var exclamationBar: CGRect {
        CGRect(x: badgeCenter.x - 0.85, y: 0, width: 1.7, height: 3.9)
    }

    /// 「!」の点
    static var exclamationDot: CGRect {
        let radius: CGFloat = 0.95
        return CGRect(x: badgeCenter.x - radius, y: 5.6 - radius, width: radius * 2, height: radius * 2)
    }
}

/// メニューバーのアイコンの右上に付ける印
enum MenuBarIconBadge: Equatable {
    /// アップデートがある
    case dot
    /// 確かめてほしいことがある
    case exclamation
}

/// メニューバーのアイコンをコードで描く（テンプレート画像なので、明暗はシステムが合わせる）
@MainActor
enum MenuBarIconRenderer {
    private static var cache: [MenuBarIconState: NSImage] = [:]

    static func image(for state: MenuBarIconState) -> NSImage {
        if let cached = cache[state] { return cached }
        let image = NSImage(size: MenuBarIconGeometry.canvas, flipped: true) { _ in
            draw(state)
            return true
        }
        image.isTemplate = true
        cache[state] = image
        return image
    }

    private static func draw(_ state: MenuBarIconState) {
        let geometry = MenuBarIconGeometry.self
        let filled = geometry.filledCells(for: state)
        // 無効のときの薄さはボタンの appearsDisabled に任せる（ここでも薄くすると二重に薄くなる）
        NSColor.black.set()
        for (index, rect) in geometry.cellRects().enumerated() {
            if filled.contains(index) {
                NSBezierPath(roundedRect: rect, xRadius: geometry.cornerRadius, yRadius: geometry.cornerRadius).fill()
            } else {
                let inner = rect.insetBy(dx: geometry.lineWidth / 2, dy: geometry.lineWidth / 2)
                let radius = max(0, geometry.cornerRadius - geometry.lineWidth / 2)
                let path = NSBezierPath(roundedRect: inner, xRadius: radius, yRadius: radius)
                path.lineWidth = geometry.lineWidth
                path.stroke()
            }
        }
        guard let badge = geometry.badge(for: state), let context = NSGraphicsContext.current else { return }
        let center = geometry.badgeCenter
        context.saveGraphicsState()
        context.compositingOperation = .clear
        circle(center: center, radius: geometry.badgeCutoutRadius).fill()
        context.restoreGraphicsState()
        NSColor.black.set()
        switch badge {
        case .dot:
            circle(center: center, radius: geometry.badgeRadius).fill()
        case .exclamation:
            let bar = geometry.exclamationBar
            NSBezierPath(roundedRect: bar, xRadius: bar.width / 2, yRadius: bar.width / 2).fill()
            NSBezierPath(ovalIn: geometry.exclamationDot).fill()
        }
    }

    private static func circle(center: CGPoint, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

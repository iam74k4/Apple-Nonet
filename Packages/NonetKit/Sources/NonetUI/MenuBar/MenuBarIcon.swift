// 担当: ui-shell
import AppKit

/// メニューバーのアイコンの形。アプリのアイコン（scripts/make-icon.swift）と同じ、輪に並んだ8つの点と真ん中の点
/// （HUD がポインタの周りに9つのアイコンを輪に出すのと同じ形）を 18pt に縮めたもの。
/// 座標は左上が原点（y は下向き）
enum MenuBarIconGeometry {
    static let canvas = CGSize(width: 18, height: 18)
    static var center: CGPoint { CGPoint(x: canvas.width / 2, y: canvas.height / 2) }
    /// 輪の半径と、輪の点の半径（輪の外側がキャンバスの縁から 1pt に収まる）
    static let ringRadius: CGFloat = 6.3
    static let dotRadius: CGFloat = 1.7
    /// 真ん中の点（ポインタのいるところ。少し大きくして、色の無いアイコンでも真ん中と分かるようにする）
    static let centerDotRadius: CGFloat = 2.1
    /// 無効のときの真ん中の輪郭の太さ
    static let lineWidth: CGFloat = 1.2
    /// 印（右上の点の代わりに描く）と、まわりに空ける輪
    static let badgeRadius: CGFloat = 3
    static let badgeCutoutRadius: CGFloat = 4
    /// 印に置き換える輪の点（右上）
    static let badgeSlot = 1

    /// 輪の8つの点の中心。上から時計回り（HUD のアイコンの並びと同じ: 0 が上、1 が右上…）
    static func ringPoints() -> [CGPoint] {
        (0..<8).map { slot in
            let angle = (-90 + 45 * Double(slot)) * .pi / 180
            return CGPoint(x: center.x + ringRadius * cos(angle), y: center.y + ringRadius * sin(angle))
        }
    }

    static func ringDotRects() -> [CGRect] {
        ringPoints().map { rect(center: $0, radius: dotRadius) }
    }

    static var centerDotRect: CGRect {
        rect(center: center, radius: centerDotRadius)
    }

    /// 点をすべて含む枠
    static var markBounds: CGRect {
        (ringDotRects() + [centerDotRect]).reduce(CGRect.null) { $0.union($1) }
    }

    /// 右上の点に重ね、キャンバスからはみ出さない位置
    static var badgeCenter: CGPoint {
        CGPoint(x: canvas.width - badgeRadius, y: badgeRadius)
    }

    /// 真ん中の点を塗るか（無効なら輪郭だけ）
    static func fillsCenter(for state: MenuBarIconState) -> Bool {
        switch state {
        case .normal, .attention, .updateAvailable: true
        case .disabled: false
        }
    }

    /// 印の形。アップデートは大きめの点、確かめてほしいことは「!」にして、「新しいものがある」と「手を貸してほしい」を
    /// 見分けられるようにする。意味はツールチップ・VoiceOver とメニューの状態の行で伝える
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

    /// 「!」の縦棒。右上の点を切り抜いた輪の中に収める
    static var exclamationBar: CGRect {
        CGRect(x: badgeCenter.x - 0.85, y: 0, width: 1.7, height: 3.9)
    }

    /// 「!」の点
    static var exclamationDot: CGRect {
        let radius: CGFloat = 0.95
        return CGRect(x: badgeCenter.x - radius, y: 5.6 - radius, width: radius * 2, height: radius * 2)
    }

    static func rect(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
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
        let badge = geometry.badge(for: state)
        // 無効のときの薄さはボタンの appearsDisabled に任せる（ここでも薄くすると二重に薄くなる）
        NSColor.black.set()
        for (slot, rect) in geometry.ringDotRects().enumerated() where badge == nil || slot != geometry.badgeSlot {
            NSBezierPath(ovalIn: rect).fill()
        }
        if geometry.fillsCenter(for: state) {
            NSBezierPath(ovalIn: geometry.centerDotRect).fill()
        } else {
            let path = NSBezierPath(ovalIn: geometry.centerDotRect.insetBy(dx: geometry.lineWidth / 2, dy: geometry.lineWidth / 2))
            path.lineWidth = geometry.lineWidth
            path.stroke()
        }
        guard let badge, let context = NSGraphicsContext.current else { return }
        let center = geometry.badgeCenter
        context.saveGraphicsState()
        context.compositingOperation = .clear
        NSBezierPath(ovalIn: geometry.rect(center: center, radius: geometry.badgeCutoutRadius)).fill()
        context.restoreGraphicsState()
        NSColor.black.set()
        switch badge {
        case .dot:
            NSBezierPath(ovalIn: geometry.rect(center: center, radius: geometry.badgeRadius)).fill()
        case .exclamation:
            let bar = geometry.exclamationBar
            NSBezierPath(roundedRect: bar, xRadius: bar.width / 2, yRadius: bar.width / 2).fill()
            NSBezierPath(ovalIn: geometry.exclamationDot).fill()
        }
    }
}

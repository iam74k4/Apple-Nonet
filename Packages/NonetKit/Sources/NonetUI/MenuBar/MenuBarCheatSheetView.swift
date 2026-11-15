// 担当: ui-shell
// メニューの先頭の早見表のビュー。描くのは SwiftUI（HUD と設定のマスと同じ部品と色）、押すのと VoiceOver は AppKit の透明なボタン
// （メニューの中でも AppKit のビューにはクリックが確実に届き、押したあとにメニューを閉じる順番もこちらで決められる）
import AppKit
import NonetCore
import Observation
import SwiftUI

/// 早見表で押せるもの
enum MenuBarCheatSheetControl: Hashable, Sendable {
    case cell(Int)
    case previousPage
    case nextPage
}

/// 早見表に描くもの。メニューを開くたびに sheet を入れ直し、ビューは作り直さない
@MainActor
@Observable
final class MenuBarCheatSheetStore {
    var sheet: MenuBarCheatSheet
    var layout: MenuBarCheatSheetLayout
    /// ポインタの下にあるもの
    var hovered: MenuBarCheatSheetControl?
    /// 押している最中のもの
    var pressed: MenuBarCheatSheetControl?
    /// システム設定の「コントラストを上げる」（メニューを開くたびに読み直す）
    var increasedContrast = false
    /// キーボードでメニューの項目を移って、早見表の行を選んでいる（Return で見ているページを設定で開く）
    var isKeyboardHighlighted = false

    init(sheet: MenuBarCheatSheet, layout: MenuBarCheatSheetLayout) {
        self.sheet = sheet
        self.layout = layout
    }
}

/// メニューの項目のビュー（NSMenuItem.view）。幅はメニューに合わせて広がる
@MainActor
final class MenuBarCheatSheetView: NSView {
    let store: MenuBarCheatSheetStore
    /// マス（空きマスも）を押した。設定でそのマスを開く
    var onOpen: ((MenuBarCellLocation) -> Void)?
    /// ページを変えた（メニューの項目の名前を合わせる）
    var onPageChange: (() -> Void)?

    private let hosting: NSHostingView<MenuBarCheatSheetContent>
    let cellButtons: [MenuBarCheatSheetButton]
    let previousButton = MenuBarCheatSheetButton(control: .previousPage)
    let nextButton = MenuBarCheatSheetButton(control: .nextPage)
    /// 「3 ページ中 1 ページ目」を VoiceOver に読ませるだけの要素（点は SwiftUI が描く）
    let pageIndicator = NSView()

    init(sheet: MenuBarCheatSheet, density: MenuBarCheatSheetLayout.Density, increasedContrast: Bool) {
        let layout = MenuBarCheatSheetLayout(sheet: sheet, density: density)
        store = MenuBarCheatSheetStore(sheet: sheet, layout: layout)
        store.increasedContrast = increasedContrast
        hosting = NSHostingView(rootView: MenuBarCheatSheetContent(store: store))
        cellButtons = (0..<Page.cellCount).map { MenuBarCheatSheetButton(control: .cell($0)) }
        super.init(frame: NSRect(origin: .zero, size: layout.size))
        // メニューがもっと広ければ、それに合わせて広げる（マスも広がる）
        autoresizingMask = [.width]

        // 中身の大きさでビューの大きさを決めさせない（大きさは MenuBarCheatSheetLayout で決める）
        hosting.sizingOptions = []
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.setAccessibilityElement(false)
        addSubview(hosting)

        for button in [previousButton, nextButton] + cellButtons {
            let control = button.control
            button.onPress = { [weak self] in self?.press(control) }
            button.onHoverChange = { [weak self] isInside in self?.setHovered(control, isInside) }
            button.onPressedChange = { [weak self] isPressing in self?.store.pressed = isPressing ? control : nil }
            addSubview(button)
        }
        pageIndicator.setAccessibilityElement(true)
        pageIndicator.setAccessibilityRole(.staticText)
        addSubview(pageIndicator)

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        layoutControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    /// クリックは透明なボタンだけが受ける。描くだけの SwiftUI には渡さない
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        guard let view, view === hosting || view.isDescendant(of: hosting) else { return view }
        return self
    }

    /// ボタンの間（見出し・マスのすき間）のクリックでは何もしない（メニューも閉じない）
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    /// メニューを開くたびに呼ぶ。最初のページ（9マスを開いたときに出るページ）に戻し、ポインタの跡を消す
    func update(sheet: MenuBarCheatSheet, density: MenuBarCheatSheetLayout.Density, increasedContrast: Bool) {
        store.sheet = sheet
        store.hovered = nil
        store.pressed = nil
        store.isKeyboardHighlighted = false
        store.increasedContrast = increasedContrast
        store.layout = MenuBarCheatSheetLayout(sheet: sheet, density: density)
        // 前に開いたメニューの幅を持ち越さない（メニューが広ければ、また広げてもらう）
        setFrameSize(store.layout.size)
    }

    /// メニューが閉じた。開いている間のポインタの跡を消す（閉じるときは mouseExited が来ないことがある）
    func resetPointerState() {
        store.hovered = nil
        store.pressed = nil
        store.isKeyboardHighlighted = false
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutControls()
    }

    /// マス（空きマスも）は設定で開き、‹ › はページを変える（メニューは開いたまま）
    func press(_ control: MenuBarCheatSheetControl) {
        switch control {
        case .cell(let index):
            guard let location = store.sheet.location(ofCell: index) else { return }
            onOpen?(location)
        case .previousPage:
            guard store.sheet.canShowPreviousPage else { return }
            store.sheet.showPreviousPage()
            pageDidChange()
        case .nextPage:
            guard store.sheet.canShowNextPage else { return }
            store.sheet.showNextPage()
            pageDidChange()
        }
    }

    private func pageDidChange() {
        // 端のページで押せなくなったボタンの上の跡を消す
        if store.hovered == .previousPage, !store.sheet.canShowPreviousPage { store.hovered = nil }
        if store.hovered == .nextPage, !store.sheet.canShowNextPage { store.hovered = nil }
        store.pressed = nil
        applyAccessibility()
        onPageChange?()
        NSAccessibility.post(element: pageIndicator, notification: .valueChanged)
        HUDAccessibility.announce(store.sheet.accessibilityLabel)
    }

    private func setHovered(_ control: MenuBarCheatSheetControl, _ isInside: Bool) {
        if isInside {
            store.hovered = control
        } else if store.hovered == control {
            store.hovered = nil
        }
    }

    private func layoutControls() {
        let layout = MenuBarCheatSheetLayout(sheet: store.sheet, width: bounds.width, density: store.layout.density)
        if store.layout != layout {
            store.layout = layout
        }
        for (index, button) in cellButtons.enumerated() {
            button.frame = layout.cellFrame(index)
        }
        previousButton.frame = layout.previousButtonFrame ?? .zero
        nextButton.frame = layout.nextButtonFrame ?? .zero
        pageIndicator.frame = layout.dotsFrame ?? .zero
        for view in [previousButton, nextButton, pageIndicator] {
            view.isHidden = !layout.hasPageControls
        }
        applyAccessibility()
    }

    private func applyAccessibility() {
        let sheet = store.sheet
        setAccessibilityLabel(sheet.accessibilityLabel)
        for (index, button) in cellButtons.enumerated() {
            button.setAccessibilityLabel(sheet.accessibilityLabel(ofCell: index))
            button.setAccessibilityHelp(MenuBarCheatSheet.cellHint)
            // 名前が長くて切れても読めるように
            button.toolTip = sheet.cellTooltip(at: index)
        }
        previousButton.setAccessibilityLabel(MenuBarCheatSheet.previousPageTitle)
        previousButton.isEnabled = sheet.canShowPreviousPage
        nextButton.setAccessibilityLabel(MenuBarCheatSheet.nextPageTitle)
        nextButton.isEnabled = sheet.canShowNextPage
        pageIndicator.setAccessibilityValue(sheet.pageDescription)
    }

    /// 読む順: ‹、何ページ目か、›、9マス（左上から右へ、上の行から）。描くだけの SwiftUI は含めない
    override func accessibilityChildren() -> [Any]? {
        let pageControls: [NSView] = store.layout.hasPageControls ? [previousButton, pageIndicator, nextButton] : []
        return pageControls + cellButtons
    }
}

/// 早見表の透明なボタン。描くのは MenuBarCheatSheetContent（hovered・pressed を見る）
@MainActor
final class MenuBarCheatSheetButton: NSView {
    let control: MenuBarCheatSheetControl
    var onPress: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var onPressedChange: ((Bool) -> Void)?
    var isEnabled = true {
        didSet {
            setAccessibilityEnabled(isEnabled)
            if !isEnabled, isPressing {
                isPressing = false
                onPressedChange?(false)
            }
        }
    }

    private var isPressing = false
    private var trackingArea: NSTrackingArea?

    init(control: MenuBarCheatSheetControl) {
        self.control = control
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if isEnabled {
            onHoverChange?(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressing = true
        onPressedChange?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = isInside(event)
        if inside != isPressing {
            isPressing = inside
            onPressedChange?(inside)
        }
    }

    /// メニューのアイコンを押したまま滑らせて離したとき（mouseDown が来ない）も、離した場所のボタンを押したことにする
    override func mouseUp(with event: NSEvent) {
        if isPressing {
            isPressing = false
            onPressedChange?(false)
        }
        guard isEnabled, isInside(event) else { return }
        onPress?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onPress?()
        return true
    }

    private func isInside(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }
}

// MARK: - 描画

/// 早見表の色。設定のグリッドと同じ明るさ（ライト・ダーク・ハイコントラスト。SettingsPalette）を、メニューの外観で選ぶ
enum MenuBarCheatSheetPalette {
    struct Colors {
        var cellBackground: Color
        var cellBorder: Color
        var emptyBorder: Color

        init(increasedContrast: Bool) {
            cellBackground = MenuBarCheatSheetPalette.color(SettingsPalette.cellBackgroundShades, increasedContrast: increasedContrast)
            cellBorder = MenuBarCheatSheetPalette.color(SettingsPalette.cellBorderShades, increasedContrast: increasedContrast)
            emptyBorder = MenuBarCheatSheetPalette.color(SettingsPalette.emptyBorderShades, increasedContrast: increasedContrast)
        }
    }

    static let standard = Colors(increasedContrast: false)
    static let increased = Colors(increasedContrast: true)

    static func colors(increasedContrast: Bool) -> Colors {
        increasedContrast ? increased : standard
    }

    /// 押せるマスに乗ったときの枠の色（押すと設定で開く）
    static let highlight = Color(nsColor: .controlAccentColor)

    private static func color(_ shades: SettingsPalette.Shades, increasedContrast: Bool) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(white: SettingsPalette.white(shades, for: appearance, increaseContrast: increasedContrast), alpha: 1)
        })
    }
}

/// 早見表の見た目。位置と大きさは MenuBarCheatSheetLayout のとおり（透明なボタンと重ねるため）
struct MenuBarCheatSheetContent: View {
    let store: MenuBarCheatSheetStore
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let layout = store.layout
        let sheet = store.sheet
        let increased = store.increasedContrast || contrast == .increased
        ZStack(alignment: .topLeading) {
            if store.isKeyboardHighlighted {
                let ring = layout.gridFrame.insetBy(dx: -3, dy: -3)
                RoundedRectangle(cornerRadius: MenuBarCheatSheetLayout.cellCornerRadius + 3, style: .continuous)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                    .placed(in: ring)
            }
            Text(sheet.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(increased ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: layout.titleFrame.width, height: layout.titleFrame.height, alignment: .leading)
                .placed(in: layout.titleFrame)
            if layout.hasPageControls {
                pageControls(layout: layout, sheet: sheet, increased: increased)
            }
            ForEach(0..<Page.cellCount, id: \.self) { index in
                MenuBarCheatSheetCell(
                    cell: sheet.cell(at: index),
                    title: sheet.cellTitle(at: index) ?? "",
                    isHovered: store.hovered == .cell(index),
                    isPressed: store.pressed == .cell(index),
                    density: layout.density,
                    increasedContrast: increased
                )
                .placed(in: layout.cellFrame(index))
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        // VoiceOver は透明なボタン（MenuBarCheatSheetButton）で読む
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func pageControls(layout: MenuBarCheatSheetLayout, sheet: MenuBarCheatSheet, increased: Bool) -> some View {
        if let previous = layout.previousButtonFrame, let next = layout.nextButtonFrame, let dots = layout.dotsFrame {
            MenuBarCheatSheetPageButton(
                systemName: "chevron.left",
                isEnabled: sheet.canShowPreviousPage,
                isHovered: store.hovered == .previousPage,
                isPressed: store.pressed == .previousPage,
                increasedContrast: increased
            )
            .placed(in: previous)
            let offsets = layout.dotOffsets
            let size = MenuBarCheatSheetLayout.dotMetrics.dotSize
            ForEach(Array(offsets.enumerated()), id: \.offset) { page, offset in
                Circle()
                    .fill(page == sheet.pageIndex ? Color.primary : Color.secondary.opacity(increased ? 0.8 : 0.45))
                    .placed(in: CGRect(x: dots.minX + offset, y: dots.midY - size / 2, width: size, height: size))
            }
            MenuBarCheatSheetPageButton(
                systemName: "chevron.right",
                isEnabled: sheet.canShowNextPage,
                isHovered: store.hovered == .nextPage,
                isPressed: store.pressed == .nextPage,
                increasedContrast: increased
            )
            .placed(in: next)
        }
    }
}

/// ‹ ›
private struct MenuBarCheatSheetPageButton: View {
    let systemName: String
    let isEnabled: Bool
    let isHovered: Bool
    let isPressed: Bool
    let increasedContrast: Bool

    var body: some View {
        ZStack {
            if isEnabled, isHovered || isPressed {
                Circle().fill(Color.primary.opacity(isPressed ? 0.2 : 0.1))
            }
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(foreground)
        }
    }

    private var foreground: Color {
        guard isEnabled else { return Color.secondary.opacity(increasedContrast ? 0.6 : 0.35) }
        return isHovered || increasedContrast ? Color.primary : Color.secondary
    }
}

/// 早見表の1マス。HUD のマスと同じ並び（角の丸いマスにアイコンと名前、空きマスは点線）を、メニューの外観の色で描く
struct MenuBarCheatSheetCell: View {
    let cell: Cell?
    let title: String
    let isHovered: Bool
    let isPressed: Bool
    let density: MenuBarCheatSheetLayout.Density
    let increasedContrast: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MenuBarCheatSheetLayout.cellCornerRadius, style: .continuous)
        let colors = MenuBarCheatSheetPalette.colors(increasedContrast: increasedContrast)
        let lineWidth: CGFloat = increasedContrast ? 1.5 : 1
        ZStack {
            // ポインタが乗ったマスは、塗らずにアクセント色の枠と鉛筆で示す（押すと実行ではなく、設定で開いて編集する）
            if cell != nil {
                shape.fill(colors.cellBackground)
                shape.strokeBorder(isActive ? MenuBarCheatSheetPalette.highlight : colors.cellBorder, lineWidth: isActive ? 2 : lineWidth)
            } else {
                shape.strokeBorder(
                    isActive ? MenuBarCheatSheetPalette.highlight : colors.emptyBorder,
                    style: StrokeStyle(lineWidth: isActive ? 2 : lineWidth, dash: [4, 3])
                )
            }
            content
            if isActive, cell != nil {
                Image(systemName: "pencil")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(MenuBarCheatSheetPalette.highlight)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .accessibilityHidden(true)
            }
        }
        .opacity(isPressed ? 0.75 : 1)
    }

    /// ポインタが乗っている（押せることを見せる）
    private var isActive: Bool { isHovered || isPressed }

    @ViewBuilder
    private var content: some View {
        if let cell {
            Group {
                switch density {
                case .regular:
                    VStack(spacing: 2) {
                        CellIconView(cell.icon, size: 13)
                        titleText
                    }
                case .compact:
                    HStack(spacing: 4) {
                        CellIconView(cell.icon, size: 11)
                        titleText
                    }
                }
            }
            .padding(.horizontal, 5)
            .foregroundStyle(Color.primary)
        } else if isActive {
            // 空きマスも押せる（設定で開いて、何かを入れる）
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MenuBarCheatSheetPalette.highlight)
        }
    }

    /// 長い名前は縮めずに省く（設定のグリッドと同じ）
    private var titleText: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

private extension View {
    /// ZStack(alignment: .topLeading) の中で、frame の位置と大きさに置く
    func placed(in frame: CGRect) -> some View {
        self.frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
}

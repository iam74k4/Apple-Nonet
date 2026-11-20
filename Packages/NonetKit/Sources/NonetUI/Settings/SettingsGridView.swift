// 担当: ui-settings
// 9マスの編集。HUD と同じ輪の並び（SettingsRingLayout）で、HUD と同じ暗い丸い台に白いアイコン、その下に名前。
// 輪の上と下には、そこで止めると開くページの名前（SettingsPageMap.destinations）を薄く置き、押すとそのページへ移る。
// クリックで選ぶ・ドラッグで入れ替える・Delete で空にする・矢印キーで移る（左上のマスは左上の鍵なので 3×3 と同じ向き）・右クリックで複製など。
// グリッドにいるときのキー: Return で表示名の欄へ、⌘D で複製、⌘⌫ で空にする、⌥⌘＋矢印キーで隣と入れ替え、⌘C・⌘V でコピーと貼り付け
import NonetCore
import SwiftUI

struct SettingsGridView: View {
    let model: SettingsModel
    @FocusState private var isFocused: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let profile = model.selectedProfile
        let page = model.currentPage
        let destinations = model.pageMap.destinations(at: model.pageIndex, globalName: model.configuration.globalProfile.name)
        // 台は HUD と同じ色（グローバルは紺）。設定の窓の上ではぼかすものが無いので、ガラスは敷かない
        let plateStyle = HUDPlateStyle(increasedContrast: contrast == .increased, isGlobalLayer: profile.isGlobal, showsGlass: false)
        GeometryReader { proxy in
            let layout = SettingsRingLayout(size: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(0..<Page.cellCount, id: \.self) { index in
                    let frame = layout.keyFrame(index)
                    SettingsGridCell(
                        model: model,
                        index: index,
                        cell: page.cells.indices.contains(index) ? page.cells[index] : nil,
                        isSelected: model.selectedIndex == index,
                        isGridFocused: isFocused,
                        dragItem: SettingsDragItem(payload: .cell(
                            profileID: profile.id,
                            address: CellAddress(page: model.pageIndex, index: index)
                        )),
                        layout: layout,
                        plateStyle: plateStyle,
                        onSelect: {
                            model.selectCell(index)
                            isFocused = true
                        }
                    )
                    .frame(width: frame.width, height: frame.height, alignment: .top)
                    .position(x: frame.midX, y: frame.midY)
                }
                ForEach([PageEdge.up, .down], id: \.self) { edge in
                    if let destination = destinations[edge] {
                        SettingsRingDestination(model: model, edge: edge, destination: destination)
                            .position(layout.edgePoint(edge))
                    }
                }
            }
        }
        .frame(minHeight: SettingsRingLayout.minHeight, maxHeight: SettingsRingLayout.maxHeight)
        .frame(maxWidth: 640)
        // 輪の背景の箱は置かない（HUD と同じく、台とアイコンだけ）
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            // ⌥⌘＋矢印キーで隣のマスと入れ替える（矢印キーだけなら、下の onMoveCommand で選ぶマスを移る）
            guard Self.isOptionCommand(press.modifiers), let index = model.selectedIndex,
                  let direction = Self.direction(press.key) else { return .ignored }
            model.swapCell(at: index, direction)
            return .handled
        }
        .onKeyPress(keys: [.return, .delete, "d"]) { press in
            guard let index = model.selectedIndex else { return .ignored }
            switch press.key {
            case .return where press.modifiers.isDisjoint(with: [.command, .option, .control, .shift]):
                return model.focusNameField() ? .handled : .ignored
            case .delete where press.modifiers.contains(.command):
                model.clearCell(at: index)
                return .handled
            case "d" where press.modifiers.contains(.command):
                model.duplicateCell(at: index)
                return .handled
            default:
                return .ignored
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .up: model.moveSelection(.up)
            case .down: model.moveSelection(.down)
            case .left: model.moveSelection(.left)
            case .right: model.moveSelection(.right)
            @unknown default: break
            }
        }
        .onDeleteCommand {
            if let index = model.selectedIndex {
                model.clearCell(at: index)
            }
        }
        .onCopyCommand {
            model.selectedIndex.map(model.cellItemProviders(at:)) ?? []
        }
        .onPasteCommand(of: [.nonetCell]) { _ in
            // 中身はペーストボードから同期で読む（受け取った NSItemProvider は非同期でしか読めない）
            if let index = model.selectedIndex {
                model.pasteCell(at: index)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "\(profile.name) のページ \(model.pageIndex + 1)", bundle: .module))
    }

    static func isOptionCommand(_ modifiers: EventModifiers) -> Bool {
        modifiers.contains(.option) && modifiers.contains(.command) && !modifiers.contains(.shift) && !modifiers.contains(.control)
    }

    static func direction(_ key: KeyEquivalent) -> SettingsGridDirection? {
        switch key {
        case .upArrow: .up
        case .downArrow: .down
        case .leftArrow: .left
        case .rightArrow: .right
        default: nil
        }
    }
}

struct SettingsGridCell: View {
    let model: SettingsModel
    let index: Int
    let cell: Cell?
    let isSelected: Bool
    /// キー（Delete・矢印キーなど）がグリッドに届く。選んでいるマスを、リストの選択と同じく、届くならアクセント色・届かなければ灰色で囲む
    var isGridFocused = false
    let dragItem: SettingsDragItem
    var layout = SettingsRingLayout(size: CGSize(width: 600, height: 480))
    var plateStyle = HUDPlateStyle(showsGlass: false)
    let onSelect: () -> Void

    @State private var isDropTarget = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var plateRadius: CGFloat { SettingsRingLayout.plateRadius }
    private var selectionRadius: CGFloat { SettingsRingLayout.selectionRadius }

    var body: some View {
        ZStack(alignment: .top) {
            plate
            if layout.labelLines > 0 {
                label
                    .padding(.top, selectionRadius + plateRadius + SettingsRingLayout.labelGap)
            }
        }
        .frame(width: layout.keyWidth(of: index))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .modifier(SettingsDraggableIfFilled(item: cell == nil ? nil : dragItem, preview: cell, plateStyle: plateStyle))
        .dropDestination(for: SettingsDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            return model.handleDrop(item.payload, onto: index)
        } isTargeted: { isDropTarget = $0 }
        .contextMenu {
            contextMenu
        }
        .help(SettingsGrid.tooltip(for: cell) ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SettingsGrid.accessibilityLabel(index: index, cell: cell))
        .accessibilityValue(HoldMark.accessibilityValue(requiresHold: cell?.requiresHold == true))
        // ⌥⌘＋矢印キーで入れ替えるのは、選んでいるマス（VoiceOver で読んでいるマスではない）
        .accessibilityHint(String(localized: "選んでから ⌥⌘＋矢印キーで、隣のマスと入れ替え", bundle: .module))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .accessibilityActions {
            if let cell {
                Button(String(localized: "複製", bundle: .module)) { model.duplicateCell(at: index) }
                Button(String(localized: "削除", bundle: .module)) { model.clearCell(at: index) }
                Button(String(localized: "このマスをテスト実行", bundle: .module)) { model.startTestRun(cellID: cell.id) }
            }
            ForEach(SettingsGrid.swapDirections, id: \.self) { direction in
                if model.canSwapCell(at: index, direction) {
                    Button(SettingsText.swapName(direction)) { model.swapCell(at: index, direction) }
                }
            }
        }
    }

    /// HUD と同じ台とアイコン。選んでいるマスは台の外を輪で囲み、ドロップ先は円を塗る。空きマスは薄い輪だけ
    private var plate: some View {
        ZStack {
            // 選んでいるマス: 輪の太さだけで見分けさせない（「コントラストを上げる」でも分かるように、薄く塗る）
            Circle().fill(selectionFill).opacity(isSelected ? 1 : 0)
            Circle().strokeBorder(selectionColor, lineWidth: contrast == .increased ? 3 : 2.5).opacity(isSelected ? 1 : 0)
            if let cell {
                HUDPlate(radius: plateRadius, scale: 1, style: plateStyle)
                HUDGlyph(icon: cell.icon, size: index == RadialLayout.centerCell ? 17 : 19)
            } else {
                Circle()
                    .strokeBorder(SettingsPalette.emptyBorder, lineWidth: contrast == .increased ? 1.6 : 1.1)
                    .frame(width: plateRadius * 2, height: plateRadius * 2)
            }
            // ドロップ先: 選んでいるマスより強い塗りと、太いアクセント色の実線
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.24))
                Circle().strokeBorder(Color.accentColor, lineWidth: 3.5)
            }
            .opacity(isDropTarget ? 1 : 0)
        }
        .frame(width: selectionRadius * 2, height: selectionRadius * 2)
        .overlay(alignment: .topTrailing) {
            if cell?.requiresHold == true {
                // 少し長く止めてから実行するマスの印。HUD と同じく、小さな台に白で載せ、台の縁に重ねる
                HoldBadge(size: 8, color: .white)
                    .padding(3)
                    .background(HUDPlate(radius: nil, scale: 1, style: plateStyle))
            }
        }
    }

    /// 名前。長い名前は折り返し、それでも入らなければ少しだけ縮めてから省く（省いた名前はヘルプ SettingsGrid.tooltip で読める）
    @ViewBuilder
    private var label: some View {
        if let cell {
            Text(SettingsGrid.displayTitle(for: cell))
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .lineLimit(layout.labelLines)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
                .frame(width: layout.keyWidth(of: index))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 選んでいるマスの色。キーが届くならアクセント色、届かなければ（サイドバーなどにキーがある）灰色。macOS のリストの選択と同じ決まり
    private var selectionColor: Color {
        isGridFocused ? Color.accentColor : Color.secondary
    }

    private var selectionFill: Color {
        selectionColor.opacity(contrast == .increased ? 0.28 : 0.16)
    }

    /// 右クリックの項目は3つだけ（複製・削除・テスト実行。空きマスではアクションを追加）。コピー・ペースト・隣との入れ替えはキー（⌘C・⌘V・⌥⌘＋矢印）とドラッグで。
    /// キーの印（⌘D など）は付けない。右クリックのメニューの項目に付けると、文字の欄を打っている間のキーまで取られることがあるため
    @ViewBuilder
    private var contextMenu: some View {
        if let cell {
            // 右クリックしたマスを選んでから行う（選択と右側のインスペクタが、操作したマスを指すように）
            Button {
                model.selectCell(index)
                model.duplicateCell(at: index)
            } label: {
                Text("複製", bundle: .module)
            }
            Button(role: .destructive) {
                model.selectCell(index)
                model.clearCell(at: index)
            } label: {
                Text("削除", bundle: .module)
            }
            Divider()
            Button {
                model.selectCell(index)
                model.startTestRun(cellID: cell.id)
            } label: {
                Text("このマスをテスト実行", bundle: .module)
            }
        } else {
            Menu {
                ForEach(SettingsActionKinds.ordered, id: \.self) { kind in
                    Button(SettingsActionKinds.name(kind)) { model.createCell(kind: kind, at: index) }
                }
            } label: {
                Text("アクションを追加", bundle: .module)
            }
        }
    }
}

/// 空きマスはドラッグできない。引いている間は HUD と同じ台とアイコンに名前を添える
private struct SettingsDraggableIfFilled: ViewModifier {
    let item: SettingsDragItem?
    let preview: Cell?
    var plateStyle = HUDPlateStyle(showsGlass: false)

    func body(content: Content) -> some View {
        if let item, let preview {
            content.draggable(item) {
                VStack(spacing: 4) {
                    ZStack {
                        HUDPlate(radius: SettingsRingLayout.plateRadius, scale: 1, style: plateStyle)
                        HUDGlyph(icon: preview.icon, size: 19)
                    }
                    Text(SettingsGrid.displayTitle(for: preview))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .padding(8)
                .frame(width: 120)
            }
        } else {
            content
        }
    }
}

/// 輪の上と下の、そこで止めると開くページ。矢印と名前だけを薄く出し（HUD で止めたときに出る名前と同じ）、押すとそのページへ移る。
/// アプリのプロファイルの上下はグローバルのページで、押すとグローバルのプロファイルで開く
struct SettingsRingDestination: View {
    let model: SettingsModel
    let edge: PageEdge
    let destination: SettingsPageMap.Destination

    var body: some View {
        Button {
            switch destination {
            case .page(let index, _): model.selectPage(index)
            case .global(let page, _): model.showGlobalPage(page.index)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: edge == .down ? "arrow.down" : "arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(String(localized: "\(SettingsText.pageMapRowHelp(edge))「\(title)」", bundle: .module))
        .accessibilityLabel(String(localized: "\(SettingsText.pageMapRowHelp(edge))、\(title)", bundle: .module))
    }

    private var title: String {
        switch destination {
        case .page(_, let title), .global(_, let title): title
        }
    }
}

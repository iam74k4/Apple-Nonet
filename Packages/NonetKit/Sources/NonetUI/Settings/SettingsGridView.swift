// 担当: ui-settings
// 3×3 のグリッド。クリックで選ぶ・ドラッグで入れ替える・Delete で空にする・矢印キーで移る・右クリックで複製など。
// グリッドにいるときのキー: Return で表示名の欄へ、⌘D で複製、⌘⌫ で空にする、⌥⌘＋矢印キーで隣と入れ替え、⌘C・⌘V でコピーと貼り付け
import NonetCore
import SwiftUI

struct SettingsGridView: View {
    let model: SettingsModel
    @FocusState private var isFocused: Bool

    var body: some View {
        let profile = model.selectedProfile
        let page = model.currentPage
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * SettingsGrid.columns + column
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
                            onSelect: {
                                model.selectCell(index)
                                isFocused = true
                            }
                        )
                    }
                }
            }
        }
        .padding(12)
        .aspectRatio(1.6, contentMode: .fit)
        .frame(maxWidth: 640)
        .background(RoundedRectangle(cornerRadius: 16).fill(SettingsPalette.gridBackground))
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
    /// キー（Delete・矢印キーなど）がグリッドに届く。選んでいるマスを、リストの選択と同じく、届くならアクセント色・届かなければ灰色で塗る
    var isGridFocused = false
    let dragItem: SettingsDragItem
    let onSelect: () -> Void

    @State private var isDropTarget = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                // マスの面の上に、選んでいるマスの塗りを重ねる（面の下に置くと隠れる）
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(cell == nil ? Color.clear : SettingsPalette.cellBackground)
                    RoundedRectangle(cornerRadius: 12).fill(selectionFill).opacity(isSelected ? 1 : 0)
                }
            }
            .overlay(border)
            .overlay(alignment: .topTrailing) { holdBadge }
            .overlay(
                // ドロップ先: 選んでいるマスより強い塗りと、太いアクセント色の実線（キーが届く選んでいる空きマスの破線と見分ける）
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.24))
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 3.5)
                }
                .opacity(isDropTarget ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture(perform: onSelect)
            .modifier(SettingsDraggableIfFilled(item: cell == nil ? nil : dragItem, preview: cell))
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

    @ViewBuilder
    private var content: some View {
        if let cell {
            // 窓が小さくてマスが低いときは、説明・名前の順に省く
            ViewThatFits(in: .vertical) {
                VStack(spacing: 4) {
                    icon(cell, size: 19)
                    title(cell)
                    subtitle(cell)
                }
                VStack(spacing: 3) {
                    icon(cell, size: 16)
                    title(cell)
                }
                icon(cell, size: 16)
            }
            .padding(.horizontal, 6)
        } else {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(.secondary)
                .opacity(isSelected ? 0.9 : (contrast == .increased ? 0.75 : 0.4))
        }
    }

    private func icon(_ cell: Cell, size: CGFloat) -> some View {
        CellIconView(cell.icon, size: size)
            .foregroundStyle(Color.primary)
    }

    /// 長い名前は縮めずに省く（縮めると隣のマスと文字の大きさがそろわない）
    private func title(_ cell: Cell) -> some View {
        Text(SettingsGrid.displayTitle(for: cell))
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func subtitle(_ cell: Cell) -> some View {
        let subtitle = SettingsGrid.subtitleContent(for: cell)
        return Text(subtitle.text)
            .font(.system(size: 11, design: subtitle.isKeys ? .monospaced : .default))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    /// 少し長く止めてから実行するマス（Cell.requiresHold）の印。HUD と同じ記号を右上に
    @ViewBuilder
    private var holdBadge: some View {
        if cell?.requiresHold == true {
            HoldBadge(size: 10, color: .secondary)
                .padding(8)
        }
    }

    /// 選んでいるマスの色。キーが届くならアクセント色、届かなければ（サイドバーなどにキーがある）灰色。macOS のリストの選択と同じ決まり
    private var selectionColor: Color {
        isGridFocused ? Color.accentColor : Color.secondary
    }

    /// 選んでいるマスの塗り。枠の太さだけで見分けさせない（「コントラストを上げる」でも分かるように）
    private var selectionFill: Color {
        selectionColor.opacity(contrast == .increased ? 0.28 : 0.16)
    }

    /// 「コントラストを上げる」のときは枠を太くする（色は SettingsPalette が濃くする）
    @ViewBuilder
    private var border: some View {
        let increased = contrast == .increased
        let selectedWidth: CGFloat = increased ? 3 : 2.5
        if cell == nil {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? selectionColor : SettingsPalette.emptyBorder,
                    style: StrokeStyle(lineWidth: isSelected ? selectedWidth : (increased ? 1.8 : 1.2), dash: [5, 4])
                )
        } else {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? selectionColor : SettingsPalette.cellBorder, lineWidth: isSelected ? selectedWidth : (increased ? 1.5 : 1))
        }
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

/// 空きマスはドラッグできない
private struct SettingsDraggableIfFilled: ViewModifier {
    let item: SettingsDragItem?
    let preview: Cell?

    func body(content: Content) -> some View {
        if let item, let preview {
            content.draggable(item) {
                VStack(spacing: 4) {
                    CellIconView(preview.icon, size: 18)
                    Text(SettingsGrid.displayTitle(for: preview))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .padding(10)
                .frame(width: 120, height: 72)
                .background(RoundedRectangle(cornerRadius: 12).fill(SettingsPalette.cellBackground))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary, lineWidth: 2))
            }
        } else {
            content
        }
    }
}

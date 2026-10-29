// 担当: ui-settings
// 3×3 のグリッド。クリックで選ぶ・ドラッグで入れ替える・Delete で空にする・矢印キーで移る・右クリックで複製など
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
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.accentColor.opacity(isFocused ? 0.45 : 0), lineWidth: 3)
        )
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "\(profile.name) のページ \(model.pageIndex + 1)", bundle: .module))
    }
}

struct SettingsGridCell: View {
    let model: SettingsModel
    let index: Int
    let cell: Cell?
    let isSelected: Bool
    let dragItem: SettingsDragItem
    let onSelect: () -> Void

    @State private var isDropTarget = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(cell == nil ? Color.clear : SettingsPalette.cellBackground))
            .overlay(border)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .opacity(isDropTarget ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture(perform: onSelect)
            .modifier(SettingsDraggableIfFilled(item: cell == nil ? nil : dragItem, preview: cell))
            .dropDestination(for: SettingsDragItem.self) { items, _ in
                guard let item = items.first else { return false }
                return model.handleDrop(item.payload, onto: index)
            } isTargeted: { isDropTarget = $0 }
            .contextMenu { contextMenu }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SettingsGrid.accessibilityLabel(index: index, cell: cell))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, onSelect)
            .accessibilityActions {
                if let cell {
                    Button(String(localized: "複製", bundle: .module)) { model.duplicateCell(at: index) }
                    Button(String(localized: "削除", bundle: .module)) { model.clearCell(at: index) }
                    Button(String(localized: "このマスをテスト実行", bundle: .module)) { model.startTestRun(cellID: cell.id) }
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
                .opacity(isSelected ? 0.9 : 0.4)
        }
    }

    private func icon(_ cell: Cell, size: CGFloat) -> some View {
        CellIconView(cell.icon, size: size)
            .foregroundStyle(Color.primary)
    }

    private func title(_ cell: Cell) -> some View {
        Text(SettingsGrid.displayTitle(for: cell))
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .truncationMode(.tail)
    }

    private func subtitle(_ cell: Cell) -> some View {
        Text(SettingsGrid.subtitle(for: cell))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    @ViewBuilder
    private var border: some View {
        if cell == nil {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? Color.primary : SettingsPalette.emptyBorder,
                    style: StrokeStyle(lineWidth: isSelected ? 2 : 1.2, dash: [5, 4])
                )
        } else {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.primary : SettingsPalette.cellBorder, lineWidth: isSelected ? 2 : 1)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let cell {
            Button {
                model.duplicateCell(at: index)
            } label: {
                Text("複製", bundle: .module)
            }
            Button(role: .destructive) {
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

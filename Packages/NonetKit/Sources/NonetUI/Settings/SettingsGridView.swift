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
                        let shared = model.sharedCell(at: index)
                        SettingsGridCell(
                            model: model,
                            index: index,
                            cell: shared ?? (page.cells.indices.contains(index) ? page.cells[index] : nil),
                            isShared: shared != nil,
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
        .accessibilityLabel(String(localized: "\(SettingsText.profileName(profile)) のページ \(model.pageIndex + 1)", bundle: .module))
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
    /// 共通マスが代わりに出ている（薄く出して「共通」の印を付け、その場では編集しない）
    var isShared = false
    let isSelected: Bool
    let dragItem: SettingsDragItem
    let onSelect: () -> Void

    @State private var isDropTarget = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        content
            .opacity(isShared ? SettingsSharedBadge.dimmedOpacity : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(cell == nil ? Color.clear : SettingsPalette.cellBackground))
            .overlay(border)
            .overlay(alignment: .topTrailing) { hudOnlyBadge }
            .overlay(alignment: .topLeading) {
                if isShared {
                    // 狭いマスでは文字を省き、アイコンと重ならないようにする
                    GeometryReader { proxy in
                        SettingsSharedBadge(showsLabel: proxy.size.width >= SettingsSharedBadge.labelMinimumWidth)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .opacity(isDropTarget ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture(perform: onSelect)
            .modifier(SettingsDraggableIfFilled(item: cell == nil || isShared ? nil : dragItem, preview: cell))
            .dropDestination(for: SettingsDragItem.self) { items, _ in
                guard let item = items.first else { return false }
                return model.handleDrop(item.payload, onto: index)
            } isTargeted: { isDropTarget = $0 && !isShared }
            .contextMenu {
                if isShared {
                    SettingsSharedCellMenu(model: model, index: index)
                } else {
                    contextMenu
                }
            }
            .help(SettingsGrid.tooltip(for: cell) ?? "")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SettingsGrid.accessibilityLabel(index: index, cell: cell))
            .accessibilityValue(
                [isShared ? SettingsText.sharedCellAccessibilityValue : "", HUDOnlyMark.accessibilityValue(requiresHUD: cell?.requiresHUD == true)]
                    .filter { !$0.isEmpty }
                    .joined(separator: "、")
            )
            .accessibilityHint(isShared ? SettingsText.sharedCellNote : String(localized: "ドラッグか ⌥⌘＋矢印キーで入れ替え", bundle: .module))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, onSelect)
            .accessibilityActions {
                if isShared {
                    Button(String(localized: "共通マスを編集", bundle: .module)) { model.editSharedCell(at: index) }
                    Button(SettingsModel.stopSharingActionName) { model.stopSharing(at: index) }
                } else if let cell {
                    if model.canMakeShared(at: index) {
                        Button(SettingsModel.makeSharedActionName) { model.requestMakeShared(at: index) }
                    }
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

    /// HUD で選んだときだけ実行するマス（Cell.requiresHUD）の印。HUD と同じ記号を右上に
    @ViewBuilder
    private var hudOnlyBadge: some View {
        if cell?.requiresHUD == true {
            HUDOnlyBadge(size: 10, color: .secondary)
                .padding(8)
        }
    }

    /// 「コントラストを上げる」のときは枠を太くする（色は SettingsPalette が濃くする）
    @ViewBuilder
    private var border: some View {
        let increased = contrast == .increased
        if cell == nil {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? Color.primary : SettingsPalette.emptyBorder,
                    style: StrokeStyle(lineWidth: isSelected ? 2 : (increased ? 1.8 : 1.2), dash: [5, 4])
                )
        } else {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.primary : SettingsPalette.cellBorder, lineWidth: isSelected ? 2 : (increased ? 1.5 : 1))
        }
    }

    /// キーの印（⌘D など）は付けない。右クリックのメニューの項目に付けると、文字の欄を打っている間のキーまで取られることがあるため
    @ViewBuilder
    private var contextMenu: some View {
        if let cell {
            Button {
                model.duplicateCell(at: index)
            } label: {
                Text("複製", bundle: .module)
            }
            Button {
                model.selectCell(index)
                model.copyCell(at: index)
            } label: {
                Text("コピー", bundle: .module)
            }
            pasteButton
            swapMenu
            Menu {
                ForEach(model.copyTargets) { target in
                    Button(target.name) { model.copyCell(at: index, toProfile: target.id) }
                }
            } label: {
                Text("ほかのプロファイルにコピー", bundle: .module)
            }
            if model.canMakeShared(at: index) {
                Button(SettingsModel.makeSharedActionName) { model.requestMakeShared(at: index) }
            }
            Divider()
            if model.isSharedCellsSelected {
                // 共通マスの行では、消すと各アプリのマスに戻る
                Button(SettingsModel.stopSharingActionName, role: .destructive) { model.stopSharing(at: index) }
            } else {
                Button(role: .destructive) {
                    model.clearCell(at: index)
                } label: {
                    Text("削除", bundle: .module)
                }
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
            pasteButton
            swapMenu
        }
    }

    private var pasteButton: some View {
        Button {
            model.pasteCell(at: index)
        } label: {
            Text("ペースト", bundle: .module)
        }
        .disabled(!model.canPasteCell())
    }

    /// 隣のマスと入れ替え（端の向きは選べない）。空きマスとなら移動になる
    private var swapMenu: some View {
        Menu {
            ForEach(SettingsGrid.swapDirections, id: \.self) { direction in
                Button(SettingsText.swapName(direction)) { model.swapCell(at: index, direction) }
                    .disabled(!model.canSwapCell(at: index, direction))
            }
        } label: {
            Text("隣と入れ替え", bundle: .module)
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

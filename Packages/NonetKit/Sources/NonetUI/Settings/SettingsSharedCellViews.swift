// 担当: ui-settings
// 共通マスの見た目: サイドバーの行・グリッドの「共通」の印・共通マスの位置の右クリック・インスペクタの説明
import NonetCore
import SwiftUI

/// サイドバーの「共通マス」の行（グローバルの上）
struct SettingsSharedCellsRow: View {
    /// 置いてある共通マスの数
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pin")
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(SettingsText.sharedCellsName)
                .lineLimit(1)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 4)
            if count > 0 {
                Text(verbatim: "\(count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// グリッドで共通マスが代わりに出ているマスの左上の小さな印
struct SettingsSharedBadge: View {
    /// 共通マスの中身を薄くする割合（その場では編集できないことを示す）
    static let dimmedOpacity = 0.5
    /// 「共通」の文字まで出すマスの幅。これより狭いと、中央のアイコンと重なるので印だけにする
    static let labelMinimumWidth: CGFloat = 120

    var showsLabel = true

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "pin.fill")
                .font(.system(size: 8, weight: .semibold))
            if showsLabel {
                Text(SettingsText.sharedBadge)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Capsule(style: .circular).fill(SettingsPalette.cellBackground))
        .overlay(Capsule(style: .circular).strokeBorder(Color.secondary.opacity(0.5)))
        .padding(5)
        .accessibilityHidden(true)
    }
}

/// プロファイルのグリッドで、共通マスが代わりに出ている位置の右クリック。その場では編集せず、共通マスの行で編集する
struct SettingsSharedCellMenu: View {
    let model: SettingsModel
    let index: Int

    var body: some View {
        Button {
            model.editSharedCell(at: index)
        } label: {
            Text("共通マスを編集", bundle: .module)
        }
        Button {
            model.selectCell(index)
            model.copyCell(at: index)
        } label: {
            Text("コピー", bundle: .module)
        }
        Divider()
        Button(SettingsModel.stopSharingActionName) { model.stopSharing(at: index) }
    }
}

/// インスペクタ: プロファイルのグリッドで共通マスの位置を選んだとき。中身を見せ、共通マスの行へ移るボタンを出す
struct SettingsSharedCellNote: View {
    let model: SettingsModel
    let cell: Cell
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CellIconView(cell.icon, size: 16)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7).fill(SettingsPalette.cellBackground))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(SettingsPalette.cellBorder))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsGrid.displayTitle(for: cell))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(SettingsGrid.subtitle(for: cell))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .accessibilityElement(children: .combine)
            SettingsNote(text: SettingsText.sharedCellNote, symbol: "pin")
            Button {
                model.editSharedCell(at: index)
            } label: {
                Text("共通マスを編集", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
    }
}

// 担当: ui-shell
import NonetCore
import Observation
import SwiftUI

/// HUD の寸法。モック（HUD 動作デモ・アプリページと触覚）に合わせる
enum HUDLayout {
    static let width: CGFloat = 504
    /// 帯もページの点も無いときの高さ
    static let baseHeight: CGFloat = 315
    static let padding: CGFloat = 18
    static let spacing: CGFloat = 12
    static let cellSpacing: CGFloat = 8
    static let cornerRadius: CGFloat = 20
    static let cellCornerRadius: CGFloat = 12
    static let bannerHeight: CGFloat = 28
    static let pageIndicatorHeight: CGFloat = 13
    /// パネルの影を SwiftUI で描くための余白。ウィンドウの影は中身が変わると遅れて付くので使わない
    static let shadowMargin: CGFloat = 28

    static func size(for model: HUDModel) -> CGSize {
        var height = baseHeight
        if model.banner != nil {
            height += bannerHeight + spacing
        }
        if model.pageCount > 1 {
            height += pageIndicatorHeight + spacing
        }
        return CGSize(width: width, height: height)
    }
}

/// HUD の色。モックの値（#111111・#1E1E1E・#A8A8A8 など）
enum HUDPalette {
    static let background = Color(white: 0x11 / 255)
    static let cell = Color(white: 0x1E / 255)
    static let emptyCell = Color(white: 0x17 / 255)
    static let cellForeground = Color(white: 0xA8 / 255)
    static let secondaryText = Color(white: 0x9A / 255)
    static let detail = Color(white: 0x78 / 255)
    static let highlightedForeground = Color(white: 0x11 / 255)
    static let highlightedDetail = Color(white: 0x55 / 255)
    static let inactiveDot = Color(white: 0x55 / 255)
    static let border = Color.white.opacity(0.08)
}

/// 表示中の HUD の中身。update のたびにここだけを書き換え、ウィンドウやホスティングビューは作り直さない
@MainActor
@Observable
final class HUDStore {
    var model: HUDModel?
}

/// パネルに置く根のビュー。影の余白の中に HUD を描く
struct HUDRootView: View {
    let store: HUDStore

    var body: some View {
        ZStack {
            if let model = store.model {
                HUDView(model: model)
            }
        }
        .padding(HUDLayout.shadowMargin)
    }
}

struct HUDView: View {
    let model: HUDModel

    var body: some View {
        let size = HUDLayout.size(for: model)
        VStack(spacing: HUDLayout.spacing) {
            header
            if let banner = model.banner {
                HUDBannerView(text: banner)
            }
            grid
            if model.pageCount > 1 {
                HUDPageIndicator(pageIndex: model.pageIndex, pageCount: model.pageCount)
            }
        }
        .padding(HUDLayout.padding)
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: HUDLayout.cornerRadius, style: .continuous)
                .fill(HUDPalette.background)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HUDLayout.cornerRadius, style: .continuous)
                .strokeBorder(HUDPalette.border, lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(model.title))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(model.title)
                .foregroundStyle(.white)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(model.hint)
                .foregroundStyle(HUDPalette.secondaryText)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .font(.system(size: 12))
    }

    private var grid: some View {
        Grid(horizontalSpacing: HUDLayout.cellSpacing, verticalSpacing: HUDLayout.cellSpacing) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        HUDCellView(cell: cell(at: index), isHighlighted: model.highlightedIndex == index, index: index)
                    }
                }
            }
        }
    }

    private func cell(at index: Int) -> HUDCell? {
        model.cells.indices.contains(index) ? model.cells[index] : nil
    }
}

struct HUDCellView: View {
    let cell: HUDCell?
    let isHighlighted: Bool
    let index: Int

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HUDLayout.cellCornerRadius, style: .continuous)
        ZStack {
            if let cell {
                shape.fill(isHighlighted ? Color.white : HUDPalette.cell)
                VStack(spacing: 5) {
                    CellIconView(cell.icon, size: 20)
                    Text(cell.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.tail)
                    if let detail = cell.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(isHighlighted ? HUDPalette.highlightedDetail : HUDPalette.detail)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.horizontal, 8)
                .foregroundStyle(isHighlighted ? HUDPalette.highlightedForeground : HUDPalette.cellForeground)
            } else if isHighlighted {
                // 空きマスは実行しても何も起きないので、塗らずに枠だけで示す
                shape.fill(HUDPalette.emptyCell)
                shape.strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
            } else {
                shape.fill(HUDPalette.emptyCell)
                shape.strokeBorder(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(HUDAnnouncement.cellDescription(cell, index: index)))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

private struct HUDBannerView: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: HUDLayout.bannerHeight)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(white: 0.2)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private struct HUDPageIndicator: View {
    let pageIndex: Int
    let pageCount: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { page in
                Circle()
                    .fill(page == pageIndex ? Color.white : HUDPalette.inactiveDot)
                    .frame(width: 7, height: 7)
            }
            Text(verbatim: "\(pageIndex + 1) / \(pageCount)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(HUDPalette.secondaryText)
                .padding(.leading, 6)
        }
        .frame(height: HUDLayout.pageIndicatorHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(HUDAnnouncement.pageDescription(pageIndex: pageIndex, pageCount: pageCount)))
    }
}

/// VoiceOver に読ませる文
enum HUDAnnouncement {
    /// マスの位置の呼び方（左上から右へ、上の行から）
    static func positionName(_ index: Int) -> String {
        switch index {
        case 0: String(localized: "左上", bundle: .module)
        case 1: String(localized: "上", bundle: .module)
        case 2: String(localized: "右上", bundle: .module)
        case 3: String(localized: "左", bundle: .module)
        case 4: String(localized: "中央", bundle: .module)
        case 5: String(localized: "右", bundle: .module)
        case 6: String(localized: "左下", bundle: .module)
        case 7: String(localized: "下", bundle: .module)
        case 8: String(localized: "右下", bundle: .module)
        default: ""
        }
    }

    /// 名詞の前に置くときの位置の呼び方（英語では「top-right corner」のようにハイフンでつなぐ）。
    /// 角の4つだけ別の訳が要る。ほかは positionName と同じ
    static func attributivePositionName(_ index: Int) -> String {
        switch index {
        case 0: String(localized: "attributivePosition.topLeft", defaultValue: "左上", bundle: .module)
        case 2: String(localized: "attributivePosition.topRight", defaultValue: "右上", bundle: .module)
        case 6: String(localized: "attributivePosition.bottomLeft", defaultValue: "左下", bundle: .module)
        case 8: String(localized: "attributivePosition.bottomRight", defaultValue: "右下", bundle: .module)
        default: positionName(index)
        }
    }

    static func pageDescription(pageIndex: Int, pageCount: Int) -> String {
        String(localized: "\(pageCount) ページ中 \(pageIndex + 1) ページ目", bundle: .module)
    }

    static func cellDescription(_ cell: HUDCell?, index: Int) -> String {
        let position = positionName(index)
        guard let cell else {
            return String(localized: "空きマス、\(position)", bundle: .module)
        }
        if let detail = cell.detail, !detail.isEmpty {
            return String(localized: "\(cell.title)、\(detail)、\(position)", bundle: .module)
        }
        return String(localized: "\(cell.title)、\(position)", bundle: .module)
    }

    /// ハイライト中のマス。指が離れていれば nil
    static func highlighted(in model: HUDModel) -> String? {
        guard let index = model.highlightedIndex, (0..<Page.cellCount).contains(index) else { return nil }
        let cell = model.cells.indices.contains(index) ? model.cells[index] : nil
        return cellDescription(cell, index: index)
    }

    /// 前の表示から読み上げる内容が変わったときだけ文を返す（同じ文を何度も読ませない）
    static func announcement(from previous: HUDModel?, to model: HUDModel) -> String? {
        let isNewPage = previous == nil || previous?.pageIndex != model.pageIndex || previous?.title != model.title
        let current = highlighted(in: model)
        if isNewPage {
            let page = model.pageCount > 1
                ? String(localized: "\(model.title)、\(pageDescription(pageIndex: model.pageIndex, pageCount: model.pageCount))", bundle: .module)
                : model.title
            return [page, current].compactMap { $0 }.joined(separator: String(localized: "、", bundle: .module))
        }
        guard previous.flatMap(highlighted(in:)) != current else { return nil }
        return current
    }
}

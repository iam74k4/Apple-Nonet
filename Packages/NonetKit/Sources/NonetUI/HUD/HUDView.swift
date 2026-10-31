// 担当: ui-shell
import NonetCore
import Observation
import SwiftUI

/// HUD の寸法。モック（HUD 動作デモ・アプリページと触覚）に合わせた標準の値に、設定の「HUD の大きさ」の倍率を掛ける
struct HUDMetrics: Equatable {
    /// 寸法と文字に掛ける倍率（HUDModel.scale）
    var scale: CGFloat

    init(scale: CGFloat) {
        self.scale = scale.isFinite && scale > 0 ? scale : 1
    }

    var width: CGFloat { HUDLayout.width * scale }
    var padding: CGFloat { HUDLayout.padding * scale }
    var spacing: CGFloat { HUDLayout.spacing * scale }
    var cellSpacing: CGFloat { HUDLayout.cellSpacing * scale }
    var cornerRadius: CGFloat { HUDLayout.cornerRadius * scale }
    var cellCornerRadius: CGFloat { HUDLayout.cellCornerRadius * scale }
    var bannerHeight: CGFloat { HUDLayout.bannerHeight * scale }
    var pageIndicatorHeight: CGFloat { HUDLayout.pageIndicatorHeight * scale }
    var footnoteHeight: CGFloat { HUDLayout.footnoteHeight * scale }
    var headerFontSize: CGFloat { 12 * scale }
    var cellTitleFontSize: CGFloat { 13 * scale }
    var detailFontSize: CGFloat { 11 * scale }
    var iconSize: CGFloat { 20 * scale }
    /// HUD で選んだときだけ実行するマスの印（HUDOnlyBadge）の大きさと、マスの角からの距離
    var badgeSize: CGFloat { 9 * scale }
    var badgeInset: CGFloat { 7 * scale }
    var dotSize: CGFloat { 7 * scale }
    var dotSpacing: CGFloat { 8 * scale }
    /// アプリのページとグローバルのページの点の間に、さらに空ける幅
    var pageGroupGap: CGFloat { HUDLayout.pageGroupGap * scale }

    func size(for model: HUDModel) -> CGSize {
        var height = HUDLayout.baseHeight
        if model.banner != nil {
            height += HUDLayout.bannerHeight + HUDLayout.spacing
        }
        if model.pageCount > 1 {
            height += HUDLayout.pageIndicatorHeight + HUDLayout.spacing
        }
        if model.footnote != nil {
            height += HUDLayout.footnoteHeight + HUDLayout.spacing
        }
        return CGSize(width: HUDLayout.width * scale, height: height * scale)
    }
}

/// HUD の標準の寸法（倍率 1）。モック（HUD 動作デモ・アプリページと触覚）に合わせる
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
    /// 9マスの下の使い始めの案内（11pt で2行まで）
    static let footnoteHeight: CGFloat = 28
    static let pageGroupGap: CGFloat = 8
    /// パネルの影を SwiftUI で描くための余白。ウィンドウの影は中身が変わると遅れて付くので使わない
    static let shadowMargin: CGFloat = 28

    /// model.scale の倍率を掛けた大きさ
    static func size(for model: HUDModel) -> CGSize {
        HUDMetrics(scale: model.scale).size(for: model)
    }
}

/// HUD の色。モックの値（#111111・#1E1E1E・#A8A8A8 など）。文字と点は WCAG の比（文字 4.5:1、点 3:1）を満たすよう明るくしてある。
/// システム設定の「コントラストを上げる」では、枠・空きマス・文字をさらに明るくする（HUDColors）
enum HUDPalette {
    static let background = Color(white: backgroundWhite)
    static let cell = Color(white: cellWhite)
    static let emptyCell = Color(white: 0x17 / 255)
    static let secondaryText = Color(white: 0x9A / 255)
    static let highlightedForeground = Color(white: 0x11 / 255)
    static let highlightedDetail = Color(white: 0x55 / 255)

    static let backgroundWhite: Double = 0x11 / 255
    static let cellWhite: Double = 0x1E / 255

    static func colors(increasedContrast: Bool) -> HUDColors {
        increasedContrast ? .increased : .standard
    }

    /// 灰色どうしのコントラスト比（WCAG 2。白の量 0〜1 で渡す）
    static func contrastRatio(_ first: Double, _ second: Double) -> Double {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ white: Double) -> Double {
        white <= 0.03928 ? white / 12.92 : pow((white + 0.055) / 1.055, 2.4)
    }
}

/// 「コントラストを上げる」で変わる色。白の量（0〜1）と不透明度で持ち、比をテストで確かめる
struct HUDColors: Equatable {
    /// マスの名前とアイコン
    var cellForegroundWhite: Double
    /// マスの下のキー（⌘B など）
    var detailWhite: Double
    /// 右上の案内・ページの番号・使い始めの案内
    var secondaryTextWhite: Double
    var inactiveDotWhite: Double
    /// パネルの縁
    var borderOpacity: Double
    /// 空きマスの点線
    var emptyCellStrokeOpacity: Double

    static let standard = HUDColors(
        cellForegroundWhite: 0xA8 / 255,
        detailWhite: 0x9A / 255,
        secondaryTextWhite: 0x9A / 255,
        inactiveDotWhite: 0x77 / 255,
        borderOpacity: 0.08,
        emptyCellStrokeOpacity: 0.07
    )

    static let increased = HUDColors(
        cellForegroundWhite: 0xE0 / 255,
        detailWhite: 0xC8 / 255,
        secondaryTextWhite: 0xC8 / 255,
        inactiveDotWhite: 0x9A / 255,
        borderOpacity: 0.4,
        emptyCellStrokeOpacity: 0.45
    )

    var cellForeground: Color { Color(white: cellForegroundWhite) }
    var detail: Color { Color(white: detailWhite) }
    var secondaryText: Color { Color(white: secondaryTextWhite) }
    var inactiveDot: Color { Color(white: inactiveDotWhite) }
    var border: Color { Color.white.opacity(borderOpacity) }
    var emptyCellStroke: Color { Color.white.opacity(emptyCellStrokeOpacity) }
}

/// 表示中の HUD の中身。update のたびにここだけを書き換え、ウィンドウやホスティングビューは作り直さない
@MainActor
@Observable
final class HUDStore {
    var model: HUDModel?
    /// システム設定の「コントラストを上げる」（出すたびに読み直す）
    var increasedContrast = false
}

/// パネルに置く根のビュー。影の余白の中に HUD を描く
struct HUDRootView: View {
    let store: HUDStore

    var body: some View {
        ZStack {
            if let model = store.model {
                HUDView(model: model, colors: HUDPalette.colors(increasedContrast: store.increasedContrast))
            }
        }
        .padding(HUDLayout.shadowMargin)
    }
}

struct HUDView: View {
    let model: HUDModel
    var colors: HUDColors = .standard

    private var metrics: HUDMetrics { HUDMetrics(scale: model.scale) }

    var body: some View {
        let metrics = metrics
        let size = metrics.size(for: model)
        VStack(spacing: metrics.spacing) {
            header
            if let banner = model.banner {
                HUDBannerView(text: banner, style: model.bannerStyle, metrics: metrics)
            }
            grid
            if model.pageCount > 1 {
                HUDPageIndicator(
                    pageIndex: model.pageIndex,
                    pageCount: model.pageCount,
                    globalPagesStart: model.globalPagesStart,
                    metrics: metrics,
                    colors: colors
                )
            }
            if let footnote = model.footnote {
                Text(footnote)
                    .font(.system(size: metrics.detailFontSize))
                    .foregroundStyle(colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.footnoteHeight)
            }
        }
        .padding(metrics.padding)
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(HUDPalette.background)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .strokeBorder(colors.border, lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(model.title))
    }

    private var header: some View {
        HStack(spacing: 12 * metrics.scale) {
            Text(model.title)
                .foregroundStyle(.white)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(model.hint)
                .foregroundStyle(colors.secondaryText)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .font(.system(size: metrics.headerFontSize))
    }

    private var grid: some View {
        Grid(horizontalSpacing: metrics.cellSpacing, verticalSpacing: metrics.cellSpacing) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        HUDCellView(cell: cell(at: index), isHighlighted: model.highlightedIndex == index, index: index, metrics: metrics, colors: colors)
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
    var metrics = HUDMetrics(scale: 1)
    var colors: HUDColors = .standard

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.cellCornerRadius, style: .continuous)
        ZStack {
            if let cell {
                shape.fill(isHighlighted ? Color.white : HUDPalette.cell)
                VStack(spacing: 5 * metrics.scale) {
                    CellIconView(cell.icon, size: metrics.iconSize)
                    Text(cell.title)
                        .font(.system(size: metrics.cellTitleFontSize, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.tail)
                    if let detail = cell.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: metrics.detailFontSize))
                            .foregroundStyle(isHighlighted ? HUDPalette.highlightedDetail : colors.detail)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.horizontal, 8 * metrics.scale)
                .foregroundStyle(isHighlighted ? HUDPalette.highlightedForeground : colors.cellForeground)
            } else if isHighlighted {
                // 空きマスは実行しても何も起きないので、塗らずに枠だけで示す
                shape.fill(HUDPalette.emptyCell)
                shape.strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
            } else {
                shape.fill(HUDPalette.emptyCell)
                shape.strokeBorder(colors.emptyCellStroke, style: StrokeStyle(lineWidth: 1, dash: [4 * metrics.scale, 3 * metrics.scale]))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if cell?.requiresHUD == true {
                HUDOnlyBadge(size: metrics.badgeSize, color: isHighlighted ? HUDPalette.highlightedDetail : colors.detail)
                    .padding(metrics.badgeInset)
            }
        }
        .overlay(alignment: .topLeading) {
            if cell?.isShared == true {
                HUDSharedBadge(isHighlighted: isHighlighted, metrics: metrics, colors: colors)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(HUDAnnouncement.cellDescription(cell, index: index)))
        .accessibilityValue(Text(HUDAnnouncement.cellValue(cell)))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// 共通マス（どのアプリでも同じ位置に出るマス）の左上の小さな印
struct HUDSharedBadge: View {
    let isHighlighted: Bool
    var metrics = HUDMetrics(scale: 1)
    var colors: HUDColors = .standard

    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 8 * metrics.scale, weight: .semibold))
            .foregroundStyle(isHighlighted ? HUDPalette.highlightedDetail : colors.detail)
            .padding(6 * metrics.scale)
            .accessibilityHidden(true)
    }
}

private struct HUDBannerView: View {
    let text: String
    let style: HUDBannerStyle
    let metrics: HUDMetrics

    var body: some View {
        HStack(spacing: 6 * metrics.scale) {
            Image(systemName: style == .warning ? "exclamationmark.triangle.fill" : "clock")
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.system(size: metrics.headerFontSize, weight: .medium))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: metrics.bannerHeight)
        .background(RoundedRectangle(cornerRadius: 8 * metrics.scale, style: .continuous).fill(Color(white: style == .warning ? 0.2 : 0.15)))
        .overlay(
            RoundedRectangle(cornerRadius: 8 * metrics.scale, style: .continuous)
                .strokeBorder(Color.white.opacity(style == .warning ? 0.25 : 0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// ページの点。アプリのページの後ろにグローバルのページをつなげたときは、その境目を少し離す
private struct HUDPageIndicator: View {
    let pageIndex: Int
    let pageCount: Int
    let globalPagesStart: Int?
    let metrics: HUDMetrics
    let colors: HUDColors

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<pageCount, id: \.self) { page in
                Circle()
                    .fill(page == pageIndex ? Color.white : colors.inactiveDot)
                    .frame(width: metrics.dotSize, height: metrics.dotSize)
                    .padding(.leading, HUDPageDots.leadingSpace(before: page, globalPagesStart: globalPagesStart, metrics: metrics))
            }
        }
        .frame(height: metrics.pageIndicatorHeight)
        // 見るのは点だけ（「1 / 3」を並べると同じことを2回言う）。何ページ目かは VoiceOver の値で読む
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("ページ", bundle: .module))
        .accessibilityValue(Text(HUDAnnouncement.pageDescription(pageIndex: pageIndex, pageCount: pageCount)))
    }
}

/// ページの点の並べ方
enum HUDPageDots {
    /// page 番目の点の前に空ける幅。グローバルの最初のページの前は pageGroupGap だけ広い
    static func leadingSpace(before page: Int, globalPagesStart: Int?, metrics: HUDMetrics) -> CGFloat {
        guard page > 0 else { return 0 }
        return page == globalPagesStart ? metrics.dotSpacing + metrics.pageGroupGap : metrics.dotSpacing
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

    /// 共通マスの VoiceOver の値（設定のグリッドと同じ文言）。共通マスでなければ nil
    static func sharedValue(_ cell: HUDCell?) -> String? {
        guard cell?.isShared == true else { return nil }
        return String(localized: "sharedButton.accessibilityValue", defaultValue: "共通マス", bundle: .module)
    }

    /// マスの VoiceOver の値。共通マス・HUD で選んだときだけ実行するマスなら、それを並べる
    static func cellValue(_ cell: HUDCell?) -> String {
        [sharedValue(cell) ?? "", HUDOnlyMark.accessibilityValue(requiresHUD: cell?.requiresHUD == true)]
            .filter { !$0.isEmpty }
            .joined(separator: "、")
    }

    /// ハイライト中のマス。指が離れていれば nil。HUD で選んだときだけ実行するマスなら、そう言い添える
    /// （すぐにタップして HUD が出たときに、なぜ実行しなかったかが分かるように）
    static func highlighted(in model: HUDModel) -> String? {
        guard let index = model.highlightedIndex, (0..<Page.cellCount).contains(index) else { return nil }
        let cell = model.cells.indices.contains(index) ? model.cells[index] : nil
        let description = cellDescription(cell, index: index)
        guard cell?.requiresHUD == true else { return description }
        return String(localized: "\(description)、\(HUDOnlyMark.accessibilityValue)", bundle: .module)
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

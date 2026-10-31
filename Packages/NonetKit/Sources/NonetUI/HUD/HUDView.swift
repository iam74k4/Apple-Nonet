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
    var frameSide: CGFloat { HUDLayout.frameSide * scale }
    var frameTop: CGFloat { HUDLayout.frameTop * scale }
    var frameBottom: CGFloat { HUDLayout.frameBottom * scale }
    var padCornerRadius: CGFloat { HUDLayout.padCornerRadius * scale }
    /// 少し長く止めるマスの進み具合の線の太さ
    var holdLineWidth: CGFloat { 3 * scale }
    var headerFontSize: CGFloat { 12 * scale }
    var cellTitleFontSize: CGFloat { 13 * scale }
    var detailFontSize: CGFloat { 11 * scale }
    var iconSize: CGFloat { 20 * scale }
    /// 少し長く止めてから実行するマスの印（HoldBadge）の大きさと、マスの角からの距離
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

/// HUD の標準の寸法（倍率 1）。モック（HUD 動作デモ・アプリページと触覚）に合わせ、9マスの周りに外枠を足した
enum HUDLayout {
    static let width: CGFloat = 504
    /// 帯もページの点も無いときの高さ（9マスの高さは前と同じで、外枠の上下の分だけ高い）
    static let baseHeight: CGFloat = 315 + frameTop + frameBottom
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
    /// 9マスの周りの外枠（トラックパッドの外枠を表す）の幅。トラックパッドの割合（左右 11%・奥 17%・手前 15%）の順を保ち、
    /// 帯として見分けられて、9マスを小さくしすぎない幅にする（割合どおりにするとマスが細くなりすぎるので、帯は控えめにする）
    static let frameSide: CGFloat = 13
    static let frameTop: CGFloat = 18
    static let frameBottom: CGFloat = 16
    /// 外枠の角の丸み（マスの角の丸み 12 と外枠の幅が作る、外側の丸み）
    static let padCornerRadius: CGFloat = 18
    /// 9マスの下の塗らない部分を、マスより外へ広げる幅（外枠の帯とマスの間に少しすき間を空ける）
    static let gridWell: CGFloat = 4
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
    /// 少し長く止めるマスを、止め終える前に光らせる色（白く塗る前）
    static let holdingCell = Color(white: holdingCellWhite)
    static let holdingCellWhite: Double = 0x33 / 255

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
    /// 外枠（やめる場所）。ふだんは控えめな帯と縁、指が外枠にあるときは帯を明るくして縁を白くする
    var frameFillOpacity: Double
    var frameStrokeOpacity: Double
    var frameActiveFillOpacity: Double
    var frameActiveStrokeOpacity: Double
    /// 指が外枠にあるときのマスの不透明度（離しても実行しないことを見せる）
    var dimmedCellOpacity: Double

    static let standard = HUDColors(
        cellForegroundWhite: 0xA8 / 255,
        detailWhite: 0x9A / 255,
        secondaryTextWhite: 0x9A / 255,
        inactiveDotWhite: 0x77 / 255,
        borderOpacity: 0.08,
        emptyCellStrokeOpacity: 0.07,
        frameFillOpacity: 0.035,
        frameStrokeOpacity: 0.1,
        frameActiveFillOpacity: 0.13,
        frameActiveStrokeOpacity: 0.8,
        dimmedCellOpacity: 0.3
    )

    static let increased = HUDColors(
        cellForegroundWhite: 0xE0 / 255,
        detailWhite: 0xC8 / 255,
        secondaryTextWhite: 0xC8 / 255,
        inactiveDotWhite: 0x9A / 255,
        borderOpacity: 0.4,
        emptyCellStrokeOpacity: 0.45,
        frameFillOpacity: 0.07,
        frameStrokeOpacity: 0.45,
        frameActiveFillOpacity: 0.22,
        frameActiveStrokeOpacity: 1,
        dimmedCellOpacity: 0.22
    )

    var cellForeground: Color { Color(white: cellForegroundWhite) }
    var detail: Color { Color(white: detailWhite) }
    var secondaryText: Color { Color(white: secondaryTextWhite) }
    var inactiveDot: Color { Color(white: inactiveDotWhite) }
    var border: Color { Color.white.opacity(borderOpacity) }
    var emptyCellStroke: Color { Color.white.opacity(emptyCellStrokeOpacity) }

    func frameFill(isActive: Bool) -> Color {
        Color.white.opacity(isActive ? frameActiveFillOpacity : frameFillOpacity)
    }

    func frameStroke(isActive: Bool) -> Color {
        Color.white.opacity(isActive ? frameActiveStrokeOpacity : frameStrokeOpacity)
    }
}

/// 表示中の HUD の中身。update のたびにここだけを書き換え、ウィンドウやホスティングビューは作り直さない
@MainActor
@Observable
final class HUDStore {
    var model: HUDModel?
    /// システム設定の「コントラストを上げる」（出すたびに読み直す）
    var increasedContrast = false
    /// システム設定の「視差効果を減らす」（出すたびに読み直す）。外枠の切り替えをアニメーションにせず、進み具合も満たしていかない
    var reduceMotion = false
}

/// パネルに置く根のビュー。影の余白の中に HUD を描く
struct HUDRootView: View {
    let store: HUDStore

    var body: some View {
        ZStack {
            if let model = store.model {
                HUDView(model: model, colors: HUDPalette.colors(increasedContrast: store.increasedContrast), reduceMotion: store.reduceMotion)
            }
        }
        .padding(HUDLayout.shadowMargin)
    }
}

struct HUDView: View {
    let model: HUDModel
    var colors: HUDColors = .standard
    var reduceMotion = false
    /// 少し長く止めるマスの進み具合を、この値（0〜1）で止めて描く（見た目の確認用）。nil なら止め始めてから duration で満たす
    var fixedHoldProgress: Double?

    private var metrics: HUDMetrics { HUDMetrics(scale: model.scale) }

    var body: some View {
        let metrics = metrics
        let size = metrics.size(for: model)
        VStack(spacing: metrics.spacing) {
            header
            if let banner = model.banner {
                HUDBannerView(text: banner, style: model.bannerStyle, metrics: metrics)
            }
            pad
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

    /// トラックパッドを表す面。9マスと、その周りの外枠（指を出して離すと何もせずに閉じる場所）。
    /// 指が外枠にあるときは、外枠を明るくして縁を白くし、マスを暗くして、中央に「離すとやめる」を出す
    private var pad: some View {
        let inFrame = model.isFingerInFrame
        let shape = RoundedRectangle(cornerRadius: metrics.padCornerRadius, style: .continuous)
        // 9マスの下は塗らず、外枠の帯だけが明るく見えるようにする（マスの間のすき間は外枠ではない）
        let well = HUDLayout.gridWell * metrics.scale
        return ZStack {
            shape.fill(colors.frameFill(isActive: inFrame))
            RoundedRectangle(cornerRadius: metrics.cellCornerRadius + well, style: .continuous)
                .fill(HUDPalette.background)
                .padding(.horizontal, metrics.frameSide - well)
                .padding(.top, metrics.frameTop - well)
                .padding(.bottom, metrics.frameBottom - well)
            shape.strokeBorder(colors.frameStroke(isActive: inFrame), lineWidth: (inFrame ? 1.5 : 1) * metrics.scale)
            grid
                .padding(.horizontal, metrics.frameSide)
                .padding(.top, metrics.frameTop)
                .padding(.bottom, metrics.frameBottom)
                .opacity(inFrame ? colors.dimmedCellOpacity : 1)
            if inFrame {
                HUDCancelLabel(metrics: metrics, colors: colors)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: inFrame)
    }

    private var grid: some View {
        Grid(horizontalSpacing: metrics.cellSpacing, verticalSpacing: metrics.cellSpacing) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        HUDCellView(
                            cell: cell(at: index),
                            isHighlighted: model.highlightedIndex == index,
                            index: index,
                            metrics: metrics,
                            colors: colors,
                            hold: model.hold?.cellIndex == index && model.highlightedIndex == index ? model.hold : nil,
                            reduceMotion: reduceMotion,
                            fixedHoldProgress: fixedHoldProgress
                        )
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
    /// 光っている、少し長く止めるマスの進み具合。止め終えるまでは白く塗らず、縁に沿って線を伸ばす
    var hold: HUDHold?
    var reduceMotion = false
    var fixedHoldProgress: Double?

    /// 白く塗る（いま指を離すと実行する）。少し長く止めるマスは止め終えてから
    private var isFilled: Bool {
        isHighlighted && (hold?.isReady ?? true)
    }

    /// 少し長く止めるマスを止めている途中
    private var isHolding: Bool {
        isHighlighted && hold?.isReady == false
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.cellCornerRadius, style: .continuous)
        ZStack {
            if let cell {
                shape.fill(isFilled ? Color.white : isHolding ? HUDPalette.holdingCell : HUDPalette.cell)
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
                            .foregroundStyle(isFilled ? HUDPalette.highlightedDetail : isHolding ? Color.white.opacity(0.8) : colors.detail)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.horizontal, 8 * metrics.scale)
                .foregroundStyle(isFilled ? HUDPalette.highlightedForeground : isHolding ? Color.white : colors.cellForeground)
                if isHolding, let hold {
                    HUDHoldRing(hold: hold, cornerRadius: metrics.cellCornerRadius, lineWidth: metrics.holdLineWidth, animates: !reduceMotion, fixedProgress: fixedHoldProgress)
                }
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
            if cell?.requiresHold == true {
                HoldBadge(size: metrics.badgeSize, color: isFilled ? HUDPalette.highlightedDetail : isHolding ? Color.white : colors.detail)
                    .padding(metrics.badgeInset)
            }
        }
        .overlay(alignment: .topLeading) {
            if cell?.isShared == true {
                HUDSharedBadge(isHighlighted: isFilled, metrics: metrics, colors: colors)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(HUDAnnouncement.cellDescription(cell, index: index)))
        .accessibilityValue(Text(HUDAnnouncement.cellValue(cell)))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// 少し長く止めるマスの進み具合。マスの縁に沿って白い線を伸ばし、一周したら（HUDHold.isReady）マスが白くなる。
/// 「視差効果を減らす」では線を伸ばさず、縁を点線で囲むだけにする（止め終えたら白くなるのは同じ）
struct HUDHoldRing: View {
    let hold: HUDHold
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let animates: Bool
    let fixedProgress: Double?
    @State private var progress: CGFloat = 0

    var body: some View {
        let ring = HUDHoldRingShape(cornerRadius: cornerRadius, inset: lineWidth / 2)
        ZStack {
            if let fixedProgress {
                ring.stroke(Color.white.opacity(0.2), lineWidth: lineWidth)
                ring.trim(from: 0, to: CGFloat(min(max(fixedProgress, 0), 1)))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            } else if animates {
                ring.stroke(Color.white.opacity(0.2), lineWidth: lineWidth)
                ring.trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            } else {
                ring.stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: lineWidth * 0.6, dash: [lineWidth * 1.5, lineWidth * 1.5]))
            }
        }
        .onAppear { start() }
        .onChange(of: hold.since) { start() }
        .accessibilityHidden(true)
    }

    /// 止め始めた（このマスになった・滑らせ直した）ところから、duration で一周させる
    private func start() {
        guard animates, fixedProgress == nil else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { progress = 0 }
        withAnimation(.linear(duration: max(hold.duration, 0))) { progress = 1 }
    }
}

/// マスの縁をなぞる線。上の辺の中ほどから時計回りに一周する（進み具合が時計の針と同じ向きに伸びる）
struct HUDHoldRingShape: Shape {
    var cornerRadius: CGFloat
    /// 線の太さの半分だけ内側を通る（マスの外にはみ出さない）
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: inset, dy: inset)
        let radius = max(0, min(cornerRadius - inset, box.width / 2, box.height / 2))
        var path = Path()
        path.move(to: CGPoint(x: box.midX, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX - radius, y: box.minY))
        path.addArc(center: CGPoint(x: box.maxX - radius, y: box.minY + radius), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - radius))
        path.addArc(center: CGPoint(x: box.maxX - radius, y: box.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: box.minX + radius, y: box.maxY))
        path.addArc(center: CGPoint(x: box.minX + radius, y: box.maxY - radius), radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: box.minX, y: box.minY + radius))
        path.addArc(center: CGPoint(x: box.minX + radius, y: box.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// 指が外枠にあるときに、暗くしたマスの上に出す「離すとやめる」
struct HUDCancelLabel: View {
    var metrics = HUDMetrics(scale: 1)
    var colors: HUDColors = .standard

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10 * metrics.scale, style: .continuous)
        HStack(spacing: 7 * metrics.scale) {
            Image(systemName: "xmark")
                .font(.system(size: 11 * metrics.scale, weight: .bold))
            Text(HUDAnnouncement.cancelLabel)
                .font(.system(size: 14 * metrics.scale, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 16 * metrics.scale)
        .padding(.vertical, 9 * metrics.scale)
        // 下の暗くしたマスの文字が透けないよう、塗りつぶす
        .background(shape.fill(HUDPalette.background))
        .overlay(shape.strokeBorder(colors.frameStroke(isActive: true), lineWidth: 1))
        .accessibilityElement(children: .combine)
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

    /// マスの VoiceOver の値。共通マス・少し長く止めてから実行するマスなら、それを並べる
    static func cellValue(_ cell: HUDCell?) -> String {
        [sharedValue(cell) ?? "", HoldMark.accessibilityValue(requiresHold: cell?.requiresHold == true)]
            .filter { !$0.isEmpty }
            .joined(separator: "、")
    }

    /// 指が外枠にあるときの「離すとやめる」（HUD の中央と読み上げ）
    static var cancelLabel: String {
        String(localized: "離すとやめる", bundle: .module)
    }

    /// 少し長く止めるマスを止め終えたとき
    static var holdReady: String {
        String(localized: "離すと実行", bundle: .module)
    }

    /// ハイライト中のマス。指が外枠にある・離れていれば nil。少し長く止めてから実行するマスなら、そう言い添える
    static func highlighted(in model: HUDModel) -> String? {
        guard let index = model.highlightedIndex, (0..<Page.cellCount).contains(index) else { return nil }
        let cell = model.cells.indices.contains(index) ? model.cells[index] : nil
        let description = cellDescription(cell, index: index)
        guard cell?.requiresHold == true else { return description }
        return String(localized: "\(description)、\(HoldMark.accessibilityValue)", bundle: .module)
    }

    /// 前の表示から読み上げる内容が変わったときだけ文を返す（同じ文を何度も読ませない）。
    /// 外枠に入ったら「離すとやめる」、少し長く止めるマスを止め終えたら「離すと実行」
    static func announcement(from previous: HUDModel?, to model: HUDModel) -> String? {
        let isNewPage = previous == nil || previous?.pageIndex != model.pageIndex || previous?.title != model.title
        let current = model.isFingerInFrame ? cancelLabel : highlighted(in: model)
        if !isNewPage, let hold = model.hold, hold.isReady, previous?.hold?.isReady != true, previous?.highlightedIndex == model.highlightedIndex {
            return holdReady
        }
        if isNewPage {
            let page = model.pageCount > 1
                ? String(localized: "\(model.title)、\(pageDescription(pageIndex: model.pageIndex, pageCount: model.pageCount))", bundle: .module)
                : model.title
            return [page, current].compactMap { $0 }.joined(separator: String(localized: "、", bundle: .module))
        }
        let before = previous.flatMap { $0.isFingerInFrame ? cancelLabel : highlighted(in: $0) }
        guard before != current else { return nil }
        return current
    }
}

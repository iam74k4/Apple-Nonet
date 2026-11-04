// 担当: ui-shell
import NonetCore
import Observation
import SwiftUI

/// HUD の寸法。標準の値（HUDLayout・RadialLayout）に、設定の「大きく表示」の倍率を掛ける
struct HUDMetrics: Equatable {
    /// 寸法と文字に掛ける倍率（HUDModel.scale）
    var scale: CGFloat

    init(scale: CGFloat) {
        self.scale = scale.isFinite && scale > 0 ? scale : 1
    }

    /// ここより外は外枠（見えない線）
    var outerRadius: CGFloat { RadialLayout.outerRadius * scale }
    /// 8つの鍵の中心が乗る円
    var keyRadius: CGFloat { RadialLayout.keyRadius * scale }
    var centerRadius: CGFloat { RadialLayout.centerRadius * scale }
    /// 円を囲む正方形の一辺。HUDPresenting.show が返す枠（ポインタでマスを選ぶ範囲）はこの正方形
    var circleSide: CGFloat { outerRadius * 2 }
    /// 正方形の中の、円の中心（開いたときのポインタ）
    var center: CGPoint { CGPoint(x: outerRadius, y: outerRadius) }
    var iconSize: CGFloat { HUDLayout.iconSize * scale }
    var centerIconSize: CGFloat { HUDLayout.centerIconSize * scale }
    /// 光らせた鍵の下の白い円の半径
    var selectionRadius: CGFloat { HUDLayout.selectionRadius * scale }
    /// 空きマスの点の半径
    var emptyDotRadius: CGFloat { 2.5 * scale }
    /// 少し長く止めるマスの進み具合の線の太さ
    var holdLineWidth: CGFloat { 2.5 * scale }
    /// 少し長く止めてから実行するマスの印（HoldBadge）の大きさ
    var badgeSize: CGFloat { 7 * scale }
    /// 左右の外へ出して止めているときの矢印の円の半径
    var pageArrowRadius: CGFloat { HUDLayout.pageArrowRadius * scale }
    var dotSize: CGFloat { 4.5 * scale }
    var dotSpacing: CGFloat { 6 * scale }
    /// アプリのページとグローバルのページの点の間に、さらに空ける幅
    var pageGroupGap: CGFloat { HUDLayout.pageGroupGap * scale }
    var pillHeight: CGFloat { HUDLayout.pillHeight * scale }
    var pillGap: CGFloat { HUDLayout.pillGap * scale }
    var pillFontSize: CGFloat { 11 * scale }
    /// アイコンの縁（白い縁・黒い影）のぼかし
    var haloRadius: CGFloat { 1.2 * scale }

    /// 正方形の中の、マスの中心（中央のマスは円の中心）
    func position(ofCell index: Int) -> CGPoint {
        guard let position = RadialLayout.position(ofCell: index) else { return center }
        return CGPoint(x: center.x + position.x * scale, y: center.y + position.y * scale)
    }

    /// 左右の外へ出して止めているときの矢印の中心（円の縁の内側）
    func pageArrowPosition(_ edge: PageEdge) -> CGPoint {
        let offset = outerRadius - pageArrowRadius - 2 * scale
        return CGPoint(x: center.x + (edge == .right ? offset : -offset), y: center.y)
    }

    /// ページの点の中心（真ん中の鍵の下）
    var pageDotsPosition: CGPoint {
        CGPoint(x: center.x, y: center.y + HUDLayout.pageDotsOffset * scale)
    }

    /// 円を囲む正方形と、その下の帯（注意書き・「練習中」）の分。帯の有無で大きさを変えない（枠が動かない）
    func size(for model: HUDModel) -> CGSize {
        CGSize(width: circleSide, height: circleSide + pillGap + pillHeight)
    }
}

/// HUD の標準の寸法（倍率 1）。ポインタを中心にした円に、8つの鍵をアイコンだけで並べ、真ん中に 9つ目。皿も輪も文字も無い。
/// 形があるのは「いま向いているもの」の下の白い円だけ。位置は RadialLayout（NonetCore）と同じで、ポインタの向きと距離で選ぶ
enum HUDLayout {
    static let iconSize: CGFloat = 20
    static let centerIconSize: CGFloat = 18
    static let selectionRadius: CGFloat = 22
    static let pageArrowRadius: CGFloat = 13
    /// ページの点の、中心からの距離（真ん中の鍵の下）
    static let pageDotsOffset: CGFloat = 30
    static let pageGroupGap: CGFloat = 6
    /// 円の下の帯（試用期間の注意書き・「練習中」）
    static let pillHeight: CGFloat = 22
    static let pillGap: CGFloat = 8
    /// 白い円の光と、アイコンの縁を SwiftUI で描くための余白。ウィンドウの影は使わない
    static let shadowMargin: CGFloat = 28

    /// model.scale の倍率を掛けた大きさ
    static func size(for model: HUDModel) -> CGSize {
        HUDMetrics(scale: model.scale).size(for: model)
    }
}

/// 表示中の HUD の中身。update のたびにここだけを書き換え、ウィンドウやホスティングビューは作り直さない
@MainActor
@Observable
final class HUDStore {
    var model: HUDModel?
    /// 鍵ごとの色。出したときに下の画面を測って決める（測れなければ fallback）
    var inks = HUDInks.fallback
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
                HUDView(
                    model: model,
                    inks: store.inks,
                    increasedContrast: store.increasedContrast,
                    reduceMotion: store.reduceMotion
                )
            }
        }
        .padding(HUDLayout.shadowMargin)
    }
}

/// HUD。ポインタの周りの 8つの鍵と真ん中の鍵、左右の外へ出して止めているときの矢印とページの点、円の下の帯
struct HUDView: View {
    let model: HUDModel
    var inks: HUDInks = .fallback
    var increasedContrast = false
    var reduceMotion = false
    /// 少し長く止めるマスの進み具合を、この値（0〜1）で止めて描く（見た目の確認用）。nil なら止め始めてから duration で満たす
    var fixedHoldProgress: Double?

    var body: some View {
        let metrics = HUDMetrics(scale: model.scale)
        let size = metrics.size(for: model)
        let inFrame = model.isFingerInFrame
        // 2本以上の指・滑らせ直すまで: 光っているマスが無く、離しても何も起きない
        let idle = model.highlightedIndex == nil && !inFrame
        let dimmed = increasedContrast ? HUDInkPalette.dimmedOpacityIncreased : HUDInkPalette.dimmedOpacity
        ZStack(alignment: .topLeading) {
            ForEach(0..<Page.cellCount, id: \.self) { index in
                HUDKeyView(
                    cell: cell(at: index),
                    index: index,
                    isHighlighted: model.highlightedIndex == index,
                    isOnBoundary: model.highlightedIndex == index && model.isHighlightOnBoundary,
                    hold: model.hold?.cellIndex == index && model.highlightedIndex == index ? model.hold : nil,
                    ink: inks.ink(at: index),
                    metrics: metrics,
                    increasedContrast: increasedContrast,
                    reduceMotion: reduceMotion,
                    fixedHoldProgress: fixedHoldProgress
                )
                .position(metrics.position(ofCell: index))
            }
            .opacity(inFrame || idle ? dimmed : 1)
            if let paging = model.edgePaging {
                HUDPagingArrow(paging: paging, metrics: metrics, animates: !reduceMotion)
                    .position(metrics.pageArrowPosition(paging.edge))
                if model.pageCount > 1 {
                    HUDPageIndicator(
                        pageIndex: model.pageIndex,
                        pageCount: model.pageCount,
                        globalPagesStart: model.globalPagesStart,
                        metrics: metrics,
                        ink: inks.ink(at: RadialLayout.centerCell)
                    )
                    .position(metrics.pageDotsPosition)
                }
            }
            if let pill = HUDPillContent.content(for: model) {
                HUDPill(content: pill, metrics: metrics)
                    .frame(width: size.width, height: metrics.pillHeight)
                    .offset(y: metrics.circleSide + metrics.pillGap)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: inFrame)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(HUDAnnouncement.frameTitle(for: model)))
    }

    private func cell(at index: Int) -> HUDCell? {
        model.cells.indices.contains(index) ? model.cells[index] : nil
    }
}

/// 1つの鍵。アイコンだけ。光らせると（いま離すと実行する）下に白い円が出る。
/// 境目の線の上・少し長く止めている途中は白く塗らず、線だけで示す。空きマスは小さな点
struct HUDKeyView: View {
    let cell: HUDCell?
    let index: Int
    let isHighlighted: Bool
    /// 指が境目の線の上にあり、いま離しても実行しない。塗らずに、線だけで示す
    var isOnBoundary = false
    /// 光っている、少し長く止めるマスの進み具合。止め終えるまでは白く塗らず、円に沿って線を伸ばす
    var hold: HUDHold?
    var ink: HUDInk = .onLight
    var metrics = HUDMetrics(scale: 1)
    var increasedContrast = false
    var reduceMotion = false
    var fixedHoldProgress: Double?

    /// 白く塗る（いま指を離すと実行する）。少し長く止めるマスは止め終えてから。境目の線の上では塗らない
    private var isFilled: Bool {
        isHighlighted && !isOnBoundary && (hold?.isReady ?? true)
    }

    /// 少し長く止めるマスを止めている途中
    private var isHolding: Bool {
        isHighlighted && hold?.isReady == false
    }

    private var isCenter: Bool { index == RadialLayout.centerCell }

    var body: some View {
        let radius = metrics.selectionRadius
        let side = radius * 2
        ZStack {
            if let cell {
                if isFilled {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .white.opacity(0.9), radius: 6 * metrics.scale)
                        .shadow(color: .black.opacity(0.25), radius: 6 * metrics.scale, y: 2 * metrics.scale)
                }
                HUDGlyph(
                    icon: cell.icon,
                    size: isCenter ? metrics.centerIconSize : metrics.iconSize,
                    ink: ink,
                    onSelection: isFilled,
                    haloRadius: metrics.haloRadius,
                    strong: increasedContrast
                )
                if isHighlighted, isOnBoundary, !isHolding {
                    // 離しても実行しない。空きマスを指したときと同じ線で示す（白い塗り＝離すと実行、と食い違わない）
                    Circle().strokeBorder(ink.color.opacity(0.85), lineWidth: 1.5 * metrics.scale)
                }
                if isHolding, let hold {
                    HUDHoldRing(
                        hold: hold,
                        lineWidth: metrics.holdLineWidth,
                        color: ink.color,
                        animates: !reduceMotion,
                        fixedProgress: fixedHoldProgress
                    )
                }
            } else if isHighlighted {
                // 空きマスは実行しても何も起きないので、塗らずに線だけで示す
                Circle().strokeBorder(ink.color.opacity(0.85), style: StrokeStyle(lineWidth: 1.5 * metrics.scale, dash: [3 * metrics.scale, 3 * metrics.scale]))
                HUDEmptyDot(ink: ink, radius: metrics.emptyDotRadius, haloRadius: metrics.haloRadius)
            } else {
                // 空きマス: 小さな点だけ（「コントラストを上げる」では少し濃く）
                HUDEmptyDot(ink: ink, radius: metrics.emptyDotRadius, haloRadius: metrics.haloRadius)
                    .opacity(increasedContrast ? 0.8 : 0.5)
            }
        }
        .frame(width: side, height: side)
        .overlay(alignment: .topTrailing) {
            if cell?.requiresHold == true {
                HoldBadge(size: metrics.badgeSize, color: isFilled ? HUDInkPalette.onSelection.opacity(0.7) : ink.color)
                    .modifier(HUDHalo(ink: ink, radius: metrics.haloRadius, strong: false))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(HUDAnnouncement.cellDescription(cell, index: index)))
        .accessibilityValue(Text(HUDAnnouncement.cellValue(cell)))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// 空きマスの点
private struct HUDEmptyDot: View {
    let ink: HUDInk
    let radius: CGFloat
    let haloRadius: CGFloat

    var body: some View {
        Circle()
            .fill(ink.color)
            .frame(width: radius * 2, height: radius * 2)
            .modifier(HUDHalo(ink: ink, radius: haloRadius, strong: false))
    }
}

/// アイコン。明るい下地では濃い色に白い縁、暗い下地では白に黒い影。白い円の上では濃い色（縁は要らない）
struct HUDGlyph: View {
    let icon: CellIcon
    let size: CGFloat
    var ink: HUDInk = .onLight
    /// 白い円の上
    var onSelection = false
    var haloRadius: CGFloat = 1.2
    /// 「コントラストを上げる」: 縁を濃くする
    var strong = false

    var body: some View {
        CellIconView(icon, size: size)
            .fontWeight(.medium)
            .foregroundStyle(onSelection ? HUDInkPalette.onSelection : ink.color)
            .modifier(HUDHalo(ink: ink, radius: haloRadius, strong: strong, enabled: !onSelection))
            .accessibilityHidden(true)
    }
}

/// アイコンの縁。SwiftUI では文字や記号に縁取りを引けないので、同じ色の影を何枚か重ねて縁にする。
/// 明るい下地（濃いアイコン）は白い縁、暗い下地（白いアイコン）は黒い影
struct HUDHalo: ViewModifier {
    let ink: HUDInk
    let radius: CGFloat
    var strong = false
    var enabled = true

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else {
            switch ink {
            case .onLight:
                content
                    .shadow(color: .white, radius: radius)
                    .shadow(color: .white, radius: radius)
                    .shadow(color: .white.opacity(strong ? 1 : 0.9), radius: radius * (strong ? 1.6 : 1))
            case .onDark:
                content
                    .shadow(color: .black.opacity(0.9), radius: radius, y: 0.5)
                    .shadow(color: .black.opacity(strong ? 0.9 : 0.5), radius: radius * 2)
            }
        }
    }
}

/// 少し長く止めるマスの進み具合。白い円の縁に沿って線を伸ばし、一周したら（HUDHold.isReady）円が白くなる。
/// 「視差効果を減らす」では線を伸ばさず、点線で囲むだけにする（止め終えたら白くなるのは同じ）
struct HUDHoldRing: View {
    let hold: HUDHold
    let lineWidth: CGFloat
    var color = Color.white
    let animates: Bool
    let fixedProgress: Double?
    @State private var progress: CGFloat = 0

    var body: some View {
        let ring = Circle().inset(by: lineWidth / 2)
        ZStack {
            if let fixedProgress {
                ring.stroke(color.opacity(0.2), lineWidth: lineWidth)
                ring.trim(from: 0, to: CGFloat(min(max(fixedProgress, 0), 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            } else if animates {
                ring.stroke(color.opacity(0.2), lineWidth: lineWidth)
                ring.trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            } else {
                ring.stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: lineWidth * 0.6, dash: [lineWidth * 1.5, lineWidth * 1.5]))
            }
        }
        // 上から時計回りに一周する（進み具合が時計の針と同じ向きに伸びる）
        .rotationEffect(.degrees(-90))
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

/// 左右の外へ出して止めている間、その側の縁に出る矢印。周りの線が切り替えるまでの進み具合
struct HUDPagingArrow: View {
    let paging: HUDEdgePaging
    let metrics: HUDMetrics
    let animates: Bool

    var body: some View {
        let side = metrics.pageArrowRadius * 2
        ZStack {
            Circle()
                .fill(Color.white)
                .shadow(color: .white.opacity(0.9), radius: 5 * metrics.scale)
                .shadow(color: .black.opacity(0.25), radius: 4 * metrics.scale, y: 2 * metrics.scale)
            Image(systemName: paging.edge == .left ? "chevron.left" : "chevron.right")
                .font(.system(size: 11 * metrics.scale, weight: .bold))
                .foregroundStyle(HUDInkPalette.onSelection)
            HUDEdgePagingBar(paging: paging, color: HUDInkPalette.onSelection, animates: animates)
                .id(HUDEdgePagingBar.restartID(for: paging))
                .padding(2 * metrics.scale)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// 左右の外へ出して止めている間、ページを切り替えるまでの進み具合。矢印の円の縁に沿って線を伸ばす。
/// 「視差効果を減らす」では伸ばさず、点線で囲む。animates が false のときの線は、見た目の確認用の静止画
struct HUDEdgePagingBar: View {
    let paging: HUDEdgePaging
    var color = Color.white
    let animates: Bool
    /// この線を作った（止め始めた）時刻。呼び出し側が止め始めるたびに id を変えて作り直すので、そのたびに最初から数える
    @State private var startedAt = Date()

    var body: some View {
        let lineWidth: CGFloat = 2
        let ring = Circle().inset(by: lineWidth / 2)
        TimelineView(.animation(paused: !animates)) { context in
            ZStack {
                if animates {
                    ring.stroke(color.opacity(0.2), lineWidth: lineWidth)
                    ring.trim(from: 0, to: Self.progress(elapsed: context.date.timeIntervalSince(startedAt), duration: paging.duration))
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                } else {
                    ring.stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: lineWidth * 0.8, dash: [3, 3]))
                }
            }
        }
        .rotationEffect(.degrees(-90))
        .accessibilityHidden(true)
    }

    /// 止め始めてから elapsed 秒たったときの進み具合（0〜1）。duration が0以下なら、最初から満ちている
    static func progress(elapsed: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard duration.isFinite, elapsed.isFinite else { return 0 }
        guard duration > 0 else { return 1 }
        return CGFloat(min(max(elapsed / duration, 0), 1))
    }

    /// 線を作り直す目印。反対側に移ったときと、ページを切り替えて数え直すとき（since が変わる）に変わる。
    /// 状態を0に戻してからアニメーションで1にする書き方だと、同じ更新の中で0への書き込みが消え、満ちたまま残る
    static func restartID(for paging: HUDEdgePaging) -> String {
        "\(paging.edge)-\(paging.since)"
    }
}

/// 円の下の帯に出すもの。試用期間の注意書き（注意・知らせ）か「練習中」。文字はこれだけ
enum HUDPillContent: Equatable {
    case banner(String, HUDBannerStyle)
    case practice(String)

    static func content(for model: HUDModel) -> HUDPillContent? {
        if let banner = model.banner { return .banner(banner, model.bannerStyle) }
        if let note = HUDAnnouncement.topNote(for: model) { return .practice(note) }
        return nil
    }

    var text: String {
        switch self {
        case .banner(let text, _), .practice(let text): text
        }
    }

    var symbol: String? {
        switch self {
        case .banner(_, .warning): "exclamationmark.triangle.fill"
        case .banner(_, .info): "clock"
        case .practice: nil
        }
    }
}

/// 円の下の帯。下地を選ばないよう、白い不透明な面に濃い文字
private struct HUDPill: View {
    let content: HUDPillContent
    let metrics: HUDMetrics

    var body: some View {
        HStack(spacing: 5 * metrics.scale) {
            if let symbol = content.symbol {
                Image(systemName: symbol).accessibilityHidden(true)
            }
            Text(content.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.system(size: metrics.pillFontSize, weight: .semibold))
        .foregroundStyle(HUDInkPalette.onSelection)
        .padding(.horizontal, 10 * metrics.scale)
        .frame(height: metrics.pillHeight)
        .background(Capsule().fill(Color(white: 0.98)).shadow(color: .black.opacity(0.25), radius: 6 * metrics.scale, y: 3 * metrics.scale))
        .accessibilityElement(children: .combine)
    }
}

/// ページの点（左右の外へ出して止めている間だけ、真ん中の鍵の下に出す）。
/// アプリのページの後ろにグローバルのページをつなげたときは、その境目を少し離す
private struct HUDPageIndicator: View {
    let pageIndex: Int
    let pageCount: Int
    let globalPagesStart: Int?
    let metrics: HUDMetrics
    var ink: HUDInk = .onLight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<pageCount, id: \.self) { page in
                Circle()
                    .fill(page == pageIndex ? ink.color : ink.color.opacity(0.35))
                    .frame(width: metrics.dotSize, height: metrics.dotSize)
                    .padding(.leading, HUDPageDots.leadingSpace(before: page, globalPagesStart: globalPagesStart, metrics: metrics))
            }
        }
        .padding(.horizontal, 5 * metrics.scale)
        .padding(.vertical, 3 * metrics.scale)
        .background(Capsule().fill(ink == .onLight ? Color.white.opacity(0.85) : Color.black.opacity(0.55)))
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

    /// マスの VoiceOver の値。少し長く止めてから実行するマスなら、それを言う
    static func cellValue(_ cell: HUDCell?) -> String {
        HoldMark.accessibilityValue(requiresHold: cell?.requiresHold == true)
    }

    /// HUD 全体の呼び方: プロファイル名と、何に対する操作か（「Safari のウインドウ」。画面に置くページだけ）
    static func frameTitle(for model: HUDModel) -> String {
        guard let context = model.context, !context.isEmpty else { return model.title }
        return [model.title, context].joined(separator: String(localized: "、", bundle: .module))
    }

    /// 指が外枠にあるときの「離すとやめる」（読み上げ）
    static var cancelLabel: String {
        String(localized: "離すとやめる", bundle: .module)
    }

    /// 左右の外枠に指を止めているときに「離すとやめる」に添える文
    static func edgePagingLabel(_ edge: PageEdge) -> String {
        switch edge {
        case .left: String(localized: "止めると前のページ", bundle: .module)
        case .right: String(localized: "止めると次のページ", bundle: .module)
        }
    }

    /// 指が外枠にあるときに読む文。左右の外枠でそちらにページがあれば、止めるとページが変わることも言う
    static func frameLabel(in model: HUDModel) -> String {
        guard let edge = model.edgePaging?.edge else { return cancelLabel }
        return [cancelLabel, edgePagingLabel(edge)].joined(separator: String(localized: "、", bundle: .module))
    }

    /// 円の下の帯に出す一言。練習中だけ「練習中」。無ければ nil。
    /// 少し長く止めるマスの進み具合は、円の縁の線が見せる（文は VoiceOver にだけ読む）
    static func topNote(for model: HUDModel) -> String? {
        model.isPractice ? String(localized: "練習中", bundle: .module) : nil
    }

    /// 少し長く止めるマスを止めている途中（VoiceOver）
    static var holdWaiting: String {
        String(localized: "そのまま止めて待つ", bundle: .module)
    }

    /// 少し長く止めるマスを止め終えたとき（VoiceOver）
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
        let current = model.isFingerInFrame ? frameLabel(in: model) : highlighted(in: model)
        if !isNewPage, let hold = model.hold, hold.isReady, previous?.hold?.isReady != true, previous?.highlightedIndex == model.highlightedIndex {
            return holdReady
        }
        if isNewPage {
            let page = model.pageCount > 1
                ? String(localized: "\(model.title)、\(pageDescription(pageIndex: model.pageIndex, pageCount: model.pageCount))", bundle: .module)
                : model.title
            return [page, current].compactMap { $0 }.joined(separator: String(localized: "、", bundle: .module))
        }
        let before = previous.flatMap { $0.isFingerInFrame ? frameLabel(in: $0) : highlighted(in: $0) }
        guard before != current else { return nil }
        return current
    }
}

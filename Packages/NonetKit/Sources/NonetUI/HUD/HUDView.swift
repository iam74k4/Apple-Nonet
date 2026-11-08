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
    /// アイコンの下の暗い台の半径
    var plateRadius: CGFloat { HUDLayout.plateRadius * scale }
    /// 空きマスの小さな台の半径
    var emptyPlateRadius: CGFloat { HUDLayout.emptyPlateRadius * scale }
    /// 止めている途中・空きマスを光らせたときの線を、台の縁から内へ離す幅（線の外側にも台の暗さを残す）
    var ringInset: CGFloat { 2 * scale }
    /// 空きマスの点の半径
    var emptyDotRadius: CGFloat { 2 * scale }
    /// 少し長く止めるマスの進み具合の線の太さ
    var holdLineWidth: CGFloat { 2.5 * scale }
    /// 少し長く止めてから実行するマスの印（HoldBadge）の大きさ
    var badgeSize: CGFloat { 7 * scale }
    /// 外枠の帯に止めているときの矢印の円の半径
    var pageArrowRadius: CGFloat { HUDLayout.pageArrowRadius * scale }
    var dotSize: CGFloat { 4.5 * scale }
    var dotSpacing: CGFloat { 6 * scale }
    /// アプリのページとグローバルのページの点の間に、さらに空ける幅
    var pageGroupGap: CGFloat { HUDLayout.pageGroupGap * scale }
    var pillHeight: CGFloat { HUDLayout.pillHeight * scale }
    var pillGap: CGFloat { HUDLayout.pillGap * scale }
    var pillFontSize: CGFloat { 11 * scale }
    /// 向けたまま止めたアイコンの下に出す名前の帯
    var labelHeight: CGFloat { HUDLayout.labelHeight * scale }
    var labelGap: CGFloat { HUDLayout.labelGap * scale }
    var labelFontSize: CGFloat { 10.5 * scale }
    /// パネルの、円を囲む正方形の外の余白（帯とその影が入る大きさ）。帯は倍率に合わせて大きくなるので、余白も倍率に合わせる（1 より小さくはしない）
    var shadowMargin: CGFloat { HUDLayout.shadowMargin * max(scale, 1) }

    /// 正方形の中の、マスの中心（中央のマスは円の中心）
    func position(ofCell index: Int) -> CGPoint {
        guard let position = RadialLayout.position(ofCell: index) else { return center }
        return CGPoint(x: center.x + position.x * scale, y: center.y + position.y * scale)
    }

    /// 向けたまま止めたアイコンの名前の中心（白い円のすぐ下。above なら白い円のすぐ上）
    func labelPosition(ofCell index: Int, above: Bool = false) -> CGPoint {
        let key = position(ofCell: index)
        let offset = selectionRadius + labelGap + labelHeight / 2
        return CGPoint(x: key.x, y: above ? key.y - offset : key.y + offset)
    }

    /// 白い円のすぐ下に出した名前が、円の下の帯（pillFrame(below: true)）に重なるか（下の鍵）
    func labelOverlapsPillBelow(ofCell index: Int) -> Bool {
        labelPosition(ofCell: index).y + labelHeight / 2 > pillFrame(below: true).minY
    }

    /// 名前の帯の幅の上限: x を中心にして、パネル（円を囲む正方形と余白）からはみ出さない幅。長い名前は末尾を省く
    func labelMaxWidth(centeredAt x: CGFloat) -> CGFloat {
        max(2 * (min(x, circleSide - x) + shadowMargin) - 8 * scale, 40 * scale)
    }

    /// 外枠の帯に出して止めているときの矢印の中心（その側の円の縁の内側）
    func pageArrowPosition(_ edge: PageEdge) -> CGPoint {
        let offset = outerRadius - pageArrowRadius - 2 * scale
        return switch edge {
        case .right: CGPoint(x: center.x + offset, y: center.y)
        case .left: CGPoint(x: center.x - offset, y: center.y)
        case .down: CGPoint(x: center.x, y: center.y + offset)
        case .up: CGPoint(x: center.x, y: center.y - offset)
        }
    }

    /// ページの点の中心（真ん中の鍵の下）
    var pageDotsPosition: CGPoint {
        CGPoint(x: center.x, y: center.y + HUDLayout.pageDotsOffset * scale)
    }

    /// 円を囲む正方形。帯（注意書き・「練習中」）は枠の外（下か、下に入らなければ上）に描くので、枠の大きさと置き場所を変えない
    /// （帯の分だけ画面の下端で円が押し上げられることも、帯の有無で枠が動くことも無い）
    func size(for model: HUDModel) -> CGSize {
        CGSize(width: circleSide, height: circleSide)
    }

    /// 帯の枠（円を囲む正方形の座標）。below なら円の下、そうでなければ円の上
    func pillFrame(below: Bool) -> CGRect {
        let y = below ? circleSide + pillGap : -(pillGap + pillHeight)
        return CGRect(x: 0, y: y, width: circleSide, height: pillHeight)
    }
}

/// HUD の標準の寸法（倍率 1）。ポインタを中心にした円に、8つの鍵を並べ、真ん中に 9つ目。全体の皿も輪も文字も無い。
/// 鍵ごとに暗い丸い台（HUDPlate）に白いアイコンを載せ、「いま向いているもの」だけ白い円に濃いアイコンにする。
/// 位置は RadialLayout（NonetCore）と同じで、ポインタの向きと距離で選ぶ
enum HUDLayout {
    static let iconSize: CGFloat = 20
    static let centerIconSize: CGFloat = 18
    static let selectionRadius: CGFloat = 22
    /// アイコンの下の暗い台（直径 36）。光らせた白い円（直径 44）より小さく、向いているものが一回り大きく見える
    static let plateRadius: CGFloat = 18
    /// 空きマスの小さな台（直径 12）
    static let emptyPlateRadius: CGFloat = 6
    static let pageArrowRadius: CGFloat = 13
    /// ページの点の、中心からの距離（真ん中の鍵の下）
    static let pageDotsOffset: CGFloat = 30
    static let pageGroupGap: CGFloat = 6
    /// 円の外の帯（試用期間の注意書き・「練習中」）
    static let pillHeight: CGFloat = 22
    static let pillGap: CGFloat = 8
    /// 向けたまま止めたアイコンの名前: 同じアイコンにこれだけとどまったら、その下に名前の帯を出す
    /// （慣れた操作では離すまでに届かないので出ない。少し長く止めるマスの holdDwell 0.45 秒より後）
    static let labelDelay: TimeInterval = 0.6
    static let labelHeight: CGFloat = 18
    static let labelGap: CGFloat = 5
    /// 枠の外に描くもの（帯とその影、白い円の光、台の影）のための余白（倍率 1。倍率を掛けたものは HUDMetrics.shadowMargin）。
    /// ウィンドウの影は使わない。帯（pillGap + pillHeight = 30）とその影（下へ 3・ぼかし 6）が入る大きさ
    static let shadowMargin: CGFloat = 40

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
    /// システム設定の「コントラストを上げる」（出すたびに読み直す）
    var increasedContrast = false
    /// システム設定の「視差効果を減らす」（出すたびに読み直す）。外枠の切り替えをアニメーションにせず、進み具合も満たしていかない
    var reduceMotion = false
    /// システム設定の「透明度を下げる」（出すたびに読み直す）。台の下にガラスを敷かず、台を不透明にする
    var reduceTransparency = false
    /// 帯を円の下に出すか（画面の下端で入らなければ上に出す。HUDPlacement.pillFitsBelow）
    var pillBelow = true
    /// ページか層を切り替えたときに出ていく輪（押し出しの動き）。動き終えたら nil
    var turn: HUDTurn?
    /// 押し出しの進み具合（0〜1。時間に比例して進め、輪ごとのカーブは HUDMotion.turnFrame で付ける）。動いていなければ 1
    var turnProgress: Double = 1
    /// 層を切り替えたときに、真ん中の鍵の下へ一瞬出す層の名前（serial が変わるたびに出し直す）
    var layerName: HUDLayerName?
    private var turnSerial = 0

    /// 表示中の HUD のページか層が替わった: 前の輪を残して、切り替えた向きへ押し出す。層が替わったら、その名前も出す
    func beginTurn(from previous: HUDModel, to model: HUDModel) {
        guard let direction = model.lastTurn else { return }
        turnSerial += 1
        let serial = turnSerial
        turn = HUDTurn(outgoingCells: previous.cells, outgoingLayer: previous.layer, direction: direction, serial: serial)
        if previous.layer != model.layer {
            layerName = HUDLayerName(text: model.title, serial: serial)
        }
        // 0 から始め直してから、次の周回で 1 へ動かす（同じ更新の中で 0 と 1 を書くと、動かずに 1 のまま描かれる）
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { turnProgress = 0 }
        let animation = HUDMotion.turnAnimation(reduceMotion: reduceMotion)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.turn?.serial == serial else { return }
            withAnimation(animation) {
                self.turnProgress = 1
            } completion: { [weak self] in
                guard let self, self.turn?.serial == serial else { return }
                self.turn = nil
            }
        }
    }

    /// 新しく出す・閉じる: 動きの途中のものを捨てる
    func resetTurn() {
        turn = nil
        turnProgress = 1
        layerName = nil
    }
}

/// ページか層を切り替えたときに出ていく輪
struct HUDTurn: Equatable {
    /// 切り替える前のページのマス
    var outgoingCells: [HUDCell?]
    var outgoingLayer: HUDLayer?
    /// 切り替えた向き（その側から次の輪が入り、前の輪は反対へ抜ける）
    var direction: PageEdge
    /// 何回目の切り替えか（続けて切り替えたときに、前の動きの終わりで今の輪を消さないため）
    var serial: Int

    /// ページか層が替わったと見る目印（層・層の中のページの番号・題名）
    static func pageKey(_ model: HUDModel) -> String {
        "\(String(describing: model.layer))|\(model.pageIndex)|\(model.title)"
    }
}

/// 層を切り替えたときに出す層の名前
struct HUDLayerName: Equatable {
    var text: String
    var serial: Int
}

/// ページと層を切り替えるときの押し出しの動き。左右も上下も同じ動きで、違うのは向きだけ。
/// 前の輪は進む向きと反対へ少し縮みながら抜け、次の輪は進んだ側から少し大きめに入って落ち着く（減速して止まる）
enum HUDMotion {
    /// 全体の時間。「視差効果を減らす」では動かさず、reducedTurnDuration で入れ替えるだけ
    static let turnDuration: TimeInterval = 0.27
    static let reducedTurnDuration: TimeInterval = 0.12
    /// 輪が動く距離（倍率 1 のポイント）
    static let turnDistance: CGFloat = 36
    /// 縮み（出ていく輪）・膨らみ（入る輪）の割合
    static let turnScale = 0.04

    static func turnAnimation(reduceMotion: Bool) -> Animation {
        .linear(duration: reduceMotion ? reducedTurnDuration : turnDuration)
    }

    /// 進み具合 progress（時間に比例、0〜1）での、輪の位置（向きの単位ベクトルに掛ける。出ていく輪は負）・大きさ・不透明度。
    /// 出ていく輪は最初の 150ms で加速しながら抜け、入る輪は 40ms 遅れて 230ms で減速しながら入る
    static func turnFrame(progress: Double, isOutgoing: Bool, reduceMotion: Bool) -> (shift: Double, scale: Double, opacity: Double) {
        let t = min(max(progress.isFinite ? progress : 1, 0), 1)
        if reduceMotion { return isOutgoing ? (0, 1, 1 - t) : (0, 1, t) }
        let ms = t * turnDuration * 1000
        if isOutgoing {
            let a = easeIn(ms / 150)
            return (-a, 1 - turnScale * a, 1 - a)
        }
        let b = easeOut((ms - 40) / 230)
        return (1 - b, 1 + turnScale * (1 - b), b)
    }

    /// 向きの単位ベクトル（画面の座標。y は下向き）
    static func vector(_ edge: PageEdge) -> (dx: CGFloat, dy: CGFloat) {
        switch edge {
        case .right: (1, 0)
        case .left: (-1, 0)
        case .down: (0, 1)
        case .up: (0, -1)
        }
    }

    private static func easeIn(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t
    }

    private static func easeOut(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return 1 - pow(1 - t, 3)
    }
}

/// 押し出しの動きを、輪全体（9つの鍵）に掛ける。進み具合を SwiftUI のアニメーションで補間させる
struct HUDTurnEffect: ViewModifier, Animatable {
    var progress: Double
    let direction: PageEdge?
    let distance: CGFloat
    let isOutgoing: Bool
    let reduceMotion: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let frame = HUDMotion.turnFrame(progress: direction == nil ? 1 : progress, isOutgoing: isOutgoing, reduceMotion: reduceMotion)
        let vector: (dx: CGFloat, dy: CGFloat) = direction.map(HUDMotion.vector) ?? (0, 0)
        content
            .scaleEffect(frame.scale)
            .offset(x: vector.dx * distance * frame.shift, y: vector.dy * distance * frame.shift)
            .opacity(frame.opacity)
    }
}

/// パネルに置く根のビュー。影の余白の中に HUD を描く
struct HUDRootView: View {
    let store: HUDStore

    var body: some View {
        ZStack {
            if let model = store.model {
                HUDView(
                    model: model,
                    increasedContrast: store.increasedContrast,
                    reduceMotion: store.reduceMotion,
                    reduceTransparency: store.reduceTransparency,
                    pillBelow: store.pillBelow,
                    turn: store.turn,
                    turnProgress: store.turnProgress,
                    layerName: store.layerName
                )
            }
        }
        .padding(store.model.map { HUDMetrics(scale: $0.scale).shadowMargin } ?? HUDLayout.shadowMargin)
    }
}

/// HUD。ポインタの周りの 8つの鍵と真ん中の鍵、外枠の帯に止めているときの矢印とページの点、円の外の帯
struct HUDView: View {
    let model: HUDModel
    var increasedContrast = false
    var reduceMotion = false
    var reduceTransparency = false
    /// 帯を円の下に出すか（入らなければ上）
    var pillBelow = true
    /// ページか層を切り替えた直後の、出ていく輪と進み具合（HUDStore）
    var turn: HUDTurn?
    var turnProgress: Double = 1
    /// 層を切り替えたときに出す層の名前（HUDStore）
    var layerName: HUDLayerName?
    /// 少し長く止めるマスの進み具合を、この値（0〜1）で止めて描く（見た目の確認用）。nil なら止め始めてから duration で満たす
    var fixedHoldProgress: Double?
    /// 向けているアイコンの名前を待たずに出す（見た目の確認用。ふだんは HUDLayout.labelDelay 止まってから）
    var showsLabelImmediately = false

    /// 名前を出している鍵（向けたまま labelDelay とどまった）
    @State private var labeledIndex: Int?
    /// 層の名前を出している（layerName が届いてから layerNameDuration の間）
    @State private var showsLayerName = false

    /// 層を切り替えたときに、層の名前を出しておく秒数
    static let layerNameDuration: TimeInterval = 1.0

    /// 向けたまま止めたときに名前を出す鍵: 中身のあるマスを向けているとき（外枠・開いた直後・空きマスでは無い）
    static func labelCandidate(_ model: HUDModel) -> Int? {
        guard !model.isFingerInFrame, let index = model.highlightedIndex, labelText(model, index: index) != nil else { return nil }
        return index
    }

    /// 名前の帯に出す文（マスの名前だけ。押すキーは出さない）
    static func labelText(_ model: HUDModel, index: Int) -> String? {
        guard model.cells.indices.contains(index), let cell = model.cells[index], !cell.title.isEmpty else { return nil }
        return cell.title
    }

    /// 名前を出すまでの待ちを数え直す目印（別のアイコンへ移った・ページが替わった）
    static func labelTimerID(_ model: HUDModel) -> String? {
        labelCandidate(model).map { "\(model.pageIndex)|\(model.title)|\($0)" }
    }

    /// 鍵のアイコンを薄くする（離しても何も起きないことを見せる。台は薄くしない）: 外枠にいる・2本以上の指・滑らせ直すまで。
    /// 開いた直後（ポインタがまだ真ん中から出ていない）は、エンジンには外枠でも薄くしない: 開くたびに薄くなっては、選べないように見える
    static func dimsKeys(_ model: HUDModel) -> Bool {
        if model.isFingerInFrame { return !model.isWaitingAtCenter }
        return model.highlightedIndex == nil
    }

    var body: some View {
        let metrics = HUDMetrics(scale: model.scale)
        let size = metrics.size(for: model)
        let inFrame = model.isFingerInFrame && !model.isWaitingAtCenter
        // 押し出している間は、どちらの輪もガラスを外す（HUDPlateStyle.showsGlass）
        let plateStyle = HUDPlateStyle(increasedContrast: increasedContrast, reduceTransparency: reduceTransparency, isGlobalLayer: model.layer == .global, showsGlass: turn == nil)
        let dims = Self.dimsKeys(model)
        let distance = HUDMotion.turnDistance * metrics.scale
        // 向けたまま止めたアイコンの名前（出すときだけ）
        let keyLabel: (index: Int, text: String)? = (showsLabelImmediately ? Self.labelCandidate(model) : labeledIndex)
            .flatMap { index in index == Self.labelCandidate(model) ? Self.labelText(model, index: index).map { (index, $0) } : nil }
        ZStack(alignment: .topLeading) {
            // 切り替える前のページの輪（押し出されて抜けていく）。マスは光らせない
            if let turn {
                keyRing(cells: turn.outgoingCells, highlight: nil, hold: nil, dims: dims, metrics: metrics,
                        plateStyle: HUDPlateStyle(increasedContrast: increasedContrast, reduceTransparency: reduceTransparency, isGlobalLayer: turn.outgoingLayer == .global, showsGlass: false))
                    .modifier(HUDTurnEffect(progress: turnProgress, direction: turn.direction, distance: distance, isOutgoing: true, reduceMotion: reduceMotion))
            }
            keyRing(cells: model.cells, highlight: model.highlightedIndex, hold: model.hold, dims: dims, metrics: metrics, plateStyle: plateStyle)
                .modifier(HUDTurnEffect(progress: turn == nil ? 1 : turnProgress, direction: turn?.direction, distance: distance, isOutgoing: false, reduceMotion: reduceMotion))
            if let paging = model.edgePaging {
                HUDPagingArrow(paging: paging, metrics: metrics, animates: !reduceMotion)
                    .position(metrics.pageArrowPosition(paging.edge))
                // ページの点は、いまの層のページだけ。左右（ページ）で止めている間だけ出す
                if model.pageCount > 1, paging.edge == .left || paging.edge == .right {
                    HUDPageIndicator(
                        pageIndex: model.pageIndex,
                        pageCount: model.pageCount,
                        metrics: metrics,
                        plateStyle: plateStyle
                    )
                    .position(metrics.pageDotsPosition)
                }
            }
            // 層を切り替えた直後だけ、真ん中の鍵の下に層の名前（白い帯）。同じ場所にページの点・案内・真ん中の鍵の名前が出たら、そちらに譲る
            if showsLayerName, let layerName, !Self.isSpotUnderCenterTaken(model, inFrame: inFrame, keyLabel: keyLabel?.index) {
                HUDKeyLabel(text: layerName.text, metrics: metrics, maxWidth: metrics.labelMaxWidth(centeredAt: metrics.center.x))
                    .position(metrics.pageDotsPosition)
                    .transition(.opacity)
            }
            // 帯に止めても切り替える先が無い（ページが1つの層の左右・前面のアプリのページが無いときの上下）: 真ん中の鍵の下に、そのことを1行で
            if inFrame, let hint = model.edgeHint {
                HUDKeyLabel(text: hint, metrics: metrics, maxWidth: metrics.labelMaxWidth(centeredAt: metrics.center.x))
                    .position(metrics.pageDotsPosition)
                    .transition(.opacity)
            }
            if let pill = HUDPillContent.content(for: model) {
                let frame = metrics.pillFrame(below: pillBelow)
                HUDPill(content: pill, metrics: metrics)
                    .frame(width: frame.width, height: frame.height)
                    .offset(y: frame.minY)
            }
            // 向けたまま止めたアイコンの名前（白い円のすぐ下。円の下の帯に重なる下の鍵では、白い円のすぐ上）。動かせば消える
            if let keyLabel {
                let above = pillBelow && HUDPillContent.content(for: model) != nil && metrics.labelOverlapsPillBelow(ofCell: keyLabel.index)
                let position = metrics.labelPosition(ofCell: keyLabel.index, above: above)
                HUDKeyLabel(text: keyLabel.text, metrics: metrics, maxWidth: metrics.labelMaxWidth(centeredAt: position.x))
                    .position(position)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: inFrame)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: labeledIndex)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: showsLayerName)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.edgeHint)
        .task(id: layerName?.serial) {
            showsLayerName = false
            guard layerName != nil else { return }
            showsLayerName = true
            try? await Task.sleep(for: .seconds(Self.layerNameDuration))
            guard !Task.isCancelled else { return }
            showsLayerName = false
        }
        .task(id: Self.labelTimerID(model)) {
            labeledIndex = nil
            guard let index = Self.labelCandidate(model) else { return }
            try? await Task.sleep(for: .seconds(HUDLayout.labelDelay))
            guard !Task.isCancelled else { return }
            labeledIndex = index
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(HUDAnnouncement.frameTitle(for: model)))
    }

    /// 9つの鍵の輪。台のガラスは鍵ごとに描く（GlassEffectContainer でまとめると、まとめたガラスがアイコンや線より上に描かれて隠れる）
    private func keyRing(cells: [HUDCell?], highlight: Int?, hold: HUDHold?, dims: Bool, metrics: HUDMetrics, plateStyle: HUDPlateStyle) -> some View {
        let size = metrics.size(for: model)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<Page.cellCount, id: \.self) { index in
                HUDKeyView(
                    cell: cells.indices.contains(index) ? cells[index] : nil,
                    index: index,
                    isHighlighted: highlight == index,
                    hold: hold?.cellIndex == index && highlight == index ? hold : nil,
                    isDimmed: dims,
                    metrics: metrics,
                    plateStyle: plateStyle,
                    reduceMotion: reduceMotion,
                    fixedHoldProgress: fixedHoldProgress
                )
                .position(metrics.position(ofCell: index))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// 1つの鍵。暗い丸い台（HUDPlate）に白いアイコン。光らせると（いま離すと実行する）白い円に濃いアイコンになる。
/// 少し長く止めている途中は、台を白い円と同じ大きさにして、その内側に白い線を伸ばす（止め終えたら白い円）。
/// 空きマスは小さな台に点、光らせると大きな台に点線。下の画面が明るくても暗くても、いつも暗い台の上に白で描くので同じように読める。
/// 外枠などで薄くするときは、アイコン・点・印だけを薄くし、台はそのまま残す（HUDKeyPalette.dimmedIconOpacity）
struct HUDKeyView: View {
    let cell: HUDCell?
    let index: Int
    let isHighlighted: Bool
    /// 光っている、少し長く止めるマスの進み具合。止め終えるまでは白く塗らず、円に沿って線を伸ばす
    var hold: HUDHold?
    /// 離しても何も起きない（外枠・2本の指）: アイコンを薄くする（HUDView.dimsKeys）
    var isDimmed = false
    var metrics = HUDMetrics(scale: 1)
    var plateStyle = HUDPlateStyle()
    var reduceMotion = false
    var fixedHoldProgress: Double?

    /// 白く塗る（いま指を離すと実行する）。少し長く止めるマスは止め終えてから。境目の線の上では塗らない
    private var isFilled: Bool {
        isHighlighted && (hold?.isReady ?? true)
    }

    /// 少し長く止めるマスを止めている途中
    private var isHolding: Bool {
        isHighlighted && hold?.isReady == false
    }

    private var isCenter: Bool { index == RadialLayout.centerCell }

    /// アイコン・点・印の不透明度
    private var markOpacity: Double { isDimmed ? plateStyle.dimmedIconOpacity : 1 }

    var body: some View {
        let radius = metrics.selectionRadius
        let side = radius * 2
        ZStack {
            if let cell {
                if isFilled {
                    // 細い暗い縁: 明るい画面の上で、白い円が台の並びの穴に見えないように
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: metrics.scale))
                        .shadow(color: .white.opacity(0.9), radius: 6 * metrics.scale)
                        .shadow(color: .black.opacity(0.25), radius: 6 * metrics.scale, y: 2 * metrics.scale)
                        .opacity(markOpacity)
                } else {
                    // 止めている途中は白い円と同じ大きさにして、向いていることを見せる
                    HUDPlate(radius: isHolding ? radius : metrics.plateRadius, scale: metrics.scale, style: plateStyle)
                }
                HUDGlyph(
                    icon: cell.icon,
                    size: isCenter ? metrics.centerIconSize : metrics.iconSize,
                    onSelection: isFilled
                )
                .opacity(markOpacity)
                if isHolding, let hold {
                    // 線は台の縁から少し内側に引く（外側にも台の暗さが残り、明るい画面でも線が背景に溶けない）
                    HUDHoldRing(
                        hold: hold,
                        lineWidth: metrics.holdLineWidth,
                        animates: !reduceMotion,
                        fixedProgress: fixedHoldProgress
                    )
                    .padding(metrics.ringInset)
                }
            } else if isHighlighted {
                // 空きマスは実行しても何も起きないので、白く塗らずに大きな台と点線で示す
                HUDPlate(radius: radius, scale: metrics.scale, style: plateStyle)
                Circle().strokeBorder(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5 * metrics.scale, dash: [3 * metrics.scale, 3 * metrics.scale]))
                    .padding(metrics.ringInset)
                    .opacity(markOpacity)
                HUDEmptyDot(radius: metrics.emptyDotRadius)
                    .opacity(markOpacity)
            } else {
                // 空きマス: 小さな台に点（「コントラストを上げる」では点を少し濃く）
                HUDPlate(radius: metrics.emptyPlateRadius, scale: metrics.scale, style: plateStyle)
                HUDEmptyDot(radius: metrics.emptyDotRadius)
                    .opacity((plateStyle.increasedContrast ? 0.9 : 0.6) * markOpacity)
            }
        }
        .frame(width: side, height: side)
        .overlay(alignment: .topTrailing) {
            if cell?.requiresHold == true {
                // 印も小さな台に白で載せ、台の縁に重ねる
                HoldBadge(size: metrics.badgeSize, color: .white)
                    .opacity(markOpacity)
                    .padding(2.5 * metrics.scale)
                    .background(HUDPlate(radius: nil, scale: metrics.scale, style: plateStyle))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(HUDAnnouncement.cellDescription(cell, index: index)))
        .accessibilityValue(Text(HUDAnnouncement.cellValue(cell)))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// 空きマスの点（台の上なので白）
private struct HUDEmptyDot: View {
    let radius: CGFloat

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: radius * 2, height: radius * 2)
    }
}

/// アイコン。台の上では白、白い円の上では濃い色
struct HUDGlyph: View {
    let icon: CellIcon
    let size: CGFloat
    /// 白い円の上
    var onSelection = false

    var body: some View {
        CellIconView(icon, size: size)
            .fontWeight(.medium)
            .foregroundStyle(onSelection ? HUDKeyPalette.onSelection : Color.white)
            .accessibilityHidden(true)
    }
}

/// アイコンの下の暗い丸い台。半透明の暗い面に細い明るい縁と薄い影（濃さと下のガラスは HUDPlateStyle）。
/// 真っ白な画面の上でも白いアイコンとのコントラスト比が 4.5:1 を下回らない。
/// 縁は暗い画面で台の形を、影は明るい画面で台の浮きを見せる。radius が nil なら置かれた枠いっぱい（印の台）
struct HUDPlate: View {
    let radius: CGFloat?
    let scale: CGFloat
    var style = HUDPlateStyle()

    var body: some View {
        let circle = Circle()
            .fill(style.fill)
            .modifier(HUDPlateBlur(enabled: style.usesGlass))
            .overlay(Circle().strokeBorder(Color.white.opacity(style.borderOpacity), lineWidth: scale))
            .shadow(color: .black.opacity(0.25), radius: 3 * scale, y: scale)
        if let radius {
            circle.frame(width: radius * 2, height: radius * 2)
        } else {
            circle
        }
    }
}

/// macOS 26 以降は、台の下に Liquid Glass（HUDSurface.glass）を敷いて下の画面をぼかす（台を透ける文字や模様を読ませない）。
/// 暗さは上に塗る面だけで決める: .regular のガラスは下地に合わせて明るくも暗くもなり、台ごとに濃さが揃わないので、色を足さない .clear にする。
/// 「透明度を下げる」では敷かない（HUDPlateStyle.usesGlass）
private struct HUDPlateBlur: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled, #available(macOS 26, *) {
            content.glassEffect(.clear, in: Circle())
        } else {
            content
        }
    }
}

/// 少し長く止めるマスの進み具合。台の縁の内側に沿って白い線を伸ばし、一周したら（HUDHold.isReady）円が白くなる。
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

/// 外枠の帯に止めている間、その側の縁に出る矢印。周りの線が切り替えるまでの進み具合
struct HUDPagingArrow: View {
    let paging: HUDEdgePaging
    let metrics: HUDMetrics
    let animates: Bool

    /// 止めている側を指す矢印（SF Symbols）
    static func symbol(_ edge: PageEdge) -> String {
        switch edge {
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .up: "chevron.up"
        case .down: "chevron.down"
        }
    }

    var body: some View {
        let side = metrics.pageArrowRadius * 2
        ZStack {
            Circle()
                .fill(Color.white)
                .shadow(color: .white.opacity(0.9), radius: 5 * metrics.scale)
                .shadow(color: .black.opacity(0.25), radius: 4 * metrics.scale, y: 2 * metrics.scale)
            Image(systemName: HUDPagingArrow.symbol(paging.edge))
                .font(.system(size: 11 * metrics.scale, weight: .bold))
                .foregroundStyle(HUDKeyPalette.onSelection)
            HUDEdgePagingBar(paging: paging, color: HUDKeyPalette.onSelection, animates: animates)
                .id(HUDEdgePagingBar.restartID(for: paging))
                .padding(2 * metrics.scale)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// 外枠の帯に止めている間、ページか層を切り替えるまでの進み具合。矢印の円の縁に沿って線を伸ばす。
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

/// 向けたまま止めたアイコンの名前。帯と同じ白い不透明な面に濃い文字で、下地を選ばない。読み上げには同じ名前がすでにある
private struct HUDKeyLabel: View {
    let text: String
    let metrics: HUDMetrics
    /// 帯の幅の上限（HUDMetrics.labelMaxWidth）。長い名前は末尾を省き、パネルの端で切れないようにする
    let maxWidth: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: metrics.labelFontSize, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(HUDKeyPalette.onSelection)
            .padding(.horizontal, 8 * metrics.scale)
            .frame(height: metrics.labelHeight)
            .background(Capsule().fill(Color(white: 0.98)).shadow(color: .black.opacity(0.22), radius: 5 * metrics.scale, y: 2 * metrics.scale))
            .frame(maxWidth: maxWidth)
            .accessibilityHidden(true)
    }
}

extension HUDView {
    /// 真ん中の鍵の下（pageDotsPosition）に、層の名前より優先して出すものがある: 左右で止めているときのページの点、案内、真ん中の鍵の名前
    static func isSpotUnderCenterTaken(_ model: HUDModel, inFrame: Bool, keyLabel: Int?) -> Bool {
        let showsDots = model.pageCount > 1 && (model.edgePaging?.edge == .left || model.edgePaging?.edge == .right)
        return showsDots || (inFrame && model.edgeHint != nil) || keyLabel == RadialLayout.centerCell
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
        .foregroundStyle(HUDKeyPalette.onSelection)
        .padding(.horizontal, 10 * metrics.scale)
        .frame(height: metrics.pillHeight)
        .background(Capsule().fill(Color(white: 0.98)).shadow(color: .black.opacity(0.25), radius: 6 * metrics.scale, y: 3 * metrics.scale))
        .accessibilityElement(children: .combine)
    }
}

/// ページの点（左右の帯に止めている間だけ、真ん中の鍵の下に出す。いまの層のページだけ）。
/// アプリのページの後ろにグローバルのページをつなげたときは、その境目を少し離す
private struct HUDPageIndicator: View {
    let pageIndex: Int
    let pageCount: Int
    let metrics: HUDMetrics
    var plateStyle = HUDPlateStyle()

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<pageCount, id: \.self) { page in
                Circle()
                    .fill(page == pageIndex ? Color.white : Color.white.opacity(0.4))
                    .frame(width: metrics.dotSize, height: metrics.dotSize)
                    .padding(.leading, HUDPageDots.leadingSpace(before: page, globalPagesStart: nil, metrics: metrics))
            }
        }
        .padding(.horizontal, 5 * metrics.scale)
        .padding(.vertical, 3 * metrics.scale)
        // 鍵の台と同じ暗い面に白い点
        .background(Capsule().fill(plateStyle.fill))
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

    /// 外枠の帯に指を止めているときに「離すとやめる」に添える文
    static func edgePagingLabel(_ edge: PageEdge) -> String {
        switch edge {
        case .left: String(localized: "止めると前のページ", bundle: .module)
        case .right: String(localized: "止めると次のページ", bundle: .module)
        case .up: String(localized: "止めるとアプリのページへ", bundle: .module)
        case .down: String(localized: "止めるとグローバルのページへ", bundle: .module)
        }
    }

    /// 指が外枠にあるときに読む文。帯で止めるとページか層が変わるなら、そのことも言う（frameAddition）
    static func frameLabel(in model: HUDModel) -> String {
        guard let addition = frameAddition(in: model) else { return cancelLabel }
        return [cancelLabel, addition].joined(separator: String(localized: "、", bundle: .module))
    }

    /// 外枠の帯に止めているときに「離すとやめる」に続けて言うこと: 止めると切り替わる先か、切り替える先が無いことの案内（HUDModel.edgeHint）
    static func frameAddition(in model: HUDModel) -> String? {
        model.edgePaging.map { edgePagingLabel($0.edge) } ?? model.edgeHint
    }

    /// 外枠にいる（開いた直後のポインタが真ん中から出る前は除く。そのときは外枠扱いでも「離すとやめる」を言わない）
    private static func isInFrame(_ model: HUDModel) -> Bool {
        model.isFingerInFrame && !model.isWaitingAtCenter
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
    /// 外枠に入ったら「離すとやめる」（開いた直後のポインタが真ん中から出る前は、外枠扱いでも言わない）、外枠の中で帯の案内が変わったらその案内だけ、
    /// 少し長く止めるマスを止め終えたら「離すと実行」
    static func announcement(from previous: HUDModel?, to model: HUDModel) -> String? {
        let isNewPage = previous == nil || previous?.pageIndex != model.pageIndex || previous?.title != model.title
        let current = isInFrame(model) ? frameLabel(in: model) : highlighted(in: model)
        if !isNewPage, let hold = model.hold, hold.isReady, previous?.hold?.isReady != true, previous?.highlightedIndex == model.highlightedIndex {
            return holdReady
        }
        if isNewPage {
            let page = model.pageCount > 1
                ? String(localized: "\(model.title)、\(pageDescription(pageIndex: model.pageIndex, pageCount: model.pageCount))", bundle: .module)
                : model.title
            return [page, current].compactMap { $0 }.joined(separator: String(localized: "、", bundle: .module))
        }
        if let previous, isInFrame(previous), isInFrame(model) {
            // 外枠の中で帯の案内だけが変わった: 「離すとやめる」は読み直さず、新しい案内だけを言う（案内が消えただけなら言わない）
            let addition = frameAddition(in: model)
            return addition == frameAddition(in: previous) ? nil : addition
        }
        let before = previous.flatMap { isInFrame($0) ? frameLabel(in: $0) : highlighted(in: $0) }
        guard before != current else { return nil }
        return current
    }
}

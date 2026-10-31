// 担当: engine。押し間違いを防ぐ2つの決まり（docs/architecture.md「操作の仕様」）。
// 境界の帯（GridMapper.tapBoundaryBand）: すぐにタップの置いた位置が内側の線の近くなら実行しない。
// HUD で選ぶマス（SessionConfiguration.hudOnlyCells）: 速押しでは実行せず、そのマスを光らせた HUD を出す。
// 既定: hudDelay 0.3秒、placementWindow 0.6秒、1ページ
import Testing
import NonetCore

@Suite struct SessionEngineMisfireTests {
    static let fireModes: [FireMode] = [.onTriggerRelease, .onFingerLift]
    /// 縦の線（左の列と中央の列の間）と、横の線（上の行と中の行の間）
    static let verticalLine = 1.0 / 3
    static let horizontalLine = 2.0 / 3

    /// トリガーを押し、(x, y) を速押しした台本と、離したときの出力
    private func fastTap(x: Double, y: Double, _ configuration: SessionConfiguration) -> (SessionScenario, [SessionEffect]) {
        var s = SessionScenario(configuration)
        s.pressTrigger(at: 0)
        s.touch(x: x, y: y, at: 0.05)
        let lifted = s.lift(at: 0.1)
        return (s, lifted)
    }

    // MARK: - 境界の帯: 速押し

    @Test(arguments: fireModes)
    func aFastTapExactlyOnAVerticalLineRunsNothing(fireMode: FireMode) {
        var (s, lifted) = fastTap(x: Self.verticalLine, y: 0.5, SessionConfiguration(fireMode: fireMode))
        #expect(lifted.executions.isEmpty)
        #expect(lifted.hapticEvents == [.rejected])
        #expect(!lifted.showsHUD)
        #expect(s.engine.isInSession)
        // 実行しなかったので、迷っていれば (a) の HUD が出る（6 の「一度実行した後」ではない）
        #expect(s.tick(at: 0.6).showsHUD)
    }

    @Test(arguments: fireModes)
    func aFastTapExactlyOnAHorizontalLineRunsNothing(fireMode: FireMode) {
        let (_, lifted) = fastTap(x: 0.5, y: Self.horizontalLine, SessionConfiguration(fireMode: fireMode))
        #expect(lifted.executions.isEmpty)
        #expect(lifted.hapticEvents == [.rejected])
    }

    @Test(arguments: fireModes)
    func aFastTapInsideTheBandRunsNothingAndJustOutsideRunsTheCell(fireMode: FireMode) {
        let configuration = SessionConfiguration(fireMode: fireMode)
        for offset in [-0.02, 0.02] {
            let (_, inside) = fastTap(x: Self.verticalLine + offset, y: 0.5, configuration)
            #expect(inside.executions.isEmpty, "x \(Self.verticalLine + offset)")
            #expect(inside.hapticEvents == [.rejected])
            let (_, below) = fastTap(x: 0.5, y: Self.horizontalLine + offset, configuration)
            #expect(below.executions.isEmpty, "y \(Self.horizontalLine + offset)")
        }
        #expect(fastTap(x: Self.verticalLine - 0.03, y: 0.5, configuration).1.executions == [.execute(page: 0, cell: 3, wasFastTap: true)])
        #expect(fastTap(x: Self.verticalLine + 0.03, y: 0.5, configuration).1.executions == [.execute(page: 0, cell: 4, wasFastTap: true)])
        #expect(fastTap(x: 0.5, y: Self.horizontalLine + 0.03, configuration).1.executions == [.execute(page: 0, cell: 1, wasFastTap: true)])
        #expect(fastTap(x: 0.5, y: Self.horizontalLine - 0.03, configuration).1.executions == [.execute(page: 0, cell: 4, wasFastTap: true)])
    }

    /// 2本の線が交わる角（4つのマスが接する）も、どちらかの線の帯に入れば実行しない
    @Test(arguments: fireModes)
    func aFastTapWhereTwoLinesCrossRunsNothing(fireMode: FireMode) {
        let configuration = SessionConfiguration(fireMode: fireMode)
        let crossings: [(x: Double, y: Double)] = [
            (1.0 / 3, 2.0 / 3), (2.0 / 3, 2.0 / 3), (1.0 / 3, 1.0 / 3), (2.0 / 3, 1.0 / 3), (1.0 / 3 + 0.02, 2.0 / 3 - 0.02),
        ]
        for (x, y) in crossings {
            let (_, lifted) = fastTap(x: x, y: y, configuration)
            #expect(lifted.executions.isEmpty, "(\(x), \(y))")
            #expect(lifted.hapticEvents == [HapticEvent.rejected])
        }
        // 角のすぐ外（どちらの帯にも入らない）は、置いたマスを実行する
        #expect(fastTap(x: 1.0 / 3 + 0.03, y: 2.0 / 3 - 0.03, configuration).1.executions == [.execute(page: 0, cell: 4, wasFastTap: true)])
    }

    /// トラックパッドの縁は境界ではない
    @Test(arguments: fireModes)
    func theOuterEdgesAreNotBoundaries(fireMode: FireMode) {
        let configuration = SessionConfiguration(fireMode: fireMode)
        #expect(fastTap(x: 0.005, y: 0.995, configuration).1.executions == [.execute(page: 0, cell: 0, wasFastTap: true)])
        #expect(fastTap(x: 0.995, y: 0.005, configuration).1.executions == [.execute(page: 0, cell: 8, wasFastTap: true)])
        #expect(fastTap(x: 0.5, y: 1, configuration).1.executions == [.execute(page: 0, cell: 1, wasFastTap: true)])
        #expect(fastTap(x: 0, y: 0.5, configuration).1.executions == [.execute(page: 0, cell: 3, wasFastTap: true)])
    }

    /// 決めるのは置いた位置。帯に置いてからマスの中へ滑らせても実行しない
    @Test func theLandingPointDecidesEvenIfTheFingerSlidesOut() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(x: Self.verticalLine, y: 0.5, at: 0.05)
        s.touch(on: 4, at: 0.08)
        #expect(s.lift(at: 0.1).executions.isEmpty)
        #expect(s.log.hapticEvents == [.rejected])
    }

    @Test func aZeroBandRunsTheCellUnderTheLine() {
        let (_, lifted) = fastTap(x: Self.verticalLine, y: 0.5, SessionConfiguration(tapBoundaryBand: 0))
        #expect(lifted.executions == [.execute(page: 0, cell: 4, wasFastTap: true)])
    }

    /// トリガーを指より少し先に離した速押しも同じ
    @Test func aFastTapInTheBandAfterTheTriggerIsReleasedRunsNothing() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(x: 0.5, y: Self.horizontalLine, at: 0.05)
        #expect(s.releaseTrigger(at: 0.1).visible.isEmpty)
        let lifted = s.lift(at: 0.15)
        #expect(lifted.executions.isEmpty)
        #expect(lifted.hapticEvents == [.rejected])
        #expect(lifted.endReason == .released)
    }

    // MARK: - 境界の帯: HUD でのタップ

    @Test func aTapOnTheVisibleHUDInTheBandRunsNothingAndKeepsTheHUD() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.tick(at: 0.6)
        s.touch(x: Self.verticalLine, y: 0.5, at: 0.7)
        #expect(s.lift(at: 0.75).visible == [.haptic(.rejected), .updateHUD(page: 0, highlightedCell: nil)])
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: nil))
        // 帯の外をタップすれば、いつもどおりその場で実行する
        s.touch(x: Self.verticalLine + 0.03, y: 0.5, at: 0.9)
        #expect(s.lift(at: 0.95).visible == [.hideHUD, .execute(page: 0, cell: 4, wasFastTap: false)])
    }

    @Test func afterATapInTheBandReleasingTheTriggerCancels() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.tick(at: 0.6)
        s.touch(x: 0.5, y: Self.horizontalLine, at: 0.7)
        s.lift(at: 0.75)
        let released = s.releaseTrigger(at: 0.9)
        #expect(released.executions.isEmpty)
        #expect(released.endReason == .cancelled)
    }

    /// 「指を離したとき」でも、滑らせずにすぐ離したタップ（tapMaxDuration・tapMaxTravel）は帯なら実行しない
    @Test func aQuickTapOnTheVisibleHUDInTheBandRunsNothingWithFingerLift() {
        var s = SessionScenario(fireMode: .onFingerLift)
        s.pressTrigger(at: 0)
        s.tick(at: 0.6)
        s.touch(x: 0.5, y: Self.horizontalLine, at: 0.7)
        #expect(s.lift(at: 0.75).visible == [.haptic(.rejected), .updateHUD(page: 0, highlightedCell: nil)])
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: nil))
        s.touch(on: 4, at: 0.9)
        #expect(s.lift(at: 0.95).visible == [.hideHUD, .execute(page: 0, cell: 4, wasFastTap: false)])
    }

    /// ページを変えた後の HUD でも同じ
    @Test(arguments: fireModes)
    func theBandAppliesOnEveryPage(fireMode: FireMode) {
        var s = SessionScenario(SessionConfiguration(fireMode: fireMode, pageCount: 2))
        s.pressTrigger(at: 0)
        // 2本指で左へスワイプして次のページへ（HUD が出る）
        s.setFingers([(id: 1, x: 0.6, y: 0.5), (id: 2, x: 0.7, y: 0.5)], at: 0.05)
        s.setFingers([(id: 1, x: 0.4, y: 0.5), (id: 2, x: 0.5, y: 0.5)], at: 0.1)
        s.liftAll(at: 0.15)
        #expect(s.engine.hud == SessionHUDState(page: 1, highlightedCell: nil))
        s.touch(x: 2.0 / 3, y: 0.5, at: 0.3)
        let lifted = s.lift(at: 0.35)
        #expect(lifted.executions.isEmpty)
        #expect(lifted.hapticEvents == [.rejected])
        #expect(s.engine.hud == SessionHUDState(page: 1, highlightedCell: nil))
        s.touch(x: 2.0 / 3 + 0.03, y: 0.5, at: 0.5)
        #expect(s.lift(at: 0.55).executions == [.execute(page: 1, cell: 5, wasFastTap: false)])
    }

    // MARK: - 境界の帯: 滑らせて選ぶときは使わない

    /// 帯に置いても、止めて HUD で選べば実行する（ハイライトで選んだマスが見えている）
    @Test func restingInTheBandAndReleasingTheTriggerRunsTheHighlightedCell() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(x: Self.verticalLine, y: 0.5, at: 0.1)
        #expect(s.tick(at: 0.4).visible == [.showHUD(page: 0, highlightedCell: 4)])
        #expect(s.releaseTrigger(at: 0.6).executions == [.execute(page: 0, cell: 4, wasFastTap: false)])
    }

    @Test func slidingIntoTheBandAndReleasingTheTriggerRunsTheHighlightedCell() {
        var s = SessionScenario()
        s.pressTrigger(at: 0)
        s.touch(on: 3, at: 0.1)
        s.tick(at: 0.4)
        // ヒステリシスで 3 のまま
        s.touch(x: Self.verticalLine + 0.01, y: 0.5, at: 0.5)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: 3))
        #expect(s.releaseTrigger(at: 0.6).executions == [.execute(page: 0, cell: 3, wasFastTap: false)])
    }

    @Test func slidingIntoTheBandAndLiftingRunsTheHighlightedCellWithFingerLift() {
        var s = SessionScenario(fireMode: .onFingerLift)
        s.pressTrigger(at: 0)
        s.touch(on: 3, at: 0.1)
        s.tick(at: 0.4)
        s.touch(x: Self.verticalLine + 0.01, y: 0.5, at: 0.5)
        #expect(s.lift(at: 0.6).executions == [.execute(page: 0, cell: 3, wasFastTap: false)])
    }

    /// 「指を離したとき」で、帯に置いて tapMaxDuration 以上止めてから離せば、光っているマスを実行する
    @Test func aSlowLiftInTheBandRunsTheHighlightedCellWithFingerLift() {
        var s = SessionScenario(fireMode: .onFingerLift)
        s.pressTrigger(at: 0)
        s.tick(at: 0.6)
        s.touch(x: Self.verticalLine, y: 0.5, at: 0.7)
        #expect(s.lift(at: 0.7 + SessionConfiguration.tapMaxDuration).executions == [.execute(page: 0, cell: 4, wasFastTap: false)])
    }

    /// 角の長押しは滑らせて選ぶので、帯で離しても光っているマスを実行する
    @Test func aCornerHoldSlideThatEndsInTheBandStillRuns() {
        var s = SessionScenario()
        s.touch(x: 0.05, y: 0.95, at: 1)
        s.holdCorner(at: 1.4)
        s.touch(on: 4, at: 1.5)
        s.touch(x: Self.verticalLine + 0.01, y: 0.5, at: 1.55)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: 4))
        #expect(s.lift(at: 1.8).executions == [.execute(page: 0, cell: 4, wasFastTap: false)])
    }

    // MARK: - HUD で選ぶマス

    private func hudOnly(_ fireMode: FireMode = .onTriggerRelease, cells: Set<Int> = [8]) -> SessionScenario {
        SessionScenario(SessionConfiguration(fireMode: fireMode, hudOnlyCells: [cells]))
    }

    /// 速押しでは実行せず、そのマスを光らせた HUD を出す。触覚は実行しなかったことを知らせる rejected。セッションは続く
    @Test(arguments: fireModes)
    func aFastTapOnAHUDOnlyCellShowsTheHUDWithThatCellInsteadOfRunning(fireMode: FireMode) {
        var s = hudOnly(fireMode)
        s.pressTrigger(at: 0)
        s.touch(on: 8, at: 0.05)
        #expect(s.lift(at: 0.1).visible == [.showHUD(page: 0, highlightedCell: 8), .haptic(.rejected)])
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: 8))
        #expect(s.engine.isInSession)
        #expect(s.engine.isTriggerHeld)
        // 指を置かないまま時間がたっても光らせたまま
        s.tick(at: 5)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: 8))
        #expect(s.log.executions.isEmpty)
    }

    /// 速押しの続きでトリガーを離しても実行しない（いつもの「指を離してからトリガーを離すとやめる」）
    @Test(arguments: fireModes)
    func releasingTheTriggerWithoutTouchingAgainCancels(fireMode: FireMode) {
        var s = hudOnly(fireMode)
        s.pressTrigger(at: 0)
        s.touch(on: 8, at: 0.05)
        s.lift(at: 0.1)
        let released = s.releaseTrigger(at: 0.2)
        #expect(released.executions.isEmpty)
        #expect(released.contains(.hideHUD))
        #expect(released.endReason == .cancelled)
    }

    /// 光っているマスをもう一度タップすれば実行する（「指を離したとき」も、そのマスに触れて離せば実行する）
    @Test(arguments: fireModes)
    func tappingTheHighlightedCellAgainRunsIt(fireMode: FireMode) {
        var s = hudOnly(fireMode)
        s.pressTrigger(at: 0)
        s.touch(on: 8, at: 0.05)
        s.lift(at: 0.1)
        #expect(s.touch(on: 8, at: 0.4).visible.isEmpty)
        #expect(s.lift(at: 0.45).visible == [.hideHUD, .execute(page: 0, cell: 8, wasFastTap: false)])
        // セッションは続き、続けて速押しできる
        #expect(s.engine.isInSession)
        s.touch(on: 2, at: 0.6)
        #expect(s.lift(at: 0.65).executions == [.execute(page: 0, cell: 2, wasFastTap: true)])
    }

    @Test func restingOnTheCellAndReleasingTheTriggerRunsIt() {
        var s = hudOnly()
        s.pressTrigger(at: 0)
        s.touch(on: 8, at: 0.05)
        s.lift(at: 0.1)
        s.touch(on: 8, at: 0.3)
        let released = s.releaseTrigger(at: 0.8)
        #expect(released.executions == [.execute(page: 0, cell: 8, wasFastTap: false)])
        #expect(released.endReason == .released)
    }

    /// 別のマスに置けばハイライトはその指を追う。置いただけでは境界の触覚を鳴らさず、滑らせれば鳴らす
    @Test func placingAFingerOnAnotherCellMovesTheHighlightWithoutABoundaryTick() {
        var s = hudOnly()
        s.pressTrigger(at: 0)
        s.touch(on: 8, at: 0.05)
        s.lift(at: 0.1)
        #expect(s.touch(on: 4, at: 0.3).visible == [.updateHUD(page: 0, highlightedCell: 4)])
        #expect(s.touch(on: 5, at: 0.4).visible == [.updateHUD(page: 0, highlightedCell: 5), .haptic(.boundary)])
        #expect(s.releaseTrigger(at: 0.8).executions == [.execute(page: 0, cell: 5, wasFastTap: false)])
    }

    /// 指を置いて離したら（タップでなければ）、光らせていたマスにも戻らない
    @Test func liftingAFingerThatWasPlacedElsewhereClearsTheHighlight() {
        var s = hudOnly()
        s.pressTrigger(at: 0)
        s.touch(on: 8, at: 0.05)
        s.lift(at: 0.1)
        s.touch(on: 4, at: 0.3)
        s.lift(at: 0.8)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: nil))
        #expect(s.releaseTrigger(at: 1).executions.isEmpty)
    }

    /// HUD が出ていれば（HUD で選んでいるので）その場で実行する
    @Test(arguments: fireModes)
    func aHUDOnlyCellRunsFromTheVisibleHUD(fireMode: FireMode) {
        var s = hudOnly(fireMode)
        s.pressTrigger(at: 0)
        s.tick(at: 0.6)
        s.touch(on: 8, at: 0.7)
        #expect(s.lift(at: 0.75).visible == [.hideHUD, .execute(page: 0, cell: 8, wasFastTap: false)])
    }

    @Test func aHUDOnlyCellRunsBySlidingInTheHUD() {
        var s = hudOnly()
        s.pressTrigger(at: 0)
        s.touch(on: 4, at: 0.1)
        s.tick(at: 0.4)
        s.touch(on: 8, at: 0.5)
        #expect(s.releaseTrigger(at: 0.7).executions == [.execute(page: 0, cell: 8, wasFastTap: false)])
    }

    /// トリガーを指より少し先に離した速押しは、HUD で確かめられないので実行しない
    @Test func aFastTapOnAHUDOnlyCellAfterTheTriggerIsReleasedRunsNothing() {
        var s = hudOnly()
        s.pressTrigger(at: 0)
        s.touch(on: 8, at: 0.05)
        s.releaseTrigger(at: 0.1)
        let lifted = s.lift(at: 0.15)
        #expect(lifted.executions.isEmpty)
        #expect(lifted.hapticEvents == [.rejected])
        #expect(!lifted.showsHUD)
        #expect(lifted.endReason == .released)
    }

    @Test func otherCellsStillRunOnAFastTap() {
        var s = hudOnly()
        s.pressTrigger(at: 0)
        s.touch(on: 2, at: 0.05)
        #expect(s.lift(at: 0.1).visible == [.execute(page: 0, cell: 2, wasFastTap: true)])
    }

    /// HUD で選ぶマスはページごと。範囲外のページは、どのマスも速押しで実行する
    @Test func hudOnlyCellsArePerPage() {
        var s = SessionScenario(SessionConfiguration(pageCount: 2, hudOnlyCells: [[], [8]]))
        s.pressTrigger(at: 0)
        s.touch(on: 8, at: 0.05)
        #expect(s.lift(at: 0.1).executions == [.execute(page: 0, cell: 8, wasFastTap: true)])

        var missing = SessionScenario(SessionConfiguration(hudOnlyCells: []))
        missing.pressTrigger(at: 0)
        missing.touch(on: 8, at: 0.05)
        #expect(missing.lift(at: 0.1).executions == [.execute(page: 0, cell: 8, wasFastTap: true)])
    }

    /// 境界の帯が先: 帯に落ちたタップは、HUD で選ぶマスの側でも HUD を出さない
    @Test func theBandWinsOverAHUDOnlyCell() {
        var s = hudOnly(cells: [4])
        s.pressTrigger(at: 0)
        s.touch(x: Self.verticalLine, y: 0.5, at: 0.05)
        let lifted = s.lift(at: 0.1)
        #expect(lifted.visible == [.haptic(.rejected)])
        #expect(s.engine.hud == nil)
    }

    /// トリガーより前から休めている指が触れたままでも、光らせたマスは消えない
    @Test func aRestingThumbKeepsTheHighlight() {
        var s = hudOnly()
        s.touch(9, x: 0.5, y: 0.02, at: 0)
        s.pressTrigger(at: 1)
        s.touch(1, on: 8, at: 1.05)
        #expect(s.lift(1, at: 1.1).visible == [.showHUD(page: 0, highlightedCell: 8), .haptic(.rejected)])
        s.sendFrame(at: 1.2)
        s.touch(9, x: 0.505, y: 0.02, at: 1.3)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: 8))
        let released = s.releaseTrigger(at: 1.5)
        #expect(released.executions.isEmpty)
        #expect(released.endReason == .cancelled)
    }

    /// 休めている親指のほかに置いた指がハイライトを引き継ぐ。その指を離した後は、親指だけが触れていても光らせていたマスに戻らない
    @Test func aFingerPlacedBesideARestingThumbTakesOverTheHighlight() {
        var s = hudOnly()
        s.touch(9, x: 0.5, y: 0.02, at: 0)
        s.pressTrigger(at: 1)
        s.touch(1, on: 8, at: 1.05)
        s.lift(1, at: 1.1)
        s.touch(2, on: 4, at: 1.3)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: 4))
        // 止めてから離した（タップではない）: 選ぶのをやめたので何も光らない
        s.lift(2, at: 1.8)
        s.sendFrame(at: 1.9)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: nil))
        #expect(s.releaseTrigger(at: 2).executions.isEmpty)
    }

    /// 休めていた指を滑らせ始めたら、ハイライトはその指を追い、離しても光らせていたマスには戻らない
    @Test func aRestingFingerThatStartsSlidingTakesOverTheHighlight() {
        var s = hudOnly()
        s.setFingers([(id: 9, x: 0.5, y: 0.02), (id: 10, x: 0.9, y: 0.02)], at: 0)
        s.pressTrigger(at: 1)
        s.touch(1, on: 8, at: 1.05)
        s.lift(1, at: 1.1)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: 8))
        // 親指（9）を滑らせる: ふつうの指になり、ハイライトはその指を追う
        s.touch(9, x: 0.15, y: 0.15, at: 1.3)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: 6))
        // 離すと何も光らない。もう1本の休めている指だけが残っても、光らせていたマスには戻らない
        s.lift(9, at: 1.5)
        s.sendFrame(at: 1.6)
        #expect(s.engine.hud == SessionHUDState(page: 0, highlightedCell: nil))
        #expect(s.releaseTrigger(at: 1.8).executions.isEmpty)
    }

    /// 角の長押しは HUD で選ぶので、HUD で選ぶマスもそのまま実行する
    @Test func aCornerHoldRunsAHUDOnlyCell() {
        var s = hudOnly(cells: [4])
        s.touch(x: 0.05, y: 0.95, at: 1)
        s.holdCorner(at: 1.4)
        s.touch(on: 4, at: 1.5)
        #expect(s.lift(at: 1.8).executions == [.execute(page: 0, cell: 4, wasFastTap: false)])
    }
}

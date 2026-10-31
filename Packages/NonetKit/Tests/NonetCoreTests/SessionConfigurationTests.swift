import Testing
import NonetCore

@Suite struct SessionConfigurationTests {
    @Test func defaultsMatchTheSpec() {
        let configuration = SessionConfiguration()
        #expect(configuration.pageCount == 1)
        #expect(configuration.hysteresis == 0.03)
        #expect(configuration.frame == .cancelFrame)
        #expect(configuration.frameHysteresis == 0.015)
        #expect(configuration.swipeThreshold == 0.12)
        #expect(configuration.maxDuration == 20)
        #expect(configuration.liftDwell == 0.15)
        #expect(configuration.holdDwell == 0.6)
        #expect(configuration.boundaryBand == 0.025)
        // 中身のあるマスが分からなければ、空きマスの判断は controller に任せる
        #expect(configuration.occupiedCells == nil)
        #expect(configuration.holdCells == nil)
        #expect(configuration.sanitized == configuration)
    }

    /// 外枠の幅（仕様: 左右 7%・手前 10%・奥 12%）
    @Test func theCancelFrameMatchesTheSpec() {
        let frame = GridInsets.cancelFrame
        #expect(frame.left == 0.07)
        #expect(frame.right == 0.07)
        #expect(frame.bottom == 0.10)
        #expect(frame.top == 0.12)
        // 開いた瞬間の指（上の縁の帯から entryTravel 動いたところ）は、まだ上の外枠にいる
        #expect(frame.top >= EdgeSlideRecognizer.entryBandHeight + EdgeSlideRecognizer.entryTravel)
    }

    @Test func sanitizedFixesOutOfRangeValues() {
        let broken = SessionConfiguration(
            pageCount: 0,
            hysteresis: .nan,
            swipeThreshold: 0,
            maxDuration: -5,
            liftDwell: -1,
            holdDwell: .nan
        ).sanitized
        #expect(broken.pageCount == 1)
        #expect(broken.hysteresis == GridMapper.defaultHysteresis)
        #expect(broken.swipeThreshold == SessionConfiguration.defaultSwipeThreshold)
        #expect(broken.maxDuration == SessionConfiguration.defaultMaxDuration)
        #expect(broken.liftDwell == SessionConfiguration.defaultLiftDwell)
        #expect(broken.holdDwell == SessionConfiguration.defaultHoldDwell)

        let extreme = SessionConfiguration(pageCount: -3, hysteresis: 2, swipeThreshold: 4, maxDuration: .infinity).sanitized
        #expect(extreme.pageCount == 1)
        #expect(extreme.hysteresis == GridMapper.maxHysteresis)
        #expect(extreme.swipeThreshold == 1)
        #expect(extreme.maxDuration == SessionConfiguration.defaultMaxDuration)
    }

    /// 少し長く止めるマスは、ふつうのマスより短くしない
    @Test func theHoldDwellIsNeverShorterThanTheLiftDwell() {
        #expect(SessionConfiguration(liftDwell: 0.3, holdDwell: 0.1).sanitized.holdDwell == 0.3)
        #expect(SessionConfiguration(liftDwell: 0, holdDwell: 0).sanitized.holdDwell == 0)
    }

    /// 外枠のヒステリシスは、いちばん狭い外枠の半分で止める（外枠に出ても切り替わらなくならないように）
    @Test func theFrameHysteresisStaysInsideTheFrame() {
        let narrow = SessionConfiguration(frame: GridInsets(all: 0.02), frameHysteresis: 0.5).sanitized
        #expect(narrow.frameHysteresis == 0.01)
        #expect(SessionConfiguration(frame: .zero).sanitized.frameHysteresis == 0)
    }

    @Test func engineTreatsAZeroPageCountAsOnePage() {
        var s = SessionScenario(pageCount: 0)
        s.slideIn(at: 0)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.1)
        s.setFingers([(1, 0.4, 0.5), (2, 0.6, 0.5)], at: 0.15)
        #expect(s.engine.pageIndex == 0)
        // 1ページしか無いので、先へ行けなかったことだけを知らせる
        #expect(s.log.hapticEvents == [.activation, .rejected])
    }
}

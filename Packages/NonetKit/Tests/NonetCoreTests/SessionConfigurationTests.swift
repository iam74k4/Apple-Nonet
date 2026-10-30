import Testing
import NonetCore

@Suite struct SessionConfigurationTests {
    @Test func defaultsMatchTheSpec() {
        let configuration = SessionConfiguration()
        #expect(configuration.hudDelay == 0.3)
        #expect(configuration.placementWindow == 0.6)
        #expect(configuration.fireMode == .onTriggerRelease)
        #expect(configuration.pageCount == 1)
        #expect(configuration.hysteresis == 0.03)
        #expect(configuration.edgeInsets == .zero)
        #expect(configuration.swipeThreshold == 0.12)
        #expect(configuration.maxDuration == 20)
        // 中身のあるマスが分からなければ、空きマスの判断は controller に任せる
        #expect(configuration.occupiedCells == nil)
        #expect(configuration.sanitized == configuration)
    }

    @Test func buildsFromGlobalSettings() {
        let settings = GlobalSettings(fireMode: .onFingerLift, hudDelay: 0.45)
        let configuration = SessionConfiguration(settings: settings, pageCount: 3)
        #expect(configuration.hudDelay == 0.45)
        #expect(configuration.fireMode == .onFingerLift)
        #expect(configuration.pageCount == 3)
        #expect(configuration.swipeThreshold == SessionConfiguration.defaultSwipeThreshold)
        #expect(configuration.maxDuration == SessionConfiguration.defaultMaxDuration)
        #expect(SessionConfiguration(settings: settings, pageCount: 1, occupiedCells: [[0, 8]]).occupiedCells == [[0, 8]])
    }

    @Test func sanitizedFixesOutOfRangeValues() {
        let broken = SessionConfiguration(
            hudDelay: -1,
            pageCount: 0,
            hysteresis: .nan,
            swipeThreshold: 0,
            maxDuration: -5
        ).sanitized
        #expect(broken.hudDelay == SessionConfiguration.defaultHUDDelay)
        #expect(broken.pageCount == 1)
        #expect(broken.hysteresis == GridMapper.defaultHysteresis)
        #expect(broken.swipeThreshold == SessionConfiguration.defaultSwipeThreshold)
        #expect(broken.maxDuration == SessionConfiguration.defaultMaxDuration)

        let nonFinite = SessionConfiguration(hudDelay: .nan, swipeThreshold: .infinity, maxDuration: .infinity).sanitized
        #expect(nonFinite.hudDelay == SessionConfiguration.defaultHUDDelay)
        #expect(nonFinite.swipeThreshold == SessionConfiguration.defaultSwipeThreshold)
        #expect(nonFinite.maxDuration == SessionConfiguration.defaultMaxDuration)

        let extreme = SessionConfiguration(hudDelay: 30, pageCount: -3, hysteresis: 2, swipeThreshold: 4, maxDuration: 10).sanitized
        #expect(extreme.hudDelay == 10)
        #expect(extreme.pageCount == 1)
        #expect(extreme.hysteresis == GridMapper.maxHysteresis)
        #expect(extreme.swipeThreshold == 1)
    }

    @Test func zeroHudDelayIsKept() {
        #expect(SessionConfiguration(hudDelay: 0).sanitized.hudDelay == 0)
    }

    /// 指を置かないときの待ち時間は、指を止めたときの待ち時間より短くしない。壊れた値は既定に、maxDuration で止める
    @Test func thePlacementWindowIsNeverShorterThanTheHudDelay() {
        #expect(SessionConfiguration(hudDelay: 0.8).sanitized.placementWindow == 0.8)
        #expect(SessionConfiguration(hudDelay: 0.15).sanitized.placementWindow == 0.6)
        #expect(SessionConfiguration(placementWindow: .nan).sanitized.placementWindow == SessionConfiguration.defaultPlacementWindow)
        #expect(SessionConfiguration(placementWindow: -1).sanitized.placementWindow == SessionConfiguration.defaultPlacementWindow)
        #expect(SessionConfiguration(placementWindow: 30, maxDuration: 5).sanitized.placementWindow == 5)
        // 設定から作るときは、いつも既定の値（設定画面には出さない）
        #expect(SessionConfiguration(settings: GlobalSettings(hudDelay: 0.45), pageCount: 1).placementWindow == SessionConfiguration.defaultPlacementWindow)
    }

    @Test func engineTreatsAZeroPageCountAsOnePage() {
        var s = SessionScenario(pageCount: 0)
        s.pressTrigger(at: 0)
        s.setFingers([(1, 0.6, 0.5), (2, 0.8, 0.5)], at: 0.05)
        s.setFingers([(1, 0.4, 0.5), (2, 0.6, 0.5)], at: 0.1)
        #expect(s.engine.pageIndex == 0)
        // 1ページしか無いので、先へ行けなかったことだけを知らせる
        #expect(s.log.hapticEvents == [.rejected])
    }

    @Test func engineUsesTheSanitizedHudDelay() {
        var s = SessionScenario(SessionConfiguration(hudDelay: -2))
        #expect(s.pressTrigger(at: 0).tickRequests == [SessionConfiguration.defaultPlacementWindow])
        #expect(s.touch(on: 4, at: 0.1).tickRequests == [0.1 + SessionConfiguration.defaultHUDDelay])
    }
}

// 担当: engine（設定に足した HUD の大きさ。GlobalSettings.hudScale）の保存と読み込み
import Foundation
@testable import NonetCore
import Testing

@Suite("モデルの Codable: HUD の大きさ")
struct ModelHUDScaleCodingTests {
    @Test func theDefaultIsStandardAndTheFactorsGrow() {
        #expect(GlobalSettings().hudScale == .standard)
        #expect(HUDScale.allCases == [.standard, .large, .extraLarge])
        #expect(HUDScale.allCases.map(\.factor) == [1, 1.25, 1.5])
    }

    @Test("すべての値が往復する", arguments: HUDScale.allCases)
    func everyValueRoundTrips(_ scale: HUDScale) throws {
        let settings = GlobalSettings(haptics: .light, hudScale: scale)
        #expect(try ModelFixtures.roundTrip(settings) == settings)
    }

    /// 標準（既定）なら書かない。この設定より前の版と同じ書式のまま
    @Test func standardIsNotWrittenAndOtherValuesAre() throws {
        #expect(try ModelFixtures.jsonObject(GlobalSettings())["hudScale"] == nil)
        #expect(try ModelFixtures.jsonObject(GlobalSettings(hudScale: .large))["hudScale"] as? String == "large")
        #expect(try ModelFixtures.jsonObject(GlobalSettings(hudScale: .extraLarge))["hudScale"] as? String == "extraLarge")
    }

    @Test func anOldFileOrAnUnknownValueReadsAsStandard() throws {
        let old = #"{"isEnabled": true, "trigger": "rightCommand", "haptics": "light"}"#
        #expect(try ModelFixtures.decode(GlobalSettings.self, old).hudScale == .standard)
        let unknown = try ModelFixtures.decode(GlobalSettings.self, #"{"hudScale": "huge", "haptics": "strong"}"#)
        #expect(unknown == GlobalSettings(haptics: .strong))
    }
}

@MainActor
@Suite("HUD の使い始めの案内と試用期間の知らせ")
struct ControllerGuidanceTests {
    @Test func theBeginnerHintIsShownForTheFirstSessions() {
        #expect(HUDGuidance.showsBeginnerHint(sessionCount: 0))
        #expect(HUDGuidance.showsBeginnerHint(sessionCount: HUDGuidance.beginnerSessionLimit - 1))
        #expect(!HUDGuidance.showsBeginnerHint(sessionCount: HUDGuidance.beginnerSessionLimit))
    }

    @Test func theTrialReminderIsDueOnceADayInTheLastDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9)))
        let evening = morning.addingTimeInterval(12 * 3600)
        let nextMorning = morning.addingTimeInterval(24 * 3600)
        let days = HUDGuidance.trialReminderDays
        #expect(HUDGuidance.isTrialReminderDue(daysLeft: days, lastShown: nil, now: morning, calendar: calendar))
        #expect(HUDGuidance.isTrialReminderDue(daysLeft: 1, lastShown: nil, now: morning, calendar: calendar))
        #expect(!HUDGuidance.isTrialReminderDue(daysLeft: days + 1, lastShown: nil, now: morning, calendar: calendar))
        #expect(!HUDGuidance.isTrialReminderDue(daysLeft: days, lastShown: morning, now: evening, calendar: calendar))
        #expect(HUDGuidance.isTrialReminderDue(daysLeft: days, lastShown: evening, now: nextMorning, calendar: calendar))
        // 時計を戻した（前に知らせた時刻が未来）なら、今日はまだとみなす
        #expect(HUDGuidance.isTrialReminderDue(daysLeft: days, lastShown: nextMorning, now: morning, calendar: calendar))
    }

    @Test func theUserDefaultsStoreKeepsTheCountAndTheDate() throws {
        let suite = "NonetGuidanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsHUDGuidanceStore(defaults: defaults)
        #expect(store.hudSessionCount == 0)
        #expect(store.lastTrialReminder == nil)
        store.hudSessionCount = 3
        let date = Date(timeIntervalSinceReferenceDate: 815_000_000)
        store.lastTrialReminder = date
        let reopened = UserDefaultsHUDGuidanceStore(defaults: defaults)
        #expect(reopened.hudSessionCount == 3)
        #expect(reopened.lastTrialReminder == date)
        // 壊れた値は 0
        defaults.set(-5, forKey: UserDefaultsHUDGuidanceStore.hudSessionCountKey)
        #expect(reopened.hudSessionCount == 0)
    }
}

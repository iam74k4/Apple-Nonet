// 担当: core-model。トリガーキーで開いていた版の設定ファイルを、今の版で読む
import Foundation
@testable import NonetCore
import Testing

@Suite("モデルの Codable: トリガーキーの版の設定")
struct ModelLegacySettingsCodingTests {
    /// トリガーキー・実行のタイミング・HUD が出るまでの時間・トリガーを渡す・角の呼び出し（どれも前の版の項目）
    static let legacySettings = #"""
    {"isEnabled": false, "trigger": "rightOption", "fireMode": "onFingerLift", "hudDelay": 0.45,
     "hudPosition": "nearCursor", "autoSwitchProfiles": false, "appendGlobalPages": true, "haptics": "strong",
     "passTriggerToApps": false, "showExecutionToast": false, "cursorLock": "decouple", "touchActivation": "topLeft",
     "hudScale": "large"}
    """#

    /// 前の版の項目は読み飛ばし、ほかの項目はそのまま読む
    @Test func oldKeysAreIgnoredAndTheRestLoads() throws {
        let settings = try ModelFixtures.decode(GlobalSettings.self, Self.legacySettings)
        #expect(settings == GlobalSettings(isEnabled: false, hudPosition: .nearCursor, haptics: .strong, hudScale: .large))
    }

    /// 読み直して書くと、前の版の項目は残らない（前の版の Nonet は、無い項目を既定値で読む）
    @Test func oldKeysAreNotWrittenBack() throws {
        let settings = try ModelFixtures.decode(GlobalSettings.self, Self.legacySettings)
        let keys = Set(try ModelFixtures.jsonObject(settings).allKeys.compactMap { $0 as? String })
        for old in ["trigger", "fireMode", "hudDelay", "passTriggerToApps", "touchActivation", "autoSwitchProfiles", "appendGlobalPages", "showExecutionToast", "cursorLock"] {
            #expect(!keys.contains(old), "\(old)")
        }
    }

    /// 値の壊れた古い項目があっても、ほかの項目は読める
    @Test func brokenOldValuesDoNotMatter() throws {
        let json = #"{"trigger": 7, "fireMode": null, "hudDelay": "fast", "touchActivation": ["x"], "haptics": "light"}"#
        #expect(try ModelFixtures.decode(GlobalSettings.self, json) == GlobalSettings(haptics: .light))
    }

    /// 前の版の設定ファイルを丸ごと読める（HUD で選んだときだけ実行するマスは、少し長く止めてから実行するマスになる）
    @Test func aWholeOldConfigurationLoads() throws {
        let json = #"""
        {"version": 1,
         "settings": {"trigger": "function", "fireMode": "onTriggerRelease", "hudDelay": 0.3, "passTriggerToApps": true, "touchActivation": "topRight"},
         "profiles": [{"kind": {"type": "global"}, "pages": [{"cells": [
           {"title": "送信", "icon": {"type": "symbol", "symbol": "paperplane"}, "requiresHUD": true,
            "action": {"type": "keystroke", "keys": [{"type": "character", "character": "d", "modifiers": ["command", "shift"]}]}},
           null, null, null, null, null, null, null, null]}]}]}
        """#
        let configuration = try ModelFixtures.decode(NonetConfiguration.self, json)
        #expect(configuration.settings == GlobalSettings())
        let cell = try #require(configuration.profiles.first?.pages.first?.cells.first ?? nil)
        #expect(cell.requiresHold)
        // 書くときも同じ名前（requiresHUD）のまま
        #expect(try ModelFixtures.jsonObject(cell)["requiresHUD"] as? Bool == true)
    }

    /// 前の版の項目だけが違う設定ファイルは、保存して失われる中身があるとはみなさない（configuration.lossy-… を作らない）
    @Test func anOldFileIsNotCopiedAsLossy() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            let current = ModelFixtures.configuration(settings: GlobalSettings(haptics: .light)).validated()
            try store.save(current)
            // 前の版の Nonet が同じ設定に、トリガーキーの項目を足して書いた
            let data = try Data(contentsOf: store.fileURL)
            var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            var settings = try #require(object["settings"] as? [String: Any])
            settings["trigger"] = "rightOption"
            settings["fireMode"] = "onTriggerRelease"
            settings["hudDelay"] = 0.3
            settings["passTriggerToApps"] = true
            settings["touchActivation"] = "topLeft"
            object["settings"] = settings
            try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: store.fileURL)

            #expect(try store.load() == current)
            #expect(try ModelFixtures.fileNames(in: directory).allSatisfy { !$0.hasPrefix("configuration.lossy") })
            // 本当に失われる項目があれば、これまでどおり残す
            settings["futureSetting"] = 1
            object["settings"] = settings
            try JSONSerialization.data(withJSONObject: object).write(to: store.fileURL)
            _ = try store.load()
            #expect(try ModelFixtures.fileNames(in: directory).contains { $0.hasPrefix("configuration.lossy") })
        }
    }
}

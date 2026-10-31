// 担当: presets。押し間違えると困るマスを、HUD で選んだときだけ実行するようにしてあるか（Cell.requiresHold）
import Foundation
import Testing
@testable import NonetCore

@Suite struct PresetHUDOnlyTests {
    static func text(_ key: String.LocalizationValue) -> String {
        ModelFixtures.text(key)
    }

    /// HUD で選んだときだけ実行するマスの名前。ここに無いプリセットには1つも無い
    static var expected: [String: Set<String>] {
        [
            // 押し間違えると参加者みんなに見える（録画は参加者に知らされる）
            "us.zoom.xos": [text("ビデオ"), text("画面共有"), text("挙手"), text("録画")],
            "com.microsoft.teams2": [text("ビデオ"), text("画面共有")],
            // 送ったメールは取り消せない
            "com.apple.mail": [text("送信")],
            // ビルドフォルダを消すので、次のビルドが最初からになる
            "com.apple.dt.Xcode": [text("クリーン")],
            // 実行中のコマンドを止めてしまう
            "com.apple.Terminal": [text("中断")],
            // 選んだファイルをゴミ箱に入れる（ゴミ箱から戻せるが、押し間違えるとファイルが消えたように見える）
            "com.apple.finder": [text("ゴミ箱に入れる")],
        ]
    }

    static func holdTitles(_ preset: AppPreset) -> Set<String> {
        Set(preset.pages.flatMap(\.cells).compactMap { $0 }.filter(\.requiresHold).map(\.title))
    }

    @Test(arguments: PresetCapabilities.allCombinations)
    func riskyCellsAreHUDOnlyOnEveryMac(capabilities: PresetCapabilities) {
        for preset in PresetLibrary.apps(for: capabilities) {
            #expect(Self.holdTitles(preset) == Self.expected[preset.app.bundleID] ?? [], "\(preset.app.bundleID)")
        }
    }

    /// 会議のミュートは、咳や物音ですぐに切り替えたいので速押しで実行できる
    @Test(arguments: ["us.zoom.xos", "com.microsoft.teams2"])
    func muteStaysAFastTap(bundleID: String) throws {
        for capabilities in PresetCapabilities.allCombinations {
            let preset = try #require(PresetLibrary.preset(forBundleID: bundleID, capabilities: capabilities))
            let mute = try #require(preset.pages[0].cells.compactMap { $0 }.first { $0.title == Self.text("ミュート") })
            #expect(!mute.requiresHold)
        }
    }

    @Test func theLauncherHasNoHUDOnlyCells() {
        let installed = Set(PresetLibrary.launcherCandidates.map(\.bundleID))
        let global = PresetLibrary.makeGlobalProfile(installedBundleIDs: installed)
        #expect(global.pages.flatMap(\.cells).compactMap { $0 }.allSatisfy { !$0.requiresHold })
    }

    /// プリセットから作ったプロファイルにも引き継ぐ（初回起動・プロファイルを追加・プリセットに戻す）
    @Test func makeProfileKeepsTheFlag() throws {
        let preset = try #require(PresetLibrary.preset(forBundleID: "com.apple.mail"))
        let profile = preset.makeProfile()
        let send = try #require(profile.pages[0].cells[8])
        #expect(send.title == Self.text("送信"))
        #expect(send.requiresHold)
        #expect(profile.pages[0].cells.compactMap { $0 }.filter(\.requiresHold).count == 1)

        var configuration = NonetConfiguration(settings: GlobalSettings(), profiles: [Profile(kind: .global)])
        let id = configuration.addAppProfile(for: preset.app, preset: preset)
        #expect(configuration.profiles.first { $0.id == id }?.pages[0].cells[8]?.requiresHold == true)
    }

    /// すでにあるプロファイル（この設定より前に作ったもの）は変えない。読み込んでも印は付かない
    @Test func existingProfilesAreNotChanged() throws {
        let json = #"""
        {"id": "6F1A3C55-0D7B-4B0E-9C1B-1E6B3A0A8F11", "kind": {"type": "app", "app": {"bundleID": "com.apple.mail", "name": "Mail"}},
         "isEnabled": true,
         "pages": [{"cells": [null, null, null, null, null, null, null, null,
           {"title": "送信", "icon": {"type": "symbol", "symbol": "paperplane"},
            "action": {"type": "openURL", "url": "https://example.com"}}]}]}
        """#
        let profile = try ModelFixtures.decode(Profile.self, json)
        let send = try #require(profile.pages[0].cells[8])
        #expect(send.title == "送信")
        #expect(!send.requiresHold)
    }
}

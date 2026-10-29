// 担当: core-model。ConfigurationStore（保存・読み込み・バックアップ・壊れたファイル・移行・書き出し / 読み込み）
import Foundation
@testable import NonetCore
import Testing

@Suite("ConfigurationStore: 設定ファイル")
struct StoreFileTests {
    @Test("保存先は ~/Library/Application Support/Nonet/configuration.json")
    func locations() {
        let directory = ConfigurationStore.defaultDirectory
        #expect(directory.path(percentEncoded: false).hasSuffix("/Library/Application Support/Nonet/"))
        #expect(directory.hasDirectoryPath)
        let store = ConfigurationStore(directory: URL(filePath: "/tmp/x", directoryHint: .isDirectory))
        #expect(store.fileURL == URL(filePath: "/tmp/x/configuration.json"))
        #expect(store.backupFileURL.lastPathComponent == "configuration.backup.json")
    }

    @Test("ファイルもフォルダも無ければ nil")
    func loadWithoutFile() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            #expect(try ConfigurationStore(directory: directory).load() == nil)
            let missing = directory.appending(path: "a/b", directoryHint: .isDirectory)
            #expect(try ConfigurationStore(directory: missing).load() == nil)
        }
    }

    @Test("保存して読み込むと同じ設定になる。フォルダが無ければ作る")
    func saveAndLoad() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory.appending(path: "nested/Nonet", directoryHint: .isDirectory))
            var configuration = ModelFixtures.configuration(settings: GlobalSettings(trigger: .rightOption, hudDelay: 0.45))
            let safariID = configuration.profiles[1].id
            for (index, action) in ModelFixtures.allActions.prefix(9).enumerated() {
                configuration.setCell(ModelFixtures.cell("\(index)", action: action), at: CellAddress(page: 0, index: index), profileID: safariID)
            }
            try store.save(configuration)
            #expect(try store.load() == configuration)

            // 人が読める JSON（整形済み）
            let text = try String(contentsOf: store.fileURL, encoding: .utf8)
            #expect(text.contains("\n"))
            #expect(text.contains(#""type" : "keystroke""#))
        }
    }

    @Test("保存するのは validated() したもの、読み込みも validated() して返す")
    func saveAndLoadValidate() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            let broken = NonetConfiguration(settings: GlobalSettings(hudDelay: 5), profiles: [ModelFixtures.profile(ModelFixtures.safari)])
            try store.save(broken)
            let loaded = try #require(try store.load())
            #expect(loaded.profiles.first?.isGlobal == true)
            #expect(loaded.settings.hudDelay == 0.8)

            // 手で書き換えられた壊れたファイルも直して返す
            let hand = #"""
            {"version": 1, "settings": {"hudDelay": 0.01}, "profiles": [
              {"kind": {"type": "app", "app": {"bundleID": "a", "name": "A"}}},
              {"kind": {"type": "app", "app": {"bundleID": "a", "name": "A2"}}},
              {"kind": {"type": "global"}}, {"kind": {"type": "global"}}
            ]}
            """#
            try Data(hand.utf8).write(to: store.fileURL)
            let repaired = try #require(try store.load())
            #expect(repaired.settings.hudDelay == 0.15)
            #expect(repaired.profiles.map(\.name) == ["グローバル", "A"])
        }
    }

    @Test("保存すると直前の版を configuration.backup.json に残す。同じ中身なら書かない")
    func backup() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            let first = ModelFixtures.configuration()
            var second = first
            second.settings.haptics = .off
            var third = second
            third.settings.trigger = .rightShift

            try store.save(first)
            #expect(!FileManager.default.fileExists(atPath: store.backupFileURL.path(percentEncoded: false)))

            try store.save(second)
            #expect(try Self.decode(store.backupFileURL) == first)
            #expect(try store.load() == second)

            // 同じ中身の保存では、バックアップは直前の版（first）のまま
            try store.save(second)
            #expect(try Self.decode(store.backupFileURL) == first)

            try store.save(third)
            #expect(try Self.decode(store.backupFileURL) == second)
            #expect(try store.load() == third)
            #expect(try ModelFixtures.fileNames(in: directory) == ["configuration.backup.json", "configuration.json"])
        }
    }

    @Test("壊れたファイルは configuration.corrupt-<日時>.json に移してから、説明つきのエラーを投げる", arguments: [
        "これは JSON ではない",
        "",
        "[1, 2, 3]",
        #""text""#,
        #"{"version": "one"}"#,
        #"{"version": 0, "profiles": []}"#,
        #"{"version": -3}"#,
        #"{"version": 1, "profiles": "none"}"#,
        #"{"version": 1, "profiles": [{"kind": {"type": "global"}}]"#,
    ])
    func corruptFileIsMovedAside(_ contents: String) throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            try Data(contents.utf8).write(to: store.fileURL)

            let error = #expect(throws: ConfigurationStoreError.self) { try store.load() }
            guard case .corrupted(let movedTo?, let reason)? = error else {
                Issue.record("corrupted(movedTo:) ではない: \(String(describing: error))")
                return
            }
            #expect(!reason.isEmpty)
            #expect(movedTo.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
            #expect(movedTo.lastPathComponent.hasPrefix("configuration.corrupt-"))
            #expect(movedTo.pathExtension == "json")
            #expect(try Data(contentsOf: movedTo) == Data(contents.utf8))
            #expect(!FileManager.default.fileExists(atPath: store.fileURL.path(percentEncoded: false)))
            #expect(error?.errorDescription?.contains(movedTo.lastPathComponent) == true)

            // 退避した後は「ファイルが無い」状態。保存しても退避したファイルには触れない
            #expect(try store.load() == nil)
            try store.save(ModelFixtures.configuration())
            #expect(try Data(contentsOf: movedTo) == Data(contents.utf8))
            #expect(!FileManager.default.fileExists(atPath: store.backupFileURL.path(percentEncoded: false)))
        }
    }

    @Test("続けて壊れても、退避したファイルを上書きしない")
    func repeatedCorruption() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            var moved: [URL] = []
            for index in 0..<3 {
                try Data("broken \(index)".utf8).write(to: store.fileURL)
                let error = #expect(throws: ConfigurationStoreError.self) { try store.load() }
                if case .corrupted(let url?, _)? = error {
                    moved.append(url)
                }
            }
            #expect(Set(moved).count == 3)
            for (index, url) in moved.enumerated() {
                #expect(try String(contentsOf: url, encoding: .utf8) == "broken \(index)")
            }
        }
    }

    @Test("読めない（フォルダになっている）ファイルは readFailed で、手を付けない")
    func unreadableFile() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: false)
            let error = #expect(throws: ConfigurationStoreError.self) { try store.load() }
            if case .readFailed? = error {} else {
                Issue.record("readFailed ではない: \(String(describing: error))")
            }
            #expect(try ModelFixtures.fileNames(in: directory) == ["configuration.json"])
        }
    }

    @Test("読む権限の無いファイルは readFailed。保存でも上書きしない")
    func unreadableFileIsNotOverwritten() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            let original = try ModelFixtures.encode(ModelFixtures.configuration())
            try original.write(to: store.fileURL)
            let path = store.fileURL.path(percentEncoded: false)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

            let loadError = #expect(throws: ConfigurationStoreError.self) { try store.load() }
            if case .readFailed? = loadError {} else {
                Issue.record("readFailed ではない: \(String(describing: loadError))")
            }
            let saveError = #expect(throws: ConfigurationStoreError.self) { try store.save(NonetConfiguration(profiles: [])) }
            if case .writeFailed? = saveError {} else {
                Issue.record("writeFailed ではない: \(String(describing: saveError))")
            }

            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
            #expect(try Data(contentsOf: store.fileURL) == original)
            #expect(try ModelFixtures.fileNames(in: directory) == ["configuration.json"])
        }
    }

    @Test("保存できないときは writeFailed")
    func saveFailure() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let blocker = directory.appending(path: "file")
            try Data("x".utf8).write(to: blocker)
            let store = ConfigurationStore(directory: blocker.appending(path: "Nonet", directoryHint: .isDirectory))
            let error = #expect(throws: ConfigurationStoreError.self) { try store.save(ModelFixtures.configuration()) }
            if case .writeFailed? = error {} else {
                Issue.record("writeFailed ではない: \(String(describing: error))")
            }
        }
    }

    @Test("新しい版のファイルは分かる範囲で読み、原本を configuration.v<版>.json に残す")
    func newerVersion() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            let store = ConfigurationStore(directory: directory)
            let future = #"""
            {"version": 2, "settings": {"trigger": "rightShift", "newThing": 1}, "profiles": [
              {"kind": {"type": "global"}, "pages": [{"cells": [
                {"title": "未来", "action": {"type": "hologram"}},
                {"title": "今", "action": {"type": "openURL", "url": "https://a.example"}}
              ]}]},
              {"kind": {"type": "website"}}
            ]}
            """#
            try Data(future.utf8).write(to: store.fileURL)

            let configuration = try #require(try store.load())
            #expect(configuration.version == 1)
            #expect(configuration.settings.trigger == .rightShift)
            #expect(configuration.profiles.count == 1)
            #expect(configuration.globalProfile.modelTitles[0][0...1] == [nil, "今"])

            let preserved = directory.appending(path: "configuration.v2.json")
            #expect(try String(contentsOf: preserved, encoding: .utf8) == future)

            // 2回目以降は最初の原本を残す
            try store.save(configuration)
            try Data(future.replacingOccurrences(of: "rightShift", with: "function").utf8).write(to: store.fileURL)
            _ = try store.load()
            #expect(try String(contentsOf: preserved, encoding: .utf8) == future)
        }
    }

    static func decode(_ url: URL) throws -> NonetConfiguration {
        try ModelJSON.makeDecoder().decode(NonetConfiguration.self, from: Data(contentsOf: url))
    }
}

@Suite("ConfigurationStore: 版の移行")
struct StoreMigrationTests {
    @Test("版が無ければ 1、整数でない・1未満は読めない")
    func versionProbe() throws {
        #expect(try ConfigurationMigration.version(of: Data("{}".utf8)) == 1)
        #expect(try ConfigurationMigration.version(of: Data(#"{"version": 3}"#.utf8)) == 3)
        #expect(throws: ConfigurationMigration.Failure.unreadable) {
            try ConfigurationMigration.version(of: Data(#"{"version": "1"}"#.utf8))
        }
        #expect(throws: ConfigurationMigration.Failure.unreadable) {
            try ConfigurationMigration.version(of: Data("[]".utf8))
        }
        #expect(throws: ConfigurationMigration.Failure.invalidVersion(0)) {
            try ConfigurationMigration.version(of: Data(#"{"version": 0}"#.utf8))
        }
    }

    @Test("手順を版の順に1つずつ当て、版を書き換える")
    func upgradeAppliesStepsInOrder() throws {
        let steps: [Int: ConfigurationMigration.Step] = [
            1: { object in
                var object = object
                object["log"] = ((object["log"] as? [Int]) ?? []) + [1]
                return object
            },
            2: { object in
                var object = object
                object["log"] = ((object["log"] as? [Int]) ?? []) + [2]
                return object
            },
        ]
        let data = try ConfigurationMigration.upgrade(Data(#"{"version": 1}"#.utf8), from: 1, to: 3, steps: steps)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["log"] as? [Int] == [1, 2])
        #expect(object["version"] as? Int == 3)

        let fromTwo = try ConfigurationMigration.upgrade(Data(#"{"version": 2}"#.utf8), from: 2, to: 3, steps: steps)
        let objectFromTwo = try #require(JSONSerialization.jsonObject(with: fromTwo) as? [String: Any])
        #expect(objectFromTwo["log"] as? [Int] == [2])
    }

    @Test("今の版以上ならそのまま。手順が欠けていれば失敗")
    func upgradeEdgeCases() throws {
        let data = Data(#"{"version": 1, "x": 1}"#.utf8)
        #expect(try ConfigurationMigration.upgrade(data, from: 1, to: 1, steps: [:]) == data)
        #expect(try ConfigurationMigration.upgrade(data, from: 4, to: 1, steps: [:]) == data)
        #expect(throws: ConfigurationMigration.Failure.missingStep(from: 2)) {
            try ConfigurationMigration.upgrade(data, from: 1, to: 3, steps: [1: { $0 }])
        }
    }

    @Test("古い版のファイルを移行してから読む（v0 → v1 の手順があったとして）")
    func decodeOldVersionThroughMigration() throws {
        // 仮の v0: トリガーキーを "triggerKey" に、プロファイルを "boards" に書いていた
        let old = #"""
        {"version": 0, "settings": {"triggerKey": "rightShift"}, "boards": [{"kind": {"type": "global"}}]}
        """#
        let steps: [Int: ConfigurationMigration.Step] = [
            0: { object in
                var object = object
                var settings = object["settings"] as? [String: Any] ?? [:]
                settings["trigger"] = settings.removeValue(forKey: "triggerKey")
                object["settings"] = settings
                object["profiles"] = object.removeValue(forKey: "boards")
                return object
            },
        ]
        // 版 0 は 1 未満なので、そのままでは読めない
        #expect(throws: ConfigurationMigration.Failure.invalidVersion(0)) {
            try ConfigurationStore.decodeConfiguration(from: Data(old.utf8), currentVersion: 1, steps: steps)
        }

        let v1 = old.replacingOccurrences(of: #""version": 0"#, with: #""version": 1"#)
        let (configuration, fileVersion) = try ConfigurationStore.decodeConfiguration(
            from: Data(v1.utf8), currentVersion: 2, steps: [1: try #require(steps[0])]
        )
        #expect(fileVersion == 1)
        #expect(configuration.version == 2)
        #expect(configuration.settings.trigger == .rightShift)
        #expect(configuration.profiles.map(\.isGlobal) == [true])
    }

    @Test("移行の手順が欠けている古いファイルは壊れたものとして退避する")
    func missingStepIsCorrupt() throws {
        try ModelFixtures.withTemporaryDirectory { directory throws in
            // 今の版が 1 なので、版 0 は移行できない
            let store = ConfigurationStore(directory: directory)
            try Data(#"{"version": 0}"#.utf8).write(to: store.fileURL)
            let error = #expect(throws: ConfigurationStoreError.self) { try store.load() }
            guard case .corrupted(let movedTo?, _)? = error else {
                Issue.record("corrupted ではない: \(String(describing: error))")
                return
            }
            #expect(FileManager.default.fileExists(atPath: movedTo.path(percentEncoded: false)))
        }
    }
}

@Suite("ConfigurationStore: プロファイルの書き出しと読み込み")
struct StoreProfileDocumentTests {
    @Test("書き出したものを読み込むと中身は同じで、id はすべて新しい")
    func exportImportRoundTrip() throws {
        var configuration = ModelFixtures.configuration()
        let xcodeID = configuration.profiles[2].id
        for (index, action) in ModelFixtures.allActions.prefix(9).enumerated() {
            configuration.setCell(ModelFixtures.cell("\(index)", action: action), at: CellAddress(page: 1, index: index), profileID: xcodeID)
        }
        let original = configuration.profiles

        let data = try ConfigurationStore.exportData(profiles: original)
        let imported = try ConfigurationStore.importProfiles(from: data)

        #expect(imported.count == original.count)
        for (a, b) in zip(imported, original) {
            #expect(a.kind == b.kind)
            #expect(a.isEnabled == b.isEnabled)
            #expect(a.modelTitles == b.modelTitles)
            #expect(a.pages.map { $0.cells.map { $0?.action } } == b.pages.map { $0.cells.map { $0?.action } })
            #expect(a.pages.map { $0.cells.map { $0?.icon } } == b.pages.map { $0.cells.map { $0?.icon } })
            #expect(a.id != b.id)
        }
        let importedCellIDs = Set(imported.flatMap { $0.pages.flatMap { $0.cells.compactMap { $0?.id } } })
        #expect(importedCellIDs.isDisjoint(with: Set(configuration.modelCellIDs)))
        #expect(importedCellIDs.count == configuration.modelCellIDs.count)
    }

    @Test("書き出しの書式: format・version・exportedAt・profiles")
    func exportFormat() throws {
        let data = try ConfigurationStore.exportData(profiles: [ModelFixtures.profile(ModelFixtures.safari)])
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["format"] as? String == "com.iam74k4.Nonet.profiles")
        #expect(object["version"] as? Int == 1)
        let exportedAt = try #require(object["exportedAt"] as? String)
        #expect(ISO8601DateFormatter().date(from: exportedAt) != nil)
        #expect((object["profiles"] as? [Any])?.count == 1)
        #expect(ConfigurationStore.profileDocumentExtension == "nonetprofile")
    }

    @Test("書き出すときもページ数・マス数・値の範囲を揃える")
    func exportNormalizes() throws {
        var profile = ModelFixtures.profile(ModelFixtures.safari)
        profile.pages[0].cells = [ModelFixtures.cell("s", action: .script(ScriptAction(source: "x", timeout: .infinity)))]
        let imported = try ConfigurationStore.importProfiles(from: ConfigurationStore.exportData(profiles: [profile]))
        #expect(imported[0].pages[0].cells.count == 9)
        #expect(imported[0].pages[0].cells[0]?.action == .script(ScriptAction(source: "x", timeout: 60)))
    }

    @Test("空の書き出しは noProfiles")
    func exportNothing() {
        #expect(throws: ConfigurationStoreError.noProfiles) {
            try ConfigurationStore.exportData(profiles: [])
        }
    }

    /// 書き出しファイル（.nonetprofile）の書式
    static let document = #"""
    {
      "format": "com.iam74k4.Nonet.profiles",
      "version": 1,
      "exportedAt": "2026-10-30T12:00:00Z",
      "profiles": [
        {"id": "00000000-0000-0000-0000-000000000002",
         "kind": {"type": "app", "app": {"bundleID": "com.figma.Desktop", "name": "Figma"}},
         "isEnabled": true,
         "pages": [{"cells": [
           {"id": "00000000-0000-0000-0000-0000000000c1", "title": "自動レイアウト",
            "icon": {"type": "symbol", "symbol": "square.grid.2x2"},
            "action": {"type": "menuItem", "app": {"bundleID": "com.figma.Desktop", "name": "Figma"},
                       "path": ["オブジェクト", "自動レイアウトを追加"],
                       "keyEquivalent": [{"type": "character", "character": "a", "modifiers": ["shift"]}]}},
           {"title": "未来のアクション", "action": {"type": "hologram"}},
           null, null, null, null, null, null, null
         ]}]},
        {"kind": {"type": "app", "app": {"bundleID": "com.figma.Desktop", "name": "Figma（重複）"}}},
        {"kind": {"type": "app", "app": {"bundleID": "", "name": "名無し"}}},
        {"kind": {"type": "website"}},
        {"kind": {"type": "global"}, "pages": [{"cells": []}, {"cells": []}]},
        {"kind": {"type": "global"}}
      ]
    }
    """#

    @Test("書き出しファイルを読む。読めないマスは空き、使えないプロファイルは外す")
    func importFixture() throws {
        let profiles = try ConfigurationStore.importProfiles(from: Data(Self.document.utf8))
        #expect(profiles.map(\.kind) == [.app(ModelFixtures.figma), .global])
        let figma = profiles[0]
        #expect(figma.id != UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        #expect(figma.pages[0].cells[0]?.id != UUID(uuidString: "00000000-0000-0000-0000-0000000000c1"))
        #expect(figma.pages[0].cells[0]?.action == .menuItem(MenuItemAction(
            app: ModelFixtures.figma, path: ["オブジェクト", "自動レイアウトを追加"], keyEquivalent: .key("a", [.shift])
        )))
        #expect(figma.pages[0].cells[1] == nil)
        #expect(profiles[1].pages.count == 2)
    }

    @Test("Nonet の書き出しファイルでないものは notAProfileDocument", arguments: [
        "not json",
        "",
        "[]",
        "{}",
        #"{"format": "com.example.other", "version": 1, "profiles": []}"#,
        #"{"format": 1, "version": 1}"#,
        // 設定ファイルそのものは書き出しファイルではない
        #"{"version": 1, "settings": {}, "profiles": [{"kind": {"type": "global"}}]}"#,
    ])
    func rejectsForeignDocuments(_ json: String) {
        #expect(throws: ConfigurationStoreError.notAProfileDocument) {
            try ConfigurationStore.importProfiles(from: Data(json.utf8))
        }
    }

    @Test("新しい版の書き出しファイルは unsupportedProfileDocumentVersion")
    func rejectsNewerVersion() {
        let json = #"{"format": "com.iam74k4.Nonet.profiles", "version": 2, "profiles": [{"kind": {"type": "global"}}]}"#
        #expect(throws: ConfigurationStoreError.unsupportedProfileDocumentVersion(2)) {
            try ConfigurationStore.importProfiles(from: Data(json.utf8))
        }
    }

    @Test("版や profiles が読めない書き出しファイルは invalidProfileDocument", arguments: [
        #"{"format": "com.iam74k4.Nonet.profiles", "profiles": []}"#,
        #"{"format": "com.iam74k4.Nonet.profiles", "version": "1", "profiles": []}"#,
        #"{"format": "com.iam74k4.Nonet.profiles", "version": 0, "profiles": []}"#,
        #"{"format": "com.iam74k4.Nonet.profiles", "version": 1}"#,
        #"{"format": "com.iam74k4.Nonet.profiles", "version": 1, "profiles": {"a": 1}}"#,
    ])
    func rejectsInvalidDocuments(_ json: String) {
        let error = #expect(throws: ConfigurationStoreError.self) {
            try ConfigurationStore.importProfiles(from: Data(json.utf8))
        }
        if case .invalidProfileDocument? = error {} else {
            Issue.record("invalidProfileDocument ではない: \(String(describing: error))")
        }
    }

    @Test("使えるプロファイルが1つも無ければ noProfiles", arguments: [
        #"{"format": "com.iam74k4.Nonet.profiles", "version": 1, "profiles": []}"#,
        #"{"format": "com.iam74k4.Nonet.profiles", "version": 1, "profiles": [{"kind": {"type": "website"}}, null, 3]}"#,
        #"{"format": "com.iam74k4.Nonet.profiles", "version": 1, "profiles": [{"kind": {"type": "app", "app": {"bundleID": " ", "name": "x"}}}]}"#,
    ])
    func rejectsEmptyDocuments(_ json: String) {
        #expect(throws: ConfigurationStoreError.noProfiles) {
            try ConfigurationStore.importProfiles(from: Data(json.utf8))
        }
    }

    @Test("読み込んだプロファイルを設定に反映する（書き出し → 読み込み → importProfiles）")
    func importIntoConfiguration() throws {
        let source = ModelFixtures.configuration()
        var target = NonetConfiguration(profiles: [ModelFixtures.globalProfile(), ModelFixtures.profile(ModelFixtures.figma)]).validated()
        let data = try ConfigurationStore.exportData(profiles: Array(source.profiles[1...]))
        let result = target.importProfiles(try ConfigurationStore.importProfiles(from: data))

        #expect(result == NonetConfiguration.ImportResult(added: 2))
        #expect(target.profiles.map(\.name) == ["グローバル", "Figma", "Safari", "Xcode"])
        #expect(ConfigurationValidationTests.satisfiesInvariants(target))
    }

    @Test("エラーの説明は日本語の文で、空でない")
    func errorDescriptions() {
        let errors: [ConfigurationStoreError] = [
            .readFailed(reason: "r"),
            .corrupted(movedTo: URL(filePath: "/tmp/configuration.corrupt-1.json"), reason: "r"),
            .corrupted(movedTo: nil, reason: "r"),
            .writeFailed(reason: "r"),
            .exportFailed(reason: "r"),
            .notAProfileDocument,
            .unsupportedProfileDocumentVersion(2),
            .invalidProfileDocument(reason: "r"),
            .noProfiles,
        ]
        for error in errors {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
        }
        #expect(errors[1].errorDescription?.contains("configuration.corrupt-1.json") == true)
    }
}

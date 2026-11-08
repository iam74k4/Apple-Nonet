// 担当: core-model。設定ファイルの JSON の書式（往復と、リテラルの JSON からの読み込み）
import Foundation
@testable import NonetCore
import Testing

@Suite("モデルの Codable: 往復")
struct ModelCodingRoundTripTests {
    @Test("すべてのアクションが往復で同じになる", arguments: ModelFixtures.allActions)
    func actionRoundTrip(_ action: Action) throws {
        #expect(try ModelFixtures.roundTrip(action) == action)
    }

    @Test("アクションは type で種類を表し、自動の \"_0\" 形式を使わない", arguments: ModelFixtures.allActions)
    func actionUsesTypeDiscriminator(_ action: Action) throws {
        let object = try ModelFixtures.jsonObject(action)
        #expect(object["type"] as? String == action.kind.rawValue)
        let json = ModelFixtures.string(try ModelFixtures.encode(action))
        #expect(!json.contains("_0"))
    }

    @Test("アクションの書式（リテラルの JSON と同じ）")
    func actionFormat() throws {
        let cases: [(Action, String)] = [
            (.keystroke(.key("b", [.command, .shift])),
             #"{"type":"keystroke","keys":[{"type":"character","character":"b","modifiers":["shift","command"]}]}"#),
            (.keystroke(KeySequence([KeyChord(.special(.f5)), KeyChord(.keyCode(36), modifiers: [.function])])),
             #"{"type":"keystroke","keys":[{"type":"special","special":"f5","modifiers":[]},{"type":"keyCode","keyCode":36,"modifiers":["function"]}]}"#),
            (.launchApp(LaunchAppAction(app: ModelFixtures.safari)),
             #"{"type":"launchApp","app":{"bundleID":"com.apple.Safari","name":"Safari"},"hideIfFrontmost":false}"#),
            (.openURL(URLAction(url: "https://example.com/a")),
             #"{"type":"openURL","url":"https://example.com/a"}"#),
            (.script(ScriptAction(source: "make", runMode: .terminal, timeout: 30)),
             #"{"type":"script","source":"make","runMode":"terminal","timeout":30}"#),
            (.shortcut(ShortcutAction(name: "集中")),
             #"{"type":"shortcut","name":"集中","passSelectedText":false}"#),
            (.menuItem(MenuItemAction(path: ["編集", "コピー"])),
             #"{"type":"menuItem","path":["編集","コピー"]}"#),
            (.menuItem(MenuItemAction(app: ModelFixtures.figma, path: ["A"], keyEquivalent: .key("k", [.option]))),
             #"{"type":"menuItem","app":{"bundleID":"com.figma.Desktop","name":"Figma"},"path":["A"],"keyEquivalent":[{"type":"character","character":"k","modifiers":["option"]}]}"#),
            (.ai(AIAction(prompt: "要約")),
             #"{"type":"ai","prompt":"要約","output":"showResult"}"#),
            (.file(FileAction(operation: .trash)),
             #"{"type":"file","operation":"trash"}"#),
        ]
        for (action, json) in cases {
            #expect(try ModelFixtures.jsonObject(action) == ModelFixtures.jsonObject(json), "\(action.kind)")
            #expect(try ModelFixtures.decode(Action.self, json) == action, "\(action.kind)")
        }
    }

    @Test("修飾キーはすべての組み合わせで往復する")
    func allModifierCombinations() throws {
        for raw in 0..<UInt8(32) {
            let action = Action.keystroke(KeySequence([KeyChord(.character("x"), modifiers: ModifierSet(rawValue: raw))]))
            #expect(try ModelFixtures.roundTrip(action) == action)
        }
    }

    @Test("すべての特殊キーが往復する", arguments: SpecialKey.allCases)
    func specialKeyRoundTrip(_ key: SpecialKey) throws {
        let action = Action.keystroke(.special(key, [.command]))
        #expect(try ModelFixtures.roundTrip(action) == action)
    }

    @Test("アイコンの書式と往復")
    func cellIconFormat() throws {
        let cases: [(CellIcon, String)] = [
            (.symbol("hammer"), #"{"type":"symbol","symbol":"hammer"}"#),
            (.app(bundleID: "com.apple.Safari"), #"{"type":"app","bundleID":"com.apple.Safari"}"#),
            (.text("AI"), #"{"type":"text","text":"AI"}"#),
        ]
        for (icon, json) in cases {
            #expect(try ModelFixtures.jsonObject(icon) == ModelFixtures.jsonObject(json))
            #expect(try ModelFixtures.roundTrip(icon) == icon)
        }
    }

    @Test("プロファイルの種類の書式と往復")
    func profileKindFormat() throws {
        let cases: [(ProfileKind, String)] = [
            (.global, #"{"type":"global"}"#),
            (.app(ModelFixtures.xcode), #"{"type":"app","app":{"bundleID":"com.apple.dt.Xcode","name":"Xcode"}}"#),
        ]
        for (kind, json) in cases {
            #expect(try ModelFixtures.jsonObject(kind) == ModelFixtures.jsonObject(json))
            #expect(try ModelFixtures.roundTrip(kind) == kind)
        }
    }

    /// 前の版の「HUD の位置」は読み飛ばす（HUD は画面いっぱいの地図になり、置く場所が無い）
    @Test func hudPositionIsRetired() throws {
        let settings = try ModelFixtures.decode(GlobalSettings.self, #"{"hudPosition": "nearCursor", "haptics": "light"}"#)
        #expect(settings == GlobalSettings(haptics: .light))
        #expect(GlobalSettings.retiredKeys.contains("hudPosition"))
    }

    /// 前の版の「背景に合わせて色を変える」は読み飛ばし、もう書かない（アイコンを暗い台に白で載せるようになり、下の画面を撮って色を決めない）
    @Test func adaptiveHUDInkIsRetired() throws {
        let settings = try ModelFixtures.decode(GlobalSettings.self, #"{"adaptiveHUDInk": true, "haptics": "off"}"#)
        #expect(settings == GlobalSettings(haptics: .off))
        #expect(GlobalSettings.retiredKeys.contains("adaptiveHUDInk"))
        let keys = try ModelFixtures.jsonObject(settings).allKeys.compactMap { $0 as? String }
        #expect(!keys.contains("adaptiveHUDInk"))
    }

    @Test("触覚の強さのすべての値が往復する", arguments: HapticStrength.allCases)
    func hapticsRoundTrip(_ strength: HapticStrength) throws {
        let settings = GlobalSettings(haptics: strength)
        #expect(try ModelFixtures.roundTrip(settings) == settings)
    }

    @Test("スクリプトの実行方法のすべての値が往復する", arguments: ScriptRunMode.allCases)
    func scriptRunModeRoundTrip(_ mode: ScriptRunMode) throws {
        let action = Action.script(ScriptAction(source: "true", runMode: mode))
        #expect(try ModelFixtures.roundTrip(action) == action)
    }

    @Test("AI の出力先のすべての値が往復する", arguments: AIOutput.allCases)
    func aiOutputRoundTrip(_ output: AIOutput) throws {
        let action = Action.ai(AIAction(prompt: "p", output: output))
        #expect(try ModelFixtures.roundTrip(action) == action)
    }

    @Test("全体の設定は既定値以外も往復する")
    func settingsRoundTrip() throws {
        let settings = GlobalSettings(isEnabled: false, haptics: .strong, hudScale: .large)
        #expect(try ModelFixtures.roundTrip(settings) == settings)
        let keys = try ModelFixtures.jsonObject(settings).allKeys.compactMap { $0 as? String }.sorted()
        // トリガーキーで開いていた版の項目（trigger・fireMode・hudDelay・passTriggerToApps・touchActivation）と hudPosition は、もう書かない
        #expect(keys == ["haptics", "hudScale", "isEnabled"])
    }

    @Test("設定全体が往復し、書くたびに同じバイト列になる")
    func configurationRoundTripIsStable() throws {
        var configuration = ModelFixtures.configuration(settings: GlobalSettings(haptics: .light, hudScale: .large))
        let xcodeID = configuration.profiles[2].id
        for (index, action) in ModelFixtures.allActions.prefix(9).enumerated() {
            configuration.setCell(ModelFixtures.cell("c\(index)", action: action), at: CellAddress(page: 1, index: index), profileID: xcodeID)
        }
        let decoded = try ModelFixtures.roundTrip(configuration)
        #expect(decoded == configuration)
        #expect(try ModelFixtures.encode(configuration) == ModelFixtures.encode(decoded))
        #expect(try ModelFixtures.encode(configuration) == ModelFixtures.encode(configuration))
    }

    @Test("マスとページの書式。空きマスは null で、常に9個書く")
    func pageFormat() throws {
        let id = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        var page = Page(cells: [Cell(id: id, title: "開く", icon: .symbol("safari"), action: .openURL(URLAction(url: "https://a.example")))])
        let expected = #"""
        {"cells":[
          {"id":"11111111-2222-3333-4444-555555555555","title":"開く","icon":{"type":"symbol","symbol":"safari"},
           "action":{"type":"openURL","url":"https://a.example"}},
          null,null,null,null,null,null,null,null]}
        """#
        #expect(try ModelFixtures.jsonObject(page) == ModelFixtures.jsonObject(expected))

        // cells を直接いじって数が狂っていても、9個で書く
        page.cells.removeLast(4)
        let cells = try #require(try ModelFixtures.jsonObject(page)["cells"] as? [Any])
        #expect(cells.count == 9)
    }
}

@Suite("モデルの Codable: 保存されたファイルの読み込み")
struct ModelCodingFixtureTests {
    /// 設定ファイル（v1）の書式。この形で ~/Library/Application Support/Nonet/configuration.json に書く
    static let fullConfiguration = #"""
    {
      "version": 1,
      "settings": {
        "isEnabled": true,
        "trigger": "rightCommand",
        "fireMode": "onFingerLift",
        "hudDelay": 0.4,
        "hudPosition": "nearCursor",
        "autoSwitchProfiles": true,
        "appendGlobalPages": false,
        "haptics": "light",
        "passTriggerToApps": false,
        "showExecutionToast": true,
        "cursorLock": "dropEvents"
      },
      "profiles": [
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "kind": {"type": "global"},
          "isEnabled": true,
          "pages": [
            {"cells": [
              {"id": "00000000-0000-0000-0000-0000000000A1", "title": "Safari",
               "icon": {"type": "app", "bundleID": "com.apple.Safari"},
               "action": {"type": "launchApp", "app": {"bundleID": "com.apple.Safari", "name": "Safari"}, "hideIfFrontmost": true}},
              null, null, null, null, null, null, null, null
            ]}
          ]
        },
        {
          "id": "00000000-0000-0000-0000-000000000002",
          "kind": {"type": "app", "app": {"bundleID": "com.apple.dt.Xcode", "name": "Xcode"}},
          "isEnabled": false,
          "pages": [
            {"cells": [
              {"id": "00000000-0000-0000-0000-0000000000B1", "title": "ビルド",
               "icon": {"type": "symbol", "symbol": "hammer"},
               "action": {"type": "keystroke", "keys": [{"type": "character", "character": "b", "modifiers": ["command"]}]}},
              {"id": "00000000-0000-0000-0000-0000000000B2", "title": "Claude",
               "icon": {"type": "text", "text": "AI"},
               "action": {"type": "script", "source": "cd \"$PROJECT_DIR\" && claude", "runMode": "terminal", "timeout": 60}},
              {"id": "00000000-0000-0000-0000-0000000000B3", "title": "ミュート",
               "icon": {"type": "symbol", "symbol": "mic.slash"},
               "action": {"type": "shortcut", "name": "ミュート", "passSelectedText": false}},
              {"id": "00000000-0000-0000-0000-0000000000B4", "title": "コピー",
               "icon": {"type": "symbol", "symbol": "doc.on.doc"},
               "action": {"type": "menuItem", "path": ["編集", "コピー"],
                          "keyEquivalent": [{"type": "character", "character": "c", "modifiers": ["command"]}]}},
              {"id": "00000000-0000-0000-0000-0000000000B5", "title": "要約",
               "icon": {"type": "symbol", "symbol": "sparkles"},
               "action": {"type": "ai", "prompt": "要約して", "output": "copyToClipboard"}},
              {"id": "00000000-0000-0000-0000-0000000000B6", "title": "Docs",
               "icon": {"type": "symbol", "symbol": "book"},
               "action": {"type": "openURL", "url": "https://developer.apple.com"}},
              null, null, null
            ]}
          ]
        }
      ]
    }
    """#

    @Test("v1 の設定ファイルを読める")
    func decodesFullConfiguration() throws {
        let configuration = try ModelFixtures.decode(NonetConfiguration.self, Self.fullConfiguration)
        #expect(configuration.version == 1)
        // トリガーキーの項目（trigger・fireMode・hudDelay・passTriggerToApps）と hudPosition は読み飛ばす
        #expect(configuration.settings == GlobalSettings(haptics: .light))
        try #require(configuration.profiles.count == 2)

        let global = configuration.profiles[0]
        #expect(global.isGlobal)
        #expect(global.id == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        #expect(global.pages[0].cells[0]?.action == .launchApp(LaunchAppAction(app: ModelFixtures.safari, hideIfFrontmost: true)))
        #expect(global.pages[0].cells[0]?.icon == .app(bundleID: "com.apple.Safari"))

        let xcode = configuration.profiles[1]
        #expect(xcode.kind == .app(ModelFixtures.xcode))
        #expect(!xcode.isEnabled)
        let actions = xcode.pages[0].cells.map { $0?.action }
        #expect(actions == [
            .keystroke(.key("b", [.command])),
            .script(ScriptAction(source: "cd \"$PROJECT_DIR\" && claude", runMode: .terminal, timeout: 60)),
            .shortcut(ShortcutAction(name: "ミュート")),
            .menuItem(MenuItemAction(path: ["編集", "コピー"], keyEquivalent: .key("c", [.command]))),
            .ai(AIAction(prompt: "要約して", output: .copyToClipboard)),
            .openURL(URLAction(url: "https://developer.apple.com")),
            nil, nil, nil,
        ])
        #expect(xcode.pages[0].cells[1]?.icon == .text("AI"))

        // 書き直しても、読み飛ばした項目のほかは同じ内容になる（UUID は大文字で書く）
        let expected = try ModelFixtures.jsonObject(Self.fullConfiguration)
        let settings = try #require(expected["settings"] as? NSDictionary)
        let trimmed = NSMutableDictionary(dictionary: settings)
        trimmed.removeObjects(forKeys: ["trigger", "fireMode", "hudDelay", "passTriggerToApps", "autoSwitchProfiles", "appendGlobalPages", "showExecutionToast", "cursorLock", "hudPosition"])
        let rewritten = NSMutableDictionary(dictionary: expected)
        rewritten["settings"] = trimmed
        #expect(try ModelFixtures.jsonObject(configuration) == rewritten)
    }

    @Test("全体の設定: 無い項目は既定値")
    func settingsMissingKeys() throws {
        #expect(try ModelFixtures.decode(GlobalSettings.self, "{}") == GlobalSettings())
        let partial = try ModelFixtures.decode(GlobalSettings.self, #"{"haptics": "off", "hudScale": "large"}"#)
        #expect(partial == GlobalSettings(haptics: .off, hudScale: .large))
    }

    @Test("全体の設定: 知らない値や型の違う値は、その項目だけ既定値")
    func settingsUnknownValues() throws {
        let json = #"""
        {"trigger": "leftControl", "fireMode": "onDoubleTap", "hudPosition": 3, "haptics": "ultra",
         "cursorLock": null, "hudDelay": "fast", "isEnabled": "yes", "showExecutionToast": false,
         "futureSetting": {"nested": true}}
        """#
        let settings = try ModelFixtures.decode(GlobalSettings.self, json)
        #expect(settings == GlobalSettings())
    }

    @Test("設定全体: settings が無い・読めないときは既定値")
    func configurationWithoutSettings() throws {
        let missing = try ModelFixtures.decode(NonetConfiguration.self, #"{"version": 1, "profiles": []}"#)
        #expect(missing.settings == GlobalSettings())
        let broken = try ModelFixtures.decode(NonetConfiguration.self, #"{"version": 1, "settings": "x", "profiles": []}"#)
        #expect(broken.settings == GlobalSettings())
    }

    @Test("設定全体: version が無ければ 1、profiles が無ければ空")
    func configurationMissingVersionAndProfiles() throws {
        let configuration = try ModelFixtures.decode(NonetConfiguration.self, "{}")
        #expect(configuration.version == 1)
        #expect(configuration.profiles.isEmpty)
    }

    @Test("設定全体: profiles が配列でない（null も）・ルートがオブジェクトでないときは読めない")
    func configurationStructureErrors() {
        #expect(throws: DecodingError.self) {
            try ModelFixtures.decode(NonetConfiguration.self, #"{"profiles": {"a": 1}}"#)
        }
        // null を「無い」として空の設定にすると、次の保存ですべてのプロファイルを失う
        #expect(throws: DecodingError.self) {
            try ModelFixtures.decode(NonetConfiguration.self, #"{"version": 1, "profiles": null}"#)
        }
        #expect(throws: DecodingError.self) {
            try ModelFixtures.decode(NonetConfiguration.self, "[]")
        }
        #expect(throws: DecodingError.self) {
            try ModelFixtures.decode(NonetConfiguration.self, #"{"version": "1"}"#)
        }
    }

    @Test("知らないアクションの種類のマスは空きマスになり、ほかのマスは残る")
    func unknownActionType() throws {
        let json = #"""
        {"cells": [
          {"title": "未来", "icon": {"type": "symbol", "symbol": "star"}, "action": {"type": "teleport", "to": "moon"}},
          {"title": "残る", "icon": {"type": "symbol", "symbol": "star"}, "action": {"type": "openURL", "url": "https://a.example"}},
          null, null, null, null, null, null, null
        ]}
        """#
        let page = try ModelFixtures.decode(Page.self, json)
        #expect(page.cells.count == 9)
        #expect(page.cells[0] == nil)
        #expect(page.cells[1]?.title == "残る")
    }

    @Test("読めないマスはどれも空きマスになる", arguments: [
        #"{"title": "a", "icon": {"type": "symbol", "symbol": "s"}}"#,
        #"{"title": "a", "icon": {"type": "symbol", "symbol": "s"}, "action": {"url": "https://a.example"}}"#,
        #"{"title": "a", "action": {"type": "keystroke", "keys": [{"type": "character", "character": "b", "modifiers": ["hyper"]}]}}"#,
        #"{"title": "a", "action": {"type": "keystroke", "keys": [{"type": "special", "special": "f99"}]}}"#,
        #"{"title": "a", "action": {"type": "keystroke", "keys": [{"type": "joystick"}]}}"#,
        #"{"title": "a", "action": {"type": "keystroke", "keys": [{"type": "keyCode", "keyCode": 70000}]}}"#,
        #"{"title": "a", "action": {"type": "keystroke", "keys": {"character": "b"}}}"#,
        #"{"title": "a", "action": {"type": "keystroke"}}"#,
        #"{"title": "a", "action": {"type": "launchApp", "app": {"name": "名前だけ"}}}"#,
        #"{"title": "a", "action": {"type": "script", "runMode": "terminal"}}"#,
        #"{"title": "a", "action": {"type": "menuItem", "app": "Figma", "path": ["A"]}}"#,
        #"{"title": "a", "action": {"type": "ai", "output": "showResult"}}"#,
        #"{"title": "a", "action": {"type": "shortcut", "name": 3}}"#,
        #""cell""#,
        "42",
        "[]",
    ])
    func unreadableCells(_ cellJSON: String) throws {
        let json = #"{"cells": [\#(cellJSON), {"title": "後ろ", "action": {"type": "ai", "prompt": "p"}}]}"#
        let page = try ModelFixtures.decode(Page.self, json)
        #expect(page.cells.count == 9)
        #expect(page.cells[0] == nil)
        #expect(page.cells[1]?.title == "後ろ")
    }

    @Test("アクションの省略できる項目は既定値、知らない列挙値も既定値")
    func actionDefaults() throws {
        let cases: [(String, Action)] = [
            (#"{"type": "launchApp", "app": {"bundleID": "com.apple.Safari", "name": "Safari"}}"#,
             .launchApp(LaunchAppAction(app: ModelFixtures.safari))),
            (#"{"type": "launchApp", "app": {"bundleID": "com.apple.Safari"}}"#,
             .launchApp(LaunchAppAction(app: AppReference(bundleID: "com.apple.Safari", name: "com.apple.Safari")))),
            (#"{"type": "script", "source": "ls"}"#,
             .script(ScriptAction(source: "ls", runMode: .background, timeout: 60))),
            (#"{"type": "script", "source": "ls", "runMode": "window", "timeout": "long"}"#,
             .script(ScriptAction(source: "ls"))),
            (#"{"type": "shortcut", "name": "n"}"#,
             .shortcut(ShortcutAction(name: "n", passSelectedText: false))),
            (#"{"type": "ai", "prompt": "p"}"#,
             .ai(AIAction(prompt: "p", output: .showResult))),
            (#"{"type": "ai", "prompt": "p", "output": "speak"}"#,
             .ai(AIAction(prompt: "p", output: .showResult))),
            (#"{"type": "menuItem", "path": ["A", "B"], "keyEquivalent": [{"type": "character", "character": "k", "modifiers": ["warp"]}]}"#,
             .menuItem(MenuItemAction(path: ["A", "B"], keyEquivalent: nil))),
            (#"{"type": "menuItem", "path": ["A"], "keyEquivalent": null}"#,
             .menuItem(MenuItemAction(path: ["A"]))),
            (#"{"type": "keystroke", "keys": [{"type": "character", "character": "q"}]}"#,
             .keystroke(.key("q"))),
            (#"{"type": "openURL", "url": "x", "futureKey": 1}"#,
             .openURL(URLAction(url: "x"))),
        ]
        for (json, expected) in cases {
            #expect(try ModelFixtures.decode(Action.self, json) == expected, "\(json)")
        }
    }

    @Test("マス: id が無ければ作り、タイトルが無ければ空、アイコンが読めなければ代わりのアイコン")
    func cellDefaults() throws {
        let launch = try ModelFixtures.decode(Cell.self, #"""
        {"icon": {"type": "hologram"}, "action": {"type": "launchApp", "app": {"bundleID": "com.apple.Safari", "name": "Safari"}}}
        """#)
        #expect(launch.title == "")
        #expect(launch.icon == .app(bundleID: "com.apple.Safari"))

        let url = try ModelFixtures.decode(Cell.self, #"{"id": "not-a-uuid", "title": "t", "action": {"type": "openURL", "url": "u"}}"#)
        #expect(url.icon == .symbol("questionmark.square.dashed"))
        #expect(url.title == "t")

        let other = try ModelFixtures.decode(Cell.self, #"{"title": "t", "action": {"type": "openURL", "url": "u"}}"#)
        #expect(url.id != other.id)
    }

    @Test("ページ: マスの数が違えば9個に揃える", arguments: [0, 1, 5, 8, 9, 10, 15])
    func wrongCellCount(_ count: Int) throws {
        let cells = (0..<count).map { #"{"title": "c\#($0)", "action": {"type": "openURL", "url": "u"}}"# }
        let page = try ModelFixtures.decode(Page.self, #"{"cells": [\#(cells.joined(separator: ","))]}"#)
        #expect(page.cells.count == 9)
        let titles = page.cells.map { $0?.title }
        let expected: [String?] = (0..<9).map { $0 < count ? "c\($0)" : nil }
        #expect(titles == expected)
    }

    @Test("ページ: cells が無い・配列でないときは空のページ")
    func pageWithoutCells() throws {
        #expect(try ModelFixtures.decode(Page.self, "{}") == .empty)
        #expect(try ModelFixtures.decode(Page.self, #"{"cells": "none"}"#) == .empty)
    }

    @Test("プロファイル: 読めないページは空きページにして位置を保つ。4ページ以上は3ページに")
    func profilePages() throws {
        let json = #"""
        {"kind": {"type": "global"}, "pages": [
          {"cells": [{"title": "1", "action": {"type": "openURL", "url": "u"}}]},
          "broken",
          {"cells": [{"title": "3", "action": {"type": "openURL", "url": "u"}}]},
          {"cells": [{"title": "4", "action": {"type": "openURL", "url": "u"}}]}
        ]}
        """#
        let profile = try ModelFixtures.decode(Profile.self, json)
        #expect(profile.pages.count == 3)
        #expect(profile.pages[0].cells[0]?.title == "1")
        #expect(profile.pages[1] == .empty)
        #expect(profile.pages[2].cells[0]?.title == "3")
        #expect(profile.isEnabled)
    }

    @Test("プロファイル: ページが無ければ空のページ1枚、id が無ければ作る")
    func profileDefaults() throws {
        let profile = try ModelFixtures.decode(Profile.self, #"{"kind": {"type": "app", "app": {"bundleID": "com.apple.Safari", "name": "Safari"}}, "pages": []}"#)
        #expect(profile.pages == [.empty])
        #expect(profile.app == ModelFixtures.safari)
        let noPages = try ModelFixtures.decode(Profile.self, #"{"kind": {"type": "global"}, "isEnabled": false}"#)
        #expect(noPages.pages == [.empty])
        #expect(!noPages.isEnabled)
    }

    @Test("設定全体: 知らない種類のプロファイルや読めないプロファイルは外し、ほかは残す")
    func unknownProfileKind() throws {
        let json = #"""
        {"version": 1, "profiles": [
          {"kind": {"type": "global"}, "pages": []},
          {"kind": {"type": "website", "host": "example.com"}, "pages": []},
          {"pages": []},
          null,
          {"kind": {"type": "app", "app": {"bundleID": "com.apple.Safari", "name": "Safari"}}, "pages": []}
        ]}
        """#
        let configuration = try ModelFixtures.decode(NonetConfiguration.self, json)
        #expect(configuration.profiles.map(\.kind) == [.global, .app(ModelFixtures.safari)])
    }

    /// スクリプトとショートカットの名前に入った NUL は、設定を直すときに除く（子プロセスに渡せない）
    @Test func nulIsRemovedFromScriptsAndShortcutNames() {
        let script = Action.script(ScriptAction(source: "echo a\u{0}b")).validated()
        #expect(script == .script(ScriptAction(source: "echo ab")))
        let shortcut = Action.shortcut(ShortcutAction(name: "x\u{0}y")).validated()
        #expect(shortcut == .shortcut(ShortcutAction(name: "xy")))
    }
}

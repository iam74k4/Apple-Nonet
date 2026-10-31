import Foundation
import NonetCore
@testable import NonetPlatform
import Testing

/// スクリーンショットと画面収録: macOS のショートカットを探して送る。キーは送らず、偽物で受ける
@Suite("画面の撮影")
@MainActor
struct ActionScreenCaptureTests {
    /// 送ったキーと、待った時間を順に覚える
    final class Recorder: KeySending {
        enum Event: Equatable {
            case keys([KeyChord])
            case wait(Duration)
        }

        var events: [Event] = []
        var failure: NonetError?

        func send(_ sequence: KeySequence) async throws {
            if let failure { throw failure }
            events.append(.keys(sequence.chords))
        }
    }

    private func runner(_ recorder: Recorder, table: [String: Any]? = nil) -> ScreenCaptureRunner {
        ScreenCaptureRunner(keys: recorder, table: { table }, sleep: { recorder.events.append(.wait($0)) })
    }

    private func chord(_ code: UInt16, _ modifiers: ModifierSet) -> KeyChord {
        KeyChord(.keyCode(code), modifiers: modifiers)
    }

    /// AppleSymbolicHotKeys の1項目
    private func entry(enabled: Bool = true, parameters: [Any], type: String = "standard") -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": parameters, "type": type] as [String: Any]]
    }

    // MARK: ショートカットを探す

    @Test("何も変えていない Mac の割り当て: ⇧⌘3・⌃⇧⌘3・⇧⌘4・⌃⇧⌘4・⇧⌘5")
    func defaultHotKeys() {
        typealias K = SystemHotKeys
        #expect(K.defaultHotKey(.saveScreen) == K.HotKey(keyCode: 0x14, modifiers: [.shift, .command]))
        #expect(K.defaultHotKey(.copyScreen) == K.HotKey(keyCode: 0x14, modifiers: [.control, .shift, .command]))
        #expect(K.defaultHotKey(.saveArea) == K.HotKey(keyCode: 0x15, modifiers: [.shift, .command]))
        #expect(K.defaultHotKey(.copyArea) == K.HotKey(keyCode: 0x15, modifiers: [.control, .shift, .command]))
        #expect(K.defaultHotKey(.options) == K.HotKey(keyCode: 0x17, modifiers: [.shift, .command]))
    }

    @Test("システム設定が書いた割り当ては、番号の項目から読む。項目が無い・読めない形なら既定")
    func lookup() {
        // 既定の ⇧⌘4（ascii 52・キーコード 21・修飾キー 1179648）と同じ形
        let table: [String: Any] = ["30": entry(parameters: [52, 21, 1_179_648])]
        #expect(SystemHotKeys.lookup(.saveArea, in: table) == .hotKey(.init(keyCode: 21, modifiers: [.shift, .command])))
        // 利用者が ⌃⌥⌘9 に変えた
        let changed: [String: Any] = ["30": entry(parameters: [57, 25, 1_835_008])]
        #expect(SystemHotKeys.lookup(.saveArea, in: changed) == .hotKey(.init(keyCode: 25, modifiers: [.control, .option, .command])))
        // 無い・表が読めない
        #expect(SystemHotKeys.lookup(.saveArea, in: nil) == .hotKey(SystemHotKeys.defaultHotKey(.saveArea)))
        #expect(SystemHotKeys.lookup(.saveArea, in: ["99": entry(parameters: [1, 2, 3])]) == .hotKey(SystemHotKeys.defaultHotKey(.saveArea)))
        for broken in [["30": "oops"], ["30": ["enabled": true]], ["30": entry(parameters: [52, 21])], ["30": entry(parameters: ["a", "b", "c"])]] as [[String: Any]] {
            #expect(SystemHotKeys.lookup(.saveArea, in: broken) == .hotKey(SystemHotKeys.defaultHotKey(.saveArea)), "\(broken)")
        }
    }

    @Test("オフにされている・キーが割り当てられていないときは、送るものが無い")
    func disabledHotKeys() {
        #expect(SystemHotKeys.lookup(.saveArea, in: ["30": entry(enabled: false, parameters: [52, 21, 1_179_648])]) == .disabled)
        // 割り当てを消すと、ascii もキーコードも 65535
        #expect(SystemHotKeys.lookup(.saveArea, in: ["30": entry(parameters: [65535, 65535, 0])]) == .disabled)
        #expect(SystemHotKeys.lookup(.saveArea, in: ["30": entry(parameters: [65535, 200, 0])]) == .disabled)
        // 別の番号がオフでも、関係ない
        #expect(SystemHotKeys.lookup(.copyArea, in: ["30": entry(enabled: false, parameters: [52, 21, 1_179_648])]) == .hotKey(SystemHotKeys.defaultHotKey(.copyArea)))
    }

    @Test("修飾キーの値（NSEvent.ModifierFlags）を読み替える")
    func cocoaFlags() {
        #expect(SystemHotKeys.modifiers(fromCocoaFlags: 0) == [])
        #expect(SystemHotKeys.modifiers(fromCocoaFlags: 131_072) == [.shift])
        #expect(SystemHotKeys.modifiers(fromCocoaFlags: 262_144) == [.control])
        #expect(SystemHotKeys.modifiers(fromCocoaFlags: 524_288) == [.option])
        #expect(SystemHotKeys.modifiers(fromCocoaFlags: 1_048_576) == [.command])
        #expect(SystemHotKeys.modifiers(fromCocoaFlags: 8_388_608) == [.function])
        #expect(SystemHotKeys.modifiers(fromCocoaFlags: 1_441_792) == [.control, .shift, .command])
    }

    @Test("この Mac の設定でも、すべて読める（割り当てか、オフ）")
    func theRealPreferencesParse() {
        let table = SystemHotKeys.currentTable()
        for id in [SystemHotKeys.Identifier.saveScreen, .copyScreen, .saveArea, .copyArea, .options] {
            switch SystemHotKeys.lookup(id, in: table) {
            case .hotKey(let hotKey): #expect(hotKey.keyCode <= 0x7F)
            case .disabled: break
            }
        }
    }

    // MARK: 送るキー

    @Test("範囲・全画面・メニューは、ショートカットを1打だけ送る。クリップボードならそのショートカット")
    func sendsTheHotKey() async throws {
        let cases: [(ScreenCaptureAction, KeyChord)] = [
            (ScreenCaptureAction(mode: .area), chord(0x15, [.shift, .command])),
            (ScreenCaptureAction(mode: .area, toClipboard: true), chord(0x15, [.control, .shift, .command])),
            (ScreenCaptureAction(mode: .fullScreen), chord(0x14, [.shift, .command])),
            (ScreenCaptureAction(mode: .fullScreen, toClipboard: true), chord(0x14, [.control, .shift, .command])),
            (ScreenCaptureAction(mode: .toolbar), chord(0x17, [.shift, .command])),
            // メニューにクリップボードは無い
            (ScreenCaptureAction(mode: .toolbar, toClipboard: true), chord(0x17, [.shift, .command])),
        ]
        for (action, expected) in cases {
            let recorder = Recorder()
            try await runner(recorder).run(action)
            #expect(recorder.events == [.keys([expected])], "\(action)")
        }
    }

    @Test("ウインドウ: 範囲のショートカットのあと、少し待って Space を送る")
    func windowSendsSpaceAfterAShortWait() async throws {
        let recorder = Recorder()
        try await runner(recorder).run(ScreenCaptureAction(mode: .window))
        #expect(recorder.events == [
            .keys([chord(0x15, [.shift, .command])]),
            .wait(ScreenCaptureRunner.windowSwitchDelay),
            .keys([KeyChord(.special(.space))]),
        ])
        let clipboard = Recorder()
        try await runner(clipboard).run(ScreenCaptureAction(mode: .window, toClipboard: true))
        #expect(clipboard.events.first == .keys([chord(0x15, [.control, .shift, .command])]))
    }

    @Test("収録を止める: ⌃⌘Esc。システム設定のショートカットは見ない")
    func stopsRecording() async throws {
        let recorder = Recorder()
        let everythingOff: [String: Any] = ["184": entry(enabled: false, parameters: [53, 23, 1_179_648])]
        try await runner(recorder, table: everythingOff).run(ScreenCaptureAction(mode: .stopRecording))
        #expect(recorder.events == [.keys([KeyChord(.special(.escape), modifiers: [.control, .command])])])
    }

    @Test("システム設定で変えたキーを送る")
    func sendsTheChangedHotKey() async throws {
        let recorder = Recorder()
        let table: [String: Any] = ["30": entry(parameters: [57, 25, 1_835_008])]
        try await runner(recorder, table: table).run(ScreenCaptureAction(mode: .area))
        #expect(recorder.events == [.keys([chord(25, [.control, .option, .command])])])
    }

    @Test("ショートカットがオフなら、何も送らずに理由を知らせる")
    func disabledHotKeyIsReported() async {
        let recorder = Recorder()
        let table: [String: Any] = ["30": entry(enabled: false, parameters: [52, 21, 1_179_648])]
        await #expect(throws: NonetError.self) {
            try await runner(recorder, table: table).run(ScreenCaptureAction(mode: .window))
        }
        #expect(recorder.events.isEmpty)
    }

    @Test("キーを送れないとき（アクセシビリティの許可が無いなど）は、そのエラーを返し、Space も送らない")
    func sendFailureStopsTheSequence() async {
        let recorder = Recorder()
        recorder.failure = .permissionDenied(ActionText.accessibility)
        await #expect(throws: NonetError.permissionDenied(ActionText.accessibility)) {
            try await runner(recorder).run(ScreenCaptureAction(mode: .window))
        }
        #expect(recorder.events.isEmpty)
    }

    @Test("送るショートカットの番号")
    func identifiers() {
        #expect(ScreenCaptureRunner.identifier(for: ScreenCaptureAction(mode: .toolbar, toClipboard: true)) == .options)
        #expect(ScreenCaptureRunner.identifier(for: ScreenCaptureAction(mode: .window, toClipboard: true)) == .copyArea)
        #expect(ScreenCaptureRunner.identifier(for: ScreenCaptureAction(mode: .fullScreen)) == .saveScreen)
    }
}

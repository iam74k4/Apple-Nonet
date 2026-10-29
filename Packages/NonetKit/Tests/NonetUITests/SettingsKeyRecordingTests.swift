// 担当: ui-settings
import AppKit
import NonetCore
@testable import NonetUI
import Testing

@Suite struct SettingsKeyChordConverterTests {
    @Test func lettersAreLowercasedWithModifiers() {
        let chord = SettingsKeyChordConverter.chord(keyCode: 0x0B, characters: "B", flags: [.command, .shift])
        #expect(chord == KeyChord(.character("b"), modifiers: [.command, .shift]))
        #expect(chord?.displayString == "⇧⌘B")
    }

    @Test func shiftedDigitKeepsTheUnshiftedCharacter() {
        // ⇧⌘4: characters(byApplyingModifiers: []) は "4"
        let chord = SettingsKeyChordConverter.chord(keyCode: 0x15, characters: "4", flags: [.command, .shift])
        #expect(chord == KeyChord(.character("4"), modifiers: [.shift, .command]))
        #expect(chord?.displayString == "⇧⌘4")
    }

    @Test func specialKeysUseTheKeyCode() {
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x24, characters: "\r", flags: .command) == KeyChord(.special(.returnKey), modifiers: .command))
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x30, characters: "\t", flags: []) == KeyChord(.special(.tab)))
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x31, characters: " ", flags: .control) == KeyChord(.special(.space), modifiers: .control))
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x33, characters: "\u{7F}", flags: .command) == KeyChord(.special(.delete), modifiers: .command))
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x35, characters: "\u{1B}", flags: .command) == KeyChord(.special(.escape), modifiers: .command))
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x66, characters: nil, flags: []) == KeyChord(.special(.eisu)))
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x68, characters: nil, flags: []) == KeyChord(.special(.kana)))
    }

    @Test func implicitFunctionFlagIsDroppedForArrowsAndFunctionKeys() {
        // 矢印や F キーには macOS が fn の印を付ける
        let arrow = SettingsKeyChordConverter.chord(keyCode: 0x7B, characters: "\u{F702}", flags: [.command, .function, .numericPad])
        #expect(arrow == KeyChord(.special(.leftArrow), modifiers: .command))
        let f5 = SettingsKeyChordConverter.chord(keyCode: 0x60, characters: "\u{F708}", flags: .function)
        #expect(f5 == KeyChord(.special(.f5)))
        let home = SettingsKeyChordConverter.chord(keyCode: 0x73, characters: "\u{F729}", flags: .function)
        #expect(home == KeyChord(.special(.home)))
    }

    @Test func functionFlagIsKeptForOrdinaryKeys() {
        let chord = SettingsKeyChordConverter.chord(keyCode: 0x0E, characters: "e", flags: .function)
        #expect(chord == KeyChord(.character("e"), modifiers: .function))
    }

    @Test func keypadKeysKeepTheirKeyCode() {
        let chord = SettingsKeyChordConverter.chord(keyCode: 0x53, characters: "1", flags: .numericPad)
        #expect(chord == KeyChord(.keyCode(0x53)))
        // テンキーの Enter は Return と別のキー
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x4C, characters: "\u{3}", flags: .numericPad) == KeyChord(.keyCode(0x4C)))
    }

    @Test func unprintableCharactersFallBackToTheKeyCode() {
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x72, characters: "\u{F746}", flags: []) == KeyChord(.keyCode(0x72)))
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x21, characters: "", flags: .command) == KeyChord(.keyCode(0x21), modifiers: .command))
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x21, characters: nil, flags: []) == KeyChord(.keyCode(0x21)))
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x21, characters: "ab", flags: []) == KeyChord(.keyCode(0x21)))
    }

    @Test func jisSymbolsAreCharacters() {
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x1E, characters: "[", flags: .command) == KeyChord(.character("["), modifiers: .command))
        #expect(SettingsKeyChordConverter.chord(keyCode: 0x5D, characters: "¥", flags: .option) == KeyChord(.character("¥"), modifiers: .option))
    }

    @Test(arguments: [UInt16(0x36), 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F])
    func modifierKeysAloneAreNotChords(keyCode: UInt16) {
        #expect(SettingsKeyChordConverter.chord(keyCode: keyCode, characters: "", flags: .command) == nil)
    }

    @Test func modifierPrefixMatchesDisplayOrder() {
        #expect(SettingsKeyChordConverter.modifierPrefix([.command, .shift, .option, .control]) == "⌃⌥⇧⌘")
        #expect(SettingsKeyChordConverter.modifierPrefix([.function, .command]) == "fn ⌘")
        #expect(SettingsKeyChordConverter.modifierPrefix([]) == "")
        let chord = KeyChord(.character("k"), modifiers: [.function, .control, .command])
        #expect(chord.displayString == SettingsKeyChordConverter.modifierPrefix(chord.modifiers) + "K")
    }

    @Test func capsLockIsIgnored() {
        #expect(SettingsKeyChordConverter.modifiers(from: [.capsLock, .command]) == .command)
    }
}

@Suite struct SettingsKeyRecorderTests {
    @Test func recordsAChordAndFinishes() {
        var recorder = SettingsKeyRecorder()
        recorder.start()
        #expect(recorder.isRecording)
        #expect(recorder.progressText == nil)
        recorder.flagsChanged(.command)
        #expect(recorder.progressText == "⌘…")
        #expect(recorder.keyDown(keyCode: 0x0B, characters: "b", flags: .command) == .recording)
        #expect(recorder.progressText == "⌘B → ⌘…")
        #expect(recorder.finish() == .finished(.key("b", .command)))
        #expect(!recorder.isRecording)
    }

    @Test func recordsASequenceAndStopsAtFour() {
        var recorder = SettingsKeyRecorder()
        recorder.start()
        #expect(recorder.keyDown(keyCode: 0x25, characters: "l", flags: .command) == .recording)
        #expect(recorder.keyDown(keyCode: 0x08, characters: "c", flags: .command) == .recording)
        #expect(recorder.keyDown(keyCode: 0x30, characters: "\t", flags: []) == .recording)
        let outcome = recorder.keyDown(keyCode: 0x24, characters: "\r", flags: [])
        #expect(outcome == .finished(.sequence(.key("l", .command), .key("c", .command), .special(.tab), .special(.returnKey))))
        #expect(!recorder.isRecording)
    }

    @Test func plainEscapeCancelsEvenAfterKeys() {
        var recorder = SettingsKeyRecorder()
        recorder.start()
        _ = recorder.keyDown(keyCode: 0x0B, characters: "b", flags: .command)
        #expect(recorder.keyDown(keyCode: 0x35, characters: "\u{1B}", flags: []) == .cancelled)
        #expect(!recorder.isRecording)
        #expect(recorder.chords.isEmpty)
    }

    @Test func escapeWithModifiersIsRecorded() {
        var recorder = SettingsKeyRecorder()
        recorder.start()
        #expect(recorder.keyDown(keyCode: 0x35, characters: "\u{1B}", flags: .command) == .recording)
        #expect(recorder.finish() == .finished(.special(.escape, .command)))
    }

    @Test func escapeCanBeAddedFromTheButton() {
        var recorder = SettingsKeyRecorder()
        recorder.start()
        #expect(recorder.appendEscape() == .recording)
        #expect(recorder.finish() == .finished(.special(.escape)))
    }

    @Test func finishingWithoutKeysIsACancel() {
        var recorder = SettingsKeyRecorder()
        recorder.start()
        recorder.flagsChanged(.shift)
        #expect(recorder.finish() == .cancelled)
    }

    @Test func modifierOnlyPressesAreIgnored() {
        var recorder = SettingsKeyRecorder()
        recorder.start()
        #expect(recorder.keyDown(keyCode: 0x37, characters: "", flags: .command) == .recording)
        #expect(recorder.chords.isEmpty)
    }

    @Test func removeLastDropsTheLastChord() {
        var recorder = SettingsKeyRecorder()
        recorder.start()
        _ = recorder.keyDown(keyCode: 0x25, characters: "l", flags: .command)
        _ = recorder.keyDown(keyCode: 0x08, characters: "c", flags: .command)
        recorder.removeLast()
        #expect(recorder.chords == [KeyChord(.character("l"), modifiers: .command)])
    }

    @Test func eventsOutsideRecordingDoNothing() {
        var recorder = SettingsKeyRecorder()
        #expect(recorder.keyDown(keyCode: 0x0B, characters: "b", flags: .command) == .cancelled)
        #expect(recorder.appendEscape() == .cancelled)
        recorder.flagsChanged(.command)
        #expect(recorder.heldModifiers.isEmpty)
        #expect(recorder.finish() == .cancelled)
    }
}

@Suite struct SettingsKeyNotationInputTests {
    @Test func parsesNotation() {
        #expect(SettingsKeyNotationInput("⌘L → ⌘C") == .valid(.sequence(.key("l", .command), .key("c", .command))))
        #expect(SettingsKeyNotationInput(" cmd+shift+4 ") == .valid(.key("4", [.command, .shift])))
        #expect(SettingsKeyNotationInput("⎋") == .valid(.special(.escape)))
    }

    @Test func reportsProblems() {
        #expect(SettingsKeyNotationInput("   ") == .empty)
        #expect(SettingsKeyNotationInput("⌘⌘") == .invalid)
        #expect(SettingsKeyNotationInput("a, b, c, d, e") == .tooLong)
        #expect(SettingsKeyNotationInput("⌘⌘").message != nil)
        #expect(SettingsKeyNotationInput("a, b, c, d, e").message != nil)
        #expect(SettingsKeyNotationInput("a").message == nil)
    }
}

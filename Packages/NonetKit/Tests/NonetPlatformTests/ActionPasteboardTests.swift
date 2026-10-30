import AppKit
@testable import NonetPlatform
import Testing

/// 利用者のクリップボードには触らず、名前付きの別のクリップボードで確かめる
@MainActor
private func withPrivatePasteboard(_ body: (NSPasteboard) async throws -> Void) async rethrows {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.iam74k4.Nonet.tests.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    try await body(pasteboard)
}

@MainActor
private func put(_ text: String, on pasteboard: NSPasteboard, extra: [NSPasteboard.PasteboardType: Data] = [:]) {
    pasteboard.clearContents()
    let item = NSPasteboardItem()
    item.setString(text, forType: .string)
    for (type, data) in extra { item.setData(data, forType: type) }
    pasteboard.writeObjects([item])
}

/// 中身を求められてから作る（元のアプリが遅い・ファイルの約束などの代わり）
private final class SlowProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    let delay: TimeInterval
    private let lock = NSLock()
    private var requests: [String] = []
    private var done = false

    init(delay: TimeInterval) {
        self.delay = delay
    }

    var requestedTypes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    var isDone: Bool {
        lock.lock()
        defer { lock.unlock() }
        return done
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        lock.lock()
        requests.append(type.rawValue)
        lock.unlock()
        Thread.sleep(forTimeInterval: delay)
        item.setData(Data(count: 1024), forType: type)
        lock.lock()
        done = true
        lock.unlock()
    }
}

/// 中身を渡さない（読むことを拒まれたときと同じく、空が返る）
private final class RefusingProvider: NSObject, NSPasteboardItemDataProvider {
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {}
}

/// テストの中で書き換える値（Task の中からも書けるように）
@MainActor
private final class Box<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private extension Result where Failure == PasteboardSnapshot.Failure {
    var failure: PasteboardSnapshot.Failure? {
        if case .failure(let failure) = self { failure } else { nil }
    }
}

/// 条件がそろうまで待つ（最大 timeout 秒）
@MainActor
private func waitUntil(timeout: TimeInterval = 4, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@Suite("クリップボードの写しと書き込み")
@MainActor
struct ActionPasteboardTests {
    private let custom = NSPasteboard.PasteboardType("com.iam74k4.nonet.test")

    @Test("書いて戻すと、複数の項目と型が元どおり")
    func snapshotRestores() async throws {
        try await withPrivatePasteboard { pasteboard in
            let first = NSPasteboardItem()
            first.setString("元のテキスト", forType: .string)
            first.setData(Data([1, 2, 3]), forType: custom)
            let second = NSPasteboardItem()
            second.setString("2つめ", forType: .string)
            pasteboard.clearContents()
            pasteboard.writeObjects([first, second])

            let snapshot = try await PasteboardSnapshot.capture(pasteboard).get()
            #expect(!snapshot.isEmpty)
            #expect(!snapshot.isConcealed)
            let count = PasteboardWriter.write("AI の結果", to: pasteboard, transient: true)
            #expect(count == pasteboard.changeCount)
            #expect(pasteboard.string(forType: .string) == "AI の結果")
            #expect(pasteboard.types?.contains(PasteboardWriter.transientType) == true)

            snapshot.restore(to: pasteboard)
            let items = try #require(pasteboard.pasteboardItems)
            #expect(items.count == 2)
            #expect(items[0].string(forType: .string) == "元のテキスト")
            #expect(items[0].data(forType: custom) == Data([1, 2, 3]))
            #expect(items[1].string(forType: .string) == "2つめ")
        }
    }

    @Test("空のクリップボードは空に戻す")
    func restoresEmpty() async throws {
        try await withPrivatePasteboard { pasteboard in
            pasteboard.clearContents()
            let snapshot = try await PasteboardSnapshot.capture(pasteboard).get()
            #expect(snapshot.isEmpty)
            PasteboardWriter.write("一時的", to: pasteboard)
            #expect(pasteboard.types?.contains(PasteboardWriter.transientType) == false)
            snapshot.restore(to: pasteboard)
            #expect(pasteboard.string(forType: .string) == nil)
        }
    }

    @Test("中身を渡すのが遅いアプリでも、メインスレッドを止めずに時間切れであきらめる")
    func slowProviderDoesNotBlockMainThread() async {
        await withPrivatePasteboard { pasteboard in
            let provider = SlowProvider(delay: 1.5)
            let item = NSPasteboardItem()
            item.setString("表のテキスト", forType: .string)
            item.setDataProvider(provider, forTypes: [custom])
            pasteboard.clearContents()
            pasteboard.writeObjects([item])

            // 写している間もメインスレッドが動いているか（イベントタップと同じスレッド）
            let ticks = Box(0)
            let ticker = Task { @MainActor in
                while !Task.isCancelled {
                    ticks.value += 1
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            var result: Result<PasteboardSnapshot, PasteboardSnapshot.Failure>?
            let elapsed = await actionElapsedSeconds {
                result = await PasteboardSnapshot.capture(pasteboard, limits: .init(timeout: 0.2))
            }
            ticker.cancel()
            #expect(result?.failure == .tooSlow, "\(String(describing: result))")
            #expect(elapsed < 1, "\(elapsed) 秒待った")
            #expect(ticks.value >= 5, "メインスレッドが止まっていた（\(ticks.value) 回）")
            // 裏で続いている読み取りが終わってからクリップボードを片付ける
            _ = await waitUntil { provider.isDone }
        }
    }

    @Test("大きすぎる中身は写さない")
    func tooLarge() async {
        await withPrivatePasteboard { pasteboard in
            put("テキスト", on: pasteboard, extra: [custom: Data(count: 2 * 1024 * 1024)])
            let result = await PasteboardSnapshot.capture(pasteboard, limits: .init(maxBytes: 1024 * 1024))
            #expect(result.failure == .tooLarge)
        }
    }

    @Test("ファイルの約束は読まず（元のアプリにファイルを作らせない）、写せないとする")
    func filePromises() async {
        await withPrivatePasteboard { pasteboard in
            let provider = SlowProvider(delay: 0)
            let item = NSPasteboardItem()
            item.setDataProvider(provider, forTypes: [NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")])
            pasteboard.clearContents()
            pasteboard.writeObjects([item])
            let result = await PasteboardSnapshot.capture(pasteboard)
            #expect(result.failure == .unrestorable)
            #expect(provider.requestedTypes.isEmpty)
        }
    }

    @Test("何も読めない中身（読むのを拒まれたときなど）は、空として戻さない")
    func unreadable() async {
        await withPrivatePasteboard { pasteboard in
            let provider = RefusingProvider()
            let item = NSPasteboardItem()
            item.setDataProvider(provider, forTypes: [.string])
            pasteboard.clearContents()
            pasteboard.writeObjects([item])
            let result = await PasteboardSnapshot.capture(pasteboard)
            #expect(result.failure == .unreadable)
        }
    }

    @Test("パスワード（ConcealedType）は中身を読まず、戻さない")
    func concealed() async throws {
        try await withPrivatePasteboard { pasteboard in
            put("パスワード", on: pasteboard, extra: [NSPasteboard.PasteboardType(PasteboardSnapshot.concealedType): Data()])
            let snapshot = try await PasteboardSnapshot.capture(pasteboard).get()
            #expect(snapshot.isConcealed)
            #expect(snapshot.byteCount == 0)
            PasteboardWriter.write("AI の結果", to: pasteboard)
            snapshot.restore(to: pasteboard)
            #expect(pasteboard.string(forType: .string) == "AI の結果")
        }
    }

    @Test("macOS 15.4 以降の「常に拒否」では読まない。「確認する」は確認に答えるまで待つ")
    func accessBehavior() {
        if #available(macOS 15.4, *) {
            #expect(PasteboardAccess(.alwaysDeny) == .denied)
            #expect(PasteboardAccess(.ask) == .asks)
            #expect(PasteboardAccess(.alwaysAllow) == .allowed)
            #expect(PasteboardAccess(.default) == .allowed)
        }
        #expect(PasteboardSnapshot.Limits.standard.askTimeout > PasteboardSnapshot.Limits.standard.timeout)
    }
}

@Suite("⌘C で選択テキストを読む")
@MainActor
struct ActionClipboardCopyTests {
    @Test("アプリが書いた文字を返し、元のクリップボードに戻す")
    func copiesAndRestores() async {
        await withPrivatePasteboard { pasteboard in
            put("元のクリップボード", on: pasteboard)
            let outcome = await ClipboardCopy.copySelection(from: pasteboard) {
                put("選択した文", on: pasteboard)
            }
            #expect(outcome == .copied("選択した文"))
            #expect(pasteboard.string(forType: .string) == "元のクリップボード")
        }
    }

    @Test("書くのが少し遅いアプリ（0.7 秒）も待つ")
    func waitsForSlowApp() async {
        await withPrivatePasteboard { pasteboard in
            put("元のクリップボード", on: pasteboard)
            let outcome = await ClipboardCopy.copySelection(from: pasteboard) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    put("遅れて来た選択", on: pasteboard)
                }
            }
            #expect(outcome == .copied("遅れて来た選択"))
            #expect(pasteboard.string(forType: .string) == "元のクリップボード")
        }
    }

    @Test("待ちきれなかった後に書かれても、元のクリップボードに戻す")
    func restoresAfterLateWrite() async {
        await withPrivatePasteboard { pasteboard in
            put("元のクリップボード", on: pasteboard)
            let timing = ClipboardCopy.Timing(copyTimeout: 0.2, lateWriteWatch: 2)
            let outcome = await ClipboardCopy.copySelection(from: pasteboard, timing: timing) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    put("とても遅い選択", on: pasteboard)
                }
            }
            #expect(outcome == .nothing)
            try? await Task.sleep(for: .milliseconds(700))
            let restored = await waitUntil { pasteboard.string(forType: .string) == "元のクリップボード" }
            #expect(restored, "\(String(describing: pasteboard.string(forType: .string)))")
        }
    }

    @Test("何も書かれなければ、クリップボードはそのまま")
    func nothingCopied() async {
        await withPrivatePasteboard { pasteboard in
            put("元のクリップボード", on: pasteboard)
            let before = pasteboard.changeCount
            let timing = ClipboardCopy.Timing(copyTimeout: 0.1, lateWriteWatch: 0)
            let outcome = await ClipboardCopy.copySelection(from: pasteboard, timing: timing) {}
            #expect(outcome == .nothing)
            #expect(pasteboard.changeCount == before)
        }
    }

    @Test("クリップボードの中身を保てなければ、⌘C を送らず、クリップボードに触らない")
    func skipsWhenClipboardCannotBeKept() async {
        await withPrivatePasteboard { pasteboard in
            put("大きな中身", on: pasteboard, extra: [NSPasteboard.PasteboardType("com.iam74k4.nonet.big"): Data(count: 64 * 1024)])
            let before = pasteboard.changeCount
            var sent = false
            let outcome = await ClipboardCopy.copySelection(from: pasteboard, limits: .init(maxBytes: 1024)) {
                sent = true
            }
            #expect(outcome == .clipboardUnavailable(.tooLarge))
            #expect(!sent)
            #expect(pasteboard.changeCount == before)
        }
    }
}

@Suite("⌘V で選択を置き換える")
@MainActor
struct ActionClipboardPasteTests {
    @Test("貼り付けを遅れて読むアプリ（0.9 秒）にも結果が届き、その後で元に戻す")
    func lateReaderGetsTheResult() async throws {
        try await withPrivatePasteboard { pasteboard in
            put("元のクリップボード", on: pasteboard)
            let pasted = Box<String?>(nil)
            let outcome = try await ClipboardPaste.paste("AI の結果", to: pasteboard) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    pasted.value = pasteboard.string(forType: .string)
                }
            }
            #expect(outcome == .pasted)
            #expect(await waitUntil { pasted.value != nil })
            #expect(pasted.value == "AI の結果")
            #expect(await waitUntil { pasteboard.string(forType: .string) == "元のクリップボード" })
        }
    }

    @Test("読まれないままでも、しばらくしたら元に戻す")
    func restoresWithoutReader() async throws {
        try await withPrivatePasteboard { pasteboard in
            put("元のクリップボード", on: pasteboard)
            let timing = ClipboardPaste.Timing(fallback: 0.5)
            _ = try await ClipboardPaste.paste("AI の結果", to: pasteboard, timing: timing) {}
            #expect(pasteboard.types?.contains(PasteboardWriter.transientType) == true)
            #expect(await waitUntil { pasteboard.string(forType: .string) == "元のクリップボード" })
        }
    }

    @Test("待っている間に利用者がコピーしたものは消さない")
    func keepsNewerCopy() async throws {
        try await withPrivatePasteboard { pasteboard in
            put("元のクリップボード", on: pasteboard)
            let timing = ClipboardPaste.Timing(fallback: 0.3)
            _ = try await ClipboardPaste.paste("AI の結果", to: pasteboard, timing: timing) {}
            put("利用者のコピー", on: pasteboard)
            try await Task.sleep(for: .milliseconds(600))
            #expect(pasteboard.string(forType: .string) == "利用者のコピー")
        }
    }

    @Test("パスワードは戻さない（パスワード管理アプリが時間で消せなくなるため）")
    func doesNotRestorePasswords() async throws {
        try await withPrivatePasteboard { pasteboard in
            put("パスワード", on: pasteboard, extra: [NSPasteboard.PasteboardType(PasteboardSnapshot.concealedType): Data()])
            let timing = ClipboardPaste.Timing(fallback: 0.2)
            _ = try await ClipboardPaste.paste("AI の結果", to: pasteboard, timing: timing) {}
            try await Task.sleep(for: .milliseconds(500))
            #expect(pasteboard.string(forType: .string) == "AI の結果")
        }
    }

    @Test("クリップボードの中身を保てなければ、貼り付けず、クリップボードに触らない")
    func skipsWhenClipboardCannotBeKept() async throws {
        try await withPrivatePasteboard { pasteboard in
            put("大きな中身", on: pasteboard, extra: [NSPasteboard.PasteboardType("com.iam74k4.nonet.big"): Data(count: 64 * 1024)])
            let before = pasteboard.changeCount
            var sent = false
            let outcome = try await ClipboardPaste.paste("AI の結果", to: pasteboard, limits: .init(maxBytes: 1024)) {
                sent = true
            }
            #expect(outcome == .clipboardUnavailable(.tooLarge))
            #expect(!sent)
            #expect(pasteboard.changeCount == before)
            #expect(pasteboard.string(forType: .string) == "大きな中身")
        }
    }

    @Test("戻す時: 読まれたら少し後（⌘V から最短 minimumDelay）、読まれなければ fallback")
    func restoreTiming() {
        let timing = ClipboardPaste.Timing(settle: 0.2, minimumDelay: 0.6, fallback: 3)
        let pasted = Date(timeIntervalSinceReferenceDate: 0)
        func at(_ seconds: TimeInterval) -> Date { pasted.addingTimeInterval(seconds) }
        #expect(!ClipboardPaste.isTimeToRestore(now: at(1), pastedAt: pasted, requestedAt: nil, timing: timing))
        #expect(ClipboardPaste.isTimeToRestore(now: at(3), pastedAt: pasted, requestedAt: nil, timing: timing))
        #expect(!ClipboardPaste.isTimeToRestore(now: at(0.3), pastedAt: pasted, requestedAt: at(0.05), timing: timing))
        #expect(ClipboardPaste.isTimeToRestore(now: at(0.6), pastedAt: pasted, requestedAt: at(0.05), timing: timing))
        #expect(!ClipboardPaste.isTimeToRestore(now: at(1.0), pastedAt: pasted, requestedAt: at(0.9), timing: timing))
        #expect(ClipboardPaste.isTimeToRestore(now: at(1.1), pastedAt: pasted, requestedAt: at(0.9), timing: timing))
    }
}

@Suite("止まるかもしれない呼び出し")
struct ActionBlockingCallTests {
    @Test("制限時間を過ぎたら、終わりを待たずに代わりの値を返す")
    func timesOut() async {
        var value = ""
        let elapsed = await actionElapsedSeconds {
            value = await BlockingCall.run(timeout: 0.1, fallback: "代わり") {
                Thread.sleep(forTimeInterval: 1)
                return "遅い"
            }
        }
        #expect(value == "代わり")
        #expect(elapsed < 0.8)
    }

    @Test("間に合えばその値")
    func returnsValue() async {
        let value = await BlockingCall.run(timeout: 2, fallback: 0) { 42 }
        #expect(value == 42)
    }
}

import AppKit
@testable import NonetPlatform
import Testing

/// 利用者のクリップボードには触らず、名前付きの別のクリップボードで確かめる
@MainActor
private func withPrivatePasteboard(_ body: (NSPasteboard) async throws -> Void) async rethrows {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.iam74k4.Nonet.tests.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    try await body(pasteboard)
    // 裏で続いている読み取りを、次のテストに持ち越さない
    _ = await waitUntil(timeout: 5) { !PasteboardReader.shared.isBusy }
}

@MainActor
private func put(_ text: String, on pasteboard: NSPasteboard, extra: [NSPasteboard.PasteboardType: Data] = [:]) {
    pasteboard.clearContents()
    let item = NSPasteboardItem()
    item.setString(text, forType: .string)
    for (type, data) in extra { item.setData(data, forType: type) }
    pasteboard.writeObjects([item])
}

/// 文字は先に書き、types は求められてから渡す項目を書く
@MainActor
private func putLazy(_ text: String, types: [NSPasteboard.PasteboardType], provider: SlowProvider, on pasteboard: NSPasteboard) {
    let item = NSPasteboardItem()
    item.setString(text, forType: .string)
    item.setDataProvider(provider, forTypes: types)
    pasteboard.clearContents()
    pasteboard.writeObjects([item])
}

/// 中身を求められてから作る（元のアプリが遅い・ファイルの約束などの代わり）
private final class SlowProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    let delay: TimeInterval
    let size: Int
    private let lock = NSLock()
    private var requests: [String] = []
    private var running = 0
    private var maxRunning = 0
    private var done = false

    init(delay: TimeInterval, size: Int = 1024) {
        self.delay = delay
        self.size = size
    }

    var requestedTypes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    var isDone: Bool {
        lock.lock()
        defer { lock.unlock() }
        return done && running == 0
    }

    /// 同時に求められた数の最大
    var maxConcurrentRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return maxRunning
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        lock.lock()
        requests.append(type.rawValue)
        running += 1
        maxRunning = max(maxRunning, running)
        lock.unlock()
        Thread.sleep(forTimeInterval: delay)
        item.setData(Data(count: size), forType: type)
        lock.lock()
        running -= 1
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

/// クリップボードを裏で読む口（PasteboardReader）は1つしかなく、一度に1つしか読まないので、クリップボードのテストは順に行う
@Suite("クリップボード", .serialized)
@MainActor
struct ActionClipboardTests {
    @Suite("クリップボードの写しと書き込み")
    @MainActor
    struct Snapshot {
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
                putLazy("表のテキスト", types: [custom], provider: provider, on: pasteboard)

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

        @Test("時間切れの読み取りが続いている間は次を読み始めず、その間にメインスレッドで書き換えても落ちない")
        func overlappingCapturesWithMainThreadWrites() async {
            await withPrivatePasteboard { pasteboard in
                let provider = SlowProvider(delay: 0.05)
                var busy = 0
                for round in 0 ..< 30 {
                    // 毎回、裏の読み取りが始まるところから（前の回の読み取りが終わってから）
                    _ = await waitUntil { !PasteboardReader.shared.isBusy }
                    putLazy("表 \(round)", types: [custom], provider: provider, on: pasteboard)
                    _ = await PasteboardSnapshot.capture(pasteboard, limits: .init(timeout: 0.01))
                    // 前の読み取りがまだ続いていれば、待たずにあきらめる（読めば 0.05 秒で終わるので、2 秒の制限時間での失敗は読まなかったということ）
                    var second: Result<PasteboardSnapshot, PasteboardSnapshot.Failure>?
                    let elapsed = await actionElapsedSeconds {
                        second = await PasteboardSnapshot.capture(pasteboard, limits: .init(timeout: 2))
                    }
                    if second?.failure == .tooSlow {
                        #expect(elapsed < 0.5, "\(elapsed) 秒待った")
                        busy += 1
                    }
                    // 裏で読んでいる間に、メインスレッドで書き換える（元に戻す処理や、結果のパネルのコピーと同じ）
                    put("書き換え \(round)", on: pasteboard)
                    pasteboard.clearContents()
                    put("もう一度 \(round)", on: pasteboard)
                }
                // 待たずに続けて（前のコードでは、ここで裏の読み取りがいくつも重なっていた）
                for round in 0 ..< 60 {
                    putLazy("続けて \(round)", types: [custom], provider: provider, on: pasteboard)
                    _ = await PasteboardSnapshot.capture(pasteboard, limits: .init(timeout: 0.01))
                    _ = await PasteboardSnapshot.capture(pasteboard, limits: .init(timeout: 0.01))
                    put("書き換え \(round)", on: pasteboard)
                }
                _ = await waitUntil { !PasteboardReader.shared.isBusy }
                #expect(busy >= 10, "読み取りが重なる場面が少ない（\(busy) 回）")
                #expect(provider.requestedTypes.count >= 10, "\(provider.requestedTypes.count) 回")
                #expect(provider.maxConcurrentRequests == 1)
            }
        }

        @Test("前の読み取りが続いていても、Nonet が書いた中身は待たずに写せる（このプロセスの中にあり、メインスレッドで読む）")
        func ownContentDoesNotNeedTheReader() async throws {
            try await withPrivatePasteboard { slow in
                let provider = SlowProvider(delay: 0.8)
                putLazy("遅い表", types: [custom], provider: provider, on: slow)
                #expect(await PasteboardSnapshot.capture(slow, limits: .init(timeout: 0.05)).failure == .tooSlow)
                #expect(PasteboardReader.shared.isBusy)

                try await withPrivatePasteboard { pasteboard in
                    put("ほかのアプリのコピー", on: pasteboard)
                    #expect(await PasteboardSnapshot.capture(pasteboard).failure == .tooSlow)

                    PasteboardWriter.write("Nonet が書いた", to: pasteboard)
                    let snapshot = try await PasteboardSnapshot.capture(pasteboard).get()
                    put("⌘C の結果", on: pasteboard)
                    snapshot.restore(to: pasteboard)
                    #expect(pasteboard.string(forType: .string) == "Nonet が書いた")
                }
                _ = await waitUntil { provider.isDone }
            }
        }

        @Test("画像は項目ごとに最初の1つだけ、ファイルの項目では写さない。UTF-16 の文字は UTF-8 があれば写さない")
        func typesToRead() {
            let text = PasteboardSnapshot.utf8TextType
            let utf16 = PasteboardSnapshot.utf16ExternalTextType
            // 表計算の範囲: 文字・HTML・独自の形と、範囲を描いた PDF と TIFF
            #expect(PasteboardSnapshot.typesToRead([text, utf16, "public.html", "com.example.sheet", "com.adobe.pdf", "public.tiff"])
                == [text, "public.html", "com.example.sheet", "com.adobe.pdf"])
            // 写真: 最初の画像（アプリが一番に渡す形）だけ
            #expect(PasteboardSnapshot.typesToRead(["public.tiff", "public.png", "public.url"]) == ["public.tiff", "public.url"])
            // Finder のファイル: アイコンは写さない
            #expect(PasteboardSnapshot.typesToRead([PasteboardSnapshot.fileURLType, text, "com.apple.icns", "public.tiff"])
                == [PasteboardSnapshot.fileURLType, text])
            // UTF-16 しか無ければ写す
            #expect(PasteboardSnapshot.typesToRead([utf16]) == [utf16])
        }

        @Test("求められてから作る画像は、最初の1つしか求めない")
        func requestsOnlyOneImage() async throws {
            try await withPrivatePasteboard { pasteboard in
                let provider = SlowProvider(delay: 0)
                putLazy("範囲", types: [.pdf, .tiff, .png], provider: provider, on: pasteboard)
                let snapshot = try await PasteboardSnapshot.capture(pasteboard).get()
                #expect(provider.requestedTypes == [NSPasteboard.PasteboardType.pdf.rawValue])
                #expect(snapshot.types.first?.contains(NSPasteboard.PasteboardType.pdf.rawValue) == true)
                #expect(snapshot.types.first?.contains(NSPasteboard.PasteboardType.tiff.rawValue) == false)
            }
        }

        @Test("写真の大きさの中身（20 MB）も、標準の上限なら写せる")
        func photoSizedContent() async throws {
            try await withPrivatePasteboard { pasteboard in
                put("写真", on: pasteboard, extra: [.tiff: Data(count: 20 * 1024 * 1024)])
                let snapshot = try await PasteboardSnapshot.capture(pasteboard, limits: .standard).get()
                #expect(snapshot.byteCount > 20 * 1024 * 1024)
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

        @Test("macOS 15.4 以降: 「常に拒否」では読まない。一般のクリップボードの .default は「確認する」と同じく、確認に答えるまで待つ")
        func accessBehavior() {
            if #available(macOS 15.4, *) {
                #expect(PasteboardAccess(.alwaysDeny, isGeneral: true) == .denied)
                #expect(PasteboardAccess(.ask, isGeneral: true) == .asks)
                #expect(PasteboardAccess(.alwaysAllow, isGeneral: true) == .allowed)
                // ヘッダー: 一般のクリップボードの既定は「読むと確認する」、ほかのクリップボードは確認なし
                #expect(PasteboardAccess(.default, isGeneral: true) == .asks)
                #expect(PasteboardAccess(.default, isGeneral: false) == .allowed)
            }
            let limits = PasteboardSnapshot.Limits.standard
            #expect(limits.timeout(for: .asks) == limits.askTimeout)
            #expect(limits.timeout(for: .allowed) == limits.timeout)
            #expect(limits.askTimeout > limits.timeout)
        }
    }

    @Suite("⌘C で選択テキストを読む")
    @MainActor
    struct Copy {
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

        @Test("写すのと ⌘C の結果を待つのを合わせて copyTimeout に収める（実行の順番を譲る 1 秒を大きく越えない）")
        func roundTripStaysWithinCopyTimeout() async {
            await withPrivatePasteboard { pasteboard in
                let provider = SlowProvider(delay: 0.7)
                putLazy("表", types: [NSPasteboard.PasteboardType("com.iam74k4.nonet.slow")], provider: provider, on: pasteboard)
                var outcome: ClipboardCopy.Outcome?
                let elapsed = await actionElapsedSeconds {
                    outcome = await ClipboardCopy.copySelection(from: pasteboard, timing: .init(lateWriteWatch: 0)) {}
                }
                #expect(outcome == .nothing)
                #expect(elapsed < 1.4, "\(elapsed) 秒掛かった")
            }
        }

        @Test("待ちきれなかった後に書かれても、元のクリップボードに戻す")
        func restoresAfterLateWrite() async {
            await withPrivatePasteboard { pasteboard in
                put("元のクリップボード", on: pasteboard)
                let timing = ClipboardCopy.Timing(copyTimeout: 0.2, minimumCopyWait: 0.1)
                let outcome = await ClipboardCopy.copySelection(from: pasteboard, timing: timing) {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        put("とても遅い選択", on: pasteboard)
                    }
                }
                #expect(outcome == .nothing)
                let restored = await waitUntil(timeout: 2) { pasteboard.string(forType: .string) == "元のクリップボード" }
                #expect(restored, "\(String(describing: pasteboard.string(forType: .string)))")
            }
        }

        @Test("見張りが終わった後に利用者がコピーしたものは、元に戻さない")
        func keepsUsersCopyAfterWatch() async throws {
            try await withPrivatePasteboard { pasteboard in
                put("元のクリップボード", on: pasteboard)
                let timing = ClipboardCopy.Timing(copyTimeout: 0.2, minimumCopyWait: 0.1)
                #expect(await ClipboardCopy.copySelection(from: pasteboard, timing: timing) {} == .nothing)
                try await Task.sleep(for: .milliseconds(800))
                put("利用者のコピー", on: pasteboard)
                try await Task.sleep(for: .milliseconds(300))
                #expect(pasteboard.string(forType: .string) == "利用者のコピー")
            }
        }

        @Test("見張りの間に次の操作が ⌘C しても、前の見張りは元に戻さない（次の操作が古いクリップボードを選択と取り違えない）")
        func nextCopyCancelsWatch() async throws {
            try await withPrivatePasteboard { pasteboard in
                for round in 0 ..< 10 {
                    put("古いクリップボード \(round)", on: pasteboard)
                    let long = ClipboardCopy.Timing(copyTimeout: 0.2, minimumCopyWait: 0.1, lateWriteWatch: 2)
                    #expect(await ClipboardCopy.copySelection(from: pasteboard, timing: long) {} == .nothing)
                    try await Task.sleep(for: .milliseconds(100))
                    // アプリはすぐに書くが、⌘C を送り終えるまでに少し掛かる（その間に前の見張りが変化を見る）
                    let second = await ClipboardCopy.copySelection(from: pasteboard) {
                        put("本当の選択", on: pasteboard)
                        try? await Task.sleep(for: .milliseconds(120))
                    }
                    #expect(second == .copied("本当の選択"), "\(round)")
                    try await Task.sleep(for: .milliseconds(150))
                    #expect(pasteboard.string(forType: .string) == "古いクリップボード \(round)", "\(round)")
                }
            }
        }

        @Test("見張りの間に Nonet が結果をコピーしたら、それを消さない")
        func writeCancelsWatch() async throws {
            try await withPrivatePasteboard { pasteboard in
                put("元のクリップボード", on: pasteboard)
                let timing = ClipboardCopy.Timing(copyTimeout: 0.2, minimumCopyWait: 0.1, lateWriteWatch: 2)
                #expect(await ClipboardCopy.copySelection(from: pasteboard, timing: timing) {} == .nothing)
                PasteboardWriter.write("AI の結果", to: pasteboard)
                try await Task.sleep(for: .milliseconds(300))
                #expect(pasteboard.string(forType: .string) == "AI の結果")
            }
        }

        @Test("⌘C を送ったアプリが前面でなくなっていたら、遅れて書かれたものは戻さない（利用者のコピーかもしれない）")
        func lateWriteInAnotherApp() async throws {
            try await withPrivatePasteboard { pasteboard in
                put("元のクリップボード", on: pasteboard)
                let timing = ClipboardCopy.Timing(copyTimeout: 0.2, minimumCopyWait: 0.1, lateWriteWatch: 2)
                #expect(await ClipboardCopy.copySelection(from: pasteboard, timing: timing, isTargetFrontmost: { false }) {} == .nothing)
                put("ほかのアプリでのコピー", on: pasteboard)
                try await Task.sleep(for: .milliseconds(300))
                #expect(pasteboard.string(forType: .string) == "ほかのアプリでのコピー")
            }
        }

        @Test("何も書かれなければ、クリップボードはそのまま")
        func nothingCopied() async {
            await withPrivatePasteboard { pasteboard in
                put("元のクリップボード", on: pasteboard)
                let before = pasteboard.changeCount
                let timing = ClipboardCopy.Timing(copyTimeout: 0.1, minimumCopyWait: 0.05, lateWriteWatch: 0)
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

        @Test("読むと確認が出るときは、写すのも ⌘C の結果を読むのも、確認に答えるまで待つ")
        func askingWaitsForTheAnswer() {
            let limits = PasteboardSnapshot.Limits.standard
            let timing = ClipboardCopy.Timing.standard
            #expect(ClipboardCopy.captureLimits(limits, access: .asks, timing: timing).timeout(for: .asks) == limits.askTimeout)
            #expect(ClipboardCopy.readTimeout(access: .asks, remaining: 0.2, limits: limits) == limits.askTimeout)
            // 確認が出ないなら、残りの時間だけ
            #expect(ClipboardCopy.captureLimits(limits, access: .allowed, timing: timing).timeout <= timing.copyTimeout)
            #expect(ClipboardCopy.readTimeout(access: .allowed, remaining: 0.2, limits: limits) == 0.2)

            // ⌘C の後に待つ期限: 確認に答えるのに掛かった時間は数えない
            let start = ContinuousClock.now
            let afterSlowCapture = start + .seconds(5)
            #expect(ClipboardCopy.copyDeadline(start: start, afterCopy: afterSlowCapture, access: .asks, timing: timing)
                == afterSlowCapture + .seconds(timing.copyTimeout))
            // 確認が出ないなら写すのと合わせて copyTimeout、⌘C の後は最短 minimumCopyWait
            #expect(ClipboardCopy.copyDeadline(start: start, afterCopy: start + .milliseconds(10), access: .allowed, timing: timing)
                == start + .seconds(timing.copyTimeout))
            #expect(ClipboardCopy.copyDeadline(start: start, afterCopy: start + .milliseconds(900), access: .allowed, timing: timing)
                == start + .milliseconds(900) + .seconds(timing.minimumCopyWait))
        }
    }

    @Suite("⌘V で選択を置き換える")
    @MainActor
    struct Paste {
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

        @Test("戻す前に次の操作が始まったら、先に元に戻してから写す（貼り付けた結果を利用者のクリップボードとして残さない）")
        func nextOperationRestoresFirst() async throws {
            try await withPrivatePasteboard { pasteboard in
                put("元のクリップボード", on: pasteboard)
                _ = try await ClipboardPaste.paste("AI の結果", to: pasteboard, timing: .init(fallback: 0.8)) {}
                #expect(pasteboard.types?.contains(PasteboardWriter.transientType) == true)
                let outcome = await ClipboardCopy.copySelection(from: pasteboard) {
                    put("次の選択", on: pasteboard)
                }
                #expect(outcome == .copied("次の選択"))
                #expect(pasteboard.string(forType: .string) == "元のクリップボード")
                // 前の貼り付けの戻す処理は、もう何もしない
                try await Task.sleep(for: .milliseconds(1000))
                #expect(pasteboard.string(forType: .string) == "元のクリップボード")
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

    @Suite("クリップボードを裏で読む口")
    struct Reader {
        @Test("時間切れの後も読み終えるまでは次を読まず、読み終えたらまた読める")
        func oneReadAtATime() async {
            let reader = PasteboardReader()
            let first = await reader.read(timeout: 0.05) { () -> Int in
                Thread.sleep(forTimeInterval: 0.4)
                return 1
            }
            guard case .timedOut = first else {
                Issue.record("\(first)")
                return
            }
            #expect(reader.isBusy)
            guard case .busy = await reader.read(timeout: 1, { 2 }) else {
                Issue.record("前の読み取りが続いているのに読んだ")
                return
            }
            _ = await waitUntil { !reader.isBusy }
            guard case .done(let value) = await reader.read(timeout: 1, { 3 }) else {
                Issue.record("読み終えた後に読めない")
                return
            }
            #expect(value == 3)
        }
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

    /// アクションの結果は、ほかのアクションが ⌘C で読んでいる・⌘V で貼っている間は書かず、終わってから書く
    /// （読み取りの最中に書くと、その結果を選択中のテキストと取り違え、戻すときに消してしまう）
    @MainActor @Test func resultWritesWaitForAClipboardOperation() async {
        await withPrivatePasteboard { pasteboard in
            put("before", on: pasteboard)
            let session = ClipboardSession.of(pasteboard)
            var release: CheckedContinuation<Void, Never>?
            let holder = Task { @MainActor in
                await session.exclusive { _ in
                    await withCheckedContinuation { release = $0 }
                }
            }
            while release == nil { await Task.yield() }
            let writer = Task { @MainActor in await PasteboardWriter.writeAfterOtherOperations("result", to: pasteboard) }
            for _ in 0..<50 { await Task.yield() }
            #expect(pasteboard.string(forType: .string) == "before")
            release?.resume()
            _ = await writer.value
            await holder.value
            #expect(pasteboard.string(forType: .string) == "result")
        }
    }
}

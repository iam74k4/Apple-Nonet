// 担当: platform-actions
import AppKit

/// クリップボードの中身の写し。⌘C / ⌘V で一時的に使った後に元へ戻す。
/// 読むのはメインスレッドの外で、制限時間と大きさの上限を付ける。中身を求められてから作るアプリ（表計算の範囲の画像、
/// Finder の大量のファイルのアイコンなど）は渡すのに何秒もかかり、メインスレッドで待つとイベントタップが止まって
/// Mac 全体のキー入力が詰まるため。写せなければクリップボードには触らない
struct PasteboardSnapshot: Sendable {
    struct Limits: Sendable {
        /// 写す中身の合計の上限（バイト）
        var maxBytes = 16 * 1024 * 1024
        /// 読み終えるまでの制限時間
        var timeout: TimeInterval = 1
        /// 読むたびに確認が出る設定（.ask）のときの制限時間。利用者が確認に答えるのを待つ
        var askTimeout: TimeInterval = 20

        static let standard = Limits()
    }

    /// 写せなかった理由
    enum Failure: Error, Equatable, Sendable {
        /// クリップボードを読むことが許可されていない（システム設定で「常に拒否」）
        case denied
        /// 中身が大きすぎる
        case tooLarge
        /// 時間内に読み終わらない
        case tooSlow
        /// ファイルの約束（貼り付けたときに元のアプリが作るファイル）など、写しでは戻せないもの
        case unrestorable
        /// 中身を読めない・読んでいる間に変わった
        case unreadable
    }

    struct Entry: Sendable {
        let type: String
        let data: Data
    }

    /// パスワード管理アプリなどが付ける印（nspasteboard.org の取り決め）
    static let concealedType = "org.nspasteboard.ConcealedType"
    /// 中身を求められてから作るファイル。読むと元のアプリにファイルを作らせてしまい、写しても戻せない
    static let promisedTypes: Set<String> = [
        "com.apple.NSFilePromiseItemMetaData",
        "com.apple.pasteboard.promised-file-url",
        "com.apple.pasteboard.promised-file-content-type",
        "com.apple.pasteboard.promised-suggested-file-name",
    ]

    /// 写した時点の changeCount
    let changeCount: Int
    /// パスワードなど。中身は読まず、戻さない（戻すと changeCount が変わり、パスワード管理アプリが時間で消す対象から外れて残り続ける）
    let isConcealed: Bool
    private let items: [[Entry]]

    private init(changeCount: Int, isConcealed: Bool, items: [[Entry]]) {
        self.changeCount = changeCount
        self.isConcealed = isConcealed
        self.items = items
    }

    var isEmpty: Bool { items.isEmpty }

    /// 写した中身の合計のバイト数
    var byteCount: Int {
        items.joined().reduce(0) { $0 + $1.data.count }
    }

    /// メインスレッドの外で写す。読む許可が無い・大きすぎる・時間内に読めない・戻せない中身なら失敗
    @MainActor
    static func capture(_ pasteboard: NSPasteboard, limits: Limits = .standard) async -> Result<PasteboardSnapshot, Failure> {
        let access = PasteboardAccess.of(pasteboard)
        if access == .denied { return .failure(.denied) }
        let name = pasteboard.name
        let timeout = access == .asks ? limits.askTimeout : limits.timeout
        let deadline = Date().addingTimeInterval(timeout)
        let maxBytes = limits.maxBytes
        let result = await BlockingCall.run(timeout: timeout, fallback: Result<PasteboardSnapshot, Failure>.failure(.tooSlow)) {
            read(NSPasteboard(name: name), maxBytes: maxBytes, deadline: deadline)
        }
        // 読んでいる間に誰かが書いたら、写しは今の中身ではない
        if case .success(let snapshot) = result, snapshot.changeCount != pasteboard.changeCount {
            return .failure(.unreadable)
        }
        return result
    }

    /// 中身を読む。元のアプリが応答するまで待つことがあるので、メインスレッドでは呼ばない。
    /// 型の一覧は安く分かるので、先に一覧で判断してから中身を読む
    static func read(_ pasteboard: NSPasteboard, maxBytes: Int, deadline: Date) -> Result<PasteboardSnapshot, Failure> {
        let changeCount = pasteboard.changeCount
        let pasteboardItems = pasteboard.pasteboardItems ?? []
        let declared = pasteboardItems.map(\.types)
        let allTypes = Set(declared.joined().map(\.rawValue))
        if allTypes.contains(concealedType) {
            return .success(PasteboardSnapshot(changeCount: changeCount, isConcealed: true, items: []))
        }
        if !allTypes.isDisjoint(with: promisedTypes) { return .failure(.unrestorable) }
        var total = 0
        var items: [[Entry]] = []
        for (item, types) in zip(pasteboardItems, declared) {
            var entries: [Entry] = []
            for type in types {
                guard Date() < deadline else { return .failure(.tooSlow) }
                // 元のアプリが渡せなかった型は飛ばす（前と同じ）。すべて読めなければ下で失敗にする
                guard let data = item.data(forType: type) else { continue }
                total += data.count
                guard total <= maxBytes else { return .failure(.tooLarge) }
                entries.append(Entry(type: type.rawValue, data: data))
            }
            items.append(entries)
        }
        // 型があるのに何も読めない（読むことを拒まれたなど）。空として戻すとクリップボードを消してしまう
        if !allTypes.isEmpty && items.allSatisfy(\.isEmpty) { return .failure(.unreadable) }
        guard Date() < deadline else { return .failure(.tooSlow) }
        return .success(PasteboardSnapshot(changeCount: changeCount, isConcealed: false, items: items))
    }

    @MainActor
    func restore(to pasteboard: NSPasteboard) {
        guard !isConcealed else { return }
        pasteboard.clearContents()
        let restored = items.compactMap { entries -> NSPasteboardItem? in
            guard !entries.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for entry in entries { item.setData(entry.data, forType: NSPasteboard.PasteboardType(entry.type)) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}

/// クリップボードを読むことへの、利用者の設定（macOS 15.4 以降の「ほかのアプリからのペースト」の確認）
enum PasteboardAccess: Equatable, Sendable {
    /// 確認なしで読める（macOS 15.4 より前も）。まだ確認を出したことがない .default もここ
    /// （確認が出る Mac では、最初に読んだときに確認が出て .ask に変わる）
    case allowed
    /// 読むたびに確認が出る
    case asks
    /// 読めない。読もうとしても空が返る
    case denied

    static func of(_ pasteboard: NSPasteboard) -> PasteboardAccess {
        if #available(macOS 15.4, *) {
            return PasteboardAccess(pasteboard.accessBehavior)
        }
        return .allowed
    }

    @available(macOS 15.4, *)
    init(_ behavior: NSPasteboard.AccessBehavior) {
        switch behavior {
        case .alwaysDeny: self = .denied
        case .ask: self = .asks
        case .default, .alwaysAllow: self = .allowed
        @unknown default: self = .allowed
        }
    }
}

enum PasteboardWriter {
    /// クリップボード履歴のアプリに残さないための印（nspasteboard.org の取り決め）
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// 文字列を書き、書いた後の changeCount を返す
    @MainActor
    @discardableResult
    static func write(_ text: String, to pasteboard: NSPasteboard, transient: Bool = false) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if transient { item.setData(Data(), forType: transientType) }
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    /// 文字列を「読まれたときに渡す」形で書く（履歴のアプリに残さない印つき）。いつ読まれたかが provider で分かる
    @MainActor
    static func writeOnDemand(_ provider: PasteDataProvider, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        item.setData(Data(), forType: transientType)
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }
}

/// 貼り付ける文字列を、読まれたときに渡す。読まれた時刻を覚えておき、相手が読み終えてから元のクリップボードに戻す
final class PasteDataProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let text: String
    private let lock = NSLock()
    private var firstRequest: Date?

    init(text: String) {
        self.text = text
    }

    /// 最初に読まれた時刻。まだなら nil
    var requestedAt: Date? {
        lock.lock()
        defer { lock.unlock() }
        return firstRequest
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        lock.lock()
        if firstRequest == nil { firstRequest = Date() }
        lock.unlock()
        item.setString(text, forType: type)
    }
}

/// ⌘C を送って選択テキストを読み、クリップボードを元に戻す
enum ClipboardCopy {
    struct Timing: Sendable {
        /// ⌘C の後、アプリが書くのを待つ上限
        var copyTimeout: TimeInterval = 1
        /// 確かめる間隔。最初は短く、だんだん長く
        var firstPoll: TimeInterval = 0.01
        var maxPoll: TimeInterval = 0.05
        /// 待ちきれなかった後も見張る時間。遅れて書かれたら元に戻す
        var lateWriteWatch: TimeInterval = 2

        static let standard = Timing()
    }

    enum Outcome: Equatable, Sendable {
        case copied(String)
        /// ⌘C を送ったが、テキストは来なかった
        case nothing
        /// クリップボードの中身を保てないので、⌘C を送らなかった
        case clipboardUnavailable(PasteboardSnapshot.Failure)
        /// ⌘C を送れなかった
        case failed
    }

    @MainActor
    static func copySelection(
        from pasteboard: NSPasteboard,
        limits: PasteboardSnapshot.Limits = .standard,
        timing: Timing = .standard,
        sendCopy: @MainActor () async throws -> Void
    ) async -> Outcome {
        let snapshot: PasteboardSnapshot
        switch await PasteboardSnapshot.capture(pasteboard, limits: limits) {
        case .success(let captured):
            snapshot = captured
        case .failure(let failure):
            ActionLog.logger.notice("クリップボードの中身を保てないため、⌘C は送りません（\(String(describing: failure), privacy: .public)）")
            return .clipboardUnavailable(failure)
        }
        let before = pasteboard.changeCount
        do {
            try await sendCopy()
        } catch {
            ActionLog.logger.notice("選択テキストを ⌘C で取れませんでした: \(error.localizedDescription)")
            return .failed
        }
        // アプリがクリップボードに書くのを待つ。消してから書くアプリもあるので、文字が来るまで見る
        let name = pasteboard.name
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(timing.copyTimeout)
        var interval = timing.firstPoll
        var written: Int?
        var text: String?
        while clock.now < deadline {
            try? await Task.sleep(for: .seconds(interval))
            interval = min(interval * 2, timing.maxPoll)
            let count = pasteboard.changeCount
            guard count != before else { continue }
            written = count
            let remaining = max(0.05, Self.seconds(deadline - clock.now))
            text = await BlockingCall.run(timeout: remaining, fallback: nil) {
                NSPasteboard(name: name).string(forType: .string)
            }
            if text != nil { break }
        }
        guard let written else {
            watchForLateWrite(pasteboard, before: before, snapshot: snapshot, duration: timing.lateWriteWatch)
            return .nothing
        }
        // ⌘C で書かれたままなら戻す。その後に利用者がコピーしたものは消さない
        if pasteboard.changeCount == written {
            snapshot.restore(to: pasteboard)
        }
        guard let text, !text.isEmpty else { return .nothing }
        return .copied(text)
    }

    /// 遅れて書くアプリのために見張り、書かれたら元に戻す（選択テキストで利用者のクリップボードを置き換えたままにしない）
    @MainActor
    private static func watchForLateWrite(_ pasteboard: NSPasteboard, before: Int, snapshot: PasteboardSnapshot, duration: TimeInterval) {
        guard duration > 0 else { return }
        Task { @MainActor in
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(duration)
            while clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
                if pasteboard.changeCount != before {
                    ActionLog.logger.notice("⌘C の結果が遅れて届いたので、クリップボードを元に戻しました")
                    snapshot.restore(to: pasteboard)
                    return
                }
            }
        }
    }

    static func seconds(_ duration: Duration) -> TimeInterval {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}

/// 結果をクリップボード経由で ⌘V し、相手が読み終えてから元のクリップボードに戻す
enum ClipboardPaste {
    struct Timing: Sendable {
        /// 読まれてから戻すまで
        var settle: TimeInterval = 0.2
        /// ⌘V から戻すまでの最短
        var minimumDelay: TimeInterval = 0.6
        /// 読まれないままのときに戻すまで。リモートデスクトップなどは貼り付けを遅れて読む
        var fallback: TimeInterval = 3

        static let standard = Timing()
    }

    enum Outcome: Equatable, Sendable {
        case pasted
        /// クリップボードの中身を保てないので、貼り付けなかった（クリップボードには触っていない）
        case clipboardUnavailable(PasteboardSnapshot.Failure)
    }

    @MainActor
    static func paste(
        _ text: String,
        to pasteboard: NSPasteboard,
        limits: PasteboardSnapshot.Limits = .standard,
        timing: Timing = .standard,
        sendPaste: @MainActor () async throws -> Void
    ) async throws -> Outcome {
        let snapshot: PasteboardSnapshot
        switch await PasteboardSnapshot.capture(pasteboard, limits: limits) {
        case .success(let captured):
            snapshot = captured
        case .failure(let failure):
            ActionLog.logger.notice("クリップボードの中身を保てないため、貼り付けません（\(String(describing: failure), privacy: .public)）")
            return .clipboardUnavailable(failure)
        }
        let provider = PasteDataProvider(text: text)
        let changeCount = PasteboardWriter.writeOnDemand(provider, to: pasteboard)
        do {
            try await sendPaste()
        } catch {
            if pasteboard.changeCount == changeCount { snapshot.restore(to: pasteboard) }
            throw error
        }
        let pastedAt = Date()
        Task { @MainActor in
            // 相手が読み終えるのを待つ。その間に利用者がコピーしたものは消さない
            while !Self.isTimeToRestore(now: Date(), pastedAt: pastedAt, requestedAt: provider.requestedAt, timing: timing) {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if pasteboard.changeCount == changeCount { snapshot.restore(to: pasteboard) }
        }
        return .pasted
    }

    /// 読まれたら少し待ってから（ただし ⌘V から minimumDelay は待つ）、読まれないままなら fallback で戻す
    static func isTimeToRestore(now: Date, pastedAt: Date, requestedAt: Date?, timing: Timing) -> Bool {
        let sincePaste = now.timeIntervalSince(pastedAt)
        if sincePaste >= timing.fallback { return true }
        guard let requestedAt else { return false }
        return sincePaste >= timing.minimumDelay && now.timeIntervalSince(requestedAt) >= timing.settle
    }
}

// 担当: platform-actions
import AppKit
import ApplicationServices
import UniformTypeIdentifiers

/// クリップボードの中身の写し。⌘C / ⌘V で一時的に使った後に元へ戻す。
/// 中身を読むのはメインスレッドの外（PasteboardReader）で、制限時間と大きさの上限を付ける。中身を求められてから作るアプリ
/// （表計算の範囲の画像、Finder の大量のファイルのアイコンなど）は渡すのに何秒もかかり、メインスレッドで待つとイベントタップが
/// 止まって Mac 全体のキー入力が詰まるため。写せなければクリップボードには触らない
struct PasteboardSnapshot: Sendable {
    struct Limits: Sendable {
        /// 写す中身の合計の上限（バイト）。写真をコピーしたときの TIFF（1200 万画素で約 48 MB）も写せるように
        var maxBytes = 64 * 1024 * 1024
        /// 読み終えるまでの制限時間
        var timeout: TimeInterval = 1
        /// 読むと確認が出ることがある（PasteboardAccess.asks）ときの制限時間。利用者が確認に答えるのを待つ
        var askTimeout: TimeInterval = 20

        static let standard = Limits()

        func timeout(for access: PasteboardAccess) -> TimeInterval {
            access == .asks ? askTimeout : timeout
        }
    }

    /// 写せなかった理由
    enum Failure: Error, Equatable, Sendable {
        /// クリップボードを読むことが許可されていない（システム設定で「常に拒否」）
        case denied
        /// 中身が大きすぎる
        case tooLarge
        /// 時間内に読み終わらない（前の読み取りがまだ続いているときも）
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
    static let utf8TextType = "public.utf8-plain-text"
    /// public.utf8-plain-text からシステムが作る形。戻した後もシステムが作り直すので写さない
    static let utf16ExternalTextType = "public.utf16-external-plain-text"
    static let fileURLType = "public.file-url"

    /// パスワードなど。中身は読まず、戻さない（戻すと changeCount が変わり、パスワード管理アプリが時間で消す対象から外れて残り続ける）
    let isConcealed: Bool
    private let items: [[Entry]]

    private init(isConcealed: Bool, items: [[Entry]]) {
        self.isConcealed = isConcealed
        self.items = items
    }

    var isEmpty: Bool { items.isEmpty }

    /// 写した中身の合計のバイト数
    var byteCount: Int {
        items.joined().reduce(0) { $0 + $1.data.count }
    }

    /// 写した型（項目ごと）
    var types: [[String]] {
        items.map { $0.map(\.type) }
    }

    /// 項目の型のうち、写すものを選ぶ（並びは元のまま）。
    /// 画像（PDF を含む）は同じものの描き方の違いなので、項目ごとに最初の1つだけを写し、ファイルの項目では写さない（ファイルそのものが中身）。
    /// 表計算の範囲の PDF・TIFF や Finder のアイコンは、求められてから作るので何秒もかかり、写しも大きくなるため
    static func typesToRead(_ types: [String]) -> [String] {
        let declared = Set(types)
        let isFile = declared.contains(fileURLType)
        var hasImage = false
        return types.filter { type in
            if type == utf16ExternalTextType && declared.contains(utf8TextType) { return false }
            guard isRendering(type) else { return true }
            if isFile || hasImage { return false }
            hasImage = true
            return true
        }
    }

    static func isRendering(_ type: String) -> Bool {
        guard let uti = UTType(type) else { return false }
        return uti.conforms(to: .image) || uti.conforms(to: .pdf)
    }

    /// 写す。読む許可が無い・大きすぎる・時間内に読めない・戻せない中身なら失敗。
    /// 型の一覧はクリップボードのサーバーが持っていて元のアプリには聞かないので、メインスレッドで読む。中身は PasteboardReader で読む
    @MainActor
    static func capture(_ pasteboard: NSPasteboard, limits: Limits = .standard) async -> Result<PasteboardSnapshot, Failure> {
        let session = ClipboardSession.of(pasteboard)
        // Nonet が貼り付けた結果をまだ戻していなければ、今すぐ戻して、その写しを使う（利用者のクリップボードはその写し）
        if let pending = session.takePendingRestore(changeCount: pasteboard.changeCount) {
            pending.restore(to: pasteboard)
            return .success(pending)
        }
        let access = PasteboardAccess.of(pasteboard)
        if access == .denied { return .failure(.denied) }
        let changeCount = pasteboard.changeCount
        let pasteboardItems = pasteboard.pasteboardItems ?? []
        let declared = pasteboardItems.map { $0.types.map(\.rawValue) }
        let allTypes = Set(declared.joined())
        if allTypes.contains(concealedType) {
            return .success(PasteboardSnapshot(isConcealed: true, items: []))
        }
        if !allTypes.isDisjoint(with: promisedTypes) { return .failure(.unrestorable) }
        let plan = declared.map(typesToRead)
        let maxBytes = limits.maxBytes
        let result: Result<[[Entry]], Failure>
        if session.isOwnContent(changeCount) {
            // Nonet が書いた中身（前に戻したものなど）はこのプロセスの中にあり、待たずに読める。
            // 裏のスレッドで読むと、このプロセスの中で中身を渡す処理が裏のスレッドで動いてしまうので、ここで読む
            result = readEntries(plan, maxBytes: maxBytes, deadline: .distantFuture) { index, type in
                pasteboardItems[index].data(forType: NSPasteboard.PasteboardType(type))
            }
        } else {
            let timeout = limits.timeout(for: access)
            let deadline = Date().addingTimeInterval(timeout)
            let name = pasteboard.name
            let count = plan.count
            let outcome = await PasteboardReader.shared.read(timeout: timeout) { () -> Result<[[Entry]], Failure> in
                guard let carbon = CarbonPasteboard(name: name), carbon.itemCount == count else { return .failure(.unreadable) }
                return readEntries(plan, maxBytes: maxBytes, deadline: deadline, data: carbon.data(item:type:))
            }
            switch outcome {
            case .done(let read):
                result = read
            case .timedOut, .busy:
                return .failure(.tooSlow)
            }
        }
        // 読んでいる間に誰かが書いたら、写しは今の中身ではない
        guard pasteboard.changeCount == changeCount else { return .failure(.unreadable) }
        switch result {
        case .success(let items):
            // 型があるのに何も読めない（読むことを拒まれたなど）。空として戻すとクリップボードを消してしまう
            if !plan.joined().isEmpty && items.allSatisfy(\.isEmpty) {
                return .failure(PasteboardAccess.of(pasteboard) == .denied ? .denied : .unreadable)
            }
            return .success(PasteboardSnapshot(isConcealed: false, items: items))
        case .failure(let failure):
            return .failure(failure)
        }
    }

    /// 選んだ型の中身を読む。元のアプリが渡せなかった型は飛ばす。大きすぎる・時間切れなら失敗
    static func readEntries(
        _ plan: [[String]],
        maxBytes: Int,
        deadline: Date,
        data: (_ item: Int, _ type: String) -> Data?
    ) -> Result<[[Entry]], Failure> {
        var total = 0
        var items: [[Entry]] = []
        for (index, types) in plan.enumerated() {
            var entries: [Entry] = []
            for type in types {
                guard Date() < deadline else { return .failure(.tooSlow) }
                guard let value = data(index, type) else { continue }
                total += value.count
                guard total <= maxBytes else { return .failure(.tooLarge) }
                entries.append(Entry(type: type, data: value))
            }
            items.append(entries)
        }
        guard Date() < deadline else { return .failure(.tooSlow) }
        return .success(items)
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
        ClipboardSession.of(pasteboard).didWrite(pasteboard.changeCount)
    }
}

/// クリップボードを読むことへの、利用者の設定（macOS 15.4 以降の「ほかのアプリからのペースト」の確認）
enum PasteboardAccess: Equatable, Sendable {
    /// 確認なしで読める（macOS 15.4 より前も）
    case allowed
    /// 読むと確認が出ることがある。利用者が答えるまで読み終わらない
    case asks
    /// 読めない。読もうとしても空が返る
    case denied

    static func of(_ pasteboard: NSPasteboard) -> PasteboardAccess {
        if #available(macOS 15.4, *) {
            return PasteboardAccess(pasteboard.accessBehavior, isGeneral: pasteboard.name == .general)
        }
        return .allowed
    }

    /// .default は、一般のクリップボードでは「読むと確認が出る」（最初の確認の後は .ask に変わる）。ほかのクリップボードでは確認なし
    @available(macOS 15.4, *)
    init(_ behavior: NSPasteboard.AccessBehavior, isGeneral: Bool) {
        switch behavior {
        case .alwaysDeny: self = .denied
        case .ask: self = .asks
        case .default: self = isGeneral ? .asks : .allowed
        case .alwaysAllow: self = .allowed
        @unknown default: self = isGeneral ? .asks : .allowed
        }
    }
}

/// クリップボードを裏で読む口。読むのは専用の直列のキューで、一度に1つだけ。
/// NSPasteboard はスレッドセーフではなく、NSPasteboard(name:) はいつも同じオブジェクト（一般のクリップボードなら NSPasteboard.general）
/// を返す。裏のスレッドで NSPasteboard を読むと、メインスレッドの書き込み（元に戻す・結果のパネルのコピー・設定ウインドウでのコピー）
/// と重なって落ちる。そこで裏では CarbonPasteboard（別のオブジェクト）で読み、NSPasteboard はメインスレッドだけで使う。
/// Carbon の参照どうしも同時に使うと落ちるので、時間切れの後も前の読み取りが続いている間は、新しく読み始めない（.busy）
final class PasteboardReader: @unchecked Sendable {
    enum Outcome<Value> {
        case done(Value)
        /// 制限時間を過ぎた。読み取りは裏で続いている
        case timedOut
        /// 前の読み取りがまだ続いているので、読まなかった
        case busy
    }

    static let shared = PasteboardReader()

    private let queue = DispatchQueue(label: "com.iam74k4.Nonet.pasteboard-reader", qos: .userInitiated)
    private let lock = NSLock()
    private var isReading = false

    /// 読み取りが続いているか（時間切れの後も、終わるまで true）
    var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isReading
    }

    func read<Value>(timeout: TimeInterval, _ body: @escaping @Sendable () -> Value) async -> Outcome<Value> {
        guard begin() else { return .busy }
        return await BlockingCall.run(timeout: timeout, fallback: Outcome<Value>.timedOut, queue: queue) { [self] in
            defer { finish() }
            return .done(body())
        }
    }

    private func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isReading else { return false }
        isReading = true
        return true
    }

    private func finish() {
        lock.lock()
        isReading = false
        lock.unlock()
    }
}

/// Carbon の Pasteboard Manager で読む。NSPasteboard とは別のオブジェクトなので、メインスレッドで NSPasteboard を使っている間も
/// 裏のスレッドで読める。参照どうしは同時に使えないので、PasteboardReader のキューの中だけで作って使う
struct CarbonPasteboard {
    private let pasteboard: Pasteboard
    private let items: [PasteboardItemID]

    init?(name: NSPasteboard.Name) {
        var created: Pasteboard?
        guard PasteboardCreate(name.rawValue as CFString, &created) == noErr, let created else { return nil }
        PasteboardSynchronize(created)
        var count = 0
        guard PasteboardGetItemCount(created, &count) == noErr else { return nil }
        var items: [PasteboardItemID] = []
        for index in stride(from: 1, through: count, by: 1) {
            var item: PasteboardItemID?
            guard PasteboardGetItemIdentifier(created, index, &item) == noErr, let item else { return nil }
            items.append(item)
        }
        pasteboard = created
        self.items = items
    }

    var itemCount: Int { items.count }

    /// item は 0 から（NSPasteboard の pasteboardItems と同じ並び）
    func data(item index: Int, type: String) -> Data? {
        guard items.indices.contains(index) else { return nil }
        var data: CFData?
        guard PasteboardCopyItemFlavorData(pasteboard, items[index], type as CFString, &data) == noErr, let data else { return nil }
        return data as Data
    }

    /// 文字を持つ最初の項目の文字（NSPasteboard の string(forType: .string) と同じ）
    func string() -> String? {
        for index in items.indices {
            if let data = data(item: index, type: PasteboardSnapshot.utf8TextType) {
                return String(decoding: data, as: UTF8.self)
            }
            if let data = data(item: index, type: PasteboardSnapshot.utf16ExternalTextType), let text = String(data: data, encoding: .utf16) {
                return text
            }
        }
        return nil
    }
}

/// Nonet がクリップボードを一時的に使う操作（⌘C で読む・⌘V で貼る）の順番と後始末。クリップボードの名前ごとに1つ。
/// 操作は1つずつ行う（前の操作が戻し終えてから、次の操作が写す）。新しい操作や書き込みが始まると、前の操作の見張り
/// （遅れて届いた ⌘C を戻す）はやめる。まだ戻していない貼り付けは、次の操作が始めに戻す
@MainActor
final class ClipboardSession {
    private static var sessions: [String: ClipboardSession] = [:]

    static func of(_ pasteboard: NSPasteboard) -> ClipboardSession {
        let key = pasteboard.name.rawValue
        if let session = sessions[key] { return session }
        let session = ClipboardSession()
        sessions[key] = session
        return session
    }

    /// 操作や書き込みが始まるたびに増える。見張りは、これが変わったらやめる
    private(set) var generation = 0
    /// Nonet が最後に書いた後の changeCount
    private var ownChangeCount: Int?
    private var pending: (token: Int, snapshot: PasteboardSnapshot, changeCount: Int)?
    private var nextToken = 0
    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// 前の操作が終わるのを待ってから、新しい操作として body を行う
    func exclusive<T>(_ body: (_ generation: Int) async throws -> T) async rethrows -> T {
        if isRunning {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isRunning = true
        }
        defer {
            if waiters.isEmpty {
                isRunning = false
            } else {
                waiters.removeFirst().resume()
            }
        }
        let generation = begin()
        return try await body(generation)
    }

    /// 新しい操作や書き込みを始める。前の操作の見張りはやめる
    @discardableResult
    func begin() -> Int {
        generation += 1
        return generation
    }

    /// Nonet が書いた。今の中身はこのプロセスの中にある
    func didWrite(_ changeCount: Int) {
        ownChangeCount = changeCount
    }

    func isOwnContent(_ changeCount: Int) -> Bool {
        ownChangeCount == changeCount
    }

    /// 貼り付けた後、相手が読み終えてから戻す写し。戻す前に次の操作が始まったら、その操作が戻す
    func setPendingRestore(_ snapshot: PasteboardSnapshot, changeCount: Int) -> Int {
        nextToken += 1
        pending = (nextToken, snapshot, changeCount)
        return nextToken
    }

    func isPending(_ token: Int) -> Bool {
        pending?.token == token
    }

    /// token の写しがまだ戻されていなければ、戻す役を引き受ける
    func claimPendingRestore(_ token: Int) -> PasteboardSnapshot? {
        guard let pending, pending.token == token else { return nil }
        self.pending = nil
        return pending.snapshot
    }

    /// 次の操作が始めに呼ぶ。クリップボードがまだ貼り付けた結果のままなら、その写し（戻すもの）を渡す
    func takePendingRestore(changeCount: Int) -> PasteboardSnapshot? {
        guard let pending else { return nil }
        self.pending = nil
        return pending.changeCount == changeCount ? pending.snapshot : nil
    }
}

enum PasteboardWriter {
    /// クリップボード履歴のアプリに残さないための印（nspasteboard.org の取り決め）
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// 文字列を書き、書いた後の changeCount を返す。Nonet の操作の見張り（遅れて届いた ⌘C を戻す）はやめる
    @MainActor
    @discardableResult
    static func write(_ text: String, to pasteboard: NSPasteboard, transient: Bool = false) -> Int {
        let session = ClipboardSession.of(pasteboard)
        session.begin()
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if transient { item.setData(Data(), forType: transientType) }
        pasteboard.writeObjects([item])
        session.didWrite(pasteboard.changeCount)
        return pasteboard.changeCount
    }

    /// アクションの結果をクリップボードに書く。ほかのアクションが ⌘C で選択中のテキストを読んでいる・⌘V で貼り付けている間は、
    /// それが終わるのを待ってから書く（読み取りの最中に書くと、その結果を選択中のテキストと取り違え、戻すときに消してしまう）
    @MainActor
    @discardableResult
    static func writeAfterOtherOperations(_ text: String, to pasteboard: NSPasteboard) async -> Int {
        await ClipboardSession.of(pasteboard).exclusive { _ in
            write(text, to: pasteboard)
        }
    }

    /// 文字列を「読まれたときに渡す」形で書く（履歴のアプリに残さない印つき）。いつ読まれたかが provider で分かる
    @MainActor
    static func writeOnDemand(_ provider: PasteDataProvider, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        item.setData(Data(), forType: transientType)
        pasteboard.writeObjects([item])
        ClipboardSession.of(pasteboard).didWrite(pasteboard.changeCount)
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
        /// 写すのと、⌘C の後にアプリが書くのを待つのとを合わせた上限（読むと確認が出るときの読み取りは除く）。
        /// 実行の順番は文脈を読み終えるころ（1 秒）に後のマスへ譲るので、普段はそれより長く掛けない
        var copyTimeout: TimeInterval = 1
        /// 写すのに時間が掛かっても、⌘C の後はこれだけは待つ
        var minimumCopyWait: TimeInterval = 0.3
        /// 確かめる間隔。最初は短く、だんだん長く
        var firstPoll: TimeInterval = 0.01
        var maxPoll: TimeInterval = 0.05
        /// 待ちきれなかった後も見張る時間。この間に最初に書かれたものが遅れて届いた選択なら、元に戻す。
        /// 利用者が自分でコピーしたものを戻さないよう短くし、ほかの操作が始まったらやめる
        var lateWriteWatch: TimeInterval = 0.5

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

    /// isTargetFrontmost: ⌘C を送るアプリがまだ前面にあるか。遅れて書かれたものを戻すのは、そのアプリが前面のままのときだけ
    @MainActor
    static func copySelection(
        from pasteboard: NSPasteboard,
        limits: PasteboardSnapshot.Limits = .standard,
        timing: Timing = .standard,
        isTargetFrontmost: @escaping @MainActor () -> Bool = { true },
        sendCopy: @MainActor () async throws -> Void
    ) async -> Outcome {
        let session = ClipboardSession.of(pasteboard)
        return await session.exclusive { generation in
            let clock = ContinuousClock()
            let start = clock.now
            let access = PasteboardAccess.of(pasteboard)
            let snapshot: PasteboardSnapshot
            switch await PasteboardSnapshot.capture(pasteboard, limits: captureLimits(limits, access: access, timing: timing)) {
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
            let deadline = copyDeadline(start: start, afterCopy: clock.now, access: access, timing: timing)
            var interval = timing.firstPoll
            var written: Int?
            var text: String?
            while clock.now < deadline {
                try? await Task.sleep(for: .seconds(interval))
                interval = min(interval * 2, timing.maxPoll)
                let count = pasteboard.changeCount
                guard count != before else { continue }
                written = count
                let timeout = readTimeout(access: access, remaining: seconds(deadline - clock.now), limits: limits)
                // 前の読み取りが続いている（.busy）・時間切れなら、次の確認でもう一度
                if case .done(let value) = await readString(pasteboard, timeout: timeout) {
                    text = value
                }
                if text != nil { break }
            }
            guard let written else {
                watchForLateWrite(
                    pasteboard,
                    session: session,
                    generation: generation,
                    before: before,
                    snapshot: snapshot,
                    duration: timing.lateWriteWatch,
                    isTargetFrontmost: isTargetFrontmost
                )
                return .nothing
            }
            // ⌘C で書かれたままなら戻す。その後に利用者がコピーしたものは消さない
            if pasteboard.changeCount == written {
                snapshot.restore(to: pasteboard)
            }
            guard let text, !text.isEmpty else { return .nothing }
            return .copied(text)
        }
    }

    /// 写すときの制限時間。確認が出ないなら、⌘C の結果を待つのと合わせて copyTimeout に収める
    static func captureLimits(_ limits: PasteboardSnapshot.Limits, access: PasteboardAccess, timing: Timing) -> PasteboardSnapshot.Limits {
        guard access != .asks else { return limits }
        var limits = limits
        limits.timeout = min(limits.timeout, timing.copyTimeout)
        return limits
    }

    /// ⌘C の後、アプリが書くのを待つ期限。確認が出ないなら、写すのに掛かった時間と合わせて copyTimeout まで（⌘C の後は最短 minimumCopyWait）。
    /// 確認が出るなら、写すのに掛かった時間（利用者が答えるまで）は数えず、⌘C から copyTimeout まで
    static func copyDeadline(
        start: ContinuousClock.Instant,
        afterCopy: ContinuousClock.Instant,
        access: PasteboardAccess,
        timing: Timing
    ) -> ContinuousClock.Instant {
        if access == .asks { return afterCopy + .seconds(timing.copyTimeout) }
        return max(start + .seconds(timing.copyTimeout), afterCopy + .seconds(timing.minimumCopyWait))
    }

    /// ⌘C で書かれた文字を読む制限時間。読むと確認が出るなら、利用者が答えるまで待つ
    static func readTimeout(access: PasteboardAccess, remaining: TimeInterval, limits: PasteboardSnapshot.Limits) -> TimeInterval {
        access == .asks ? limits.askTimeout : max(0.05, remaining)
    }

    @MainActor
    static func readString(_ pasteboard: NSPasteboard, timeout: TimeInterval) async -> PasteboardReader.Outcome<String?> {
        let name = pasteboard.name
        return await PasteboardReader.shared.read(timeout: timeout) {
            CarbonPasteboard(name: name)?.string()
        }
    }

    /// 遅れて書くアプリのために少しの間だけ見張り、最初に書かれたものが遅れて届いた選択なら元に戻す
    /// （選択テキストで利用者のクリップボードを置き換えたままにしない）。
    /// ほかの操作や書き込みが始まったら、⌘C を送ったアプリが前面でなくなっていたら、戻さない（利用者のコピーかもしれない）
    @MainActor
    private static func watchForLateWrite(
        _ pasteboard: NSPasteboard,
        session: ClipboardSession,
        generation: Int,
        before: Int,
        snapshot: PasteboardSnapshot,
        duration: TimeInterval,
        isTargetFrontmost: @escaping @MainActor () -> Bool
    ) {
        guard duration > 0 else { return }
        Task { @MainActor in
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(duration)
            while clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
                guard session.generation == generation else { return }
                guard pasteboard.changeCount != before else { continue }
                if isTargetFrontmost() {
                    ActionLog.logger.notice("⌘C の結果が遅れて届いたので、クリップボードを元に戻しました")
                    snapshot.restore(to: pasteboard)
                }
                return
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
        let session = ClipboardSession.of(pasteboard)
        return try await session.exclusive { _ in
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
            let token = session.setPendingRestore(snapshot, changeCount: changeCount)
            Task { @MainActor in
                // 相手が読み終えるのを待つ。その間に次の操作が始まったら、その操作が戻す。利用者がコピーしたものは消さない
                while !Self.isTimeToRestore(now: Date(), pastedAt: pastedAt, requestedAt: provider.requestedAt, timing: timing) {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard session.isPending(token) else { return }
                }
                guard let snapshot = session.claimPendingRestore(token) else { return }
                if pasteboard.changeCount == changeCount { snapshot.restore(to: pasteboard) }
            }
            return .pasted
        }
    }

    /// 読まれたら少し待ってから（ただし ⌘V から minimumDelay は待つ）、読まれないままなら fallback で戻す
    static func isTimeToRestore(now: Date, pastedAt: Date, requestedAt: Date?, timing: Timing) -> Bool {
        let sincePaste = now.timeIntervalSince(pastedAt)
        if sincePaste >= timing.fallback { return true }
        guard let requestedAt else { return false }
        return sincePaste >= timing.minimumDelay && now.timeIntervalSince(requestedAt) >= timing.settle
    }
}

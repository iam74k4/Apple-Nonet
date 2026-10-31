// 担当: engine
import Foundation

/// 実行を頼まれた順に始める。次の実行は、前の実行が終わるか順番を譲る（ControllerExecutionTurn.pass）まで始めない。
/// 続けて実行したときに順番が入れ替わらず、キー入力どうしが混ざらないように。
/// 長く掛かる実行（裏で動くスクリプトなど）は途中で順番を譲り、後のマスを終わるまで待たせない
@MainActor
final class ControllerExecutionQueue {
    private let scheduler: any Scheduler
    /// 最後に頼まれた実行の順番。次に頼まれた実行は、これが譲られるのを待つ
    private var lastTurn: ControllerExecutionTurn?
    /// 終わっていない実行（順番を譲った後も、終わるまでここに残る）
    private var unfinished: [Int: Task<Void, Never>] = [:]
    private var nextID = 0

    init(scheduler: any Scheduler) {
        self.scheduler = scheduler
    }

    /// 前に頼まれた実行が順番を譲ってから job を始める。job が終わると順番は自動で譲られる。
    /// 返す Task で job の結果を待てる
    @discardableResult
    func enqueue<T: Sendable>(_ job: @escaping @MainActor (ControllerExecutionTurn) async -> T) -> Task<T, Never> {
        let previous = lastTurn
        let turn = ControllerExecutionTurn(scheduler: scheduler)
        lastTurn = turn
        let task = Task { @MainActor in
            await previous?.wait()
            let result = await job(turn)
            turn.pass()
            return result
        }
        let id = nextID
        nextID += 1
        unfinished[id] = Task { @MainActor [weak self] in
            _ = await task.value
            self?.unfinished[id] = nil
        }
        return task
    }

    /// 頼まれた実行がすべて終わるまで待つ（順番を譲った後の実行と、待っている間に頼まれたものも含む）
    func waitUntilIdle() async {
        while let next = unfinished.values.first {
            await next.value
        }
    }
}

/// 1つの実行が持つ順番。譲る（pass）と、次に頼まれた実行が始まる
@MainActor
final class ControllerExecutionTurn {
    private let scheduler: any Scheduler
    private(set) var isPassed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var deadline: (any ScheduledTask)?

    init(scheduler: any Scheduler) {
        self.scheduler = scheduler
    }

    /// seconds が過ぎたら、終わっていなくても順番を譲る。前に決めた時間は置き換える
    func pass(after seconds: TimeInterval) {
        guard !isPassed else { return }
        deadline?.cancel()
        deadline = scheduler.schedule(after: max(0, seconds)) { [weak self] in
            self?.pass()
        }
    }

    func pass() {
        guard !isPassed else { return }
        isPassed = true
        deadline?.cancel()
        deadline = nil
        let waiting = waiters
        waiters.removeAll()
        for waiter in waiting {
            waiter.resume()
        }
    }

    /// 譲られるまで待つ
    func wait() async {
        guard !isPassed else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// アクションの種類ごとの、実行の順番の扱い
enum ControllerExecutionPolicy {
    /// 長く掛かるアクションが、後の実行を待たせる最長の時間。始めに前面アプリの選択テキストや URL を読む
    /// （⌘C を送ることもある）ので、読み終えるまでは後のキー入力（⌘W など）を送らない
    static let longRunningHold: TimeInterval = 1
    /// どの実行も、後の実行をこれより長くは待たせない（応答しないアプリなどで、後のマスがすべて止まらないように）
    static let holdLimit: TimeInterval = 5

    /// 終わるまで数十秒以上掛かることがあるアクション（裏で動くスクリプト・ショートカット・AI）
    static func isLongRunning(_ action: Action) -> Bool {
        switch action {
        case .script(let script): script.runMode == .background
        case .shortcut, .ai: true
        case .keystroke, .launchApp, .openURL, .menuItem: false
        }
    }

    /// action を始めてから、後の実行を待たせる最長の時間
    static func hold(for action: Action) -> TimeInterval {
        isLongRunning(action) ? longRunningHold : holdLimit
    }

    /// 前面アプリにキーを送る（テスト実行で、そのアプリが前面にならなかったときは送らない。Nonet の設定ウィンドウに届くため）
    static func sendsInputToFrontmostApp(_ action: Action) -> Bool {
        switch action {
        case .keystroke: true
        case .ai(let ai): ai.output == .replaceSelection
        // 裏のスクリプトとショートカットも、出力で選択範囲を置き換えるなら ⌘V を送る
        case .script(let script): script.runMode == .background && script.output == .replaceSelection
        case .shortcut(let shortcut): shortcut.output == .replaceSelection
        case .launchApp, .openURL, .menuItem: false
        }
    }

    /// 前面のアプリによって動きが変わる。アプリを起動するマスと URL は変わらないので、テスト実行で前のアプリを前面に戻さない
    /// （戻すと「前面なら隠す」の起動が、そのアプリを隠してしまう）
    static func dependsOnFrontmostApp(_ action: Action) -> Bool {
        switch action {
        case .launchApp, .openURL: false
        case .keystroke, .script, .shortcut, .menuItem, .ai: true
        }
    }
}

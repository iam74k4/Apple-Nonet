// 担当: engine
import Foundation

/// 実行を1つずつ、頼まれた順に行う。速押しを続けたときに順番が入れ替わらず、同時にも走らないように
@MainActor
final class ControllerExecutionQueue {
    /// 最後に頼まれたもの。次に頼まれたものはこれが終わるのを待つ
    private var tail: Task<Void, Never>?

    /// 前に頼まれたものがすべて終わってから job を始める。返す Task で job の結果を待てる
    @discardableResult
    func enqueue<T: Sendable>(_ job: @escaping @MainActor () async -> T) -> Task<T, Never> {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            return await job()
        }
        tail = Task { @MainActor in _ = await task.value }
        return task
    }

    /// 頼まれたものがすべて終わるまで待つ（待っている間に頼まれたものも含む）
    func waitUntilIdle() async {
        while let current = tail {
            await current.value
            if tail == current { return }
        }
    }
}

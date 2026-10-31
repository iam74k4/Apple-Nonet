// 担当: engine
import Foundation

/// 設定の保存をまとめる。変更のたびには書かず、最初の変更から interval 後に最新の設定を1回だけ書く
/// （スライダーを動かしている間にファイルを何十回も書き、バックアップを途中の値で上書きしないように）。
/// 書けなかったときは、その設定を待たせたまま間を空けて書き直す（ディスクが一時的にいっぱいなど。終了時の flush でも書き直す）
@MainActor
final class ControllerConfigurationSaver {
    static let defaultInterval: TimeInterval = 0.5
    /// 書けなかった後に書き直すまでの間（秒）。失敗が続くたびに倍にし、maxRetryInterval で止める
    static let firstRetryInterval: TimeInterval = 2
    static let maxRetryInterval: TimeInterval = 60

    /// 書いた結果。失敗は ConfigurationStoreError など
    var onResult: ((Result<Void, any Error>) -> Void)?
    /// false の間は書かず、待っている保存も捨てる（読めなかった設定ファイルを上書きしないため）
    var isEnabled = true {
        didSet {
            guard !isEnabled else { return }
            task?.cancel()
            task = nil
            pending = nil
            failureCount = 0
        }
    }

    /// まだ書いていない設定
    private(set) var pending: NonetConfiguration?
    private var task: (any ScheduledTask)?
    /// task が書き直しの予定か（新しい変更は、書き直しを待たずに interval 後に書く）
    private var isRetryTask = false
    /// 続けて書けなかった回数。書けたら 0 に戻す
    private(set) var failureCount = 0
    private let scheduler: any Scheduler
    private let interval: TimeInterval
    private let write: (NonetConfiguration) throws -> Void

    init(scheduler: any Scheduler, interval: TimeInterval = ControllerConfigurationSaver.defaultInterval, write: @escaping (NonetConfiguration) throws -> Void) {
        self.scheduler = scheduler
        self.interval = interval
        self.write = write
    }

    var hasPendingSave: Bool { pending != nil }

    /// interval 後に書く。それまでに頼まれたら、最後の設定だけを書く
    func schedule(_ configuration: NonetConfiguration) {
        guard isEnabled else { return }
        pending = configuration
        if isRetryTask {
            task?.cancel()
            task = nil
        }
        guard task == nil else { return }
        scheduleFlush(after: interval, isRetry: false)
    }

    /// 待たずに書く（初回起動・壊れたファイルを置き換えるとき）
    func saveNow(_ configuration: NonetConfiguration) {
        guard isEnabled else { return }
        pending = configuration
        flush()
    }

    /// 待っている保存をすぐに書く。書けなければ、その設定を待たせたまま書き直しを予約する
    func flush() {
        task?.cancel()
        task = nil
        isRetryTask = false
        guard isEnabled, let configuration = pending else { return }
        pending = nil
        do {
            try write(configuration)
            failureCount = 0
            onResult?(.success(()))
        } catch {
            failureCount += 1
            // 書いている間に新しい変更が来ていれば、そちらを書く（古い設定で上書きしない）
            if pending == nil {
                pending = configuration
            }
            onResult?(.failure(error))
            if isEnabled, pending != nil, task == nil {
                scheduleFlush(after: retryInterval, isRetry: true)
            }
        }
    }

    /// 次に書き直すまでの間。2秒・4秒・8秒…と延ばし、1分で止める
    var retryInterval: TimeInterval {
        let exponent = Double(max(failureCount - 1, 0))
        return min(Self.firstRetryInterval * pow(2, exponent), Self.maxRetryInterval)
    }

    private func scheduleFlush(after delay: TimeInterval, isRetry: Bool) {
        isRetryTask = isRetry
        task = scheduler.schedule(after: delay) { [weak self] in
            self?.task = nil
            self?.isRetryTask = false
            self?.flush()
        }
    }
}

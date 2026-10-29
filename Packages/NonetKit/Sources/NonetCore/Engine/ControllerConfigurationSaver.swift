// 担当: engine
import Foundation

/// 設定の保存をまとめる。変更のたびには書かず、最初の変更から interval 後に最新の設定を1回だけ書く
/// （スライダーを動かしている間にファイルを何十回も書き、バックアップを途中の値で上書きしないように）
@MainActor
final class ControllerConfigurationSaver {
    static let defaultInterval: TimeInterval = 0.5

    /// 書いた結果。失敗は ConfigurationStoreError など
    var onResult: ((Result<Void, any Error>) -> Void)?
    /// false の間は書かず、待っている保存も捨てる（読めなかった設定ファイルを上書きしないため）
    var isEnabled = true {
        didSet {
            guard !isEnabled else { return }
            task?.cancel()
            task = nil
            pending = nil
        }
    }

    /// まだ書いていない設定
    private(set) var pending: NonetConfiguration?
    private var task: (any ScheduledTask)?
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
        guard task == nil else { return }
        task = scheduler.schedule(after: interval) { [weak self] in
            self?.task = nil
            self?.flush()
        }
    }

    /// 待たずに書く（初回起動・壊れたファイルを置き換えるとき）
    func saveNow(_ configuration: NonetConfiguration) {
        guard isEnabled else { return }
        pending = configuration
        flush()
    }

    /// 待っている保存をすぐに書く
    func flush() {
        task?.cancel()
        task = nil
        guard isEnabled, let configuration = pending else { return }
        pending = nil
        do {
            try write(configuration)
            onResult?(.success(()))
        } catch {
            onResult?(.failure(error))
        }
    }
}

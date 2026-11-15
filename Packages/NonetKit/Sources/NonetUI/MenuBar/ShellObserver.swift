// 担当: ui-shell
import Foundation
import Observation

/// @Observable の値を見張り、変わったらメインスレッドで知らせる（メニューバーのアイコン・初回起動の練習）。
/// 最初の値はすぐに知らせる。cancel するか解放されたら止まる
@MainActor
final class ShellObserver<Value: Equatable> {
    private let read: @MainActor () -> Value
    private let onChange: @MainActor (Value) -> Void
    private var last: Value?
    private var isActive = true

    init(_ read: @escaping @MainActor () -> Value, onChange: @escaping @MainActor (Value) -> Void) {
        self.read = read
        self.onChange = onChange
        track()
    }

    func cancel() {
        isActive = false
    }

    private func track() {
        guard isActive else { return }
        let value = withObservationTracking {
            read()
        } onChange: { [weak self] in
            // willSet で呼ばれるので、値が入った後に読み直す
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.track() }
            }
        }
        guard value != last else { return }
        last = value
        onChange(value)
    }
}

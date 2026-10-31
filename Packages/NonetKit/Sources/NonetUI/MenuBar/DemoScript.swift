// 担当: ui-shell。デモ動画の台本（App/DemoMode.swift の --demo-script）。テストできるように NonetUI に置く
import CoreGraphics
import Foundation

/// デモ動画で見せる指の動き。時刻（秒）と指の位置（x は左が 0、y は手前が 0。TouchPoint と同じ）の並びで、間は滑らかにつなぐ。
/// 位置が nil の時刻からは、次の時刻まで指を離している。見せる流れ（9マスの Xcode のプロファイルと、その後ろのグローバルのページ）:
/// 1. 上の縁から開き、中央のマス（Claude Code）に滑らせて離し、実行する
/// 2. 上の縁から開き、右の外枠へ出して止め、次のページへ。滑らせて中央のマスで離し、実行する
/// 3. 上の縁から開き、手前の外枠へ出して離し、やめる
/// 外枠に止める時間は、1回だけ切り替わる長さ（SessionConfiguration.edgePageDwell の後、edgePageRepeat の前に出る）にしてある
public enum DemoScript {
    public struct Key: Equatable, Sendable {
        public var time: TimeInterval
        public var point: CGPoint?

        public init(time: TimeInterval, point: CGPoint?) {
            self.time = time
            self.point = point
        }
    }

    public static let keys: [Key] = [
        // 1. 開いて、中央のマスで離す
        Key(time: 0.0, point: nil),
        Key(time: 1.0, point: CGPoint(x: 0.50, y: 0.975)),
        Key(time: 1.25, point: CGPoint(x: 0.50, y: 0.975)),
        Key(time: 1.6, point: CGPoint(x: 0.50, y: 0.86)),
        Key(time: 2.4, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 3.4, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 3.4, point: nil),
        // 2. 右の外枠で止めて、次のページへ。中央のマスで離す
        Key(time: 4.6, point: CGPoint(x: 0.62, y: 0.975)),
        Key(time: 4.85, point: CGPoint(x: 0.62, y: 0.975)),
        Key(time: 5.2, point: CGPoint(x: 0.62, y: 0.86)),
        Key(time: 6.0, point: CGPoint(x: 0.955, y: 0.62)),
        Key(time: 6.65, point: CGPoint(x: 0.955, y: 0.62)),
        Key(time: 7.45, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 8.45, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 8.45, point: nil),
        // 3. 手前の外枠で離して、やめる
        Key(time: 9.8, point: CGPoint(x: 0.38, y: 0.975)),
        Key(time: 10.05, point: CGPoint(x: 0.38, y: 0.975)),
        Key(time: 10.4, point: CGPoint(x: 0.38, y: 0.86)),
        Key(time: 11.2, point: CGPoint(x: 0.50, y: 0.06)),
        Key(time: 12.3, point: CGPoint(x: 0.50, y: 0.06)),
        Key(time: 12.3, point: nil),
        Key(time: 13.7, point: nil),
    ]

    public static var duration: TimeInterval { keys.last?.time ?? 0 }

    /// time 秒の指の位置。離している間は nil
    public static func sample(at time: TimeInterval) -> CGPoint? {
        guard time >= 0, time < duration else { return nil }
        // 同じ時刻の Key が並ぶとき（指を離す瞬間）は、後ろのものが次の区間の始まり
        var index = 0
        for (i, key) in keys.enumerated() where key.time <= time {
            index = i
        }
        guard index + 1 < keys.count, let start = keys[index].point else { return nil }
        let end = keys[index + 1]
        guard let to = end.point else { return start }
        let span = end.time - keys[index].time
        guard span > 0 else { return start }
        let progress = (time - keys[index].time) / span
        // ゆっくり動き出して、ゆっくり止まる
        let eased = progress * progress * (3 - 2 * progress)
        return CGPoint(x: start.x + (to.x - start.x) * eased, y: start.y + (to.y - start.y) * eased)
    }
}

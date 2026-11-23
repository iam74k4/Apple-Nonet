// 担当: ui-shell。デモ動画の台本（App/DemoMode.swift の --demo-script）。テストできるように NonetUI に置く
import CoreGraphics
import Foundation

/// デモ動画で見せる指の動き。時刻（秒）と指の位置（x は左が 0、y は手前が 0。TouchPoint と同じ）の並びで、間は滑らかにつなぐ。
/// 位置が nil の時刻からは、次の時刻まで指を離している。デモはこの位置を HUD の円に写してポインタを動かす
/// （トラックパッドの真ん中が円の中心。DemoTouchSource.pointerTravel）。どの回も真ん中に指を置いて強く押し込み、
/// forcePresses の時刻（押し込んでから ForcePress.hold の標準だけ止めた後）に開く。見せる流れ（9マスの Xcode のプロファイルと、グローバルのページの層）:
/// 1. 開き、上の鍵を通って真ん中の鍵（Claude Code）に戻して離し、実行する
/// 2. 開き、輪のすぐ下の帯で止めてグローバルのページ（画面に置く）へ。真ん中の鍵（最大化）で離し、実行する
/// 3. 開き、輪の下の外へ出てすぐ離し、やめる（止める時間 edgePageDwell より短く離すので、層は変わらない）
/// 帯に止める時間は、1回だけ切り替わる長さ（SessionConfiguration.edgePageDwell の後）にしてある
public enum DemoScript {
    public struct Key: Equatable, Sendable {
        public var time: TimeInterval
        public var point: CGPoint?

        public init(time: TimeInterval, point: CGPoint?) {
            self.time = time
            self.point = point
        }
    }

    /// 強く押し込んで止め終え、9マスが開く時刻（指を置いて 0.2 秒で押し込み、標準の 0.25 秒止める）
    public static let forcePresses: [TimeInterval] = [1.45, 5.05, 10.05]

    public static let keys: [Key] = [
        // 1. 真ん中で押し込んで開き、上の鍵を通って中央のマスで離す
        Key(time: 0.0, point: nil),
        Key(time: 1.0, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 1.6, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 2.2, point: CGPoint(x: 0.50, y: 0.86)),
        Key(time: 3.0, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 4.0, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 4.0, point: nil),
        // 2. 輪のすぐ下の帯で止めて、グローバルのページへ。中央のマスで離す
        Key(time: 4.6, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 5.2, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 6.0, point: CGPoint(x: 0.52, y: 0.06)),
        Key(time: 6.65, point: CGPoint(x: 0.52, y: 0.06)),
        Key(time: 7.45, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 8.45, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 8.45, point: nil),
        // 3. 手前の外枠ですぐ離して、やめる（止める時間より短いので、層は変わらない）
        Key(time: 9.6, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 10.2, point: CGPoint(x: 0.50, y: 0.50)),
        Key(time: 11.0, point: CGPoint(x: 0.50, y: 0.06)),
        Key(time: 11.3, point: CGPoint(x: 0.50, y: 0.06)),
        Key(time: 11.3, point: nil),
        Key(time: 13.5, point: nil),
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

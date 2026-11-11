// 担当: ui-shell。デモ動画の台本（App/DemoMode.swift の --demo-script・--demo-script-file）。テストできるように NonetUI に置く
import CoreGraphics
import Foundation

/// デモ動画で見せる指の動き。時刻（秒）と指の位置（x は左が 0、y は手前が 0。TouchPoint と同じ）の並びで、間は滑らかにつなぐ。
/// 位置が nil の時刻からは、次の時刻まで指を離している。デモはこの位置を HUD の円に写してポインタを動かし
/// （pointer(for:in:)）、本物と同じくポインタの向きと距離でマスを選ぶ。
///
/// 内蔵の台本（builtIn）は、1つのアプリ（--demo-app。既定は Xcode）のまま4回開き、1回に1つずつ見せる:
/// 1. 上の縁から開き、上のマスへ向けて止め、離して実行する
/// 2. 開いて輪のすぐ下で止め、グローバルのページの層へ移る。左のマスへ向けて離し、実行する
/// 3. 開いてもう一度グローバルの層へ移り、輪の右で止めて次のページへ送る。右上のマスへ向けて離し、実行する
/// 4. 開いてすぐ指を上へ戻し、輪の上の外で止めて（鍵が薄くなる）、離してやめる（何も実行しない）。アプリの層の上の帯は
///    切り替える先も案内も無いので、止めていても何も起きない。真ん中のマスを通らない: 前の台本は真ん中まで来てから下へ出ていて、
///    真ん中の鍵が名前つきで光ってから閉じるので、そのマスを選んだように見えた（2026-11-11 のレビュー）
/// どのマスが何をするかは設定しだい。初回の設定のままなら、Xcode の上は「実行」、グローバルの最初のページは「画面に置く」で
/// 左は「左半分」、次のページはランチャー（並ぶアプリは Mac しだい）。
/// グローバルの層で真ん中のマスへは向けない: 「画面に置く」の真ん中は「最大化」で、置く場所を示す枠が画面いっぱいに出て、何の枠か分からなくなる
/// （前の台本はそうしていて、2026-11-11 に所有者が「全画面が紺になるのが変」と退けた。「左半分」なら枠だと分かる）。
///
/// 輪の外で止める時間は、1回だけ切り替わる長さにしてある: SessionConfiguration.defaultEdgePageDwell（0.5 秒）より長く止め、
/// 続けて切り替わる defaultEdgePageRepeat（その 0.9 秒後）より前にその側を出る。4 の場面は上の帯なので、止めても切り替わらない。
/// この間隔は実機で確かめたもの（scripts/demo/xcode.json の場面のあとに、zoom.json の 2〜4 つ目の場面を時刻だけずらしてつないだ）。
/// 直すときは、ShellDemoScriptTests が本物の操作のロジックに通して確かめる
public struct DemoScript: Equatable, Sendable {
    public struct Key: Equatable, Sendable {
        public var time: TimeInterval
        public var point: CGPoint?

        public init(time: TimeInterval, point: CGPoint?) {
            self.time = time
            self.point = point
        }
    }

    /// 読めない・検査に落ちた台本の理由（デモは、これを標準エラーに書いて始めずに終える）
    public struct Problem: Error, Equatable, Sendable, CustomStringConvertible {
        public var description: String

        public init(_ description: String) {
            self.description = description
        }
    }

    public let keys: [Key]

    /// 並びをそのまま持つ（検査しない）。ファイルの台本は init(json:)・init(contentsOf:) で読み、検査を通す
    init(keys: [Key]) {
        self.keys = keys
    }

    public static let builtIn = DemoScript(keys: [
        // 1. 開いて、上のマスで止めて離す
        Key(time: 0.0, point: nil),
        Key(time: 0.6, point: CGPoint(x: 0.5, y: 0.975)),
        Key(time: 0.85, point: CGPoint(x: 0.5, y: 0.975)),
        Key(time: 1.2, point: CGPoint(x: 0.5, y: 0.86)),
        Key(time: 1.5, point: CGPoint(x: 0.5, y: 0.81)),
        Key(time: 2.8, point: CGPoint(x: 0.5, y: 0.81)),
        Key(time: 2.8, point: nil),
        // 2. 輪のすぐ下で止めて、グローバルの層へ。左下を回って左のマスへ行き、離す
        Key(time: 4.0, point: CGPoint(x: 0.5, y: 0.975)),
        Key(time: 4.25, point: CGPoint(x: 0.5, y: 0.975)),
        Key(time: 4.6, point: CGPoint(x: 0.5, y: 0.86)),
        Key(time: 5.3, point: CGPoint(x: 0.5, y: 0.05)),
        Key(time: 5.95, point: CGPoint(x: 0.5, y: 0.05)),
        Key(time: 6.2, point: CGPoint(x: 0.12, y: 0.12)),
        Key(time: 6.4, point: CGPoint(x: 0.08, y: 0.42)),
        Key(time: 6.6, point: CGPoint(x: 0.19, y: 0.5)),
        Key(time: 7.9, point: CGPoint(x: 0.19, y: 0.5)),
        Key(time: 7.9, point: nil),
        // 3. もう一度グローバルの層へ。輪の右で止めて次のページへ送り、右上のマスで離す
        Key(time: 9.1, point: CGPoint(x: 0.5, y: 0.975)),
        Key(time: 9.35, point: CGPoint(x: 0.5, y: 0.975)),
        Key(time: 9.7, point: CGPoint(x: 0.5, y: 0.86)),
        Key(time: 10.4, point: CGPoint(x: 0.5, y: 0.05)),
        Key(time: 11.05, point: CGPoint(x: 0.5, y: 0.05)),
        Key(time: 11.35, point: CGPoint(x: 0.92, y: 0.1)),
        Key(time: 11.6, point: CGPoint(x: 0.95, y: 0.5)),
        Key(time: 12.25, point: CGPoint(x: 0.95, y: 0.5)),
        Key(time: 12.5, point: CGPoint(x: 0.92, y: 0.82)),
        Key(time: 12.75, point: CGPoint(x: 0.719, y: 0.719)),
        Key(time: 13.9, point: CGPoint(x: 0.719, y: 0.719)),
        Key(time: 13.9, point: nil),
        // 4. 開いてすぐ指を上へ戻し、輪の上の外で止めて（鍵が薄くなる）離し、やめる（アプリの層の上の帯は、止めても何も起きない）
        Key(time: 15.1, point: CGPoint(x: 0.5, y: 0.975)),
        Key(time: 15.35, point: CGPoint(x: 0.5, y: 0.975)),
        Key(time: 15.7, point: CGPoint(x: 0.5, y: 0.86)),
        Key(time: 16.05, point: CGPoint(x: 0.5, y: 0.96)),
        Key(time: 17.15, point: CGPoint(x: 0.5, y: 0.96)),
        Key(time: 17.15, point: nil),
        Key(time: 18.1, point: nil),
    ])

    // MARK: - ファイルの台本

    /// JSON の台本を読む（--demo-script-file。見本は scripts/demo/）。形は [[秒, x, y], [秒], …] で、x・y の無い行は指を離す。
    /// 読めない・検査（problem(in:)）に落ちたら、理由を投げる
    public init(json data: Data) throws {
        let rows: [[Double]]
        do {
            rows = try JSONDecoder().decode([[Double]].self, from: data)
        } catch {
            throw Problem("JSON を [[秒, x, y], [秒], …] の形（数だけ）で読めません\(Self.place(of: error))")
        }
        var keys: [Key] = []
        for (index, row) in rows.enumerated() {
            switch row.count {
            case 1: keys.append(Key(time: row[0], point: nil))
            case 3: keys.append(Key(time: row[0], point: CGPoint(x: row[1], y: row[2])))
            default: throw Problem("\(index + 1) 行目: [秒, x, y] か [秒] で書く（数が \(row.count) 個あります）")
            }
        }
        if let problem = Self.problem(in: keys) {
            throw Problem(problem)
        }
        self.keys = keys
    }

    public init(contentsOf url: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Problem("ファイルを読めません（\(error.localizedDescription)）")
        }
        try self.init(json: data)
    }

    /// JSON のどの行で読めなくなったか（分かるときだけ。「（3 行目）」）
    private static func place(of error: any Error) -> String {
        let context: DecodingError.Context? = switch error {
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context): context
        default: nil
        }
        guard let row = context?.codingPath.first?.intValue else { return "" }
        return "（\(row + 1) 行目）"
    }

    /// 台本として流せない並びなら、その理由（最初に見つけた1つ）。流せるなら nil
    /// - 時刻は 0 以上で、前の行より戻らない（同じ時刻は並べてよい: 指を離す瞬間）
    /// - x・y は 0〜1（トラックパッドの中）
    /// - 指を置く行が1つはあり、最後の行は指を離している（触れたままで終わると、開いた HUD が閉じない）
    static func problem(in keys: [Key]) -> String? {
        guard !keys.isEmpty else { return "行がありません" }
        var previous = 0.0
        for (index, key) in keys.enumerated() {
            let row = "\(index + 1) 行目"
            guard key.time.isFinite, key.time >= 0 else { return "\(row): 時刻は 0 以上の秒で書く" }
            guard key.time >= previous else { return "\(row): 時刻（\(key.time) 秒）が前の行（\(previous) 秒）より戻っています" }
            previous = key.time
            if let point = key.point, !(0...1).contains(point.x) || !(0...1).contains(point.y) {
                return "\(row): x と y は 0〜1 で書く（x は左が 0、y は手前が 0）"
            }
        }
        guard keys.contains(where: { $0.point != nil }) else { return "指を置く行（[秒, x, y]）がありません" }
        guard keys.last?.point == nil else { return "最後の行は [秒] にして、指を離して終える" }
        return nil
    }

    // MARK: - 流す

    public var duration: TimeInterval { keys.last?.time ?? 0 }

    /// time 秒の指の位置。離している間と、最初の行より前・最後の行から後は nil
    public func sample(at time: TimeInterval) -> CGPoint? {
        guard let first = keys.first, time >= first.time, time < duration else { return nil }
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

    /// 台本の指の位置（トラックパッドの 0〜1）を HUD の枠に写すときの倍率。指がトラックパッドの端まで行けば、ポインタが円の外（外枠）に出るように
    public static let pointerTravel: CGFloat = 1.3

    /// 台本の指の位置を、ポインタの位置に写す。map は表示中の HUD の枠（円を囲む正方形。主画面の左上が原点で y が下向き）。
    /// トラックパッドの真ん中が円の中心で、そこからの動きを倍率で広げる
    public static func pointer(for point: CGPoint, in map: CGRect) -> CGPoint {
        CGPoint(
            x: map.midX + (point.x - 0.5) * map.width * pointerTravel,
            y: map.midY + (0.5 - point.y) * map.height * pointerTravel
        )
    }
}

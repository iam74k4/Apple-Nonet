// 担当: ui-shell。デモ動画の台本（App/DemoMode.swift の --demo-script・--demo-script-file）。テストできるように NonetUI に置く
import CoreGraphics
import Foundation

/// デモ動画で見せる指の動き。時刻（秒）と指の位置（x は左が 0、y は手前が 0。TouchPoint と同じ）の並びで、間は滑らかにつなぐ。
/// 位置が nil の時刻からは、次の時刻まで指を離している。pressed の時刻からは、次の時刻まで指を強く押し込んでいる
/// （デモは、本物のキーボードモニターと同じく、押し込んで ForcePress.hold だけ止めたら開く出来事を送る）。
/// デモはこの位置を HUD の円に写してポインタを動かし（pointer(for:in:)）、本物と同じくポインタの向きと距離でマスを選ぶ。
///
/// 内蔵の台本（builtIn）は、1つのアプリ（--demo-app。既定は Xcode）のまま4回開き、1回に1つずつ見せる。どの回も、トラックパッドの真ん中を
/// 強く押し込んで止めて開く（1.1.0 の既定の開き方。2026-11-27 に所有者が「押し込みで撮り直す」と決めた。前は上の縁から滑らせていた）。
/// 開いた瞬間はポインタが真ん中のマスにあるので、すぐに動き出す（留まると名前の札が出て、そのマスを選んだように見える）。
/// 真ん中のマスを選ぶには、一度真ん中の外へ出てから戻す（ControllerPointerSelection。開いた瞬間に離せば何もせずに閉じるため）:
/// 1. 開いて上のマスへ向けて止め、離して実行する
/// 2. 開いて輪のすぐ上で止め、グローバルのページの層へ移る。左上の外を回って左のマスへ向けて離し、実行する
/// 3. 開いてもう一度グローバルの層へ移り、輪の右で止めて次のページへ送る。右上のマスへ向けて離し、実行する
/// 4. 開いて右上の隅へ出し、帯より遠く（どの側でもない。止めても何も切り替わらない）で止めて（鍵が薄くなる）、離してやめる
///    （何も実行しない）。アプリの層の上の帯はグローバルの層へ、下の帯は下のページ（ユーティリティ）へ移り、右・左もページがあれば送るので、
///    やめる場面は帯の外で止める
/// どのマスが何をするかは設定しだい。初回の設定のままなら、Xcode の上は「実行」、グローバルの最初のページは「画面に置く」で
/// 左は「左半分」、次のページはランチャー（並ぶアプリは Mac しだい）。
/// グローバルの層で真ん中のマスへは向けない: 「画面に置く」の真ん中は「最大化」で、置く場所を示す枠が画面いっぱいに出て、何の枠か分からなくなる
/// （前の台本はそうしていて、2026-11-11 に所有者が「全画面が紺になるのが変」と退けた。「左半分」なら枠だと分かる）。
///
/// 輪の外の帯で止める時間は、SessionConfiguration.defaultEdgePageDwell（0.5 秒）より長くしてある（1回止めて動くのは1つだけなので、
/// 止めすぎても続けては切り替わらない）。帯を通りかかるだけの動きは、止める時間より短く通り過ぎる。
/// 直すときは、ShellDemoScriptTests が本物の操作のロジックに通して確かめる
public struct DemoScript: Equatable, Sendable {
    public struct Key: Equatable, Sendable {
        public var time: TimeInterval
        public var point: CGPoint?
        /// この時刻から次の時刻まで、指を強く押し込んでいる（指を置いている行だけ）
        public var pressed: Bool

        public init(time: TimeInterval, point: CGPoint?, pressed: Bool = false) {
            self.time = time
            self.point = point
            self.pressed = pressed
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
        // 1. 真ん中を押し込んで開き、上のマスで止めて離す
        Key(time: 0.0, point: nil),
        Key(time: 0.6, point: CGPoint(x: 0.5, y: 0.5)),
        Key(time: 0.75, point: CGPoint(x: 0.5, y: 0.5), pressed: true),
        Key(time: 1.1, point: CGPoint(x: 0.5, y: 0.5)),
        Key(time: 1.4, point: CGPoint(x: 0.5, y: 0.81)),
        Key(time: 2.8, point: CGPoint(x: 0.5, y: 0.81)),
        Key(time: 2.8, point: nil),
        // 2. 開いて輪のすぐ上で止め、グローバルの層へ。左上を回って左のマスへ行き、離す
        Key(time: 4.0, point: CGPoint(x: 0.5, y: 0.5)),
        Key(time: 4.15, point: CGPoint(x: 0.5, y: 0.5), pressed: true),
        Key(time: 4.5, point: CGPoint(x: 0.5, y: 0.5)),
        Key(time: 5.0, point: CGPoint(x: 0.5, y: 0.95)),
        Key(time: 5.65, point: CGPoint(x: 0.5, y: 0.95)),
        Key(time: 5.9, point: CGPoint(x: 0.12, y: 0.88)),
        Key(time: 6.1, point: CGPoint(x: 0.08, y: 0.58)),
        Key(time: 6.3, point: CGPoint(x: 0.19, y: 0.5)),
        Key(time: 7.6, point: CGPoint(x: 0.19, y: 0.5)),
        Key(time: 7.6, point: nil),
        // 3. もう一度グローバルの層へ。輪の右で止めて次のページへ送り、右上のマスで離す
        Key(time: 8.8, point: CGPoint(x: 0.5, y: 0.5)),
        Key(time: 8.95, point: CGPoint(x: 0.5, y: 0.5), pressed: true),
        Key(time: 9.3, point: CGPoint(x: 0.5, y: 0.5)),
        Key(time: 9.8, point: CGPoint(x: 0.5, y: 0.95)),
        Key(time: 10.45, point: CGPoint(x: 0.5, y: 0.95)),
        Key(time: 10.75, point: CGPoint(x: 0.92, y: 0.9)),
        Key(time: 11.0, point: CGPoint(x: 0.95, y: 0.5)),
        Key(time: 11.65, point: CGPoint(x: 0.95, y: 0.5)),
        Key(time: 11.9, point: CGPoint(x: 0.92, y: 0.82)),
        Key(time: 12.15, point: CGPoint(x: 0.719, y: 0.719)),
        Key(time: 13.3, point: CGPoint(x: 0.719, y: 0.719)),
        Key(time: 13.3, point: nil),
        // 4. 開いて右へ出てから右上の隅へ上がり、帯より遠くで止めて（鍵が薄くなる）離し、やめる（どの側でもないので、止めても何も起きない）。
        // 帯（中心から 134〜210pt）は右の側（アプリの層では右にページが無く、何も出ない）で横切る。上の側で横切ると、グローバルの層の矢印と
        // 名前が一瞬出て、移るように見える。真ん中から隅へまっすぐ出ると、上と右の境（45°）を通り、どちらになるかが揺れる
        Key(time: 14.5, point: CGPoint(x: 0.5, y: 0.5)),
        Key(time: 14.65, point: CGPoint(x: 0.5, y: 0.5), pressed: true),
        Key(time: 15.0, point: CGPoint(x: 0.5, y: 0.5)),
        Key(time: 15.3, point: CGPoint(x: 0.97, y: 0.62)),
        Key(time: 15.55, point: CGPoint(x: 0.97, y: 0.97)),
        Key(time: 16.55, point: CGPoint(x: 0.97, y: 0.97)),
        Key(time: 16.55, point: nil),
        Key(time: 17.5, point: nil),
    ])

    // MARK: - ファイルの台本

    /// JSON の台本を読む（--demo-script-file。見本は scripts/demo/）。形は [[秒, x, y], [秒], …] で、x・y の無い行は指を離す。
    /// [秒, x, y, 1] は、その時刻から次の行まで強く押し込む（4つ目は 0 か 1）。読めない・検査（problem(in:)）に落ちたら、理由を投げる
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
            case 4:
                guard row[3] == 0 || row[3] == 1 else {
                    throw Problem("\(index + 1) 行目: 押し込む印（4つ目）は 0 か 1 で書く")
                }
                keys.append(Key(time: row[0], point: CGPoint(x: row[1], y: row[2]), pressed: row[3] == 1))
            default: throw Problem("\(index + 1) 行目: [秒, x, y]・[秒, x, y, 押し込む印] か [秒] で書く（数が \(row.count) 個あります）")
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

    /// 押し込んで開く台本か（デモのトラックパッドの図は、そのとき上の縁の帯を描かない。開く場所ではないので）
    public var pressesToOpen: Bool { keys.contains(where: \.pressed) }

    /// time 秒に指を強く押し込んでいるか（指を置いていて、いまの区間の始まりの行が pressed）
    public func isPressed(at time: TimeInterval) -> Bool {
        guard sample(at: time) != nil else { return false }
        return keys[segment(at: time)].pressed
    }

    /// time 秒を含む区間の始まりの行。同じ時刻の Key が並ぶとき（指を離す瞬間）は、後ろのものが次の区間の始まり
    private func segment(at time: TimeInterval) -> Int {
        var index = 0
        for (i, key) in keys.enumerated() where key.time <= time {
            index = i
        }
        return index
    }

    /// time 秒の指の位置。離している間と、最初の行より前・最後の行から後は nil
    public func sample(at time: TimeInterval) -> CGPoint? {
        guard let first = keys.first, time >= first.time, time < duration else { return nil }
        let index = segment(at: time)
        guard index + 1 < keys.count, let start = keys[index].point else { return nil }
        let end = keys[index + 1]
        guard let to = end.point else { return start }
        let span = end.time - keys[index].time
        guard span > 0 else { return start }
        let s = (time - keys[index].time) / span
        // 3次のエルミート補間。止める点では速さを 0（ゆっくり動き出して、ゆっくり止まる）、通り過ぎる点では前後の点を結ぶ向きの
        // 速さを保つ。どの点でも速さを 0 にしていたころは、輪の外を回る道筋の点ごとに指がいったん止まり、カクカクして見えた
        // （2026-11-27 の所有者の指摘「カーソルの動きが不自然」）。両端とも止める点なら、前と同じ曲線（s² (3 − 2s)）になる
        let v0 = velocity(at: index)
        let v1 = velocity(at: index + 1)
        let h00 = 2 * s * s * s - 3 * s * s + 1
        let h10 = s * s * s - 2 * s * s + s
        let h01 = -2 * s * s * s + 3 * s * s
        let h11 = s * s * s - s * s
        let x = h00 * start.x + h10 * span * v0.dx + h01 * to.x + h11 * span * v1.dx
        let y = h00 * start.y + h10 * span * v0.dy + h01 * to.y + h11 * span * v1.dy
        // 通り過ぎる点のまわりで少し膨らんでも、トラックパッドの外には出さない
        return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    /// i 番目の点を通るときの指の速さ（トラックパッドの幅・高さ / 秒）。指を置いた・離す・同じ位置に留まる点では止めるので 0。
    /// 前後とも別の位置へ動く途中の点では、前の点から次の点へ向かう平均の速さ（Catmull-Rom）
    private func velocity(at i: Int) -> CGVector {
        guard i > 0, i + 1 < keys.count,
              let point = keys[i].point, let previous = keys[i - 1].point, let next = keys[i + 1].point,
              previous != point, next != point
        else { return .zero }
        let span = keys[i + 1].time - keys[i - 1].time
        guard span > 0 else { return .zero }
        return CGVector(dx: (next.x - previous.x) / span, dy: (next.y - previous.y) / span)
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

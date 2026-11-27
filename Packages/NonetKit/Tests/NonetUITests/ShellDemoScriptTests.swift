// 担当: ui-shell。デモ動画の台本（DemoScript）を、本物の操作のロジック（押し込んで止める時間 ForcePress.hold・EdgeSlideRecognizer・SessionEngine・
// ControllerPointerSelection）に通して確かめる
import CoreGraphics
import Foundation
import NonetCore
@testable import NonetUI
import Testing

@Suite("デモ動画の台本")
struct ShellDemoScriptTests {
    struct Replay {
        var executions: [String] = []
        var haptics: [HapticEvent] = []
        var ends: [SessionEndReason] = []
        var openedAt: [TimeInterval] = []
        var pages: [Int] = []
        /// 輪の外の帯に入っていて、そこで開くページの矢印（と名前）が出ていた時刻
        var pagingShownAt: [TimeInterval] = []
    }

    /// 台本の指を 120Hz で入れ、開く動きの判定と SessionEngine を NonetController と同じ順でつなぐ。
    /// 押し込んで ForcePress.hold（開きやすさは標準）だけ止めたら開く（デモの DemoKeyboardMonitor が .forcePressed を送るのと同じ）。
    /// 上の縁から滑らせる台本は、EdgeSlideRecognizer で開く。
    /// 開いている間は、デモ（App/DemoMode.swift）と同じく、指の位置を HUD の枠に写したポインタでマスを選ぶ
    static func replay(_ script: DemoScript, pageCount: Int = 4) -> Replay {
        var engine = SessionEngine()
        var recognizer = EdgeSlideRecognizer()
        var selection = ControllerPointerSelection()
        // 表示中の HUD の枠（倍率 1 の円を囲む正方形）。ポインタは枠の中心からの向きと距離だけを見るので、置く場所はどこでもよい
        let map = CGRect(x: 600, y: 300, width: RadialLayout.outerRadius * 2, height: RadialLayout.outerRadius * 2)
        // 前面のアプリのプロファイル（1 ページ）の後ろにグローバルのページ、いちばん後ろに下のページ（ユーティリティ）。
        // 輪の上で止めるとグローバルの層（2 ページ目から）へ、下で止めると下のページへ移る
        let configuration = SessionConfiguration(pageCount: pageCount, layerStart: 1, belowStart: pageCount - 1)
        var result = Replay()
        var nextTick: TimeInterval?
        var wasTouching = false
        let hold = ForcePress.hold(for: .standard)
        var pressedSince: TimeInterval?
        var pressReported = false

        func collect(_ effects: [SessionEffect], at time: TimeInterval) {
            for effect in effects {
                switch effect {
                case .execute(let page, let cell): result.executions.append("\(page):\(cell)")
                case .haptic(let event): result.haptics.append(event)
                case .sessionEnded(let reason):
                    result.ends.append(reason)
                    nextTick = nil
                case .requestTick(let at): nextTick = at
                case .showHUD, .updateHUD:
                    // HUD を出すたびに、ポインタの選び方は開いた直後に戻る（NonetController と同じ）
                    if case .showHUD = effect { selection = ControllerPointerSelection() }
                    if let page = engine.pageIndex, result.pages.last != page { result.pages.append(page) }
                    if engine.hud?.edgePaging != nil { result.pagingShownAt.append(time) }
                default: break
                }
            }
        }

        var time = 0.0
        while time <= script.duration + 0.5 {
            if let due = nextTick, due <= time {
                nextTick = nil
                collect(engine.handle(.tick(at: time)), at: time)
            }
            var frame: TouchFrame?
            var pointer: CGPoint?
            if let point = script.sample(at: time) {
                wasTouching = true
                frame = TouchFrame(timestamp: time, points: [TouchPoint(id: 1, x: point.x, y: point.y, majorAxis: 12)])
                pointer = DemoScript.pointer(for: point, in: map)
            } else if wasTouching {
                wasTouching = false
                frame = TouchFrame(timestamp: time, points: [])
            }
            if let frame {
                let selected = engine.isInSession ? selection.frame(frame, pointer: pointer, map: map) : frame
                collect(engine.handle(.touches(selected)), at: time)
                if recognizer.apply(frame, isSessionActive: engine.isInSession) == .slid {
                    result.openedAt.append(time)
                    collect(engine.handle(.open(at: time, configuration: configuration)), at: time)
                }
            }
            if script.isPressed(at: time) {
                if pressedSince == nil {
                    pressedSince = time
                    pressReported = false
                }
                if !pressReported, let since = pressedSince, time - since >= hold - 1e-9 {
                    pressReported = true
                    if !engine.isInSession {
                        result.openedAt.append(time)
                        collect(engine.handle(.open(at: time, configuration: configuration)), at: time)
                    }
                }
            } else {
                pressedSince = nil
            }
            time += 1.0 / 120
        }
        return result
    }

    /// 指を置いた時刻（離していた後に、位置のある行が来たところ）
    static func touchStarts(_ script: DemoScript) -> [TimeInterval] {
        script.keys.indices
            .filter { script.keys[$0].point != nil && ($0 == 0 || script.keys[$0 - 1].point == nil) }
            .map { script.keys[$0].time }
    }

    /// 収録に使う台本（scripts/demo/）
    static func recorded(_ name: String) throws -> DemoScript {
        try DemoScript(contentsOf: ShellInfoPlistTests.repositoryRoot.appending(path: "scripts/demo/\(name).json"))
    }

    /// JSON の台本を読めなかった理由。読めたら nil
    static func problem(_ json: String) -> String? {
        do {
            _ = try DemoScript(json: Data(json.utf8))
            return nil
        } catch {
            return "\(error)"
        }
    }

    // MARK: - 内蔵の台本

    @Test("内蔵の台本は4回開く: 上のマスを実行・グローバルの層へ移って左のマスを実行・もう一度移り次のページの右上のマスを実行・帯より遠くで止めて離し、やめる")
    func theBuiltInScriptShowsTheFourSessions() {
        let result = Self.replay(.builtIn)
        #expect(result.openedAt.count == 4)
        // 1回目は前面のアプリのページの上（1）、2回目はグローバルの最初のページの左（3）、3回目はその次のページの右上（2）。
        // 真ん中（4。「画面に置く」では最大化）は実行しない
        #expect(result.executions == ["0:1", "1:3", "2:2"])
        // 輪の上で止めた2回はどちらも1回だけ層が替わり、輪の右で止めた1回は1ページだけ送る（止めすぎて続けて替わらない）
        #expect(result.haptics.filter { $0 == .layerChange }.count == 2)
        #expect(result.haptics.filter { $0 == .pageChange }.count == 1)
        #expect(result.pages == [0, 1, 0, 1, 2, 0])
        #expect(result.ends == [.released, .released, .released, .cancelled(.liftedInFrame)])
        // やめる場面は帯に入らない（入ると、そこで開くページの矢印と名前が一瞬出て、移るように見える）
        #expect(result.pagingShownAt.filter { $0 > result.openedAt[3] }.isEmpty)
    }

    @Test("開く動きは、トラックパッドの真ん中を強く押し込んで止めたもの（1.1.0 の既定）。どれも押し込んでから ForcePress.hold で開く")
    func opensByPressingFirmly() {
        let result = Self.replay(.builtIn)
        let touchStarts = Self.touchStarts(.builtIn)
        #expect(touchStarts == [0.6, 4.0, 8.8, 14.5])
        let pressStarts = DemoScript.builtIn.keys.filter(\.pressed).map(\.time)
        #expect(result.openedAt.count == pressStarts.count)
        for (press, opened) in zip(pressStarts, result.openedAt) {
            #expect(abs(opened - press - ForcePress.hold(for: .standard)) < 0.02)
        }
        // 押し込むのは真ん中（ポインタの下に開く。開いた瞬間のポインタは円の中心）
        for key in DemoScript.builtIn.keys where key.pressed {
            #expect(key.point == CGPoint(x: 0.5, y: 0.5))
        }
        #expect(DemoScript.builtIn.pressesToOpen)
    }

    @Test("内蔵の台本は、ファイルの台本と同じ検査に通る。位置はトラックパッドの中で、離している間は nil")
    func theBuiltInScriptIsValid() {
        let script = DemoScript.builtIn
        #expect(DemoScript.problem(in: script.keys) == nil)
        var time = 0.0
        while time < script.duration {
            if let point = script.sample(at: time) {
                #expect((0...1).contains(point.x) && (0...1).contains(point.y))
            }
            time += 0.01
        }
        #expect(script.sample(at: 0.3) == nil)
        #expect(script.sample(at: 3.5) == nil)
        #expect(script.sample(at: script.duration) == nil)
        #expect(script.sample(at: -1) == nil)
    }

    // MARK: - ファイルの台本

    @Test("収録に使う台本（scripts/demo/）は検査に通り、狙った場面になる")
    func theRecordedScriptsShowTheirSessions() throws {
        // Xcode: 上のマス（実行）で離す
        let xcode = Self.replay(try Self.recorded("xcode"))
        #expect(xcode.executions == ["0:1"])
        #expect(xcode.ends == [.released])
        // Zoom: 真ん中（ミュート）・上でグローバルへ移って左（左半分）・上でグローバルへ移り右で次のページ（ランチャー）の右上（メール）・
        // 下で下のページ（ユーティリティ）へ移り真ん中（撮影してコピー）・帯より遠くで止めて離し、やめる。どの回も押し込んで開く
        let zoom = Self.replay(try Self.recorded("zoom"))
        #expect(zoom.executions == ["0:4", "1:3", "2:2", "3:4"])
        #expect(zoom.haptics.filter { $0 == .layerChange }.count == 3)
        #expect(zoom.haptics.filter { $0 == .pageChange }.count == 1)
        // 軽い2打は、最後にやめたときの1回だけ（移る先が無い向きで止めて知らせることは無い。輪の外は通りかかるだけ）
        #expect(zoom.haptics.filter { $0 == .rejected }.count == 1)
        #expect(zoom.haptics.last == .rejected)
        #expect(zoom.pages == [0, 1, 0, 1, 2, 0, 3, 0])
        #expect(zoom.ends == [.released, .released, .released, .released, .cancelled(.liftedInFrame)])
        #expect(!zoom.pagingShownAt.filter { $0 < zoom.openedAt[4] }.isEmpty)
        #expect(zoom.pagingShownAt.filter { $0 > zoom.openedAt[4] }.isEmpty)
        #expect(xcode.openedAt.count == 1 && zoom.openedAt.count == 5)
    }

    @Test("JSON の台本: [秒, x, y] は指を置く行、[秒] は指を離す行。間は滑らかにつなぐ")
    func readsJSON() throws {
        let script = try DemoScript(json: Data("[[0], [0.5, 0.25, 1], [1.5, 0.75, 0], [1.5], [2]]".utf8))
        #expect(script.keys == [
            DemoScript.Key(time: 0, point: nil),
            DemoScript.Key(time: 0.5, point: CGPoint(x: 0.25, y: 1)),
            DemoScript.Key(time: 1.5, point: CGPoint(x: 0.75, y: 0)),
            DemoScript.Key(time: 1.5, point: nil),
            DemoScript.Key(time: 2, point: nil),
        ])
        #expect(script.duration == 2)
        #expect(script.sample(at: 0.25) == nil)
        #expect(script.sample(at: 0.5) == CGPoint(x: 0.25, y: 1))
        #expect(script.sample(at: 1.0) == CGPoint(x: 0.5, y: 0.5))
        #expect(script.sample(at: 1.5) == nil)
        #expect(script.sample(at: 2) == nil)
    }

    @Test("指は、止める点（同じ位置に留まる点）でだけ止まり、通り過ぎる点では止まらずに動き続ける")
    func passesThroughWaypointsWithoutStopping() throws {
        // 0.5 秒目まで留まり、1 秒目の点を通り過ぎて、1.5 秒目で止まる
        let script = try DemoScript(json: Data("[[0, 0.1, 0.5], [0.5, 0.1, 0.5], [1, 0.5, 0.9], [1.5, 0.9, 0.5], [2, 0.9, 0.5], [2]]".utf8))
        func speed(at time: TimeInterval) throws -> CGFloat {
            let dt = 1.0 / 240
            let a = try #require(script.sample(at: time - dt))
            let b = try #require(script.sample(at: time + dt))
            return hypot(b.x - a.x, b.y - a.y) / (2 * dt)
        }
        // 通り過ぎる点: 前の点から次の点へ向かう平均の速さ（0.8 / 秒）で通る（どの点でも止めていたころは 0 だった）
        #expect(try abs(speed(at: 1.0) - 0.8) < 0.05)
        #expect(script.sample(at: 1.0) == CGPoint(x: 0.5, y: 0.9))
        // 止める点: ゆっくり動き出し、ゆっくり止まる
        #expect(try speed(at: 0.5 + 1.0 / 240) < 0.1)
        #expect(try speed(at: 1.5 - 1.0 / 240) < 0.1)
        #expect(script.sample(at: 1.5) == CGPoint(x: 0.9, y: 0.5))
    }

    @Test("JSON の台本: [秒, x, y, 1] は、その時刻から次の行まで強く押し込む。離している間と最初の行より前は押し込んでいない")
    func readsPresses() throws {
        let script = try DemoScript(json: Data("[[0], [0.5, 0.5, 0.5], [1, 0.5, 0.5, 1], [1.5, 0.5, 0.5, 0], [2, 0.5, 0.9], [2]]".utf8))
        #expect(script.pressesToOpen)
        #expect(!script.isPressed(at: 0.25))
        #expect(!script.isPressed(at: 0.75))
        #expect(script.isPressed(at: 1.0))
        #expect(script.isPressed(at: 1.4))
        #expect(!script.isPressed(at: 1.5))
        #expect(!script.isPressed(at: 2.5))
        #expect(!(try DemoScript(json: Data("[[0, 0.5, 0.5], [1]]".utf8))).pressesToOpen)
    }

    @Test("時刻 0 から始まらない台本は、最初の行まで指を離している")
    func nothingBeforeTheFirstRow() throws {
        let script = try DemoScript(json: Data("[[1, 0.5, 0.9], [2, 0.5, 0.5], [2]]".utf8))
        #expect(script.sample(at: 0) == nil)
        #expect(script.sample(at: 0.99) == nil)
        #expect(script.sample(at: 1) == CGPoint(x: 0.5, y: 0.9))
    }

    @Test("検査に落ちる台本は、理由（分かるときは何行目か）を添えて読まない", arguments: [
        ("[]", "行がありません"),
        ("[[0], [1]]", "指を置く行（[秒, x, y]）がありません"),
        ("[[0], [1, 0.5, 0.5]]", "最後の行は [秒] にして、指を離して終える"),
        ("[[0], [1, 0.5], [2]]", "2 行目: [秒, x, y]・[秒, x, y, 押し込む印] か [秒] で書く（数が 2 個あります）"),
        ("[[0], [1, 0.5, 0.5, 0.5], [2]]", "2 行目: 押し込む印（4つ目）は 0 か 1 で書く"),
        ("[[0], [1, 0.5, 0.5, 1, 0], [2]]", "2 行目: [秒, x, y]・[秒, x, y, 押し込む印] か [秒] で書く（数が 5 個あります）"),
        ("[[0], [], [2]]", "2 行目: [秒, x, y]・[秒, x, y, 押し込む印] か [秒] で書く（数が 0 個あります）"),
        ("[[-1], [1, 0.5, 0.5], [2]]", "1 行目: 時刻は 0 以上の秒で書く"),
        ("[[0], [2, 0.5, 0.5], [1.5, 0.5, 0.5], [3]]", "3 行目: 時刻（1.5 秒）が前の行（2.0 秒）より戻っています"),
        ("[[0], [1, 1.01, 0.5], [2]]", "2 行目: x と y は 0〜1 で書く（x は左が 0、y は手前が 0）"),
        ("[[0], [1, 0.5, -0.01], [2]]", "2 行目: x と y は 0〜1 で書く（x は左が 0、y は手前が 0）"),
        ("[[0], [1, \"0.5\", 0.5], [2]]", "JSON を [[秒, x, y], [秒], …] の形（数だけ）で読めません（2 行目）"),
        ("[[0], [1, true, 0.5], [2]]", "JSON を [[秒, x, y], [秒], …] の形（数だけ）で読めません（2 行目）"),
        ("[[0], [1, 0.5, 0.5], 2]", "JSON を [[秒, x, y], [秒], …] の形（数だけ）で読めません（3 行目）"),
        ("{\"keys\": [[0]]}", "JSON を [[秒, x, y], [秒], …] の形（数だけ）で読めません"),
        ("[[0], [1, 0.5, 0.5], [2]", "JSON を [[秒, x, y], [秒], …] の形（数だけ）で読めません"),
        ("", "JSON を [[秒, x, y], [秒], …] の形（数だけ）で読めません"),
    ])
    func rejectsScriptsThatCannotRun(json: String, problem: String) {
        #expect(Self.problem(json) == problem)
    }

    @Test("同じ時刻の行は並べてよい（指を離す瞬間）。x と y は端の 0 と 1 まで")
    func acceptsTheEdges() {
        #expect(Self.problem("[[0, 0, 1], [0, 1, 0], [0]]") == nil)
        #expect(Self.problem("[[0.5, 0.5, 0.5], [0.5]]") == nil)
    }

    @Test("無いファイルの台本は、理由を添えて読まない")
    func rejectsAMissingFile() {
        let missing = FileManager.default.temporaryDirectory.appending(path: "nonet-demo-\(UUID().uuidString).json")
        do {
            _ = try DemoScript(contentsOf: missing)
            Issue.record("無いファイルを読めたことになっている")
        } catch {
            #expect("\(error)".hasPrefix("ファイルを読めません（"))
            #expect(error is DemoScript.Problem)
        }
    }

    // MARK: - ポインタへの写し方

    @Test("台本の指は、トラックパッドの真ん中を円の中心にして、HUD の枠の 1.3 倍に広げてポインタに写す（奥が上）")
    func mapsTheFingerOntoTheHUD() {
        let map = CGRect(x: 100, y: 200, width: 200, height: 200)
        #expect(DemoScript.pointer(for: CGPoint(x: 0.5, y: 0.5), in: map) == CGPoint(x: 200, y: 300))
        #expect(DemoScript.pointer(for: CGPoint(x: 1, y: 0.5), in: map) == CGPoint(x: 330, y: 300))
        #expect(DemoScript.pointer(for: CGPoint(x: 0.5, y: 1), in: map) == CGPoint(x: 200, y: 170))
        #expect(DemoScript.pointer(for: CGPoint(x: 0, y: 0), in: map) == CGPoint(x: 70, y: 430))
    }
}

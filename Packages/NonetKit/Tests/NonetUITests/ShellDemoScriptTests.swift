// 担当: ui-shell。デモ動画の台本（DemoScript）を、本物の操作のロジック（EdgeSlideRecognizer・SessionEngine）に通して確かめる
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
    }

    /// 台本の指を 120Hz で入れ、開く動きの判定と SessionEngine を NonetController と同じ順でつなぐ
    static func replay(pageCount: Int = 4) -> Replay {
        var engine = SessionEngine()
        var recognizer = EdgeSlideRecognizer()
        // Xcode のプロファイル（1 ページ）の後ろにグローバルのページ。下の帯でグローバルの層（2 ページ目から）へ移る
        let configuration = SessionConfiguration(pageCount: pageCount, layerStart: 1)
        var result = Replay()
        var nextTick: TimeInterval?
        var wasTouching = false

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
                    if let page = engine.pageIndex, result.pages.last != page { result.pages.append(page) }
                default: break
                }
            }
        }

        var time = 0.0
        while time <= DemoScript.duration + 0.5 {
            if let due = nextTick, due <= time {
                nextTick = nil
                collect(engine.handle(.tick(at: time)), at: time)
            }
            var frame: TouchFrame?
            if let point = DemoScript.sample(at: time) {
                wasTouching = true
                frame = TouchFrame(timestamp: time, points: [TouchPoint(id: 1, x: point.x, y: point.y, majorAxis: 12)])
            } else if wasTouching {
                wasTouching = false
                frame = TouchFrame(timestamp: time, points: [])
            }
            if let frame {
                collect(engine.handle(.touches(frame)), at: time)
                if recognizer.apply(frame, isSessionActive: engine.isInSession) == .slid {
                    result.openedAt.append(time)
                    collect(engine.handle(.open(at: time, configuration: configuration)), at: time)
                }
            }
            time += 1.0 / 120
        }
        return result
    }

    @Test("3回開く: 中央のマスを実行・下の帯でグローバルのページへ移って中央のマスを実行・外枠ですぐ離してやめる")
    func theScriptShowsTheThreeSessions() {
        let result = Self.replay()
        #expect(result.openedAt.count == 3)
        // 1回目はいちばん上のページの中央、2回目は1つ先のページの中央（1回だけ切り替わる）
        #expect(result.executions == ["0:4", "1:4"])
        #expect(result.haptics.filter { $0 == .layerChange }.count == 1)
        #expect(result.haptics.filter { $0 == .pageChange }.isEmpty)
        #expect(result.ends == [.released, .released, .cancelled(.liftedInFrame)])
    }

    @Test("開く動きは、上の縁から1本指で下へ滑らせたもの。どれも触れてから 0.6 秒のうちに開く")
    func opensQuicklyFromTheTopBand() {
        let result = Self.replay()
        let touchStarts = [1.0, 4.6, 9.8]
        for (start, opened) in zip(touchStarts, result.openedAt) {
            #expect(opened - start < EdgeSlideRecognizer.entryWindow)
            #expect(opened > start)
        }
    }

    @Test("台本の位置はトラックパッドの中。離している間は nil")
    func samplesStayOnThePad() {
        var time = 0.0
        while time < DemoScript.duration {
            if let point = DemoScript.sample(at: time) {
                #expect((0...1).contains(point.x) && (0...1).contains(point.y))
            }
            time += 0.01
        }
        #expect(DemoScript.sample(at: 0.5) == nil)
        #expect(DemoScript.sample(at: 3.5) == nil)
        #expect(DemoScript.sample(at: DemoScript.duration) == nil)
        #expect(DemoScript.sample(at: -1) == nil)
    }
}

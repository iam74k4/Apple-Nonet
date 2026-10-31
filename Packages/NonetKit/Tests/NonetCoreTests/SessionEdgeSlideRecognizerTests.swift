// 担当: engine。開く動き（上の縁から1本指を下へ滑り込ませる。EdgeSlideRecognizer）
import Foundation
import NonetCore
import Testing

/// 時刻つきのフレームを順に渡す
private struct Slide {
    var recognizer = EdgeSlideRecognizer()
    var fingers: [Int: (x: Double, y: Double, major: Double?)] = [:]
    var events: [EdgeSlideRecognizer.Event] = []
    var isSessionActive = false

    @discardableResult
    mutating func touch(_ id: Int = 1, x: Double = 0.5, y: Double, major: Double? = nil, at time: TimeInterval) -> EdgeSlideRecognizer.Event {
        fingers[id] = (x, y, major)
        return send(at: time)
    }

    @discardableResult
    mutating func lift(_ id: Int = 1, at time: TimeInterval) -> EdgeSlideRecognizer.Event {
        fingers[id] = nil
        return send(at: time)
    }

    @discardableResult
    mutating func send(at time: TimeInterval) -> EdgeSlideRecognizer.Event {
        let points = fingers.keys.sorted().compactMap { id in
            fingers[id].map { TouchPoint(id: id, x: $0.x, y: $0.y, majorAxis: $0.major) }
        }
        let event = recognizer.apply(TouchFrame(timestamp: time, points: points), isSessionActive: isSessionActive)
        events.append(event)
        return event
    }

    var slidCount: Int { events.filter { $0 == .slid }.count }
}

@Suite struct SessionEdgeSlideRecognizerTests {
    typealias R = EdgeSlideRecognizer

    @Test func constantsMatchTheSpec() {
        #expect(R.entryBandHeight == 0.06)
        #expect(R.entryTravel == 0.05)
        #expect(R.entryWindow == 0.4)
        #expect(R.palmMajorAxis == 25)
    }

    /// 上の縁の帯（奥 6%、幅はすべて）で触れ始めて、0.4 秒のうちに 0.05 下へ動けば開く
    @Test(arguments: [0.0, 0.5, 1.0])
    func aDownwardSlideFromTheTopBandOpens(x: Double) {
        var s = Slide()
        #expect(s.touch(x: x, y: 0.97, at: 10) == .touchBeganInBand)
        #expect(s.touch(x: x, y: 0.94, at: 10.05) == .none)
        #expect(s.touch(x: x, y: 0.91, at: 10.1) == .slid)
        // 1つのタッチで1回だけ
        #expect(s.touch(x: x, y: 0.7, at: 10.2) == .none)
        #expect(s.slidCount == 1)
    }

    @Test func theBandEdgeIsInsideAndBelowItIsOutside() {
        #expect(R.isInEntryBand(x: 0.3, y: 1 - R.entryBandHeight))
        #expect(R.isInEntryBand(x: 0.3, y: 1))
        #expect(!R.isInEntryBand(x: 0.3, y: 1 - R.entryBandHeight - 0.001))
        #expect(!R.isInEntryBand(x: 0.3, y: .nan))
    }

    /// 帯の外で触れ始めたタッチは、帯に入ってきても、下へ動いても開かない
    @Test func aTouchThatBeganBelowTheBandNeverOpens() {
        var s = Slide()
        #expect(s.touch(y: 0.9, at: 0) == .none)
        s.touch(y: 0.98, at: 0.05)
        s.touch(y: 0.8, at: 0.1)
        s.touch(y: 0.5, at: 0.15)
        #expect(s.slidCount == 0)
    }

    /// 動きが足りない（0.05 未満）なら開かない
    @Test func tooLittleTravelDoesNotOpen() {
        var s = Slide()
        s.touch(y: 0.97, at: 0)
        #expect(s.touch(y: 0.97 - R.entryTravel + 0.002, at: 0.1) == .none)
        #expect(s.touch(y: 0.97 - R.entryTravel - 0.001, at: 0.15) == .slid)
    }

    /// 触れてから 0.4 秒を過ぎてから届いても開かない（上の縁からゆっくり動かすのは、ふつうのポインタの移動）
    @Test func aSlowSlideDoesNotOpen() {
        var s = Slide()
        s.touch(y: 0.97, at: 0)
        s.touch(y: 0.96, at: 0.3)
        #expect(s.touch(y: 0.85, at: R.entryWindow + 0.01) == .none)
        // そのタッチでは、もう待たない
        #expect(s.touch(y: 0.6, at: 0.5) == .none)
        #expect(s.slidCount == 0)
        // 0.4 秒ちょうどは間に合う
        var onTime = Slide()
        onTime.touch(y: 0.97, at: 0)
        #expect(onTime.touch(y: 0.9, at: R.entryWindow) == .slid)
    }

    /// 下より横に動いた（|dx| > dy）なら開かない。真下から 45° までは開く
    @Test func theSlideMustBeMostlyDownward() {
        #expect(R.isEntrySlide(dx: 0, dy: 0.05))
        #expect(R.isEntrySlide(dx: 0.06, dy: 0.06))
        #expect(R.isEntrySlide(dx: -0.06, dy: 0.06))
        #expect(!R.isEntrySlide(dx: 0.07, dy: 0.06))
        #expect(!R.isEntrySlide(dx: 0, dy: -0.06))
        #expect(!R.isEntrySlide(dx: .nan, dy: 0.06))

        var diagonal = Slide()
        diagonal.touch(x: 0.5, y: 0.97, at: 0)
        #expect(diagonal.touch(x: 0.57, y: 0.91, at: 0.1) == .none)
        #expect(diagonal.slidCount == 0)
    }

    /// 上の縁に沿って横に滑らせた（ポインタを動かしている）タッチは、その後に下へ動いても開かない
    @Test func aSidewaysSlideAlongTheEdgeGivesUp() {
        var s = Slide()
        s.touch(x: 0.3, y: 0.97, at: 0)
        s.touch(x: 0.36, y: 0.97, at: 0.05)
        #expect(s.touch(x: 0.36, y: 0.85, at: 0.1) == .none)
        #expect(s.slidCount == 0)
    }

    /// 2本目の指が触れたら、そのタッチでは開かない。最初から2本・ほかの指が触れているところに置いた指も
    @Test func aSecondFingerStopsIt() {
        var s = Slide()
        s.touch(1, y: 0.97, at: 0)
        s.touch(2, x: 0.2, y: 0.3, at: 0.02)
        s.lift(2, at: 0.04)
        #expect(s.touch(1, y: 0.85, at: 0.1) == .none)
        #expect(s.slidCount == 0)

        var resting = Slide()
        resting.touch(2, x: 0.2, y: 0.05, at: 0)
        #expect(resting.touch(1, y: 0.97, at: 0.5) == .none)
        #expect(resting.touch(1, y: 0.85, at: 0.6) == .none)
        #expect(resting.slidCount == 0)

        var both = Slide()
        both.fingers = [1: (0.4, 0.97, nil), 2: (0.6, 0.97, nil)]
        #expect(both.send(at: 0) == .none)
        both.fingers = [1: (0.4, 0.85, nil), 2: (0.6, 0.85, nil)]
        #expect(both.send(at: 0.1) == .none)
    }

    /// 手のひらの大きさの接触（majorAxis が 25 以上）なら開かない。大きさが分からなければ外さない
    @Test func aPalmDoesNotOpen() {
        var palm = Slide()
        #expect(palm.touch(y: 0.97, major: 30, at: 0) == .none)
        #expect(palm.touch(y: 0.85, major: 30, at: 0.1) == .none)

        var grows = Slide()
        grows.touch(y: 0.97, major: 12, at: 0)
        #expect(grows.touch(y: 0.85, major: R.palmMajorAxis, at: 0.1) == .none)

        var unknown = Slide()
        unknown.touch(y: 0.97, at: 0)
        #expect(unknown.touch(y: 0.85, at: 0.1) == .slid)
        #expect(R.isPalmSized(TouchPoint(id: 1, x: 0, y: 0, majorAxis: 25)))
        #expect(!R.isPalmSized(TouchPoint(id: 1, x: 0, y: 0, majorAxis: 24.9)))
        #expect(!R.isPalmSized(TouchPoint(id: 1, x: 0, y: 0)))
    }

    /// セッション中に触れ始めた指は待たない（開いている9マスの指を、閉じた後に開く動きとみなさない）
    @Test func touchesDuringASessionAreIgnored() {
        var s = Slide()
        s.isSessionActive = true
        #expect(s.touch(y: 0.97, at: 0) == .none)
        s.isSessionActive = false
        #expect(s.touch(y: 0.85, at: 0.1) == .none)
        // 待っている間にセッションが始まったら（別の道筋で開いた）、取り消す
        var waiting = Slide()
        waiting.touch(y: 0.97, at: 0)
        waiting.isSessionActive = true
        #expect(waiting.touch(y: 0.85, at: 0.1) == .none)
        #expect(!waiting.recognizer.isWaiting)
    }

    /// 指を離すと待つのをやめ、次のタッチでまた待つ。離すのと置くのが1フレームの間に起きたら、新しいタッチ
    @Test func everyTouchGetsItsOwnChance() {
        var s = Slide()
        s.touch(y: 0.97, at: 0)
        s.lift(at: 0.05)
        #expect(!s.recognizer.isWaiting)
        s.touch(y: 0.97, at: 1)
        #expect(s.touch(y: 0.9, at: 1.1) == .slid)
        // 指が入れ替わった（restarted）
        var swapped = Slide()
        swapped.touch(1, y: 0.5, at: 0)
        swapped.fingers = [2: (0.5, 0.98, nil)]
        #expect(swapped.send(at: 0.05) == .touchBeganInBand)
        #expect(swapped.touch(2, y: 0.9, at: 0.1) == .slid)
    }
}

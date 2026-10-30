// 担当: engine。トラックパッドの角の長押し（CornerHoldRecognizer）を見分ける規則
import Foundation
import NonetCore
import Testing

/// 指の動きを時刻つきで渡す台本。既定は左上の角を見ていて、セッションの外
private struct CornerScript {
    var recognizer = CornerHoldRecognizer()
    var corner: TouchActivation = .topLeft
    var isSessionActive = false
    private(set) var fingers: [Int: (x: Double, y: Double)] = [:]

    init(corner: TouchActivation = .topLeft) {
        self.corner = corner
    }

    @discardableResult
    mutating func touch(_ id: Int = 1, x: Double, y: Double, at time: TimeInterval) -> Bool {
        fingers[id] = (x, y)
        return send(at: time)
    }

    /// 触れている指をまとめて置き換える（同じフレームで2本置く など）
    @discardableResult
    mutating func setFingers(_ points: [(id: Int, x: Double, y: Double)], at time: TimeInterval) -> Bool {
        fingers = [:]
        for point in points {
            fingers[point.id] = (point.x, point.y)
        }
        return send(at: time)
    }

    @discardableResult
    mutating func lift(_ id: Int = 1, at time: TimeInterval) -> Bool {
        fingers[id] = nil
        return send(at: time)
    }

    /// いまの指をそのまま送り直す
    @discardableResult
    mutating func send(at time: TimeInterval) -> Bool {
        let points = fingers.keys.sorted().compactMap { id in fingers[id].map { TouchPoint(id: id, x: $0.x, y: $0.y) } }
        return recognizer.apply(TouchFrame(timestamp: time, points: points), corner: corner, isSessionActive: isSessionActive)
    }

    mutating func tick(at time: TimeInterval) -> Bool {
        recognizer.tick(at: time, corner: corner, isSessionActive: isSessionActive)
    }
}

@Suite struct SessionCornerHoldRecognizerTests {
    typealias R = CornerHoldRecognizer

    /// 左上・右上の角の中ほど
    static let topLeft = (x: 0.05, y: 0.95)
    static let topRight = (x: 0.95, y: 0.95)

    @Test func theConstantsMatchTheSpec() {
        #expect(R.zoneWidth == 0.12)
        #expect(R.zoneHeight == 0.18)
        #expect(R.holdDuration == 0.4)
        #expect(R.movementTolerance == 0.02)
    }

    // MARK: 合図する

    @Test func aStillFingerInTheCornerActivatesAfterTheHold() {
        var s = CornerScript()
        #expect(s.touch(x: Self.topLeft.x, y: Self.topLeft.y, at: 10) == false)
        #expect(s.recognizer.deadline == 10 + R.holdDuration)
        #expect(s.send(at: 10.2) == false)
        #expect(s.send(at: 10 + R.holdDuration - 0.001) == false)
        #expect(s.send(at: 10 + R.holdDuration) == true)
        #expect(s.recognizer.deadline == nil)
    }

    /// 指を止めている間にフレームが来なくても、合図の時刻の tick で始まる
    @Test func theDeadlineTickActivatesWithoutFurtherFrames() {
        var s = CornerScript()
        s.touch(x: Self.topLeft.x, y: Self.topLeft.y, at: 10)
        #expect(s.tick(at: 10.39) == false)
        #expect(s.tick(at: 10.4) == true)
    }

    @Test func smallMovementsWithinTheToleranceStillActivate() {
        var s = CornerScript()
        s.touch(x: 0.05, y: 0.95, at: 10)
        s.touch(x: 0.05 + R.movementTolerance * 0.7, y: 0.95 - R.movementTolerance * 0.7, at: 10.2)
        #expect(s.send(at: 10.4) == true)
    }

    @Test func theTopRightCornerActivatesWhenChosen() {
        var s = CornerScript(corner: .topRight)
        s.touch(x: Self.topRight.x, y: Self.topRight.y, at: 3)
        #expect(s.tick(at: 3.4) == true)
        // 左上は見ていない
        var other = CornerScript(corner: .topRight)
        other.touch(x: Self.topLeft.x, y: Self.topLeft.y, at: 3)
        #expect(other.recognizer.deadline == nil)
        #expect(other.tick(at: 3.4) == false)
        #expect(other.send(at: 3.5) == false)
    }

    // MARK: 取り消す

    @Test func aSecondFingerCancels() {
        var s = CornerScript()
        s.touch(x: 0.05, y: 0.95, at: 10)
        s.touch(2, x: 0.5, y: 0.5, at: 10.1)
        #expect(s.recognizer.deadline == nil)
        // もう1本を離して、角の指だけに戻っても、このタッチでは待たない
        s.lift(2, at: 10.2)
        #expect(s.send(at: 10.6) == false)
        #expect(s.tick(at: 11) == false)
    }

    @Test func movingBeyondTheToleranceCancels() {
        var s = CornerScript()
        s.touch(x: 0.05, y: 0.95, at: 10)
        s.touch(x: 0.05 + R.movementTolerance + 0.005, y: 0.95, at: 10.1)
        #expect(s.recognizer.deadline == nil)
        // 元の位置に戻っても待たない
        s.touch(x: 0.05, y: 0.95, at: 10.2)
        #expect(s.send(at: 10.6) == false)
    }

    @Test func liftingEarlyCancels() {
        var s = CornerScript()
        s.touch(x: 0.05, y: 0.95, at: 10)
        s.lift(at: 10.3)
        #expect(s.recognizer.deadline == nil)
        #expect(s.tick(at: 10.4) == false)
    }

    /// 角の外で触れ始め、角に入ってきた指は待たない（ふつうのポインタの操作で角を通っただけ）
    @Test func aTouchThatStartsOutsideAndMovesIntoTheCornerDoesNotActivate() {
        var s = CornerScript()
        s.touch(x: 0.3, y: 0.7, at: 10)
        #expect(s.recognizer.deadline == nil)
        s.touch(x: 0.05, y: 0.95, at: 10.1)
        #expect(s.send(at: 10.6) == false)
        #expect(s.tick(at: 11) == false)
    }

    /// 最初から2本で触れたジェスチャー（スクロールなど）は、1本が角に残っても待たない
    @Test func aGestureThatStartsWithTwoFingersDoesNotActivate() {
        var s = CornerScript()
        s.setFingers([(1, 0.05, 0.95), (2, 0.2, 0.9)], at: 10)
        #expect(s.recognizer.deadline == nil)
        s.lift(2, at: 10.1)
        #expect(s.send(at: 10.6) == false)
        #expect(s.tick(at: 11) == false)
        // 新しいタッチなら、また待つ
        s.lift(at: 11.1)
        s.touch(x: 0.05, y: 0.95, at: 12)
        #expect(s.tick(at: 12.4) == true)
    }

    /// 指を離すのと置くのが1フレームの間に起きた（restarted）ときも、新しいタッチとして見る
    @Test func aFingerReplacedWithinOneFrameStartsANewWait() {
        var s = CornerScript()
        s.touch(x: 0.5, y: 0.5, at: 10)
        s.setFingers([(2, 0.05, 0.95)], at: 10.05)
        #expect(s.recognizer.deadline == 10.05 + R.holdDuration)
        #expect(s.tick(at: 10.05 + R.holdDuration) == true)
    }

    // MARK: 角の範囲

    @Test(arguments: [TouchActivation.topLeft, .topRight])
    func zoneEdgesAreInsideAndJustBeyondIsOutside(corner: TouchActivation) {
        let edgeX = corner == .topLeft ? R.zoneWidth : 1 - R.zoneWidth
        let beyondX = corner == .topLeft ? R.zoneWidth + 0.001 : 1 - R.zoneWidth - 0.001
        let edgeY = 1 - R.zoneHeight
        let cornerX = corner == .topLeft ? 0.0 : 1.0
        #expect(R.isInZone(x: cornerX, y: 1, corner: corner))
        #expect(R.isInZone(x: edgeX, y: 1, corner: corner))
        #expect(R.isInZone(x: cornerX, y: edgeY, corner: corner))
        #expect(R.isInZone(x: edgeX, y: edgeY, corner: corner))
        #expect(!R.isInZone(x: beyondX, y: 1, corner: corner))
        #expect(!R.isInZone(x: cornerX, y: edgeY - 0.001, corner: corner))
        // 手前の角は数えない
        #expect(!R.isInZone(x: cornerX, y: 0, corner: corner))

        // 縁ちょうどで置いた指は待ち、少し外なら待たない
        var inside = CornerScript(corner: corner)
        inside.touch(x: edgeX, y: edgeY, at: 1)
        #expect(inside.tick(at: 1.4) == true)
        var outside = CornerScript(corner: corner)
        outside.touch(x: beyondX, y: edgeY, at: 1)
        #expect(outside.tick(at: 1.4) == false)
        var below = CornerScript(corner: corner)
        below.touch(x: edgeX, y: edgeY - 0.001, at: 1)
        #expect(below.tick(at: 1.4) == false)
    }

    @Test func offHasNoZone() {
        #expect(!R.isInZone(x: 0, y: 1, corner: .off))
        #expect(!R.isInZone(x: 1, y: 1, corner: .off))
    }

    // MARK: 1回だけ

    @Test func itNeverFiresTwiceForTheSameTouch() {
        var s = CornerScript()
        s.touch(x: 0.05, y: 0.95, at: 10)
        #expect(s.send(at: 10.4) == true)
        #expect(s.send(at: 10.5) == false)
        #expect(s.tick(at: 10.8) == false)
        #expect(s.send(at: 12) == false)
        #expect(s.recognizer.deadline == nil)
        // 離して置き直せば、また合図する
        s.lift(at: 12.1)
        s.touch(x: 0.05, y: 0.95, at: 13)
        #expect(s.send(at: 13.4) == true)
    }

    @Test func theTickAndAFrameAtTheSameTimeFireOnce() {
        var s = CornerScript()
        s.touch(x: 0.05, y: 0.95, at: 10)
        #expect(s.tick(at: 10.4) == true)
        #expect(s.send(at: 10.4) == false)
    }

    // MARK: 見ていないとき

    @Test func nothingHappensWhileTheSettingIsOff() {
        var s = CornerScript(corner: .off)
        s.touch(x: 0.05, y: 0.95, at: 10)
        #expect(s.recognizer.deadline == nil)
        #expect(s.send(at: 10.5) == false)
        #expect(s.tick(at: 10.5) == false)
    }

    @Test func turningTheSettingOffOrChangingTheCornerCancelsTheWait() {
        var s = CornerScript()
        s.touch(x: 0.05, y: 0.95, at: 10)
        s.corner = .off
        #expect(s.send(at: 10.1) == false)
        #expect(s.recognizer.deadline == nil)
        s.corner = .topLeft
        #expect(s.send(at: 10.5) == false)

        var changed = CornerScript()
        changed.touch(x: 0.05, y: 0.95, at: 20)
        changed.corner = .topRight
        #expect(changed.tick(at: 20.4) == false)
        changed.corner = .topLeft
        #expect(changed.send(at: 20.6) == false)
    }

    /// セッション中に置いた指は、セッションが終わった後も長押しとみなさない（キーで始めたセッションの指など）
    @Test func aTouchThatBeganDuringASessionIsIgnoredAfterwards() {
        var s = CornerScript()
        s.isSessionActive = true
        s.touch(x: 0.05, y: 0.95, at: 10)
        #expect(s.recognizer.deadline == nil)
        s.isSessionActive = false
        #expect(s.send(at: 10.5) == false)
        #expect(s.tick(at: 11) == false)
        // 離して置き直せば待つ
        s.lift(at: 11.1)
        s.touch(x: 0.05, y: 0.95, at: 12)
        #expect(s.tick(at: 12.4) == true)
    }

    @Test func aSessionThatStartsWhileWaitingCancelsTheWait() {
        var s = CornerScript()
        s.touch(x: 0.05, y: 0.95, at: 10)
        s.isSessionActive = true
        #expect(s.tick(at: 10.4) == false)
        s.isSessionActive = false
        #expect(s.send(at: 10.6) == false)

        var framed = CornerScript()
        framed.touch(x: 0.05, y: 0.95, at: 20)
        framed.isSessionActive = true
        #expect(framed.send(at: 20.1) == false)
        framed.isSessionActive = false
        #expect(framed.tick(at: 20.4) == false)
    }
}

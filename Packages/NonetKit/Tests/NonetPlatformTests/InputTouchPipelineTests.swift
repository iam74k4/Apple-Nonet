import CMultitouch
import Foundation
import NonetCore
import os
import Testing
@testable import NonetPlatform

@Suite struct InputTouchConversionTests {
    @Test(arguments: [(Int32(3), true), (4, true), (0, false), (1, false), (2, false), (5, false), (6, false), (7, false)])
    func touchingStates(state: Int32, touching: Bool) throws {
        let point = try #require(TouchPoint(contact: MultitouchContact(identifier: 7, state: state, x: 0.25, y: 0.75)))
        #expect(point == TouchPoint(id: 7, x: 0.25, y: 0.75, isTouching: touching))
    }

    @Test func contactStructMatchesTheVerifiedLayout() {
        #expect(MemoryLayout<CMTTouch>.size == 96)
        #expect(MemoryLayout<CMTTouch>.offset(of: \.identifier) == 16)
        #expect(MemoryLayout<CMTTouch>.offset(of: \.state) == 20)
        #expect(MemoryLayout<CMTTouch>.offset(of: \.normalized) == 32)
        #expect(MemoryLayout<CMTTouch>.offset(of: \.absolute) == 68)
    }

    @Test func readsTheNormalizedPositionFromTheRawContact() {
        var touch = CMTTouch()
        touch.identifier = 3
        touch.state = 4
        touch.normalized.position = CMTPoint(x: 0.2, y: 0.8)
        touch.absolute.position = CMTPoint(x: 50, y: 60)
        #expect(MultitouchContact(touch) == MultitouchContact(identifier: 3, state: 4, x: 0.2, y: 0.8))
    }

    /// 接触の大きさ（長径）も読む。角の長押しで手のひらを見分けるのに使う
    @Test func readsTheMajorAxisFromTheRawContact() throws {
        var touch = CMTTouch()
        touch.identifier = 3
        touch.state = 4
        touch.normalized.position = CMTPoint(x: 0.2, y: 0.8)
        touch.majorAxis = 31.5
        let contact = MultitouchContact(touch)
        #expect(contact.majorAxis == 31.5)
        let point = try #require(TouchPoint(contact: contact))
        #expect(point.majorAxis == 31.5)
    }

    /// 0 以下・壊れた値は「大きさが分からない」
    @Test(arguments: [Float(0), -1, .nan, .infinity])
    func anUnknownMajorAxisIsNil(value: Float) throws {
        let point = try #require(TouchPoint(contact: MultitouchContact(identifier: 1, state: 4, x: 0.5, y: 0.5, majorAxis: value)))
        #expect(point.majorAxis == nil)
    }

    @Test func clampsCoordinatesIntoTheUnitSquare() throws {
        let point = try #require(TouchPoint(contact: MultitouchContact(identifier: 1, state: 4, x: -0.02, y: 1.3)))
        #expect(point.x == 0)
        #expect(point.y == 1)
    }

    @Test(arguments: [Float.nan, .infinity, -.infinity])
    func dropsBrokenCoordinates(value: Float) {
        #expect(TouchPoint(contact: MultitouchContact(identifier: 1, state: 4, x: value, y: 0.5)) == nil)
        #expect(TouchPoint(contact: MultitouchContact(identifier: 1, state: 4, x: 0.5, y: value)) == nil)
    }

    @Test func convertsAFrameKeepingOrder() {
        let contacts = [
            MultitouchContact(identifier: 2, state: 4, x: 0.1, y: 0.2),
            MultitouchContact(identifier: 3, state: 4, x: .nan, y: 0.2),
            MultitouchContact(identifier: 5, state: 5, x: 0.9, y: 0.8),
        ]
        let points = TouchPoint.points(from: contacts)
        #expect(points.map(\.id) == [2, 5])
        #expect(points.map(\.isTouching) == [true, false])
        #expect(TouchFrame(timestamp: 0, points: points).touchingIDs == [2])
    }
}

@Suite struct InputMultitouchDeviceTests {
    @Test func excludesMagicMiceButNeverTheBuiltInTrackpad() {
        let devices = [
            MultitouchDeviceInfo(id: 1, familyID: 112, isBuiltIn: false),
            MultitouchDeviceInfo(id: 2, familyID: 129, isBuiltIn: false),
            MultitouchDeviceInfo(id: 3, familyID: 113, isBuiltIn: false),
            MultitouchDeviceInfo(id: 4, familyID: 112, isBuiltIn: true),
        ]
        #expect(MultitouchDeviceInfo.usable(devices).map(\.id) == [4, 2])
    }

    @Test func putsBuiltInFirstAndKeepsTheRestInOrder() {
        let devices = [
            MultitouchDeviceInfo(id: 10, familyID: 128, isBuiltIn: false),
            MultitouchDeviceInfo(id: 11, familyID: 130, isBuiltIn: false),
            MultitouchDeviceInfo(id: 12, familyID: 110, isBuiltIn: true),
        ]
        #expect(MultitouchDeviceInfo.usable(devices).map(\.id) == [12, 10, 11])
        #expect(MultitouchDeviceInfo.usable([]).isEmpty)
    }
}

@Suite struct InputTouchDeviceSelectorTests {
    typealias Decision = TouchDeviceSelector.Decision

    @Test func ignoresEmptyFramesWhenNoDeviceIsActive() {
        var selector = TouchDeviceSelector()
        #expect(selector.accept(device: 1, touchingCount: 0, at: 0) == .drop)
        #expect(selector.activeDevice == nil)
    }

    @Test func locksOntoTheTouchedDeviceUntilItsFingersLift() {
        var selector = TouchDeviceSelector()
        #expect(selector.accept(device: 1, touchingCount: 1, at: 0) == Decision(deliver: true))
        #expect(selector.activeDevice == 1)
        // 別のデバイスのフレームは混ぜない
        #expect(selector.accept(device: 2, touchingCount: 2, at: 0.01) == .drop)
        #expect(selector.accept(device: 2, touchingCount: 0, at: 0.02) == .drop)
        #expect(selector.accept(device: 1, touchingCount: 2, at: 0.03) == Decision(deliver: true))
        // 指が離れたフレームは渡してから手放す
        #expect(selector.accept(device: 1, touchingCount: 0, at: 0.04) == Decision(deliver: true))
        #expect(selector.activeDevice == nil)
        #expect(selector.accept(device: 2, touchingCount: 1, at: 0.05) == Decision(deliver: true))
        #expect(selector.activeDevice == 2)
    }

    @Test func takesOverFromAStaleDeviceAndLiftsItsFingers() {
        var selector = TouchDeviceSelector()
        selector.staleInterval = 0.5
        _ = selector.accept(device: 1, touchingCount: 1, at: 10)
        #expect(selector.accept(device: 2, touchingCount: 1, at: 10.4) == .drop)
        // 1台目のフレームが途絶えた（抜かれた）
        #expect(selector.accept(device: 2, touchingCount: 0, at: 11) == .drop)
        #expect(selector.accept(device: 2, touchingCount: 1, at: 11) == Decision(deliver: true, liftPrevious: true))
        #expect(selector.activeDevice == 2)
    }

    @Test func resetForgetsTheActiveDevice() {
        var selector = TouchDeviceSelector()
        _ = selector.accept(device: 1, touchingCount: 1, at: 0)
        selector.reset()
        #expect(selector.accept(device: 2, touchingCount: 1, at: 0.01) == Decision(deliver: true))
    }
}

@Suite struct InputTouchFrameCoalescerTests {
    private func frame(_ time: TimeInterval, _ ids: [Int], x: Double = 0.5) -> TouchFrame {
        TouchFrame(timestamp: time, points: ids.map { TouchPoint(id: $0, x: x, y: 0.5) })
    }

    @Test func keepsTheFirstAndLatestFrameOfARun() {
        var coalescer = TouchFrameCoalescer(capacity: 16)
        for i in 0..<5 {
            coalescer.push(frame(Double(i) * 0.01, [1], x: Double(i) / 10))
        }
        let frames = coalescer.drain()
        #expect(frames.map(\.timestamp) == [0, 0.04])
        #expect(frames.last?.points.first?.x == 0.4)
        #expect(coalescer.drain().isEmpty)
    }

    /// メインスレッドが長く止まっても、途中の位置を keepInterval ごとに残す（指を置いて 0.2 秒で滑らせたことが分かる）
    @Test func keepsIntermediatePositionsDuringALongStall() {
        var coalescer = TouchFrameCoalescer(capacity: 32)
        for i in 0...65 {
            coalescer.push(frame(Double(i) * 0.01, [1], x: Double(i) / 100))
        }
        let times = coalescer.drain().map(\.timestamp)
        #expect(times.first == 0)
        #expect(times.last == 0.65)
        // 隣どうしの間は keepInterval より少し短いか同じくらい（遅れても、続けて残すのは keepInterval に1つ）
        for (earlier, later) in zip(times, times.dropFirst()) {
            #expect(later - earlier <= TouchFrameCoalescer.keepInterval + 1e-9)
        }
        #expect(times.contains { abs($0 - 0.2) <= TouchFrameCoalescer.keepInterval })
        #expect(times.count <= 20)
    }

    /// 上の縁から 0.2 秒で滑らせたあと、メインスレッドが 0.65 秒まで止まっていても、まとめたフレームで9マスが開く
    @Test func aSlideDuringALongStallStillOpens() {
        var coalescer = TouchFrameCoalescer(capacity: 32)
        for i in 0...65 {
            let time = Double(i) * 0.01
            let y = 0.97 - 0.07 * min(time, 0.2) / 0.2
            coalescer.push(TouchFrame(timestamp: time, points: [TouchPoint(id: 1, x: 0.5, y: y)]))
        }
        var recognizer = EdgeSlideRecognizer()
        let events = coalescer.drain().map { recognizer.apply($0, isSessionActive: false) }
        #expect(events.contains(.slid))
    }

    @Test func keepsEveryChangeInTheTouchingFingers() {
        var coalescer = TouchFrameCoalescer(capacity: 16)
        // メインスレッドが止まっている間の短いタップ
        coalescer.push(frame(0, [1]))
        coalescer.push(frame(0.01, [1]))
        coalescer.push(frame(0.02, [1]))
        coalescer.push(frame(0.03, []))
        coalescer.push(frame(0.04, [2]))
        coalescer.push(frame(0.05, [2, 3]))
        let frames = coalescer.drain()
        #expect(frames.map(\.timestamp) == [0, 0.02, 0.03, 0.04, 0.05])
        #expect(frames.map(\.touchingIDs) == [[1], [1], [], [2], [2, 3]])
    }

    @Test func hoveringPointsDoNotCountAsChanges() {
        var coalescer = TouchFrameCoalescer(capacity: 16)
        coalescer.push(frame(0, [1]))
        coalescer.push(frame(0.01, [1]))
        coalescer.push(TouchFrame(timestamp: 0.02, points: [TouchPoint(id: 1, x: 0.5, y: 0.5), TouchPoint(id: 4, x: 0.1, y: 0.1, isTouching: false)]))
        #expect(coalescer.drain().map(\.timestamp) == [0, 0.02])
    }

    @Test func neverGrowsBeyondCapacity() {
        var coalescer = TouchFrameCoalescer(capacity: 4)
        for i in 0..<100 {
            coalescer.push(frame(Double(i), i.isMultiple(of: 2) ? [1] : []))
            #expect(coalescer.count <= 4)
        }
        // 古いものから捨てる
        #expect(coalescer.drain().map(\.timestamp) == [96, 97, 98, 99])
    }

    /// 離れたことにしたフレーム（デバイスの開始し直し）は、続く空のフレームで置き換えない（開いていたら何も実行せずに閉じる印）
    @Test func keepsASynthesizedLift() {
        var coalescer = TouchFrameCoalescer(capacity: 16)
        coalescer.push(frame(0, []))
        coalescer.push(TouchFrame(timestamp: 0.01, points: [], isSynthesizedLift: true))
        coalescer.push(frame(0.02, []))
        let frames = coalescer.drain()
        #expect(frames.map(\.isSynthesizedLift) == [false, true, false])
    }

    @Test func capacityIsAtLeastTwo() {
        #expect(TouchFrameCoalescer(capacity: 0).capacity == 2)
    }
}

@Suite struct InputTouchPipelineTests {
    final class DrainCounter: Sendable {
        private let count = OSAllocatedUnfairLock(initialState: 0)
        var value: Int { count.withLock { $0 } }
        func increment() { count.withLock { $0 += 1 } }
    }

    private func points(_ ids: [Int]) -> [TouchPoint] {
        ids.map { TouchPoint(id: $0, x: 0.5, y: 0.5) }
    }

    @Test func schedulesOneDrainUntilItRuns() {
        let counter = DrainCounter()
        let pipeline = TouchPipeline(scheduleDrain: { counter.increment() })
        pipeline.receive(deviceID: 1, points: points([1]), timestamp: 0)
        pipeline.receive(deviceID: 1, points: points([1]), timestamp: 0.01)
        pipeline.receive(deviceID: 1, points: points([1]), timestamp: 0.02)
        #expect(counter.value == 1)
        let drained = pipeline.drain()
        #expect(drained.frames.map(\.timestamp) == [0, 0.02])
        #expect(drained.device == 1)
        pipeline.receive(deviceID: 1, points: [], timestamp: 0.03)
        #expect(counter.value == 2)
        #expect(pipeline.drain().frames.map(\.timestamp) == [0.03])
    }

    @Test func doesNotScheduleForIgnoredFrames() {
        let counter = DrainCounter()
        let pipeline = TouchPipeline(scheduleDrain: { counter.increment() })
        pipeline.receive(deviceID: 1, points: [], timestamp: 0)
        pipeline.receive(deviceID: 1, points: [TouchPoint(id: 1, x: 0, y: 0, isTouching: false)], timestamp: 0)
        #expect(counter.value == 0)
        #expect(pipeline.drain().frames.isEmpty)
    }

    @Test func neverMixesDevicesInOneStream() {
        let pipeline = TouchPipeline(scheduleDrain: {})
        pipeline.receive(deviceID: 1, points: points([1]), timestamp: 0)
        pipeline.receive(deviceID: 2, points: points([1, 2]), timestamp: 0.01)
        pipeline.receive(deviceID: 1, points: [], timestamp: 0.02)
        pipeline.receive(deviceID: 2, points: points([1, 2]), timestamp: 0.03)
        let drained = pipeline.drain()
        #expect(drained.frames.map(\.timestamp) == [0, 0.02, 0.03])
        #expect(drained.device == 2)
    }

    @Test func insertsALiftWhenTakingOverFromAStaleDevice() {
        let pipeline = TouchPipeline(staleInterval: 0.5, scheduleDrain: {})
        pipeline.receive(deviceID: 1, points: points([1]), timestamp: 0)
        pipeline.receive(deviceID: 2, points: points([1]), timestamp: 1)
        let frames = pipeline.drain().frames
        #expect(frames.map(\.touchingIDs) == [[1], [], [1]])
        #expect(frames.map(\.timestamp) == [0, 1, 1])
    }

    @Test func resetClearsPendingFramesButKeepsTheScheduledDrain() {
        let counter = DrainCounter()
        let pipeline = TouchPipeline(scheduleDrain: { counter.increment() })
        pipeline.receive(deviceID: 1, points: points([1]), timestamp: 0)
        pipeline.reset()
        // 予約済みの受け取りがまだ来ていないので、もう一度は予約しない
        pipeline.receive(deviceID: 2, points: points([3]), timestamp: 0.1)
        #expect(counter.value == 1)
        let drained = pipeline.drain()
        #expect(drained.frames.map(\.touchingIDs) == [[3]])
        #expect(drained.device == 2)
    }

    @Test func resetForgetsTheLastDevice() {
        let pipeline = TouchPipeline(scheduleDrain: {})
        pipeline.receive(deviceID: 4, points: points([1]), timestamp: 0)
        pipeline.reset()
        let drained = pipeline.drain()
        #expect(drained.frames.isEmpty)
        #expect(drained.device == nil)
    }

    @Test func staysBoundedUnderConcurrentFrames() {
        let counter = DrainCounter()
        let pipeline = TouchPipeline(capacity: 8, scheduleDrain: { counter.increment() })
        DispatchQueue.concurrentPerform(iterations: 4) { thread in
            for i in 0..<2_000 {
                let ids = i.isMultiple(of: 3) ? [] : [thread]
                pipeline.receive(deviceID: 1, points: ids.map { TouchPoint(id: $0, x: 0.5, y: 0.5) }, timestamp: Double(i))
                if i.isMultiple(of: 97) { _ = pipeline.drain() }
            }
        }
        #expect(pipeline.drain().frames.count <= 8)
        #expect(counter.value >= 1)
    }
}

import Testing
@testable import NonetCore

@Suite struct SessionFingerTrackerTests {
    private func point(_ id: Int, _ x: Double = 0.5, _ y: Double = 0.5, touching: Bool = true) -> TouchPoint {
        TouchPoint(id: id, x: x, y: y, isTouching: touching)
    }

    @Test func reportsBeganMovedEndedAndNone() {
        var tracker = FingerTracker()
        #expect(tracker.apply([], at: 0) == .none)
        #expect(tracker.apply([point(1)], at: 1) == .began)
        #expect(tracker.gestureStart == 1)
        #expect(tracker.apply([point(1, 0.6)], at: 2) == .moved)
        #expect(tracker.lastPlaced == .init(id: 1, x: 0.6, y: 0.5))
        #expect(tracker.apply([], at: 3) == .ended)
        #expect(!tracker.isTouching)
        #expect(tracker.apply([], at: 4) == .none)
    }

    @Test func keepsFingersInPlacementOrder() {
        var tracker = FingerTracker()
        _ = tracker.apply([point(5)], at: 0)
        _ = tracker.apply([point(2), point(5)], at: 1)
        // id ではなく置いた順。最後に置いたのは 2
        #expect(tracker.fingers.map(\.id) == [5, 2])
        #expect(tracker.lastPlaced?.id == 2)
        _ = tracker.apply([point(5), point(2), point(9)], at: 2)
        #expect(tracker.lastPlaced?.id == 9)
        _ = tracker.apply([point(5), point(2)], at: 3)
        #expect(tracker.lastPlaced?.id == 2)
    }

    @Test func fingersArrivingInTheSameFrameAreOrderedById() {
        var tracker = FingerTracker()
        #expect(tracker.apply([point(7), point(3)], at: 0) == .began)
        #expect(tracker.fingers.map(\.id) == [3, 7])
    }

    @Test func ignoresPointsThatAreNotTouching() {
        var tracker = FingerTracker()
        #expect(tracker.apply([point(1, touching: false)], at: 0) == .none)
        #expect(tracker.apply([point(1), point(2, touching: false)], at: 1) == .began)
        #expect(tracker.count == 1)
        #expect(tracker.apply([point(1, touching: false)], at: 2) == .ended)
    }

    @Test func duplicateIdsUseTheLastPoint() {
        var tracker = FingerTracker()
        _ = tracker.apply([point(1, 0.1), point(1, 0.9)], at: 0)
        #expect(tracker.count == 1)
        #expect(tracker.lastPlaced?.x == 0.9)
    }

    @Test func swappingEveryFingerBetweenFramesRestartsTheTouch() {
        var tracker = FingerTracker()
        _ = tracker.apply([point(1), point(2)], at: 0)
        #expect(tracker.gestureMaxFingers == 2)
        #expect(tracker.apply([point(3)], at: 1) == .restarted)
        #expect(tracker.gestureStart == 1)
        #expect(tracker.gestureMaxFingers == 1)
        #expect(tracker.fingers.map(\.id) == [3])
    }

    @Test func remembersTheMostFingersInTheTouch() {
        var tracker = FingerTracker()
        _ = tracker.apply([point(1)], at: 0)
        _ = tracker.apply([point(1), point(2), point(3)], at: 1)
        _ = tracker.apply([point(1)], at: 2)
        #expect(tracker.gestureMaxFingers == 3)
        #expect(tracker.gestureStart == 0)
        _ = tracker.apply([], at: 3)
        #expect(tracker.gestureMaxFingers == 0)
    }
}

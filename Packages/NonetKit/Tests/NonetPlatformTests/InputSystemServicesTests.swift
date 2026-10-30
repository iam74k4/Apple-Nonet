import Foundation
import NonetCore
import Testing
@testable import NonetPlatform

@Suite struct InputFrontmostAppFilterTests {
    let own = FrontmostAppFilter.Own(bundleID: "com.iam74k4.Nonet", processID: 500)

    @Test func reportsOrdinaryApps() {
        let decision = FrontmostAppFilter.decide(bundleID: "com.apple.dt.Xcode", name: "Xcode", processID: 42, own: own)
        #expect(decision == .update(RunningAppInfo(app: AppReference(bundleID: "com.apple.dt.Xcode", name: "Xcode"), processID: 42)))
    }

    @Test func ignoresNonetItself() {
        #expect(FrontmostAppFilter.decide(bundleID: "com.iam74k4.Nonet", name: "Nonet", processID: 500, own: own) == .ignore)
        // 別のプロセスでも、同じアプリなら無視する
        #expect(FrontmostAppFilter.decide(bundleID: "com.iam74k4.Nonet", name: "Nonet", processID: 501, own: own) == .ignore)
        // bundleID が無くても、自分のプロセスなら無視する
        #expect(FrontmostAppFilter.decide(bundleID: nil, name: nil, processID: 500, own: own) == .ignore)
    }

    @Test func appsWithoutBundleIDUseTheGlobalProfile() {
        #expect(FrontmostAppFilter.decide(bundleID: nil, name: "tool", processID: 9, own: own) == .update(nil))
        #expect(FrontmostAppFilter.decide(bundleID: "", name: "tool", processID: 9, own: own) == .update(nil))
    }

    @Test func fallsBackToTheBundleIDForTheName() {
        let expected = FrontmostAppFilter.Decision.update(RunningAppInfo(app: AppReference(bundleID: "com.example.app", name: "com.example.app"), processID: 3))
        #expect(FrontmostAppFilter.decide(bundleID: "com.example.app", name: nil, processID: 3, own: own) == expected)
        #expect(FrontmostAppFilter.decide(bundleID: "com.example.app", name: "", processID: 3, own: own) == expected)
    }

    @Test func worksWhenNonetHasNoBundleID() {
        let unbundled = FrontmostAppFilter.Own(bundleID: nil, processID: 1)
        #expect(FrontmostAppFilter.decide(bundleID: "com.apple.Safari", name: "Safari", processID: 2, own: unbundled) != .ignore)
    }

    @Test func recognizesNonetAsTheActiveApp() {
        // セッションを始めないかどうか（設定ウィンドウが前面）を決めるのに使う
        #expect(FrontmostAppFilter.isOwn(bundleID: "com.iam74k4.Nonet", processID: 500, own: own))
        #expect(FrontmostAppFilter.isOwn(bundleID: "com.iam74k4.Nonet", processID: 501, own: own))
        #expect(FrontmostAppFilter.isOwn(bundleID: nil, processID: 500, own: own))
        #expect(!FrontmostAppFilter.isOwn(bundleID: "com.apple.Safari", processID: 42, own: own))
        #expect(!FrontmostAppFilter.isOwn(bundleID: nil, processID: 42, own: own))
        #expect(!FrontmostAppFilter.isOwn(bundleID: "com.iam74k4.Nonet", processID: 42, own: FrontmostAppFilter.Own(bundleID: nil, processID: 1)))
    }
}

@MainActor
@Suite struct InputSchedulerTests {
    @Test func clampsDelays() {
        #expect(MainRunLoopScheduler.clampedDelay(.nan) == 0)
        #expect(MainRunLoopScheduler.clampedDelay(-3) == 0)
        #expect(MainRunLoopScheduler.clampedDelay(0.25) == 0.25)
        #expect(MainRunLoopScheduler.clampedDelay(.infinity) == MainRunLoopScheduler.maximumDelay)
    }

    @Test func nowIsTheMonotonicUptime() {
        let scheduler = MainRunLoopScheduler()
        let first = scheduler.now
        let uptime = ProcessInfo.processInfo.systemUptime
        let second = scheduler.now
        #expect(first <= uptime)
        #expect(uptime <= second)
    }

    @Test func runsTheActionOnTheMainThreadAfterTheDelay() async {
        let scheduler = MainRunLoopScheduler()
        let start = scheduler.now
        let elapsed: TimeInterval = await withCheckedContinuation { continuation in
            scheduler.schedule(after: 0.05) {
                #expect(Thread.isMainThread)
                continuation.resume(returning: scheduler.now - start)
            }
        }
        #expect(elapsed >= 0.045)
    }

    @Test func cancelledTasksNeverRun() async {
        let scheduler = MainRunLoopScheduler()
        var ran: [String] = []
        let cancelled = scheduler.schedule(after: 0.01) { ran.append("cancelled") }
        cancelled.cancel()
        await withCheckedContinuation { continuation in
            scheduler.schedule(after: 0.05) {
                ran.append("kept")
                continuation.resume()
            }
        }
        #expect(ran == ["kept"])
    }

    @Test func negativeDelayRunsSoon() async {
        let scheduler = MainRunLoopScheduler()
        await withCheckedContinuation { continuation in
            scheduler.schedule(after: -1) { continuation.resume() }
        }
    }

    @Test func taskFiresAtMostOnce() {
        var count = 0
        let task = MainQueueTask { count += 1 }
        #expect(task.isPending)
        task.fire()
        task.fire()
        #expect(count == 1)
        #expect(!task.isPending)
        task.cancel()
    }

    @Test func cancellingInsideTheActionIsSafe() {
        var count = 0
        var task: MainQueueTask?
        task = MainQueueTask {
            count += 1
            task?.cancel()
        }
        task?.fire()
        #expect(count == 1)
    }
}

@MainActor
@Suite struct InputSystemSmokeTests {
    @Test func accessibilitySettingsURLsAreValid() {
        for string in SystemPermissions.accessibilitySettingsURLs {
            #expect(URL(string: string) != nil, "\(string)")
        }
    }

    @Test func keyboardLayoutIsStable() {
        #expect(KeyboardLayout.isJIS == KeyboardLayout.isJIS)
    }

    @Test func frontmostObserverNeverReportsItself() {
        let observer = WorkspaceFrontmostAppObserver()
        #expect(observer.current?.processID != ProcessInfo.processInfo.processIdentifier)
        observer.start()
        observer.start()
        observer.stop()
    }
}

import AppKit
import ApplicationServices
import NonetCore
@testable import NonetPlatform
import Testing

/// 本物のウインドウを動かす（NONET_LIVE_WINDOW=1 のときだけ）。辞書.app を開き、左半分に置いてから最大化し、終わったら閉じる。
/// テストの実行ファイルにアクセシビリティの許可が無ければ、その旨を記録して何もしない
@Suite("画面に置く（実機）", .enabled(if: ProcessInfo.processInfo.environment["NONET_LIVE_WINDOW"] == "1"))
@MainActor
struct ActionWindowPlacementLiveTests {
    static let bundleID = "com.apple.Dictionary"

    @Test func placesARealWindow() async throws {
        guard AXIsProcessTrusted() else {
            Issue.record("テストの実行ファイルにアクセシビリティの許可が無い（AXIsProcessTrusted == false）ので、実機では確かめられない")
            return
        }
        let url = try #require(NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID))
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let running = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        defer { running.terminate() }
        let app = RunningAppInfo(app: AppReference(bundleID: Self.bundleID, name: "辞書"), processID: running.processIdentifier)
        let placer = AXWindowPlacer()
        // ウインドウが出るまで待つ（最長 8 秒）
        var target: CGRect?
        for _ in 0..<80 {
            if let frame = placer.targetFrame(for: .left, app: app) { target = frame; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let leftTarget = try #require(target, "辞書のウインドウが見つからない")
        let screen = try #require(NSScreen.main)
        #expect(leftTarget == WindowRegion.left.frame(in: screen.visibleFrame))

        try await placer.place(.left, app: app)
        try await Task.sleep(for: .milliseconds(300))
        let afterLeft = try #require(placer.targetFrame(for: .maximize, app: app))
        #expect(afterLeft == screen.visibleFrame)
        try await placer.place(.maximize, app: app)
        try await Task.sleep(for: .milliseconds(300))
        try await placer.place(.bottomRight, app: app)
        try await Task.sleep(for: .milliseconds(300))
        print("live: placed Dictionary left → maximize → bottomRight on \(screen.visibleFrame)")
    }
}

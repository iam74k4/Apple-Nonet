import Foundation
import NonetCore
@testable import NonetPlatform
import Testing

/// キー入力のマスを送る直前の、前面のアプリの確かめ
@Suite("キーの送り先")
struct ActionKeyTargetTests {
    static let safari = RunningAppInfo(app: AppReference(bundleID: "com.apple.Safari", name: "Safari"), processID: 100)

    @Test func sendsWhenTheAppIsStillInFront() throws {
        try KeyTarget.check(expected: Self.safari, frontmostPID: 100)
    }

    /// 前のマスのアプリの起動を待つ間に前面が変わったら、別のアプリに ⌘W などを送らない
    @Test func refusesWhenAnotherAppCameToTheFront() {
        let message = String(localized: "前面のアプリが変わったため、キーを送りませんでした", bundle: .nonetActions)
        #expect(throws: NonetError.actionFailed(message)) {
            try KeyTarget.check(expected: Self.safari, frontmostPID: 200)
        }
    }

    /// 送り先が決まっていない・いまの前面が分からないときは確かめない
    @Test func doesNotCheckWithoutBothApps() throws {
        try KeyTarget.check(expected: nil, frontmostPID: 200)
        try KeyTarget.check(expected: Self.safari, frontmostPID: nil)
    }
}

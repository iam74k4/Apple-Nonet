// 担当: platform-actions
import AppKit
import NonetCore
import os

/// 起動中アプリの候補（NSRunningApplication から必要なものだけ）
struct RunningAppCandidate: Equatable {
    var bundleID: String?
    var name: String?
    var processID: pid_t
    var isRegular: Bool
    var isTerminated: Bool

    init(bundleID: String?, name: String?, processID: pid_t, isRegular: Bool, isTerminated: Bool = false) {
        self.bundleID = bundleID
        self.name = name
        self.processID = processID
        self.isRegular = isRegular
        self.isTerminated = isTerminated
    }

    init(_ app: NSRunningApplication) {
        self.init(
            bundleID: app.bundleIdentifier,
            name: app.localizedName,
            processID: app.processIdentifier,
            isRegular: app.activationPolicy == .regular,
            isTerminated: app.isTerminated
        )
    }
}

enum RunningAppFilter {
    static let nonetBundleID = "com.iam74k4.Nonet"

    /// メニューバーを持つ（Dock に出る）アプリ。Nonet 自身は除き、名前順
    static func menuBarApps(from candidates: [RunningAppCandidate], excluding excluded: Set<String>) -> [RunningAppInfo] {
        candidates
            .compactMap { candidate -> RunningAppInfo? in
                guard candidate.isRegular, !candidate.isTerminated,
                      let bundleID = candidate.bundleID, !bundleID.isEmpty, !excluded.contains(bundleID)
                else { return nil }
                let name = candidate.name.flatMap { $0.isEmpty ? nil : $0 } ?? bundleID
                return RunningAppInfo(app: AppReference(bundleID: bundleID, name: name), processID: candidate.processID)
            }
            .sorted { lhs, rhs in
                let order = lhs.app.name.localizedStandardCompare(rhs.app.name)
                return order == .orderedSame ? lhs.processID < rhs.processID : order == .orderedAscending
            }
    }

    static var ownBundleIDs: Set<String> {
        var ids: Set<String> = [nonetBundleID]
        if let main = Bundle.main.bundleIdentifier { ids.insert(main) }
        return ids
    }
}

/// アクセシビリティ API でアプリのメニューを読む
@MainActor
public final class AccessibilityMenuReader: MenuReading {
    public init() {}

    public func runningApps() -> [RunningAppInfo] {
        RunningAppFilter.menuBarApps(
            from: NSWorkspace.shared.runningApplications.map(RunningAppCandidate.init),
            excluding: RunningAppFilter.ownBundleIDs
        )
    }

    public func menuItems(for app: RunningAppInfo) async throws -> [MenuItemNode] {
        guard AXIsProcessTrusted() else { throw NonetError.permissionDenied(ActionText.accessibility) }
        let name = app.app.name.isEmpty ? app.app.bundleID : app.app.name
        let pid = app.processID
        do {
            // 遅いアプリでは数秒かかる。メインスレッドはキーのイベントタップも動かしているので塞がない。
            // 呼んだ側が取り消したら（ほかのアプリを選び直した）、裏の読み取りもやめる（遅いアプリは要求を1つずつしか受けないので、
            // 古い読み取りが残ると、新しい読み取りが期限に届いて途中で切れる）
            let cancelled = MenuReadCancellation()
            let nodes = try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) {
                    try MenuTreeBuilder.build(AXMenuTree(pid: pid, isCancelled: { cancelled.isSet }))
                }.value
            } onCancel: {
                cancelled.set()
            }
            // やめたなら、途中までの木を読み終えたものとして返さない
            try Task.checkCancellation()
            return nodes
        } catch let error as AXCallError {
            ActionLog.logger.error("メニューを読めませんでした: AXError \(error.code.rawValue)")
            throw error.nonetError(appName: name)
        }
    }
}

/// メニューの読み取りをやめた印（裏のスレッドから読み、取り消しの通知から立てる）
final class MenuReadCancellation: Sendable {
    private let flag = OSAllocatedUnfairLock(initialState: false)

    var isSet: Bool { flag.withLock { $0 } }

    func set() {
        flag.withLock { $0 = true }
    }
}

// 担当: platform-actions
import AppKit
import ApplicationServices
import NonetCore

/// 「画面に置く」。前面のアプリの最前面のウインドウを、アクセシビリティ（AX）で動かす。
/// AX の座標は主画面の左上が原点で y が下向き。AppKit のグローバル座標（主画面の左下が原点、y が上向き）とは
/// WindowPlacementMath で行き来する。置く枠は、ウインドウの中心がある画面の使える範囲（メニューバーと Dock を除く）から決める
@MainActor
public final class AXWindowPlacer: WindowPlacing {
    public nonisolated init() {}

    public func targetFrame(for region: WindowRegion, app: RunningAppInfo?) -> CGRect? {
        guard let window = focusedWindow(of: app), let frame = frame(of: window) else { return nil }
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        let appKitFrame = WindowPlacementMath.flipped(frame, primaryHeight: primaryHeight)
        let visible = WindowPlacementMath.screenIndex(containing: appKitFrame, in: screens.map(\.frame)).map { screens[$0].visibleFrame }
            ?? NSScreen.main?.visibleFrame
        guard let visible else { return nil }
        return region.frame(in: visible)
    }

    public func place(_ region: WindowRegion, app: RunningAppInfo?) throws {
        guard AXIsProcessTrusted() else { throw NonetError.permissionDenied(ActionText.accessibility) }
        guard let window = focusedWindow(of: app) else {
            throw NonetError.actionFailed(String(localized: "前面のウインドウが見つかりません", bundle: .nonetActions))
        }
        guard let target = targetFrame(for: region, app: app) else {
            throw NonetError.actionFailed(String(localized: "ウインドウの場所を読めませんでした", bundle: .nonetActions))
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let axTarget = WindowPlacementMath.flipped(target, primaryHeight: primaryHeight)
        // 大きさに下限のあるアプリでも位置が合うよう、大きさ → 位置 → 大きさ の順に入れる
        try set(window, size: axTarget.size)
        try set(window, position: axTarget.origin)
        try set(window, size: axTarget.size)
        guard let after = frame(of: window), WindowPlacementMath.isPlaced(after, at: axTarget) else {
            throw NonetError.actionFailed(String(localized: "このウインドウは動かせませんでした（フルスクリーンや、大きさの決まったウインドウかもしれません）", bundle: .nonetActions))
        }
    }

    // MARK: AX

    /// app（nil なら今の前面のアプリ）の、キーのウインドウ。無ければメインのウインドウ、それも無ければ最初のウインドウ
    private func focusedWindow(of app: RunningAppInfo?) -> AXUIElement? {
        guard let pid = app?.processID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let application = AXUIElementCreateApplication(pid)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(application, attribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                return (value as! AXUIElement)
            }
        }
        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows) == .success,
           let list = windows as? [AXUIElement], let first = list.first {
            return first
        }
        return nil
    }

    /// AX の座標（主画面の左上が原点、y は下向き）
    private func frame(of window: AXUIElement) -> CGRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        guard read(window, kAXPositionAttribute, .cgPoint, into: &position), read(window, kAXSizeAttribute, .cgSize, into: &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// AXValue の中身（CGPoint・CGSize）を result に写す。参照を含まない値だけに限る（生のバイトで書き込むので）
    private func read<T: BitwiseCopyable>(_ window: AXUIElement, _ attribute: String, _ type: AXValueType, into result: inout T) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return false }
        return AXValueGetValue(value as! AXValue, type, &result)
    }

    private func set(_ window: AXUIElement, position: CGPoint) throws {
        var point = position
        guard let value = AXValueCreate(.cgPoint, &point) else { throw NonetError.actionFailed("AXValue") }
        try check(AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value))
    }

    private func set(_ window: AXUIElement, size: CGSize) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { throw NonetError.actionFailed("AXValue") }
        try check(AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value))
    }

    private func check(_ error: AXError) throws {
        switch error {
        case .success:
            return
        case .apiDisabled, .notImplemented:
            throw NonetError.permissionDenied(ActionText.accessibility)
        default:
            throw NonetError.actionFailed(String(localized: "このウインドウは動かせませんでした（フルスクリーンや、大きさの決まったウインドウかもしれません）", bundle: .nonetActions))
        }
    }
}

/// 座標の計算（AppKit と AX の行き来、ウインドウのある画面、置けたかの判断）。NSScreen に触れない
enum WindowPlacementMath {
    /// AppKit のグローバル座標と AX の座標を行き来する（どちらも主画面を基準に、y を折り返す）
    static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// ウインドウの中心を含む画面。無ければ、重なりがいちばん大きい画面。どの画面にも掛かっていなければ nil
    static func screenIndex(containing window: CGRect, in frames: [CGRect]) -> Int? {
        let center = CGPoint(x: window.midX, y: window.midY)
        if let index = frames.firstIndex(where: { $0.contains(center) }) {
            return index
        }
        let overlaps = frames.map { frame -> CGFloat in
            let intersection = frame.intersection(window)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        guard let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 else { return nil }
        return best
    }

    /// 置けたとみなす（位置が target に近い。大きさに下限のあるアプリは、大きさが違っても位置が合えばよい）
    static func isPlaced(_ frame: CGRect, at target: CGRect, tolerance: CGFloat = 10) -> Bool {
        abs(frame.minX - target.minX) <= tolerance && abs(frame.minY - target.minY) <= tolerance
    }
}

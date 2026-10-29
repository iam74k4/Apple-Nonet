// 契約（共通部品。変更は統合担当だけ）。HUD・設定画面・初回起動で同じ見た目にする
import AppKit
import NonetCore
import SwiftUI

/// マスのアイコン。SF Symbols・アプリのアイコン・文字のどれか
public struct CellIconView: View {
    public var icon: CellIcon
    public var size: CGFloat

    public init(_ icon: CellIcon, size: CGFloat = 20) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size))
                .frame(width: size * 1.3, height: size * 1.3)
        case .app(let bundleID):
            Image(nsImage: AppIconCache.icon(forBundleID: bundleID))
                .resizable()
                .interpolation(.high)
                .frame(width: size * 1.4, height: size * 1.4)
        case .text(let text):
            Text(text)
                .font(.system(size: size * 0.8, weight: .bold))
                .frame(width: size * 1.3, height: size * 1.3)
                .background(RoundedRectangle(cornerRadius: size * 0.3).strokeBorder(.secondary.opacity(0.6)))
        }
    }
}

/// アプリのアイコンを bundleID から引く。見つからなければ汎用のアイコン
@MainActor
public enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    public static func icon(forBundleID bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        cache[bundleID] = image
        return image
    }
}

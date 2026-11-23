// 担当: ui-shell
// 「最近のスクショ」のトレイ: 最近のスクリーンショットを新しい順に並べ、クリックで画像をコピー、ドラッグでそのまま添付する。
// 前面のアプリを替えない（キーだけ受け取る）パネル。Esc・外のクリック・コピーで閉じる
import AppKit
import ImageIO
import NonetCore
import Observation
import SwiftUI

/// トレイの寸法
enum HUDScreenshotTrayLayout {
    static let thumbnailSize = CGSize(width: 148, height: 96)
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 18
    /// 見出しの行と、下の案内の行
    static let headerHeight: CGFloat = 26
    static let footerHeight: CGFloat = 34
    /// 名前（何分前）の行
    static let labelHeight: CGFloat = 20
    /// 何も並べないとき（無い・読めない）の中身の高さ
    static let messageHeight: CGFloat = 96
    /// サムネイルの長い辺の画素数（Retina で 148pt を描ける大きさ）
    static let thumbnailPixels = 360

    static func panelSize(count: Int) -> CGSize {
        let columns = max(count, 3)
        let width = padding * 2 + CGFloat(columns) * thumbnailSize.width + CGFloat(columns - 1) * spacing
        let body = count == 0 ? messageHeight : thumbnailSize.height + 8 + labelHeight
        return CGSize(width: width, height: padding * 2 + headerHeight + 10 + body + footerHeight)
    }
}

@MainActor
@Observable
final class HUDScreenshotTrayStore {
    var listing: ScreenshotListing?
    var thumbnails: [URL: NSImage] = [:]
    /// キーボード（← →）で選んでいる1枚
    var selection = 0
    /// 表示の基準の時刻（「3分前」）
    var now = Date()

    var items: [ScreenshotItem] {
        if case .found(let items, _)? = listing { return items }
        return []
    }
}

/// 前面のアプリを替えずにキーになるパネル。Esc・外のクリックで閉じる
final class HUDScreenshotTrayPanel: NSPanel {
    var onClose: (() -> Void)?
    var onMove: ((Int) -> Void)?
    var onCopySelection: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func resignKey() {
        super.resignKey()
        // ほかのアプリやウインドウをクリックした（添付する先の入力欄に戻った など）
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: onMove?(-1)
        case 124: onMove?(1)
        case 36, 76, 49: onCopySelection?()
        default: super.keyDown(with: event)
        }
    }
}

/// 裏で読んだサムネイルをメインスレッドへ渡す箱（CGImage は読んだ後に変えない）
private struct ThumbnailBox: @unchecked Sendable {
    let image: CGImage?
}

@MainActor
final class HUDScreenshotTrayController {
    private let store = HUDScreenshotTrayStore()
    private var panel: HUDScreenshotTrayPanel?
    private var loadTask: Task<Void, Never>?
    /// コピーした（トーストで知らせる）
    var onCopied: ((ScreenshotItem) -> Void)?
    /// 探す（テストでは差し替える）
    var findScreenshots: () -> ScreenshotListing = {
        let defaults = UserDefaults(suiteName: ScreenshotFolder.defaultsDomain)
        return ScreenshotFolder.recent(
            in: ScreenshotFolder.location(defaults: defaults),
            namePrefixes: ScreenshotFolder.namePrefixes(defaults: defaults)
        )
    }
    /// クリップボードに書く（テストではクリップボードに触れないように差し替える）
    var writeToPasteboard: (ScreenshotItem) -> Bool = { HUDScreenshotTrayController.write($0, to: .general) }
    /// URL を開く（保存先を Finder で開く・システム設定を開く）
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    var isVisible: Bool { panel?.isVisible == true }
    var listing: ScreenshotListing? { store.listing }

    /// center を中心に出す。開くたびに探し直す
    func show(centeredAt center: CGPoint, on screen: HUDScreenGeometry) {
        let listing = findScreenshots()
        store.listing = listing
        store.selection = 0
        store.now = Date()
        store.thumbnails = [:]
        let panel = self.panel ?? makePanel()
        panel.title = String(localized: "スクリーンショット", bundle: .module)
        let size = HUDScreenshotTrayLayout.panelSize(count: store.items.count)
        panel.setFrame(HUDPlacement.frame(size: size, centeredAt: center, in: screen), display: true)
        panel.makeKeyAndOrderFront(nil)
        loadThumbnails(for: store.items)
        HUDAccessibility.announce(Self.announcement(for: listing))
    }

    func close() {
        loadTask?.cancel()
        loadTask = nil
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    /// その1枚をクリップボードに入れて閉じる（画像と、ファイルとして貼り付けられる場所の両方）
    func copy(_ item: ScreenshotItem) {
        guard writeToPasteboard(item) else { return }
        ShellClipboard.didWrite()
        close()
        onCopied?(item)
    }

    func copySelection() {
        let items = store.items
        guard items.indices.contains(store.selection) else { return }
        copy(items[store.selection])
    }

    func moveSelection(by delta: Int) {
        let count = store.items.count
        guard count > 0 else { return }
        store.selection = min(max(store.selection + delta, 0), count - 1)
    }

    var selection: Int { store.selection }

    private func makePanel() -> HUDScreenshotTrayPanel {
        let panel = HUDScreenshotTrayPanel()
        panel.onClose = { [weak self] in self?.close() }
        panel.onMove = { [weak self] in self?.moveSelection(by: $0) }
        panel.onCopySelection = { [weak self] in self?.copySelection() }
        let view = HUDScreenshotTrayView(
            store: store,
            onCopy: { [weak self] in self?.copy($0) },
            onOpenFolder: { [weak self] in
                guard let self, let folder = self.store.listing?.folder else { return }
                self.close()
                self.openURL(folder)
            },
            onOpenPrivacySettings: { [weak self] in
                self?.close()
                self?.openURL(HUDScreenshotTrayView.privacySettingsURL)
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    /// サムネイルはメインスレッドの外で小さく読む（大きな画面のスクリーンショットでも止めない）
    private func loadThumbnails(for items: [ScreenshotItem]) {
        loadTask?.cancel()
        let urls = items.map(\.url)
        loadTask = Task { [weak self] in
            for url in urls {
                let box = await Task.detached(priority: .userInitiated) {
                    ThumbnailBox(image: Self.thumbnail(of: url, maxPixels: HUDScreenshotTrayLayout.thumbnailPixels))
                }.value
                guard !Task.isCancelled else { return }
                if let image = box.image {
                    self?.store.thumbnails[url] = NSImage(cgImage: image, size: .zero)
                }
            }
        }
    }

    nonisolated static func thumbnail(of url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 画像（PNG か TIFF）とファイルの場所を、1つの項目として書く。チャットやメールの入力欄では画像として、Finder ではファイルとして貼り付く
    nonisolated static func write(_ item: ScreenshotItem, to pasteboard: NSPasteboard) -> Bool {
        let entry = NSPasteboardItem()
        entry.setString(item.url.absoluteString, forType: .fileURL)
        let ext = item.url.pathExtension.lowercased()
        if ext == "png", let data = try? Data(contentsOf: item.url) {
            entry.setData(data, forType: .png)
        } else if (ext == "tif" || ext == "tiff"), let data = try? Data(contentsOf: item.url) {
            entry.setData(data, forType: .tiff)
        } else if let image = NSImage(contentsOf: item.url), let tiff = image.tiffRepresentation {
            entry.setData(tiff, forType: .tiff)
        } else {
            return false
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects([entry])
    }

    nonisolated static func announcement(for listing: ScreenshotListing) -> String {
        switch listing {
        case .found(let items, _) where items.isEmpty:
            String(localized: "スクリーンショットはまだありません", bundle: .module)
        case .found(let items, _):
            String(localized: "スクリーンショット \(items.count) 枚。クリックでコピー、ドラッグで添付", bundle: .module)
        case .notPermitted:
            String(localized: "スクリーンショットの保存先を読めません", bundle: .module)
        case .missingFolder:
            String(localized: "スクリーンショットの保存先が見つかりません", bundle: .module)
        }
    }
}

struct HUDScreenshotTrayView: View {
    @Bindable var store: HUDScreenshotTrayStore
    let onCopy: (ScreenshotItem) -> Void
    let onOpenFolder: () -> Void
    let onOpenPrivacySettings: () -> Void

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!

    typealias Layout = HUDScreenshotTrayLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            footer
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("スクリーンショット", bundle: .module)
                .font(.system(size: 14, weight: .semibold))
            if let folder = store.listing?.folder {
                Text(Self.folderName(folder))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(action: onOpenFolder) {
                Text("フォルダを開く", bundle: .module)
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .frame(height: Layout.headerHeight)
    }

    @ViewBuilder
    private var content: some View {
        switch store.listing {
        case .found(let items, _)? where !items.isEmpty:
            HStack(alignment: .top, spacing: Layout.spacing) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    thumbnail(item, isSelected: index == store.selection)
                }
            }
        case .notPermitted?:
            message(
                String(localized: "保存先のフォルダを読む許可がありません", bundle: .module),
                detail: String(localized: "システム設定 › プライバシーとセキュリティ › ファイルとフォルダ で、Nonet にデスクトップなどへのアクセスを許可してください", bundle: .module),
                button: (String(localized: "システム設定を開く", bundle: .module), onOpenPrivacySettings)
            )
        case .missingFolder?:
            message(
                String(localized: "スクリーンショットの保存先が見つかりません", bundle: .module),
                detail: String(localized: "⇧⌘5 の「オプション」で保存先を選び直してください", bundle: .module),
                button: nil
            )
        default:
            message(
                String(localized: "スクリーンショットはまだありません", bundle: .module),
                detail: String(localized: "撮ったものが、新しい順にここに並びます", bundle: .module),
                button: nil
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Text("クリックでコピー", bundle: .module)
            Text("ドラッグで添付", bundle: .module)
            Text("Esc で閉じる", bundle: .module)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: Layout.footerHeight, alignment: .bottom)
    }

    private func thumbnail(_ item: ScreenshotItem, isSelected: Bool) -> some View {
        Button {
            onCopy(item)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                    if let image = store.thumbnails[item.url] {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(3)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: Layout.thumbnailSize.width, height: Layout.thumbnailSize.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                        .padding(-3)
                )
                Text(Self.age(of: item.date, now: store.now))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(height: Layout.labelHeight)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .help(item.url.lastPathComponent)
        .accessibilityLabel(Text(Self.age(of: item.date, now: store.now)))
        .accessibilityHint(Text("クリックでコピー、ドラッグで添付", bundle: .module))
    }

    private func message(_ title: String, detail: String, button: (String, () -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let button {
                Button(button.0, action: button.1)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Layout.messageHeight, alignment: .topLeading)
    }

    /// 「たった今」「3分前」「昨日」（今の言語で）
    static func age(of date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 {
            return String(localized: "たった今", bundle: .module)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// 保存先の名前（ホームの中なら ~ から）
    static func folderName(_ folder: URL) -> String {
        let path = folder.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        if trimmed.hasPrefix(home) {
            return "~/" + trimmed.dropFirst(home.count).drop(while: { $0 == "/" })
        }
        return trimmed
    }
}

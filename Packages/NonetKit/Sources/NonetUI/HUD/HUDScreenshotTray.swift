// 担当: ui-shell
// 「最近のスクショ」のトレイ: 最近のスクリーンショットと画面の収録を新しい順に並べ、クリックでコピー、ドラッグでそのまま添付する。
// 前面のアプリを替えない（キーだけ受け取る）パネル。Esc・外のクリック・コピーで閉じる
import AppKit
import ImageIO
import NonetCore
import Observation
import QuickLookThumbnailing
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

    /// 1段に並べる最大の数（12枚は 6 × 2 段）
    static let maxColumns = 6

    /// 段の数に合わせた列の数（3 枚より少なくても、案内が入る幅は取る）
    static func columns(count: Int) -> Int {
        guard count > maxColumns else { return max(count, 3) }
        return Int((Double(count) / Double((count + maxColumns - 1) / maxColumns)).rounded(.up))
    }

    static func rows(count: Int) -> Int {
        count == 0 ? 0 : (count + columns(count: count) - 1) / columns(count: count)
    }

    static func panelSize(count: Int) -> CGSize {
        let columns = columns(count: count)
        let rows = rows(count: count)
        let width = padding * 2 + CGFloat(columns) * thumbnailSize.width + CGFloat(columns - 1) * spacing
        let row = thumbnailSize.height + 8 + labelHeight
        let body = count == 0 ? messageHeight : CGFloat(rows) * row + CGFloat(rows - 1) * spacing
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
    /// ← → は1つ、↑ ↓ は1段（列の数）
    var onMove: ((Int) -> Void)?
    var columns = 1
    var onCopySelection: (() -> Void)?
    /// ⌘⌫（Finder と同じ）で選んでいる1枚をゴミ箱へ
    var onTrashSelection: (() -> Void)?

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
        case 126: onMove?(-columns)
        case 125: onMove?(columns)
        case 36, 76, 49: onCopySelection?()
        case 51 where event.modifierFlags.contains(.command): onTrashSelection?()
        default: super.keyDown(with: event)
        }
    }
}

/// 裏で読んだサムネイルをメインスレッドへ渡す箱（CGImage は読んだ後に変えない）
struct ThumbnailBox: @unchecked Sendable {
    let image: CGImage?
}

@MainActor
final class HUDScreenshotTrayController {
    private let store = HUDScreenshotTrayStore()
    private var panel: HUDScreenshotTrayPanel?
    private var loadTask: Task<Void, Never>?
    /// 探している（最初の1回は macOS がフォルダを読む許可を確かめるので、メインスレッドでは探さない）
    private var listTask: Task<Void, Never>?
    /// show を呼ぶたびに増やす（前に頼んだ探し物の結果で、新しいトレイを上書きしない）
    private var generation = 0
    /// 出した場所（探し終えて大きさが変わったときに、同じ中心に置き直す）
    private var placement: (center: CGPoint, screen: HUDScreenGeometry)?
    /// コピーした（トーストで知らせる）
    var onCopied: ((ScreenshotItem) -> Void)?
    /// 探す（テストでは差し替える）
    var findScreenshots: @Sendable (ScreenshotTrayAction) -> ScreenshotListing = { options in
        let defaults = UserDefaults(suiteName: ScreenshotFolder.defaultsDomain)
        return ScreenshotFolder.recent(
            in: ScreenshotFolder.location(defaults: defaults),
            limit: options.count,
            includesVideos: options.includesVideos,
            namePrefixes: ScreenshotFolder.namePrefixes(defaults: defaults)
        )
    }
    /// クリップボードに書く（テストではクリップボードに触れないように差し替える）
    var writeToPasteboard: (ScreenshotItem) -> Bool = { HUDScreenshotTrayController.write($0, to: .general) }
    /// URL を開く（保存先を Finder で開く・システム設定を開く）
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Finder でそのファイルを選んで見せる
    var revealInFinder: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    /// ゴミ箱に入れる（Finder の「ゴミ箱に入れる」と同じ。戻せる）
    var moveToTrash: (URL) async throws -> Void = { url in
        _ = try await NSWorkspace.shared.recycle([url])
    }
    /// ゴミ箱に入れられなかった（トーストで知らせる）
    var onTrashFailed: ((ScreenshotItem) -> Void)?

    /// 出すときにキーにする（Esc・↑↓←→ を受け取る）。テストでは、ほかのテストのウインドウと取り合わないよう false にする
    var becomesKey = true

    var isVisible: Bool { panel?.isVisible == true }
    var listing: ScreenshotListing? { store.listing }

    /// center を中心に出す。すぐに「探しています」で出し、探し終えたら並べる（開くたびに探し直す）
    func show(_ options: ScreenshotTrayAction = ScreenshotTrayAction(), centeredAt center: CGPoint, on screen: HUDScreenGeometry) {
        generation += 1
        let current = generation
        loadTask?.cancel()
        listTask?.cancel()
        store.listing = nil
        store.selection = 0
        store.now = Date()
        store.thumbnails = [:]
        placement = (center, screen)
        let panel = self.panel ?? makePanel()
        panel.title = String(localized: "スクリーンショット", bundle: .module)
        layOut()
        if becomesKey {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        let find = findScreenshots
        listTask = Task { [weak self] in
            let listing = await Task.detached(priority: .userInitiated) { find(options) }.value
            guard let self, !Task.isCancelled, self.generation == current else { return }
            self.store.listing = listing
            self.layOut()
            self.loadThumbnails(for: self.store.items)
            HUDAccessibility.announce(Self.announcement(for: listing))
        }
    }

    /// 探し終えるまで待つ（テスト用）
    func waitForListing() async {
        await listTask?.value
    }

    /// 並べる数に合わせて大きさを変え、出した場所を中心に置き直す
    private func layOut() {
        guard let panel, let placement else { return }
        let count = store.items.count
        panel.columns = HUDScreenshotTrayLayout.columns(count: count)
        let size = HUDScreenshotTrayLayout.panelSize(count: count)
        panel.setFrame(HUDPlacement.frame(size: size, centeredAt: placement.center, in: placement.screen), display: true)
    }

    func close() {
        loadTask?.cancel()
        loadTask = nil
        listTask?.cancel()
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

    /// Finder でその1枚を選んで見せ、トレイを閉じる
    func reveal(_ item: ScreenshotItem) {
        close()
        revealInFinder(item.url)
    }

    /// その1枚をゴミ箱に入れ、トレイから外す（デスクトップを片付ける）。トレイは開いたまま
    func trash(_ item: ScreenshotItem) async {
        do {
            try await moveToTrash(item.url)
        } catch {
            onTrashFailed?(item)
            return
        }
        guard case .found(var items, let folder)? = store.listing, let index = items.firstIndex(of: item) else { return }
        items.remove(at: index)
        store.listing = .found(items, folder: folder)
        store.thumbnails[item.url] = nil
        store.selection = min(store.selection, max(items.count - 1, 0))
        layOut()
    }

    func trashSelection() {
        let items = store.items
        guard items.indices.contains(store.selection) else { return }
        let item = items[store.selection]
        Task { await trash(item) }
    }

    private func makePanel() -> HUDScreenshotTrayPanel {
        let panel = HUDScreenshotTrayPanel()
        panel.onClose = { [weak self] in self?.close() }
        panel.onMove = { [weak self] in self?.moveSelection(by: $0) }
        panel.onCopySelection = { [weak self] in self?.copySelection() }
        panel.onTrashSelection = { [weak self] in self?.trashSelection() }
        let view = HUDScreenshotTrayView(
            store: store,
            onCopy: { [weak self] in self?.copy($0) },
            onReveal: { [weak self] in self?.reveal($0) },
            onTrash: { [weak self] item in Task { await self?.trash(item) } },
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
        let entries = items.map { ($0.url, $0.isVideo) }
        loadTask = Task { [weak self] in
            for (url, isVideo) in entries {
                let box: ThumbnailBox
                if isVideo {
                    box = await Self.videoThumbnail(of: url)
                } else {
                    box = await Task.detached(priority: .userInitiated) {
                        ThumbnailBox(image: Self.thumbnail(of: url, maxPixels: HUDScreenshotTrayLayout.thumbnailPixels))
                    }.value
                }
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

    /// 動画の最初の場面（QuickLook。macOS が作るので、動画を自分で読まない）
    nonisolated static func videoThumbnail(of url: URL) async -> ThumbnailBox {
        let size = CGSize(width: HUDScreenshotTrayLayout.thumbnailSize.width, height: HUDScreenshotTrayLayout.thumbnailSize.height)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2, representationTypes: .thumbnail)
        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        return ThumbnailBox(image: representation?.cgImage)
    }

    /// 画像（PNG か TIFF）とファイルの場所を、1つの項目として書く。チャットやメールの入力欄では画像として、Finder ではファイルとして貼り付く。
    /// 動画はファイルの場所だけ（チャットやメールの入力欄では添付になる）
    nonisolated static func write(_ item: ScreenshotItem, to pasteboard: NSPasteboard) -> Bool {
        let entry = NSPasteboardItem()
        entry.setString(item.url.absoluteString, forType: .fileURL)
        let ext = item.url.pathExtension.lowercased()
        if item.isVideo {
            guard FileManager.default.isReadableFile(atPath: item.url.path(percentEncoded: false)) else { return false }
        } else if ext == "png", let data = try? Data(contentsOf: item.url) {
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
    let onReveal: (ScreenshotItem) -> Void
    let onTrash: (ScreenshotItem) -> Void
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
            let columns = Array(repeating: GridItem(.fixed(Layout.thumbnailSize.width), spacing: Layout.spacing, alignment: .top), count: Layout.columns(count: items.count))
            LazyVGrid(columns: columns, alignment: .leading, spacing: Layout.spacing) {
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
        case nil:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("探しています…", bundle: .module)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: Layout.messageHeight)
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
            Text("⌘⌫ でゴミ箱へ", bundle: .module)
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
                    if item.isVideo {
                        // 収録の印（右下の再生の印）
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(8)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: Layout.thumbnailSize.width, height: Layout.thumbnailSize.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                        .padding(-3)
                )
                Text(Self.label(of: item, now: store.now))
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
        .contextMenu {
            Button {
                onCopy(item)
            } label: {
                Text("コピー", bundle: .module)
            }
            Button {
                onReveal(item)
            } label: {
                Text("Finder で表示", bundle: .module)
            }
            Divider()
            Button(role: .destructive) {
                onTrash(item)
            } label: {
                Text("ゴミ箱に入れる", bundle: .module)
            }
        }
        .help(item.url.lastPathComponent)
        .accessibilityLabel(Text(Self.label(of: item, now: store.now)))
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

    /// 名前の行: 撮った時刻と、収録なら「収録」
    static func label(of item: ScreenshotItem, now: Date) -> String {
        let age = age(of: item.date, now: now)
        guard item.isVideo else { return age }
        return String(localized: "収録・\(age)", bundle: .module)
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

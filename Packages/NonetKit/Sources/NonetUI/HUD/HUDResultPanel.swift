// 担当: ui-shell
import AppKit
import NonetCore
import Observation
import SwiftUI

/// 結果のパネルの寸法
enum HUDResultLayout {
    static let width: CGFloat = 480
    /// 見出し（タイトルバーの高さを含む）とボタンの列
    static let headerHeight: CGFloat = 44
    static let footerHeight: CGFloat = 52
    static let textInset = CGSize(width: 16, height: 12)
    static let minTextAreaHeight: CGFloat = 72
    static let maxHeight: CGFloat = 560
    static let fontSize: CGFloat = 13

    static var chromeHeight: CGFloat { headerHeight + footerHeight }

    /// 文の高さに合わせ、画面の 3/4 か maxHeight の小さい方で止める（それより長ければスクロール）
    static func panelSize(textHeight: CGFloat, screen: HUDScreenGeometry) -> CGSize {
        let limit = min(maxHeight, (screen.visibleFrame.height - 2 * HUDPlacement.edgeMargin) * 0.75)
        let textArea = max(minTextAreaHeight, ceil(textHeight) + 2 * textInset.height)
        let height = max(chromeHeight + minTextAreaHeight, min(chromeHeight + textArea, limit))
        return CGSize(width: width, height: height)
    }

    static var textWidth: CGFloat {
        width - 2 * textInset.width
    }

    @MainActor
    static func textHeight(of text: String) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: fontSize)])
        let bounds = attributed.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return bounds.height
    }
}

/// フォーカスを奪わない結果のパネル。クリックして初めてキーになり、Esc・⌘W で閉じる
final class HUDResultPanel: NSPanel {
    var onClose: (() -> Void)?
    var onCopyAll: (() -> Void)?
    weak var textView: NSTextView?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: HUDResultLayout.width, height: 240),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        // 文を選ぶなど、キーが必要なときだけキーになる（前面アプリの入力を奪わない）
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func performClose(_ sender: Any?) {
        onClose?()
    }

    /// ⌘C・⌘A・⌘W はここで受ける。メインメニュー（ShellMainMenu）の「コピー」は選択が無いと使えないが、
    /// この画面では選択が無ければ全文をコピーする
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Caps Lock・テンキー・fn は見ない（Caps Lock が点いていると ⌘Q がメインメニューの「終了」に回り、Nonet が終わる）
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "c":
            if let textView, textView.selectedRange().length > 0 {
                textView.copy(nil)
                ShellClipboard.didWrite()
            } else {
                onCopyAll?()
            }
            return true
        case "a":
            textView?.selectAll(nil)
            return true
        case "w":
            onClose?()
            return true
        case "q" where !NSApplication.shared.isActive:
            // Nonet は前面ではない（メニューバーは前面のアプリのもの）。メインメニューの「終了」に回すと Nonet が終わってしまうので、
            // このパネルだけを閉じる
            onClose?()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

/// 読むだけの文。Esc は閉じるに回す（NSTextView は Esc を補完に使う）
final class HUDResultTextView: NSTextView {
    override func cancelOperation(_ sender: Any?) {
        window?.cancelOperation(sender)
    }

    override func complete(_ sender: Any?) {
        window?.cancelOperation(sender)
    }
}

@MainActor
@Observable
final class HUDResultStore {
    var model: ResultModel?
    var didCopy = false
}

struct HUDResultView: View {
    let store: HUDResultStore
    let onCopy: () -> Void
    let onClose: () -> Void
    var onTextViewCreated: (NSTextView) -> Void = { _ in }

    var body: some View {
        let model = store.model ?? ResultModel(title: "", text: "")
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let icon = model.icon {
                    CellIconView(icon, size: 14)
                }
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // 左上の閉じるボタンと重ならないように
            .padding(.horizontal, 72)
            .frame(maxWidth: .infinity)
            .frame(height: HUDResultLayout.headerHeight)
            Divider()
            HUDResultTextArea(text: model.text, onCreated: onTextViewCreated)
            Divider()
            HStack(spacing: 8) {
                Text("選択してコピーすることもできます", bundle: .module)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: onCopy) {
                    Label {
                        store.didCopy ? Text("コピーしました", bundle: .module) : Text("コピー", bundle: .module)
                    } icon: {
                        Image(systemName: store.didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .frame(minWidth: 96)
                }
                Button(action: onClose) {
                    Text("閉じる", bundle: .module)
                        .frame(minWidth: 64)
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.regular)
            .padding(.horizontal, 16)
            .frame(height: HUDResultLayout.footerHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

/// 選べてスクロールできる文（長い文でも軽い NSTextView を使う）
struct HUDResultTextArea: NSViewRepresentable {
    let text: String
    var onCreated: (NSTextView) -> Void = { _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = HUDResultTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: HUDResultLayout.fontSize)
        textView.textColor = .labelColor
        textView.textContainerInset = HUDResultLayout.textInset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text
        textView.setAccessibilityLabel(String(localized: "結果", bundle: .module))
        scrollView.documentView = textView
        onCreated(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scroll(.zero)
    }
}

/// 結果のパネルを1つだけ持つ。新しい結果は今のパネルの中身を置き換える
@MainActor
final class HUDResultPanelController {
    private let store = HUDResultStore()
    private var panel: HUDResultPanel?
    private var copiedResetTimer: Timer?
    /// テストではクリップボードに触れないように差し替える
    var writeToPasteboard: (String) -> Void = { text in
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        ShellClipboard.didWrite()
    }

    var isVisible: Bool { panel?.isVisible == true }
    var currentResult: ResultModel? { store.model }

    /// center を中心に出す。表示中なら位置はそのままで、上の辺をそろえて大きさだけ合わせる
    func show(_ result: ResultModel, centeredAt center: CGPoint, on screen: HUDScreenGeometry) {
        store.model = result
        store.didCopy = false
        let panel = self.panel ?? makePanel()
        let size = HUDResultLayout.panelSize(textHeight: HUDResultLayout.textHeight(of: result.text), screen: screen)
        let frame: CGRect
        if panel.isVisible {
            let current = panel.frame
            let resized = CGRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height)
            let visible = panel.screen?.visibleFrame ?? screen.visibleFrame
            frame = HUDPlacement.clamp(resized, into: visible)
        } else {
            frame = HUDPlacement.frame(size: size, centeredAt: center, in: screen)
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        HUDAccessibility.announce(HUDAccessibility.toastAnnouncement(title: result.title, detail: result.text))
    }

    func close() {
        copiedResetTimer?.invalidate()
        copiedResetTimer = nil
        panel?.orderOut(nil)
        store.model = nil
        store.didCopy = false
    }

    func copyAll() {
        guard let text = store.model?.text else { return }
        writeToPasteboard(text)
        store.didCopy = true
        copiedResetTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.didCopy = false }
        }
        copiedResetTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func makePanel() -> HUDResultPanel {
        let panel = HUDResultPanel()
        let view = HUDResultView(
            store: store,
            onCopy: { [weak self] in self?.copyAll() },
            onClose: { [weak self] in self?.close() },
            onTextViewCreated: { [weak panel] textView in panel?.textView = textView }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.onClose = { [weak self] in self?.close() }
        panel.onCopyAll = { [weak self] in self?.copyAll() }
        self.panel = panel
        return panel
    }
}

// 担当: ui-settings
// 打ち終わってから書き込む入力欄。入力のたびに保存しないよう、少し止まったとき・Return・欄を離れたときに確定する
import AppKit
import SwiftUI

/// 欄に出している文字と、まだ書き込んでいない打ちかけ。再描画をまたいで使い回す
@MainActor
@Observable
final class SettingsDraftBuffer {
    /// 欄に出している文字
    private(set) var draft: String
    /// 最新の描画で渡された書き込み先。待っている確定が古い描画の書き込み先を呼ばないよう、描画のたびに差し替える
    @ObservationIgnored var commit: (String) -> Void
    /// 確定していない打ちかけを、種類の切り替えなどの前にまとめて確定させる
    @ObservationIgnored weak var registry: SettingsPendingEdits?
    /// 設定に入っている値（最後に知らされたもの）
    @ObservationIgnored private(set) var value: String
    /// draft が最後に value と揃っていたとき（または確定したとき）の値。ここから変わっていれば打ちかけ
    @ObservationIgnored private var baseline: String
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let delay: Duration

    init(value: String, delay: Duration, commit: @escaping (String) -> Void = { _ in }) {
        draft = value
        self.value = value
        baseline = value
        self.delay = delay
        self.commit = commit
    }

    /// まだ確定していない打ちかけがある
    var hasPendingEdit: Bool { draft != baseline }

    /// 利用者が打ち込んだ。少し止まったら確定する
    func edit(_ text: String) {
        guard text != draft else { return }
        draft = text
        pending?.cancel()
        registry?.add(self)
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// 設定の値がほかで変わった。打ちかけでなければ欄も合わせる
    func valueChanged(_ newValue: String) {
        value = newValue
        if draft == baseline {
            draft = newValue
            baseline = newValue
        }
    }

    /// 待っている確定が終わるまで待つ（テスト用）
    func waitForPendingCommit() async {
        await pending?.value
    }

    /// 打ちかけを確定する
    func flush() {
        pending?.cancel()
        pending = nil
        registry?.remove(self)
        guard draft != baseline else { return }
        baseline = draft
        if draft != value {
            commit(draft)
        }
    }
}

/// 確定を待っている欄。種類の切り替え・タブの切り替え・ウィンドウを閉じる前に、まとめて確定させる
@MainActor
final class SettingsPendingEdits {
    private struct Entry {
        weak var buffer: SettingsDraftBuffer?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    var count: Int { entries.values.filter { $0.buffer != nil }.count }

    func add(_ buffer: SettingsDraftBuffer) {
        entries[ObjectIdentifier(buffer)] = Entry(buffer: buffer)
    }

    func remove(_ buffer: SettingsDraftBuffer) {
        entries[ObjectIdentifier(buffer)] = nil
    }

    func flushAll() {
        let buffers = entries.values.compactMap(\.buffer)
        entries.removeAll()
        for buffer in buffers {
            buffer.flush()
        }
    }
}

private struct SettingsPendingEditsKey: EnvironmentKey {
    static let defaultValue: SettingsPendingEdits? = nil
}

extension EnvironmentValues {
    var settingsPendingEdits: SettingsPendingEdits? {
        get { self[SettingsPendingEditsKey.self] }
        set { self[SettingsPendingEditsKey.self] = newValue }
    }
}

/// 打ち終わってから書き込む1行の欄
struct SettingsCommitTextField: View {
    let value: String
    let placeholder: String
    var monospaced = false
    var accessibilityLabel: String?
    /// 増えたらこの欄に移る（グリッドで Return を押したときの表示名の欄など）
    var focusRequest = 0
    let commit: (String) -> Void

    @State private var buffer: SettingsDraftBuffer
    @FocusState private var isFocused: Bool
    @Environment(\.settingsPendingEdits) private var pendingEdits

    init(
        value: String,
        placeholder: String,
        monospaced: Bool = false,
        accessibilityLabel: String? = nil,
        focusRequest: Int = 0,
        commit: @escaping (String) -> Void
    ) {
        self.value = value
        self.placeholder = placeholder
        self.monospaced = monospaced
        self.accessibilityLabel = accessibilityLabel
        self.focusRequest = focusRequest
        self.commit = commit
        _buffer = State(initialValue: SettingsDraftBuffer(value: value, delay: .milliseconds(450)))
    }

    var body: some View {
        let buffer = buffer
        // 描画のたびに最新の書き込み先へ差し替える（見ていない値なので、描き直しは起きない）
        buffer.commit = commit
        buffer.registry = pendingEdits
        return TextField(text: Binding(get: { buffer.draft }, set: { buffer.edit($0) }), prompt: Text(placeholder)) {
            Text(accessibilityLabel ?? placeholder)
        }
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .font(monospaced ? .system(.body, design: .monospaced) : .body)
        .focused($isFocused)
        .onSubmit { buffer.flush() }
        .onChange(of: isFocused) { if !isFocused { buffer.flush() } }
        .onChange(of: value) { _, newValue in buffer.valueChanged(newValue) }
        .onChange(of: focusRequest) { isFocused = true }
        .onDisappear { buffer.flush() }
    }
}

/// 打ち終わってから書き込む複数行の欄。code ならスクリプト用（等幅で、スマート引用符などの置き換えをしない）。
/// どちらも NSTextView を直接使い、打ち込みの取り消しは欄の中だけで効くようにする（SettingsCodeTextView）
struct SettingsCommitTextEditor: View {
    let value: String
    var code = false
    var minHeight: CGFloat = 100
    let accessibilityLabel: String
    let commit: (String) -> Void

    @State private var buffer: SettingsDraftBuffer
    @State private var isFocused = false
    @Environment(\.settingsPendingEdits) private var pendingEdits

    init(value: String, code: Bool = false, minHeight: CGFloat = 100, accessibilityLabel: String, commit: @escaping (String) -> Void) {
        self.value = value
        self.code = code
        self.minHeight = minHeight
        self.accessibilityLabel = accessibilityLabel
        self.commit = commit
        _buffer = State(initialValue: SettingsDraftBuffer(value: value, delay: .milliseconds(600)))
    }

    var body: some View {
        let buffer = buffer
        buffer.commit = commit
        buffer.registry = pendingEdits
        return editor
            .frame(minHeight: minHeight)
            .background(RoundedRectangle(cornerRadius: SettingsMetrics.smallRadius).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.smallRadius)
                    .strokeBorder(isFocused ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor), lineWidth: isFocused ? 2 : 1)
            )
            .onChange(of: value) { _, newValue in buffer.valueChanged(newValue) }
            .onDisappear { buffer.flush() }
    }

    private var editor: some View {
        SettingsCodeTextView(
            text: buffer.draft,
            code: code,
            accessibilityLabel: accessibilityLabel,
            edit: { [buffer] in buffer.edit($0) },
            endEditing: { [buffer] in buffer.flush() },
            focusChanged: { isFocused = $0 }
        )
        .padding(code ? 1 : 4)
    }
}

/// 複数行の欄。SwiftUI の TextEditor は macOS の「スマート引用符」「スマートダッシュ」「ユーザ辞書の置き換え」を
/// 止められず、打った " が “ に、-- が — に変わって zsh で動かなくなるため、NSTextView を直接使う（code が false の指示文などは置き換えを残す）。
/// 打ち込みの取り消しはこの欄だけの undoManager に積み、欄を離れたら捨てる。欄で変えた中身は、離れたときに
/// 設定の取り消し（SettingsModel のマスごとのまとまり）に1つで積む。窓の undoManager に打ち込みを積むと、
/// マスの中身を元に戻した後に、合わなくなった打ち込みの取り消しが残る
struct SettingsCodeTextView: NSViewRepresentable {
    let text: String
    var code = true
    let accessibilityLabel: String
    let edit: (String) -> Void
    let endEditing: () -> Void
    let focusChanged: (Bool) -> Void

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SettingsCodeTextView
        /// この欄の打ち込みだけの取り消し
        let typingUndoManager = UndoManager()

        init(parent: SettingsCodeTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // 日本語の変換中は確定してから受け取る
            guard !textView.hasMarkedText() else { return }
            parent.edit(textView.string)
        }

        func textDidEndEditing(_ notification: Notification) {
            typingUndoManager.removeAllActions()
            parent.endEditing()
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            typingUndoManager
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SettingsCodeNSTextView(frame: .zero)
        if code {
            Self.configureForCode(textView)
        } else {
            Self.configureForProse(textView)
        }
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.drawsBackground = false
        textView.string = text
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.onFocusChange = { [weak coordinator = context.coordinator] focused in
            // ビューの更新中に呼ばれることがあるので、状態は後で変える
            Task { @MainActor in coordinator?.parent.focusChanged(focused) }
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // ほかで値が変わったときだけ入れ替える（打っている最中に入れ替えるとカーソルが飛ぶ）
        if textView.string != text, !textView.hasMarkedText() {
            let selection = textView.selectedRanges
            // 入れ替えた後の文字に、前の打ち込みの取り消しは合わない
            context.coordinator.typingUndoManager.removeAllActions()
            textView.string = text
            let length = (text as NSString).length
            textView.selectedRanges = selection.map { value in
                let range = value.rangeValue
                let location = min(range.location, length)
                return NSValue(range: NSRange(location: location, length: min(range.length, length - location)))
            }
        }
        if textView.accessibilityLabel() != accessibilityLabel {
            textView.setAccessibilityLabel(accessibilityLabel)
        }
    }

    /// 打った文字をそのまま残す（コードでは引用符・ダッシュ・綴りの自動修正がどれも壊す）
    static func configureForCode(_ textView: NSTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .textColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
    }

    /// 指示文など、ふつうの文の欄（置き換えや綴りの確かめは、利用者の設定のまま）
    static func configureForProse(_ textView: NSTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .textColor
    }
}

/// フォーカスの出入りを知らせる NSTextView（枠の色を変えるため）
final class SettingsCodeNSTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            onFocusChange?(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            onFocusChange?(false)
        }
        return accepted
    }
}

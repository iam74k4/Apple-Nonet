// 担当: ui-settings
// 設定画面で使い回す部品（色・確定してから書き込む入力欄・帯）
import AppKit
import NonetCore
import SwiftUI

/// モックに合わせた白黒の色。ダークモードでも同じ明暗の関係にする
enum SettingsPalette {
    static let gridBackground = dynamic(light: 0.957, dark: 0.165)
    static let cellBackground = dynamic(light: 1.0, dark: 0.235)
    static let cellBorder = dynamic(light: 0.878, dark: 0.33)
    static let emptyBorder = dynamic(light: 0.72, dark: 0.45)
    static let panelBorder = dynamic(light: 0.898, dark: 0.26)

    private static func dynamic(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: isDark ? dark : light, alpha: 1)
        })
    }
}

/// 打ち終わってから書き込む1行の欄。入力のたびに保存しないよう、少し止まったとき・Return・欄を離れたときに確定する
struct SettingsCommitTextField: View {
    let value: String
    let placeholder: String
    var monospaced = false
    var accessibilityLabel: String?
    let commit: (String) -> Void

    @State private var draft: String
    /// draft が最後に value と揃っていたときの値。ここから変わっていれば利用者が打ち込んだ
    @State private var baseline: String
    @State private var pending: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    init(value: String, placeholder: String, monospaced: Bool = false, accessibilityLabel: String? = nil, commit: @escaping (String) -> Void) {
        self.value = value
        self.placeholder = placeholder
        self.monospaced = monospaced
        self.accessibilityLabel = accessibilityLabel
        self.commit = commit
        _draft = State(initialValue: value)
        _baseline = State(initialValue: value)
    }

    var body: some View {
        TextField(text: $draft, prompt: Text(placeholder)) {
            Text(accessibilityLabel ?? placeholder)
        }
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .font(monospaced ? .system(.body, design: .monospaced) : .body)
        .focused($isFocused)
        .onChange(of: draft) { schedule() }
        .onSubmit { flush() }
        .onChange(of: isFocused) { if !isFocused { flush() } }
        .onChange(of: value) { syncFromValue() }
        .onDisappear { flush() }
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    private func flush() {
        pending?.cancel()
        pending = nil
        guard draft != baseline else { return }
        baseline = draft
        if draft != value {
            commit(draft)
        }
    }

    private func syncFromValue() {
        // 打ちかけでなければ、ほかで変わった値に合わせる
        if draft == baseline {
            draft = value
            baseline = value
        }
    }
}

/// 打ち終わってから書き込む複数行の欄（スクリプト・指示文）
struct SettingsCommitTextEditor: View {
    let value: String
    var monospaced = false
    var minHeight: CGFloat = 100
    let accessibilityLabel: String
    let commit: (String) -> Void

    @State private var draft: String
    @State private var baseline: String
    @State private var pending: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    init(value: String, monospaced: Bool = false, minHeight: CGFloat = 100, accessibilityLabel: String, commit: @escaping (String) -> Void) {
        self.value = value
        self.monospaced = monospaced
        self.minHeight = minHeight
        self.accessibilityLabel = accessibilityLabel
        self.commit = commit
        _draft = State(initialValue: value)
        _baseline = State(initialValue: value)
    }

    var body: some View {
        TextEditor(text: $draft)
            .font(monospaced ? .system(size: 12, design: .monospaced) : .body)
            .autocorrectionDisabled(monospaced)
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(minHeight: minHeight)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isFocused ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor), lineWidth: isFocused ? 2 : 1)
            )
            .focused($isFocused)
            .accessibilityLabel(accessibilityLabel)
            .onChange(of: draft) { schedule() }
            .onChange(of: isFocused) { if !isFocused { flush() } }
            .onChange(of: value) {
                if draft == baseline {
                    draft = value
                    baseline = value
                }
            }
            .onDisappear { flush() }
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    private func flush() {
        pending?.cancel()
        pending = nil
        guard draft != baseline else { return }
        baseline = draft
        if draft != value {
            commit(draft)
        }
    }
}

/// インスペクタの見出し付きの欄
struct SettingsField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 小さな注意書き
struct SettingsNote: View {
    let text: String
    var symbol: String?
    var isWarning = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(isWarning ? Color.orange : Color.secondary)
                    .accessibilityHidden(true)
            }
            Text(text)
                .foregroundStyle(isWarning ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 画面上部の帯（知らせ・権限など）
struct SettingsBanner<Buttons: View>: View {
    let symbol: String
    let title: String
    let message: String?
    var isWarning = true
    var onClose: (() -> Void)?
    @ViewBuilder var buttons: Buttons

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(isWarning ? Color.orange : Color.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            buttons
                .controlSize(.small)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help(String(localized: "閉じる", bundle: .module))
                .accessibilityLabel(String(localized: "閉じる", bundle: .module))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }
}

/// ヘルプの「?」ボタン。押すと吹き出しで説明を出す
struct SettingsHelpButton<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
        .popover(isPresented: $isShown, arrowEdge: .trailing) {
            content
                .padding(16)
                .frame(width: 380)
        }
    }
}

// 担当: ui-settings
// プロファイルを読み込む前の確認。何かを実行するマス（スクリプト・キー入力・メニュー項目・AI・ファイルを開く URL）の中身を
// 切らずにすべて見せ、最後までスクロールして見るまで「読み込む」を押せないようにする
import NonetCore
import SwiftUI

/// 読み込む前に見せる、1つのマスの中身
struct SettingsImportReviewEntry: Identifiable, Equatable {
    enum Style: Equatable {
        /// 種類や設定の説明（「スクリプト（3行）:」「結果: 画面に表示」）
        case label
        /// ファイルの中身そのもの（スクリプトの行・AI への指示）。terms は含まれていた注意が要る命令（SettingsImportPlan.suspiciousTerms）
        case code(terms: [String])
        /// 目立たせる注意（Return を押す・注意が要る命令）
        case warning
    }

    struct Line: Identifiable, Equatable {
        let id: Int
        var text: String
        var style: Style
    }

    let id: Int
    /// プロファイルの名前（1行にして長ければ切る）
    var profileName: String
    /// マスの表示名（1行にして長ければ切る）
    var title: String
    var lines: [Line]

    /// 注意が要る行か、目立たせる注意がある
    var isFlagged: Bool {
        lines.contains { line in
            switch line.style {
            case .label: false
            case .code(let terms): !terms.isEmpty
            case .warning: true
            }
        }
    }

    /// 文にしたもの（SettingsText.importConfirmation）。注意が要る行の後には、その命令を「⚠」で添える
    var textLines: [String] {
        var result = [String(localized: "・\(profileName) › \(title)", bundle: .module)]
        for line in lines {
            switch line.style {
            case .label:
                result.append(line.text)
            case .code(let terms):
                result.append(line.text)
                if !terms.isEmpty {
                    result.append("⚠ " + SettingsText.suspiciousNote(terms))
                }
            case .warning:
                result.append("⚠ " + line.text)
            }
        }
        return result
    }
}

extension SettingsText {
    /// 中身を見せるマスの前に出す説明
    static var importReviewIntro: String {
        String(localized: "次のマスは、あなたの権限でスクリプトを実行したり、キーを入力したり、メニューを選んだり、選択したテキストを AI に渡したり、ファイルを開いたり、Finder で選んだファイルを動かしたりします。中身をすべて確かめ、信頼できるファイルだけを読み込んでください。", bundle: .module)
    }

    /// 最後までスクロールしていないときの案内
    static var importReviewScrollHint: String {
        String(localized: "最後までスクロールして中身をすべて確かめると、読み込めます", bundle: .module)
    }

    /// Return と同じ働きのキーや ⌃ の付いたキーを押すマスの注意
    static var importSubmitKeyWarning: String {
        String(localized: "Return と同じ働きのキー（または ⌃ の付いたキー）を押します。コマンドの実行やメッセージの送信になることがあります。", bundle: .module)
    }

    /// 注意が要る命令を含む行の注意
    static func suspiciousNote(_ terms: [String]) -> String {
        let list = terms.joined(separator: ", ")
        return String(localized: "注意が要る命令（\(list)）を含みます。ネットワークから取ってきたものを実行したり、ファイルを消したりできます。", bundle: .module)
    }

    /// 読み込まれるマスのうち、中身を見せるものすべて（数に上限は無い。中身も切らない）
    static func importReviewEntries(_ plan: SettingsImportPlan) -> [SettingsImportReviewEntry] {
        plan.reviewedCells.enumerated().map { index, reviewed in
            SettingsImportReviewEntry(
                id: index,
                profileName: singleLine(reviewed.profileName, limit: importNameLimit),
                title: singleLine(SettingsGrid.displayTitle(for: reviewed.cell), limit: importNameLimit),
                lines: reviewLines(for: reviewed).enumerated().map { SettingsImportReviewEntry.Line(id: $0.offset, text: $0.element.text, style: $0.element.style) }
            )
        }
    }

    /// マスの中身。スクリプトは全部の行、キー入力は押すキーのすべて、メニュー項目はパスとショートカット、AI は指示と結果の出し方、
    /// URL は開くファイル、ファイルの操作はその操作。ファイルから来た文は、見えない文字を「⟨U+202E⟩」のように見える形にする（visibleLine）
    static func reviewLines(for reviewed: SettingsImportPlan.ReviewedCell) -> [(text: String, style: SettingsImportReviewEntry.Style)] {
        var lines: [(text: String, style: SettingsImportReviewEntry.Style)] = []
        switch reviewed.cell.action {
        case .script(let script):
            let source = sourceLines(script.source)
            lines.append((String(localized: "スクリプト（\(source.count)行）:", bundle: .module, locale: .nonetUI), .label))
            lines += source.map { ($0, .code(terms: SettingsImportPlan.suspiciousTerms(in: $0))) }
        case .keystroke(let keys):
            let preview = visibleLine(keysPreview(keys))
            lines.append((String(localized: "キー入力: \(preview)", bundle: .module), .label))
            let terms = SettingsImportPlan.suspiciousTerms(in: preview)
            if !terms.isEmpty {
                lines.append((suspiciousNote(terms), .warning))
            }
        case .menuItem(let menu):
            let app = menu.app.map { visibleLine($0.name.isEmpty ? $0.bundleID : $0.name) }
                ?? String(localized: "前面のアプリ", bundle: .module)
            let path = menu.path.map(visibleLine).joined(separator: " › ")
            lines.append((String(localized: "メニュー項目: \(app) › \(path)", bundle: .module), .label))
            if let shortcut = menu.keyEquivalent, !shortcut.chords.isEmpty {
                lines.append((String(localized: "ショートカット: \(visibleLine(keysPreview(shortcut)))", bundle: .module), .label))
                lines.append((String(localized: "ショートカットは、アプリのメニューにあるこの項目のショートカットと同じときだけ送ります。違うときはメニューを押します。", bundle: .module), .label))
            }
        case .ai(let ai):
            lines.append((String(localized: "AI への指示:", bundle: .module), .label))
            lines += sourceLines(ai.prompt).map { ($0, .code(terms: [])) }
            lines.append((String(localized: "結果: \(name(ai.output))", bundle: .module), .label))
        case .openURL(let url):
            lines.append((String(localized: "開くファイル: \(visibleLine(url.url.trimmingCharacters(in: .whitespacesAndNewlines)))", bundle: .module), .label))
        case .file(let file):
            lines.append((String(localized: "Finder で選んだファイルを: \(file.operation.title)", bundle: .module), .label))
        case .launchApp, .shortcut:
            break
        }
        if reviewed.pressesSubmitKey {
            lines.append((importSubmitKeyWarning, .warning))
        }
        return lines
    }

    /// 行に分けた文（改行の種類は問わない）。最後の改行の後の空の行は数えない。各行は visibleLine で見える形にする
    static func sourceLines(_ text: String) -> [String] {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { visibleLine(String($0)) }
        while lines.count > 1, lines.last?.isEmpty == true {
            lines.removeLast()
        }
        if lines == [""] {
            return []
        }
        return lines
    }

    /// ファイルから来た1行を、切らずに見える形にする。タブは空白4つ、ほかの見えない文字（制御文字・文字の向きを変える書式文字など）は
    /// 「⟨U+202E⟩」にする（確かめる画面で、見えない文字で中身を隠したり並びを入れ替えたりできないように）
    static func visibleLine(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if scalar == "\t" {
                result += "    "
            } else if isHidden(scalar) {
                result += String(format: "⟨U+%04X⟩", scalar.value)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}

/// 読み込む前の確認のシート。置き換わるもの、何かを実行するマスの中身（スクロールできる、読むだけの等幅の欄）、ボタン。
/// 中身を見せるマスがあれば、欄を最後までスクロールするまで「読み込む」「新しいプロファイルだけ追加」を押せない
struct SettingsImportReviewSheet: View {
    let model: SettingsModel
    let plan: SettingsImportPlan

    private static let scrollSpace = "importReview"

    /// 欄の最後の印の下端（欄の上端から）が、欄の高さの中に入った
    static func hasReachedEnd(markerMaxY: CGFloat, viewportHeight: CGFloat) -> Bool {
        viewportHeight > 0 && markerMaxY <= viewportHeight + 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "「\(plan.fileName)」を読み込みますか？", bundle: .module))
                .font(.headline)
            let replacement = SettingsText.importReplacementLines(plan)
            if !replacement.isEmpty {
                Text(replacement.joined(separator: "\n"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if plan.hasReviewedCells {
                Text(SettingsText.importReviewIntro)
                    .fixedSize(horizontal: false, vertical: true)
                reviewList
                if !model.importReviewReachedEnd {
                    Label(SettingsText.importReviewScrollHint, systemImage: "arrow.down.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            buttons
        }
        .padding(20)
        .frame(width: 640)
    }

    private var reviewList: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SettingsText.importReviewEntries(plan)) { entry in
                        entryView(entry)
                    }
                    // 最後まで見たかを知るための印
                    Color.clear
                        .frame(height: 1)
                        .background(GeometryReader { marker in
                            Color.clear.preference(key: SettingsImportReviewEndKey.self, value: marker.frame(in: .named(Self.scrollSpace)).maxY)
                        })
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .coordinateSpace(name: Self.scrollSpace)
            .onPreferenceChange(SettingsImportReviewEndKey.self) { maxY in
                let height = viewport.size.height
                MainActor.assumeIsolated {
                    if Self.hasReachedEnd(markerMaxY: maxY, viewportHeight: height) {
                        model.markImportReviewRead()
                    }
                }
            }
        }
        .frame(minHeight: 220, idealHeight: 380, maxHeight: 460)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }

    private func entryView(_ entry: SettingsImportReviewEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(verbatim: "\(entry.profileName) › \(entry.title)")
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: entry.isFlagged ? "exclamationmark.triangle.fill" : "square.grid.3x3")
                    .foregroundStyle(entry.isFlagged ? Color.orange : Color.secondary)
            }
            ForEach(entry.lines) { line in
                lineView(line)
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: SettingsImportReviewEntry.Line) -> some View {
        switch line.style {
        case .label:
            Text(verbatim: line.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .code(let terms):
            VStack(alignment: .leading, spacing: 2) {
                // 空の行も1行分の高さで出す
                Text(verbatim: line.text.isEmpty ? " " : line.text)
                    .font(.system(.body, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if !terms.isEmpty {
                    Label(SettingsText.suspiciousNote(terms), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(terms.isEmpty ? Color.clear : Color.orange.opacity(0.15))
        case .warning:
            Label(line.text, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button(role: .cancel) {
                model.confirmation = nil
            } label: {
                Text("キャンセル", bundle: .module)
            }
            .keyboardShortcut(.cancelAction)
            if plan.replacesExisting, plan.addsProfiles {
                Button {
                    model.importNewProfilesOnly(plan)
                } label: {
                    Text("新しいプロファイルだけ追加", bundle: .module)
                }
                .disabled(!model.canConfirmImport(plan))
            }
            Button(role: plan.replacesExisting ? .destructive : nil) {
                model.confirm(.importProfiles(plan))
            } label: {
                Text(SettingsText.importConfirmationButton(plan))
            }
            .disabled(!model.canConfirmImport(plan))
        }
    }
}

/// 確認の欄の最後の印の下端
private struct SettingsImportReviewEndKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

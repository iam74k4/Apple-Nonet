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

    /// 文字を打ち、それを消す・動かす・補完するキーも押すマスの注意
    static var importEditKeyWarning: String {
        String(localized: "打った文字を消す・打つ場所を動かす・補完するキー（⌫・矢印・Tab・Esc など）も押します。実際に入る文字はアプリによって変わり、ここに出ている文字のとおりとは限りません。", bundle: .module)
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
    /// URL は開くファイル、ファイルの操作はその操作、ショートカット.app のショートカットはその名前と選択中のテキストを渡すか。ファイルから来た文は、見えない文字を「⟨U+202E⟩」のように見える形にする（visibleLine）
    static func reviewLines(for reviewed: SettingsImportPlan.ReviewedCell) -> [(text: String, style: SettingsImportReviewEntry.Style)] {
        var lines: [(text: String, style: SettingsImportReviewEntry.Style)] = []
        // アプリのプロファイルのマスは、ファイルの中の名前だけでなく、本当に動くアプリ（bundle ID）を見せる。
        // この Mac にあるそのアプリの名前とファイルの名前が違えば目立たせる（別のアプリの名前を付けて、危ないキーを読み違えさせない）
        if let app = reviewed.app {
            lines.append((String(localized: "アプリ: \(visibleLine(app.bundleID))", bundle: .module), .label))
            let names = reviewed.installedAppNames
            if let installed = names.first,
               !names.contains(where: { $0.compare(app.name, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame }) {
                lines.append((String(localized: "このファイルでの名前は「\(visibleLine(app.name))」ですが、この Mac ではそのアプリは「\(installed)」です。", bundle: .module), .warning))
            }
        }
        switch reviewed.cell.action {
        case .script(let script):
            let source = sourceLines(script.source)
            lines.append((String(localized: "スクリプト（\(source.count)行）:", bundle: .module, locale: .nonetUI), .label))
            lines += source.map { ($0, .code(terms: SettingsImportPlan.suspiciousTerms(in: $0))) }
        case .keystroke(let keys):
            let preview = visibleLine(keysPreview(keys))
            lines.append((String(localized: "キー入力: \(preview)", bundle: .module), .label))
            // キーコードで書いたキーが打つ文字（表記からは分からない）も見せて、注意が要る命令を探す
            let typed = reviewed.keyCodeText.map(visibleLine)
            if let typed {
                lines.append((String(localized: "打つ文字（キーコードも文字にしたもの）: 「\(typed)」", bundle: .module), .code(terms: SettingsImportPlan.suspiciousTerms(in: typed))))
            }
            var terms = SettingsImportPlan.suspiciousTerms(in: preview + (typed.map { " " + $0 } ?? ""))
            // 打ち方の決まりを変えて打ったもの（Home・End・⌥⌫ の働きが違うアプリ・消すキーを効かせない）にあっても知らせる
            for text in reviewed.typedTexts.map(visibleLine) {
                for term in SettingsImportPlan.suspiciousTerms(in: text) where !terms.contains(term) {
                    terms.append(term)
                }
            }
            if !terms.isEmpty {
                lines.append((suspiciousNote(terms), .warning))
            }
            if reviewed.editsTypedText {
                lines.append((importEditKeyWarning, .warning))
            }
        case .menuItem(let menu):
            let app = menu.app.map { $0.name.isEmpty ? visibleLine($0.bundleID) : "\(visibleLine($0.name))（\(visibleLine($0.bundleID))）" }
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
            let target = visibleLine(url.url.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append(SettingsImportPlan.opensLocalFile(url.url)
                ? (String(localized: "開くファイル: \(target)", bundle: .module), .label)
                : (String(localized: "開くリンク: \(target)", bundle: .module), .label))
        case .file(let file):
            lines.append((String(localized: "Finder で選んだファイルを: \(file.operation.title)", bundle: .module), .label))
        case .shortcut(let shortcut):
            lines.append((String(localized: "実行するショートカット: \(visibleLine(shortcut.name))", bundle: .module), .label))
            if shortcut.passSelectedText {
                lines.append((String(localized: "選択中のテキストをショートカットに渡します", bundle: .module), .label))
            }
        case .pasteText(let paste):
            lines.append((String(localized: "貼るテキスト:", bundle: .module), .label))
            lines += sourceLines(paste.text).map { ($0, .code(terms: [])) }
        case .launchApp, .placeWindow, .screenshots, .media:
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
        let scalars = Array(text.unicodeScalars)
        let flagTags = flagTagIndices(scalars)
        for (index, scalar) in scalars.enumerated() {
            let previous = index > 0 ? scalars[index - 1] : nil
            // 正しい地域の旗の絵文字（🏴 ＋ タグ文字 1〜6 個 ＋ 終わりのタグ）のタグ文字だけは、見える形にしない
            let inFlagTags = flagTags.contains(index)
            if scalar == "\t" {
                result += "    "
            } else if isHidden(scalar) && !inFlagTags || isInvisibleInReview(scalar, after: previous, inFlagTags: inFlagTags) {
                result += String(format: "⟨U+%04X⟩", scalar.value)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// 地域の旗の絵文字（🏴 ＋ 数字か小文字のタグ文字 1〜6 個 ＋ 終わりのタグ U+E007F）の、タグ文字の位置。
    /// それ以外のタグ文字（🏴 の後に続けて長い文を隠したもの・終わりの無いもの）は含めない
    static func flagTagIndices(_ scalars: [Unicode.Scalar]) -> Set<Int> {
        var result = Set<Int>()
        var index = 0
        while index < scalars.count {
            guard scalars[index].value == 0x1F3F4 else { index += 1; continue }
            var end = index + 1
            while end < scalars.count, end - index - 1 < 6,
                  (0xE0030...0xE0039).contains(scalars[end].value) || (0xE0061...0xE007A).contains(scalars[end].value) {
                end += 1
            }
            if end > index + 1, end < scalars.count, scalars[end].value == 0xE007F {
                result.formUnion((index + 1)...end)
                index = end + 1
            } else {
                index += 1
            }
        }
        return result
    }

    /// 書式文字のほかに、見えない文字（Default_Ignorable: 異体字セレクタ・ハングルの埋め字など）。
    /// 絵文字をつなぐ ZWJ・ZWNJ、絵文字の直後の異体字セレクタ（️）、旗の絵文字のタグ文字は残す
    static func isInvisibleInReview(_ scalar: Unicode.Scalar, after previous: Unicode.Scalar?, inFlagTags: Bool) -> Bool {
        guard scalar.properties.isDefaultIgnorableCodePoint else { return false }
        switch scalar.value {
        case 0x200C, 0x200D:
            return false
        case 0xFE0E, 0xFE0F:
            return !(previous?.properties.isEmoji ?? false)
        case 0xE0020...0xE007F:
            return !inFlagTags
        default:
            return true
        }
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
        .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.smallRadius))
        .overlay(RoundedRectangle(cornerRadius: SettingsMetrics.smallRadius).strokeBorder(Color(nsColor: .separatorColor)))
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
                    SettingsImportWarning(text: SettingsText.suspiciousNote(terms), font: .system(size: 11))
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(terms.isEmpty ? Color.clear : Color.orange.opacity(0.15))
        case .warning:
            SettingsImportWarning(text: line.text, font: .callout)
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

/// 確認の欄の注意（危ないかもしれない中身・読み込めない部分）。橙は記号だけにして、文字はふつうの色で読めるようにする
private struct SettingsImportWarning: View {
    let text: String
    let font: Font

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(font)
        .accessibilityElement(children: .combine)
    }
}

/// 確認の欄の最後の印の下端
private struct SettingsImportReviewEndKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

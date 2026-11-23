// 担当: ui-settings
// アクションの種類ごとの編集欄
import AppKit
import NonetCore
import SwiftUI

// MARK: - キー入力

struct SettingsKeystrokeEditor: View {
    let model: SettingsModel
    let cellID: UUID
    let keys: KeySequence
    @State private var notation = ""
    @State private var notationMessage: String?

    private var isRecording: Bool { model.recordingCellID == cellID && model.recorder.isRecording }

    var body: some View {
        SettingsField(title: String(localized: "送るキー", bundle: .module)) {
            VStack(alignment: .leading, spacing: 8) {
                recorderField
                if isRecording {
                    HStack(spacing: 8) {
                        // Return もキーとして記録するので、既定のボタン（Return で押せる見た目）にはしない
                        Button {
                            model.finishRecording()
                        } label: {
                            Text("完了", bundle: .module)
                        }
                        Button {
                            model.appendEscapeToRecording()
                        } label: {
                            Text("Esc を加える", bundle: .module)
                        }
                        .help(String(localized: "Esc キーを打鍵として加えます（Esc を押すと記録をやめるため）", bundle: .module))
                        Button {
                            model.removeLastRecordedChord()
                        } label: {
                            Image(systemName: "delete.left")
                        }
                        .disabled(model.recorder.chords.isEmpty)
                        .help(String(localized: "最後のキーを消す", bundle: .module))
                        .accessibilityLabel(String(localized: "最後のキーを消す", bundle: .module))
                        Spacer()
                        Button {
                            model.cancelRecording()
                        } label: {
                            Text("やめる", bundle: .module)
                        }
                    }
                    .controlSize(.small)
                    Text("続けて押すと連続キーになります（4つまで）。Return や Tab もそのまま記録します。「完了」か、ほかの場所をクリックすると決まります。Esc で記録をやめます。", bundle: .module)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // 記録はこのアプリに届いたキーだけを見る。スクリーンショットなどのキーは macOS が先に使うので届かない
                    Text("スクリーンショットの ⇧⌘4 など、macOS が先に使うキーは記録できません。「やめる」を押して、表記の欄に入力してください。", bundle: .module)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 6) {
                        // 等幅にすると案内（プロンプト）まで等幅になり、狭いインスペクタで切れる
                        TextField(text: $notation, prompt: Text("表記で入力", bundle: .module)) {
                            Text("キーの表記", bundle: .module)
                        }
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(applyNotation)
                        Button(action: applyNotation) {
                            Text("決定", bundle: .module)
                        }
                        .disabled(notation.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("例: ⌘L → ⌘C。スクリーンショットの ⇧⌘4 など、macOS が先に使うキーは記録できないので、ここに入力します。", bundle: .module)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let notationMessage {
                        SettingsNote(text: notationMessage, symbol: "exclamationmark.triangle", isWarning: true)
                    }
                }
            }
            .background(SettingsRecorderAreaReader(model: model))
        }
    }

    private var recorderField: some View {
        Button {
            if isRecording {
                model.finishRecording()
            } else {
                notationMessage = nil
                model.beginRecording(cellID: cellID)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isRecording ? "record.circle" : "keyboard")
                    .foregroundStyle(isRecording ? Color.red : Color.secondary)
                    .accessibilityHidden(true)
                Text(fieldText)
                    .font(.system(size: 15, weight: .medium, design: fieldTextIsPlaceholder ? .default : .monospaced))
                    .foregroundStyle(fieldTextIsPlaceholder ? Color.secondary : Color.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if !isRecording {
                    Text("記録", bundle: .module)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SettingsMetrics.mediumRadius).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.mediumRadius)
                    .strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isRecording ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "送るキー", bundle: .module))
        .accessibilityValue(fieldText)
        .accessibilityHint(isRecording
            ? String(localized: "記録中です。キーを押してください。", bundle: .module)
            : String(localized: "押すとキーの記録を始めます", bundle: .module))
    }

    private var fieldText: String {
        if isRecording {
            return model.recorder.progressText ?? String(localized: "キーを押してください…", bundle: .module)
        }
        return keys.chords.isEmpty ? String(localized: "クリックして記録", bundle: .module) : keys.displayString
    }

    private var fieldTextIsPlaceholder: Bool {
        isRecording ? model.recorder.progressText == nil : keys.chords.isEmpty
    }

    private func applyNotation() {
        let input = SettingsKeyNotationInput(notation)
        if case .valid(let sequence) = input {
            model.updateAction(ofCell: cellID, as: KeySequence.self) { $0 = sequence }
            notation = ""
            notationMessage = nil
        } else {
            notationMessage = input.message
        }
    }
}

/// 記録欄とそのボタンの場所を SettingsModel に知らせる。記録中にこの外をクリックしたら記録を終える
struct SettingsRecorderAreaReader: NSViewRepresentable {
    let model: SettingsModel

    /// 場所を知らせるだけで、クリックは受け取らない
    final class AreaView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> AreaView {
        let view = AreaView()
        model.recorderArea = view
        return view
    }

    func updateNSView(_ view: AreaView, context: Context) {
        if model.recorderArea !== view {
            model.recorderArea = view
        }
    }
}

// MARK: - 開く（アプリか URL）

/// 「開く」の編集欄。アプリ（launchApp）と URL（openURL）は、設定の画面では1つの種類に見せ、ここで切り替える
struct SettingsOpenEditor: View {
    let model: SettingsModel
    let cell: Cell

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(selection: Binding(get: { cell.action.kind }, set: { model.changeKind(ofCell: cell.id, to: $0) })) {
                Text("アプリ", bundle: .module).tag(ActionKind.launchApp)
                Text("URL", bundle: .module).tag(ActionKind.openURL)
            } label: {
                Text("開くもの", bundle: .module)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            switch cell.action {
            case .launchApp(let launch):
                SettingsLaunchAppEditor(model: model, cellID: cell.id, launch: launch)
            case .openURL(let url):
                SettingsURLEditor(model: model, cellID: cell.id, url: url)
            default:
                EmptyView()
            }
        }
    }
}

struct SettingsLaunchAppEditor: View {
    let model: SettingsModel
    let cellID: UUID
    let launch: LaunchAppAction
    @State private var isPicking = false
    @State private var pickError: String?

    var body: some View {
        SettingsField(title: String(localized: "開くアプリ", bundle: .module)) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    model.reloadInstalledApps()
                    isPicking = true
                } label: {
                    HStack(spacing: 8) {
                        if launch.app.bundleID.isEmpty {
                            Image(systemName: "app.dashed")
                            Text("アプリを選ぶ…", bundle: .module)
                        } else {
                            CellIconView(.app(bundleID: launch.app.bundleID), size: 14)
                            Text(launch.app.name.isEmpty ? launch.app.bundleID : launch.app.name)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .popover(isPresented: $isPicking, arrowEdge: .leading) {
                    SettingsAppPickerPopover(model: model, current: launch.app.bundleID) { app in
                        model.chooseApp(app, forCell: cellID)
                        isPicking = false
                    }
                }
                Button {
                    Task {
                        guard let url = await model.files?.chooseApplication() else { return }
                        if let app = SettingsAppCatalog.appReference(forBundleAt: url) {
                            model.chooseApp(app, forCell: cellID)
                            pickError = nil
                        } else {
                            pickError = String(localized: "このアプリは選べません（bundle ID がありません）", bundle: .module)
                        }
                    }
                } label: {
                    Text("一覧にないアプリを選ぶ…", bundle: .module)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
                if let pickError {
                    SettingsNote(text: pickError, symbol: "exclamationmark.triangle", isWarning: true)
                }
                Toggle(isOn: Binding(
                    get: { launch.hideIfFrontmost },
                    set: { hide in model.updateAction(ofCell: cellID, as: LaunchAppAction.self) { $0.hideIfFrontmost = hide } }
                )) {
                    Text("前面のときは隠す", bundle: .module)
                    Text("もう一度押すと隠れるので、アプリの切り替えのように使えます", bundle: .module)
                }
                .toggleStyle(.checkbox)
            }
        }
    }
}

/// インストール済みアプリから1つ選ぶ（アプリを開くマス）
struct SettingsAppPickerPopover: View {
    let model: SettingsModel
    let current: String
    let choose: (AppReference) -> Void
    @State private var query = ""
    @State private var selection: String?

    var body: some View {
        let entries = SettingsAppCatalog.entries(apps: model.installedApps, query: query, existingBundleIDs: [], presetsFirst: false)
        VStack(alignment: .leading, spacing: 8) {
            TextField(text: $query, prompt: Text("アプリを検索", bundle: .module)) {
                Text("アプリを検索", bundle: .module)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            SettingsAppList(entries: entries, selection: $selection, showsBadges: false) { entry in
                choose(entry.app)
            }
            .frame(height: 300)
            HStack {
                Text("ダブルクリックで選びます", bundle: .module)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if let entry = entries.first(where: { $0.id == selection }) {
                        choose(entry.app)
                    }
                } label: {
                    Text("選ぶ", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { selection = current.isEmpty ? nil : current.lowercased() }
    }
}

/// アプリの一覧（アイコン・名前・プリセットの有無）
struct SettingsAppList: View {
    let entries: [SettingsAppEntry]
    @Binding var selection: String?
    var showsBadges = true
    let choose: (SettingsAppEntry) -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    CellIconView(.app(bundleID: entry.app.bundleID), size: 16)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.app.name.isEmpty ? entry.app.bundleID : entry.app.name)
                            .lineLimit(1)
                        Text(entry.app.bundleID)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    if showsBadges, entry.hasProfile {
                        Text("追加済み", bundle: .module)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if showsBadges, entry.hasPreset {
                        Text("プリセットあり", bundle: .module)
                            .font(.system(size: 11, weight: .medium))
                            .fixedSize()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .overlay(Capsule(style: .circular).strokeBorder(Color.primary.opacity(0.5)))
                            .padding(.trailing, 4)
                    }
                }
                .tag(entry.id)
                .accessibilityElement(children: .combine)
            }
        }
        .contextMenu(forSelectionType: String.self) { _ in
            EmptyView()
        } primaryAction: { ids in
            if let id = ids.first, let entry = entries.first(where: { $0.id == id }) {
                choose(entry)
            }
        }
        .overlay {
            if entries.isEmpty {
                Text("見つかりません", bundle: .module)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - URL

struct SettingsURLEditor: View {
    let model: SettingsModel
    let cellID: UUID
    let url: URLAction

    var body: some View {
        let check = SettingsURLCheck(url.url)
        SettingsField(title: String(localized: "開く URL", bundle: .module)) {
            VStack(alignment: .leading, spacing: 6) {
                SettingsCommitTextField(value: url.url, placeholder: "https://example.com", accessibilityLabel: String(localized: "開く URL", bundle: .module)) { text in
                    model.updateAction(ofCell: cellID, as: URLAction.self) { $0.url = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                if let message = check.message {
                    SettingsNote(
                        text: message,
                        symbol: check.isProblem ? "exclamationmark.triangle" : "info.circle",
                        isWarning: check.isProblem
                    )
                } else {
                    SettingsNote(text: String(localized: "既定のアプリで開きます。obsidian:// のようなアプリ独自の URL も使えます。", bundle: .module))
                }
            }
        }
    }
}

// MARK: - スクリプト

struct SettingsScriptEditor: View {
    let model: SettingsModel
    let cellID: UUID
    let script: ScriptAction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("実行するスクリプト（zsh）", bundle: .module)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    SettingsHelpButton(label: String(localized: "スクリプトで使える環境変数", bundle: .module)) {
                        SettingsScriptHelp()
                    }
                }
                SettingsCommitTextEditor(
                    value: script.source,
                    code: true,
                    minHeight: 120,
                    accessibilityLabel: String(localized: "実行するスクリプト", bundle: .module)
                ) { source in
                    update { $0.source = source }
                }
            }
            SettingsField(title: String(localized: "実行の仕方", bundle: .module)) {
                Picker(selection: Binding(get: { script.runMode }, set: { mode in update { $0.runMode = mode } })) {
                    ForEach(ScriptRunMode.allCases, id: \.self) { mode in
                        Text(SettingsText.name(mode)).tag(mode)
                    }
                } label: {
                    Text("実行の仕方", bundle: .module)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(script.runMode == .background
                    ? String(localized: "終わるまで待ちます。出力があれば結果のパネルに出し（出したくないときは > /dev/null）、失敗したらエラーの最後を表示します", bundle: .module)
                    : String(localized: "ターミナルの新しいウインドウで実行します。claude のような対話型のコマンド向けです。", bundle: .module))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if script.runMode == .background {
                SettingsField(title: String(localized: "制限時間", bundle: .module)) {
                    HStack(spacing: 6) {
                        TextField(value: Binding(
                            get: { script.timeout },
                            set: { value in update { $0.timeout = SettingsCellEditing.clampedTimeout(value) } }
                        ), format: .number.precision(.fractionLength(0))) {
                            Text("制限時間", bundle: .module)
                        }
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                        Stepper(
                            value: Binding(
                                get: { script.timeout },
                                set: { value in update { $0.timeout = SettingsCellEditing.clampedTimeout(value) } }
                            ),
                            in: ScriptAction.timeoutRange,
                            step: 5
                        ) {
                            Text("制限時間", bundle: .module)
                        }
                        .labelsHidden()
                        Text("秒", bundle: .module)
                        Spacer()
                    }
                }
            }
        }
    }

    /// 描画したときの script ではなく、今の中身を書き換える（入力欄の確定は遅れて届くため）
    private func update(_ transform: (inout ScriptAction) -> Void) {
        model.updateAction(ofCell: cellID, as: ScriptAction.self, transform)
    }
}

/// スクリプトに渡す環境変数の説明（docs/user-guide.md と同じ）
struct SettingsScriptHelp: View {
    private var rows: [(String, String)] {
        [
            ("NONET_APP_BUNDLE_ID", String(localized: "前面のアプリの bundle ID", bundle: .module)),
            ("NONET_APP_NAME", String(localized: "前面のアプリの名前", bundle: .module)),
            ("NONET_DOCUMENT_PATH", String(localized: "前面のウインドウで開いている書類", bundle: .module)),
            ("NONET_PROJECT_DIR", String(localized: "書類から決めたプロジェクトのフォルダ", bundle: .module)),
            ("PROJECT_DIR", String(localized: "NONET_PROJECT_DIR と同じ", bundle: .module)),
            ("NONET_BROWSER_URL", String(localized: "ブラウザで表示中のページ（Safari・Google Chrome・Arc・Microsoft Edge・Brave）", bundle: .module)),
            ("NONET_SELECTED_TEXT", String(localized: "選択中のテキスト", bundle: .module)),
        ]
    }

    /// 説明の最後の段落（それぞれ1つの Text）
    static var notes: [String] {
        [
            String(localized: "作業フォルダはプロジェクトのフォルダ（分からなければホーム）。裏で実行するときはログインシェル（zsh -l）で動き、PATH はターミナルと同じもの（Nonet の起動時に ~/.zshrc まで読んで調べたもの）を使います。~/.zshrc のエイリアスや関数を使えるのは、ターミナルで実行するときだけです。", bundle: .module),
            // 選択中のテキストとブラウザの URL は、読むのに ⌘C を送ったりブラウザに問い合わせたりするので、名前を書いたスクリプトでだけ読む
            String(localized: "NONET_SELECTED_TEXT と NONET_BROWSER_URL は、スクリプトの中（コメントでもかまいません）にその名前があるときだけ設定されます。", bundle: .module),
            // 「ターミナルで実行」は .command のファイルを開くだけで、Apple Events を送らない（許可を求めない）
            String(localized: "スクリプトに NONET_BROWSER_URL を書くと、ブラウザの URL を初めて読むときに、macOS が「オートメーション」の許可を求めます。", bundle: .module),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("スクリプトに渡す環境変数", bundle: .module)
                .font(.headline)
            Text("実行したときの前面のアプリの情報です。値がないものは設定されません。", bundle: .module)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(rows, id: \.0) { name, detail in
                    GridRow {
                        Text(verbatim: name)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Divider()
            // ~ や $ を Markdown として読まないよう、String で渡す
            VStack(alignment: .leading, spacing: 6) {
                // コードの例は文の中に入れると途中で折り返されるので、それぞれの行に置く
                Text(String(localized: "変数は次のように \" で囲んでください。", bundle: .module))
                SettingsCodeLine(code: "\"$NONET_SELECTED_TEXT\"")
                Text(String(localized: "ないかもしれない変数は、次のように既定値を付けると安全です。", bundle: .module))
                SettingsCodeLine(code: "${PROJECT_DIR:-$HOME}")
                ForEach(Self.notes, id: \.self) { note in
                    Text(note)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 説明の中のコードの例。折り返さず等幅で、そのままコピーできる
struct SettingsCodeLine: View {
    let code: String

    var body: some View {
        Text(verbatim: code)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.primary)
            .fixedSize()
            .textSelection(.enabled)
            .padding(.leading, 12)
    }
}

// MARK: - ショートカット

struct SettingsShortcutEditor: View {
    let model: SettingsModel
    let list: SettingsShortcutList
    let cellID: UUID
    let shortcut: ShortcutAction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsField(title: String(localized: "実行するショートカット", bundle: .module)) {
                HStack(spacing: 6) {
                    SettingsCommitTextField(
                        value: shortcut.name,
                        placeholder: String(localized: "ショートカットの名前", bundle: .module)
                    ) { name in
                        update { $0.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    Menu {
                        menuContent
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(String(localized: "ショートカットの一覧から選ぶ", bundle: .module))
                    .accessibilityLabel(String(localized: "ショートカットの一覧から選ぶ", bundle: .module))
                    if list.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel(String(localized: "ショートカットの一覧を読み直しています", bundle: .module))
                    }
                }
                status
            }
            Toggle(isOn: Binding(get: { shortcut.passSelectedText }, set: { pass in update { $0.passSelectedText = pass } })) {
                Text("選択中のテキストを渡す", bundle: .module)
                Text("翻訳や要約など、テキストを受け取るショートカットで使います", bundle: .module)
            }
            .toggleStyle(.checkbox)
            SettingsNote(text: String(localized: "ショートカットがテキストを返したときは、結果のパネルに出します", bundle: .module))
        }
        .onAppear { list.loadIfNeeded() }
    }

    @ViewBuilder
    private var menuContent: some View {
        switch list.state {
        case .idle:
            Text("一覧をまだ読み込んでいません", bundle: .module)
        case .loading:
            Text("読み込んでいます…", bundle: .module)
        case .loaded(let names) where names.isEmpty:
            Text("ショートカットがありません", bundle: .module)
        case .loaded(let names):
            ForEach(names, id: \.self) { name in
                Button(name) { update { $0.name = name } }
            }
        }
        Divider()
        Button {
            list.reload()
        } label: {
            Text("一覧を読み直す", bundle: .module)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch list.state {
        case .idle:
            // 読み込みの途中でウィンドウを閉じたときなど
            HStack(spacing: 6) {
                Text("ショートカットの一覧をまだ読み込んでいません", bundle: .module)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                reloadButton(String(localized: "読み込む", bundle: .module))
            }
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("ショートカットの一覧を読み込んでいます…", bundle: .module)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .loaded(let names) where names.isEmpty:
            VStack(alignment: .leading, spacing: 4) {
                SettingsNote(text: String(localized: "ショートカットが見つかりません。ショートカット.app で作ってから、一覧を読み直してください。", bundle: .module), symbol: "info.circle")
                reloadButton(String(localized: "一覧を読み直す", bundle: .module))
            }
        case .loaded(let names):
            let name = shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !names.contains(name) {
                VStack(alignment: .leading, spacing: 4) {
                    SettingsNote(text: String(localized: "「\(name)」というショートカットは見つかりません", bundle: .module), symbol: "exclamationmark.triangle", isWarning: true)
                    reloadButton(String(localized: "一覧を読み直す", bundle: .module))
                }
            } else if name.isEmpty {
                SettingsNote(text: String(localized: "右の一覧から選ぶか、名前を入力してください", bundle: .module))
            }
        }
    }

    private func reloadButton(_ title: String) -> some View {
        Button {
            list.reload()
        } label: {
            Text(title)
        }
        .buttonStyle(.link)
        .font(.system(size: 11))
        .disabled(list.isRefreshing)
    }

    /// 描画したときの shortcut ではなく、今の中身を書き換える（入力欄の確定は遅れて届くため）
    private func update(_ transform: (inout ShortcutAction) -> Void) {
        model.updateAction(ofCell: cellID, as: ShortcutAction.self, transform)
    }
}

// MARK: - メニュー項目

struct SettingsMenuItemEditor: View {
    let model: SettingsModel
    let menu: MenuItemAction

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsField(title: String(localized: "押すメニュー項目", bundle: .module)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(menu.path.isEmpty ? String(localized: "未設定", bundle: .module) : menu.path.joined(separator: SettingsMenuIndex.pathSeparator))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(menu.path.isEmpty ? Color.secondary : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                        GridRow {
                            Text("アプリ", bundle: .module).foregroundStyle(.secondary)
                            Text(menu.app.map { $0.name.isEmpty ? $0.bundleID : $0.name } ?? String(localized: "前面のアプリ", bundle: .module))
                        }
                        GridRow {
                            Text("キー", bundle: .module).foregroundStyle(.secondary)
                            Text(menu.keyEquivalent?.displayString ?? String(localized: "なし（メニューを順にたどって押します）", bundle: .module))
                                .font(menu.keyEquivalent == nil ? .system(size: 11) : .system(size: 11, design: .monospaced))
                        }
                    }
                    .font(.system(size: 11))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: SettingsMetrics.mediumRadius).strokeBorder(SettingsPalette.panelBorder))
            }
            Button {
                model.showMenus(true)
            } label: {
                Label {
                    Text("メニューから選ぶ…", bundle: .module)
                } icon: {
                    Image(systemName: "filemenu.and.selection")
                }
            }
            SettingsNote(text: String(localized: "対象のアプリが起動している必要があります。メニューの名前は macOS の言語で変わるので、言語を変えたら割り当て直してください。", bundle: .module))
        }
    }
}

// MARK: - AI

struct SettingsAIEditor: View {
    let model: SettingsModel
    let cellID: UUID
    let ai: AIAction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let reason = model.services.ai.unavailableReason {
                SettingsNote(text: reason, symbol: "exclamationmark.triangle", isWarning: true)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: SettingsMetrics.mediumRadius).fill(Color.orange.opacity(0.08)))
            }
            SettingsField(title: String(localized: "指示文", bundle: .module)) {
                SettingsCommitTextEditor(
                    value: ai.prompt,
                    minHeight: 80,
                    accessibilityLabel: String(localized: "指示文", bundle: .module)
                ) { prompt in
                    update { $0.prompt = prompt }
                }
                Text("選択中のテキストと指示文を、Mac の中の言語モデル（Apple Intelligence）に渡します", bundle: .module)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsField(title: String(localized: "結果の出し方", bundle: .module)) {
                Picker(selection: Binding(get: { ai.output }, set: { output in update { $0.output = output } })) {
                    ForEach(AIOutput.allCases, id: \.self) { output in
                        Text(SettingsText.name(output)).tag(output)
                    }
                } label: {
                    Text("結果の出し方", bundle: .module)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            }
        }
    }

    /// 描画したときの ai ではなく、今の中身を書き換える（入力欄の確定は遅れて届くため）
    private func update(_ transform: (inout AIAction) -> Void) {
        model.updateAction(ofCell: cellID, as: AIAction.self, transform)
    }
}

// MARK: - ファイル

struct SettingsFileEditor: View {
    let model: SettingsModel
    let cellID: UUID
    let file: FileAction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsField(title: String(localized: "Finder で選んでいるファイルを", bundle: .module)) {
                Picker(selection: Binding(get: { file.operation }, set: { model.chooseFileOperation($0, forCell: cellID) })) {
                    ForEach(FileOperation.allCases, id: \.self) { operation in
                        Text(operation.title).tag(operation)
                    }
                } label: {
                    Text("Finder で選んでいるファイルを", bundle: .module)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                Text(SettingsText.detail(file.operation))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsNote(text: SettingsText.fileTarget)
        }
    }
}

/// 「画面に置く」: 置く場所を 3×3 で選ぶ（HUD のマスと同じ並び）
struct SettingsPlaceWindowEditor: View {
    let model: SettingsModel
    let cellID: UUID
    let place: PlaceWindowAction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsField(title: String(localized: "置く場所", bundle: .module)) {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(0..<3, id: \.self) { row in
                        GridRow {
                            ForEach(0..<3, id: \.self) { column in
                                regionButton(WindowRegion.allCases[row * 3 + column])
                            }
                        }
                    }
                }
                Text(SettingsText.placeWindowDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func regionButton(_ region: WindowRegion) -> some View {
        let isSelected = region == place.region
        return Button {
            model.choosePlaceWindowRegion(region, forCell: cellID)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: region.symbol)
                    .font(.system(size: 17))
                Text(region.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .frame(width: 74, height: 52)
            // アクセント色の上の文字は、macOS が選んだ項目に使う色（アクセント色が明るいときも読める）
            .foregroundStyle(isSelected ? Color(nsColor: .alternateSelectedControlTextColor) : Color.primary)
            .background(RoundedRectangle(cornerRadius: SettingsMetrics.mediumRadius).fill(isSelected ? Color.accentColor : SettingsPalette.cellBackground))
            .overlay(RoundedRectangle(cornerRadius: SettingsMetrics.mediumRadius).strokeBorder(isSelected ? Color.clear : SettingsPalette.cellBorder))
            .contentShape(RoundedRectangle(cornerRadius: SettingsMetrics.mediumRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(region.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// 「再生・音量」: 送るキーを選ぶ（4つずつ2段）
struct SettingsMediaEditor: View {
    let model: SettingsModel
    let cellID: UUID
    let media: MediaAction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsField(title: String(localized: "押すキー", bundle: .module)) {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            ForEach(0..<4, id: \.self) { column in
                                keyButton(MediaKey.allCases[row * 4 + column])
                            }
                        }
                    }
                }
                Text(SettingsText.mediaDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func keyButton(_ key: MediaKey) -> some View {
        let isSelected = key == media.key
        return Button {
            model.chooseMediaKey(key, forCell: cellID)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: key.symbol)
                    .font(.system(size: 16))
                Text(key.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 62, height: 50)
            .foregroundStyle(isSelected ? Color(nsColor: .alternateSelectedControlTextColor) : Color.primary)
            .background(RoundedRectangle(cornerRadius: SettingsMetrics.mediumRadius).fill(isSelected ? Color.accentColor : SettingsPalette.cellBackground))
            .overlay(RoundedRectangle(cornerRadius: SettingsMetrics.mediumRadius).strokeBorder(isSelected ? Color.clear : SettingsPalette.cellBorder))
            .contentShape(RoundedRectangle(cornerRadius: SettingsMetrics.mediumRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// 「最近のスクショ」: 並べる数と、画面の収録も並べるか
struct SettingsScreenshotTrayEditor: View {
    let model: SettingsModel
    let cellID: UUID
    let tray: ScreenshotTrayAction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsField(title: String(localized: "並べる数", bundle: .module)) {
                Picker(selection: Binding(get: { tray.count }, set: { count in model.setScreenshotTray({ $0.count = count }, forCell: cellID) })) {
                    ForEach(ScreenshotTrayAction.counts, id: \.self) { count in
                        Text(verbatim: "\(count)").tag(count)
                    }
                } label: {
                    Text("並べる数", bundle: .module)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            Toggle(isOn: Binding(get: { tray.includesVideos }, set: { on in model.setScreenshotTray({ $0.includesVideos = on }, forCell: cellID) })) {
                Text("画面の収録（動画）も並べる", bundle: .module)
            }
            SettingsNote(text: SettingsText.screenshotsDetail)
        }
    }
}

/// 「テキストを貼る」: 貼るテキスト（{date}・{time} は貼るときに置き換える）
struct SettingsPasteTextEditor: View {
    let model: SettingsModel
    let cellID: UUID
    let paste: PasteTextAction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsField(title: String(localized: "貼るテキスト", bundle: .module)) {
                SettingsCommitTextEditor(
                    value: paste.text,
                    minHeight: 90,
                    accessibilityLabel: String(localized: "貼るテキスト", bundle: .module)
                ) { text in
                    model.updateAction(ofCell: cellID, as: PasteTextAction.self) { $0.text = text }
                }
                Text(SettingsText.pasteTextDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

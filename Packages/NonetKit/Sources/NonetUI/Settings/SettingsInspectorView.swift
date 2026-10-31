// 担当: ui-settings
// 右のインスペクタ: 選んだマスの表示名・アイコン・アクション。変更はその場で保存する
import NonetCore
import SwiftUI

struct SettingsInspectorView: View {
    let model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let index = model.selectedIndex {
                    HStack(alignment: .firstTextBaseline) {
                        Text(SettingsGrid.cellName(index))
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                        if model.selectedProfile.pages.count > 1 {
                            Text("ページ \(model.pageIndex + 1)", bundle: .module)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let cell = model.selectedCell {
                        SettingsCellEditor(model: model, cell: cell, profile: model.selectedProfile)
                            .id(cell.id)
                    } else {
                        SettingsEmptyCellChooser(model: model, index: index)
                    }
                } else {
                    Text("マスを選ぶと、ここで設定できます", bundle: .module)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// 空きマス: 種類を選んで作る
struct SettingsEmptyCellChooser: View {
    let model: SettingsModel
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("このマスは空いています。アクションの種類を選んでください。", bundle: .module)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(SettingsActionKinds.ordered, id: \.self) { kind in
                    Button {
                        model.createCell(kind: kind, at: index)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: SettingsActionKinds.symbol(kind))
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            Text(SettingsActionKinds.name(kind))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .controlSize(.large)
                }
            }
            Text("メニューの項目は「メニューから割り当て」でも入れられます", bundle: .module)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsCellEditor: View {
    let model: SettingsModel
    let cell: Cell
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsField(title: String(localized: "表示名", bundle: .module)) {
                HStack(spacing: 8) {
                    SettingsIconButton(model: model, cell: cell, profile: profile)
                    SettingsCommitTextField(
                        value: cell.title,
                        placeholder: SettingsCellEditing.automaticTitle(for: cell.action),
                        accessibilityLabel: String(localized: "表示名", bundle: .module),
                        focusRequest: model.nameFieldFocusRequest
                    ) { title in
                        model.updateCell(id: cell.id) { $0.title = title }
                    }
                }
            }
            SettingsField(title: String(localized: "アクションの種類", bundle: .module)) {
                Picker(selection: Binding(get: { cell.action.kind }, set: { model.changeKind(ofCell: cell.id, to: $0) })) {
                    ForEach(SettingsActionKinds.ordered, id: \.self) { kind in
                        Label(SettingsActionKinds.name(kind), systemImage: SettingsActionKinds.symbol(kind))
                            .tag(kind)
                    }
                } label: {
                    Text("アクションの種類", bundle: .module)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            actionEditor
            Toggle(isOn: Binding(get: { cell.requiresHUD }, set: { model.setRequiresHUD($0, ofCell: cell.id) })) {
                Text(SettingsText.hudOnlyTitle)
                Text(SettingsText.hudOnlyDetail)
            }
            .toggleStyle(.checkbox)
            Divider()
            SettingsTestRunSection(model: model, cell: cell)
            Button(role: .destructive) {
                if let index = model.selectedIndex {
                    model.clearCell(at: index)
                }
            } label: {
                Text("このマスを空にする", bundle: .module)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .font(.system(size: 12))
        }
    }

    @ViewBuilder
    private var actionEditor: some View {
        switch cell.action {
        case .keystroke(let keys):
            SettingsKeystrokeEditor(model: model, cellID: cell.id, keys: keys)
        case .launchApp(let launch):
            SettingsLaunchAppEditor(model: model, cellID: cell.id, launch: launch)
        case .openURL(let url):
            SettingsURLEditor(model: model, cellID: cell.id, url: url)
        case .script(let script):
            SettingsScriptEditor(model: model, cellID: cell.id, script: script)
        case .shortcut(let shortcut):
            SettingsShortcutEditor(model: model, list: model.shortcutList, cellID: cell.id, shortcut: shortcut)
        case .menuItem(let menu):
            SettingsMenuItemEditor(model: model, menu: menu)
        case .ai(let ai):
            SettingsAIEditor(model: model, cellID: cell.id, ai: ai)
        }
    }
}

extension SettingsModel {
    /// 「すぐのタップでは実行しない（HUD で選んだときだけ）」（Cell.requiresHUD）。ほかのインスペクタの変更と同じく ⌘Z で戻せる
    func setRequiresHUD(_ isOn: Bool, ofCell id: UUID) {
        updateCell(id: id) { $0.requiresHUD = isOn }
    }
}

/// 「このマスをテスト実行」と結果
struct SettingsTestRunSection: View {
    let model: SettingsModel
    let cell: Cell

    var body: some View {
        let run = model.testRun(for: cell.id)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                model.startTestRun(cellID: cell.id)
            } label: {
                Label {
                    Text("このマスをテスト実行", bundle: .module)
                } icon: {
                    Image(systemName: "play.fill")
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(run != nil && run?.record == nil)
            if let run {
                if let record = run.record {
                    SettingsNote(
                        text: SettingsText.testResult(record),
                        symbol: record.succeeded ? "checkmark.circle" : "xmark.octagon",
                        isWarning: !record.succeeded
                    )
                    if let output = record.output {
                        SettingsTestOutput(text: output)
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("実行しています…", bundle: .module)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !profile.isGlobal {
                Text("アプリのプロファイルでは、そのアプリを前面に出してから実行します", bundle: .module)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var profile: Profile { model.selectedProfile }
}

/// テスト実行の結果（「画面に表示」の AI・スクリプト・ショートカット）。選んでコピーできる
struct SettingsTestOutput: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(verbatim: text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxHeight: 160)
        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(SettingsPalette.panelBorder))
        .accessibilityLabel(Text("結果", bundle: .module))
    }
}

// MARK: - アイコン

struct SettingsIconButton: View {
    let model: SettingsModel
    let cell: Cell
    let profile: Profile
    @State private var isPicking = false

    var body: some View {
        Button {
            isPicking.toggle()
        } label: {
            CellIconView(cell.icon, size: 16)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(SettingsPalette.cellBackground))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(SettingsPalette.cellBorder))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "アイコンを変更", bundle: .module))
        .accessibilityLabel(String(localized: "アイコンを変更", bundle: .module))
        .popover(isPresented: $isPicking, arrowEdge: .bottom) {
            SettingsIconPicker(
                icon: cell.icon,
                suggestedAppBundleID: SettingsIconLibrary.suggestedApp(for: cell.action, profile: profile),
                defaultIcon: SettingsCellEditing.defaultIcon(for: cell.action)
            ) { icon in
                model.updateCell(id: cell.id) { $0.icon = icon }
            }
        }
    }
}

struct SettingsIconPicker: View {
    let icon: CellIcon
    let suggestedAppBundleID: String?
    let defaultIcon: CellIcon
    let choose: (CellIcon) -> Void

    @State private var kind: SettingsIconLibrary.Kind
    @State private var query = ""
    @State private var text: String

    init(icon: CellIcon, suggestedAppBundleID: String?, defaultIcon: CellIcon, choose: @escaping (CellIcon) -> Void) {
        self.icon = icon
        self.suggestedAppBundleID = suggestedAppBundleID
        self.defaultIcon = defaultIcon
        self.choose = choose
        _kind = State(initialValue: SettingsIconLibrary.Kind(icon))
        if case .text(let value) = icon {
            _text = State(initialValue: value)
        } else {
            _text = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(selection: $kind) {
                ForEach(SettingsIconLibrary.Kind.allCases) { kind in
                    Text(kind.name).tag(kind)
                }
            } label: {
                Text("アイコンの種類", bundle: .module)
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            switch kind {
            case .symbol: symbolGrid
            case .app: appChoice
            case .text: textChoice
            }

            if icon != defaultIcon {
                Button {
                    choose(defaultIcon)
                } label: {
                    Text("既定のアイコンに戻す", bundle: .module)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var symbolGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(text: $query, prompt: Text("記号を検索（英語）", bundle: .module)) {
                Text("記号を検索（英語）", bundle: .module)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let groups = SettingsIconLibrary.filter(query)
                    if groups.isEmpty {
                        Text("見つかりません", bundle: .module)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(groups) { group in
                        Text(group.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8), spacing: 6) {
                            ForEach(group.symbols, id: \.self) { symbol in
                                let isCurrent = icon == .symbol(symbol)
                                Button {
                                    choose(.symbol(symbol))
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.system(size: 15))
                                        .frame(width: 30, height: 30)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(isCurrent ? Color.primary.opacity(0.12) : Color.clear))
                                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isCurrent ? Color.primary : Color.clear, lineWidth: 1.5))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(symbol)
                                .accessibilityLabel(symbol)
                            }
                        }
                    }
                }
            }
            .frame(height: 220)
        }
    }

    @ViewBuilder
    private var appChoice: some View {
        if let bundleID = suggestedAppBundleID {
            HStack(spacing: 12) {
                CellIconView(.app(bundleID: bundleID), size: 24)
                Button {
                    choose(.app(bundleID: bundleID))
                } label: {
                    Text("このアプリのアイコンを使う", bundle: .module)
                }
                .disabled(icon == .app(bundleID: bundleID))
            }
        } else {
            Text("アプリのアイコンは、アプリ起動のマスか、アプリのプロファイルで使えます", bundle: .module)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var textChoice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(text: $text, prompt: Text("1〜2文字", bundle: .module)) {
                    Text("アイコンの文字", bundle: .module)
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .onSubmit(applyText)
                Button(action: applyText) {
                    Text("使う", bundle: .module)
                }
                .disabled(SettingsIconLibrary.normalizedText(text) == nil)
                if let normalized = SettingsIconLibrary.normalizedText(text) {
                    CellIconView(.text(normalized), size: 18)
                }
            }
            Text("1〜2文字（3文字目からは切ります）", bundle: .module)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func applyText() {
        if let normalized = SettingsIconLibrary.normalizedText(text) {
            text = normalized
            choose(.text(normalized))
        }
    }
}

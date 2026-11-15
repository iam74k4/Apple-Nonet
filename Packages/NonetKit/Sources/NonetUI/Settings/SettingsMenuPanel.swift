// 担当: ui-settings
// 「メニューから割り当て」のパネル（モックのボード「メニューから選ぶ設定」）と、プロファイルの追加
import NonetCore
import SwiftUI

struct SettingsMenuPanel: View {
    let model: SettingsModel
    @Bindable var browser: SettingsMenuBrowser
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Button {
                    model.showMenus(false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help(String(localized: "インスペクタに戻る", bundle: .module))
                .accessibilityLabel(String(localized: "インスペクタに戻る", bundle: .module))
            }
            Text("起動中のアプリのメニューを読み取ります", bundle: .module)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Picker(selection: Binding(
                    get: { browser.selectedApp?.processID },
                    set: { id in browser.select(browser.runningApps.first { $0.processID == id }) }
                )) {
                    Text("アプリを選ぶ", bundle: .module).tag(Int32?.none)
                    ForEach(browser.runningApps, id: \.processID) { app in
                        Text(app.app.name.isEmpty ? app.app.bundleID : app.app.name).tag(Int32?.some(app.processID))
                    }
                } label: {
                    Text("アプリ", bundle: .module)
                }
                .labelsHidden()
                Button {
                    browser.refreshApps(preferredBundleID: model.selectedProfile.app?.bundleID)
                    browser.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "読み直す", bundle: .module))
                .accessibilityLabel(String(localized: "読み直す", bundle: .module))
            }
            TextField(text: $browser.query, prompt: Text("メニューを検索", bundle: .module)) {
                Text("メニューを検索", bundle: .module)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .disabled(browser.sections.isEmpty)
            content
                .frame(maxHeight: .infinity)
            Text("項目をマスへドラッグするか、ダブルクリックで選んでいるメニュー項目のマス（無ければ空いているマス）に入れます", bundle: .module)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var title: String {
        if let app = browser.selectedApp {
            let name = app.app.name.isEmpty ? app.app.bundleID : app.app.name
            return String(localized: "\(name) のメニュー", bundle: .module)
        }
        return String(localized: "メニューから割り当て", bundle: .module)
    }

    @ViewBuilder
    private var content: some View {
        switch browser.state {
        case .idle where browser.selectedApp != nil:
            // 読み込みの途中でウィンドウを閉じたときなど
            placeholder(
                symbol: "filemenu.and.selection",
                text: String(localized: "メニューをまだ読み込んでいません", bundle: .module),
                action: (String(localized: "メニューを読み込む", bundle: .module), { browser.reload() })
            )
        case .idle:
            placeholder(symbol: "filemenu.and.selection", text: browser.runningApps.isEmpty
                ? String(localized: "メニューを読めるアプリが起動していません", bundle: .module)
                : String(localized: "メニューを読むアプリを選んでください。対象のアプリは起動しておきます。", bundle: .module))
        case .loading:
            VStack(spacing: 8) {
                ProgressView()
                Text("メニューを読み込んでいます…", bundle: .module)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message, let needsPermission):
            VStack(spacing: 10) {
                Image(systemName: needsPermission ? "lock.shield" : "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if needsPermission {
                    Button {
                        model.services.permissions.openAccessibilitySettings()
                    } label: {
                        Text("システム設定を開く", bundle: .module)
                    }
                }
                Button {
                    browser.reload()
                } label: {
                    Text("もう一度読む", bundle: .module)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let sections) where sections.isEmpty:
            placeholder(symbol: "filemenu.and.selection", text: String(localized: "割り当てられるメニュー項目がありません", bundle: .module))
        case .loaded:
            let sections = browser.visibleSections
            if sections.isEmpty {
                placeholder(symbol: "magnifyingglass", text: String(localized: "「\(browser.query)」に合う項目はありません", bundle: .module))
            } else {
                list(sections)
            }
        }
    }

    private func list(_ sections: [SettingsMenuSection]) -> some View {
        List(selection: $selection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        SettingsMenuRow(entry: entry)
                            .tag(entry.id)
                            .draggable(SettingsDragItem(payload: .menuItem(id: entry.id))) {
                                Text(entry.node.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule(style: .circular).fill(Color.primary))
                                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                            }
                    }
                } header: {
                    Text(section.title)
                }
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let entry = browser.entry(id: id) {
                Button {
                    model.assignMenuItem(entry.node)
                } label: {
                    Text("マスに入れる", bundle: .module)
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let entry = browser.entry(id: id) {
                model.assignMenuItem(entry.node)
            }
        }
    }

    private func placeholder(symbol: String, text: String, action: (title: String, perform: () -> Void)? = nil) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.title, action: action.perform)
                    .padding(.top, 2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsMenuRow: View {
    let entry: SettingsMenuEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.node.title)
                    .lineLimit(1)
                if !entry.location.isEmpty {
                    Text(entry.location)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if let keys = entry.node.keyEquivalent {
                Text(keys.displayString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(entry.node.isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        // 薄くしただけでは VoiceOver に伝わらないので、使えない項目は「使用不可」と読ませる
        .accessibilityValue(entry.node.isEnabled ? "" : String(localized: "使用不可", bundle: .module))
        .accessibilityHint(String(localized: "選んでいるメニュー項目のマス（無ければ空いているマス）に入れます", bundle: .module))
    }
}

// MARK: - プロファイルの追加

struct SettingsAddProfileSheet: View {
    let model: SettingsModel
    @State private var query = ""
    @State private var selection: String?
    @State private var pickError: String?

    var body: some View {
        let existing = Set(model.appProfiles.compactMap(\.app?.bundleID))
        // 複製するときは、プロファイルのあるアプリを出さない（1つのアプリに1つまで）。プリセットは使わないので印も出さない
        let source = model.duplicatingProfileID.flatMap(model.configuration.profile(id:))
        let all = SettingsAppCatalog.entries(apps: model.installedApps, query: query, existingBundleIDs: existing, presetsFirst: source == nil)
        let entries = source == nil ? all : all.filter { !$0.hasProfile }
        VStack(alignment: .leading, spacing: 12) {
            if let source {
                Text("「\(source.name)」を複製して使うアプリ", bundle: .module)
                    .font(.headline)
                Text("選んだアプリに、「\(source.name)」のページとマスをすべて写した新しいプロファイルを作ります", bundle: .module)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // 開くボタン（「プロファイルを追加…」）と違い、シートの見出しには「…」を付けない
                Text(String(localized: "settings.addProfileSheet.title", defaultValue: "プロファイルを追加", bundle: .module))
                    .font(.headline)
                Text("アプリを選ぶと、そのアプリが前面にあるときの9マスを作ります。プリセットのあるアプリは、最初から中身が入ります。", bundle: .module)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField(text: $query, prompt: Text("アプリを検索", bundle: .module)) {
                Text("アプリを検索", bundle: .module)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            SettingsAppList(entries: entries, selection: $selection, showsBadges: source == nil) { entry in
                model.addProfile(for: entry.app)
            }
            .frame(minHeight: 280)
            if let pickError {
                SettingsNote(text: pickError, symbol: "exclamationmark.triangle", isWarning: true)
            }
            HStack {
                Button {
                    Task {
                        guard let url = await model.files?.chooseApplication() else { return }
                        if let app = SettingsAppCatalog.appReference(forBundleAt: url) {
                            model.addProfile(for: app)
                        } else {
                            pickError = String(localized: "このアプリは選べません（bundle ID がありません）", bundle: .module)
                        }
                    }
                } label: {
                    Text("一覧にないアプリを選ぶ…", bundle: .module)
                }
                Spacer()
                Button(role: .cancel) {
                    model.isAddingProfile = false
                } label: {
                    Text("キャンセル", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    if let entry = entries.first(where: { $0.id == selection }) {
                        model.addProfile(for: entry.app)
                    }
                } label: {
                    if source == nil {
                        Text("追加", bundle: .module)
                    } else {
                        Text("複製", bundle: .module)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil || !entries.contains { $0.id == selection })
            }
        }
        .padding(20)
        .frame(width: 460, height: 520)
        .onAppear { model.reloadInstalledApps() }
    }
}

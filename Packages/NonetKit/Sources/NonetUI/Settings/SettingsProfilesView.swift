// 担当: ui-settings
// プロファイルのタブ: 左にプロファイルの一覧、中央にページと 3×3、右にインスペクタ（またはメニューから割り当て）
import NonetCore
import SwiftUI

struct SettingsProfilesView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(model: model)
                .frame(width: 210)
            Divider()
            SettingsEditorCenter(model: model)
                .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            Group {
                switch model.rightPanel {
                case .inspector: SettingsInspectorView(model: model)
                case .menus: SettingsMenuPanel(model: model, browser: model.menuBrowser)
                }
            }
            .frame(width: 310)
            .frame(maxHeight: .infinity)
        }
        .background { SettingsProfileShortcuts(model: model) }
        .sheet(isPresented: $model.isAddingProfile) {
            SettingsAddProfileSheet(model: model)
        }
    }
}

/// プロファイルのタブのキー（⌘F で絞り込み、⌘1〜⌘3 でページ）。文字の欄で使うキーとは重ならない。
/// グリッドだけのキー（Return・⌘D・⌘⌫・⌥⌘＋矢印キー）は SettingsGridView が受ける
struct SettingsProfileShortcuts: View {
    let model: SettingsModel

    var body: some View {
        ZStack {
            Button(String(localized: "プロファイルを絞り込む", bundle: .module)) { model.focusFilter() }
                .keyboardShortcut("f", modifiers: .command)
            ForEach(1...Profile.maxPages, id: \.self) { number in
                Button(String(localized: "ページ \(number)", bundle: .module)) { model.selectPageByShortcut(number) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - サイドバー

struct SettingsSidebar: View {
    @Bindable var model: SettingsModel
    @FocusState private var isFilterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if model.showsProfileFilter {
                filterField
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
            }
            if model.profileQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                profileList
            } else {
                SettingsSearchResultsList(model: model)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    model.isAddingProfile = true
                } label: {
                    Label {
                        Text("プロファイルを追加", bundle: .module)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(.borderless)
                Toggle(isOn: Binding(get: { model.settings.isEnabled }, set: { model.setSetting(\.isEnabled, $0) })) {
                    Text("Nonet を有効にする", bundle: .module)
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.filterFocusRequest) {
            // 欄はこの変更で出てくるので、出てから移る
            Task { @MainActor in isFilterFocused = true }
        }
    }

    private var filterField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(text: $model.profileQuery, prompt: Text("名前・マス・キーで絞り込み", bundle: .module)) {
                Text("プロファイルを絞り込む", bundle: .module)
            }
            .textFieldStyle(.plain)
            .focused($isFilterFocused)
            .onExitCommand {
                model.clearFilter()
                isFilterFocused = false
            }
            if !model.profileQuery.isEmpty {
                Button {
                    model.clearFilter()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "絞り込みをやめる", bundle: .module))
                .accessibilityLabel(String(localized: "絞り込みをやめる", bundle: .module))
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }

    private var profileList: some View {
        List(selection: Binding(get: { model.selectedProfile.id }, set: { model.selectProfile($0) })) {
            Section {
                globalRow
                    .tag(model.configuration.globalProfile.id)
                    .contextMenu { SettingsProfileContextMenu(model: model, profile: model.configuration.globalProfile) }
            } header: {
                Text("プロファイル", bundle: .module)
            }
            Section {
                ForEach(model.appProfiles) { profile in
                    SettingsProfileRow(profile: profile, isInUse: profile.id == model.inUseProfileID)
                        .tag(profile.id)
                        .contextMenu { SettingsProfileContextMenu(model: model, profile: profile) }
                }
                .onMove { model.moveProfiles(fromOffsets: $0, toOffset: $1) }
            } header: {
                // アイコンの種類やメニュー項目の「アプリ」と違い、複数のアプリの一覧の見出し
                Text(String(localized: "settings.sidebar.appsHeader", defaultValue: "アプリ", bundle: .module))
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            let profile = model.selectedProfile
            if !profile.isGlobal {
                model.requestDeleteProfile(profile.id)
            }
        }
        .overlay(alignment: .bottom) {
            if model.appProfiles.isEmpty {
                Text("「プロファイルを追加」で、アプリごとの9マスを作れます", bundle: .module)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(16)
            }
        }
    }

    private var globalRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(model.configuration.globalProfile.name)
                .lineLimit(1)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 4)
            Text("既定", bundle: .module)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

/// プロファイルの右クリック: 使い方・複製・プリセットに戻す・書き出し・削除
struct SettingsProfileContextMenu: View {
    let model: SettingsModel
    let profile: Profile

    var body: some View {
        if !profile.isGlobal {
            Picker(selection: Binding(get: { profile.mode }, set: { model.setProfileMode(profile.id, $0) })) {
                ForEach(ProfileMode.allCases, id: \.self) { mode in
                    Text(SettingsText.name(mode)).tag(mode)
                }
            } label: {
                Text("前面にあるとき", bundle: .module)
            }
            .pickerStyle(.inline)
            Divider()
        }
        Button {
            model.beginDuplicatingProfile(profile.id)
        } label: {
            Text("複製して別のアプリに使う…", bundle: .module)
        }
        if model.preset(forProfile: profile.id) != nil {
            Button {
                model.requestResetProfile(profile.id)
            } label: {
                Text("プリセットに戻す…", bundle: .module)
            }
        }
        Button {
            Task { await model.exportProfiles([profile], suggestedName: profile.name) }
        } label: {
            Text("このプロファイルを書き出す…", bundle: .module)
        }
        if !profile.isGlobal {
            Divider()
            Button(role: .destructive) {
                model.requestDeleteProfile(profile.id)
            } label: {
                Text("削除…", bundle: .module)
            }
        }
    }
}

struct SettingsProfileRow: View {
    let profile: Profile
    /// いま前面のアプリで使われているプロファイル（「使用中」の印）
    var isInUse = false

    var body: some View {
        let isUsed = profile.mode == .profile
        HStack(spacing: 8) {
            CellIconView(.app(bundleID: profile.app?.bundleID ?? ""), size: 14)
                .saturation(isUsed ? 1 : 0)
                .opacity(isUsed ? 1 : 0.45)
                .accessibilityHidden(true)
            Text(profile.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isUsed ? Color.primary : Color.secondary)
            Spacer(minLength: 4)
            if isInUse {
                Text("使用中", bundle: .module)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(Capsule(style: .circular).strokeBorder(Color.accentColor.opacity(0.6)))
                    // VoiceOver では値（accessibilityValue）で読むので、ここでは読まない（2回読まない）
                    .accessibilityHidden(true)
            }
            if let badge = Self.badge(profile.mode) {
                Text(badge)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(Capsule(style: .circular).strokeBorder(Color.secondary.opacity(0.5)))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue([isInUse ? String(localized: "使用中", bundle: .module) : "", isUsed ? "" : SettingsText.name(profile.mode)]
            .filter { !$0.isEmpty }.joined(separator: String(localized: "、", bundle: .module)))
    }

    /// 一覧の右の小さな印。グローバルを使うプロファイルは「グローバル」、使わないアプリは「オフ」
    static func badge(_ mode: ProfileMode) -> String? {
        switch mode {
        case .profile: nil
        case .global: String(localized: "settings.sidebar.usesGlobalBadge", defaultValue: "グローバル", bundle: .module)
        case .off: String(localized: "オフ", bundle: .module)
        }
    }
}

/// 絞り込みの結果: 名前の合うプロファイルと、名前・説明・送るキーの合うボタン（「Xcode › ページ 1 › ビルド ⌘B」）
struct SettingsSearchResultsList: View {
    let model: SettingsModel

    var body: some View {
        let results = model.searchResults
        List {
            if !results.profiles.isEmpty {
                Section {
                    ForEach(results.profiles) { profile in
                        Button {
                            model.selectProfile(profile.id)
                        } label: {
                            SettingsProfileRow(profile: profile, isInUse: profile.id == model.inUseProfileID)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(profile.id == model.selectedProfile.id ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                } header: {
                    Text("プロファイル", bundle: .module)
                }
            }
            if !results.cells.isEmpty {
                Section {
                    ForEach(results.cells) { match in
                        Button {
                            model.reveal(match)
                        } label: {
                            row(match)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(isSelected(match) ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                } header: {
                    Text("マス", bundle: .module)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if results.isEmpty {
                Text("見つかりません", bundle: .module)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func isSelected(_ match: SettingsCellMatch) -> Bool {
        match.profileID == model.selectedProfile.id && match.address == model.selectedAddress
    }

    private func row(_ match: SettingsCellMatch) -> some View {
        HStack(spacing: 6) {
            Text(match.path)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if match.detailIsKeys {
                Text(match.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.system(size: 12))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 中央

struct SettingsEditorCenter: View {
    let model: SettingsModel

    var body: some View {
        let profile = model.selectedProfile
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                // 名前が長くて入らないときは、使い方の見出しを省いて名前に場所を譲る（見出しはヘルプと VoiceOver に残す）
                ViewThatFits(in: .horizontal) {
                    header(profile, showsModeLabel: true)
                    header(profile, showsModeLabel: false)
                }
                Text(SettingsText.profileDescription(profile))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsPageBar(model: model)
            SettingsGridView(model: model)
                .opacity(profile.mode == .profile ? 1 : 0.55)
            footer
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private func header(_ profile: Profile, showsModeLabel: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(profile.name)
                .font(.system(size: 22, weight: .bold))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if !profile.isGlobal {
                let title = String(localized: "\(profile.name) が前面にあるとき", bundle: .module)
                let picker = Picker(selection: Binding(get: { profile.mode }, set: { model.setProfileMode(profile.id, $0) })) {
                    ForEach(ProfileMode.allCases, id: \.self) { mode in
                        Text(SettingsText.name(mode)).tag(mode)
                    }
                } label: {
                    Text("前面にあるとき", bundle: .module)
                        .font(.system(size: 12))
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .help(title)
                .accessibilityLabel(title)
                // 狭いときは見出しをポップアップの上に移し、選択肢の幅も縮めて名前を先に出す（名前の方を優先する）。
                // 見出しを消すと「このプロファイル」だけが残り、何を選ぶのか分からない
                if showsModeLabel {
                    picker.fixedSize()
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("前面にあるとき", bundle: .module)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                        picker.labelsHidden()
                            .frame(minWidth: 110, maxWidth: 190)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let message = model.gridMessage {
            SettingsNote(text: message, symbol: "exclamationmark.triangle", isWarning: true)
        } else if let notice = model.undoNotice {
            // 編集メニューの「取り消す」（⌘Z）が見えなくても、空にしたマスや消したプロファイルなどを戻せるように
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(notice.text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    model.undoFromNotice()
                } label: {
                    Text("元に戻す", bundle: .module)
                }
                .buttonStyle(.link)
                Spacer(minLength: 8)
            }
            .font(.system(size: 11))
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text("マスを選んで右側で設定。ドラッグか ⌥⌘＋矢印キーで入れ替え、Delete で空にする。", bundle: .module)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }
}

/// ページの切り替え（最大3）と、メニューから割り当て。ページの見出しのダブルクリックで名前を変える
struct SettingsPageBar: View {
    let model: SettingsModel

    var body: some View {
        // 窓が狭いときはページの名前を数字だけに、それでも入らなければ「メニューから割り当て」をアイコンだけにする
        // （数字だけでもページと分かるが、アイコンだけのボタンは何をするのか分からない）
        ViewThatFits(in: .horizontal) {
            bar(compactPages: false, compactMenuButton: false)
            bar(compactPages: true, compactMenuButton: false)
            bar(compactPages: true, compactMenuButton: true)
        }
    }

    private func bar(compactPages: Bool, compactMenuButton: Bool) -> some View {
        let profile = model.selectedProfile
        return HStack(spacing: 6) {
            do {
                ForEach(profile.pages.indices, id: \.self) { index in
                    pageButton(
                        index,
                        name: profile.pages[index].name,
                        isSelected: index == model.pageIndex,
                        compact: compactPages
                    )
                }
                if model.canAddPage {
                    Button {
                        model.addPage()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "ページを追加", bundle: .module))
                    .accessibilityLabel(String(localized: "ページを追加", bundle: .module))
                }
                pageMenu
            }
            Spacer(minLength: 8)
            menuToggle(compact: compactMenuButton)
        }
    }

    /// 選んでいるページの操作。削除はページの見出しの横に記号だけで置かない（区切りの線に見え、どのページを消すのかも分からない）
    private var pageMenu: some View {
        let title = String(localized: "ページの操作", bundle: .module)
        return Menu {
            Button {
                model.addPage()
            } label: {
                Text(String(localized: "settings.pageMenu.addPage", defaultValue: "ページを追加", bundle: .module))
            }
            .disabled(!model.canAddPage)
            Button {
                model.beginRenamingPage(model.pageIndex)
            } label: {
                Text("名前を変更…", bundle: .module)
            }
            Divider()
            Button(role: .destructive) {
                model.requestRemovePage(model.pageIndex)
            } label: {
                Text("このページを削除…", bundle: .module)
            }
            .disabled(!model.canRemovePage)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(title)
        .accessibilityLabel(title)
    }

    private func menuToggle(compact: Bool) -> some View {
        let title = String(localized: "メニューから割り当て", bundle: .module)
        return Toggle(isOn: Binding(get: { model.rightPanel == .menus }, set: { model.showMenus($0) })) {
            if compact {
                Image(systemName: "filemenu.and.selection")
            } else {
                Label {
                    Text(title).lineLimit(1)
                } icon: {
                    Image(systemName: "filemenu.and.selection")
                }
            }
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .help(title)
        .accessibilityLabel(title)
    }

    private func pageButton(_ index: Int, name: String?, isSelected: Bool, compact: Bool) -> some View {
        let title = SettingsText.pageTitle(index: index, name: name)
        let rename = String(localized: "名前を変更…", bundle: .module)
        return Button {
            model.selectPage(index)
        } label: {
            Text(compact ? "\(index + 1)" : title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: compact ? nil : 140)
                .fixedSize()
                .padding(.horizontal, compact ? 8 : 10)
                .padding(.vertical, 4)
                .frame(minWidth: 26)
                .foregroundStyle(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                // 選んでいるページだけを塗る。ほかのページに枠を付けると、グリッドの選んでいるマスと見分けにくい
                .background(Capsule(style: .circular).fill(isSelected ? Color.primary : SettingsPalette.cellBackground))
                .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        // ダブルクリックで名前を変える（1回目のクリックでそのページを選ぶ）
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.beginRenamingPage(index) })
        .help(String(localized: "ダブルクリックで名前を変更", bundle: .module))
        .accessibilityLabel(SettingsText.pageAccessibilityLabel(index: index, name: name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: rename) { model.beginRenamingPage(index) }
        .popover(
            isPresented: Binding(get: { model.renamingPage == index }, set: { if !$0, model.renamingPage == index { model.renamingPage = nil } }),
            arrowEdge: .bottom
        ) {
            SettingsPageNameEditor(model: model, index: index, name: name ?? "")
        }
        .contextMenu {
            Button {
                model.beginRenamingPage(index)
            } label: {
                Text(rename)
            }
            if model.canRemovePage {
                Button(role: .destructive) {
                    model.requestRemovePage(index)
                } label: {
                    Text("このページを削除…", bundle: .module)
                }
            }
        }
        .dropDestination(for: SettingsDragItem.self) { items, _ in
            // マスをページの見出しに落とすと、そのページの空きマスへ移す
            guard let item = items.first else { return false }
            return model.handleDrop(item.payload, ontoPage: index)
        }
    }
}

/// ページの名前の欄（吹き出し）。Return で決め、Esc でやめる。空にすると「ページ 2」に戻る
struct SettingsPageNameEditor: View {
    let model: SettingsModel
    let index: Int
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(model: SettingsModel, index: Int, name: String) {
        self.model = model
        self.index = index
        _text = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ページの名前", bundle: .module)
                .font(.system(size: 12, weight: .semibold))
            TextField(text: $text, prompt: Text(String(localized: "ページ \(index + 1)", bundle: .module))) {
                Text("ページの名前", bundle: .module)
            }
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit { model.renamePage(index, to: text) }
            .onExitCommand { model.renamingPage = nil }
            Text("「デバッグ」「Git」のように、何のページかを付けます。Nonet のメニューのいちばん上の一覧にも出ます。空にすると「ページ \(index + 1)」に戻ります。", bundle: .module)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button {
                    model.renamingPage = nil
                } label: {
                    Text("キャンセル", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    model.renamePage(index, to: text)
                } label: {
                    Text("決定", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 260)
        .onAppear { isFocused = true }
    }
}

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
        .sheet(isPresented: $model.isAddingProfile) {
            SettingsAddProfileSheet(model: model)
        }
    }
}

// MARK: - サイドバー

struct SettingsSidebar: View {
    let model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { model.selectedProfile.id }, set: { model.selectProfile($0) })) {
                Section {
                    globalRow
                        .tag(model.configuration.globalProfile.id)
                } header: {
                    Text("プロファイル", bundle: .module)
                }
                Section {
                    ForEach(model.appProfiles) { profile in
                        SettingsProfileRow(profile: profile)
                            .tag(profile.id)
                            .contextMenu { contextMenu(for: profile) }
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

    @ViewBuilder
    private func contextMenu(for profile: Profile) -> some View {
        Button {
            model.setProfileEnabled(profile.id, !profile.isEnabled)
        } label: {
            if profile.isEnabled {
                Text("無効にする", bundle: .module)
            } else {
                Text("有効にする", bundle: .module)
            }
        }
        Button {
            Task { await model.exportProfiles([profile], suggestedName: profile.name) }
        } label: {
            Text("このプロファイルを書き出す…", bundle: .module)
        }
        Divider()
        Button(role: .destructive) {
            model.requestDeleteProfile(profile.id)
        } label: {
            Text("削除…", bundle: .module)
        }
    }
}

struct SettingsProfileRow: View {
    let profile: Profile

    var body: some View {
        HStack(spacing: 8) {
            CellIconView(.app(bundleID: profile.app?.bundleID ?? ""), size: 14)
                .saturation(profile.isEnabled ? 1 : 0)
                .opacity(profile.isEnabled ? 1 : 0.45)
                .accessibilityHidden(true)
            Text(profile.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(profile.isEnabled ? Color.primary : Color.secondary)
            Spacer(minLength: 4)
            if !profile.isEnabled {
                Text("オフ", bundle: .module)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(Capsule(style: .circular).strokeBorder(Color.secondary.opacity(0.5)))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(profile.isEnabled ? "" : String(localized: "無効", bundle: .module))
    }
}

// MARK: - 中央

struct SettingsEditorCenter: View {
    let model: SettingsModel

    var body: some View {
        let profile = model.selectedProfile
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                // 名前が長くて入らないときは、スイッチの説明を省いて名前に場所を譲る（説明はヘルプと VoiceOver に残す）
                ViewThatFits(in: .horizontal) {
                    header(profile, showsToggleLabel: true)
                    header(profile, showsToggleLabel: false)
                }
                Text(description(of: profile))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsPageBar(model: model)
            SettingsGridView(model: model)
                .opacity(profile.isEnabled ? 1 : 0.55)
            footer
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private func header(_ profile: Profile, showsToggleLabel: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(profile.name)
                .font(.system(size: 22, weight: .bold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if !profile.isGlobal {
                let title = String(localized: "このプロファイルを使う", bundle: .module)
                let toggle = Toggle(isOn: Binding(get: { profile.isEnabled }, set: { model.setProfileEnabled(profile.id, $0) })) {
                    Text(title)
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(title)
                Group {
                    if showsToggleLabel {
                        toggle
                    } else {
                        toggle.labelsHidden()
                    }
                }
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let message = model.gridMessage {
            SettingsNote(text: message, symbol: "exclamationmark.triangle", isWarning: true)
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text("マスを選んで右側で設定。ドラッグで入れ替え、Delete で空にする", bundle: .module)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(verbatim: "3×3")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private func description(of profile: Profile) -> String {
        if profile.isGlobal {
            return String(localized: "プロファイルの無いアプリで使う9マス", bundle: .module)
        }
        if !profile.isEnabled {
            return String(localized: "無効になっています。\(profile.name) でもグローバルを使います", bundle: .module)
        }
        return String(localized: "\(profile.name) が前面にあるときに使う9マス", bundle: .module)
    }
}

/// ページの切り替え（最大3）と、メニューから割り当て
struct SettingsPageBar: View {
    let model: SettingsModel

    var body: some View {
        // 窓が狭いときは「メニューから割り当て」をアイコンだけに、それでも入らなければページの名前を数字だけにする
        ViewThatFits(in: .horizontal) {
            bar(compactPages: false, compactMenuButton: false)
            bar(compactPages: false, compactMenuButton: true)
            bar(compactPages: true, compactMenuButton: true)
        }
    }

    private func bar(compactPages: Bool, compactMenuButton: Bool) -> some View {
        let profile = model.selectedProfile
        return HStack(spacing: 6) {
            ForEach(profile.pages.indices, id: \.self) { index in
                pageButton(
                    index,
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
            if model.canRemovePage {
                Button {
                    model.requestRemovePage(model.pageIndex)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "このページを削除", bundle: .module))
                .accessibilityLabel(String(localized: "このページを削除", bundle: .module))
            }
            Spacer(minLength: 8)
            menuToggle(compact: compactMenuButton)
        }
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

    private func pageButton(_ index: Int, isSelected: Bool, compact: Bool) -> some View {
        let title = String(localized: "ページ \(index + 1)", bundle: .module)
        return Button {
            model.selectPage(index)
        } label: {
            Text(compact ? "\(index + 1)" : title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, compact ? 8 : 10)
                .padding(.vertical, 4)
                .frame(minWidth: 26)
                .foregroundStyle(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                .background(Capsule(style: .circular).fill(isSelected ? Color.primary : Color.clear))
                .overlay(Capsule(style: .circular).strokeBorder(isSelected ? Color.clear : SettingsPalette.cellBorder))
                .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
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

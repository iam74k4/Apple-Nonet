// 担当: ui-settings
// 「プロファイルを整理…」のシート。初めて開いたときにプリセットのプロファイルがたくさん入るので、
// 使わないアプリのものにチェックを付けて、1回の確認でまとめて消せるようにする（控えは1つ、⌘Z で全部戻る）
import NonetCore
import SwiftUI

struct SettingsProfileCleanupSheet: View {
    let model: SettingsModel
    @State private var selection: Set<UUID> = []
    @State private var isConfirming = false

    var body: some View {
        let profiles = model.appProfiles
        let missing = Self.missingProfileIDs(profiles, installed: model.installedApps)
        // 選んだ後に消えたもの（ほかで消した）は数えない
        let chosen = selection.intersection(profiles.map(\.id))
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.cleanupSheet.title", defaultValue: "プロファイルを整理", bundle: .module))
                .font(.headline)
            Text("使わないアプリのプロファイルにチェックを付けて、まとめて削除します。グローバルのマスは残ります。削除した後も ⌘Z で元に戻せます。", bundle: .module)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(profiles) { profile in
                    Toggle(isOn: binding(for: profile.id)) {
                        row(profile, isMissing: missing.contains(profile.id))
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 280)
            HStack(spacing: 8) {
                Button {
                    selection = Set(profiles.map(\.id))
                } label: {
                    Text("すべて選択", bundle: .module)
                }
                .disabled(chosen.count == profiles.count)
                if !missing.isEmpty {
                    Button {
                        selection.formUnion(missing)
                    } label: {
                        Text("見つからないアプリを選択", bundle: .module)
                    }
                    .help(String(localized: "この Mac で見つからないアプリのプロファイルにチェックを付けます", bundle: .module))
                }
                Button {
                    selection = []
                } label: {
                    Text("選択を解除", bundle: .module)
                }
                .disabled(chosen.isEmpty)
                Spacer(minLength: 8)
            }
            .controlSize(.small)
            HStack {
                Spacer()
                Button(role: .cancel) {
                    model.isCleaningUpProfiles = false
                } label: {
                    Text("キャンセル", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    isConfirming = true
                } label: {
                    Text("\(chosen.count)個を削除…", bundle: .module)
                }
                .disabled(chosen.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 540)
        .onAppear { model.reloadInstalledApps() }
        .alert(
            String(localized: "\(chosen.count)個のプロファイルを削除しますか？", bundle: .module, locale: .nonetUI),
            isPresented: $isConfirming
        ) {
            Button(role: .destructive) {
                model.isCleaningUpProfiles = false
                model.deleteProfiles(chosen)
            } label: {
                Text("削除", bundle: .module)
            }
            Button(role: .cancel) {} label: {
                Text("キャンセル", bundle: .module)
            }
        } message: {
            Text("選んだプロファイルのマスもすべて削除します。⌘Z で元に戻せます。", bundle: .module)
        }
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { isOn in
                if isOn {
                    selection.insert(id)
                } else {
                    selection.remove(id)
                }
            }
        )
    }

    private func row(_ profile: Profile, isMissing: Bool) -> some View {
        HStack(spacing: 8) {
            CellIconView(.app(bundleID: profile.app?.bundleID ?? ""), size: 16)
                .accessibilityHidden(true)
            Text(profile.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if isMissing {
                SettingsBadge(text: String(localized: "見つからない", bundle: .module))
            }
            if let badge = SettingsProfileRow.badge(profile.mode) {
                SettingsBadge(text: badge)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// この Mac で見つからないアプリのプロファイル。アプリの一覧をまだ読んでいなければ（空なら）、どれも数えない
    static func missingProfileIDs(_ profiles: [Profile], installed: [AppReference]) -> Set<UUID> {
        guard !installed.isEmpty else { return [] }
        // bundle ID は大文字と小文字を区別しない（NonetConfiguration と同じ）
        func key(_ bundleID: String) -> String { bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let installedIDs = Set(installed.map { key($0.bundleID) })
        return Set(profiles.filter { profile in
            guard let app = profile.app else { return false }
            return !installedIDs.contains(key(app.bundleID))
        }.map(\.id))
    }
}

/// 一覧の右の小さな印（「オフ」「グローバル」「見つからない」）
struct SettingsBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(Capsule(style: .circular).strokeBorder(Color.secondary.opacity(0.5)))
    }
}

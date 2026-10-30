// 担当: ui-settings
// 「以前の設定に戻す…」: Backups フォルダの控え（新しいものから10個）を並べ、選んだ控えの設定に戻す
import NonetCore
import SwiftUI

/// 一般の「書き出しと読み込み」に置くボタン（押すと控えの一覧を出す）
struct SettingsRestoreBackupButton: View {
    let model: SettingsModel

    var body: some View {
        Button {
            model.showBackups()
        } label: {
            Text("以前の設定に戻す…", bundle: .module)
        }
        .help(String(localized: "削除や読み込みの前などに残した控えから、以前の設定に戻します", bundle: .module))
    }
}

struct SettingsBackupsSheet: View {
    let model: SettingsModel
    @State private var selection: String?
    @State private var confirming: ConfigurationBackup?

    var body: some View {
        let entries = model.backupEntries
        VStack(alignment: .leading, spacing: 12) {
            Text("以前の設定に戻す", bundle: .module)
                .font(.headline)
            Text("Nonet は、設定を変えている間（1時間に1回まで）と、プロファイルやページの削除・読み込み・プリセットに戻す前に、その時点の設定を控えておきます。新しいものから\(ConfigurationStore.maxBackups)個まで残します。", bundle: .module)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if entries.isEmpty {
                Text("まだ控えがありません", bundle: .module)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries, selection: $selection) { entry in
                    row(entry)
                        .tag(entry.id)
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
            }
            HStack {
                Spacer()
                Button(role: .cancel) {
                    model.isShowingBackups = false
                } label: {
                    Text("キャンセル", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    confirming = entries.first { $0.id == selection }?.backup
                } label: {
                    Text("戻す…", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!entries.contains { $0.id == selection && $0.appProfileCount != nil })
            }
        }
        .padding(20)
        .frame(width: 480, height: 420)
        // 一覧のシートの上に出す（設定の窓の確認は、シートが開いている間は出せない）
        .alert(
            confirming.map { String(localized: "\(SettingsText.backupDate($0.date))の設定に戻しますか？", bundle: .module) } ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { backup in
            Button(role: .destructive) {
                model.restoreBackup(backup)
            } label: {
                Text("この設定に戻す", bundle: .module)
            }
            Button(role: .cancel) {
                confirming = nil
            } label: {
                Text("キャンセル", bundle: .module)
            }
        } message: { _ in
            Text("今のプロファイルと設定は、この控えの中身に置き換わります。今の設定も「以前の設定に戻す」に残すので、後で戻せます。", bundle: .module)
        }
    }

    private func row(_ entry: SettingsBackupEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(SettingsText.backupDate(entry.backup.date))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                Spacer(minLength: 8)
                Text(SettingsText.name(entry.backup.reason))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(SettingsText.backupSummary(entry))
                .font(.system(size: 11))
                .foregroundStyle(entry.appProfileCount == nil ? Color.orange : Color.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

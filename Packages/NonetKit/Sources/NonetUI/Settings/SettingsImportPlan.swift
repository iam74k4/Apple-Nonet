// 担当: ui-settings
// プロファイルの読み込みを、実際に設定へ入れる前に写しで試した結果。置き換わるものや、何かを実行するマスがあれば先に確かめる
import Foundation
import NonetCore

struct SettingsImportPlan: Identifiable, Equatable {
    /// 読み込む前に中身を見せるマスと、それがあるプロファイルの名前
    struct ReviewedCell: Equatable {
        var profileName: String
        var cell: Cell
    }

    let id = UUID()
    /// 読み込むファイルの名前（確かめるときに出す。1行にして長ければ切る）
    var fileName: String
    /// 読み込む中身（メニュー項目の長いショートカットは除いたもの）
    var document: ConfigurationStore.ImportedProfiles
    /// 写しに読み込んだときの結果
    var result: NonetConfiguration.ImportResult
    /// 置き換わる自分のアプリのプロファイルの名前（設定の並び順）
    var replacedNames: [String]
    /// 読み込まれるプロファイルの、スクリプト・Return を押すか長いキー入力・Mac の中のファイルを開く URL のマス（ファイルの並び順）。
    /// どれもその人の権限で動くので、何も置き換わらなくても読み込む前に中身を見せて確かめる
    var reviewedCells: [ReviewedCell]

    init(document: ConfigurationStore.ImportedProfiles, configuration: NonetConfiguration, fileName: String) {
        self.fileName = SettingsText.singleLine(fileName, limit: SettingsText.importFileNameLimit)
        let document = Self.withoutLongMenuShortcuts(document)
        self.document = document
        var preview = configuration
        result = preview.importProfiles(document)
        let replacedIDs = Set(Self.importedApps(in: document).compactMap { app in
            Self.existingProfile(for: app, in: configuration)?.id
        })
        replacedNames = configuration.profiles.filter { replacedIDs.contains($0.id) }.map(\.name)
        reviewedCells = Self.usedProfiles(in: document).flatMap { profile in
            profile.pages.flatMap { page in
                page.cells.compactMap { cell in
                    cell.flatMap { Self.needsReview($0.action) ? ReviewedCell(profileName: profile.name, cell: $0) : nil }
                }
            }
        }
    }

    /// 今の設定を上書きする（グローバルのページか、同じアプリのプロファイル）
    var replacesExisting: Bool { result.replacedGlobal || !replacedNames.isEmpty }

    /// 新しく加わるアプリのプロファイルがある
    var addsProfiles: Bool { result.added > 0 }

    /// 読み込まれるプロファイルに、中身を見せるマスがある
    var hasReviewedCells: Bool { !reviewedCells.isEmpty }

    /// 読み込む前に確かめる（置き換わるものがあるか、何かを実行するマスがある）
    var needsConfirmation: Bool { replacesExisting || hasReviewedCells }

    /// 置き換えるものを除いた中身（新しいアプリのプロファイルだけ加えるとき）。設定はその時点のもので決める
    func newProfilesOnly(in configuration: NonetConfiguration) -> ConfigurationStore.ImportedProfiles {
        let profiles = document.profiles.filter { profile in
            guard let app = profile.app else { return false }
            return Self.existingProfile(for: app, in: configuration) == nil
        }
        return ConfigurationStore.ImportedProfiles(profiles: profiles, unreadableCount: document.unreadableCount)
    }

    /// 読み込みで実際に使われるプロファイルが、スクリプトのマスを含む（読み込んだ後の知らせ）
    static func containsScripts(in document: ConfigurationStore.ImportedProfiles) -> Bool {
        containsScripts(usedProfiles(in: document))
    }

    static func containsScripts(_ profiles: [Profile]) -> Bool {
        profiles.contains { profile in
            profile.pages.contains { page in
                page.cells.contains { cell in
                    if case .script = cell?.action { return true }
                    return false
                }
            }
        }
    }

    // MARK: 中身を見せるマス

    /// 読み込む前に中身を見せるアクション。スクリプト、Return を押すか設定画面で入れられるより長いキー入力
    /// （コマンドを打って実行できる）、Mac の中のファイルを開く URL（.command や .app も開ける）
    static func needsReview(_ action: Action) -> Bool {
        switch action {
        case .script:
            true
        case .keystroke(let keys):
            keys.chords.count > SettingsKeyRecorder.maximumChords || pressesReturn(keys)
        case .openURL(let url):
            opensLocalFile(url.url)
        case .launchApp, .shortcut, .menuItem, .ai:
            false
        }
    }

    /// Return（テンキーの Enter を含む）を押す
    static func pressesReturn(_ keys: KeySequence) -> Bool {
        keys.chords.contains { chord in
            switch chord.key {
            case .special(let key):
                key == .returnKey
            case .keyCode(let code):
                // kVK_Return・kVK_ANSI_KeypadEnter
                code == 0x24 || code == 0x4C
            case .character(let character):
                character.unicodeScalars.contains { $0 == "\r" || $0 == "\n" || $0 == "\u{3}" }
            }
        }
    }

    /// / や ~ で始まるか file: の URL（開くときにファイルの場所として扱う。URLNormalizer と同じ決まり）
    static func opensLocalFile(_ url: String) -> Bool {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("~") || (text.hasPrefix("/") && !text.hasPrefix("//")) {
            return true
        }
        return text.lowercased().hasPrefix("file:")
    }

    /// メニュー項目のショートカットは1打だけ残す。メニューから読んだものは必ず1打なので、それより長いものは
    /// メニューを押すように見せて任意のキーを打つためのもの。捨てても、メニューを押して同じ項目を選べる
    static func withoutLongMenuShortcuts(_ document: ConfigurationStore.ImportedProfiles) -> ConfigurationStore.ImportedProfiles {
        var document = document
        for profile in document.profiles.indices {
            for page in document.profiles[profile].pages.indices {
                for slot in document.profiles[profile].pages[page].cells.indices {
                    guard case .menuItem(var menu)? = document.profiles[profile].pages[page].cells[slot]?.action,
                          let keys = menu.keyEquivalent, keys.chords.count != 1 else { continue }
                    menu.keyEquivalent = nil
                    document.profiles[profile].pages[page].cells[slot]?.action = .menuItem(menu)
                }
            }
        }
        return document
    }

    // MARK: 読み込みの決まり

    /// 読み込みで使われるプロファイル。グローバルや同じアプリが重なっていれば最初のものだけ、bundle ID の無いアプリは除く
    /// （NonetConfiguration.importProfiles と同じ決まり）
    static func usedProfiles(in document: ConfigurationStore.ImportedProfiles) -> [Profile] {
        var seen = Set<String>()
        var hasGlobal = false
        return document.profiles.filter { profile in
            guard let app = profile.app else {
                defer { hasGlobal = true }
                return !hasGlobal
            }
            let key = bundleIDKey(app.bundleID)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    /// ファイルの中のアプリ。同じアプリが重なっていれば最初のものだけ（読み込みと同じ決まり）
    private static func importedApps(in document: ConfigurationStore.ImportedProfiles) -> [AppReference] {
        usedProfiles(in: document).compactMap(\.app)
    }

    /// 有効・無効にかかわらず、同じアプリのプロファイル（読み込みはこれを置き換える）
    private static func existingProfile(for app: AppReference, in configuration: NonetConfiguration) -> Profile? {
        let key = bundleIDKey(app.bundleID)
        guard !key.isEmpty else { return nil }
        return configuration.profiles.first { $0.app.map { bundleIDKey($0.bundleID) == key } == true }
    }

    /// bundle ID は大文字と小文字を区別しない（NonetConfiguration と同じ）
    private static func bundleIDKey(_ bundleID: String) -> String {
        bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// 担当: presets
// プリセットを書くための部品と、プリセットで使うアプリの参照。
// プリセットのショートカットは、各社の公式ドキュメントに載っている macOS の既定のキー割り当てだけを使う。
// キーの文字は US と JIS のどちらでも修飾キーなしで入力できるもの（英数字と - , . / ; [ ]）に限る。
// .character は現在のキー配列から修飾キーなしでその文字が出るキーを探すので、
// JIS で ⇧ が要る \ ` = ' などは送れない（PresetLibraryTests で確かめている）。
//
// 中央は指がいちばん置きやすく、迷った指が止まるマス。AI（Apple Intelligence）や Claude Code のように
// Mac によっては動かないアクションは、使えない Mac では入れず、中央にはそのアプリの代わりのマスを置く（PresetCapabilities）。
// Claude Code は押し間違えるとターミナルのウインドウが開くので、使える Mac でも中央には置かない
//
// 押し間違えると困るマス（相手に見える・送ってしまう・取り消せない・時間を失う）は、少し長く止めてから実行する
// （PresetBuilder.holdBeforeRunning。Cell.requiresHold）。そのマスでふつうより長く指を止めてから離すと実行する。
// 会議のミュートは、咳や物音ですぐに切り替えたいので付けない。開くだけのもの（返信・コミットのシート・共有しない AirDrop の窓）にも付けない
import Foundation

/// プリセットの中身。アプリごとのデータは PresetData+*.swift に分けてある
enum PresetData {}

/// プリセットを組み立てる近道。表示名は日本語で書き、ここで .module からローカライズする
enum PresetBuilder {
    /// 中央のマスの位置
    static let centerIndex = 4

    /// 文字列カタログへの抽出は String.LocalizationValue の型で行われるので、引数のリテラルもそのまま抽出される
    static func text(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: .module)
    }

    static func key(_ title: String.LocalizationValue, _ symbol: String, _ keys: KeySequence) -> Cell {
        Cell(title: text(title), icon: .symbol(symbol), action: .keystroke(keys))
    }

    /// Finder で選んでいるファイルへの操作
    static func file(_ title: String.LocalizationValue, _ symbol: String, _ action: FileAction) -> Cell {
        Cell(title: text(title), icon: .symbol(symbol), action: .file(action))
    }

    /// 範囲を選んで撮るスクリーンショット（macOS の ⇧⌘4）。出典: https://support.apple.com/en-us/102646
    static func captureArea() -> Cell {
        key("範囲を撮影", "rectangle.dashed", .key("4", [.shift, .command]))
    }

    static func launch(_ title: String.LocalizationValue, _ symbol: String, _ app: AppReference) -> Cell {
        Cell(title: text(title), icon: .symbol(symbol), action: .launchApp(LaunchAppAction(app: app)))
    }

    static func script(_ title: String.LocalizationValue, _ symbol: String, _ action: ScriptAction) -> Cell {
        Cell(title: text(title), icon: .symbol(symbol), action: .script(action))
    }

    /// 少し長く止めてから実行するマスにする（Cell.requiresHold）。押し間違えると相手に見える・送ってしまう・取り消せない・
    /// 時間を失う操作に使う。滑らせて通りかかっただけで離しても実行しない
    static func holdBeforeRunning(_ cell: Cell) -> Cell {
        var cell = cell
        cell.requiresHold = true
        return cell
    }

    /// 開発アプリの外側のマス。プロジェクトのフォルダで Claude Code を対話モードで開く。
    /// PROJECT_DIR は前面の書類から決まる（ScriptEnvironment）。決まらなければホームで開く。
    /// claude が見つからない Mac では入れない（そのマスは空ける）
    static func claudeCode(_ capabilities: PresetCapabilities) -> Cell? {
        guard capabilities.claudeCode else { return nil }
        return script("Claude Code", "sparkles", ScriptAction(source: #"cd "${PROJECT_DIR:-$HOME}" && claude"#, runMode: .terminal))
    }

    /// ブラウザのページ内検索（⌘F）。AI を使えない Mac では、ブラウザの中央に置く
    static func findOnPage() -> Cell {
        key("ページ内検索", "text.magnifyingglass", .key("f", .command))
    }

    /// 中央に AI を置く並び。cells の中央は AI のマス。
    /// AI を使えない Mac では、fallbackIndex のマスを中央へ移し、空いた元の位置に filler を入れる（ほかのマスの位置は変えない）。
    /// filler は AI を使える Mac には無い、そのアプリの9マスに入れそびれていた操作にする
    static func aiCentered(_ cells: [Cell?], fallbackIndex: Int, filler: Cell, _ capabilities: PresetCapabilities) -> [Cell?] {
        guard !capabilities.appleIntelligence else { return cells }
        var cells = cells
        cells[centerIndex] = cells[fallbackIndex]
        cells[fallbackIndex] = filler
        return cells
    }

    /// 選択中の文章を要約して HUD の位置に出す。読むだけの画面（ブラウザ・受信メール・チャット）向け
    static func summarize() -> Cell {
        ai("要約", "sparkles", AIAction(
            prompt: text("次の文章を、要点がわかるように日本語で3行以内に要約してください。要約だけを返してください。"),
            output: .showResult
        ))
    }

    /// 選択中の文章を翻訳して HUD の位置に出す。日本語なら英語に、それ以外は日本語にする
    static func translate() -> Cell {
        ai("翻訳", "character.bubble", AIAction(
            prompt: text("次の文章を翻訳してください。日本語なら自然な英語に、それ以外の言語なら自然な日本語に訳し、訳文だけを返してください。"),
            output: .showResult
        ))
    }

    /// 選択中の文章を直して置き換える。自分で書いている画面（メモ・ドキュメント）向け
    static func proofread() -> Cell {
        ai("校正", "text.badge.checkmark", AIAction(
            prompt: text("次の文章の誤字脱字と不自然な表現を直してください。意味と文体は変えず、直した文章だけを返してください。"),
            output: .replaceSelection
        ))
    }

    private static func ai(_ title: String.LocalizationValue, _ symbol: String, _ action: AIAction) -> Cell {
        Cell(title: text(title), icon: .symbol(symbol), action: .ai(action))
    }

    /// 1ページ9マスのプリセット。summary には実際に入っているマスの数を渡す
    static func preset(
        _ app: AppReference,
        category: String.LocalizationValue,
        cells: [Cell?],
        summary: (Int) -> String.LocalizationValue
    ) -> AppPreset {
        preset(app, category: category, pages: [Page(cells: cells)], summary: summary)
    }

    /// 複数ページのプリセット。summary には、全部のページに入っているマスの数を渡す
    static func preset(
        _ app: AppReference,
        category: String.LocalizationValue,
        pages: [Page],
        summary: (Int) -> String.LocalizationValue
    ) -> AppPreset {
        let count = pages.flatMap(\.cells).compactMap { $0 }.count
        return AppPreset(app: app, category: text(category), summary: text(summary(count)), pages: pages)
    }
}

/// プリセットとランチャーで使うアプリ。bundleID はインストール済みの Info.plist か
/// Homebrew の cask 定義（formulae.brew.sh/api/cask/<名前>.json）で確かめたもの
enum KnownApp {
    // Apple のアプリ（名前は日本語の表示名。英語はローカライズで "Mail" などにする）
    static var mail: AppReference { apple("com.apple.mail", "メール") }
    static var calendar: AppReference { apple("com.apple.iCal", "カレンダー") }
    static var notes: AppReference { apple("com.apple.Notes", "メモ") }
    static var safari: AppReference { AppReference(bundleID: "com.apple.Safari", name: "Safari") }
    static var terminal: AppReference { apple("com.apple.Terminal", "ターミナル") }
    static var finder: AppReference { AppReference(bundleID: "com.apple.finder", name: "Finder") }
    static var messages: AppReference { apple("com.apple.MobileSMS", "メッセージ") }
    static var music: AppReference { apple("com.apple.Music", "ミュージック") }
    static var reminders: AppReference { apple("com.apple.reminders", "リマインダー") }
    static var photos: AppReference { apple("com.apple.Photos", "写真") }
    static var systemSettings: AppReference { apple("com.apple.systempreferences", "システム設定") }
    static var maps: AppReference { apple("com.apple.Maps", "マップ") }
    static var preview: AppReference { apple("com.apple.Preview", "プレビュー") }
    static var faceTime: AppReference { AppReference(bundleID: "com.apple.FaceTime", name: "FaceTime") }
    static var appStore: AppReference { AppReference(bundleID: "com.apple.AppStore", name: "App Store") }
    static var xcode: AppReference { AppReference(bundleID: "com.apple.dt.Xcode", name: "Xcode") }
    // iWork（bundleID は /Applications の Info.plist、14.5 で確認）
    static var keynote: AppReference { AppReference(bundleID: "com.apple.iWork.Keynote", name: "Keynote") }
    static var pages: AppReference { AppReference(bundleID: "com.apple.iWork.Pages", name: "Pages") }
    static var numbers: AppReference { AppReference(bundleID: "com.apple.iWork.Numbers", name: "Numbers") }
    /// Mac App Store 専売（itunes.apple.com/lookup?id=424389933 の bundleId で確認）
    static var finalCut: AppReference { AppReference(bundleID: "com.apple.FinalCut", name: "Final Cut Pro") }

    // ほかの会社のアプリ（製品名なので訳さない）
    static var chrome: AppReference { AppReference(bundleID: "com.google.Chrome", name: "Google Chrome") }
    static var arc: AppReference { AppReference(bundleID: "company.thebrowser.Browser", name: "Arc") }
    static var dia: AppReference { AppReference(bundleID: "company.thebrowser.dia", name: "Dia") }
    static var edge: AppReference { AppReference(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge") }
    static var firefox: AppReference { AppReference(bundleID: "org.mozilla.firefox", name: "Firefox") }
    static var claude: AppReference { AppReference(bundleID: "com.anthropic.claudefordesktop", name: "Claude") }
    /// 2026年7月に Codex と統合された ChatGPT。以前の com.openai.chat は「ChatGPT Classic」になった
    static var chatGPT: AppReference { AppReference(bundleID: "com.openai.codex", name: "ChatGPT") }
    /// 以前の ChatGPT。今も更新が続き、新しいアプリと並べて入れておける。新しいアプリは別の大きなダウンロードなので、
    /// こちらだけの Mac も多い（https://help.openai.com/en/articles/20001276 、
    /// formulae.brew.sh/api/cask/chatgpt-classic.json の「ChatGPT Classic.app」）
    static var chatGPTClassic: AppReference { AppReference(bundleID: "com.openai.chat", name: "ChatGPT Classic") }
    static var slack: AppReference { AppReference(bundleID: "com.tinyspeck.slackmacgap", name: "Slack") }
    static var notion: AppReference { AppReference(bundleID: "notion.id", name: "Notion") }
    static var figma: AppReference { AppReference(bundleID: "com.figma.Desktop", name: "Figma") }
    static var vsCode: AppReference { AppReference(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code") }
    static var cursor: AppReference { AppReference(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor") }
    static var zoom: AppReference { AppReference(bundleID: "us.zoom.xos", name: "Zoom") }
    /// 新しい Teams（2.x）。旧 Teams（com.microsoft.teams）は 2024 年に提供が終わった
    static var teams: AppReference { AppReference(bundleID: "com.microsoft.teams2", name: "Microsoft Teams") }
    static var outlook: AppReference { AppReference(bundleID: "com.microsoft.Outlook", name: "Microsoft Outlook") }
    static var word: AppReference { AppReference(bundleID: "com.microsoft.Word", name: "Microsoft Word") }
    static var excel: AppReference { AppReference(bundleID: "com.microsoft.Excel", name: "Microsoft Excel") }
    static var powerPoint: AppReference { AppReference(bundleID: "com.microsoft.Powerpoint", name: "Microsoft PowerPoint") }
    static var spotify: AppReference { AppReference(bundleID: "com.spotify.client", name: "Spotify") }
    static var line: AppReference { AppReference(bundleID: "jp.naver.line.mac", name: "LINE") }
    static var discord: AppReference { AppReference(bundleID: "com.hnc.Discord", name: "Discord") }
    static var obsidian: AppReference { AppReference(bundleID: "md.obsidian", name: "Obsidian") }
    /// Homebrew の cask が無く、Adobe の文書にも載っていない。MacScripter などの投稿で製品版・ベータ版とも同じと確かめた
    /// （リリースの前に、インストール済みの Photoshop で `osascript -e 'id of app "Adobe Photoshop 2026"'` を確かめる。docs/release.md）
    static var photoshop: AppReference { AppReference(bundleID: "com.adobe.Photoshop", name: "Adobe Photoshop") }

    private static func apple(_ bundleID: String, _ name: String.LocalizationValue) -> AppReference {
        AppReference(bundleID: bundleID, name: PresetBuilder.text(name))
    }
}

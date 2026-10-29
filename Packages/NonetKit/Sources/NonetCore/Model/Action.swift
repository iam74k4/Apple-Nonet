// 担当: core-model（公開 API は契約。Codable の書式と summary の実装を担当する）
import Foundation

/// アプリを指す。bundleID で特定し、name は表示用
public struct AppReference: Codable, Hashable, Sendable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// マスを押したときに行うこと
public enum Action: Codable, Equatable, Sendable {
    /// 前面アプリにキーを送る
    case keystroke(KeySequence)
    /// アプリを起動する（起動中なら前面に出す）
    case launchApp(LaunchAppAction)
    case openURL(URLAction)
    case script(ScriptAction)
    /// ショートカット.app のショートカットを実行する
    case shortcut(ShortcutAction)
    /// アプリのメニュー項目を押す
    case menuItem(MenuItemAction)
    /// 端末内の言語モデルで、選択中のテキストを処理する（macOS 26 以降）
    case ai(AIAction)
}

public enum ActionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case keystroke, launchApp, openURL, script, shortcut, menuItem, ai
}

public struct LaunchAppAction: Codable, Equatable, Sendable {
    public var app: AppReference
    /// すでに前面にあるときは隠す（アプリ切り替えのように使う）
    public var hideIfFrontmost: Bool

    public init(app: AppReference, hideIfFrontmost: Bool = false) {
        self.app = app
        self.hideIfFrontmost = hideIfFrontmost
    }
}

public struct URLAction: Codable, Equatable, Sendable {
    public var url: String

    public init(url: String) {
        self.url = url
    }
}

public enum ScriptRunMode: String, Codable, CaseIterable, Sendable {
    /// 裏で実行し、失敗したときだけ知らせる
    case background
    /// ターミナルの新しいウィンドウで実行する（claude のような対話型のコマンド向け）
    case terminal
}

public struct ScriptAction: Codable, Equatable, Sendable {
    /// zsh のスクリプト。NONET_* と PROJECT_DIR の環境変数が使える（ScriptEnvironment）
    public var source: String
    public var runMode: ScriptRunMode
    /// background のときの制限時間（秒）
    public var timeout: Double

    public init(source: String, runMode: ScriptRunMode = .background, timeout: Double = 60) {
        self.source = source
        self.runMode = runMode
        self.timeout = timeout
    }
}

public struct ShortcutAction: Codable, Equatable, Sendable {
    /// ショートカット.app での名前
    public var name: String
    /// 選択中のテキストを入力として渡す
    public var passSelectedText: Bool

    public init(name: String, passSelectedText: Bool = false) {
        self.name = name
        self.passSelectedText = passSelectedText
    }
}

public struct MenuItemAction: Codable, Equatable, Sendable {
    /// nil なら前面アプリのメニューを押す
    public var app: AppReference?
    /// メニューバーからのタイトルの並び（例: ["オブジェクト", "自動レイアウトを追加"]）
    public var path: [String]
    /// メニューに表示されていたショートカット。対象アプリが前面ならこれを送るのが速い
    public var keyEquivalent: KeySequence?

    public init(app: AppReference? = nil, path: [String], keyEquivalent: KeySequence? = nil) {
        self.app = app
        self.path = path
        self.keyEquivalent = keyEquivalent
    }
}

public enum AIOutput: String, Codable, CaseIterable, Sendable {
    /// 選択中のテキストを結果で置き換える
    case replaceSelection
    case copyToClipboard
    /// HUD の位置に結果を表示する
    case showResult
}

public struct AIAction: Codable, Equatable, Sendable {
    /// 指示文。選択中のテキストは後ろに付けて渡す
    public var prompt: String
    public var output: AIOutput

    public init(prompt: String, output: AIOutput = .showResult) {
        self.prompt = prompt
        self.output = output
    }
}

extension Action {
    public var kind: ActionKind {
        switch self {
        case .keystroke: .keystroke
        case .launchApp: .launchApp
        case .openURL: .openURL
        case .script: .script
        case .shortcut: .shortcut
        case .menuItem: .menuItem
        case .ai: .ai
        }
    }

    /// HUD や設定画面に出す短い説明（例: "⌘B"、"Simulator"、"スクリプト"）
    public var summary: String {
        fatalError("未実装: core-model")
    }
}

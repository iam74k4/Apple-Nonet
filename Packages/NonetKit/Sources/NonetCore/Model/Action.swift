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
    public static let defaultTimeout: Double = 60
    /// 制限時間として受け付ける範囲（秒）。validated() はこの範囲に収める
    public static let timeoutRange: ClosedRange<Double> = 1...3600

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
        switch self {
        case .keystroke(let keys):
            keys.displayString
        case .launchApp(let action):
            action.app.nameOrBundleID
        case .openURL(let action):
            URLAction.displayHost(of: action.url) ?? String(localized: "URL", bundle: .module)
        case .script(let action):
            switch action.runMode {
            case .background: String(localized: "スクリプト", bundle: .module)
            case .terminal: String(localized: "ターミナル", bundle: .module)
            }
        case .shortcut(let action):
            action.name.trimmedNonEmpty ?? String(localized: "ショートカット", bundle: .module)
        case .menuItem(let action):
            action.path.last(where: { $0.trimmedNonEmpty != nil }) ?? String(localized: "メニュー項目", bundle: .module)
        case .ai:
            String(localized: "AI", bundle: .module)
        }
    }
}

extension Action {
    /// 範囲外の値を直したもの（スクリプトの制限時間）
    func validated() -> Action {
        guard case .script(var script) = self else { return self }
        let range = ScriptAction.timeoutRange
        script.timeout = script.timeout.isFinite
            ? min(max(script.timeout, range.lowerBound), range.upperBound)
            : ScriptAction.defaultTimeout
        return .script(script)
    }
}

extension AppReference {
    /// 名前が空なら bundleID
    var nameOrBundleID: String {
        name.trimmedNonEmpty ?? bundleID
    }
}

extension URLAction {
    /// 表示用のホスト名（"www." は省く）。ホストの無い URL はそのまま、空なら nil
    static func displayHost(of string: String) -> String? {
        guard let trimmed = string.trimmedNonEmpty else { return nil }
        var components = URLComponents(string: trimmed)
        if components?.scheme == nil {
            components = URLComponents(string: "https://" + trimmed)
        }
        guard let host = components?.host, !host.isEmpty else { return trimmed }
        if host.lowercased().hasPrefix("www."), host.count > 4 {
            return String(host.dropFirst(4))
        }
        return host
    }
}

extension String {
    /// 前後の空白を除いて空でなければ、除いた文字列
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Codable
// 書式は {"type": "<ActionKind>", ...中身のキー}。keystroke だけは {"type": "keystroke", "keys": [...]}。
// 既定値のある項目は無くても読み、知らない列挙値は既定値にする。知らない type は読めない（マスが空きになる）

extension Action {
    private enum CodingKeys: String, CodingKey {
        case type, keys
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch ActionKind(rawValue: type) {
        case .keystroke:
            self = .keystroke(try container.decode(KeySequenceCoding.self, forKey: .keys).sequence)
        case .launchApp:
            self = .launchApp(try LaunchAppAction(from: decoder))
        case .openURL:
            self = .openURL(try URLAction(from: decoder))
        case .script:
            self = .script(try ScriptAction(from: decoder))
        case .shortcut:
            self = .shortcut(try ShortcutAction(from: decoder))
        case .menuItem:
            self = .menuItem(try MenuItemAction(from: decoder))
        case .ai:
            self = .ai(try AIAction(from: decoder))
        case nil:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "未知のアクションの種類")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        // 中身は同じ階層に書く（JSONEncoder は同じ階層の keyed container を1つにまとめる）
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .type)
        switch self {
        case .keystroke(let keys):
            try container.encode(KeySequenceCoding(keys), forKey: .keys)
        case .launchApp(let action):
            try action.encode(to: encoder)
        case .openURL(let action):
            try action.encode(to: encoder)
        case .script(let action):
            try action.encode(to: encoder)
        case .shortcut(let action):
            try action.encode(to: encoder)
        case .menuItem(let action):
            try action.encode(to: encoder)
        case .ai(let action):
            try action.encode(to: encoder)
        }
    }
}

extension AppReference {
    private enum CodingKeys: String, CodingKey {
        case bundleID, name
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bundleID = try container.decode(String.self, forKey: .bundleID)
        self.init(bundleID: bundleID, name: container.decodeLossy(String.self, forKey: .name, default: bundleID))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleID, forKey: .bundleID)
        try container.encode(name, forKey: .name)
    }
}

extension LaunchAppAction {
    private enum CodingKeys: String, CodingKey {
        case app, hideIfFrontmost
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            app: try container.decode(AppReference.self, forKey: .app),
            hideIfFrontmost: container.decodeLossy(Bool.self, forKey: .hideIfFrontmost, default: false)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(app, forKey: .app)
        try container.encode(hideIfFrontmost, forKey: .hideIfFrontmost)
    }
}

extension URLAction {
    private enum CodingKeys: String, CodingKey {
        case url
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(url: try container.decode(String.self, forKey: .url))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
    }
}

extension ScriptAction {
    private enum CodingKeys: String, CodingKey {
        case source, runMode, timeout
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            source: try container.decode(String.self, forKey: .source),
            runMode: container.decodeLossy(ScriptRunMode.self, forKey: .runMode, default: .background),
            timeout: container.decodeLossy(Double.self, forKey: .timeout, default: ScriptAction.defaultTimeout)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(runMode, forKey: .runMode)
        try container.encode(timeout, forKey: .timeout)
    }
}

extension ShortcutAction {
    private enum CodingKeys: String, CodingKey {
        case name, passSelectedText
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            passSelectedText: container.decodeLossy(Bool.self, forKey: .passSelectedText, default: false)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(passSelectedText, forKey: .passSelectedText)
    }
}

extension MenuItemAction {
    private enum CodingKeys: String, CodingKey {
        case app, path, keyEquivalent
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // app を読み落とすと前面アプリのメニューを押してしまうので、読めなければマスごと読めないことにする
        let app = try container.decodeIfPresent(AppReference.self, forKey: .app)
        let path = try container.decode([String].self, forKey: .path)
        // キーが読めなくてもメニューをたどれば押せる
        let keys = container.decodeLossy(KeySequenceCoding?.self, forKey: .keyEquivalent, default: nil)
        self.init(app: app, path: path, keyEquivalent: keys?.sequence)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(app, forKey: .app)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(keyEquivalent.map(KeySequenceCoding.init), forKey: .keyEquivalent)
    }
}

extension AIAction {
    private enum CodingKeys: String, CodingKey {
        case prompt, output
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            prompt: try container.decode(String.self, forKey: .prompt),
            output: container.decodeLossy(AIOutput.self, forKey: .output, default: .showResult)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(output, forKey: .output)
    }
}

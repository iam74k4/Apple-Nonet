// 担当: ui-shell
// App の起動引数。テストできるように NonetUI に置く（--self-check 以外は App が DEBUG ビルドでだけ使う）
import Foundation

public struct ShellLaunchOptions: Equatable, Sendable {
    /// --self-check: 画面を出さずに動作の確認結果を JSON で出して終わる（すべてのビルド）
    public var selfCheck = false
    /// --config-dir <dir>: 設定の置き場所（試用の記録もメモリだけに置く）
    public var configDirectory: URL?
    /// --show-settings [profiles|general|license]
    public var settingsTab: SettingsTab?
    /// --show-onboarding
    public var showOnboarding = false
    /// --onboarding-step <welcome|apps|practice|done>: 初回の案内をその画面まで進めて出す（--show-onboarding も兼ねる）
    public var onboardingStep: String?
    /// --preview-hud: 最初のページの HUD を出したままにする
    public var previewHUD = false
    /// --preview-app <bundle ID>: --preview-hud で、前面のアプリの代わりにこのアプリのページを出す
    public var previewBundleID: String?
    /// --preview-backdrop <画像>: --preview-hud で、HUD の後ろに画面いっぱいに敷く絵（ガラスの HUD を決まった背景で撮る）
    public var previewBackdrop: URL?
    /// --demo: 販売ページ用のデモ動画を撮る（本物の操作のロジックと HUD で、何も実行しない。指の位置を示すトラックパッドの図を出す）
    public var demo = false
    /// --demo-app <bundle ID>: --demo で、前面のアプリの代わりにこのアプリのプロファイルを使う
    public var demoBundleID: String?
    /// --demo-backdrop <画像>: --demo で、画面いっぱいに敷く背景
    public var demoBackdrop: URL?
    /// --demo-script: --demo で、実機の指の代わりに台本どおりの指の動きを入れる（終わったらアプリを終える）
    public var demoScript = false
    /// --demo-start-file <パス>: --demo-script で、このファイルができてから台本を始め、終わったらこのファイルが消えるまで背景を出したままにする（録画が始まってから動かし、録画が止まってから終えるため）。付けなければすぐ始め、終わったら少し見せて終える
    public var demoStartFile: URL?
    /// --preview-toast: トーストを繰り返し出す
    public var previewToast = false
    /// --preview-result: 結果のパネルを出す
    public var previewResult = false
    /// --simulate-expired-trial: 20日前に試用を始めたことにする（保存はしない）
    public var simulateExpiredTrial = false
    /// --snapshot <dir>: 表示中のウィンドウを何度か PNG に書き出して終わる（画面の収録の許可が無くても見た目を確かめられる）
    public var snapshotDirectory: URL?

    public init() {}

    /// 先頭（実行ファイルのパス）は読まない。知らない引数（Xcode が渡す -NSDocumentRevisionsDebugMode など）は無視する
    public static func parse(_ arguments: [String]) -> ShellLaunchOptions {
        var options = ShellLaunchOptions()
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil
            switch argument {
            case "--self-check":
                options.selfCheck = true
            case "--config-dir":
                if let next, !next.hasPrefix("--") {
                    options.configDirectory = URL(fileURLWithPath: (next as NSString).expandingTildeInPath, isDirectory: true)
                    index += 1
                }
            case "--show-settings":
                if let next, let tab = SettingsTab(rawValue: next) {
                    options.settingsTab = tab
                    index += 1
                } else {
                    options.settingsTab = .profiles
                }
            case "--show-onboarding":
                options.showOnboarding = true
            case "--onboarding-step":
                if let next, !next.hasPrefix("--") {
                    options.onboardingStep = next
                    options.showOnboarding = true
                    index += 1
                }
            case "--preview-hud":
                options.previewHUD = true
            case "--demo":
                options.demo = true
            case "--demo-script":
                options.demo = true
                options.demoScript = true
            case "--demo-start-file":
                if let next, !next.hasPrefix("--") {
                    options.demoStartFile = URL(fileURLWithPath: (next as NSString).expandingTildeInPath)
                    index += 1
                }
            case "--demo-app":
                if let next, !next.hasPrefix("--") {
                    options.demoBundleID = next
                    index += 1
                }
            case "--demo-backdrop":
                if let next, !next.hasPrefix("--") {
                    options.demoBackdrop = URL(fileURLWithPath: (next as NSString).expandingTildeInPath)
                    index += 1
                }
            case "--preview-app":
                if let next, !next.hasPrefix("--") {
                    options.previewBundleID = next
                    index += 1
                }
            case "--preview-backdrop":
                if let next, !next.hasPrefix("--") {
                    options.previewBackdrop = URL(fileURLWithPath: (next as NSString).expandingTildeInPath)
                    index += 1
                }
            case "--preview-toast":
                options.previewToast = true
            case "--preview-result":
                options.previewResult = true
            case "--simulate-expired-trial":
                options.simulateExpiredTrial = true
            case "--snapshot":
                if let next, !next.hasPrefix("--") {
                    options.snapshotDirectory = URL(fileURLWithPath: (next as NSString).expandingTildeInPath, isDirectory: true)
                    index += 1
                }
            default:
                break
            }
            index += 1
        }
        return options
    }
}

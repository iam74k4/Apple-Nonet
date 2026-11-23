// 担当: presets（公開 API は契約）
import Foundation

/// プリセットを組み立てるときに見る、この Mac でできること。
/// 中央は指がいちばん置きやすいマスなので、この Mac で動かないアクションは置かない
public struct PresetCapabilities: Equatable, Hashable, Sendable {
    /// AI アクション（Apple Intelligence）を使えるか
    public var appleIntelligence: Bool
    /// 利用者のシェルで claude コマンド（Claude Code）が見つかるか
    public var claudeCode: Bool

    public init(appleIntelligence: Bool, claudeCode: Bool) {
        self.appleIntelligence = appleIntelligence
        self.claudeCode = claudeCode
    }

    /// どちらも使える。すべての種類のアクションが入る（設定の往復の確かめやテスト）
    public static let all = PresetCapabilities(appleIntelligence: true, claudeCode: true)
    /// どちらも使えない
    public static let none = PresetCapabilities(appleIntelligence: false, claudeCode: false)
    /// すべての組み合わせ
    static let allCombinations: [PresetCapabilities] = [
        .all,
        PresetCapabilities(appleIntelligence: true, claudeCode: false),
        PresetCapabilities(appleIntelligence: false, claudeCode: true),
        .none,
    ]
}

/// プリセットを組み立てるときに見る、この Mac の状態。本物は NonetPlatform の SystemPresetEnvironment
@MainActor
public protocol PresetEnvironmentProviding: AnyObject {
    /// 今わかっている、この Mac でできること。すぐに返る。claude をまだ調べ終えていなければ、見つからない扱い
    var capabilities: PresetCapabilities { get }
    /// claude を調べ終えるのを待ってから返す（長くても数秒。調べられなければ見つからない扱い）
    func resolvedCapabilities() async -> PresetCapabilities
    /// Dock に置いてある、インストール済みのアプリ（Dock の順）。読めなければ空
    func dockApps() -> [AppReference]
}

/// 決まった値を返す PresetEnvironmentProviding（テストやプレビュー、調べる手段が無いとき）
@MainActor
public final class FixedPresetEnvironment: PresetEnvironmentProviding {
    public var capabilities: PresetCapabilities
    public var dock: [AppReference]

    /// 既定値の引数（NonetServices などの init）からも作れるよう、メインアクターに限らない
    public nonisolated init(capabilities: PresetCapabilities = .all, dockApps: [AppReference] = []) {
        self.capabilities = capabilities
        dock = dockApps
    }

    public func resolvedCapabilities() async -> PresetCapabilities {
        capabilities
    }

    public func dockApps() -> [AppReference] {
        dock
    }
}

/// 「ページを追加」で選べるページの型（設定のページの「＋」）。どのプロファイルにも足せる。
/// 初回の設定に入るページを、消した後や前の版から使っている人も足せるようにする
public enum PageTemplate: CaseIterable, Hashable, Sendable {
    /// 空のページ
    case empty
    /// 「画面に置く」の9マス
    case windowPlacement
    /// 「ユーティリティ」の9マス
    case utilities
    /// 「メディア」の9マス（再生・音量・明るさ）
    case media

    /// メニューに出す名前。型のページは、そのページの名前と同じ
    public var title: String {
        switch self {
        case .empty: String(localized: "空のページ", bundle: .module)
        case .windowPlacement, .utilities, .media: makePage().name ?? ""
        }
    }

    /// 足すページ。マスの id は毎回新しくなる
    public func makePage() -> Page {
        switch self {
        case .empty: .empty
        case .windowPlacement: PresetLibrary.makeWindowPlacementPage()
        case .utilities: PresetLibrary.makeUtilityPage()
        case .media: PresetLibrary.makeMediaPage()
        }
    }
}

/// 初回起動で用意するアプリ別の9マス
public struct AppPreset: Identifiable, Sendable {
    public var app: AppReference
    /// 「開発」「デザイン」など（ローカライズ済み）
    public var category: String
    /// 「ビルド、テスト、Claude Code など9個」のような説明（ローカライズ済み）。入っているマスだけを挙げる
    public var summary: String
    public var pages: [Page]

    public init(app: AppReference, category: String, summary: String, pages: [Page]) {
        self.app = app
        self.category = category
        self.summary = summary
        self.pages = pages
    }

    public var id: String { app.bundleID }

    /// このプリセットからプロファイルを作る。マスの id は毎回振り直す
    public func makeProfile() -> Profile {
        let pages = pages.map { page in
            Page(cells: page.cells.map { cell in
                cell.map { Cell(title: $0.title, icon: $0.icon, action: $0.action, requiresHold: $0.requiresHold) }
            }, name: page.name, layout: page.layout)
        }
        return Profile(kind: .app(app), pages: pages)
    }
}

public enum PresetLibrary {
    /// 用意しているアプリのプリセット（AI も Claude Code も使える Mac のもの）。初回起動の「アプリを選ぶ」に出す順。
    /// 利用者の Mac に入れるときは apps(for:) で、その Mac でできることに合わせる
    public static var apps: [AppPreset] {
        apps(for: .all)
    }

    /// この Mac でできることに合わせたプリセット。使えないアクションは入れず、中央には代わりのマスを置く
    public static func apps(for capabilities: PresetCapabilities) -> [AppPreset] {
        // 初回の案内の「アプリを選ぶ」はこの順に並ぶので、誰でも使うもの（Finder・ブラウザ・メール・会議）を先に、
        // オフィス・ドキュメント・デザインと映像、開発の順にする
        [
            PresetData.finder,
            PresetData.safari(capabilities),
            PresetData.chrome(capabilities),
            PresetData.arc(capabilities),
            PresetData.mail(capabilities),
            PresetData.outlook(capabilities),
            PresetData.zoom,
            PresetData.teams(capabilities),
            PresetData.slack(capabilities),
            PresetData.excel,
            PresetData.word(capabilities),
            PresetData.powerPoint,
            PresetData.keynote,
            PresetData.pages(capabilities),
            PresetData.numbers,
            PresetData.notion(capabilities),
            PresetData.notes(capabilities),
            PresetData.obsidian(capabilities),
            PresetData.figma,
            PresetData.photoshop,
            PresetData.finalCut,
            PresetData.xcode(capabilities),
            PresetData.vsCode(capabilities),
            PresetData.cursor(capabilities),
            PresetData.terminal(capabilities),
        ]
    }

    /// bundleID の大文字・小文字は区別しない（Launch Services と同じ）。AI も Claude Code も使える Mac のもの
    public static func preset(forBundleID bundleID: String) -> AppPreset? {
        preset(forBundleID: bundleID, capabilities: .all)
    }

    /// この Mac でできることに合わせたプリセット
    public static func preset(forBundleID bundleID: String, capabilities: PresetCapabilities) -> AppPreset? {
        apps(for: capabilities).first { $0.app.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    /// グローバル（ランチャー）に並べるアプリの候補。優先順。
    /// 同じアプリの新旧（ChatGPT と ChatGPT Classic）はどちらも候補に含む。インストール済みかはこの全部で調べる
    public static var launcherCandidates: [AppReference] {
        PresetData.launcherEntries.map(\.app)
    }

    /// インストール済みの候補を優先順に9個ずつ並べたグローバルのプロファイル（最大 Profile.maxPages ページ）。
    /// 同じアプリの新旧が両方入っていれば新しい方だけ。1つも無ければ空の1ページ
    public static func makeGlobalProfile(installedBundleIDs: Set<String>) -> Profile {
        makeGlobalProfile(installedBundleIDs: installedBundleIDs, dockApps: [])
    }

    /// 「画面に置く」のページ。3×3 のマスが、そのまま画面の場所（初回の設定では、グローバルの最初のページ）
    public static func makeWindowPlacementPage() -> Page {
        Page(
            cells: WindowRegion.allCases.map { region in
                Cell(title: region.title, icon: .symbol(region.symbol), action: .placeWindow(PlaceWindowAction(region: region)))
            },
            name: PresetBuilder.text("画面に置く")
        )
    }

    /// 「メディア」のページ。真ん中が再生／一時停止、左右が前と次の曲、上下が音量、左下が消音、右の上下が明るさ。
    /// 「ページを追加」の型から足す（初回の設定には入れない）
    public static func makeMediaPage() -> Page {
        let cell = { (key: MediaKey) in Cell(title: key.title, icon: .symbol(key.symbol), action: .media(MediaAction(key: key))) }
        return Page(
            cells: [
                nil, cell(.volumeUp), cell(.brightnessUp),
                cell(.previous), cell(.playPause), cell(.next),
                cell(.mute), cell(.volumeDown), cell(.brightnessDown),
            ],
            name: PresetBuilder.text("メディア")
        )
    }

    /// 「ユーティリティ」のページ。撮影と収録・最近のスクショ・絵文字と記号・消音・画面を消す・画面をロック
    /// （初回の設定では、グローバルの2ページ目。PresetData.utilityPage）。マスの id は毎回新しくなる
    public static func makeUtilityPage() -> Page {
        PresetData.utilityPage
    }

    /// Dock のアプリを Dock の順に先に並べ、残りをインストール済みの候補の優先順で足したグローバルのプロファイル。
    /// dockApps はインストール済みのもの（PresetEnvironmentProviding.dockApps()）。空なら候補だけで並べる
    public static func makeGlobalProfile(installedBundleIDs: Set<String>, dockApps: [AppReference]) -> Profile {
        let cells = PresetData.launcherEntries(dockApps: dockApps, installedBundleIDs: installedBundleIDs)
            .prefix(Page.cellCount * Profile.maxPages)
            .map { entry in
                Cell(
                    title: entry.title,
                    icon: .app(bundleID: entry.app.bundleID),
                    action: .launchApp(LaunchAppAction(app: entry.app))
                )
            }
        let pages = stride(from: 0, to: cells.count, by: Page.cellCount).map { start in
            Page(cells: Array(cells[start..<min(start + Page.cellCount, cells.count)]))
        }
        return Profile(kind: .global, pages: pages.isEmpty ? [.empty] : pages)
    }
}

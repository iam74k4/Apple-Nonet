// 契約（変更は統合担当だけ）。macOS に触れる部分はすべてこの protocol の向こう側に置き、
// NonetController を偽物の実装でテストできるようにする。実装は NonetPlatform、HUD は NonetUI。
import Foundation

// MARK: - トラックパッド

/// トラックパッド上の1本の指。座標は 0〜1 で、x は左が 0、y は手前が 0
public struct TouchPoint: Equatable, Sendable {
    public var id: Int
    public var x: Double
    public var y: Double
    /// false は近接・離れかけなど、触れていない状態
    public var isTouching: Bool
    /// 接触の楕円の長径（MultitouchSupport の majorAxis。指先でおよそ 8〜15）。分からなければ nil。
    /// トラックパッドの図（デモ）で指の大きさを見せるのに使う
    public var majorAxis: Double?

    public init(id: Int, x: Double, y: Double, isTouching: Bool = true, majorAxis: Double? = nil) {
        self.id = id
        self.x = x
        self.y = y
        self.isTouching = isTouching
        self.majorAxis = majorAxis
    }
}

public struct TouchFrame: Equatable, Sendable {
    /// Scheduler.now と同じ時計の秒
    public var timestamp: TimeInterval
    public var points: [TouchPoint]
    /// 指が離れたフレームではなく、トラックパッドから続きが来なくなったので（切断・スリープ明け・別のトラックパッドに替わった）、
    /// 離れたことにしたフレーム。開いていれば何も実行せずに閉じる（光っていたマスで離したことにしない）
    public var isSynthesizedLift: Bool
    /// このフレームを受け取ったときのポインタの位置（主画面の左上が原点）。トラックパッドのスレッドで読む。
    /// メインスレッドが止まってフレームがまとめて届いても、それぞれのフレームの時刻のポインタでマスを選べるように。
    /// nil なら、届けたときの位置を使う（読めなかった・合成したフレーム・テスト）
    public var pointer: CGPoint?

    public init(timestamp: TimeInterval, points: [TouchPoint], isSynthesizedLift: Bool = false, pointer: CGPoint? = nil) {
        self.timestamp = timestamp
        self.points = points
        self.isSynthesizedLift = isSynthesizedLift
        self.pointer = pointer
    }

    public var touching: [TouchPoint] { points.filter(\.isTouching) }
}

@MainActor
public protocol TouchSource: AnyObject {
    /// マルチタッチのトラックパッドがあるか
    var isAvailable: Bool { get }
    /// メインスレッドで呼ばれる
    var onFrame: ((TouchFrame) -> Void)? { get set }
    func start() throws
    func stop()
}

// MARK: - キーボードとポインタ

public enum KeyboardEvent: Equatable, Sendable {
    /// 9マスを開いている（ポインタを抑止している）間に、キーや修飾キーが押された（そのキーは前面アプリに渡す）。
    /// トラックパッドに触れていない間に届いたマウスやホイールのイベントも同じ
    case interrupted
    /// トラックパッドのどこかを強く押し込み（強めのクリックの2段目）、そのまま forcePressHold だけ止めた。
    /// そのクリックはまだ前面アプリに渡していない（預かっている）。受け取ったら、9マスを開くかを決めて finishForcePress で答える
    case forcePressed
    /// 強めのクリックの2段目まで押し込んだ。hold 秒止めると .forcePressed が来る（その間、ポインタに輪を見せる）
    case forcePressStarted(hold: TimeInterval)
    /// 押し込んだが、止め終える前に離した・動かした（輪を消す。クリックは前面アプリに返した）
    case forcePressCancelled
}

/// キーボードとポインタのイベントタップ。9マスはトラックパッドを強く押し込んで開くので、キーボードは開いている間だけ見る。
/// 強く長押しで開けるとき（forcePressHold が nil でない）は、トラックパッドで押した左クリックを、強く押し込んで止めたかが分かるまで預かる
@MainActor
public protocol KeyboardMonitor: AnyObject {
    var cursorLock: CursorLockMethod { get set }
    /// true の間、ポインタの移動・クリック・スクロール・ジェスチャーを前面アプリに渡さず、キーボードも見る
    /// （キーや修飾キーが押されたら .interrupted を1回送る）。false の間はキーボードを見ない。
    /// 捨てた「押す」に対応する「離す」は、false に戻した後でも捨てる
    var isSuppressingPointer: Bool { get set }
    /// メインスレッドで呼ばれる
    var onEvent: ((KeyboardEvent) -> Void)? { get set }
    /// トラックパッドにいま指が触れているか（NonetController が指のフレームから知らせる）。
    /// 抑止中に、トラックパッドに触れていない間（離してから少し経った後）に届いた押す・スクロール・移動は、
    /// マウスやホイールのものとみなす。そのイベントは手を加えずに前面アプリに渡し、.interrupted を1回送る
    var isTrackpadTouched: Bool { get set }
    /// マウスやトラックパッドのボタンが、いま物理的に押されているか（どのボタンでも）
    var isMouseButtonDown: Bool { get }
    /// 強く押し込んでから、.forcePressed を送るまで止めておく秒数（ForcePress.hold）。nil の間はクリックを預からず、強く押しても何もしない
    /// （止めている・無効・許可なし・キーの記録中・「このアプリでは Nonet を使わない」アプリが前面 など、開けないとき）。
    /// 預かっている間に nil にしたら、預かったクリックは前面アプリに返す
    var forcePressHold: TimeInterval? { get set }
    /// .forcePressed への答え。opened なら（9マスを開いた・開かずに知らせた）預かったクリックを捨て、
    /// そのクリックの離すも捨てる（押したままの動きはボタンを押していない移動として渡す）。そうでなければ、クリックを前面アプリに返す
    func finishForcePress(opened: Bool)
    var isRunning: Bool { get }
    /// アクセシビリティの許可が無ければ NonetError.permissionDenied
    func start() throws
    func stop()
    /// isSuppressingPointer を false にする。dropsLateClicks なら、その直後の短い間に届くクリックの「押す」も捨てる
    /// （終わる直前に離れた指の「タップでクリック」が、抑止の後に遅れて届くことがあるため）
    func endPointerSuppression(dropsLateClicks: Bool)
    /// いまのポインタの位置（主画面の左上が原点、y が下向き）。分からなければ nil。
    /// 9マスを開いている間、ポインタはふだんどおり動き（前面のアプリには渡さない）、HUD の地図の上でポインタが乗っているマスを選ぶ
    var pointerLocation: CGPoint? { get }
    /// 抑止中に、ポインタを point（主画面の左上が原点、y が下向き）へ動かす。開いたときに一度だけ、地図の奥の外枠の帯の中央へ置く
    /// （画面の端で HUD の枠を寄せたとき）。抑止中でなければ何もしない
    func movePointer(to point: CGPoint)
}

extension KeyboardMonitor {
    /// 遅れて届くクリックを捨てない実装の既定
    public func endPointerSuppression(dropsLateClicks: Bool) {
        isSuppressingPointer = false
    }

    /// クリックを預からない実装の既定（強く押しても開かない）
    public var forcePressHold: TimeInterval? {
        get { nil }
        set {}
    }

    /// クリックを預からない実装の既定
    public func finishForcePress(opened: Bool) {}

    /// ポインタの位置を知らない実装の既定（マスはトラックパッドの上の指の位置で選ぶ）
    public var pointerLocation: CGPoint? { nil }

    /// ポインタを動かさない実装の既定
    public func movePointer(to point: CGPoint) {}

    /// マウスのイベントを見分けない実装の既定（抑止中はどのデバイスのイベントも捨てる）
    public var isTrackpadTouched: Bool {
        get { false }
        set {}
    }

    /// ボタンの状態を読まない実装の既定（いつも離れている）
    public var isMouseButtonDown: Bool { false }
}

// MARK: - 触覚

public enum HapticEvent: Equatable, Sendable {
    /// 指がマスの境界をまたいだ
    case boundary
    case pageChange
    /// 上下の帯に止めて、アプリとグローバルの層を切り替えた（ページの2打と指で見分けられる、強めの1打）
    case layerChange
    /// 少し長く止めるマスを止め終えた（いま離すと実行する）
    case holdReady
    case execute
    /// トラックパッドを強く押し込んで9マスを開いた（開いたことを指に知らせる）
    case activation
    /// 受け付けたが何もしなかった（外枠・境界の帯・空きマスで離した・止める時間が足りずに離した・2本以上の指で離した・
    /// 試用期間の終了や Nonet のウィンドウで実行しなかった・切り替える先の無い向きへスワイプした）。
    /// 「何も起きなかった」と「届かなかった」を指で見分けられるように
    case rejected
}

@MainActor
public protocol HapticPlayer: AnyObject {
    func play(_ event: HapticEvent, strength: HapticStrength)
}

// MARK: - アクションの実行

public struct RunningAppInfo: Equatable, Sendable {
    public var app: AppReference
    public var processID: Int32

    public init(app: AppReference, processID: Int32) {
        self.app = app
        self.processID = processID
    }
}

public struct ActionContext: Sendable {
    /// 9マスを開いたときに前面にあったアプリ
    public var frontmostApp: RunningAppInfo?
    /// 長く掛かるアクションが、前面アプリの選択テキストや URL を読み終えた（⌘C も戻し終えた）ときに呼ぶ。
    /// そこで後の実行に順番を譲る（読み終える前に後のキー入力（⌘W など）が届かないように）
    public var didReadContext: (@MainActor @Sendable () -> Void)?
    /// 「ターミナルで実行」のスクリプトを開くアプリ（設定の GlobalSettings.terminalApp）
    public var terminalApp: TerminalApp

    public init(frontmostApp: RunningAppInfo?, didReadContext: (@MainActor @Sendable () -> Void)? = nil, terminalApp: TerminalApp = .terminal) {
        self.frontmostApp = frontmostApp
        self.didReadContext = didReadContext
        self.terminalApp = terminalApp
    }
}

@MainActor
public protocol ActionPerforming: AnyObject {
    /// 失敗したら NonetError（表示できる説明つき）を投げる
    func perform(_ action: Action, context: ActionContext) async throws
    /// perform と同じだが、結果の出し方が「画面に表示」の AI・裏のスクリプト・ショートカットの文字列を、クリップボードに入れずに返す。ほかは nil
    func performReturningOutput(_ action: Action, context: ActionContext) async throws -> String?
}

extension ActionPerforming {
    public func performReturningOutput(_ action: Action, context: ActionContext) async throws -> String? {
        try await perform(action, context: context)
        return nil
    }
}

@MainActor
public protocol FrontmostAppObserving: AnyObject {
    var current: RunningAppInfo? { get }
    /// メインスレッドで呼ばれる
    var onChange: ((RunningAppInfo?) -> Void)? { get set }
    func start()
    func stop()
    /// Nonet のウィンドウ（設定・初回の案内・結果のパネルなど）がいまキーで、送ったキーがそこに届くか。
    /// current は Nonet を数えないので、別に聞く。Nonet が前面のアプリでも、キーのウィンドウが無ければ false
    var isOwnWindowKey: Bool { get }
    /// 前面のアプリがブラウザなら、前面のウインドウで見ているページのホスト名（サイトごとのボタン）。
    /// 9マスを開くときに呼ぶ（読むのに少し掛かることがある）。ブラウザでない・読めなければ nil
    func currentSiteHost() -> String?
}

extension FrontmostAppObserving {
    /// Nonet のウィンドウがキーになることの無い実装の既定
    public var isOwnWindowKey: Bool { false }

    /// サイトを読まない実装の既定
    public func currentSiteHost() -> String? { nil }
}

// MARK: - 設定画面で使うもの

/// メニュー項目。区切り線は含めない
public struct MenuItemNode: Identifiable, Equatable, Sendable {
    public var title: String
    /// メニューバーからのタイトルの並び
    public var path: [String]
    public var keyEquivalent: KeySequence?
    public var isEnabled: Bool
    public var children: [MenuItemNode]

    public init(title: String, path: [String], keyEquivalent: KeySequence? = nil, isEnabled: Bool = true, children: [MenuItemNode] = []) {
        self.title = title
        self.path = path
        self.keyEquivalent = keyEquivalent
        self.isEnabled = isEnabled
        self.children = children
    }

    public var id: String { path.joined(separator: "\u{1F}") }
}

@MainActor
public protocol MenuReading: AnyObject {
    /// メニューバーを持つ起動中のアプリ
    func runningApps() -> [RunningAppInfo]
    /// アクセシビリティの許可が必要。Apple メニューは含めない。読むのはメインスレッドの外
    func menuItems(for app: RunningAppInfo) async throws -> [MenuItemNode]
}

@MainActor
public protocol PermissionsProviding: AnyObject {
    var isAccessibilityGranted: Bool { get }
    /// システムの許可ダイアログを出す
    func requestAccessibility()
    func openAccessibilitySettings()
    /// パスワード入力中など、キーの監視ができない状態
    var isSecureInputActive: Bool { get }
}

@MainActor
public protocol InstalledAppsProviding: AnyObject {
    /// /Applications などにあるアプリ（名前順）
    func installedApps() -> [AppReference]
    func isInstalled(bundleID: String) -> Bool
}

@MainActor
public protocol ShortcutsProviding: AnyObject {
    /// ショートカット.app にあるショートカットの名前
    func shortcutNames() async -> [String]
}

@MainActor
public protocol AIAvailabilityProviding: AnyObject {
    /// AI アクションを今使えない理由（表示できる文）。使えるなら nil
    var unavailableReason: String? { get }
}

@MainActor
public protocol LoginItemControlling: AnyObject {
    var isEnabled: Bool { get }
    /// 登録してある（動いている、またはシステム設定の「ログイン項目」での許可待ち）
    var isRegistered: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

extension LoginItemControlling {
    /// 許可待ちを区別しない実装の既定
    public var isRegistered: Bool { isEnabled }
}

// MARK: - 時間

@MainActor
public protocol ScheduledTask: AnyObject {
    func cancel()
}

@MainActor
public protocol Scheduler: AnyObject {
    /// 単調増加の秒
    var now: TimeInterval { get }
    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask
}

// MARK: - HUD

@MainActor
public protocol HUDPresenting: AnyObject {
    /// HUD を出す。開いたときのポインタのすぐ下に地図を置き、地図の枠（主画面の左上が原点、y が下向き）を返す。
    /// 開いている間は、この枠の上でポインタが乗っているマスを選ぶ（ControllerPointerSelection）
    @discardableResult
    func show(_ model: HUDModel) -> CGRect?
    /// 表示中の HUD を更新する（ハイライトやページ）。帯や行が増減して枠が変わったら、新しい地図の枠を返す（変わらなければ nil でもよい）
    @discardableResult
    func update(_ model: HUDModel) -> CGRect?
    func hide()
    func showToast(_ toast: ToastModel)
    /// AI の結果など、読んでコピーできる文を出す（閉じるまで残る）
    func showResult(_ result: ResultModel)
    /// 表示中のトーストを消す（「実行中」のトーストを、実行が終わって知らせることが無いときに消す）
    func hideToast()
    /// 「画面に置く」のマスを光らせている間、置く枠（AppKit のグローバル座標）を画面に見せる。閉じるときは hide() で消す
    func showPlacementPreview(_ frame: CGRect)
    func hidePlacementPreview()
    /// 最近のスクリーンショットのトレイを、HUD を出していた場所（無ければポインタ）の近くに出す。
    /// 探す・並べる・コピーする・ドラッグさせる・閉じるは画面が受け持つ（ScreenshotFolder で探す）
    func showScreenshotTray(_ options: ScreenshotTrayAction)
    /// 強く押し込んでから開くまでの間、ポインタの周りに duration で満ちる輪を出す（止め終えたら9マスが開く）
    func showPressProgress(duration: TimeInterval)
    func hidePressProgress()
}

extension HUDPresenting {
    /// トーストを消せない実装の既定（時間で消える）
    public func hideToast() {}

    /// 置く枠を見せない実装の既定
    public func showPlacementPreview(_ frame: CGRect) {}
    public func hidePlacementPreview() {}

    /// トレイを出さない実装の既定
    public func showScreenshotTray(_ options: ScreenshotTrayAction) {}

    /// 輪を出さない実装の既定
    public func showPressProgress(duration: TimeInterval) {}
    public func hidePressProgress() {}

}

// MARK: - ウインドウを置く

/// 「画面に置く」。前面のアプリのウインドウを、画面の場所に置く。座標は AppKit のグローバル座標（主画面の左下が原点、y は上向き）
@MainActor
public protocol WindowPlacing: AnyObject {
    /// app の最前面のウインドウを region に置く。ウインドウが無い・動かせないときは NonetError。
    /// 本物はアクセシビリティの呼び出しをメインスレッドの外で待つ（固まりかけたアプリでも、ポインタやほかの入力を止めない）
    func place(_ region: WindowRegion, app: RunningAppInfo?) async throws
    /// 置いたときの枠（HUD で光らせている間のプレビュー用）。ウインドウが無ければ nil
    func targetFrame(for region: WindowRegion, app: RunningAppInfo?) -> CGRect?
    /// 9マスを開くたびに呼ぶ。下見のために覚えたウインドウの場所を忘れる（閉じている間にウインドウが動いたかもしれない）
    func resetPreview()
}

extension WindowPlacing {
    public func resetPreview() {}
}

/// ウインドウを置けない実装（テストと見た目の確認）
@MainActor
public final class UnavailableWindowPlacer: WindowPlacing {
    public nonisolated init() {}

    public func place(_ region: WindowRegion, app: RunningAppInfo?) throws {
        throw NonetError.actionFailed(String(localized: "この Mac ではウインドウを置けません", bundle: .module))
    }

    public func targetFrame(for region: WindowRegion, app: RunningAppInfo?) -> CGRect? {
        nil
    }
}

// MARK: - まとめ

/// NonetController が使うサービス一式。本物は NonetServices.live()（NonetPlatform）
@MainActor
public struct NonetServices {
    public var touchSource: any TouchSource
    public var keyboard: any KeyboardMonitor
    public var haptics: any HapticPlayer
    public var performer: any ActionPerforming
    public var frontmostApp: any FrontmostAppObserving
    public var menus: any MenuReading
    public var permissions: any PermissionsProviding
    public var installedApps: any InstalledAppsProviding
    public var shortcuts: any ShortcutsProviding
    public var ai: any AIAvailabilityProviding
    public var loginItem: any LoginItemControlling
    public var scheduler: any Scheduler
    /// プリセットを組み立てるときに見る、この Mac の状態（AI・Claude Code・Dock）
    public var presetEnvironment: any PresetEnvironmentProviding
    /// 「画面に置く」（置く枠のプレビューに使う。実行は performer が行う）
    public var windowPlacer: any WindowPlacing

    public init(
        touchSource: any TouchSource,
        keyboard: any KeyboardMonitor,
        haptics: any HapticPlayer,
        performer: any ActionPerforming,
        frontmostApp: any FrontmostAppObserving,
        menus: any MenuReading,
        permissions: any PermissionsProviding,
        installedApps: any InstalledAppsProviding,
        shortcuts: any ShortcutsProviding,
        ai: any AIAvailabilityProviding,
        loginItem: any LoginItemControlling,
        scheduler: any Scheduler,
        presetEnvironment: any PresetEnvironmentProviding = FixedPresetEnvironment(),
        windowPlacer: any WindowPlacing = UnavailableWindowPlacer()
    ) {
        self.touchSource = touchSource
        self.keyboard = keyboard
        self.haptics = haptics
        self.performer = performer
        self.frontmostApp = frontmostApp
        self.menus = menus
        self.permissions = permissions
        self.installedApps = installedApps
        self.shortcuts = shortcuts
        self.ai = ai
        self.loginItem = loginItem
        self.scheduler = scheduler
        self.presetEnvironment = presetEnvironment
        self.windowPlacer = windowPlacer
    }
}

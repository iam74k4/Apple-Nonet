// 担当: engine（公開 API は契約。設定画面・メニューバー・初回起動がこの API を使う）
import Foundation
import Observation
import os

let controllerLogger = Logger(subsystem: "com.iam74k4.Nonet", category: "engine")

public enum ControllerStatus: Equatable, Sendable {
    case stopped
    /// 上の縁からの滑り込みを待っている
    case running
    /// 設定で無効にしている
    case disabled
    /// アクセシビリティの許可が無い
    case needsAccessibility
    /// マルチタッチのトラックパッドが無い
    case noTrackpad
    /// パスワード入力中などで、キーを監視できない（開いている間にキーで閉じられないので、開かない）
    case secureInputActive
}

/// 実行したマス（実行しなかった・失敗したものも含む）
public struct ExecutionRecord: Equatable, Sendable {
    public var cellTitle: String
    public var profileName: String
    /// プロファイル内での位置
    public var address: CellAddress
    public var succeeded: Bool
    /// 失敗の理由など
    public var message: String?
    public var date: Date
    /// 結果の出し方が「画面に表示」のアクション（AI・裏のスクリプト・ショートカット）の結果。設定画面のテスト実行の下に出す
    public var output: String?
    /// マスのあるプロファイル（設定でそのマスを開くため）。分からなければ nil
    public var profileID: UUID?

    public init(
        cellTitle: String,
        profileName: String,
        address: CellAddress,
        succeeded: Bool,
        message: String?,
        date: Date,
        output: String? = nil,
        profileID: UUID? = nil
    ) {
        self.cellTitle = cellTitle
        self.profileName = profileName
        self.address = address
        self.succeeded = succeeded
        self.message = message
        self.date = date
        self.output = output
        self.profileID = profileID
    }
}

/// 9マスを開いて、何も実行せずに指を離して閉じたときの記録。初回の案内の練習（外枠に出してやめる）で使う
public struct CancellationRecord: Equatable, Sendable {
    public var reason: SessionCancellation
    public var date: Date
    /// ポインタで選ぶとき、開いてからポインタを真ん中から出さずに離した（外枠扱いで閉じたが、外枠まで動かしてはいない）
    public var liftedBeforeMoving: Bool

    public init(reason: SessionCancellation, date: Date, liftedBeforeMoving: Bool = false) {
        self.reason = reason
        self.date = date
        self.liftedBeforeMoving = liftedBeforeMoving
    }
}

/// Nonet の本体。上の縁からの滑り込みで開く → 滑らせて選ぶ → 指を離して実行 の流れを動かし、設定を持つ。
/// 仕様は docs/architecture.md の「操作の仕様」。開く動きは EdgeSlideRecognizer、セッションの規則は SessionEngine が持ち、
/// ここはトラックパッド・キーボード・タイマーをそれらに渡し、出力を HUD・触覚・実行につなぐ
@MainActor
@Observable
public final class NonetController {
    /// 権限・トラックパッド・セキュア入力を確かめ直す間隔
    static let pollInterval: TimeInterval = 2
    /// テスト実行で、アプリを前面に出してから待つ時間
    static let activationDelay: TimeInterval = 0.4
    /// それでも前面にならないとき（起動に時間がかかるとき）に確かめ直す間隔と回数
    static let activationRetryInterval: TimeInterval = 0.2
    static let activationRetryCount = 8
    /// 開いたときに license.refresh() を呼び直さない間隔。refresh は試用の記録を保存先に書くので、開くたびには呼ばない
    /// （実行してよいかは canExecuteActions がいつでも正しく答え、日付の変化などでは ui-shell が呼ぶ）
    static let licenseRefreshInterval: TimeInterval = 60
    /// recentExecutions に残す数
    public static let recentExecutionLimit = 10
    /// 長く掛かるマス（ControllerExecutionPolicy.isLongRunning）がこの秒数で終わらなければ、「実行中」のトーストを出す
    static let runningToastDelay: TimeInterval = 0.5

    public private(set) var configuration: NonetConfiguration
    public private(set) var status: ControllerStatus = .stopped
    /// いま前面アプリで使うプロファイルの名前
    public private(set) var activeProfileName: String?
    public private(set) var lastExecution: ExecutionRecord?
    /// 最近の実行（新しい順、最大 recentExecutionLimit 個）。失敗・試用期間の終了などで実行しなかったものも含む。
    /// 練習モードの記録（実際には実行していない）は含まない。メニューの「最近の実行」などで使う
    public private(set) var recentExecutions: [ExecutionRecord] = []
    /// 最後に、9マスを開いて何も実行せずに指を離したとき（外枠で離した など）。練習モードでも記録する
    public private(set) var lastCancellation: CancellationRecord?
    /// true の間はアクションを実行せず、lastExecution に記録だけする（初回起動の練習用）
    public var isPracticeMode = false
    /// true の間はセッションを始めない（設定画面でキーを記録しているとき）
    public var isRecordingKeys = false {
        didSet {
            // 記録しているところでマスが実行されないように、始まっているセッションは何も実行せずに終える
            if isRecordingKeys, !oldValue {
                endSession()
            }
        }
    }
    /// 保存された設定が無かった（初回起動）
    public private(set) var isFirstLaunch = false
    /// 初回起動の案内で「ログイン時に起動」を勧めた（takeLoginItemRecommendation）
    @ObservationIgnored private var hasRecommendedLoginItem = false

    /// 初回起動で、まだ「ログイン時に起動」を勧めていなければ true を返し、勧めたことにする。
    /// 同じ起動の中で案内を開き直しても、もう勧めない（外したものを、また選んだ状態にしない）
    public func takeLoginItemRecommendation() -> Bool {
        guard isFirstLaunch, !hasRecommendedLoginItem else { return false }
        hasRecommendedLoginItem = true
        return true
    }
    /// 利用者に知らせたい問題（設定ファイルが壊れていた・保存できない など）。設定画面とメニューに出す
    public private(set) var notice: String?

    @ObservationIgnored private let services: NonetServices
    @ObservationIgnored private let store: ConfigurationStore
    @ObservationIgnored private let hud: any HUDPresenting
    @ObservationIgnored private let license: LicenseManager
    @ObservationIgnored private let saver: ControllerConfigurationSaver
    @ObservationIgnored private let executions: ControllerExecutionQueue
    @ObservationIgnored private var engine = SessionEngine()
    /// いまのセッションで使うもの。セッションの外は nil
    @ObservationIgnored private var session: ControllerSession?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isTouchSourceRunning = false
    @ObservationIgnored private var isHUDVisible = false
    /// 開いている間の、HUD の枠（円を囲む正方形。主画面の左上が原点、y が下向き。HUDPresenting.show が返す）。ポインタの位置をこの枠の中心からの向きと距離でマスに写す
    @ObservationIgnored private var hudMapFrame: CGRect?
    /// ポインタの位置をマスに写す（ヒステリシスのために直前の場所を持つ）。開くたびに作り直す
    @ObservationIgnored private var pointerSelection = ControllerPointerSelection()
    /// 最後に HUD に渡したエンジンの状態。ポインタが中央から出た（HUDModel.isWaitingAtCenter が変わる）のに
    /// エンジンの状態が変わらなかったときに、HUD だけを描き直すため
    @ObservationIgnored private var lastHUDState: SessionHUDState?
    @ObservationIgnored private var tickTask: (any ScheduledTask)?
    @ObservationIgnored private var pollTask: (any ScheduledTask)?
    /// エンジンの出力を処理している間に来た入力（出力の処理からエンジンを呼び直さないように、順に処理する）
    @ObservationIgnored private var pendingInputs: [(input: SessionInput, starting: ControllerSession?)] = []
    @ObservationIgnored private var isHandlingInput = false
    /// サービスごとの直近の失敗。2秒ごとの確かめ直しで、同じ失敗を何度もログに書かないため
    @ObservationIgnored private var serviceFailures: [String: String] = [:]
    /// 保存の失敗で出した notice。保存できたら消す
    @ObservationIgnored private var saveFailureNotice: String?
    /// 開いたときに最後に license.refresh() を頼んだ時刻（Scheduler.now）
    @ObservationIgnored private var lastLicenseRefresh: TimeInterval?
    /// 開く動き（上の縁からの滑り込み）。フレームはセッションの外の分もすべて渡す
    @ObservationIgnored private var opener = EdgeSlideRecognizer()
    /// 開く動きを見分けてから、開くまで待っている（EdgeSlideRecognizer.entryConfirmDelay）
    @ObservationIgnored private var pendingOpen: (any ScheduledTask)?
    /// pendingOpen を決めた、上の縁から滑らせた指（同じフレームで指が入れ替わったら開かない）
    @ObservationIgnored private var pendingOpenFingerID: Int?
    /// 上の縁で触れ始めてから離すまでの ProcessInfo のアクティビティ。メニューバーのアプリはウィンドウが無いと App Nap で
    /// タイマーがまとめて遅らされることがあるので、開く前の entryConfirmDelay・止めて切り替えるまでの時間・少し長く止めるマスを
    /// 遅らせない。ふつうにポインタを動かすだけのタッチでは持たない（電力を使わない）
    @ObservationIgnored private var latencyActivity: NSObjectProtocol?
    /// 閉じた後のライセンスの数え直し（止めるときは取り消す）
    @ObservationIgnored private var licenseRefreshTask: (any ScheduledTask)?
    /// HUD を隠したとき、ポインタがまだ開いた直後の真ん中にいた（hideHUD で覚え、.sessionEnded で使って戻す）
    @ObservationIgnored private var wasHiddenBeforeMoving = false
    /// 初回起動で、claude を調べ終えてからプリセットを作り直す（rebuildFirstPresetsWhenResolved）
    @ObservationIgnored private var firstPresetsRebuild: Task<Void, Never>?
    /// Nonet のウィンドウが前面で開かなかったことを、この起動で知らせた（知らせるのは1回だけ）
    @ObservationIgnored private var hasNotifiedOwnWindow = false
    /// 使い始めの案内と試用期間の知らせを、何回・いつ出したか
    @ObservationIgnored private let guidance: any HUDGuidanceStoring
    /// トラックパッドに指が触れているか（キーボードモニターに知らせ、マウスのイベントを見分けてもらう）
    @ObservationIgnored private var isTrackpadTouched = false
    /// 「実行中」のトーストを出した実行（終わるまで）と、いま画面に出ている「実行中」のトーストの実行
    @ObservationIgnored private var shownRunningToasts: Set<Int> = []
    @ObservationIgnored private var visibleRunningToast: Int?
    @ObservationIgnored private var nextRunID = 0
    /// 今の日時（記録の日時と、試用期間の知らせを1日に1回にするため。テストで差し替える）
    @ObservationIgnored var currentDate: () -> Date = { Date() }

    /// guidance は使い始めの案内と試用期間の知らせの記録（既定は UserDefaults）
    public init(
        services: NonetServices,
        store: ConfigurationStore,
        hud: any HUDPresenting,
        license: LicenseManager,
        guidance: any HUDGuidanceStoring = UserDefaultsHUDGuidanceStore()
    ) {
        self.services = services
        self.store = store
        self.hud = hud
        self.license = license
        self.guidance = guidance
        executions = ControllerExecutionQueue(scheduler: services.scheduler)
        saver = ControllerConfigurationSaver(scheduler: services.scheduler) { [store] configuration in
            try store.save(configuration)
        }
        // 読み込む前の仮の設定。start() までの変更で保存済みの設定を上書きしないよう、保存もしない
        saver.isEnabled = false
        configuration = NonetConfiguration(profiles: []).validated()
        saver.onResult = { [weak self] result in
            self?.saveFinished(result)
        }
    }

    // MARK: - 開始と停止

    /// 設定を読み、監視を始める。権限が無ければ status で知らせ、許可されたら自動で動き出す
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        loadConfiguration()
        services.keyboard.onEvent = { [weak self] event in
            self?.handleKeyboard(event)
        }
        // セッションの外のフレームも渡す（開く動きを見分けるため。開いたときに触れている指をエンジンが知っておくため）
        services.touchSource.onFrame = { [weak self] frame in
            self?.receiveTouches(frame)
        }
        services.frontmostApp.onChange = { [weak self] _ in
            self?.updateActiveProfile()
        }
        services.frontmostApp.start()
        refreshServices()
        updateActiveProfile()
        controllerLogger.info("開始しました（状態: \(String(describing: self.status), privacy: .public)）")
    }

    /// 監視をすべて止める。セッション中なら何も実行せずに終え（ポインタの抑止をやめ、HUD を閉じる）、待っている保存を書く
    public func stop() {
        endLatencyActivity()
        if isStarted {
            endSession()
            // 止めるときに閉じたセッションの後の数え直しは行わない（止めた後に予定を残さない）
            licenseRefreshTask?.cancel()
            licenseRefreshTask = nil
            isStarted = false
            tickTask?.cancel()
            tickTask = nil
            pollTask?.cancel()
            pollTask = nil
            firstPresetsRebuild?.cancel()
            firstPresetsRebuild = nil
            cancelPendingOpen()
            services.keyboard.onEvent = nil
            services.touchSource.onFrame = nil
            services.frontmostApp.onChange = nil
            stopKeyboard()
            stopTouchSource()
            services.frontmostApp.stop()
            hideHUD()
            if services.keyboard.isSuppressingPointer {
                services.keyboard.isSuppressingPointer = false
            }
            engine = SessionEngine()
            session = nil
            opener = EdgeSlideRecognizer()
            controllerLogger.info("停止しました")
        }
        saver.flush()
        status = .stopped
    }

    /// 設定を保存しているか（設定ファイルを読めなかった・アンインストールした後は false）
    public var isSavingConfiguration: Bool { saver.isEnabled }
    /// アンインストールで止めた（この起動の間は、もう保存を始めない）
    private var savingStoppedForGood = false

    /// 待っている保存を書いてから、この後の変更を書かない（アンインストールで設定のフォルダをゴミ箱に入れた後に、
    /// メニューで「有効にする」などを変えても、フォルダを作り直さない）。変更はこの起動の間だけ効く
    public func stopSaving() {
        saver.flush()
        saver.isEnabled = false
        savingStoppedForGood = true
    }

    /// 設定ファイルを読めずに保存をやめていたとき、利用者が控えに戻したら、また保存する（今の設定を書く）。
    /// 読めないファイルは save() が上書きしない（書けなければ知らせて書き直す）。新しい版のファイルは写しを残してあるので上書きしてよい。
    /// アンインストールの後は始めない
    public func resumeSaving() {
        guard !saver.isEnabled, !savingStoppedForGood else { return }
        saver.isEnabled = true
        notice = nil
        saver.saveNow(configuration)
    }

    // MARK: - 設定

    /// 設定を変えて保存し、すぐに反映する
    public func update(_ transform: (inout NonetConfiguration) -> Void) {
        var changed = configuration
        transform(&changed)
        replaceConfiguration(changed)
    }

    public func replaceConfiguration(_ configuration: NonetConfiguration) {
        let next = configuration.validated()
        guard next != self.configuration else { return }
        let previous = self.configuration
        self.configuration = next
        saver.schedule(next)
        configurationDidChange(from: previous)
    }

    public func dismissNotice() {
        notice = nil
        saveFailureNotice = nil
    }

    /// 権限の状態を確かめ直す（設定画面や初回起動から呼ぶ）
    public func refreshPermissions() {
        refreshServices()
    }

    // MARK: - テスト実行

    /// 設定画面の「テスト実行」。実際に使うときと同じアプリに向けて実行する: アプリのプロファイルならそのアプリを、
    /// グローバルなら設定ウィンドウの前に使っていたアプリを前面に出してから実行する（キーが設定ウィンドウに届かないように）。
    /// 練習モードでも実行する（試用中にマスを試すための機能）が、試用期間が終わっていれば licenseRequired で失敗する
    @discardableResult
    public func testRun(_ cell: Cell, profileID: UUID) async -> ExecutionRecord {
        let profile = configuration.profile(id: profileID)
        let target = ControllerTarget(
            cell: cell,
            profileName: profile?.name ?? "",
            address: address(of: cell, in: profile),
            profileID: profile?.id,
            profilePageCount: profile?.pages.count ?? 1
        )
        guard license.canExecuteActions else {
            return refuseWithoutLicense(target)
        }
        let profileApp = profile?.app
        return await executions.enqueue { turn in
            await self.runTest(target, profileApp: profileApp, turn: turn)
        }.value
    }

    private func runTest(_ target: ControllerTarget, profileApp: AppReference?, turn: ControllerExecutionTurn) async -> ExecutionRecord {
        // 前面に出すのに時間が掛かっても、後の実行をいつまでも待たせない
        turn.pass(after: ControllerExecutionPolicy.holdLimit)
        let action = target.cell.action
        // frontmostApp は Nonet を数えないので、設定ウィンドウが前面でも、その前に使っていたアプリを指す
        let lastApp = ControllerExecutionPolicy.dependsOnFrontmostApp(action) ? services.frontmostApp.current?.app : nil
        if let app = profileApp ?? lastApp {
            do {
                let activate = Action.launchApp(LaunchAppAction(app: app, hideIfFrontmost: false))
                try await services.performer.perform(activate, context: ActionContext(frontmostApp: services.frontmostApp.current))
            } catch {
                // 別のアプリにキーを送らないよう、マスは実行しない
                return fail(target, error: error)
            }
            await waitUntilFrontmost(app)
            if !isFrontmost(app), ControllerExecutionPolicy.sendsInputToFrontmostApp(action) {
                // 起動に時間が掛かっている。送ると、いま前面にある Nonet の設定ウィンドウなどに届く
                let reason = String(localized: "\(app.nameOrBundleID) が前面になりませんでした", bundle: .module)
                return fail(target, error: NonetError.actionFailed(reason))
            }
        } else if ControllerExecutionPolicy.sendsInputToFrontmostApp(action) {
            let reason = String(localized: "送り先のアプリがありません。使いたいアプリを一度前面に出してから試してください。", bundle: .module)
            return fail(target, error: NonetError.actionFailed(reason))
        }
        let context = ActionContext(frontmostApp: services.frontmostApp.current)
        return await perform(target, context: context, turn: turn, showsSuccessAfterRunning: false)
    }

    /// 前面に来るまで少し待つ。起動に時間がかかるアプリは、前面に来るまで（最長で約2秒）待つ
    private func waitUntilFrontmost(_ app: AppReference) async {
        await sleep(Self.activationDelay)
        var retries = 0
        while !isFrontmost(app), retries < Self.activationRetryCount {
            await sleep(Self.activationRetryInterval)
            retries += 1
        }
    }

    /// app が前面で、送ったキーがそのアプリに届くか。frontmostApp.current は Nonet を数えないので、
    /// 設定ウィンドウがキーのままなら、current がそのアプリでも前面ではない（キーは設定ウィンドウに届く）
    private func isFrontmost(_ app: AppReference) -> Bool {
        guard !services.frontmostApp.isOwnWindowKey, let current = services.frontmostApp.current else { return false }
        return NonetConfiguration.bundleIDKey(current.app.bundleID) == NonetConfiguration.bundleIDKey(app.bundleID)
    }

    /// Scheduler で待つ（テストでは手で進める時計で待てる）
    private func sleep(_ delay: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            services.scheduler.schedule(after: delay) {
                continuation.resume()
            }
        }
    }

    /// 頼んだ実行がすべて終わるまで待つ（テスト用）
    func waitForExecutions() async {
        await executions.waitUntilIdle()
    }

    // MARK: - キーボード

    /// 開いている間だけ届く（キーボードモニターは、ポインタを抑止している間だけキーボードを見る）
    private func handleKeyboard(_ event: KeyboardEvent) {
        switch event {
        case .interrupted:
            send(.interrupted(at: services.scheduler.now))
        }
    }

    // MARK: - 開く

    /// トラックパッドのフレーム。エンジンに渡してから、開く動きを見る（開いたとき、エンジンはこのフレームの指で選び始める）
    private func receiveTouches(_ frame: TouchFrame) {
        let touching = !frame.touching.isEmpty
        if touching != isTrackpadTouched {
            isTrackpadTouched = touching
            services.keyboard.isTrackpadTouched = touching
            if !touching, !engine.isInSession {
                endLatencyActivity()
            }
        }
        // トラックパッドの続きが来なくなって離れたことにしたフレーム。光っているマスで離したことにせず、何も実行せずに閉じる
        if frame.isSynthesizedLift {
            send(.interrupted(at: frame.timestamp))
        }
        // 開いている間は、HUD の中心からのポインタの向きと距離で決めたマスの位置を指の位置にする（HUD が無ければポインタは読まない）
        let pointer = hudMapFrame != nil && engine.isInSession ? services.keyboard.pointerLocation : nil
        let wasWaitingAtCenter = pointerSelection.isWaitingAtCenter
        send(.touches(pointerSelection.frame(frame, pointer: pointer, map: hudMapFrame)))
        // 中央から出たのにエンジンの状態が変わらなかった（外枠のまま）ときも、HUD の「開いた直後」の見た目を解く
        if wasWaitingAtCenter, !pointerSelection.isWaitingAtCenter, isHUDVisible, let session, let state = lastHUDState {
            if let map = hud.update(hudModel(session, state: state)) {
                hudMapFrame = map
            }
        }
        // 待つ間に2本目の指が触れた・指が離れた・別の指に入れ替わったなら、開かない（2本指のスクロールを始めた・短くなぞっただけ・
        // 滑らせた指を離したフレームで別の指が触れた。その指は縁から滑らせていない）
        if frame.touching.count != 1 || frame.touching.first?.id != pendingOpenFingerID {
            cancelPendingOpen()
        }
        // 開きやすさは設定からそのつど入れる（触れ始めた後に変えても、そのタッチは触れたときの決まりで見る）
        let thresholds = EdgeSlideRecognizer.Thresholds(configuration.settings.openSensitivity)
        if opener.thresholds != thresholds {
            opener.thresholds = thresholds
        }
        switch opener.apply(frame, isSessionActive: engine.isInSession) {
        case .none:
            break
        case .touchBeganInBand:
            // 開く動きの間に指を滑らせた分だけポインタが動くので、触れ始めた位置を覚えておき、開いたらそこへ戻す
            services.keyboard.rememberPointerLocation()
            beginLatencyActivity()
        case .slid:
            scheduleOpen(fingerID: frame.touching.first?.id)
        }
    }

    /// 開く動きを見分けた。entryConfirmDelay だけ待って、1本指のままなら開く（待つ間のフレームに頼らず、タイマーで待つ）
    private func scheduleOpen(fingerID: Int?) {
        cancelPendingOpen()
        pendingOpenFingerID = fingerID
        pendingOpen = services.scheduler.schedule(after: EdgeSlideRecognizer.entryConfirmDelay) { [weak self] in
            guard let self else { return }
            self.pendingOpen = nil
            self.pendingOpenFingerID = nil
            guard self.isTrackpadTouched else { return }
            self.openFromEdge()
        }
    }

    private func beginLatencyActivity() {
        guard latencyActivity == nil else { return }
        latencyActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "上の縁から9マスを開いている"
        )
    }

    private func endLatencyActivity() {
        guard let activity = latencyActivity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        latencyActivity = nil
    }

    private func cancelPendingOpen() {
        pendingOpen?.cancel()
        pendingOpen = nil
        pendingOpenFingerID = nil
    }

    /// 上の縁からの滑り込みを見分けた。開いてよければセッションを始める。
    /// マウスやトラックパッドのボタンを押し込んだまま（クリックしたままドラッグを始めるところ など）・始められない状態
    /// （無効・許可なし・セキュア入力・「このアプリでは Nonet を使わない」）・Nonet のウィンドウがキー（練習中を除く）なら、
    /// 何もしない（ポインタはそのまま動く）。試用期間が終わっていたら開かず、終わったことと次にすることをトースト1つと触覚で知らせる
    /// （開く動きは1つのタッチで1回なので、トーストも1回）
    private func openFromEdge() {
        guard !services.keyboard.isMouseButtonDown else {
            controllerLogger.debug("ボタンが押されているため、開きません")
            return
        }
        guard canBeginSession() else { return }
        // Nonet のウィンドウ（設定など）がキーなら開かない。送るキーや読む選択範囲が Nonet のウィンドウのものになり、
        // 設定でマスをドラッグするなど、トラックパッドを使っている最中でもある。初回の案内の練習は、案内のウィンドウの上で試す
        guard isPracticeMode || !services.frontmostApp.isOwnWindowKey else {
            controllerLogger.debug("Nonet のウィンドウがキーなので、開きません")
            // 設定で説明を読んですぐ試した人が、反応が無くて壊れていると思わないよう、起動してから1回だけ知らせる
            // （設定でマスをドラッグするたびに出ると邪魔なので、2回目からは知らせない）
            if !hasNotifiedOwnWindow {
                hasNotifiedOwnWindow = true
                showToast(ControllerPresentation.ownWindowToast)
            }
            return
        }
        guard license.canExecuteActions else {
            controllerLogger.notice("試用期間が終わっているため、開きません")
            playHaptic(.rejected, strength: configuration.settings.haptics)
            showToast(ControllerPresentation.trialEndedToast)
            // 起動したまま一日の途中で終わったときは、表示用の entitlement がまだ試用中のまま（日付が変わるか、メニューを開くまで）。
            // 数え直して「試用期間が終わりました」のウィンドウや設定の帯をすぐ出す
            if case .trial = license.entitlement {
                services.scheduler.schedule(after: 0) { [weak self] in
                    self?.license.refresh()
                }
            }
            return
        }
        let next = ControllerSession(configuration: configuration, frontmostApp: services.frontmostApp.current)
        // エンジンの beginPointerSuppression で、この呼び出しの中で isSuppressingPointer を true にする（直後のポインタイベントを取りこぼさない）
        send(.open(at: services.scheduler.now, configuration: next.engineConfiguration), starting: next)
    }

    /// セッションを始められるか（開く前と、試用期間が終わっていて開かないときの知らせの前に確かめる）
    private func canBeginSession() -> Bool {
        guard isStarted, !isRecordingKeys else { return false }
        // セキュア入力は2秒ごとにしか確かめないので、開くたびに確かめ直す
        // （パスワード欄に入った直後に開かないため・離れた直後から使えるようにするため）
        if status == .secureInputActive || services.permissions.isSecureInputActive {
            refreshServices()
        }
        guard status == .running else { return false }
        // 「このアプリでは Nonet を使わない」アプリが前面なら開かない。ポインタを止めず、HUD も出さない。
        // 試用期間の終了を知らせるトーストと触覚も出さない（仕様: そのアプリでは何もしない）。
        // 初回の案内の練習は別: 案内のウィンドウの上で試すので、その前に使っていたアプリで使わない設定でも開く（グローバルのページ）
        return isPracticeMode || !configuration.isTurnedOff(forBundleID: services.frontmostApp.current?.app.bundleID)
    }

    /// 表示用の entitlement を新しくする（日付が変わった後の残り日数など）。
    /// 9マスを閉じた後に呼ぶ。保存先への書き込みがあるので、フレームの処理を返してから行い、licenseRefreshInterval に1回までにする。
    /// ライセンスがあれば試用を数えなくてよいので呼ばない。実行してよいかは canExecuteActions がいつでも正しく答える
    private func refreshLicenseAfterSession() {
        if case .licensed = license.entitlement { return }
        let now = services.scheduler.now
        if let last = lastLicenseRefresh, now >= last, now - last < Self.licenseRefreshInterval { return }
        lastLicenseRefresh = now
        licenseRefreshTask?.cancel()
        licenseRefreshTask = services.scheduler.schedule(after: 0) { [weak self] in
            self?.licenseRefreshTask = nil
            self?.license.refresh()
        }
    }

    // MARK: - エンジン

    /// starting は開いたときに決めた、新しいセッションで使うもの
    private func send(_ input: SessionInput, starting: ControllerSession? = nil) {
        pendingInputs.append((input, starting))
        guard !isHandlingInput else { return }
        isHandlingInput = true
        defer { isHandlingInput = false }
        while !pendingInputs.isEmpty {
            let next = pendingInputs.removeFirst()
            for effect in engine.handle(next.input) {
                apply(effect, starting: next.starting)
            }
        }
    }

    private func apply(_ effect: SessionEffect, starting: ControllerSession?) {
        switch effect {
        case .beginPointerSuppression:
            // 前のセッションの終わり（sessionEnded）はこれより前に来るので、ここで入れ替える
            if let starting {
                session = starting
            }
            // ポインタを触れ始めた位置に戻して止め、キーボードを見始める（キーが押されたら閉じる）
            services.keyboard.isSuppressingPointer = true
        case .endPointerSuppression(let dropsLateClicks):
            services.keyboard.endPointerSuppression(dropsLateClicks: dropsLateClicks)
        case .showHUD(let state):
            prepareFirstHUD()
            guard let session else { return }
            pointerSelection = ControllerPointerSelection()
            services.windowPlacer.resetPreview()
            lastHUDState = state
            hudMapFrame = hud.show(hudModel(session, state: state))
            isHUDVisible = true
            // 開いたときのポインタは HUD の円の中心。画面の端で枠を寄せてそこに来ていなければ、一度だけそこへ動かす
            if let map = hudMapFrame, let pointer = services.keyboard.pointerLocation {
                let start = ControllerPointerSelection.startPoint(in: map)
                if hypot(pointer.x - start.x, pointer.y - start.y) > 0.5 {
                    services.keyboard.movePointer(to: start)
                }
            }
            updatePlacementPreview(session, state: state)
        case .updateHUD(let state):
            guard let session, isHUDVisible else { return }
            lastHUDState = state
            if let map = hud.update(hudModel(session, state: state)) {
                hudMapFrame = map
            }
            updatePlacementPreview(session, state: state)
        case .hideHUD:
            hideHUD()
        case .haptic(let event):
            playHaptic(event, strength: session?.settings.haptics ?? configuration.settings.haptics)
        case .execute(let page, let cell):
            guard let session else { return }
            execute(page: page, cell: cell, in: session)
        case .requestTick(let time):
            scheduleTick(at: time)
        case .sessionEnded(let reason):
            // 開いたまま真ん中から出ずに離したか（先に届く .hideHUD で覚えたもの。まだ隠していなければここで見る）
            let liftedBeforeMoving = hudMapFrame != nil ? pointerSelection.isWaitingAtCenter : wasHiddenBeforeMoving
            wasHiddenBeforeMoving = false
            tickTask?.cancel()
            tickTask = nil
            if services.keyboard.isSuppressingPointer {
                services.keyboard.isSuppressingPointer = false
            }
            hideHUD()
            session = nil
            if case .cancelled(let cancellation) = reason {
                lastCancellation = CancellationRecord(reason: cancellation, date: currentDate(), liftedBeforeMoving: liftedBeforeMoving)
            }
            if !isTrackpadTouched {
                endLatencyActivity()
            }
            // 表示用のライセンスを新しくする（ファイルを読み書きするので、開いている間の最初のフレームではなく、閉じた後に）
            refreshLicenseAfterSession()
            controllerLogger.debug("セッションが終わりました: \(String(describing: reason), privacy: .public)")
        }
    }

    /// タイマーは常に1つ。新しい依頼は前の依頼を置き換える
    private func scheduleTick(at time: TimeInterval) {
        tickTask?.cancel()
        let delay = max(0, time - services.scheduler.now)
        tickTask = services.scheduler.schedule(after: delay) { [weak self] in
            guard let self else { return }
            self.tickTask = nil
            self.send(.tick(at: self.services.scheduler.now))
        }
    }

    /// 始まっているセッションを、何も実行せずに終える
    private func endSession() {
        guard engine.isInSession else { return }
        send(.interrupted(at: services.scheduler.now))
    }

    // MARK: - HUD と触覚

    private func hudModel(_ session: ControllerSession, state: SessionHUDState) -> HUDModel {
        session.hudModel(
            state,
            isPracticeMode: isPracticeMode,
            isTrialEnded: !license.canExecuteActions,
            isWaitingAtCenter: pointerSelection.isWaitingAtCenter
        )
    }

    /// セッションで最初に HUD を出すとき、試用期間の残り日数の帯（残り HUDGuidance.trialReminderDays 日から、1日に1回）を出すかを決めて記録する
    private func prepareFirstHUD() {
        guard var current = session, !current.hasShownHUD else { return }
        current.hasShownHUD = true
        let now = currentDate()
        if case .trial(let daysLeft) = license.entitlement, license.canExecuteActions,
           HUDGuidance.isTrialReminderDue(daysLeft: daysLeft, lastShown: guidance.lastTrialReminder, now: now) {
            current.trialReminderDays = daysLeft
            guidance.lastTrialReminder = now
        }
        session = current
    }

    /// トーストを出す。大きさは設定の「HUD の大きさ」に合わせる。出ている「実行中」のトーストは置き換わる
    private func showToast(_ toast: ToastModel) {
        var toast = toast
        toast.scale = configuration.settings.hudScale.factor
        visibleRunningToast = nil
        hud.showToast(toast)
    }

    private func hideHUD() {
        // セッションの終わりは .hideHUD の後に .sessionEnded が届くので、ポインタの選び方を捨てる前に、
        // 開いたまま真ん中から出ずに閉じたかを覚えておく（CancellationRecord.liftedBeforeMoving）
        if hudMapFrame != nil {
            wasHiddenBeforeMoving = pointerSelection.isWaitingAtCenter
        }
        hudMapFrame = nil
        lastHUDState = nil
        pointerSelection = ControllerPointerSelection()
        guard isHUDVisible else { return }
        isHUDVisible = false
        hud.hidePlacementPreview()
        hud.hide()
    }

    /// 「画面に置く」のマスを光らせている間（離せば置く状態のときだけ）、置く枠を画面に見せる
    private func updatePlacementPreview(_ session: ControllerSession, state: SessionHUDState) {
        guard let index = state.highlightedCell, !state.isOnBoundary, !session.pages.isEmpty else {
            hud.hidePlacementPreview()
            return
        }
        let page = session.pages[min(max(state.page, 0), session.pages.count - 1)]
        guard page.cells.indices.contains(index), case .placeWindow(let place)? = page.cells[index]?.action,
              let frame = services.windowPlacer.targetFrame(for: place.region, app: session.frontmostApp) else {
            hud.hidePlacementPreview()
            return
        }
        hud.showPlacementPreview(frame)
    }

    private func playHaptic(_ event: HapticEvent, strength: HapticStrength) {
        guard strength != .off else { return }
        services.haptics.play(event, strength: strength)
    }

    // MARK: - 実行

    private func execute(page: Int, cell: Int, in session: ControllerSession) {
        // 空きマスは何もしない（エンジンが中身を知らなかったとき）。受け付けなかったことを触覚で知らせる
        guard let target = session.target(page: page, cell: cell) else {
            playHaptic(.rejected, strength: session.settings.haptics)
            return
        }
        guard license.canExecuteActions else {
            playHaptic(.rejected, strength: session.settings.haptics)
            refuseWithoutLicense(target)
            return
        }
        // Nonet のウィンドウ（設定など）がキーなら、前面アプリに働きかけるマスは実行しない（開くときにも確かめるが、
        // 開いている間に結果のパネルなどがキーになったときのため）。送るキーや読む選択範囲が Nonet のウィンドウのものになる。
        // アプリを開く・URL は実行する。練習モードは何も実行しないので、初回の案内のウィンドウがキーでも記録する
        if !isPracticeMode, ControllerExecutionPolicy.dependsOnFrontmostApp(target.cell.action), services.frontmostApp.isOwnWindowKey {
            playHaptic(.rejected, strength: session.settings.haptics)
            refuseInOwnWindow(target)
            return
        }
        playHaptic(.execute, strength: session.settings.haptics)
        if isPracticeMode {
            record(target, succeeded: true, message: nil, isPractice: true)
            return
        }
        let context = ActionContext(frontmostApp: session.frontmostApp)
        executions.enqueue { [weak self] turn in
            _ = await self?.perform(target, context: context, turn: turn, showsSuccessAfterRunning: true)
        }
    }

    /// 前の実行が順番を譲ってから呼ばれる。結果の表示と記録は、順番を譲った後でも終わったときに行う。
    /// 長く掛かるマスは、runningToastDelay で終わらなければ「実行中」のトーストを出し、終わったら結果のパネル・失敗のトースト・
    /// 成功のトースト（showsSuccessAfterRunning なら）に置き換えるか、消す
    private func perform(
        _ target: ControllerTarget,
        context: ActionContext,
        turn: ControllerExecutionTurn,
        showsSuccessAfterRunning: Bool
    ) async -> ExecutionRecord {
        // 長く掛かるアクション（裏のスクリプト・ショートカット・AI）は、文脈を読み終えるころに順番を譲る。
        // 終わるまで待たせると、後のマスが数十秒後に、押したときとは別のアプリへまとめて送られる
        turn.pass(after: ControllerExecutionPolicy.hold(for: target.cell.action))
        var context = context
        // 文脈を読み終えたら、上限を待たずに譲る。ほかのアクション（ターミナルのスクリプト・ゴミ箱に入れる）は、終わるまで譲らない
        if ControllerExecutionPolicy.isLongRunning(target.cell.action) {
            let scheduler = services.scheduler
            let start = scheduler.now
            context.didReadContext = { [weak turn] in
                // 始めてから longRunningMinimumHold は待たせる（pass(after:) は前に決めた時間より早くするだけ）
                turn?.pass(after: ControllerExecutionPolicy.longRunningMinimumHold - (scheduler.now - start))
            }
        }
        let run = startRunningToast(for: target)
        do {
            let output = try await services.performer.performReturningOutput(target.cell.action, context: context)
            let didShowRunning = finishRunningToast(run)
            if let output {
                hideRunningToast(run)
                hud.showResult(ControllerPresentation.result(target.cell, output: output))
            } else if didShowRunning && showsSuccessAfterRunning {
                showToast(ControllerPresentation.successToast(target.cell))
            } else {
                hideRunningToast(run)
            }
            return record(target, succeeded: true, message: nil, output: output)
        } catch {
            finishRunningToast(run)
            return fail(target, error: error)
        }
    }

    /// 「実行中」のトーストを出す予定
    private struct RunningToast {
        var id: Int
        var task: (any ScheduledTask)?
    }

    /// 長く掛かるマスなら、runningToastDelay 後に「実行中」のトーストを出す予定を入れる
    private func startRunningToast(for target: ControllerTarget) -> RunningToast? {
        guard ControllerExecutionPolicy.isLongRunning(target.cell.action) else { return nil }
        let id = nextRunID
        nextRunID += 1
        let task = services.scheduler.schedule(after: Self.runningToastDelay) { [weak self] in
            guard let self else { return }
            self.showToast(ControllerPresentation.runningToast(target.cell))
            self.shownRunningToasts.insert(id)
            self.visibleRunningToast = id
        }
        return RunningToast(id: id, task: task)
    }

    /// 実行が終わった。「実行中」のトーストを出していたか
    @discardableResult
    private func finishRunningToast(_ run: RunningToast?) -> Bool {
        guard let run else { return false }
        run.task?.cancel()
        return shownRunningToasts.remove(run.id) != nil
    }

    /// その実行の「実行中」のトーストがまだ出ていれば消す（ほかのトーストに置き換わっていれば何もしない）
    private func hideRunningToast(_ run: RunningToast?) {
        guard let run, visibleRunningToast == run.id else { return }
        visibleRunningToast = nil
        hud.hideToast()
    }

    @discardableResult
    private func refuseWithoutLicense(_ target: ControllerTarget) -> ExecutionRecord {
        controllerLogger.notice("試用期間が終わっているため実行しません")
        let message = NonetError.licenseRequired.localizedDescription
        showToast(ControllerPresentation.failureToast(target, message: message))
        return record(target, succeeded: false, message: message)
    }

    /// 設定画面からは「このマスをテスト実行」で試せる（直前のアプリを前面に戻してから実行する）
    private func refuseInOwnWindow(_ target: ControllerTarget) {
        controllerLogger.notice("Nonet のウィンドウがキーなので実行しません（\(target.cell.action.kind.rawValue, privacy: .public)）")
        let message = String(localized: "Nonet のウィンドウが前面にあるので実行しませんでした。設定では「このマスをテスト実行」で試せます。", bundle: .module)
        showToast(ControllerPresentation.failureToast(target, message: message))
        record(target, succeeded: false, message: message)
    }

    private func fail(_ target: ControllerTarget, error: any Error) -> ExecutionRecord {
        let message = error.localizedDescription
        // 理由にはスクリプトの出力などが入ることがあるので、ログでは伏せる
        controllerLogger.error("実行に失敗しました（\(target.cell.action.kind.rawValue, privacy: .public)）: \(message, privacy: .private)")
        showToast(ControllerPresentation.failureToast(target, message: message))
        return record(target, succeeded: false, message: message)
    }

    /// isPractice は練習モードの記録（実際には実行していない）。lastExecution にだけ残し、recentExecutions には入れない
    @discardableResult
    private func record(_ target: ControllerTarget, succeeded: Bool, message: String?, output: String? = nil, isPractice: Bool = false) -> ExecutionRecord {
        let record = ExecutionRecord(
            cellTitle: target.cell.title,
            profileName: target.profileName,
            address: target.address,
            succeeded: succeeded,
            message: message,
            date: currentDate(),
            output: output,
            profileID: target.profileID
        )
        lastExecution = record
        if !isPractice {
            recentExecutions.insert(record, at: 0)
            if recentExecutions.count > Self.recentExecutionLimit {
                recentExecutions.removeLast(recentExecutions.count - Self.recentExecutionLimit)
            }
        }
        return record
    }

    // MARK: - 権限とサービス

    /// 権限・トラックパッド・セキュア入力を確かめ、サービスと status をそろえる。有効な間は2秒ごとに確かめ直す
    private func refreshServices() {
        guard isStarted else { return }
        let isEnabled = configuration.settings.isEnabled
        var hasPermission = false
        var isGranted = false
        var hasTrackpad = false
        var isSecureInput = false
        if isEnabled {
            hasPermission = services.permissions.isAccessibilityGranted
            isGranted = hasPermission
            // 許可が無い間はセッションを始められないので、指の位置も読まない（指が触れるたびにメインスレッドを起こさない）
            if hasPermission {
                hasTrackpad = startTouchSource()
                // トラックパッドが無ければ開くことも無いので、イベントタップは作らない
                if hasTrackpad {
                    isGranted = startKeyboard()
                }
            }
            isSecureInput = services.permissions.isSecureInputActive
        }
        let next = ControllerStatus.resolve(
            isEnabled: isEnabled,
            isAccessibilityGranted: isGranted,
            isTrackpadAvailable: hasTrackpad,
            isSecureInputActive: isSecureInput
        )
        setStatus(next)
        if !(isEnabled && isGranted && hasTrackpad) {
            stopKeyboard()
        }
        // 止めるときに触れていた指は離れたことにするので、始め直した後は新しいタッチとして数える。
        // セキュア入力の間は止めない（入ったり出たりが多く、終わったらすぐに使えるようにするため）
        if !(isEnabled && hasPermission) {
            stopTouchSource()
        }
        schedulePoll()
    }

    private func setStatus(_ next: ControllerStatus) {
        // セッションはサービスを止める前に終える（ポインタの抑止を戻し、HUD を閉じる）
        if next != .running {
            endSession()
        }
        guard status != next else { return }
        controllerLogger.info("状態が変わりました: \(String(describing: self.status), privacy: .public) → \(String(describing: next), privacy: .public)")
        status = next
    }

    private func schedulePoll() {
        pollTask?.cancel()
        pollTask = nil
        guard isStarted, configuration.settings.isEnabled else { return }
        pollTask = services.scheduler.schedule(after: Self.pollInterval) { [weak self] in
            guard let self else { return }
            self.pollTask = nil
            self.refreshServices()
        }
    }

    /// 動いていなければ始める。トラックパッドを使えるか
    private func startTouchSource() -> Bool {
        if !isTouchSourceRunning {
            do {
                try services.touchSource.start()
                isTouchSourceRunning = true
                serviceSucceeded("touch")
            } catch {
                serviceFailed("touch", error)
                return false
            }
        }
        return services.touchSource.isAvailable
    }

    private func stopTouchSource() {
        guard isTouchSourceRunning else { return }
        services.touchSource.stop()
        isTouchSourceRunning = false
        // 止めた後はフレームが来ないので、触れていた指は離れたことにする
        receiveTouches(TouchFrame(timestamp: services.scheduler.now, points: []))
    }

    /// 動いていなければ始める。動いているか
    private func startKeyboard() -> Bool {
        let keyboard = services.keyboard
        guard !keyboard.isRunning else { return true }
        // 開いている間にタップが無効になった: 作り直す前にセッションを終える（作り直しでポインタの抑止が外れ、開いたまま残らないように）
        endSession()
        do {
            try keyboard.start()
            // マウスやホイールのイベントを見分けられるよう、トラックパッドに触れているかを先に知らせておく
            keyboard.isTrackpadTouched = isTrackpadTouched
            serviceSucceeded("keyboard")
            controllerLogger.info("キーボードの監視を始めました")
        } catch {
            serviceFailed("keyboard", error)
        }
        return keyboard.isRunning
    }

    private func stopKeyboard() {
        let wasRunning = services.keyboard.isRunning
        endSession()
        // 動いていなくても止める（システムに無効にされたタップと、その後片付けを残さない。止める物が無ければ何もしない）
        services.keyboard.stop()
        if wasRunning {
            controllerLogger.info("キーボードの監視を止めました")
        }
    }

    private func serviceFailed(_ name: String, _ error: any Error) {
        let message = error.localizedDescription
        guard serviceFailures[name] != message else { return }
        serviceFailures[name] = message
        controllerLogger.error("\(name, privacy: .public) を始められません: \(message, privacy: .public)")
    }

    private func serviceSucceeded(_ name: String) {
        serviceFailures[name] = nil
    }

    private func configurationDidChange(from previous: NonetConfiguration) {
        let old = previous.settings
        let new = configuration.settings
        if old.isEnabled != new.isEnabled {
            controllerLogger.info("\(new.isEnabled ? "有効" : "無効", privacy: .public)にしました")
            // 無効にしたら、始まっているセッションは何も実行せずに終える（refreshServices が状態を変えるときに終える）
            refreshServices()
        }
        updateActiveProfile()
    }

    private func updateActiveProfile() {
        guard isStarted else { return }
        let bundleID = services.frontmostApp.current?.app.bundleID
        let name = configuration.resolvedPages(frontmostBundleID: bundleID).first?.profileName
        if activeProfileName != name {
            activeProfileName = name
        }
    }

    // MARK: - 読み込みと保存

    private func loadConfiguration() {
        // stop() の後の変更を先に書いてから読む
        saver.flush()
        saver.isEnabled = true
        let loaded: NonetConfiguration?
        do {
            loaded = try store.load()
        } catch {
            startFromInitialConfiguration(after: error)
            return
        }
        // この版では残せない値のある設定だった（新しい版の Nonet で書いた・知らない種類のマス など）。原本の場所を知らせる
        if let kept = store.takeLastPreservedOriginal() {
            notice = String(localized: "設定ファイルに、この版の Nonet では使えない中身がありました。元のファイルは「\(kept.lastPathComponent)」として残しています。", bundle: .module)
        }
        if let loaded {
            configuration = loaded
            return
        }
        controllerLogger.info("保存された設定が無いので、初回の設定を作ります")
        isFirstLaunch = true
        let capabilities = services.presetEnvironment.capabilities
        configuration = Self.initialConfiguration(services: services, capabilities: capabilities)
        saver.saveNow(configuration)
        rebuildFirstPresetsWhenResolved(builtWith: capabilities)
    }

    /// 初回の設定は claude を調べ終える前に作る（調べ終えていなければ Claude Code のマスは入らない）。
    /// 調べ終えてできることが変わっていて、その間にプロファイルを何も変えていなければ、作り直す（全体の設定はそのまま）
    private func rebuildFirstPresetsWhenResolved(builtWith capabilities: PresetCapabilities) {
        let initialProfiles = configuration.profiles
        let environment = services.presetEnvironment
        firstPresetsRebuild = Task { [weak self] in
            let resolved = await environment.resolvedCapabilities()
            guard let self, !Task.isCancelled, resolved != capabilities else { return }
            guard self.configuration.profiles == initialProfiles else {
                controllerLogger.info("プロファイルが変わっていたので、初回のプリセットは作り直さない")
                return
            }
            var rebuilt = Self.initialConfiguration(services: self.services, capabilities: resolved)
            rebuilt.settings = self.configuration.settings
            self.replaceConfiguration(rebuilt)
            controllerLogger.info("この Mac でできることを調べ終えたので、初回のプリセットを作り直した")
        }
    }

    private func startFromInitialConfiguration(after error: any Error) {
        configuration = Self.initialConfiguration(services: services)
        if case ConfigurationStoreError.corrupted = error {
            // 壊れたファイルは別の名前に移してあるので、初期の設定で置き換える
            controllerLogger.error("設定ファイルが壊れていたので、初期の設定で始めます")
            notice = error.localizedDescription
            saver.saveNow(configuration)
        } else {
            // 読めないファイルを上書きしないよう、この起動の間は保存しない
            controllerLogger.error("設定ファイルを読めないので、保存せずに初期の設定で動かします: \(error.localizedDescription, privacy: .public)")
            saver.isEnabled = false
            // 次の起動でも同じになる（ファイルはそのまま）ので、「終了するまで」とは言わない。控えに戻せば、また保存する
            notice = String(localized: "\(error.localizedDescription)。設定の変更は保存されません。「以前の設定に戻す…」で控えに戻すと、また保存します。", bundle: .module)
        }
    }

    private func saveFinished(_ result: Result<Void, any Error>) {
        switch result {
        case .success:
            if let shown = saveFailureNotice, notice == shown {
                notice = nil
            }
            saveFailureNotice = nil
        case .failure(let error):
            let message = error.localizedDescription
            controllerLogger.error("設定を保存できません: \(message, privacy: .public)")
            saveFailureNotice = message
            notice = message
        }
    }

    private func address(of cell: Cell, in profile: Profile?) -> CellAddress {
        guard let profile else { return CellAddress(page: 0, index: 0) }
        for (pageIndex, page) in profile.pages.enumerated() {
            if let index = page.cells.firstIndex(where: { $0?.id == cell.id }) {
                return CellAddress(page: pageIndex, index: index)
            }
        }
        return CellAddress(page: 0, index: 0)
    }

    /// インストール済みのアプリから作る最初の設定。プリセットはこの Mac でできること（capabilities。nil なら今わかっていること）に合わせる
    /// （claude を調べ終える前なら Claude Code のマスは入らない。調べ終えたら rebuildFirstPresetsWhenResolved が作り直す）
    static func initialConfiguration(services: NonetServices, capabilities: PresetCapabilities? = nil) -> NonetConfiguration {
        let installedLaunchers = PresetLibrary.launcherCandidates
            .map(\.bundleID)
            .filter { services.installedApps.isInstalled(bundleID: $0) }
        let environment = services.presetEnvironment
        let presets = PresetLibrary.apps(for: capabilities ?? environment.capabilities)
            .filter { services.installedApps.isInstalled(bundleID: $0.app.bundleID) }
        return .initial(
            appPresets: presets,
            installedBundleIDs: Set(installedLaunchers),
            dockApps: environment.dockApps()
        )
    }
}

// 担当: engine（公開 API は契約。設定画面・メニューバー・初回起動がこの API を使う）
import Foundation
import Observation
import os

let controllerLogger = Logger(subsystem: "com.iam74k4.Nonet", category: "engine")

public enum ControllerStatus: Equatable, Sendable {
    case stopped
    /// トリガーを待っている
    case running
    /// 設定で無効にしている
    case disabled
    /// アクセシビリティの許可が無い
    case needsAccessibility
    /// マルチタッチのトラックパッドが無い
    case noTrackpad
    /// パスワード入力中などで、キーを監視できない
    case secureInputActive
}

/// 最後に実行したマス
public struct ExecutionRecord: Equatable, Sendable {
    public var cellTitle: String
    public var profileName: String
    public var address: CellAddress
    public var succeeded: Bool
    /// 失敗の理由など
    public var message: String?
    /// HUD を出さずに実行した
    public var wasFastTap: Bool
    public var date: Date

    public init(cellTitle: String, profileName: String, address: CellAddress, succeeded: Bool, message: String?, wasFastTap: Bool, date: Date) {
        self.cellTitle = cellTitle
        self.profileName = profileName
        self.address = address
        self.succeeded = succeeded
        self.message = message
        self.wasFastTap = wasFastTap
        self.date = date
    }
}

/// Nonet の本体。トリガー → 速押し / HUD → 実行 の流れを動かし、設定を持つ。
/// 仕様は docs/architecture.md の「操作の仕様」。セッションの規則は SessionEngine が持ち、
/// ここはキーボード・トラックパッド・タイマーをエンジンに渡し、エンジンの出力を HUD・触覚・実行につなぐ
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

    public private(set) var configuration: NonetConfiguration
    public private(set) var status: ControllerStatus = .stopped
    /// いま前面アプリで使うプロファイルの名前
    public private(set) var activeProfileName: String?
    public private(set) var lastExecution: ExecutionRecord?
    /// true の間はアクションを実行せず、lastExecution に記録だけする（初回起動の練習用）
    public var isPracticeMode = false
    /// true の間はセッションを始めない（設定画面でキーを記録しているとき）
    public var isRecordingKeys = false {
        didSet {
            // 記録するキーで HUD が出たりマスが実行されたりしないように、始まっているセッションは何も実行せずに終える
            if isRecordingKeys, !oldValue {
                endSession()
            }
        }
    }
    /// 保存された設定が無かった（初回起動）
    public private(set) var isFirstLaunch = false
    /// 利用者に知らせたい問題（設定ファイルが壊れていた・保存できない など）。設定画面とメニューに出す
    public private(set) var notice: String?

    @ObservationIgnored private let services: NonetServices
    @ObservationIgnored private let store: ConfigurationStore
    @ObservationIgnored private let hud: any HUDPresenting
    @ObservationIgnored private let license: LicenseManager
    @ObservationIgnored private let saver: ControllerConfigurationSaver
    @ObservationIgnored private let executions = ControllerExecutionQueue()
    @ObservationIgnored private var engine = SessionEngine()
    /// いまのセッションで使うもの。セッションの外は nil
    @ObservationIgnored private var session: ControllerSession?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isTouchSourceRunning = false
    @ObservationIgnored private var isHUDVisible = false
    @ObservationIgnored private var tickTask: (any ScheduledTask)?
    @ObservationIgnored private var pollTask: (any ScheduledTask)?
    /// エンジンの出力を処理している間に来た入力（出力の処理からエンジンを呼び直さないように、順に処理する）
    @ObservationIgnored private var pendingInputs: [(input: SessionInput, starting: ControllerSession?)] = []
    @ObservationIgnored private var isHandlingInput = false
    /// サービスごとの直近の失敗。2秒ごとの確かめ直しで、同じ失敗を何度もログに書かないため
    @ObservationIgnored private var serviceFailures: [String: String] = [:]
    /// 保存の失敗で出した notice。保存できたら消す
    @ObservationIgnored private var saveFailureNotice: String?

    public init(services: NonetServices, store: ConfigurationStore, hud: any HUDPresenting, license: LicenseManager) {
        self.services = services
        self.store = store
        self.hud = hud
        self.license = license
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
        // セッションの外のフレームも渡す（トリガーより前から置いていた指を速押しと間違えないため）
        services.touchSource.onFrame = { [weak self] frame in
            self?.send(.touches(frame))
        }
        services.frontmostApp.onChange = { [weak self] _ in
            self?.updateActiveProfile()
        }
        services.frontmostApp.start()
        applyKeyboardSettings()
        refreshServices()
        updateActiveProfile()
        controllerLogger.info("開始しました（状態: \(String(describing: self.status), privacy: .public)）")
    }

    /// 監視をすべて止める。セッション中なら何も実行せずに終え（ポインタの抑止をやめ、HUD を閉じる）、待っている保存を書く
    public func stop() {
        if isStarted {
            endSession()
            isStarted = false
            tickTask?.cancel()
            tickTask = nil
            pollTask?.cancel()
            pollTask = nil
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
            controllerLogger.info("停止しました")
        }
        saver.flush()
        status = .stopped
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

    /// 設定画面の「テスト実行」。アプリのプロファイルなら、そのアプリを前面に出してから実行する。
    /// 練習モードでも実行する（試用中にマスを試すための機能）が、試用期間が終わっていれば licenseRequired で失敗する
    @discardableResult
    public func testRun(_ cell: Cell, profileID: UUID) async -> ExecutionRecord {
        let profile = configuration.profile(id: profileID)
        let target = ControllerTarget(cell: cell, profileName: profile?.name ?? "", address: address(of: cell, in: profile))
        guard license.canExecuteActions else {
            return refuseWithoutLicense(target, wasFastTap: false)
        }
        let app = profile?.app
        return await executions.enqueue {
            await self.runTest(target, activating: app)
        }.value
    }

    private func runTest(_ target: ControllerTarget, activating app: AppReference?) async -> ExecutionRecord {
        if let app {
            do {
                let activate = Action.launchApp(LaunchAppAction(app: app, hideIfFrontmost: false))
                try await services.performer.perform(activate, context: ActionContext(frontmostApp: services.frontmostApp.current))
            } catch {
                // 別のアプリにキーを送らないよう、マスは実行しない
                return fail(target, wasFastTap: false, error: error)
            }
            await waitUntilFrontmost(app)
        }
        return await perform(target, context: ActionContext(frontmostApp: services.frontmostApp.current), wasFastTap: false, showsSuccessToast: false)
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

    private func isFrontmost(_ app: AppReference) -> Bool {
        guard let current = services.frontmostApp.current else { return false }
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

    private func handleKeyboard(_ event: KeyboardEvent) {
        let now = services.scheduler.now
        switch event {
        case .triggerDown:
            guard canBeginSession() else { return }
            let next = ControllerSession(configuration: configuration, frontmostApp: services.frontmostApp.current)
            // エンジンの beginPointerSuppression で、この呼び出しの中で isSuppressingPointer を true にする（直後のポインタイベントを取りこぼさない）
            send(.triggerDown(at: now, configuration: next.engineConfiguration), starting: next)
            refreshLicenseAfterTrigger()
        case .triggerUp:
            send(.triggerUp(at: now))
        case .interrupted:
            send(.interrupted(at: now))
        }
    }

    private func canBeginSession() -> Bool {
        guard isStarted, !isRecordingKeys else { return false }
        // セキュア入力は2秒ごとにしか確かめないので、パスワード欄を離れた直後のトリガーのために確かめ直す
        if status == .secureInputActive {
            refreshServices()
        }
        return status == .running
    }

    /// 表示用の entitlement を新しくする（日付が変わった後の残り日数など）。
    /// 保存先への書き込みがあるので、トリガーのイベントを返してから行う。実行してよいかは canExecuteActions がいつでも正しく答える
    private func refreshLicenseAfterTrigger() {
        services.scheduler.schedule(after: 0) { [weak self] in
            self?.license.refresh()
        }
    }

    // MARK: - エンジン

    /// starting はトリガーを押したときに決めた、新しいセッションで使うもの
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
            services.keyboard.isSuppressingPointer = true
        case .endPointerSuppression:
            services.keyboard.isSuppressingPointer = false
        case .showHUD(let page, let highlightedCell):
            guard let session else { return }
            hud.show(hudModel(session, page: page, highlightedCell: highlightedCell), position: session.settings.hudPosition)
            isHUDVisible = true
        case .updateHUD(let page, let highlightedCell):
            guard let session, isHUDVisible else { return }
            hud.update(hudModel(session, page: page, highlightedCell: highlightedCell))
        case .hideHUD:
            hideHUD()
        case .haptic(let event):
            playHaptic(event, strength: session?.settings.haptics ?? configuration.settings.haptics)
        case .execute(let page, let cell, let wasFastTap):
            guard let session else { return }
            execute(page: page, cell: cell, wasFastTap: wasFastTap, in: session)
        case .requestTick(let time):
            scheduleTick(at: time)
        case .sessionEnded(let reason):
            tickTask?.cancel()
            tickTask = nil
            if services.keyboard.isSuppressingPointer {
                services.keyboard.isSuppressingPointer = false
            }
            hideHUD()
            session = nil
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

    private func hudModel(_ session: ControllerSession, page: Int, highlightedCell: Int?) -> HUDModel {
        session.hudModel(page: page, highlightedCell: highlightedCell, isPracticeMode: isPracticeMode, isTrialEnded: !license.canExecuteActions)
    }

    private func hideHUD() {
        guard isHUDVisible else { return }
        isHUDVisible = false
        hud.hide()
    }

    private func playHaptic(_ event: HapticEvent, strength: HapticStrength) {
        guard strength != .off else { return }
        services.haptics.play(event, strength: strength)
    }

    // MARK: - 実行

    private func execute(page: Int, cell: Int, wasFastTap: Bool, in session: ControllerSession) {
        // 空きマスは何もしない（触覚も鳴らさない）
        guard let target = session.target(page: page, cell: cell) else { return }
        guard license.canExecuteActions else {
            refuseWithoutLicense(target, wasFastTap: wasFastTap)
            return
        }
        playHaptic(.execute, strength: session.settings.haptics)
        if isPracticeMode {
            record(target, succeeded: true, message: nil, wasFastTap: wasFastTap)
            return
        }
        let context = ActionContext(frontmostApp: session.frontmostApp)
        let showsSuccessToast = wasFastTap && session.settings.showExecutionToast
        executions.enqueue { [weak self] in
            _ = await self?.perform(target, context: context, wasFastTap: wasFastTap, showsSuccessToast: showsSuccessToast)
        }
    }

    private func perform(_ target: ControllerTarget, context: ActionContext, wasFastTap: Bool, showsSuccessToast: Bool) async -> ExecutionRecord {
        do {
            let output = try await services.performer.performReturningOutput(target.cell.action, context: context)
            if let output {
                hud.showResult(ControllerPresentation.result(target.cell, output: output))
            } else if showsSuccessToast {
                hud.showToast(ControllerPresentation.successToast(target.cell))
            }
            return record(target, succeeded: true, message: nil, wasFastTap: wasFastTap)
        } catch {
            return fail(target, wasFastTap: wasFastTap, error: error)
        }
    }

    @discardableResult
    private func refuseWithoutLicense(_ target: ControllerTarget, wasFastTap: Bool) -> ExecutionRecord {
        controllerLogger.notice("試用期間が終わっているため実行しません")
        let message = NonetError.licenseRequired.localizedDescription
        hud.showToast(ControllerPresentation.failureToast(target.cell, message: message))
        return record(target, succeeded: false, message: message, wasFastTap: wasFastTap)
    }

    private func fail(_ target: ControllerTarget, wasFastTap: Bool, error: any Error) -> ExecutionRecord {
        let message = error.localizedDescription
        // 理由にはスクリプトの出力などが入ることがあるので、ログでは伏せる
        controllerLogger.error("実行に失敗しました（\(target.cell.action.kind.rawValue, privacy: .public)）: \(message, privacy: .private)")
        hud.showToast(ControllerPresentation.failureToast(target.cell, message: message))
        return record(target, succeeded: false, message: message, wasFastTap: wasFastTap)
    }

    @discardableResult
    private func record(_ target: ControllerTarget, succeeded: Bool, message: String?, wasFastTap: Bool) -> ExecutionRecord {
        let record = ExecutionRecord(
            cellTitle: target.cell.title,
            profileName: target.profileName,
            address: target.address,
            succeeded: succeeded,
            message: message,
            wasFastTap: wasFastTap,
            date: Date()
        )
        lastExecution = record
        return record
    }

    // MARK: - 権限とサービス

    /// 権限・トラックパッド・セキュア入力を確かめ、サービスと status をそろえる。有効な間は2秒ごとに確かめ直す
    private func refreshServices() {
        guard isStarted else { return }
        let isEnabled = configuration.settings.isEnabled
        var isGranted = false
        var hasTrackpad = false
        var isSecureInput = false
        if isEnabled {
            hasTrackpad = startTouchSource()
            isGranted = services.permissions.isAccessibilityGranted
            // トラックパッドが無ければキーボードは見張らない（トリガーを飲み込む設定のとき、使えないキーにしないため）
            if isGranted, hasTrackpad {
                isGranted = startKeyboard()
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
        if !isEnabled {
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
        send(.touches(TouchFrame(timestamp: services.scheduler.now, points: [])))
    }

    /// 動いていなければ始める。動いているか
    private func startKeyboard() -> Bool {
        let keyboard = services.keyboard
        guard !keyboard.isRunning else { return true }
        do {
            try keyboard.start()
            serviceSucceeded("keyboard")
            controllerLogger.info("キーボードの監視を始めました")
        } catch {
            serviceFailed("keyboard", error)
        }
        return keyboard.isRunning
    }

    private func stopKeyboard() {
        guard services.keyboard.isRunning else { return }
        endSession()
        services.keyboard.stop()
        controllerLogger.info("キーボードの監視を止めました")
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

    private func applyKeyboardSettings() {
        let settings = configuration.settings
        let keyboard = services.keyboard
        if keyboard.trigger != settings.trigger {
            keyboard.trigger = settings.trigger
        }
        if keyboard.passTriggerToApps != settings.passTriggerToApps {
            keyboard.passTriggerToApps = settings.passTriggerToApps
        }
        if keyboard.cursorLock != settings.cursorLock {
            keyboard.cursorLock = settings.cursorLock
        }
    }

    private func configurationDidChange(from previous: NonetConfiguration) {
        let old = previous.settings
        let new = configuration.settings
        if old.isEnabled != new.isEnabled || old.trigger != new.trigger || old.passTriggerToApps != new.passTriggerToApps {
            // 押しているキーの扱いが変わるので、始まっているセッションは何も実行せずに終える
            endSession()
        }
        applyKeyboardSettings()
        if old.isEnabled != new.isEnabled {
            controllerLogger.info("\(new.isEnabled ? "有効" : "無効", privacy: .public)にしました")
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
        if let loaded {
            configuration = loaded
            return
        }
        controllerLogger.info("保存された設定が無いので、初回の設定を作ります")
        isFirstLaunch = true
        configuration = Self.initialConfiguration(services: services)
        saver.saveNow(configuration)
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
            notice = String(localized: "\(error.localizedDescription)。Nonet を終了するまで、設定の変更は保存されません", bundle: .module)
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

    /// インストール済みのアプリから作る最初の設定
    static func initialConfiguration(services: NonetServices) -> NonetConfiguration {
        let installedLaunchers = PresetLibrary.launcherCandidates
            .map(\.bundleID)
            .filter { services.installedApps.isInstalled(bundleID: $0) }
        let presets = PresetLibrary.apps.filter { services.installedApps.isInstalled(bundleID: $0.app.bundleID) }
        return .initial(
            trigger: .defaultKey(isJIS: services.isJISKeyboard),
            appPresets: presets,
            installedBundleIDs: Set(installedLaunchers)
        )
    }
}

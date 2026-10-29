// 担当: engine。NonetController を偽物のサービスで組み立て、キーボード・指・時計を台本のように動かす
import Foundation
@testable import NonetCore

enum ControllerFixtures {
    static let safari = AppReference(bundleID: "com.apple.Safari", name: "Safari")
    static let safariApp = RunningAppInfo(app: safari, processID: 501)
    static let notes = AppReference(bundleID: "com.apple.Notes", name: "メモ")
    static let notesApp = RunningAppInfo(app: notes, processID: 777)

    // Safari のプロファイル（1ページ目）
    static let newTab = Cell(title: "新しいタブ", icon: .symbol("plus.square"), action: .keystroke(.key("t", [.command])))
    static let closeTab = Cell(title: "タブを閉じる", icon: .symbol("xmark"), action: .keystroke(.key("w", [.command])))
    static let summarize = Cell(title: "要約", icon: .symbol("sparkles"), action: .ai(AIAction(prompt: "要約して", output: .showResult)))
    static let reader = Cell(title: "リーダー", icon: .symbol("book"), action: .menuItem(MenuItemAction(app: safari, path: ["表示", "リーダーを表示"])))
    // Safari のプロファイル（2ページ目）
    static let reload = Cell(title: "再読み込み", icon: .symbol("arrow.clockwise"), action: .keystroke(.key("r", [.command])))
    // グローバル
    static let openNotes = Cell(title: "メモ", icon: .app(bundleID: notes.bundleID), action: .launchApp(LaunchAppAction(app: notes)))
    static let docs = Cell(title: "ドキュメント", icon: .text("D"), action: .openURL(URLAction(url: "https://example.com/docs")))

    /// Safari: [新しいタブ, 空, タブを閉じる, 空, 要約, 空, 空, 空, リーダー] と [再読み込み]。
    /// グローバル: [メモ, 空, …, ドキュメント（8）]。トリガーは右⌥
    static func configuration(settings: GlobalSettings = GlobalSettings(trigger: .rightOption)) -> NonetConfiguration {
        let global = Profile(kind: .global, pages: [Page(cells: [openNotes, nil, nil, nil, nil, nil, nil, nil, docs])])
        let safariProfile = Profile(kind: .app(safari), pages: [
            Page(cells: [newTab, nil, closeTab, nil, summarize, nil, nil, nil, reader]),
            Page(cells: [reload]),
        ])
        return NonetConfiguration(settings: settings, profiles: [global, safariProfile]).validated()
    }

    static func settings(_ transform: (inout GlobalSettings) -> Void) -> GlobalSettings {
        var settings = GlobalSettings(trigger: .rightOption)
        transform(&settings)
        return settings
    }
}

@MainActor
final class ControllerHarness {
    let recorder = ControllerFakeRecorder()
    let scheduler = ControllerFakeScheduler()
    let permissions = ControllerFakePermissions()
    let touchSource = ControllerFakeTouchSource()
    let keyboard: ControllerFakeKeyboard
    let haptics: ControllerFakeHaptics
    let performer: ControllerFakePerformer
    let frontmost = ControllerFakeFrontmostApp()
    let installedApps: ControllerFakeInstalledApps
    let hud: ControllerFakeHUD
    let directory: URL
    let store: ConfigurationStore
    let clock = ControllerFakeClock(Date(timeIntervalSinceReferenceDate: 815_000_000))
    let licenseStorage = ControllerFakeLicenseStorage()
    let license: LicenseManager
    let controller: NonetController
    /// いま触れている指
    private var fingers: [Int: (x: Double, y: Double)] = [:]

    /// configuration を保存してから組み立てる（nil なら設定ファイルの無い初回起動）。
    /// trialEnded なら試用期間が終わっている。frontmost はトリガーを押すときの前面アプリ
    init(
        configuration: NonetConfiguration? = ControllerFixtures.configuration(),
        trialEnded: Bool = false,
        isJISKeyboard: Bool = false,
        installed: Set<String> = [],
        frontmost app: RunningAppInfo? = ControllerFixtures.safariApp
    ) throws {
        keyboard = ControllerFakeKeyboard(recorder: recorder, permissions: permissions)
        haptics = ControllerFakeHaptics(recorder: recorder)
        performer = ControllerFakePerformer(recorder: recorder)
        installedApps = ControllerFakeInstalledApps(bundleIDs: installed)
        hud = ControllerFakeHUD(recorder: recorder)
        directory = FileManager.default.temporaryDirectory.appending(path: "NonetControllerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ConfigurationStore(directory: directory)
        if let configuration {
            try store.save(configuration)
        }
        if trialEnded {
            licenseStorage.trialStartDate = clock.now.addingTimeInterval(-30 * 86_400)
        }
        license = LicenseManager(verifier: nil, storage: licenseStorage, now: clock.closure)
        frontmost.current = app
        let services = NonetServices(
            touchSource: touchSource,
            keyboard: keyboard,
            haptics: haptics,
            performer: performer,
            frontmostApp: frontmost,
            menus: ControllerFakeMenus(),
            permissions: permissions,
            installedApps: installedApps,
            shortcuts: ControllerFakeShortcuts(),
            ai: ControllerFakeAI(),
            loginItem: ControllerFakeLoginItem(),
            scheduler: scheduler,
            isJISKeyboard: isJISKeyboard
        )
        controller = NonetController(services: services, store: store, hud: hud, license: license)
    }

    deinit {
        // 読めない設定を試すテストが権限を変えていても消せるように戻す
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path(percentEncoded: false))
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: 操作

    func start() {
        controller.start()
    }

    func pressTrigger() {
        keyboard.send(.triggerDown)
    }

    func releaseTrigger() {
        keyboard.send(.triggerUp)
    }

    func interrupt() {
        keyboard.send(.interrupted)
    }

    func advance(_ seconds: TimeInterval) {
        scheduler.advance(by: seconds)
    }

    /// 指を置く・動かす（マスの中央へ）
    func touch(_ id: Int = 1, on cell: Int) {
        fingers[id] = Pad.center(cell)
        sendFrame()
    }

    func touch(_ id: Int = 1, x: Double, y: Double) {
        fingers[id] = (x, y)
        sendFrame()
    }

    func lift(_ id: Int = 1) {
        fingers[id] = nil
        sendFrame()
    }

    func sendFrame() {
        let points = fingers.keys.sorted().compactMap { id in
            fingers[id].map { TouchPoint(id: id, x: $0.x, y: $0.y) }
        }
        touchSource.send(TouchFrame(timestamp: scheduler.now, points: points))
    }

    /// トリガーを押したまま、hudDelay より短くマスをタップする
    func tap(_ cell: Int) {
        advance(0.05)
        touch(on: cell)
        advance(0.05)
        lift()
        advance(0.05)
    }

    /// トリガーを押し、マスを速押しして、トリガーを離す
    func fastTap(_ cell: Int) {
        pressTrigger()
        tap(cell)
        releaseTrigger()
    }

    /// 頼んだ実行がすべて終わるまで待つ
    func settle() async {
        await controller.waitForExecutions()
    }

    /// 非同期の処理が進むまで待つ（条件が成り立つか、十分に譲るまで）
    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
    }

    // MARK: 調べる

    func savedConfiguration() throws -> NonetConfiguration? {
        try store.load()
    }

    func fileData() throws -> Data {
        try Data(contentsOf: store.fileURL)
    }

    func profileID(_ app: AppReference) throws -> UUID {
        guard let id = controller.configuration.appProfile(forBundleID: app.bundleID)?.id else {
            throw ControllerHarnessError.missingProfile
        }
        return id
    }
}

enum ControllerHarnessError: Error {
    case missingProfile
}

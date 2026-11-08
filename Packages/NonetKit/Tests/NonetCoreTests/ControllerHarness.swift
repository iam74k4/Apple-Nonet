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
    /// グローバル: [メモ, 空, …, ドキュメント（8）]
    static func configuration(settings: GlobalSettings = GlobalSettings()) -> NonetConfiguration {
        let global = Profile(kind: .global, pages: [Page(cells: [openNotes, nil, nil, nil, nil, nil, nil, nil, docs])])
        let safariProfile = Profile(kind: .app(safari), pages: [
            Page(cells: [newTab, nil, closeTab, nil, summarize, nil, nil, nil, reader]),
            Page(cells: [reload]),
        ])
        return NonetConfiguration(settings: settings, profiles: [global, safariProfile]).validated()
    }

    static func settings(_ transform: (inout GlobalSettings) -> Void) -> GlobalSettings {
        var settings = GlobalSettings()
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
    let windowPlacer = ControllerFakeWindowPlacer()
    let directory: URL
    let store: ConfigurationStore
    let clock = ControllerFakeClock(Date(timeIntervalSinceReferenceDate: 815_000_000))
    let licenseStorage = ControllerFakeLicenseStorage()
    /// 使い始めの案内と試用期間の知らせの記録（UserDefaults に書かない）。既定は使い始めの案内を出し終えた人
    let guidance = MemoryHUDGuidanceStore()
    let license: LicenseManager
    let controller: NonetController
    /// いま触れている指
    private var fingers: [Int: (x: Double, y: Double)] = [:]
    /// 指ごとの接触の長径（TouchPoint.majorAxis）。無い指は nil（大きさが分からない）
    var majorAxes: [Int: Double] = [:]

    /// configuration を保存してから組み立てる（nil なら設定ファイルの無い初回起動）。
    /// trialEnded なら試用期間が終わっている。trialDaysUsed は試用を使った日数（残り日数の知らせを試す）。
    /// licensed ならライセンスを登録済み。frontmost は9マスを開くときの前面アプリ
    init(
        configuration: NonetConfiguration? = ControllerFixtures.configuration(),
        trialEnded: Bool = false,
        trialDaysUsed: Double? = nil,
        licensed: Bool = false,
        installed: Set<String> = [],
        frontmost app: RunningAppInfo? = ControllerFixtures.safariApp,
        presetEnvironment: any PresetEnvironmentProviding = FixedPresetEnvironment()
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
        } else if let trialDaysUsed {
            licenseStorage.trialStartDate = clock.now.addingTimeInterval(-trialDaysUsed * 86_400)
        }
        var verifier: LicenseVerifier?
        if licensed {
            verifier = try LicenseTestFixtures.verifier()
            licenseStorage.licenseKey = try LicenseTestFixtures.licenseKey()
        }
        license = LicenseManager(verifier: verifier, storage: licenseStorage, now: clock.closure)
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
            presetEnvironment: presetEnvironment,
            windowPlacer: windowPlacer
        )
        controller = NonetController(services: services, store: store, hud: hud, license: license, guidance: guidance)
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

    /// 開いている間にキーを押した（本物のモニターは開いている間だけ知らせる）
    func pressKey() {
        keyboard.pressKey()
    }

    /// 上の縁の帯で触れ始めた指の高さと、開くまでに下へ滑らせた後の高さ
    static let edgeY = 0.98
    static let slidY = 0.92

    /// 上の縁から指を下へ滑り込ませて9マスを開く（触れて 0.05 秒で 0.06 下へ。EdgeSlideRecognizer）。
    /// 見分けてから実際に開くまで、entryConfirmDelay 待つ。開いた後の指は上の外枠にいる
    func open(_ id: Int = 1, x: Double = 0.5) {
        touch(id, x: x, y: Self.edgeY)
        advance(0.05)
        touch(id, x: x, y: Self.slidY)
        advance(EdgeSlideRecognizer.entryConfirmDelay)
    }

    /// 開いて、マスまで滑らせ、dwell だけ止めてから離す（ふつうのマスは 0.15 秒止めれば実行する）
    func run(_ cell: Int, dwell: TimeInterval = 0.2) {
        open()
        choose(cell, dwell: dwell)
    }

    /// 開いていれば（指が触れていれば）マスまで滑らせ、dwell だけ止めてから離す。閉じていれば開いてから
    func choose(_ cell: Int, dwell: TimeInterval = 0.2) {
        if fingers.isEmpty {
            open()
        }
        advance(0.05)
        touch(on: cell)
        advance(dwell)
        lift()
        advance(0.05)
    }

    /// 開いていれば、いまの場所で指を離して閉じる
    func closeIfOpen() {
        guard !fingers.isEmpty else { return }
        lift()
        advance(0.05)
    }

    /// 開いたまま、いまの場所で指を離す（開いた直後なら上の外枠なので、何もせずに閉じる）
    func liftAndClose() {
        lift()
        advance(0.05)
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

    /// 触れている指をまとめて入れ替えたフレームを1つ送る（同じフレームで指が離れ、別の指が触れた）
    func replaceFingers(with points: [Int: (x: Double, y: Double)]) {
        fingers = points
        sendFrame()
    }

    /// トラックパッドの続きが来なくなり、トラックパッドの側が指を離れたことにしたフレームを送る（切断・スリープ明け）
    func synthesizedLift() {
        fingers.removeAll()
        touchSource.send(TouchFrame(timestamp: scheduler.now, points: [], isSynthesizedLift: true))
    }

    func sendFrame() {
        let points = fingers.keys.sorted().compactMap { id in
            fingers[id].map { TouchPoint(id: id, x: $0.x, y: $0.y, majorAxis: majorAxes[id]) }
        }
        touchSource.send(TouchFrame(timestamp: scheduler.now, points: points))
    }

    /// 頼んだ実行がすべて終わるまで待つ
    func settle() async {
        await controller.waitForExecutions()
    }

    /// 非同期の処理が進むまで待つ（条件が成り立つか、十分に譲るまで）
    func waitUntil(_ condition: () -> Bool) async {
        await controllerWaitUntil(condition)
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

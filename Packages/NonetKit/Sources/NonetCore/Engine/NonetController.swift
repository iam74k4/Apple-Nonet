// 担当: engine（公開 API は契約。設定画面・メニューバー・初回起動がこの API を使う）
import Foundation
import Observation

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
/// 仕様は docs/architecture.md の「操作の仕様」
///
/// 暫定実装（統合担当）: 設定の読み書きと権限の状態だけ動く。セッションは engine-controller が実装する
@MainActor
@Observable
public final class NonetController {
    public private(set) var configuration: NonetConfiguration
    public private(set) var status: ControllerStatus = .stopped
    /// いま前面アプリで使うプロファイルの名前
    public private(set) var activeProfileName: String?
    public private(set) var lastExecution: ExecutionRecord?
    /// true の間はアクションを実行せず、lastExecution に記録だけする（初回起動の練習用）
    public var isPracticeMode = false
    /// true の間はセッションを始めない（設定画面でキーを記録しているとき）
    public var isRecordingKeys = false
    /// 保存された設定が無かった（初回起動）
    public private(set) var isFirstLaunch = false
    /// 利用者に知らせたい問題（設定ファイルが壊れていた・保存できない など）。設定画面とメニューに出す
    public private(set) var notice: String?

    @ObservationIgnored private let services: NonetServices
    @ObservationIgnored private let store: ConfigurationStore
    @ObservationIgnored private let hud: any HUDPresenting
    @ObservationIgnored private let license: LicenseManager

    public init(services: NonetServices, store: ConfigurationStore, hud: any HUDPresenting, license: LicenseManager) {
        self.services = services
        self.store = store
        self.hud = hud
        self.license = license
        configuration = NonetConfiguration(profiles: []).validated()
    }

    /// 設定を読み、監視を始める。権限が無ければ status で知らせ、許可されたら自動で動き出す
    public func start() {
        loadConfiguration()
        refreshPermissions()
    }

    public func stop() {
        status = .stopped
    }

    /// 設定を変えて保存し、すぐに反映する
    public func update(_ transform: (inout NonetConfiguration) -> Void) {
        var changed = configuration
        transform(&changed)
        replaceConfiguration(changed)
    }

    public func replaceConfiguration(_ configuration: NonetConfiguration) {
        self.configuration = configuration.validated()
        save()
        refreshPermissions()
    }

    /// 設定画面の「テスト実行」。アプリのプロファイルなら、そのアプリを前面に出してから実行する
    @discardableResult
    public func testRun(_ cell: Cell, profileID: UUID) async -> ExecutionRecord {
        let profile = configuration.profile(id: profileID)
        var record = ExecutionRecord(
            cellTitle: cell.title,
            profileName: profile?.name ?? "",
            address: address(of: cell, in: profile),
            succeeded: true,
            message: nil,
            wasFastTap: false,
            date: Date()
        )
        do {
            try await services.performer.perform(cell.action, context: ActionContext(frontmostApp: services.frontmostApp.current))
        } catch {
            record.succeeded = false
            record.message = error.localizedDescription
        }
        lastExecution = record
        return record
    }

    /// 権限の状態を確かめ直す（設定画面や初回起動から呼ぶ）
    public func refreshPermissions() {
        if !configuration.settings.isEnabled {
            status = .disabled
        } else if !services.permissions.isAccessibilityGranted {
            status = .needsAccessibility
        } else {
            status = .running
        }
    }

    public func dismissNotice() {
        notice = nil
    }

    private func loadConfiguration() {
        do {
            if let loaded = try store.load() {
                configuration = loaded
                return
            }
            isFirstLaunch = true
        } catch {
            notice = error.localizedDescription
        }
        configuration = Self.initialConfiguration(services: services)
        save()
    }

    private func save() {
        do {
            try store.save(configuration)
        } catch {
            notice = error.localizedDescription
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

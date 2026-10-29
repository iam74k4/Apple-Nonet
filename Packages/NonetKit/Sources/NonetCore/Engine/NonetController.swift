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

    public init(services: NonetServices, store: ConfigurationStore, hud: any HUDPresenting, license: LicenseManager) {
        fatalError("未実装: engine")
    }

    /// 設定を読み、監視を始める。権限が無ければ status で知らせ、許可されたら自動で動き出す
    public func start() {
        fatalError("未実装: engine")
    }

    public func stop() {
        fatalError("未実装: engine")
    }

    /// 設定を変えて保存し、すぐに反映する
    public func update(_ transform: (inout NonetConfiguration) -> Void) {
        fatalError("未実装: engine")
    }

    public func replaceConfiguration(_ configuration: NonetConfiguration) {
        fatalError("未実装: engine")
    }

    /// 設定画面の「テスト実行」。アプリのプロファイルなら、そのアプリを前面に出してから実行する
    @discardableResult
    public func testRun(_ cell: Cell, profileID: UUID) async -> ExecutionRecord {
        fatalError("未実装: engine")
    }

    /// 権限の状態を確かめ直す（設定画面や初回起動から呼ぶ）
    public func refreshPermissions() {
        fatalError("未実装: engine")
    }
}

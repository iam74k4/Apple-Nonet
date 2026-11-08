// 担当: platform-actions
import Foundation
import NonetCore
import ServiceManagement

/// SMAppService でログイン時に起動する
@MainActor
public final class SMAppServiceLoginItem: LoginItemControlling {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public var isRegistered: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    public func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        do {
            if enabled {
                guard service.status != .enabled else { return }
                try service.register()
            } else {
                guard service.status == .enabled || service.status == .requiresApproval else { return }
                try service.unregister()
            }
        } catch {
            ActionLog.logger.error("ログイン項目を変更できませんでした: \(error.localizedDescription)")
            // 呼んだ側が「ログイン時に起動するように設定できませんでした（理由）」と包むので、理由（SMAppService のエラー）だけを渡す
            if enabled, service.status != .requiresApproval {
                throw NonetError.actionFailed(error.localizedDescription)
            } else if !enabled {
                throw NonetError.actionFailed(error.localizedDescription)
            }
        }
        // 登録はできたが、システム設定の「ログイン項目」で許可されるまで動かない
        if enabled, service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            throw NonetError.permissionDenied(String(localized: "ログイン項目", bundle: .nonetActions))
        }
    }
}

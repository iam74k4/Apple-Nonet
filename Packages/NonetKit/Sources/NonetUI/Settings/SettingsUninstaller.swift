// 担当: ui-settings
// 情報のタブの「Nonet をアンインストール…」。消さずにゴミ箱に入れるので、ゴミ箱を空にするまでは元に戻せる。
// ライセンスキーと試用の記録（環境設定とキーチェーン）は残す: 入れ直せば登録し直さずに使え、試用期間もやり直しにならない
import AppKit
import NonetCore
import os

private let uninstallLog = Logger(subsystem: "com.iam74k4.Nonet", category: "ui-settings")

/// ゴミ箱に入れる（テストでは偽物にする）
@MainActor
protocol SettingsTrashing: AnyObject {
    func exists(_ url: URL) -> Bool
    func moveToTrash(_ url: URL) throws
}

@MainActor
final class SettingsFileTrash: SettingsTrashing {
    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

/// ゴミ箱に入れるもの
struct SettingsUninstallTargets: Equatable {
    /// Nonet.app
    var app: URL
    /// 設定のフォルダ（~/Library/Application Support/Nonet）。試用の記録の写しも入っているが、
    /// 環境設定とキーチェーンにある記録は残るので、試用期間はやり直しにならない
    var settingsFolder: URL
    /// アップデートの一時ファイルなど（~/Library/Caches/<bundle id> と ~/Library/HTTPStorages/<bundle id>）
    var caches: [URL]

    /// 動いているアプリと、その設定の置き場所。Debug ビルドで --config-dir を渡したときは、そのフォルダを設定の置き場所にする
    /// （AppDelegate と同じ。本物の設定をゴミ箱に入れない）
    static func current(bundle: Bundle = .main, arguments: [String] = ProcessInfo.processInfo.arguments) -> SettingsUninstallTargets {
        var settingsFolder = ConfigurationStore.defaultDirectory
        #if DEBUG
        if let directory = ShellLaunchOptions.parse(arguments).configDirectory {
            settingsFolder = directory
        }
        #endif
        let bundleID = bundle.bundleIdentifier ?? LicenseInfo.productID
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL.homeDirectory.appending(path: "Library", directoryHint: .isDirectory)
        return SettingsUninstallTargets(
            app: bundle.bundleURL,
            settingsFolder: settingsFolder,
            caches: [
                library.appending(path: "Caches/\(bundleID)", directoryHint: .isDirectory),
                library.appending(path: "HTTPStorages/\(bundleID)", directoryHint: .isDirectory),
            ]
        )
    }
}

/// アンインストールの結果。ゴミ箱に入れられなかったものと、止められなかったものを伝える
struct SettingsUninstallResult: Equatable {
    /// ゴミ箱に入れられなかったフォルダ（Finder で入れてもらう）
    var leftovers: [URL] = []
    /// ログイン時の起動を止められなかった（システム設定 › 一般 › ログイン項目 で外してもらう）
    var loginItemFailed = false
}

/// 「Nonet をアンインストール…」の確認と、その後の知らせ
enum SettingsUninstallStep: Equatable {
    /// 何をして何を残すかを伝えて確かめる
    case confirm
    /// ゴミ箱に入れた。最後にすること（アクセシビリティの許可を外す）を伝え、閉じたら終了する
    case finished(SettingsUninstallResult)
    /// アプリをゴミ箱に入れられなかった（ほかには何も変えていない）
    case failed
}

enum SettingsUninstallError: Error, Equatable {
    /// アプリではないところから動いている（swift test など）
    case notAnApp
    /// アプリをゴミ箱に入れられなかった。ほかには何も変えていない
    case appNotTrashed
}

@MainActor
struct SettingsUninstaller {
    var trash: any SettingsTrashing
    var targets: SettingsUninstallTargets

    /// 1. ログイン時の起動を止める（アプリをゴミ箱に入れた後では、登録を外せないことがあるため先に）
    /// 2. アプリをゴミ箱に入れる。できなければログイン時の起動を元に戻し、ほかには何もせずにやめる
    /// 3. stopController で待っている設定の保存を書き出してから、設定のフォルダとキャッシュをゴミ箱に入れる
    ///    （後から保存されて、フォルダが作り直されないように）
    /// ライセンスキーと試用の記録が入っている環境設定（~/Library/Preferences）とキーチェーンには触れない
    func run(loginItem: any LoginItemControlling, stopController: () -> Void) throws -> SettingsUninstallResult {
        guard targets.app.pathExtension == "app" else { throw SettingsUninstallError.notAnApp }
        var result = SettingsUninstallResult()
        let wasLoginItemEnabled = loginItem.isEnabled
        // システム設定での許可待ちの登録は、アプリをゴミ箱に入れられてから外す（入れられずにやめるとき、登録し直すと
        // システム設定が開いてしまうので、先に外さない）
        let waitsForApproval = !wasLoginItemEnabled && loginItem.isRegistered
        if wasLoginItemEnabled {
            do {
                try loginItem.setEnabled(false)
            } catch {
                uninstallLog.error("ログイン時の起動を止められませんでした: \(error.localizedDescription, privacy: .public)")
                result.loginItemFailed = true
            }
        }
        do {
            try trash.moveToTrash(targets.app)
        } catch {
            uninstallLog.error("アプリをゴミ箱に入れられませんでした: \(error.localizedDescription, privacy: .public)")
            if wasLoginItemEnabled, !result.loginItemFailed {
                try? loginItem.setEnabled(true)
            }
            throw SettingsUninstallError.appNotTrashed
        }
        if waitsForApproval {
            do {
                try loginItem.setEnabled(false)
            } catch {
                uninstallLog.error("許可待ちのログイン項目を外せませんでした: \(error.localizedDescription, privacy: .public)")
                result.loginItemFailed = true
            }
        }
        stopController()
        for folder in [targets.settingsFolder] + targets.caches where trash.exists(folder) {
            do {
                try trash.moveToTrash(folder)
            } catch {
                uninstallLog.error("ゴミ箱に入れられませんでした: \(error.localizedDescription, privacy: .public)")
                result.leftovers.append(folder)
            }
        }
        uninstallLog.info("アンインストールしました")
        return result
    }
}

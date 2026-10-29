// 担当: ui-shell
import CoreGraphics
import Foundation
import NonetCore
import Observation
@testable import NonetUI
import Testing

/// テストの引数に使う状態（引数はメインアクターの外で作られる）
enum ShellMenuState {
    static func make(
        _ status: ControllerStatus = .running,
        enabled: Bool = true,
        profile: String? = nil,
        global: Bool = false,
        notice: String? = nil,
        entitlement: Entitlement = .trial(daysLeft: 12),
        updates: Bool = false
    ) -> MenuBarState {
        MenuBarState(
            status: status,
            isEnabled: enabled,
            activeProfileName: profile,
            isGlobalProfileActive: global,
            notice: notice,
            entitlement: entitlement,
            canCheckForUpdates: updates
        )
    }
}

@Suite("メニューバー")
@MainActor
struct ShellMenuBarTests {
    @Test("状態の文", arguments: [
        (ShellMenuState.make(profile: "Xcode"), "Xcode のプロファイル"),
        (ShellMenuState.make(profile: "グローバル", global: true), "グローバルのプロファイル"),
        (ShellMenuState.make(), "動作中"),
        (ShellMenuState.make(profile: ""), "動作中"),
        (ShellMenuState.make(.disabled, enabled: false), "Nonet は無効です"),
        (ShellMenuState.make(.needsAccessibility, enabled: false), "Nonet は無効です"),
        (ShellMenuState.make(.needsAccessibility), "アクセシビリティの許可が必要です"),
        (ShellMenuState.make(.noTrackpad), "トラックパッドが見つかりません"),
        (ShellMenuState.make(.secureInputActive), "パスワード入力中は使えません"),
        (ShellMenuState.make(.stopped), "停止しています"),
    ])
    func statusText(state: MenuBarState, expected: String) {
        #expect(MenuBarModel.statusText(for: state) == expected)
    }

    @Test("アイコン: 普段・無効・確認が必要", arguments: [
        (ShellMenuState.make(), MenuBarIconState.normal),
        (ShellMenuState.make(entitlement: .licensed(LicenseInfo(licenseID: "1", licensee: "A", email: nil, issuedAt: Date(timeIntervalSince1970: 0)))), .normal),
        (ShellMenuState.make(.disabled, enabled: false), .disabled),
        (ShellMenuState.make(.running, enabled: false), .disabled),
        (ShellMenuState.make(.stopped), .disabled),
        (ShellMenuState.make(.needsAccessibility), .attention),
        (ShellMenuState.make(.noTrackpad), .attention),
        (ShellMenuState.make(.secureInputActive), .attention),
        (ShellMenuState.make(entitlement: .expired), .attention),
        (ShellMenuState.make(notice: "設定ファイルを保存できません"), .attention),
        // 自分で無効にしているなら、試用切れや知らせより「無効」を見せる
        (ShellMenuState.make(.disabled, enabled: false, notice: "壊れていました", entitlement: .expired), .disabled),
    ])
    func iconState(state: MenuBarState, expected: MenuBarIconState) {
        #expect(MenuBarModel.iconState(for: state) == expected)
    }

    @Test("ライセンスの行")
    func licenseText() {
        #expect(MenuBarModel.licenseText(for: .trial(daysLeft: 3)) == "試用期間: 残り 3 日")
        #expect(MenuBarModel.licenseText(for: .expired) == "試用期間が終了しました")
        let info = LicenseInfo(licenseID: "1", licensee: "山田", email: nil, issuedAt: Date(timeIntervalSince1970: 0))
        #expect(MenuBarModel.licenseText(for: .licensed(info)) == "登録済み")
    }

    @Test("メニューの並び（普段）。アップデートの確認が無ければ出さない")
    func entries() {
        let entries = MenuBarModel.entries(for: ShellMenuState.make(profile: "Xcode"))
        #expect(entries == [
            .status("Xcode のプロファイル", .normal),
            .separator,
            .toggleEnabled(isOn: true),
            .separator,
            .openSettings,
            .editProfiles,
            .showOnboarding,
            .separator,
            .license("試用期間: 残り 12 日"),
            .separator,
            .quit,
        ])
    }

    @Test("アップデートの確認はライセンスの次")
    func updatesEntry() throws {
        let entries = MenuBarModel.entries(for: ShellMenuState.make(updates: true))
        let license = try #require(entries.firstIndex(of: .license("試用期間: 残り 12 日")))
        #expect(entries[license + 1] == .checkForUpdates)
    }

    @Test("許可が無ければ「アクセシビリティを許可…」を出す。無効のときは出さない")
    func accessibilityEntry() {
        #expect(MenuBarModel.entries(for: ShellMenuState.make(.needsAccessibility)).contains(.requestAccessibility))
        #expect(!MenuBarModel.entries(for: ShellMenuState.make(.needsAccessibility, enabled: false)).contains(.requestAccessibility))
        #expect(!MenuBarModel.entries(for: ShellMenuState.make()).contains(.requestAccessibility))
    }

    @Test("知らせがあれば状態の下に出し、消す項目を付ける")
    func noticeEntries() {
        let entries = MenuBarModel.entries(for: ShellMenuState.make(.running, notice: "設定ファイルが壊れていたので退避しました"))
        #expect(Array(entries.prefix(3)) == [
            .status("動作中", .attention),
            .notice("設定ファイルが壊れていたので退避しました"),
            .dismissNotice,
        ])
        #expect(!MenuBarModel.entries(for: ShellMenuState.make(notice: "")).contains(.dismissNotice))
    }

    @Test("無効のときはチェックを外す")
    func toggleOff() {
        #expect(MenuBarModel.entries(for: ShellMenuState.make(.disabled, enabled: false)).contains(.toggleEnabled(isOn: false)))
    }

    @Test("項目の文言は利用ガイドと同じ")
    func titles() {
        #expect(MenuBarEntry.toggleEnabled(isOn: true).title == "Nonet を有効にする")
        #expect(MenuBarEntry.openSettings.title == "設定…")
        #expect(MenuBarEntry.editProfiles.title == "プロファイルを編集…")
        #expect(MenuBarEntry.showOnboarding.title == "初回の案内をもう一度")
        #expect(MenuBarEntry.checkForUpdates.title == "アップデートを確認")
        #expect(MenuBarEntry.quit.title == "終了")
    }

    @Test("NonetController と LicenseManager から状態を集める")
    func stateFromController() {
        let harness = ShellControllerHarness(accessibilityGranted: false)
        harness.controller.start()
        let state = MenuBarState(controller: harness.controller, license: harness.license, canCheckForUpdates: true)
        #expect(state.status == .needsAccessibility)
        #expect(state.isEnabled)
        #expect(state.entitlement == .trial(daysLeft: 14))
        #expect(state.canCheckForUpdates)
        #expect(MenuBarModel.iconState(for: state) == .attention)

        harness.controller.update { $0.settings.isEnabled = false }
        let disabled = MenuBarState(controller: harness.controller, license: harness.license, canCheckForUpdates: false)
        #expect(!disabled.isEnabled)
        #expect(MenuBarModel.iconState(for: disabled) == .disabled)
    }

    @Test("見張り: 最初の値をすぐに知らせ、変わったら知らせる。cancel で止まる")
    func observer() async {
        let harness = ShellControllerHarness(accessibilityGranted: true)
        var seen: [Bool] = []
        let observer = ShellObserver({ harness.controller.configuration.settings.isEnabled }, onChange: { seen.append($0) })
        #expect(seen == [true])
        harness.controller.update { $0.settings.isEnabled = false }
        await Self.drainMainQueue()
        #expect(seen == [true, false])
        // 同じ値なら知らせない
        harness.controller.update { $0.settings.hudDelay = 0.5 }
        await Self.drainMainQueue()
        #expect(seen == [true, false])
        observer.cancel()
        harness.controller.update { $0.settings.isEnabled = true }
        await Self.drainMainQueue()
        #expect(seen == [true, false])
    }

    @Test("アイコンの形: 9マスが同じ大きさで重ならず、キャンバスに収まる")
    func iconGeometry() {
        let canvas = CGRect(origin: .zero, size: MenuBarIconGeometry.canvas)
        let cells = MenuBarIconGeometry.cellRects()
        #expect(cells.count == 9)
        for (index, cell) in cells.enumerated() {
            #expect(canvas.contains(cell))
            #expect(cell.width == MenuBarIconGeometry.cellSize && cell.height == MenuBarIconGeometry.cellSize)
            for other in cells[(index + 1)...] {
                #expect(!cell.intersects(other))
            }
        }
        // 左上から右へ、上の行から（y は下向き）
        #expect(cells[0].minX < cells[1].minX && cells[1].minX < cells[2].minX)
        #expect(cells[0].minY < cells[3].minY && cells[3].minY < cells[6].minY)
        // 中央にそろう
        let grid = MenuBarIconGeometry.gridBounds
        #expect(abs(grid.midX - canvas.midX) < 0.001)
        #expect(abs(grid.midY - canvas.midY) < 0.001)
        #expect(cells[MenuBarIconGeometry.centerIndex].midX == grid.midX)
    }

    @Test("アイコンの形: 中央の塗りと注意の印")
    func iconVariants() {
        #expect(MenuBarIconGeometry.filledCells(for: .normal) == [4])
        #expect(MenuBarIconGeometry.filledCells(for: .attention) == [4])
        #expect(MenuBarIconGeometry.filledCells(for: .disabled).isEmpty)
        #expect(MenuBarIconGeometry.showsBadge(for: .attention))
        #expect(!MenuBarIconGeometry.showsBadge(for: .normal))
        #expect(!MenuBarIconGeometry.showsBadge(for: .disabled))

        // 印は右上のマスに重なり、キャンバスからはみ出さず、ほかのマスには触れない
        let center = MenuBarIconGeometry.badgeCenter
        let radius = MenuBarIconGeometry.badgeRadius
        let canvas = CGRect(origin: .zero, size: MenuBarIconGeometry.canvas)
        #expect(canvas.contains(CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)))
        let cells = MenuBarIconGeometry.cellRects()
        #expect(cells[2].contains(center))
        for index in [0, 1, 3, 4, 5, 6, 7, 8] {
            #expect(Self.distance(from: center, to: cells[index]) >= MenuBarIconGeometry.badgeCutoutRadius - 0.001)
        }
        #expect(MenuBarIconGeometry.badgeCutoutRadius > radius)
    }

    @Test("アイコンの画像はテンプレートで、状態ごとに使い回す")
    func iconImages() {
        for state in MenuBarIconState.allCases {
            let image = MenuBarIconRenderer.image(for: state)
            #expect(image.isTemplate)
            #expect(image.size == MenuBarIconGeometry.canvas)
            #expect(MenuBarIconRenderer.image(for: state) === image)
        }
    }

    @Test("トリガーキーの呼び方と練習の案内")
    func triggerText() {
        #expect(ShellText.triggerName(.rightCommand) == "右⌘")
        #expect(ShellText.triggerName(.rightOption) == "右⌥")
        #expect(ShellText.triggerName(.rightShift) == "右⇧")
        #expect(ShellText.triggerName(.function) == "fn")
        #expect(ShellText.practiceInstruction(.rightCommand) == "右⌘を押しながら、トラックパッドの右上をタップ")
    }

    static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// ShellObserver はメインキューで読み直すので、積まれた仕事を流す
    static func drainMainQueue() async {
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
}

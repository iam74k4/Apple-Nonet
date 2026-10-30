// 契約（変更は統合担当だけ）
import NonetCore

extension NonetServices {
    /// この Mac で動く本物のサービス一式
    @MainActor
    public static func live() -> NonetServices {
        NonetServices(
            touchSource: MultitouchTouchSource(),
            keyboard: EventTapKeyboardMonitor(),
            haptics: TrackpadHapticPlayer(),
            performer: SystemActionPerformer(),
            frontmostApp: WorkspaceFrontmostAppObserver(),
            menus: AccessibilityMenuReader(),
            permissions: SystemPermissions(),
            installedApps: WorkspaceInstalledApps(),
            shortcuts: ShortcutsCLI(),
            ai: OnDeviceAIAvailability(),
            loginItem: SMAppServiceLoginItem(),
            scheduler: MainRunLoopScheduler(),
            isJISKeyboard: KeyboardLayout.isJIS,
            presetEnvironment: SystemPresetEnvironment()
        )
    }
}

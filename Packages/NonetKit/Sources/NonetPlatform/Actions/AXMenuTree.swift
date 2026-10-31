// 担当: platform-actions
import ApplicationServices
import Foundation
import NonetCore

/// AXUIElement を読む小さな道具。値の型はすべて確かめてから取り出す
enum AXRead {
    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (error, value)
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        let (error, value) = copy(element, attribute)
        return error == .success ? self.element(value) : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        let (error, value) = copy(element, attribute)
        return error == .success ? value as? String : nil
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        let (error, value) = copy(element, kAXChildrenAttribute)
        guard error == .success, let array = value as? [AnyObject] else { return [] }
        return array.compactMap { self.element($0) }
    }

    /// CopyMultipleAttributeValues の結果で、読めなかった属性は AXValue（kAXValueAXErrorType）になる
    static func isErrorValue(_ value: AnyObject) -> Bool {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return false }
        return AXValueGetType(unsafeDowncast(value, to: AXValue.self)) == .axError
    }

    static func application(pid: pid_t, timeout: Float) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        return application
    }
}

/// アクセシビリティ API の呼び出しの失敗
struct AXCallError: Error, Equatable {
    var code: AXError

    func nonetError(appName: String) -> NonetError {
        switch code {
        case .apiDisabled:
            .permissionDenied(ActionText.accessibility)
        case .invalidUIElement:
            .actionFailed(String(localized: "\(appName) が起動していません", bundle: .nonetActions))
        case .cannotComplete:
            .actionFailed(String(localized: "\(appName) が応答しません", bundle: .nonetActions))
        default:
            .actionFailed(String(localized: "\(appName) のメニューを読めませんでした", bundle: .nonetActions))
        }
    }
}

/// アクセシビリティ API で読むメニューバー。応答しないアプリで止まり続けないよう、
/// 1回の呼び出しの待ち時間と、全体の時間の上限を持つ
struct AXMenuTree: MenuTree {
    let application: AXUIElement
    let timeout: Float
    let deadline: Date

    init(pid: pid_t, timeout: Float = 1, budget: TimeInterval = 5) {
        application = AXRead.application(pid: pid, timeout: timeout)
        self.timeout = timeout
        deadline = Date().addingTimeInterval(budget)
    }

    private static let attributeNames = [
        kAXTitleAttribute,
        kAXEnabledAttribute,
        kAXMenuItemCmdCharAttribute,
        kAXMenuItemCmdModifiersAttribute,
        kAXMenuItemCmdVirtualKeyAttribute,
        kAXMenuItemCmdGlyphAttribute,
    ] as CFArray

    func menuBarItems() throws -> [AXUIElement] {
        let (error, value) = AXRead.copy(application, kAXMenuBarAttribute)
        guard error == .success else { throw AXCallError(code: error) }
        guard let menuBar = AXRead.element(value) else { throw AXCallError(code: .noValue) }
        AXUIElementSetMessagingTimeout(menuBar, timeout)
        return AXRead.children(menuBar)
    }

    func attributes(of node: AXUIElement) -> MenuEntryAttributes {
        AXUIElementSetMessagingTimeout(node, timeout)
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(node, Self.attributeNames, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
        guard error == .success, let array = values as? [AnyObject], array.count == 6 else {
            return MenuEntryAttributes(title: AXRead.string(node, kAXTitleAttribute))
        }
        func value(_ index: Int) -> AnyObject? {
            AXRead.isErrorValue(array[index]) ? nil : array[index]
        }
        return MenuEntryAttributes(
            title: value(0) as? String,
            isEnabled: (value(1) as? Bool) ?? true,
            cmdChar: value(2) as? String,
            cmdModifiers: (value(3) as? NSNumber)?.intValue,
            cmdVirtualKey: (value(4) as? NSNumber)?.intValue,
            cmdGlyph: (value(5) as? NSNumber)?.intValue
        )
    }

    /// 項目の子は AXMenu が1つで、その子が項目
    func submenuItems(of node: AXUIElement) -> [AXUIElement] {
        guard Date() < deadline else { return [] }
        guard let menu = AXRead.children(node).first else { return [] }
        AXUIElementSetMessagingTimeout(menu, timeout)
        return AXRead.children(menu)
    }
}

/// メニュー項目をパスでたどって押す。アクセシビリティ API はアプリが応答するまで待つので、メインスレッドでは呼ばない。
/// タイトルが状態で変わった項目は、対になるタイトルか同じショートカットで探す（MenuPathResolver）
enum MenuItemPresser {
    /// アプリのメニューバーから読んだ、その項目のショートカット（MenuShortcutLookup）。読めなければ nil
    static func shortcut(path: [String], pid: pid_t) -> KeySequence? {
        MenuShortcutLookup.shortcut(at: path, in: AXMenuTree(pid: pid))
    }

    static func press(path: [String], keyEquivalent: KeySequence? = nil, pid: pid_t, appName: String) throws {
        guard !path.isEmpty else {
            throw NonetError.actionFailed(String(localized: "メニュー項目が設定されていません", bundle: .nonetActions))
        }
        let tree = AXMenuTree(pid: pid)
        let node: AXUIElement?
        do {
            node = try MenuPathResolver.resolve(path, keyEquivalent: keyEquivalent, in: tree)
        } catch let error as AXCallError {
            throw error.nonetError(appName: appName)
        }
        let display = MenuTitleMatcher.displayPath(path)
        guard let node else { throw NonetError.menuItemNotFound(display) }
        guard tree.attributes(of: node).isEnabled else {
            throw NonetError.actionFailed(String(localized: "メニュー項目「\(display)」は今は使えません", bundle: .nonetActions))
        }
        let error = AXUIElementPerformAction(node, kAXPressAction as CFString)
        switch error {
        case .success:
            return
        case .cannotComplete:
            // 項目がダイアログを開くと、閉じるまで応答が返らない。押せてはいる
            ActionLog.logger.notice("メニュー項目を押した後、応答がありませんでした")
        default:
            throw AXCallError(code: error).nonetError(appName: appName)
        }
    }
}

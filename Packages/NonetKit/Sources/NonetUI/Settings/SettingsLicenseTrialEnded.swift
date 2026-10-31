// 担当: ui-settings（クラス名・init・start・showIfDue は契約。App が使う）
// 試用期間が終わったときに出す小さなウィンドウ。起動したときと、使っている間に試用期間が終わったときに、1日に1回まで出す。
// HUD はクリックできず、メニューバーの印だけでは気づかれないので、何をすればよいか（購入・登録）をここで伝える
import AppKit
import NonetCore
import SwiftUI

/// 前に出した日時。defaults が nil ならメモリだけに置く（Debug の --config-dir では本物の UserDefaults に書かない）
@MainActor
final class TrialEndedPromptRecord {
    static let key = "com.iam74k4.Nonet.license.trialEndedPromptShown"

    private let defaults: UserDefaults?
    private var memory: Date?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    var lastShown: Date? {
        get {
            guard let defaults else { return memory }
            return defaults.object(forKey: Self.key) as? Date
        }
        set {
            guard let defaults else {
                memory = newValue
                return
            }
            defaults.set(newValue, forKey: Self.key)
        }
    }

    /// 今日はまだ出していないか（同じ日付なら出さない。時計を戻して前の日時になっていたら出す）
    static func isDue(now: Date, lastShown: Date?, calendar: Calendar) -> Bool {
        guard let lastShown else { return true }
        return !calendar.isDate(lastShown, inSameDayAs: now) || lastShown > now.addingTimeInterval(60)
    }
}

@MainActor
public final class TrialEndedWindowController {
    // テストで差し替える
    var now: () -> Date = { Date() }
    var calendar = Calendar.current
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// ウィンドウを出す。ほかのアプリで打っている最中に出ることがあるので、Nonet を前面にしない
    var present: (NSWindow) -> Void = { window in
        window.center()
        window.orderFrontRegardless()
    }

    private let license: LicenseManager
    private let purchaseURL: URL?
    private let onRegister: () -> Void
    private let record: TrialEndedPromptRecord
    private var observer: ShellObserver<Entitlement>?
    private let windowDelegate = TrialEndedWindowDelegate()
    private(set) var window: NSWindow?

    /// purchaseURL: 「購入する」で開く（nil ならボタンを出さない）。
    /// defaults: 出した日を覚える場所（nil ならメモリだけ）。onRegister: 「ライセンスキーを登録…」（設定のライセンスのタブを開く）
    public init(license: LicenseManager, purchaseURL: URL?, defaults: UserDefaults?, onRegister: @escaping () -> Void) {
        self.license = license
        self.purchaseURL = purchaseURL
        self.onRegister = onRegister
        record = TrialEndedPromptRecord(defaults: defaults)
    }

    /// 試用期間の状態を見張り始める。もう終わっていればすぐに（今日まだ出していなければ）出す
    public func start() {
        observer = ShellObserver({ [weak self] in
            self?.license.entitlement ?? .expired
        }, onChange: { [weak self] entitlement in
            self?.entitlementDidChange(entitlement)
        })
    }

    /// 試用期間が終わっていて、今日まだ出していなければ出す（9マスを開こうとして断られたときなどにも呼べる）
    public func showIfDue() {
        guard license.entitlement == .expired, window == nil else { return }
        let current = now()
        guard TrialEndedPromptRecord.isDue(now: current, lastShown: record.lastShown, calendar: calendar) else { return }
        record.lastShown = current
        let window = makeWindow()
        self.window = window
        present(window)
    }

    func entitlementDidChange(_ entitlement: Entitlement) {
        switch entitlement {
        case .expired:
            showIfDue()
        case .licensed:
            // ほかの所（購入のメールのリンクなど）で登録したら、もう要らない
            close()
        case .trial:
            break
        }
    }

    func buy() {
        let url = purchaseURL
        close()
        if let url {
            openURL(url)
        }
    }

    func register() {
        close()
        onRegister()
    }

    func close() {
        guard let window else { return }
        self.window = nil
        window.delegate = nil
        window.close()
    }

    private func makeWindow() -> NSWindow {
        // 前面にならないパネル。ほかのアプリで打っている文字を奪わず、ボタンは最初のクリックで押せる
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: TrialEndedView.width, height: 140)),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = String(localized: "Nonet の試用期間が終了しました", bundle: .module)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // しまう・広げるは使わない（閉じるは「あとで」と同じ）
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        let hosting = NSHostingView(rootView: TrialEndedView(
            showsPurchase: purchaseURL != nil,
            onBuy: { [weak self] in self?.buy() },
            onRegister: { [weak self] in self?.register() },
            onLater: { [weak self] in self?.close() }
        ))
        panel.contentView = hosting
        // 文の長さ（日本語・英語）に合わせた高さにする
        panel.setContentSize(NSSize(width: TrialEndedView.width, height: hosting.fittingSize.height))
        windowDelegate.onClose = { [weak self] in
            self?.window = nil
            ShellActivation.handBackAfterClosingWindow()
        }
        panel.delegate = windowDelegate
        return panel
    }
}

private final class TrialEndedWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (@MainActor () -> Void)?

    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { onClose?() }
    }
}

struct TrialEndedView: View {
    static let width: CGFloat = 500

    let showsPurchase: Bool
    let onBuy: () -> Void
    let onRegister: () -> Void
    let onLater: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Nonet の試用期間が終了しました", bundle: .module)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("設定はそのまま残っています。ライセンスキーを登録すると、すぐに元どおり使えます。", bundle: .module)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button(action: onLater) {
                        Text("あとで", bundle: .module)
                    }
                    .keyboardShortcut(.cancelAction)
                    Button(action: onRegister) {
                        Text("ライセンスキーを登録…", bundle: .module)
                    }
                    .keyboardShortcut(showsPurchase ? nil : .defaultAction)
                    if showsPurchase {
                        Button(action: onBuy) {
                            Text("購入する", bundle: .module)
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 20)
        .frame(width: Self.width, alignment: .topLeading)
    }
}

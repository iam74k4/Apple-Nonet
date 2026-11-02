// 契約（変更は統合担当だけ）
import Foundation

public struct HUDCell: Equatable, Sendable {
    public var title: String
    public var icon: CellIcon
    /// "⌘B" など。出さないなら nil
    public var detail: String?
    /// 少し長く止めてから実行するマス（Cell.requiresHold）。小さな印を付ける
    public var requiresHold: Bool

    public init(title: String, icon: CellIcon, detail: String? = nil, requiresHold: Bool = false) {
        self.title = title
        self.icon = icon
        self.detail = detail
        self.requiresHold = requiresHold
    }
}

/// HUD の上部の帯の見た目
public enum HUDBannerStyle: Equatable, Sendable {
    /// 注意（試用期間の終了など）
    case warning
    /// 知らせ（試用期間の残り日数など）。注意の印を付けない
    case info
}

/// 少し長く止めてから実行するマスに、指を止めている間の進み具合（SessionHold）
public struct HUDHold: Equatable, Sendable {
    /// 止めているマス（0〜8）
    public var cellIndex: Int
    /// 止め始めた時刻（Scheduler.now の秒）。HUD は、これが変わったら進み具合を最初から満たし直す
    public var since: TimeInterval
    /// 止める必要のある秒数（SessionConfiguration.holdDwell）。HUD はこの間に進み具合を満たしていく
    public var duration: TimeInterval
    /// 止め終えた。いま指を離すと実行する
    public var isReady: Bool

    public init(cellIndex: Int, since: TimeInterval = 0, duration: TimeInterval, isReady: Bool) {
        self.cellIndex = cellIndex
        self.since = since
        self.duration = duration
        self.isReady = isReady
    }
}

/// 左右の外枠に指を止めている間の、ページを切り替えるまでの進み具合（SessionEdgePaging）
public struct HUDEdgePaging: Equatable, Sendable {
    /// 指を止めている側。左は前のページ、右は次のページ
    public var edge: PageEdge
    /// 止め始めた時刻（Scheduler.now の秒）。HUD は、これが変わったら進み具合を最初から満たし直す
    public var since: TimeInterval
    /// 切り替えるまでの秒数。HUD はこの間に進み具合を満たしていく
    public var duration: TimeInterval

    public init(edge: PageEdge, since: TimeInterval = 0, duration: TimeInterval) {
        self.edge = edge
        self.since = since
        self.duration = duration
    }
}

/// HUD に出すもの
public struct HUDModel: Equatable, Sendable {
    /// プロファイル名
    public var title: String
    public var pageIndex: Int
    public var pageCount: Int
    /// 常に9個。nil は空きマス
    public var cells: [HUDCell?]
    /// 指の下にあるマス。指が外枠にある・2本以上の指が触れていれば nil
    public var highlightedIndex: Int?
    /// 指が9マスの外側の枠（やめる場所）にある。離すと何も実行しない。HUD はマスを暗くし、枠を強めて「離すとやめる」を出す
    public var isFingerInFrame: Bool
    /// 少し長く止めてから実行するマスに指を止めている間の進み具合。そのマスを光らせていなければ nil
    public var hold: HUDHold?
    /// 指が左右の外枠にあり、そちらにページがあるときの、切り替えるまでの進み具合。HUD は外枠の帯に進み具合を、
    /// 「離すとやめる」の下に「止めると次のページ」を出す
    public var edgePaging: HUDEdgePaging?
    /// 練習中（初回の案内の練習。実行しない）。HUD は題名の横に「練習中」を出す
    public var isPractice: Bool
    /// 案内の文（例: 「マスで指を離すと実行」）。HUD には出さない（使い始めの案内 footnote が言う）。読み上げの既定に使う
    public var hint: String
    /// 上部の注意書き（例: 試用期間の終了）
    public var banner: String?
    public var bannerStyle: HUDBannerStyle
    /// 9マスの下の1〜2行の案内（使い始めの数回だけ。例: 「指を滑らせて選ぶ · マスで離すと実行 · 外枠で離すとやめる」）。出さないなら nil
    public var footnote: String?
    /// アプリのページの後ろにグローバルのページをつなげたとき、グローバルの最初のページの位置。
    /// ページの点をそこで少し離す。つなげていなければ nil
    public var globalPagesStart: Int?
    /// 寸法と文字に掛ける倍率（設定の「HUD の大きさ」。HUDScale.factor）
    public var scale: Double

    public init(
        title: String,
        pageIndex: Int,
        pageCount: Int,
        cells: [HUDCell?],
        highlightedIndex: Int?,
        isFingerInFrame: Bool = false,
        hold: HUDHold? = nil,
        edgePaging: HUDEdgePaging? = nil,
        isPractice: Bool = false,
        hint: String,
        banner: String? = nil,
        bannerStyle: HUDBannerStyle = .warning,
        footnote: String? = nil,
        globalPagesStart: Int? = nil,
        scale: Double = 1
    ) {
        self.title = title
        self.pageIndex = pageIndex
        self.pageCount = pageCount
        self.cells = cells
        self.highlightedIndex = highlightedIndex
        self.isFingerInFrame = isFingerInFrame
        self.hold = hold
        self.edgePaging = edgePaging
        self.isPractice = isPractice
        self.hint = hint
        self.banner = banner
        self.bannerStyle = bannerStyle
        self.footnote = footnote
        self.globalPagesStart = globalPagesStart
        self.scale = scale
    }
}

/// 実行結果を一瞬だけ出す小さな表示
public struct ToastModel: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case info, success, failure
        /// 長く掛かるマスを実行している。時間では消えず、終わったときに置き換えるか消す（HUDPresenting.hideToast）
        case running
    }

    public var title: String
    public var detail: String?
    public var icon: CellIcon?
    public var style: Style
    /// 寸法と文字に掛ける倍率（設定の「HUD の大きさ」。HUDScale.factor）
    public var scale: Double

    public init(title: String, detail: String? = nil, icon: CellIcon? = nil, style: Style = .info, scale: Double = 1) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.style = style
        self.scale = scale
    }
}

/// AI の「結果を表示」などで出す文。利用者が読み、コピーして閉じる
public struct ResultModel: Equatable, Sendable {
    /// マスの名前
    public var title: String
    public var text: String
    public var icon: CellIcon?

    public init(title: String, text: String, icon: CellIcon? = nil) {
        self.title = title
        self.text = text
        self.icon = icon
    }
}

/// 利用者に見せられる失敗。errorDescription はローカライズ済みの文
public enum NonetError: Error, Equatable, LocalizedError, Sendable {
    /// 必要な権限が無い。値は権限の名前
    case permissionDenied(String)
    /// アプリが見つからない。値はアプリ名か bundleID
    case appNotFound(String)
    /// メニュー項目が見つからない。値は「編集 > コピー」のようなパス
    case menuItemNotFound(String)
    /// 実行に失敗した。値は理由
    case actionFailed(String)
    case timedOut
    /// この Mac では使えない。値は理由
    case unavailable(String)
    /// ライセンスが必要
    case licenseRequired

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let name):
            String(localized: "\(name)の許可が必要です", bundle: .module)
        case .appNotFound(let name):
            String(localized: "\(name) が見つかりません", bundle: .module)
        case .menuItemNotFound(let path):
            String(localized: "メニュー項目「\(path)」が見つかりません", bundle: .module)
        case .actionFailed(let reason):
            reason
        case .timedOut:
            String(localized: "時間内に終わりませんでした", bundle: .module)
        case .unavailable(let reason):
            reason
        case .licenseRequired:
            // HUD は押せないので、次にすることのある場所（メニューバーの Nonet）を言う
            String(localized: "試用期間が終了しました。メニューバーの Nonet から購入・登録できます。", bundle: .module)
        }
    }
}

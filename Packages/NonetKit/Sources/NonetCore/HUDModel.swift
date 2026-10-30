// 契約（変更は統合担当だけ）
import Foundation

public struct HUDCell: Equatable, Sendable {
    public var title: String
    public var icon: CellIcon
    /// "⌘B" など。出さないなら nil
    public var detail: String?

    public init(title: String, icon: CellIcon, detail: String? = nil) {
        self.title = title
        self.icon = icon
        self.detail = detail
    }
}

/// HUD の上部の帯の見た目
public enum HUDBannerStyle: Equatable, Sendable {
    /// 注意（試用期間の終了など）
    case warning
    /// 知らせ（試用期間の残り日数など）。注意の印を付けない
    case info
}

/// HUD に出すもの
public struct HUDModel: Equatable, Sendable {
    /// プロファイル名
    public var title: String
    public var pageIndex: Int
    public var pageCount: Int
    /// 常に9個。nil は空きマス
    public var cells: [HUDCell?]
    /// 指の下にあるマス。指が離れていれば nil
    public var highlightedIndex: Int?
    /// 右上の案内（例: 「タップか 右⌘を離して実行」）
    public var hint: String
    /// 上部の注意書き（例: 試用期間の終了）
    public var banner: String?
    public var bannerStyle: HUDBannerStyle
    /// 9マスの下の1〜2行の案内（使い始めの数回だけ。例: 「指を滑らせて選ぶ · …」）。出さないなら nil
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
            String(localized: "試用期間が終了しました。メニューバーの Nonet から購入・登録できます", bundle: .module)
        }
    }
}

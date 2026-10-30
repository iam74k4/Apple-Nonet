// 担当: ui-shell
// 同じ Nonet を2つ動かさない。2つ動くと、どちらもトリガーキーとトラックパッドを見て、1回のタップでマスが2回実行され、
// 試用の時間も2倍に数えられる（ディスクイメージから開いたものと、アプリケーションフォルダのものなど）。
// ここは決め方だけ。プロセスを調べて終わる部分は App/main.swift
import Foundation

/// 動いている Nonet（同じ bundle ID）の1つ
public struct ShellRunningInstance: Equatable, Sendable {
    public var processID: Int32
    public var bundleURL: URL?
    /// もう終わった（一覧に残っているだけ）
    public var isTerminated: Bool

    public init(processID: Int32, bundleURL: URL?, isTerminated: Bool) {
        self.processID = processID
        self.bundleURL = bundleURL
        self.isTerminated = isTerminated
    }
}

public enum ShellInstanceDecision: Equatable, Sendable {
    /// ほかに動いているものが無いので、このまま起動する
    case launch
    /// 終わりかけのもの（アップデートの後の再起動・終了した直後の起動し直し）かもしれないので、少し待って調べ直す
    case wait
    /// 動いている方に設定を開かせて、このプロセスは終わる
    case handOff(ShellRunningInstance)
}

public enum ShellInstanceGuard {
    /// 前のプロセスが終わるのを待つ長さ（秒）
    public static let shutdownGrace: TimeInterval = 3
    /// 待つ間に調べ直す間隔（秒）
    public static let pollInterval: TimeInterval = 0.1

    /// running は同じ bundle ID で動いているもの（自分を含んでよい）。waited は調べ始めてから待った時間。
    /// allowsMultiple なら調べない（DEBUG ビルドで設定の置き場所を分けて、配布版と並べて動かすとき）
    public static func decide(
        running: [ShellRunningInstance],
        ownProcessID: Int32,
        waited: TimeInterval,
        allowsMultiple: Bool
    ) -> ShellInstanceDecision {
        guard !allowsMultiple else { return .launch }
        let others = running.filter { $0.processID != ownProcessID && !$0.isTerminated }
        guard let other = others.first(where: { $0.bundleURL != nil }) ?? others.first else { return .launch }
        return waited < shutdownGrace ? .wait : .handOff(other)
    }
}

// 担当: ui-shell
// 同じ Nonet を2つ動かさない。2つ動くと、どちらもトリガーキーとトラックパッドを見て、1回のタップでマスが2回実行され、
// 試用の時間も2倍に数えられる（ディスクイメージから開いたものと、アプリケーションフォルダのものなど）。
// ここは決め方だけ。プロセスを調べて終わる部分は App/SingleInstance.swift
import Foundation

/// 動いている Nonet（同じ bundle ID）の1つ
public struct ShellRunningInstance: Equatable, Sendable {
    public var processID: Int32
    public var bundleURL: URL?
    /// もう終わった（一覧に残っているだけ）
    public var isTerminated: Bool
    /// 起動し終えた（NSRunningApplication.isFinishedLaunching）。自分はまだ起動の途中
    public var isFinishedLaunching: Bool
    /// 開かれた時刻。分からなければ nil（プロセス番号で比べる）
    public var launchDate: Date?
    /// どこから開かれたか
    public var location: ShellInstallLocation

    public init(
        processID: Int32,
        bundleURL: URL?,
        isTerminated: Bool = false,
        isFinishedLaunching: Bool = true,
        launchDate: Date? = nil,
        location: ShellInstallLocation = .installed
    ) {
        self.processID = processID
        self.bundleURL = bundleURL
        self.isTerminated = isTerminated
        self.isFinishedLaunching = isFinishedLaunching
        self.launchDate = launchDate
        self.location = location
    }
}

public enum ShellInstanceDecision: Equatable, Sendable {
    /// ほかに動いているものが無いので、このまま起動する
    case launch
    /// 終わりかけのもの（アップデートの後の再起動・終了した直後の起動し直し）や、同時に開かれて譲るはずのものがあるので、少し待って調べ直す
    case wait
    /// ディスクイメージなどの一時的な場所で動いている方に終わってもらい、終わったらこちらが起動する（待つ間も調べ直す）
    case replace(ShellRunningInstance)
    /// 動いている方に任せて、このプロセスは終わる。起動し終えていれば、そちらに設定を開かせる
    case handOff(ShellRunningInstance)
}

/// どれを残すかは、どのプロセスから見ても同じ順で決める（同時に開かれても、2つとも終わったり、2つとも残ったりしない）。
/// 1. 本来の場所（アプリケーションフォルダなど）のものを、ディスクイメージなどの一時的な場所のものより残す
/// 2. 起動し終えたものを、起動の途中のものより残す
/// 3. 先に開かれたもの（同じなら、プロセス番号の小さいもの）を残す
public enum ShellInstanceGuard {
    /// 残す方が、終わりかけ（アップデートの後の再起動など）かもしれないので待つ長さ（秒）
    public static let shutdownGrace: TimeInterval = 3
    /// こちらを残すときに、譲るはずのものが終わるのを待つ長さ（秒）。過ぎても終わらなければ、こちらが譲る（2つは動かさない）
    public static let takeOverTimeout: TimeInterval = 10
    /// 待つ間に調べ直す間隔（秒）
    public static let pollInterval: TimeInterval = 0.1

    /// running は同じ bundle ID で動いているもの（自分を含んでよい）。own は自分（起動の途中）。waited は調べ始めてから待った時間。
    /// allowsMultiple なら調べない（DEBUG ビルドで設定の置き場所を分けて、配布版と並べて動かすとき）
    public static func decide(
        running: [ShellRunningInstance],
        own: ShellRunningInstance,
        waited: TimeInterval,
        allowsMultiple: Bool
    ) -> ShellInstanceDecision {
        guard !allowsMultiple else { return .launch }
        let others = running.filter { $0.processID != own.processID && !$0.isTerminated }
        guard !others.isEmpty else { return .launch }
        let keeper = others.reduce(own) { outranks($1, $0) ? $1 : $0 }

        guard keeper.processID == own.processID else {
            // 残す方が終わりかけかもしれないので、少し待ってから任せる。
            // 残す方が起動の途中でも、こちらが終わるのを待っているので、任せて終わる
            return waited < shutdownGrace ? .wait : .handOff(keeper)
        }
        // こちらを残す。起動し終えているもの（一時的な場所のもの）は自分では終わらないので、終わってもらう。
        // 起動の途中のものは、こちらを見て自分で譲るので待つ
        let running = others.first(where: \.isFinishedLaunching)
        guard waited < takeOverTimeout else {
            return .handOff(running ?? others[0])
        }
        return running.map { .replace($0) } ?? .wait
    }

    /// a を b より残すか
    static func outranks(_ a: ShellRunningInstance, _ b: ShellRunningInstance) -> Bool {
        if a.location != b.location {
            return a.location == .installed
        }
        if a.isFinishedLaunching != b.isFinishedLaunching {
            return a.isFinishedLaunching
        }
        if let aDate = a.launchDate, let bDate = b.launchDate, aDate != bDate {
            return aDate < bDate
        }
        return a.processID < b.processID
    }
}

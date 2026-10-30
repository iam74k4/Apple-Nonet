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
    /// 終わり始めている（ShellQuitMarker の印がある）。終わるのを待ってから起動する
    public var isQuitting: Bool
    /// 開かれた時刻。分からなければ nil（プロセス番号で比べる）
    public var launchDate: Date?
    /// どこから開かれたか
    public var location: ShellInstallLocation

    public init(
        processID: Int32,
        bundleURL: URL?,
        isTerminated: Bool = false,
        isFinishedLaunching: Bool = true,
        isQuitting: Bool = false,
        launchDate: Date? = nil,
        location: ShellInstallLocation = .installed
    ) {
        self.processID = processID
        self.bundleURL = bundleURL
        self.isTerminated = isTerminated
        self.isFinishedLaunching = isFinishedLaunching
        self.isQuitting = isQuitting
        self.launchDate = launchDate
        self.location = location
    }
}

public enum ShellInstanceDecision: Equatable, Sendable {
    /// ほかに動いているものが無いので、このまま起動する
    case launch
    /// 終わりかけのもの（終了した直後の起動し直し）や、同時に開かれて譲るはずのものがあるので、少し待って調べ直す
    case wait
    /// ディスクイメージなどの一時的な場所で動いている方に終わってもらい、終わったらこちらが起動する（待つ間も調べ直す）
    case replace(ShellRunningInstance)
    /// 動いている方に任せて、このプロセスは終わる。起動し終えていれば、そちらに設定を開かせる
    case handOff(ShellRunningInstance)
}

/// どれを残すかは、どのプロセスから見ても同じ順で決める（同時に開かれても、2つとも終わったり、2つとも残ったりしない）。
/// 終わり始めているもの（ShellQuitMarker）は残さず、終わるのを待つ。
/// 1. 本来の場所（アプリケーションフォルダなど）のものを、ディスクイメージなどの一時的な場所のものより残す
/// 2. 起動し終えたものを、起動の途中のものより残す
/// 3. 先に開かれたもの（同じなら、プロセス番号の小さいもの）を残す
public enum ShellInstanceGuard {
    /// 残す方が起動の途中（同時に開かれた）なら、任せる前に待つ長さ（秒）。起動し終えたものには待たずに任せる
    public static let shutdownGrace: TimeInterval = 3
    /// こちらを残すときに、譲るはずのもの・終わりかけのものが終わるのを待つ長さ（秒）。
    /// 譲るはずのものが過ぎても終わらなければ、こちらが譲る（2つは動かさない）
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
        // 終わりかけのもの（終了した直後に開き直した）は残す候補にしない。終わるのを待ってから起動する
        // （2つが同時にトリガーキーを見ないように）。終わりきらなくても、もう入力は見ていないので、待ちすぎたら起動する
        let staying = others.filter { !$0.isQuitting }
        guard !staying.isEmpty else {
            return waited < takeOverTimeout ? .wait : .launch
        }
        let keeper = staying.reduce(own) { outranks($1, $0) ? $1 : $0 }

        guard keeper.processID == own.processID else {
            // 起動し終えて動いているなら、待たずに任せる（もう一度開いたらすぐに設定が開くように）。
            // 起動の途中のもの（同時に開かれた）は、こちらが終わるのを待っているので、少し待ってから任せて終わる
            if keeper.isFinishedLaunching {
                return .handOff(keeper)
            }
            return waited < shutdownGrace ? .wait : .handOff(keeper)
        }
        // こちらを残す。起動し終えているもの（一時的な場所のもの）は自分では終わらないので、終わってもらう。
        // 起動の途中のものは、こちらを見て自分で譲るので待つ
        let running = staying.first(where: \.isFinishedLaunching)
        guard waited < takeOverTimeout else {
            return .handOff(running ?? staying[0])
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

/// 終わり始めた印。applicationWillTerminate で書き、あとから開かれた Nonet が「終わるのを待つか、すぐに任せるか」を決めるのに読む。
/// 一時フォルダ（利用者ごと）に、プロセス番号ごとのファイルを置く
public enum ShellQuitMarker {
    static let prefix = "Nonet-quitting-"

    public static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory
    }

    static func url(processID: Int32, in directory: URL) -> URL {
        directory.appendingPathComponent("\(prefix)\(processID)", isDirectory: false)
    }

    /// 自分が終わり始めたことを書く
    public static func mark(processID: Int32, in directory: URL = defaultDirectory) {
        FileManager.default.createFile(atPath: url(processID: processID, in: directory).path, contents: Data())
    }

    /// processID の Nonet が終わり始めているか。launchDate（そのプロセスを開いた時刻）より前の印は、
    /// 同じ番号の前のプロセスが残したものなので数えない
    public static func isQuitting(processID: Int32, launchDate: Date?, in directory: URL = defaultDirectory) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url(processID: processID, in: directory).path) else {
            return false
        }
        guard let launchDate, let written = attributes[.modificationDate] as? Date else { return true }
        // ファイルの時刻は秒より細かく残らないことがあるので、1秒だけ見逃す
        return written >= launchDate.addingTimeInterval(-1)
    }

    /// 起動したときに、前のプロセスが残した印をすべて消す（起動できたなら、ほかの Nonet はもう動いていない）
    public static func removeAll(in directory: URL = defaultDirectory) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(prefix) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name, isDirectory: false))
        }
    }
}

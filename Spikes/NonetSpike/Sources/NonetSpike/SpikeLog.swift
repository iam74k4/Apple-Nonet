import Foundation

/// ~/Library/Logs/NonetSpike/spike.log に追記する。検証結果はこのファイルから読む
final class SpikeLog {
    static let shared = SpikeLog()

    let fileURL: URL
    /// メインスレッドで呼ばれる
    var onLine: ((String) -> Void)?

    private let handle: FileHandle?
    private let queue = DispatchQueue(label: "NonetSpike.log")
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/NonetSpike", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("spike.log")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        handle?.seekToEndOfFile()
    }

    func write(_ category: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(category)] \(message)"
        queue.async { [handle] in
            handle?.write(Data((line + "\n").utf8))
        }
        if Thread.isMainThread {
            onLine?(line)
        } else {
            DispatchQueue.main.async { [weak self] in self?.onLine?(line) }
        }
    }
}

func log(_ category: String, _ message: String) {
    SpikeLog.shared.write(category, message)
}

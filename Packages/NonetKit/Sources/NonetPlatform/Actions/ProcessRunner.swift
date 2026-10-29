// 担当: platform-actions
import Foundation

/// 末尾の limit バイトだけを残すバッファ（標準エラーは最後の数行が要る）
struct TailBuffer {
    let limit: Int
    private var storage = Data()
    private var droppedBytes = false

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    var isTruncated: Bool { droppedBytes || storage.count > limit }

    mutating func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        storage.append(chunk)
        // 毎回切ると遅いので、上限の2倍を超えたときだけ切る
        if storage.count > limit * 2 {
            storage = Data(storage.suffix(limit))
            droppedBytes = true
        }
    }

    var data: Data {
        storage.count > limit ? Data(storage.suffix(limit)) : storage
    }

    /// UTF-8 として読む。途中で切った場合は、先頭の途切れた文字のかけらを捨てる
    var text: String {
        var bytes = data[...]
        if isTruncated {
            bytes = bytes.drop { $0 & 0b1100_0000 == 0b1000_0000 }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

struct ProcessRequest: Sendable {
    var executable: URL
    var arguments: [String]
    /// nil なら Nonet の環境変数をそのまま渡す
    var environment: [String: String]?
    var currentDirectory: URL?
    var timeout: TimeInterval
    /// 標準出力・標準エラーそれぞれで残すバイト数（末尾を残す）
    var outputLimit = 64 * 1024
    /// 制限時間を過ぎて SIGTERM を送ってから SIGKILL までの猶予
    var killGracePeriod: TimeInterval = 2
    /// 終了後、出力を読み切るのを待つ時間。裏で動き続ける孫プロセスがパイプを握っていても先へ進む
    var drainGracePeriod: TimeInterval = 0.2
}

struct ProcessOutput: Sendable, Equatable {
    var status: Int32
    /// シグナルで終わった（status はシグナルの番号）
    var wasSignaled: Bool
    var timedOut: Bool
    var stdout: String
    var stderr: String

    var succeeded: Bool { !timedOut && !wasSignaled && status == 0 }
}

/// 子プロセスを動かし、終わるか制限時間を過ぎるまで待つ（メインスレッドは止めない）。
/// 子は自分のプロセスグループで動くので、打ち切るときはグループごと止める
enum ProcessRunner {
    static func run(_ request: ProcessRequest) async throws -> ProcessOutput {
        let run = ProcessRun(request: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                run.start(continuation)
            }
        } onCancel: {
            run.stop(timedOut: false)
        }
    }
}

/// 1回の実行の状態。パイプの読み取り・終了・制限時間がそれぞれ別のスレッドから触るので、lock で守る
private final class ProcessRun: @unchecked Sendable {
    private enum Stream {
        case stdout, stderr
    }

    private let request: ProcessRequest
    private let lock = NSLock()
    private var process: Process?
    private var stdout: TailBuffer
    private var stderr: TailBuffer
    private var openStreams = 2
    private var termination: (status: Int32, signaled: Bool)?
    private var pid: pid_t = 0
    private var timedOut = false
    private var cancelled = false
    private var finished = false
    private var continuation: CheckedContinuation<ProcessOutput, Error>?

    init(request: ProcessRequest) {
        self.request = request
        stdout = TailBuffer(limit: request.outputLimit)
        stderr = TailBuffer(limit: request.outputLimit)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func start(_ continuation: CheckedContinuation<ProcessOutput, Error>) {
        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        if let environment = request.environment { process.environment = environment }
        if let directory = request.currentDirectory { process.currentDirectoryURL = directory }
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        install(outPipe, as: .stdout)
        install(errPipe, as: .stderr)
        process.terminationHandler = { [self] process in
            exited(status: process.terminationStatus, signaled: process.terminationReason == .uncaughtSignal)
        }

        let cancelledBeforeLaunch = locked {
            self.continuation = continuation
            self.process = process
            return cancelled
        }
        var launchError: Error? = cancelledBeforeLaunch ? CancellationError() : nil
        if launchError == nil {
            do { try process.run() } catch { launchError = error }
        }
        if let launchError {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            finish(failure: launchError)
            return
        }
        let cancelledDuringLaunch = locked {
            pid = process.processIdentifier
            return cancelled
        }
        if cancelledDuringLaunch {
            stop(timedOut: false)
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + request.timeout) { [weak self] in
            self?.stop(timedOut: true)
        }
    }

    private func install(_ pipe: Pipe, as stream: Stream) {
        // ハンドラがパイプを握り、終わり（EOF）まで読み続ける。
        // 結果を返した後も読み捨てるので、裏に残った孫プロセスが書いても SIGPIPE にならない
        pipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                withExtendedLifetime(pipe) {}
                streamClosed()
            } else {
                received(chunk, on: stream)
            }
        }
    }

    private func received(_ chunk: Data, on stream: Stream) {
        locked {
            guard !finished else { return }
            switch stream {
            case .stdout: stdout.append(chunk)
            case .stderr: stderr.append(chunk)
            }
        }
    }

    private func streamClosed() {
        let ready = locked {
            openStreams -= 1
            return openStreams == 0 && termination != nil
        }
        if ready { finish() }
    }

    private func exited(status: Int32, signaled: Bool) {
        let ready = locked {
            termination = (status, signaled)
            return openStreams == 0
        }
        if ready {
            finish()
        } else {
            DispatchQueue.global().asyncAfter(deadline: .now() + request.drainGracePeriod) { [self] in
                finish()
            }
        }
    }

    /// 制限時間・取り消し。まず SIGTERM、猶予のあと残っていれば SIGKILL
    func stop(timedOut: Bool) {
        let target: pid_t? = locked {
            if timedOut { guard !cancelled else { return nil } } else { cancelled = true }
            guard termination == nil, !finished, pid > 0 else { return nil }
            if timedOut { self.timedOut = true }
            return pid
        }
        guard let target else { return }
        Self.signal(target, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + request.killGracePeriod) { [self] in
            let stillRunning = locked { termination == nil }
            if stillRunning { Self.signal(target, SIGKILL) }
        }
    }

    private static func signal(_ pid: pid_t, _ signal: Int32) {
        // グループごと止める。グループが無ければ本人だけ
        if kill(-pid, signal) != 0 {
            kill(pid, signal)
        }
    }

    private func finish(failure: Error? = nil) {
        let outcome: (CheckedContinuation<ProcessOutput, Error>, Result<ProcessOutput, Error>)? = locked {
            guard !finished, let continuation else { return nil }
            let result: Result<ProcessOutput, Error>
            if let failure {
                result = .failure(failure)
            } else if let termination {
                if cancelled && !timedOut {
                    result = .failure(CancellationError())
                } else {
                    result = .success(ProcessOutput(
                        status: termination.status,
                        wasSignaled: termination.signaled,
                        timedOut: timedOut,
                        stdout: stdout.text,
                        stderr: stderr.text
                    ))
                }
            } else {
                return nil
            }
            finished = true
            self.continuation = nil
            process?.terminationHandler = nil
            process = nil
            return (continuation, result)
        }
        guard let (continuation, result) = outcome else { return }
        continuation.resume(with: result)
    }
}

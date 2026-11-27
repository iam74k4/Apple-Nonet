// 画面の一部を H.264 の MP4 に収録する（販売ページ・ポートフォリオのデモ動画用。macOS 14 以降）。
// screencapture -v は、ここの環境では録画を始められなかったので、ScreenCaptureKit で書く。ポインタは写さない。
// コンパイル: swiftc -O -parse-as-library scripts/record-screen.swift -o build/record-screen（@main があるので -parse-as-library が要る）
// 使い方: build/record-screen <出力の .mp4> <最長の秒> <x> <y> <幅> <高さ> <出力の幅> <出力の高さ> [ビットレート bps（既定 3000000）] [最初に捨てる秒（既定 0）]
//   x・y・幅・高さは、画面の左上を原点にした pt。最初に捨てる秒は、デモのアプリが背景を敷く前の画面を残さないため。
//   最長の秒より前に SIGINT（kill -INT）を送ると、そこで止めて書き終える（呼ぶ側が、写したい場面の終わりに止める）
import AVFoundation
import ScreenCaptureKit

final class FrameWriter: NSObject, SCStreamOutput {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let skip: TimeInterval
    private var firstTime: CMTime?
    private var sessionStarted = false
    private var lastTime = CMTime.zero
    private(set) var frames = 0

    init(url: URL, width: Int, height: Int, bitrate: Int, skip: TimeInterval) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60,
            ],
            // 色: 画面を sRGB で受け取り（下の colorSpaceName）、動画にも「伝達関数は sRGB」と書く。既定のままだと、
            // 暗い色が持ち上がって色みも抜け（墨 #222226 の背景が #2B2B2B に見えた）、同じ背景の静止画と色がそろわない
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: kCVImageBufferTransferFunction_sRGB as String,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        self.skip = skip
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete else { return }
        let time = sampleBuffer.presentationTimeStamp
        if firstTime == nil { firstTime = time }
        guard let firstTime, CMTimeGetSeconds(time - firstTime) >= skip else { return }
        if !sessionStarted {
            writer.startWriting()
            writer.startSession(atSourceTime: time)
            sessionStarted = true
        }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
            lastTime = time
            frames += 1
        }
    }

    /// 最後の画面を、tail 秒だけ長く見せて書き終える（画面が変わらない間はフレームが来ないので、そのままだと最後の画面がすぐ終わる）
    func finish(tail: TimeInterval) async {
        guard sessionStarted else { return }
        input.markAsFinished()
        writer.endSession(atSourceTime: lastTime + CMTime(seconds: tail, preferredTimescale: 600))
        await writer.finishWriting()
    }
}

/// SIGINT か、最長の秒のどちらか早いほうまで待つ
enum StopSignal {
    /// 受け取るまで消えないよう、持っておく（持たないと、待つ前に片付けられて、信号が届かない）
    private static var source: DispatchSourceSignal?

    static func wait(upTo seconds: Double) async {
        // バックグラウンドで始めたシェルのコマンドは SIGINT が無視されている。DispatchSource で受けるには、無視にしておく
        signal(SIGINT, SIG_IGN)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let lock = NSLock()
            var finished = false
            func resume() {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                continuation.resume()
            }
            let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            source.setEventHandler { resume() }
            source.resume()
            Self.source = source
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { resume() }
        }
    }
}

@main
struct RecordScreen {
    static func main() async {
        // ファイルにつないでも1行ずつ出す（呼ぶ側が「収録を始めました」を待って次の操作に進むため）
        setvbuf(stdout, nil, _IOLBF, 0)
        let args = CommandLine.arguments
        guard args.count >= 9, let seconds = Double(args[2]),
              let x = Double(args[3]), let y = Double(args[4]), let width = Double(args[5]), let height = Double(args[6]),
              let outWidth = Int(args[7]), let outHeight = Int(args[8]) else {
            FileHandle.standardError.write(Data("使い方: record-screen <出力の .mp4> <秒> <x> <y> <幅> <高さ> <出力の幅> <出力の高さ> [bps] [最初に捨てる秒]\n".utf8))
            exit(2)
        }
        let bitrate = args.count > 9 ? Int(args[9]) ?? 3_000_000 : 3_000_000
        let skip = args.count > 10 ? Double(args[10]) ?? 0 : 0
        let url = URL(fileURLWithPath: args[1])
        try? FileManager.default.removeItem(at: url)
        do {
            let content = try await SCShareableContent.current
            // 主の画面（メニューバーのある画面）を撮る。Nonet の --demo も、背景をこの画面に敷く
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
                // 画面がスリープ・ロック中は、画面の一覧が空になる（画面の収録の許可が無いときは、ここまで来ずに SCShareableContent が失敗する）
                FileHandle.standardError.write(Data("画面が見つかりません。Mac のロックを解除して、画面を点けてから、もう一度実行してください\n".utf8))
                exit(1)
            }
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: x, y: y, width: width, height: height)
            configuration.width = outWidth
            configuration.height = outHeight
            // 1 秒 60 コマまで受け取る。30 コマだと、右下の図の指の点が速く動く所で1コマに大きく跳び、カクカクして見えた（2026-11-27）
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.colorSpaceName = CGColorSpace.sRGB
            configuration.showsCursor = false
            let output = try FrameWriter(url: url, width: outWidth, height: outHeight, bitrate: bitrate, skip: skip)
            let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: configuration, delegate: nil)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "record-screen"))
            try await stream.startCapture()
            print("record-screen: 収録を始めました（最長 \(seconds) 秒）")
            await StopSignal.wait(upTo: seconds)
            try await stream.stopCapture()
            await output.finish(tail: 1.0)
            print("record-screen: \(output.frames) フレームを \(url.path) に書きました")
        } catch {
            FileHandle.standardError.write(Data("record-screen: \(error)\n".utf8))
            exit(1)
        }
    }
}

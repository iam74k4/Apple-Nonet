// 画面の一部を H.264 の MP4 に収録する（販売ページ・ポートフォリオのデモ動画用。macOS 14 以降）。
// screencapture -v は、ここの環境では録画を始められなかったので、ScreenCaptureKit で書く。ポインタは写さない。
// コンパイル: swiftc -O scripts/record-screen.swift -o build/record-screen
// 使い方: build/record-screen <出力の .mp4> <秒> <x> <y> <幅> <高さ> <出力の幅> <出力の高さ> [ビットレート bps（既定 3000000）] [最初に捨てる秒（既定 0）]
//   x・y・幅・高さは、画面の左上を原点にした pt。最初に捨てる秒は、デモのアプリが背景を敷く前の画面を残さないため
import AVFoundation
import ScreenCaptureKit

final class FrameWriter: NSObject, SCStreamOutput {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let skip: TimeInterval
    private var firstTime: CMTime?
    private var sessionStarted = false
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
            frames += 1
        }
    }

    func finish() async {
        guard sessionStarted else { return }
        input.markAsFinished()
        await writer.finishWriting()
    }
}

@main
struct RecordScreen {
    static func main() async {
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
            guard let display = content.displays.first else {
                // 画面がスリープ・ロック中は、画面の一覧が空になる（画面の収録の許可が無いときは、ここまで来ずに SCShareableContent が失敗する）
                FileHandle.standardError.write(Data("画面が見つかりません。Mac のロックを解除して、画面を点けてから、もう一度実行してください\n".utf8))
                exit(1)
            }
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: x, y: y, width: width, height: height)
            configuration.width = outWidth
            configuration.height = outHeight
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = false
            let output = try FrameWriter(url: url, width: outWidth, height: outHeight, bitrate: bitrate, skip: skip)
            let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: configuration, delegate: nil)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "record-screen"))
            try await stream.startCapture()
            print("record-screen: 収録を始めました（\(seconds) 秒）")
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            try await stream.stopCapture()
            await output.finish()
            print("record-screen: \(output.frames) フレームを \(url.path) に書きました")
        } catch {
            FileHandle.standardError.write(Data("record-screen: \(error)\n".utf8))
            exit(1)
        }
    }
}

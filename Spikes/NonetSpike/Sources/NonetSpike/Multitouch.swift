import CMultitouch
import Foundation

struct TouchPoint {
    let id: Int32
    let state: Int32
    /// 0〜1。y は手前が 0
    let x: Float
    let y: Float
    let size: Float

    /// 3: 接触開始, 4: 接触中
    var isTouching: Bool { state == 3 || state == 4 }
}

struct MultitouchDevice: Identifiable {
    let index: Int32
    let builtIn: Bool
    let familyID: Int32
    let deviceID: UInt64
    /// 単位は 0.01mm
    let surfaceSize: (width: Int32, height: Int32)?

    var id: Int32 { index }

    var summary: String {
        let size = surfaceSize.map { String(format: "%.1f×%.1fmm", Double($0.width) / 100, Double($0.height) / 100) } ?? "サイズ不明"
        return "#\(index) \(builtIn ? "内蔵" : "外付け") family=\(familyID) id=\(deviceID) \(size)"
    }
}

/// 非公開の MultitouchSupport.framework から、トラックパッド上の指の絶対位置を受け取る
enum Multitouch {
    /// MultitouchSupport のスレッドから呼ばれる
    private static var onFrame: ((Int32, [TouchPoint]) -> Void)?

    static func load() -> (devices: [MultitouchDevice], error: String?) {
        var buffer = [CChar](repeating: 0, count: 256)
        guard cmt_load(&buffer, Int32(buffer.count)) else {
            return ([], String(cString: buffer))
        }
        let devices = (0..<cmt_device_count()).map { index -> MultitouchDevice in
            var width: Int32 = 0
            var height: Int32 = 0
            let hasSize = cmt_device_surface_size(index, &width, &height)
            return MultitouchDevice(
                index: index,
                builtIn: cmt_device_is_builtin(index),
                familyID: cmt_device_family_id(index),
                deviceID: cmt_device_id(index),
                surfaceSize: hasSize ? (width, height) : nil
            )
        }
        return (devices, nil)
    }

    static func start(_ handler: @escaping (Int32, [TouchPoint]) -> Void) {
        onFrame = handler
        cmt_start { deviceIndex, touches, count, _ in
            guard let handler = Multitouch.onFrame else { return }
            var points: [TouchPoint] = []
            if let touches, count > 0 {
                points = UnsafeBufferPointer(start: touches, count: Int(count)).map {
                    TouchPoint(
                        id: $0.identifier,
                        state: $0.state,
                        x: $0.normalized.position.x,
                        y: $0.normalized.position.y,
                        size: $0.zTotal
                    )
                }
            }
            handler(deviceIndex, points)
        }
    }

    static func stop() {
        cmt_stop()
        onFrame = nil
    }
}

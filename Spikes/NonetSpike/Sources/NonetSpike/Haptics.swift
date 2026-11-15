import AppKit
import CMultitouch

enum HapticMode: String, CaseIterable, Identifiable {
    case off = "なし"
    case alignment = "NSHaptic: alignment"
    case generic = "NSHaptic: generic"
    case levelChange = "NSHaptic: levelChange"
    case actuator = "MTActuator（非公開 API）"

    var id: Self { self }
}

/// 公開 API（NSHapticFeedbackManager）と非公開 API（MTActuator）の両方で振動させる
final class Haptics {
    private(set) var actuatorOpen = false

    /// 戻り値は IOReturn（0 で成功）
    func openActuator(deviceIndex: Int32) -> Int32 {
        let result = cmt_actuator_open(deviceIndex)
        actuatorOpen = result == 0
        return result
    }

    func close() {
        cmt_actuator_close()
        actuatorOpen = false
    }

    /// 失敗したときだけ理由を返す
    func play(_ mode: HapticMode, actuationID: Int32, unknown2: Float, unknown3: Float) -> String? {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch mode {
        case .off:
            return nil
        case .alignment:
            performer.perform(.alignment, performanceTime: .now)
        case .generic:
            performer.perform(.generic, performanceTime: .now)
        case .levelChange:
            performer.perform(.levelChange, performanceTime: .now)
        case .actuator:
            guard actuatorOpen else { return "アクチュエータを開けていない" }
            let result = cmt_actuator_actuate(actuationID, 0, unknown2, unknown3)
            if result != 0 { return String(format: "MTActuatorActuate 失敗 0x%08x", UInt32(bitPattern: result)) }
        }
        return nil
    }
}

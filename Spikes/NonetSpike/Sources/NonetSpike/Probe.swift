import ApplicationServices
import Carbon
import CMultitouch
import Foundation

enum KeyboardInfo {
    static var layoutName: String {
        switch Int(KBGetLayoutType(Int16(LMGetKbdType()))) {
        case kKeyboardJIS: "JIS"
        case kKeyboardISO: "ISO"
        case kKeyboardANSI: "ANSI"
        default: "不明"
        }
    }

    /// JIS 配列には右⌥が無い
    static var isJIS: Bool { layoutName == "JIS" }
}

/// `NonetSpike --probe`: 画面を出さずに、権限・デバイス・アクチュエータの状態を表示して終わる
enum Probe {
    static func run() {
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("キーボード配列: \(KeyboardInfo.layoutName)")
        print("権限（このプロセスを起動した側の権限）: アクセシビリティ=\(AXIsProcessTrusted()) 入力監視=\(CGPreflightListenEventAccess()) イベント送出=\(CGPreflightPostEventAccess())")
        print("CMTTouch のサイズ: \(MemoryLayout<CMTTouch>.size) バイト")

        let (devices, error) = Multitouch.load()
        if let error {
            print("MultitouchSupport: 読み込み失敗 — \(error)")
            return
        }
        print("MultitouchSupport: 読み込み成功、デバイス \(devices.count) 台")
        for device in devices {
            print("  \(device.summary)")
            let result = cmt_actuator_open(device.index)
            print("    アクチュエータを開く: \(result == 0 ? "成功" : String(format: "失敗 0x%08x", UInt32(bitPattern: result)))")
            cmt_actuator_close()
        }
    }
}

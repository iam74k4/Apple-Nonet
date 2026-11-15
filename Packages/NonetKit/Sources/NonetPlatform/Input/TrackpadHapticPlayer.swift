// 担当: platform-input
// クラス名・public init・protocol への準拠は契約（NonetServices.live() が使う）
import AppKit
import CMultitouch
import NonetCore

/// トラックパッドの触覚。MTActuator（非公開）を優先し、使えなければ NSHapticFeedbackManager
@MainActor
public final class TrackpadHapticPlayer: HapticPlayer {
    private let engine: HapticEngine
    private var wakeObservation: NotificationObservation?

    public init() {
        engine = HapticEngine(
            backend: MultitouchHapticBackend(),
            clock: { ProcessInfo.processInfo.systemUptime },
            lastTouchedDevice: { MultitouchActivity.lastTouchedDeviceID }
        )
        // スリープから戻るとアクチュエータを開き直す必要がある
        wakeObservation = NotificationObservation(center: NSWorkspace.shared.notificationCenter, name: NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.engine.reset()
        }
    }

    public func play(_ event: HapticEvent, strength: HapticStrength) {
        engine.play(event, strength: strength)
    }
}

// MARK: - 調整用の表

/// MTActuatorActuate に渡す値
struct HapticActuation: Equatable, Sendable {
    var actuationID: Int32
    var unknown1: UInt32 = 0
    var unknown2: Float = 0
    var unknown3: Float = 2
}

/// 1回の触覚の中の1打
struct HapticPulse: Equatable, Sendable {
    var actuation: HapticActuation
    /// 1打目からの秒数
    var delay: TimeInterval
}

/// 公開 API で鳴らすときの種類
enum HapticFallbackPattern: Equatable, Sendable {
    case alignment
    case levelChange
    case generic

    var nsPattern: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .alignment: .alignment
        case .levelChange: .levelChange
        case .generic: .generic
        }
    }
}

/// 触覚の割り当て。実機での感触は確かめていないので、調整はこの表だけで済むようにまとめてある。
/// どの強さでも種類を指で見分けられるよう、強さ（境界 < 実行）と打つ回数（ページ・受け付けなかった は2打）で分ける
enum HapticTuning {
    /// MTActuator の actuationID（弱 / 中 / 強）。3〜6 は数字が大きいほど強いという報告に基づく（未確認）
    static let actuationIDs: [HapticEvent: (light: Int32, medium: Int32, strong: Int32)] = [
        .boundary: (light: 3, medium: 4, strong: 5),
        // 2打（secondPulseDelays）。境界と同じ強さでも、打つ回数で分かる。
        // 弱では「受け付けなかった」（3 の2打）と同じにならないよう、1つ強くする
        .pageChange: (light: 4, medium: 4, strong: 5),
        // 上下の帯でアプリとグローバルの層を切り替えた。ページの2打と打つ回数で分け、実行と同じ強めの1打にする
        .layerChange: (light: 5, medium: 6, strong: 6),
        // 少し長く止めるマスを止め終えた（いま離すと実行する）。境界より1つ強い1打で、離してよいことを指に知らせる
        .holdReady: (light: 4, medium: 5, strong: 6),
        .execute: (light: 4, medium: 6, strong: 6),
        // 上の縁から指を滑らせて9マスが開いた。開いたことだけを伝える軽い1打（境界より1つ弱い。
        // すぐ後にマスへ入ると境界の1打が来るので、それより目立たせない）
        .activation: (light: 3, medium: 3, strong: 4),
        // 弱い2打。強さの設定に関係なく同じ（「何も起きなかった」は控えめに）
        .rejected: (light: 3, medium: 3, strong: 3),
    ]

    /// 2打目を打つまでの秒数。無い種類は1打だけ
    static let secondPulseDelays: [HapticEvent: TimeInterval] = [
        .pageChange: 0.05,
        .rejected: 0.04,
    ]

    /// 同じ種類を続けて鳴らす最短の間隔（秒）。境界を素早くまたいでも震えっぱなしにならないように
    static let minimumIntervals: [HapticEvent: TimeInterval] = [
        .boundary: 0.06,
        .pageChange: 0.15,
        .layerChange: 0.15,
        .holdReady: 0.15,
        .execute: 0.08,
        .activation: 0.15,
        .rejected: 0.15,
    ]

    /// 境界の触覚は、ほかの触覚の直後（この秒数以内）なら鳴らさない
    static let boundaryQuietPeriod: TimeInterval = 0.04

    /// アクチュエータを開けなかった・鳴らせなかったデバイスを、もう一度試すまでの秒数
    static let actuatorRetryInterval: TimeInterval = 10

    static func actuation(for event: HapticEvent, strength: HapticStrength) -> HapticActuation? {
        guard let ids = actuationIDs[event] else { return nil }
        switch strength {
        case .off: return nil
        case .light: return HapticActuation(actuationID: ids.light)
        case .medium: return HapticActuation(actuationID: ids.medium)
        case .strong: return HapticActuation(actuationID: ids.strong)
        }
    }

    /// 鳴らす打（1打目は delay 0）。オフなら空
    static func pulses(for event: HapticEvent, strength: HapticStrength) -> [HapticPulse] {
        guard let actuation = actuation(for: event, strength: strength) else { return [] }
        var pulses = [HapticPulse(actuation: actuation, delay: 0)]
        if let delay = secondPulseDelays[event] {
            pulses.append(HapticPulse(actuation: actuation, delay: delay))
        }
        return pulses
    }

    static func fallback(for event: HapticEvent) -> HapticFallbackPattern {
        switch event {
        case .boundary: .alignment
        case .pageChange: .levelChange
        case .layerChange: .levelChange
        case .holdReady: .levelChange
        case .execute: .generic
        case .activation: .levelChange
        case .rejected: .generic
        }
    }
}

/// 触覚を鳴らしすぎないようにする
struct HapticRateLimiter {
    private var lastPlayed: [HapticEvent: TimeInterval] = [:]
    private var lastAny: TimeInterval?

    mutating func shouldPlay(_ event: HapticEvent, at time: TimeInterval) -> Bool {
        if let last = lastPlayed[event], time - last < HapticTuning.minimumIntervals[event, default: 0] {
            return false
        }
        if event == .boundary, let lastAny, time - lastAny < HapticTuning.boundaryQuietPeriod {
            return false
        }
        lastPlayed[event] = time
        lastAny = time
        return true
    }
}

// MARK: - 鳴らす仕組み

/// アクチュエータと公開 API への窓口（テストでは偽物に差し替える）
@MainActor
protocol HapticBackend: AnyObject {
    func openActuator(deviceID: UInt64) -> Bool
    func actuate(_ actuation: HapticActuation) -> Bool
    func closeActuator()
    /// 指が触れたデバイスが分からないときに使うデバイス（内蔵を優先）
    func defaultDeviceID() -> UInt64?
    func performFallback(_ pattern: HapticFallbackPattern)
}

/// アクチュエータを必要になってから開き、失敗したら公開 API で鳴らす
@MainActor
final class HapticEngine {
    private let backend: any HapticBackend
    private let clock: () -> TimeInterval
    private let lastTouchedDevice: () -> UInt64?
    /// 2打目を打つ時刻に呼んでもらう（テストでは手で進める）
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private var limiter = HapticRateLimiter()
    private(set) var openDeviceID: UInt64?
    private var failedAt: [UInt64: TimeInterval] = [:]
    private var defaultDevice: UInt64??

    init(
        backend: any HapticBackend,
        clock: @escaping () -> TimeInterval,
        lastTouchedDevice: @escaping () -> UInt64?,
        schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = HapticEngine.scheduleOnMain
    ) {
        self.backend = backend
        self.clock = clock
        self.lastTouchedDevice = lastTouchedDevice
        self.schedule = schedule
    }

    nonisolated static func scheduleOnMain(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { action() }
        }
    }

    func play(_ event: HapticEvent, strength: HapticStrength) {
        let pulses = HapticTuning.pulses(for: event, strength: strength)
        guard let first = pulses.first else { return }
        let now = clock()
        guard limiter.shouldPlay(event, at: now) else { return }
        pulse(first.actuation, event: event, now: now)
        // 2打目は間を空けて打つ（ページの切り替え・受け付けなかった）
        for next in pulses.dropFirst() {
            schedule(next.delay) { [weak self] in
                guard let self else { return }
                self.pulse(next.actuation, event: event, now: self.clock())
            }
        }
    }

    private func pulse(_ actuation: HapticActuation, event: HapticEvent, now: TimeInterval) {
        if !actuate(actuation, now: now) {
            backend.performFallback(HapticTuning.fallback(for: event))
        }
    }

    /// スリープからの復帰などで、開いているアクチュエータが使えなくなったとき
    func reset() {
        backend.closeActuator()
        openDeviceID = nil
        failedAt = [:]
        defaultDevice = nil
    }

    private func actuate(_ actuation: HapticActuation, now: TimeInterval) -> Bool {
        guard let device = targetDevice() else { return false }
        if openDeviceID == device, backend.actuate(actuation) { return true }
        // 開いていない・別のデバイス・開いたまま使えなくなった（スリープ後など）。開き直して1回だけ試す
        backend.closeActuator()
        openDeviceID = nil
        if let failed = failedAt[device], now - failed < HapticTuning.actuatorRetryInterval { return false }
        guard backend.openActuator(deviceID: device) else {
            failedAt[device] = now
            return false
        }
        openDeviceID = device
        guard backend.actuate(actuation) else {
            backend.closeActuator()
            openDeviceID = nil
            failedAt[device] = now
            return false
        }
        failedAt[device] = nil
        return true
    }

    private func targetDevice() -> UInt64? {
        if let touched = lastTouchedDevice() { return touched }
        if defaultDevice == nil { defaultDevice = .some(backend.defaultDeviceID()) }
        return defaultDevice ?? nil
    }
}

/// CMultitouch のアクチュエータと NSHapticFeedbackManager
@MainActor
final class MultitouchHapticBackend: HapticBackend {
    func openActuator(deviceID: UInt64) -> Bool {
        guard (try? MultitouchLibrary.load()) != nil else { return false }
        let result = cmt_actuator_open(deviceID)
        if result != 0 {
            inputLogger.notice("アクチュエータを開けない（0x\(String(UInt32(bitPattern: result), radix: 16), privacy: .public)）。公開 API で鳴らす")
        }
        return result == 0
    }

    func actuate(_ actuation: HapticActuation) -> Bool {
        cmt_actuator_actuate(actuation.actuationID, actuation.unknown1, actuation.unknown2, actuation.unknown3) == 0
    }

    func closeActuator() {
        cmt_actuator_close()
    }

    func defaultDeviceID() -> UInt64? {
        MultitouchDeviceInfo.usable(MultitouchLibrary.devices()).first?.id
    }

    func performFallback(_ pattern: HapticFallbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern.nsPattern, performanceTime: .now)
    }

    deinit {
        cmt_actuator_close()
    }
}

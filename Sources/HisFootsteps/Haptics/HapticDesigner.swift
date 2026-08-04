import CoreHaptics
import Foundation

/// ハプティクスの強度プロファイル。
enum HapticProfile: String, CaseIterable, Identifiable, Codable {
    /// 静かな場所向け。点で軽く鳴らす。
    case subtle = "そっと"
    /// 標準。打点の質感がはっきり分かる。
    case standard = "標準"
    /// 全身に来る。重ねがけで最大限の衝撃を出す。
    case brutal = "強烈"

    var id: String { rawValue }

    /// 全イベントに掛かる強度倍率
    var gain: Float {
        switch self {
        case .subtle: return 0.55
        case .standard: return 0.82
        case .brutal: return 1.0
        }
    }

    /// 打撃の余韻レイヤーを重ねるか（これが「ズドン」の正体）
    var layered: Bool {
        switch self {
        case .subtle: return false
        case .standard, .brutal: return true
        }
    }

    /// 拍間を埋める低周波の「グルーヴベッド」を鳴らすか
    var grooveBed: Bool {
        self == .brutal
    }

    var description: String {
        switch self {
        case .subtle: return "図書館でも使える控えめな触感"
        case .standard: return "打点の輪郭がくっきり分かる"
        case .brutal: return "手のひらまで響く。推奨"
        }
    }
}

/// 打点の種類ごとに「触って気持ちいい波形」を組み立てる工房。
///
/// 設計の要点:
///  - シャープネスが高いtransient単発は「カチッ」としか感じない。
///    低シャープネスのcontinuous（減衰エンベロープ付き）を重ねると初めて「ドンッ」になる。
///  - キックは 立ち上がりのtransient → 太い胴鳴りのcontinuous → 余韻のtransient の3層。
///  - スネアは 鋭いtransient → 短いバズ → 抜けのtransient の3層。
enum HapticDesigner {

    // MARK: - 部品

    private static func clamp(_ value: Float) -> Float {
        min(1, max(0, value))
    }

    private static func transient(_ time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: clamp(intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: clamp(sharpness))
            ],
            relativeTime: max(0, time)
        )
    }

    private static func continuous(
        _ time: TimeInterval,
        duration: TimeInterval,
        intensity: Float,
        sharpness: Float,
        attack: Float = 0,
        decay: Float = 0.1,
        sustained: Bool = false
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: clamp(intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: clamp(sharpness)),
                CHHapticEventParameter(parameterID: .attackTime, value: clamp(attack)),
                CHHapticEventParameter(parameterID: .decayTime, value: clamp(decay)),
                CHHapticEventParameter(parameterID: .sustained, value: sustained ? 1 : 0)
            ],
            relativeTime: max(0, time),
            duration: max(0.01, duration)
        )
    }

    // MARK: - 打点

    static func events(
        for kind: HitKind,
        at time: TimeInterval,
        strength: Float,
        profile: HapticProfile
    ) -> [CHHapticEvent] {
        let gain = profile.gain
        let s = clamp(strength)

        switch kind {
        case .kick:
            // ズ・ドン。胴鳴りを長めに取り、余韻のもう一撃で「重さ」を作る。
            let i = clamp((0.80 + 0.20 * s) * gain)
            var events = [
                transient(time, intensity: i, sharpness: 0.12),
                continuous(time + 0.003, duration: 0.15, intensity: i, sharpness: 0.0, attack: 0, decay: 0.13)
            ]
            if profile.layered {
                events.append(transient(time + 0.048, intensity: i * 0.5, sharpness: 0.02))
                events.append(continuous(time + 0.05, duration: 0.10, intensity: i * 0.42, sharpness: 0.0, attack: 0.01, decay: 0.09))
            }
            return events

        case .snare:
            // パンッ。高めのシャープネスで前に出し、短いバズで胴を鳴らす。
            let i = clamp((0.74 + 0.26 * s) * gain)
            var events = [
                transient(time, intensity: i, sharpness: 0.85),
                continuous(time + 0.002, duration: 0.075, intensity: i * 0.92, sharpness: 0.55, attack: 0, decay: 0.065)
            ]
            if profile.layered {
                events.append(transient(time + 0.020, intensity: i * 0.5, sharpness: 1.0))
            }
            return events

        case .hat:
            // チッ。存在は分かるが主張しない粒。
            let i = clamp((0.24 + 0.24 * s) * gain)
            return [transient(time, intensity: i, sharpness: 1.0)]

        case .openHat:
            let i = clamp((0.28 + 0.24 * s) * gain)
            return [
                transient(time, intensity: i * 0.8, sharpness: 1.0),
                continuous(time + 0.004, duration: 0.085, intensity: i * 0.7, sharpness: 0.9, attack: 0, decay: 0.08)
            ]

        case .accent:
            // ドカーン。小節頭やキメで全身に来る一撃。
            let i = clamp(gain)
            var events = [
                transient(time, intensity: i, sharpness: 0.28),
                continuous(time + 0.002, duration: 0.34, intensity: i, sharpness: 0.08, attack: 0, decay: 0.3)
            ]
            if profile.layered {
                events.append(transient(time + 0.055, intensity: i * 0.72, sharpness: 0.05))
                events.append(transient(time + 0.125, intensity: i * 0.45, sharpness: 0.0))
                events.append(continuous(time + 0.13, duration: 0.20, intensity: i * 0.4, sharpness: 0.02, attack: 0.02, decay: 0.18))
            }
            return events

        case .ghost:
            let i = clamp(0.16 * s * gain + 0.06 * gain)
            return [transient(time, intensity: i, sharpness: 0.7)]
        }
    }

    /// 拍と拍の間を埋める低周波のうねり。これがあると「点」ではなく「グルーヴ」になる。
    static func bedEvent(
        at time: TimeInterval,
        duration: TimeInterval,
        lowEnergy: Float,
        profile: HapticProfile
    ) -> CHHapticEvent? {
        guard profile.grooveBed else { return nil }
        let intensity = clamp((0.05 + 0.17 * clamp(lowEnergy)) * profile.gain)
        guard intensity > 0.045 else { return nil }
        return continuous(
            time,
            duration: max(0.05, duration),
            intensity: intensity,
            sharpness: 0.0,
            attack: 0.15,
            decay: 0.4,
            sustained: false
        )
    }

    // MARK: - 単発演出

    /// カウントイン（3・2・1・GO）のクリック
    static func countInEvents(at time: TimeInterval, isFinal: Bool, profile: HapticProfile) -> [CHHapticEvent] {
        if isFinal {
            return events(for: .accent, at: time, strength: 1, profile: profile)
        }
        let i = clamp(0.8 * profile.gain)
        return [
            transient(time, intensity: i, sharpness: 0.6),
            continuous(time + 0.002, duration: 0.06, intensity: i * 0.7, sharpness: 0.3, attack: 0, decay: 0.055)
        ]
    }

    /// PERFECT判定時のごく短い「効いてる」感。ビートを濁さないよう極小に留める。
    static func perfectSparkle(at time: TimeInterval, profile: HapticProfile) -> [CHHapticEvent] {
        let i = clamp(0.35 * profile.gain)
        return [
            transient(time, intensity: i, sharpness: 1.0),
            transient(time + 0.028, intensity: i * 0.6, sharpness: 1.0)
        ]
    }

    /// オンボーディングで「これがマイケルの鼓動だ」と伝えるためのハートビート
    static func heartbeatEvents(profile: HapticProfile) -> [CHHapticEvent] {
        var events: [CHHapticEvent] = []
        events += self.events(for: .kick, at: 0.0, strength: 1, profile: profile)
        events += self.events(for: .kick, at: 0.22, strength: 0.7, profile: profile)
        return events
    }
}

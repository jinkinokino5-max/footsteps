import Combine
import Foundation

/// ユーザー設定（ハプティクスの強度、モード、同期の微調整）。
final class AppSettings: ObservableObject {
    private enum Key {
        static let profile = "hf.hapticProfile"
        static let mode = "hf.performanceMode"
        static let lead = "hf.hapticLeadMs"
        static let punchEQ = "hf.punchEQ"
        static let onboarded = "hf.onboarded"
    }

    @Published var hapticProfile: HapticProfile {
        didSet { UserDefaults.standard.set(hapticProfile.rawValue, forKey: Key.profile) }
    }

    @Published var mode: PerformanceMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Key.mode) }
    }

    /// ハプティクスを何ミリ秒早く出すか（-60...+60）
    @Published var hapticLeadMs: Double {
        didSet {
            UserDefaults.standard.set(hapticLeadMs, forKey: Key.lead)
            HapticConductor.shared.leadTime = hapticLeadMs / 1000.0
        }
    }

    @Published var punchEQ: Bool {
        didSet {
            UserDefaults.standard.set(punchEQ, forKey: Key.punchEQ)
            AudioEngineController.shared.punchEQEnabled = punchEQ
        }
    }

    @Published var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: Key.onboarded) }
    }

    init() {
        let defaults = UserDefaults.standard
        hapticProfile = HapticProfile(rawValue: defaults.string(forKey: Key.profile) ?? "") ?? .brutal
        mode = PerformanceMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .beatFocus
        hapticLeadMs = defaults.object(forKey: Key.lead) as? Double ?? 0
        punchEQ = defaults.object(forKey: Key.punchEQ) as? Bool ?? true
        hasOnboarded = defaults.bool(forKey: Key.onboarded)

        HapticConductor.shared.leadTime = hapticLeadMs / 1000.0
        AudioEngineController.shared.punchEQEnabled = punchEQ
    }
}

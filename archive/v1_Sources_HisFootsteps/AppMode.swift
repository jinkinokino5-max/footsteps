import Foundation

/// 企画書「機能5：モード切り替え」に対応する3つの体験モード
enum AppMode: String, CaseIterable, Identifiable {
    case beatFocused = "ビート重視"
    case stepFocused = "ステップ重視"
    case viewingOnly = "観賞"

    var id: String { rawValue }

    /// ハプティクスの強さ（ビート重視モードは振動を強めにする）
    var hapticIntensity: Float {
        switch self {
        case .beatFocused: return 1.0
        case .stepFocused: return 0.7
        case .viewingOnly: return 0.85
        }
    }

    /// 指の追従判定を行うかどうか（観賞モードは操作なしで眺めるだけ）
    var isFollowJudgeEnabled: Bool {
        self != .viewingOnly
    }
}

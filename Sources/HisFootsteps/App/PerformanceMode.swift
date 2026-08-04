import Foundation

/// 企画書「機能5：モード切り替え」に対応する3つの体験モード。
enum PerformanceMode: String, CaseIterable, Identifiable, Codable {
    /// ビート重視：振動と閃光を最大に。判定は甘め。
    case beatFocus = "BEAT"
    /// ステップ重視：次の足跡のゴーストを見せ、判定を厳密に取る。
    case stepFocus = "STEP"
    /// 観賞：操作なしで、足跡とビートをただ浴びる。
    case watch = "WATCH"

    var id: String { rawValue }

    var japaneseName: String {
        switch self {
        case .beatFocus: return "ビート重視"
        case .stepFocus: return "ステップ重視"
        case .watch: return "観賞"
        }
    }

    var caption: String {
        switch self {
        case .beatFocus: return "振動と光を最大に浴びる"
        case .stepFocus: return "次の一歩を読んで正確に追う"
        case .watch: return "両足で踏むステップを見る"
        }
    }

    /// 指の追従を採点するか
    var judgesFollow: Bool { self != .watch }

    /// 両足でステップを踏むか。
    /// 追従モードは指で追う的が1つでないと成立しないため、いまは観賞モードのみ。
    var usesDualFeet: Bool { self == .watch }

    /// 次のステップをいくつ先まで見せるか。
    /// 0だと初見の人は次にどこへ足が飛ぶか分からず、全部MISSになって体験が終わる。
    /// どのモードでも最低1歩先は必ず見せる。
    var previewCount: Int {
        switch self {
        case .beatFocus: return 1
        case .stepFocus: return 3
        case .watch: return 1
        }
    }

    /// 閃光・パーティクルの量
    var spectacle: Double {
        switch self {
        case .beatFocus: return 1.25
        case .stepFocus: return 0.75
        case .watch: return 1.1
        }
    }

    /// 判定距離の甘さ（大きいほど甘い）
    var judgeTolerance: Double {
        switch self {
        case .beatFocus: return 1.35
        case .stepFocus: return 1.0
        case .watch: return 1.0
        }
    }
}

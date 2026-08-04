import CoreGraphics
import Foundation

enum Judgement: Int, CaseIterable {
    case perfect
    case great
    case good
    case miss

    var label: String {
        switch self {
        case .perfect: return "PERFECT"
        case .great: return "GREAT"
        case .good: return "GOOD"
        case .miss: return "MISS"
        }
    }

    var score: Int {
        switch self {
        case .perfect: return 1000
        case .great: return 600
        case .good: return 260
        case .miss: return 0
        }
    }

    /// 精度に換算したときの重み（0...1）
    var accuracyWeight: Double {
        switch self {
        case .perfect: return 1.0
        case .great: return 0.75
        case .good: return 0.4
        case .miss: return 0
        }
    }
}

struct JudgedStep {
    let moveIndex: Int
    let time: TimeInterval
    let judgement: Judgement
    /// 正規化座標での距離
    let distance: Double
    /// 正なら遅れ、負なら早い
    let timingOffset: TimeInterval?
}

struct PerformanceResult {
    let songTitle: String
    let bpm: Double
    let score: Int
    let accuracyPercent: Double
    let maxCombo: Int
    let counts: [Judgement: Int]
    /// 平均タイミングのズレ（秒）。正なら遅れ気味。
    let timingBias: TimeInterval
    let rank: String
    let headline: String
    let advice: String

    var totalSteps: Int {
        counts.values.reduce(0, +)
    }
}

/// 指の追従を拍ごとに採点する判定エンジン。
///
/// 「その瞬間の距離」だけで採点すると指が一瞬でも離れた瞬間に理不尽なミスになるため、
/// 拍の前後 ±0.15 秒のあいだで最も近づいた瞬間を探し、距離とタイミングの両方を見る。
struct FollowJudge {
    /// 判定に使う時間窓（拍の前後）
    static let timingWindow: TimeInterval = 0.16

    /// 正規化座標での距離しきい値
    static let perfectDistance = 0.075
    static let greatDistance = 0.125
    static let goodDistance = 0.20

    static func judge(
        moveIndex: Int,
        targetTime: TimeInterval,
        targetPosition: CGPoint,
        touchHistory: [(time: TimeInterval, point: CGPoint)],
        tolerance: Double = 1.0
    ) -> JudgedStep {
        var bestDistance = Double.greatestFiniteMagnitude
        var bestOffset: TimeInterval = 0
        var found = false

        for sample in touchHistory {
            let dt = sample.time - targetTime
            guard abs(dt) <= timingWindow else { continue }
            let dx = Double(sample.point.x - targetPosition.x)
            let dy = Double(sample.point.y - targetPosition.y)
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < bestDistance {
                bestDistance = distance
                bestOffset = dt
                found = true
            }
        }

        guard found else {
            return JudgedStep(moveIndex: moveIndex, time: targetTime, judgement: .miss, distance: 1, timingOffset: nil)
        }

        let scale = max(0.5, tolerance)
        let judgement: Judgement
        if bestDistance < perfectDistance * scale {
            judgement = .perfect
        } else if bestDistance < greatDistance * scale {
            judgement = .great
        } else if bestDistance < goodDistance * scale {
            judgement = .good
        } else {
            judgement = .miss
        }

        return JudgedStep(
            moveIndex: moveIndex,
            time: targetTime,
            judgement: judgement,
            distance: bestDistance,
            timingOffset: judgement == .miss ? nil : bestOffset
        )
    }

    // MARK: - 集計

    static func summarize(steps: [JudgedStep], songTitle: String, bpm: Double, maxCombo: Int, score: Int) -> PerformanceResult {
        var counts: [Judgement: Int] = [:]
        for judgement in Judgement.allCases { counts[judgement] = 0 }
        for step in steps { counts[step.judgement, default: 0] += 1 }

        let total = max(1, steps.count)
        let weighted = steps.reduce(0.0) { $0 + $1.judgement.accuracyWeight }
        let accuracy = weighted / Double(total) * 100

        let offsets = steps.compactMap(\.timingOffset)
        let bias = offsets.isEmpty ? 0 : offsets.reduce(0, +) / Double(offsets.count)

        let rank: String
        switch accuracy {
        case 96...: rank = "S+"
        case 90..<96: rank = "S"
        case 80..<90: rank = "A"
        case 68..<80: rank = "B"
        case 52..<68: rank = "C"
        default: rank = "D"
        }

        let headline: String
        switch accuracy {
        case 96...: headline = "怪物だ。彼と同じ場所に立っている。"
        case 90..<96: headline = "ステージが君のものになった。"
        case 80..<90: headline = "グルーヴに乗れている。あと一歩でキレる。"
        case 68..<80: headline = "身体は分かってきた。指がまだ追いつかない。"
        case 52..<68: headline = "ビートは掴んだ。軌跡を先読みしよう。"
        default: headline = "まずは観賞モードで、彼の歩幅を目に焼き付けよう。"
        }

        let advice: String
        if steps.isEmpty {
            advice = "画面に指を置いたまま、光る足跡を追いかけてください。"
        } else if bias > 0.045 {
            advice = "全体に \(Int(bias * 1000))ms 遅れています。次の足跡が光る前に、身体を先に送り出してください。"
        } else if bias < -0.045 {
            advice = "全体に \(Int(-bias * 1000))ms 走っています。着地の瞬間まで一拍ためると、重心が乗ります。"
        } else if (counts[.miss] ?? 0) > total / 4 {
            advice = "タイミングは合っています。移動距離の大きい所で指が置き去りです。視線を次の足跡へ先に飛ばしましょう。"
        } else {
            advice = "タイミング・軌跡ともに噛み合っています。強度を上げて、より深いグルーヴへ。"
        }

        return PerformanceResult(
            songTitle: songTitle,
            bpm: bpm,
            score: score,
            accuracyPercent: accuracy,
            maxCombo: maxCombo,
            counts: counts,
            timingBias: bias,
            rank: rank,
            headline: headline,
            advice: advice
        )
    }
}

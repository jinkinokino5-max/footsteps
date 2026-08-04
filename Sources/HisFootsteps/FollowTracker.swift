import Combine
import CoreGraphics
import Foundation

struct FollowJudgeResult {
    let beatIndex: Int
    /// 目標座標との距離（判定不能な場合はnil＝ミス扱い）
    let distance: CGFloat?
    /// 正: 拍より遅れて追従、負: 拍より早く追従。判定不能ならnil
    let timingOffset: TimeInterval?
}

struct FollowSummary {
    let accuracyPercent: Double
    let comment: String
    let timingComment: String?
}

/// 指の追従位置と足跡の目標座標を拍ごとに突き合わせ、追従精度とタイミングのズレを判定する（Phase6：割り切った精度で実装）
final class FollowTracker: ObservableObject {
    @Published private(set) var results: [FollowJudgeResult] = []

    /// 拍の前後どれだけの範囲まで、指の履歴からタイミング判定の候補として探すか
    private let timingSearchWindow: TimeInterval = 0.3

    func reset() {
        results = []
    }

    /// - Parameters:
    ///   - beatTime: 再生開始からの拍の相対時刻
    ///   - touchHistory: 再生開始からの相対時刻付きの指の位置履歴
    func record(
        beatIndex: Int,
        beatTime: TimeInterval,
        targetPosition: CGPoint,
        touchHistory: [(time: TimeInterval, location: CGPoint)],
        maxAcceptableDistance: CGFloat
    ) {
        let candidates = touchHistory.filter { abs($0.time - beatTime) <= timingSearchWindow }
        guard !candidates.isEmpty else {
            results.append(FollowJudgeResult(beatIndex: beatIndex, distance: nil, timingOffset: nil))
            return
        }

        var bestDistance: CGFloat = .greatestFiniteMagnitude
        var bestOffset: TimeInterval = 0
        for candidate in candidates {
            let dx = candidate.location.x - targetPosition.x
            let dy = candidate.location.y - targetPosition.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < bestDistance {
                bestDistance = distance
                bestOffset = candidate.time - beatTime
            }
        }

        guard bestDistance <= maxAcceptableDistance else {
            results.append(FollowJudgeResult(beatIndex: beatIndex, distance: bestDistance, timingOffset: nil))
            return
        }

        results.append(FollowJudgeResult(beatIndex: beatIndex, distance: bestDistance, timingOffset: bestOffset))
    }

    func summary(maxAcceptableDistance: CGFloat) -> FollowSummary {
        guard !results.isEmpty, maxAcceptableDistance > 0 else {
            return FollowSummary(accuracyPercent: 0, comment: "判定データがありません。指で足跡をなぞりながら再生してください。", timingComment: nil)
        }

        let scores: [Double] = results.map { result in
            guard let distance = result.distance else { return 0 }
            let clamped = min(distance, maxAcceptableDistance)
            return Double(1 - clamped / maxAcceptableDistance)
        }
        let average = scores.reduce(0, +) / Double(scores.count)
        let percent = average * 100

        let comment: String
        switch percent {
        case 80...:
            comment = "素晴らしい追従精度です。ビートにしっかり乗れています。"
        case 50..<80:
            comment = "まずまずの精度です。軌跡の切り替わりのタイミングを意識するとさらに良くなります。"
        default:
            comment = "軌跡からのズレが大きめです。まずはゆっくり指で追ってみましょう。"
        }

        let timingOffsets = results.compactMap(\.timingOffset)
        let timingComment: String?
        if timingOffsets.isEmpty {
            timingComment = nil
        } else {
            let averageOffset = timingOffsets.reduce(0, +) / Double(timingOffsets.count)
            switch averageOffset {
            case ..<(-0.05):
                timingComment = "全体的にビートより早めに動いています。少し待ってから動くと合いやすくなります。"
            case 0.05...:
                timingComment = "全体的にビートより遅れて動いています。少し先取りして動いてみましょう。"
            default:
                timingComment = "タイミングはビートとよく合っています。"
            }
        }

        return FollowSummary(accuracyPercent: percent, comment: comment, timingComment: timingComment)
    }
}

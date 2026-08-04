import Combine
import CoreGraphics

struct FollowJudgeResult {
    let beatIndex: Int
    /// 目標座標との距離（指を離していた場合はnil＝ミス扱い）
    let distance: CGFloat?
}

struct FollowSummary {
    let accuracyPercent: Double
    let comment: String
}

/// 指の追従位置と足跡の目標座標を拍ごとに突き合わせ、追従精度を判定する（Phase6：割り切った精度で実装）
final class FollowTracker: ObservableObject {
    @Published private(set) var results: [FollowJudgeResult] = []

    func reset() {
        results = []
    }

    func record(beatIndex: Int, targetPosition: CGPoint, touchLocation: CGPoint?) {
        guard let touchLocation else {
            results.append(FollowJudgeResult(beatIndex: beatIndex, distance: nil))
            return
        }
        let dx = touchLocation.x - targetPosition.x
        let dy = touchLocation.y - targetPosition.y
        let distance = (dx * dx + dy * dy).squareRoot()
        results.append(FollowJudgeResult(beatIndex: beatIndex, distance: distance))
    }

    func summary(maxAcceptableDistance: CGFloat) -> FollowSummary {
        guard !results.isEmpty, maxAcceptableDistance > 0 else {
            return FollowSummary(accuracyPercent: 0, comment: "判定データがありません。指で足跡をなぞりながら再生してください。")
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
        return FollowSummary(accuracyPercent: percent, comment: comment)
    }
}

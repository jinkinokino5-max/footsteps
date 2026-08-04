import CoreGraphics

/// 拍インデックスから足跡の目標座標を生成する（左右交互＋上下のジグザグで簡易的なステップ軌跡を表現）
enum FootstepPath {
    private static let verticalFractions: [CGFloat] = [0.25, 0.5, 0.75, 0.5]

    static func position(forBeatIndex index: Int, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }

        let isLeft = index % 2 == 0
        let x = size.width * (isLeft ? 0.3 : 0.7)

        let cyclePosition = index % verticalFractions.count
        let y = size.height * verticalFractions[cyclePosition]

        return CGPoint(x: x, y: y)
    }
}

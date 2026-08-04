import CoreGraphics
import Foundation

/// 1小節分のステップの型。マイケルの動きの語彙を抽象化したもの。
enum StepPattern: CaseIterable {
    /// 左右に踏み替える基本形
    case sideStep
    /// 四角を描く
    case boxStep
    /// 足を交差させる
    case crossStep
    /// ムーンウォーク（左へ滑る）
    case moonwalkLeft
    /// ムーンウォーク（右へ滑る）
    case moonwalkRight
    /// 16分に迫る速い切り返し
    case zigzagFast
    /// 蹴り出しの連打
    case kickCombo
    /// 溜めてスピン
    case spinCombo
    /// つま先立ちからのフリーズ
    case toeFreeze
    /// センターで小さく揺れる
    case anchorSway

    /// ステージ内の安全域
    private static let minX = 0.15
    private static let maxX = 0.85
    private static let minY = 0.22
    private static let maxY = 0.84

    private static func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: CGFloat(min(maxX, max(minX, Double(point.x)))),
            y: CGFloat(min(maxY, max(minY, Double(point.y))))
        )
    }

    private struct Slot {
        var position: CGPoint
        var style: MoveStyle
        var rotation: Double
        var plants: Bool = true
        /// 拍のどこに置くか（0.0 = 拍の頭、0.5 = 裏拍）
        var offset: Double = 0
    }

    func build(
        beats: [GrooveBeat],
        beatPeriod: TimeInterval,
        startFoot: Foot,
        startPosition: CGPoint,
        energy: Double,
        rng: inout DeterministicRandom
    ) -> [StepMove] {
        guard !beats.isEmpty else { return [] }

        let jitterX = rng.range(-0.035, 0.035)
        let jitterY = rng.range(-0.03, 0.03)

        var foot = startFoot
        var out: [StepMove] = []

        for (i, beat) in beats.enumerated() {
            let slots = self.slots(atBeat: i, energy: energy, startPosition: startPosition)
            for slot in slots {
                let position = StepPattern.clamped(
                    CGPoint(x: slot.position.x + CGFloat(jitterX), y: slot.position.y + CGFloat(jitterY))
                )
                let time = beat.time + beatPeriod * slot.offset
                let travel = beatPeriod * slot.style.travelRatio * (slot.offset > 0 ? 0.5 : 1.0)
                out.append(
                    StepMove(
                        time: time,
                        travel: max(0.05, travel),
                        position: position,
                        foot: foot,
                        rotation: slot.rotation,
                        style: slot.style,
                        bar: beat.bar,
                        beatIndex: beat.index,
                        accent: beat.isDownbeat && slot.offset == 0,
                        plants: slot.plants
                    )
                )
                foot = foot.opposite
            }
        }
        return out
    }

    // MARK: - 型ごとの足の置き場所

    private func slots(atBeat i: Int, energy: Double, startPosition: CGPoint) -> [Slot] {
        let index = i % 4

        switch self {
        case .sideStep:
            let left = index % 2 == 0
            return [Slot(
                position: CGPoint(x: left ? 0.31 : 0.69, y: index < 2 ? 0.66 : 0.58),
                style: .plant,
                rotation: left ? -13 : 13
            )]

        case .boxStep:
            let corners: [CGPoint] = [
                CGPoint(x: 0.33, y: 0.74),
                CGPoint(x: 0.33, y: 0.44),
                CGPoint(x: 0.67, y: 0.44),
                CGPoint(x: 0.67, y: 0.74)
            ]
            let rotations: [Double] = [-18, -6, 8, 20]
            return [Slot(position: corners[index], style: .plant, rotation: rotations[index])]

        case .crossStep:
            let spots: [CGPoint] = [
                CGPoint(x: 0.40, y: 0.70),
                CGPoint(x: 0.60, y: 0.62),
                CGPoint(x: 0.35, y: 0.54),
                CGPoint(x: 0.65, y: 0.70)
            ]
            let rotations: [Double] = [28, -28, 34, -34]
            return [Slot(position: spots[index], style: index % 2 == 0 ? .plant : .snap, rotation: rotations[index])]

        case .moonwalkLeft, .moonwalkRight:
            let goingLeft = (self == .moonwalkLeft)
            let t = Double(index) / 3.0
            let from = goingLeft ? 0.78 : 0.22
            let to = goingLeft ? 0.22 : 0.78
            let x = from + (to - from) * t
            let y = 0.68 - 0.03 * sin(t * .pi)
            return [Slot(
                position: CGPoint(x: x, y: y),
                style: .glide,
                rotation: goingLeft ? -6 : 6,
                plants: index % 2 == 0
            )]

        case .zigzagFast:
            // 8分で切り返す。速い展開の小節に使う。
            let first = Slot(
                position: CGPoint(x: index % 2 == 0 ? 0.29 : 0.71, y: 0.76 - 0.10 * Double(index)),
                style: .snap,
                rotation: index % 2 == 0 ? -22 : 22
            )
            let second = Slot(
                position: CGPoint(x: index % 2 == 0 ? 0.44 : 0.56, y: 0.72 - 0.10 * Double(index)),
                style: .snap,
                rotation: index % 2 == 0 ? -8 : 8,
                plants: energy > 0.7,
                offset: 0.5
            )
            return energy > 0.55 ? [first, second] : [first]

        case .kickCombo:
            switch index {
            case 0: return [Slot(position: CGPoint(x: 0.42, y: 0.70), style: .plant, rotation: -10)]
            case 1: return [Slot(position: CGPoint(x: 0.76, y: 0.52), style: .kick, rotation: 42)]
            case 2: return [Slot(position: CGPoint(x: 0.58, y: 0.70), style: .plant, rotation: 10)]
            default: return [Slot(position: CGPoint(x: 0.24, y: 0.52), style: .kick, rotation: -42)]
            }

        case .spinCombo:
            switch index {
            case 0: return [Slot(position: CGPoint(x: 0.36, y: 0.68), style: .plant, rotation: -14)]
            case 1: return [Slot(position: CGPoint(x: 0.64, y: 0.68), style: .plant, rotation: 14)]
            case 2: return [Slot(position: CGPoint(x: 0.50, y: 0.56), style: .snap, rotation: 0)]
            default: return [Slot(position: CGPoint(x: 0.50, y: 0.50), style: .spin, rotation: 0)]
            }

        case .toeFreeze:
            switch index {
            case 0: return [Slot(position: CGPoint(x: 0.50, y: 0.66), style: .plant, rotation: 0)]
            case 1: return [Slot(position: CGPoint(x: 0.50, y: 0.62), style: .toeStand, rotation: 0)]
            case 2: return [Slot(position: CGPoint(x: 0.50, y: 0.62), style: .freeze, rotation: 0, plants: false)]
            default: return [Slot(position: CGPoint(x: 0.68, y: 0.70), style: .snap, rotation: 24)]
            }

        case .anchorSway:
            let left = index % 2 == 0
            return [Slot(
                position: CGPoint(x: left ? 0.44 : 0.56, y: 0.66 - 0.02 * Double(index)),
                style: .plant,
                rotation: left ? -7 : 7
            )]
        }
    }
}

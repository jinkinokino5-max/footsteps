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
    private static let minX = 0.12
    private static let maxX = 0.88
    private static let minY = 0.30
    private static let maxY = 0.87

    private static func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: CGFloat(min(maxX, max(minX, Double(point.x)))),
            y: CGFloat(min(maxY, max(minY, Double(point.y))))
        )
    }

    /// パターンの素の座標を、ステージ全体へ広げる。
    ///
    /// 素の値（x 0.29〜0.71 / y 0.44〜0.76）のまま描くと、画面のごく一部にしか
    /// 足跡が現れず「狭いところでうろうろしている」ように見えてしまう。
    /// 中心から外へ引き伸ばして、床の奥行きを使い切る。
    private static func spread(_ point: CGPoint) -> CGPoint {
        let x = 0.5 + (Double(point.x) - 0.5) * 1.18
        let y = 0.575 + (Double(point.y) - 0.60) * 1.55
        return clamped(CGPoint(x: x, y: y))
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
        var isFirstOfBar = true
        var previousPosition = startPosition

        // 小節内の位置は必ず beatInBar で見る。イントロなどで拍が欠けた小節でも、
        // パターンの1拍目が小節頭に落ちるようにするため。
        for beat in beats {
            let slots = self.slots(atBeat: beat.beatInBar, energy: energy, startPosition: startPosition)
            for slot in slots {
                let position = StepPattern.spread(
                    CGPoint(x: slot.position.x + CGFloat(jitterX), y: slot.position.y + CGFloat(jitterY))
                )

                let dx = Double(position.x - previousPosition.x)
                let dy = Double(position.y - previousPosition.y)
                let distance = (dx * dx + dy * dy).squareRoot()

                // 小節の切り替わりで舞台の端から端へ飛ぶことがある。
                // それを踏み込みでやると指が物理的に間に合わないので、滑りに変える。
                // 見た目にも「大きな移動＝スライド」の方が自然。
                var style = slot.style
                if isFirstOfBar, style == .plant || style == .snap, distance > 0.40 {
                    style = .glide
                }
                isFirstOfBar = false
                previousPosition = position

                // 移動が長いほど、到達までの時間も伸ばす。
                // 質感（速く出てピタリと止まる）は保ったまま、指が間に合う速度に収める。
                var ratio = style.travelRatio
                if distance > 0.32 {
                    ratio = min(0.95, ratio * (1 + (distance - 0.32) * 1.6))
                }

                let time = beat.time + beatPeriod * slot.offset
                let travel = beatPeriod * ratio * (slot.offset > 0 ? 0.5 : 1.0)
                out.append(
                    StepMove(
                        time: time,
                        travel: max(0.05, travel),
                        position: position,
                        foot: foot,
                        rotation: slot.rotation,
                        style: style,
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

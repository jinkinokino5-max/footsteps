import CoreGraphics
import Foundation

enum Foot: Int, Codable {
    case left
    case right

    var mirrored: Bool { self == .left }
    var opposite: Foot { self == .left ? .right : .left }
}

/// ステップの質。到達の仕方（イージング）と見た目がここで変わる。
enum MoveStyle: Int, Codable {
    /// 踏み込む。素早く到達して止まる。
    case plant
    /// 滑る（ムーンウォーク）。拍いっぱいを使って等速で移動する。
    case glide
    /// 鋭い方向転換。ギリギリまで溜めて一気に到達する。
    case snap
    /// 回転。
    case spin
    /// つま先立ち。位置は動かず上に伸びる。
    case toeStand
    /// 蹴り出し。外へ出してすぐ戻る。
    case kick
    /// 完全静止のキメ。
    case freeze

    /// 拍のうち何割の時間を移動に使うか。
    /// 短すぎると指が物理的に追いつけず全部MISSになるので、
    /// 「踏み込み」の質感を保てる範囲でいちばん長く取っている。
    var travelRatio: Double {
        switch self {
        case .plant: return 0.52
        case .glide: return 1.0
        case .snap: return 0.34
        case .spin: return 0.8
        case .toeStand: return 0.55
        case .kick: return 0.42
        case .freeze: return 0.35
        }
    }
}

struct StepMove {
    /// 到達すべき時刻（＝その拍の時刻）
    let time: TimeInterval
    /// 移動にかける時間（秒）
    let travel: TimeInterval
    /// ステージ内の正規化座標（0...1）
    let position: CGPoint
    let foot: Foot
    /// 足の向き（度、0が上向き）
    let rotation: Double
    let style: MoveStyle
    let bar: Int
    /// 通し拍番号（判定と結びつける）
    let beatIndex: Int
    /// 小節頭やキメなら true
    let accent: Bool
    /// この足を実際に「置く」か（滑りの途中は置かない）
    let plants: Bool
}

/// 現在フレームで足が居るべき状態。
struct ChoreoState {
    let position: CGPoint
    let rotation: Double
    /// つま先立ちなどで上に伸びる係数（1.0が標準）
    let scale: Double
    /// 到達直後の輝き（0...1）
    let landing: Double
    let foot: Foot
    let style: MoveStyle
    /// 直近に到達した手順の番号
    let moveIndex: Int
}

/// 曲のグルーヴマップから「振り付け」を組み立てる。
///
/// ただのランダム移動ではなく、小節単位で意味のあるステップ（サイドステップ、ムーンウォーク、
/// スピン、キック、フリーズ）を、その小節のエネルギーに応じて選び出して並べる。
/// 同じ曲なら必ず同じ振り付けになるので、繰り返し練習が成立する。
struct Choreography {
    let moves: [StepMove]

    // MARK: - 生成

    static func build(from map: GrooveMap) -> Choreography {
        var rng = DeterministicRandom(seed: fnv1a(map.songID))
        var moves: [StepMove] = []
        moves.reserveCapacity(map.beats.count + 8)

        // 小節ごとにビートをまとめる
        var barBuckets: [Int: [GrooveBeat]] = [:]
        for beat in map.beats {
            barBuckets[beat.bar, default: []].append(beat)
        }
        let bars = barBuckets.keys.sorted()

        var currentFoot: Foot = .right
        var lastPosition = CGPoint(x: 0.5, y: 0.62)

        for bar in bars {
            guard let beats = barBuckets[bar]?.sorted(by: { $0.index < $1.index }), !beats.isEmpty else { continue }
            let energy = Double(map.energy(ofBar: max(0, bar)))
            let pattern = choosePattern(bar: bar, energy: energy, rng: &rng)

            let generated = pattern.build(
                beats: beats,
                beatPeriod: map.beatPeriod,
                startFoot: currentFoot,
                startPosition: lastPosition,
                energy: energy,
                rng: &rng
            )
            if let last = generated.last {
                currentFoot = last.foot.opposite
                lastPosition = last.position
            }
            moves.append(contentsOf: generated)
        }

        moves.sort { $0.time < $1.time }
        return Choreography(moves: moves)
    }

    private static func choosePattern(bar: Int, energy: Double, rng: inout DeterministicRandom) -> StepPattern {
        // 8小節に一度は「見せ場」を置く
        if bar > 0, bar % 8 == 7 {
            return rng.bool() ? .spinCombo : .toeFreeze
        }
        if bar > 0, bar % 4 == 3, energy > 0.45 {
            return .kickCombo
        }

        if energy < 0.32 {
            return rng.pick([.anchorSway, .sideStep, .toeFreeze])
        } else if energy < 0.58 {
            return rng.pick([.sideStep, .boxStep, .crossStep, .moonwalkLeft])
        } else {
            return rng.pick([.zigzagFast, .moonwalkRight, .kickCombo, .crossStep, .boxStep])
        }
    }

    // MARK: - 参照

    /// 指定時刻に足が居るべき状態を返す。
    func state(at time: TimeInterval) -> ChoreoState {
        guard !moves.isEmpty else {
            return ChoreoState(
                position: CGPoint(x: 0.5, y: 0.6),
                rotation: 0,
                scale: 1,
                landing: 0,
                foot: .right,
                style: .plant,
                moveIndex: 0
            )
        }

        let nextIndex = firstMoveIndex(after: time)

        // 全ステップを終えたあと
        guard nextIndex < moves.count else {
            let last = moves[moves.count - 1]
            return ChoreoState(
                position: last.position,
                rotation: last.rotation,
                scale: 1,
                landing: 0,
                foot: last.foot,
                style: last.style,
                moveIndex: moves.count - 1
            )
        }

        let next = moves[nextIndex]
        let previous: StepMove? = nextIndex > 0 ? moves[nextIndex - 1] : nil
        let from = previous?.position ?? next.position
        let fromRotation = previous?.rotation ?? next.rotation

        let travelStart = next.time - next.travel
        let raw: Double
        if time <= travelStart {
            raw = 0
        } else {
            raw = min(1, max(0, (time - travelStart) / max(0.016, next.travel)))
        }
        let eased = ease(raw, style: next.style)

        let progress = CGFloat(eased)
        var position = CGPoint(
            x: from.x + (next.position.x - from.x) * progress,
            y: from.y + (next.position.y - from.y) * progress
        )
        var rotation = fromRotation + shortestAngle(from: fromRotation, to: next.rotation) * eased
        var scale = 1.0

        switch next.style {
        case .spin:
            rotation = fromRotation + 360 * eased
        case .toeStand:
            scale = 1.0 + 0.35 * sin(eased * .pi)
        case .kick:
            // 一度外へ蹴り出して戻る弧を描く
            let arc = sin(eased * .pi)
            position.x += (next.position.x - from.x) * CGFloat(0.35 * arc)
            position.y -= CGFloat(0.10 * arc)
            scale = 1.0 + 0.15 * arc
        case .glide:
            scale = 0.94
        default:
            break
        }

        // 直前に到達したステップの余韻（着地の光）
        var landing = 0.0
        if let previous {
            let since = time - previous.time
            if since >= 0, since < 0.28 {
                landing = 1 - since / 0.28
            }
        }

        return ChoreoState(
            position: position,
            rotation: rotation,
            scale: scale,
            landing: landing,
            foot: next.foot,
            style: next.style,
            moveIndex: nextIndex
        )
    }

    func firstMoveIndex(after time: TimeInterval) -> Int {
        var low = 0
        var high = moves.count
        while low < high {
            let mid = (low + high) / 2
            if moves[mid].time < time { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// 直近に踏まれた足跡（残像描画用）
    func recentPlants(before time: TimeInterval, window: TimeInterval) -> ArraySlice<StepMove> {
        let end = firstMoveIndex(after: time)
        var start = end
        while start > 0, moves[start - 1].time > time - window {
            start -= 1
        }
        return moves[start..<end]
    }

    // MARK: - 補間

    private func ease(_ t: Double, style: MoveStyle) -> Double {
        switch style {
        case .glide:
            return t
        case .snap:
            // 溜めてから一気に
            return t * t * t
        case .plant, .kick:
            // 素早く出て、着地でぴたりと止まる
            return 1 - pow(1 - t, 4)
        case .spin:
            return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .toeStand, .freeze:
            return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        }
    }

    private func shortestAngle(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    // MARK: - 決定的な乱数

    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01b3
        }
        return hash
    }
}

/// 同じ曲なら常に同じ振り付けになるようにするための、種付き擬似乱数。
struct DeterministicRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func unit() -> Double {
        Double(next() % 1_000_000) / 1_000_000.0
    }

    mutating func bool() -> Bool {
        next() % 2 == 0
    }

    mutating func pick<T>(_ options: [T]) -> T {
        options[Int(next() % UInt64(options.count))]
    }

    mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * unit()
    }
}

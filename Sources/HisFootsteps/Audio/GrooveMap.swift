import Foundation

/// 打点の種類。ハプティクスの触感と、ビジュアルの演出はここで分岐する。
enum HitKind: Int, Codable, Sendable {
    /// キック（ドンッ）: 低くて重い衝撃
    case kick = 0
    /// スネア（タッ）: 鋭く弾ける衝撃
    case snare = 1
    /// クローズドハイハット（チッ）: 極短い点
    case hat = 2
    /// オープンハイハット（チーッ）: 短い持続
    case openHat = 3
    /// アクセント／クラッシュ: 全身に来る一撃
    case accent = 4
    /// ゴーストノート: 拍の隙間を埋める微かな粒
    case ghost = 5

    /// 演出上の「重さ」。ビジュアルのスケールなどに使う。
    var weight: Double {
        switch self {
        case .kick: return 1.0
        case .snare: return 0.8
        case .hat: return 0.28
        case .openHat: return 0.42
        case .accent: return 1.35
        case .ghost: return 0.18
        }
    }
}

struct GrooveHit: Codable, Sendable {
    /// 曲頭からの秒数
    let time: TimeInterval
    let kind: HitKind
    /// 0...1。検出されたオンセットの強さ
    let strength: Float
    /// 小節番号
    let bar: Int
    /// 小節内の16分位置（0...15）
    let step: Int
}

struct GrooveBeat: Codable, Sendable {
    let time: TimeInterval
    /// 曲全体の通し拍番号
    let index: Int
    let bar: Int
    /// 小節内の拍（0...3）
    let beatInBar: Int
    /// 0...1。その拍のオンセットの強さ
    let strength: Float

    var isDownbeat: Bool { beatInBar == 0 }
}

/// 曲を解析して得た「グルーヴの設計図」。
/// ハプティクス・振付・ビジュアルはすべてこの1つの地図から駆動される。
struct GrooveMap: Codable, Sendable {
    static let currentVersion = 3

    let version: Int
    let songID: String
    let duration: TimeInterval
    let bpm: Double
    /// 拍と拍の間隔（秒）
    let beatPeriod: TimeInterval
    /// 最初の拍の時刻
    let firstBeatTime: TimeInterval

    let beats: [GrooveBeat]
    let hits: [GrooveHit]

    /// 小節ごとの平均エネルギー（0...1）。振付の激しさを決めるのに使う。
    let barEnergy: [Float]

    /// ビジュアル駆動用のエネルギーカーブ。energyFrameRate Hzでサンプリング。
    let energyFrameRate: Double
    let lowEnergy: [Float]
    let midEnergy: [Float]
    let highEnergy: [Float]

    var barCount: Int { barEnergy.count }
    var barDuration: TimeInterval { beatPeriod * 4 }

    // MARK: - 時刻からの参照

    private func energyIndex(at time: TimeInterval) -> Int? {
        guard energyFrameRate > 0, !lowEnergy.isEmpty else { return nil }
        let i = Int(time * energyFrameRate)
        guard i >= 0, i < lowEnergy.count else { return nil }
        return i
    }

    func low(at time: TimeInterval) -> Float {
        guard let i = energyIndex(at: time) else { return 0 }
        return lowEnergy[i]
    }

    func mid(at time: TimeInterval) -> Float {
        guard let i = energyIndex(at: time), i < midEnergy.count else { return 0 }
        return midEnergy[i]
    }

    func high(at time: TimeInterval) -> Float {
        guard let i = energyIndex(at: time), i < highEnergy.count else { return 0 }
        return highEnergy[i]
    }

    /// 曲頭からの秒数を「拍単位の連続値」に変換する。1.5なら2拍目の裏。
    func beatPosition(at time: TimeInterval) -> Double {
        guard beatPeriod > 0 else { return 0 }
        return (time - firstBeatTime) / beatPeriod
    }

    func energy(ofBar bar: Int) -> Float {
        guard bar >= 0, bar < barEnergy.count else { return 0.5 }
        return barEnergy[bar]
    }
}

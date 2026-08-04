import Accelerate
import AVFoundation
import Foundation

enum GrooveAnalyzerError: Error, LocalizedError {
    case cannotOpenFile
    case emptyFile
    case fftUnavailable

    var errorDescription: String? {
        switch self {
        case .cannotOpenFile: return "曲を開けませんでした"
        case .emptyFile: return "曲の中身が空でした"
        case .fftUnavailable: return "解析エンジンを初期化できませんでした"
        }
    }
}

/// 曲を「グルーヴの設計図」に変換する解析エンジン。
///
/// 処理の流れ:
///  1. STFT（vDSP）で低/中/高の3帯域の振幅を時系列で取り出す
///  2. 帯域ごとのスペクトルフラックス（＝音の立ち上がり）を計算し、局所統計で白色化する
///  3. 自己相関でテンポを推定し、動的計画法（Ellis法）で拍を追跡する（テンポの揺れにも追従する）
///  4. 低域の強さから小節頭（ダウンビート）を推定する
///  5. 16分グリッド上で帯域エネルギーを見て、キック/スネア/ハット/アクセントに分類する
///  6. ビジュアル用に60Hzのエネルギーカーブを出力する
enum GrooveAnalyzer {
    private static let fftSize = 1024
    private static let hopSize = 512
    static let energyFrameRate: Double = 60

    // MARK: - Public

    static func analyze(url: URL, songID: String, progress: ((Double) -> Void)? = nil) throws -> GrooveMap {
        let features = try computeSpectra(url: url, progress: progress)
        progress?(0.75)

        let frameRate = features.frameRate
        let lowN = whitened(features.lowFlux, frameRate: frameRate)
        let midN = whitened(features.midFlux, frameRate: frameRate)
        let highN = whitened(features.highFlux, frameRate: frameRate)

        var envelope = [Float](repeating: 0, count: lowN.count)
        for i in 0..<envelope.count {
            envelope[i] = lowN[i] * 1.0 + midN[i] * 0.9 + highN[i] * 0.55
        }
        envelope = smoothed(envelope, radius: 1)

        let tracked = trackBeats(envelope: envelope, frameRate: frameRate, duration: features.duration)
        let folded = foldedTempo(times: tracked.times, period: tracked.period, lowFlux: lowN, frameRate: frameRate)
        progress?(0.85)

        let beatTimes = folded.times
        let period = folded.period

        let downbeatOffset = estimateDownbeatOffset(
            beatTimes: beatTimes,
            lowFlux: lowN,
            midFlux: midN,
            frameRate: frameRate
        )

        var beats: [GrooveBeat] = []
        beats.reserveCapacity(beatTimes.count)
        for (i, t) in beatTimes.enumerated() {
            let rel = i - downbeatOffset
            let bar = Int(floor(Double(rel) / 4.0))
            let beatInBar = ((rel % 4) + 4) % 4
            let strength = sampleMax(envelope, time: t, frameRate: frameRate, radius: 2) / 4.0
            beats.append(
                GrooveBeat(
                    time: t,
                    index: i,
                    bar: bar,
                    beatInBar: beatInBar,
                    strength: min(1, max(0, strength))
                )
            )
        }

        let hits = buildHits(
            beats: beats,
            beatTimes: beatTimes,
            lowFlux: lowN,
            midFlux: midN,
            highFlux: highN,
            frameRate: frameRate
        )
        progress?(0.93)

        let curves = buildEnergyCurves(features: features)
        let barEnergy = buildBarEnergy(beats: beats, curves: curves, duration: features.duration)

        progress?(1.0)

        return GrooveMap(
            version: GrooveMap.currentVersion,
            songID: songID,
            duration: features.duration,
            bpm: period > 0 ? 60.0 / period : 120,
            beatPeriod: period,
            firstBeatTime: beatTimes.first ?? 0,
            beats: beats,
            hits: hits,
            barEnergy: barEnergy,
            energyFrameRate: energyFrameRate,
            lowEnergy: curves.low,
            midEnergy: curves.mid,
            highEnergy: curves.high
        )
    }

    // MARK: - 1. STFT

    private struct SpectralFeatures {
        var frameRate: Double
        var duration: TimeInterval
        var lowFlux: [Float]
        var midFlux: [Float]
        var highFlux: [Float]
        var lowMag: [Float]
        var midMag: [Float]
        var highMag: [Float]
    }

    private static func computeSpectra(url: URL, progress: ((Double) -> Void)?) throws -> SpectralFeatures {
        guard let file = try? AVAudioFile(forReading: url) else {
            throw GrooveAnalyzerError.cannotOpenFile
        }
        let format = file.processingFormat
        let totalFrames = file.length
        guard totalFrames > 0 else { throw GrooveAnalyzerError.emptyFile }

        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { throw GrooveAnalyzerError.emptyFile }
        guard let fft = FFTProcessor(size: fftSize) else { throw GrooveAnalyzerError.fftUnavailable }

        let binCount = fft.binCount
        let hzPerBin = sampleRate / Double(fftSize)
        func bin(_ hz: Double) -> Int { max(1, min(binCount - 1, Int(hz / hzPerBin))) }

        let lowLo = bin(28), lowHi = max(bin(28) + 1, bin(165))
        let midLo = bin(180), midHi = max(bin(180) + 1, bin(2200))
        let highLo = bin(2600), highHi = max(bin(2600) + 1, bin(11000))

        let chunkCapacity: AVAudioFrameCount = 1 << 16
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkCapacity) else {
            throw GrooveAnalyzerError.cannotOpenFile
        }

        let expectedFrames = max(16, Int(Double(totalFrames) / Double(hopSize)) + 2)
        var lowMag = [Float](); lowMag.reserveCapacity(expectedFrames)
        var midMag = [Float](); midMag.reserveCapacity(expectedFrames)
        var highMag = [Float](); highMag.reserveCapacity(expectedFrames)

        var pending = [Float]()
        pending.reserveCapacity(Int(chunkCapacity) + fftSize)
        let channelCount = Int(format.channelCount)

        while true {
            try file.read(into: buffer)
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let channelData = buffer.floatChannelData else { break }

            var mono = [Float](repeating: 0, count: n)
            mono.withUnsafeMutableBufferPointer { mp in
                guard let dst = mp.baseAddress else { return }
                dst.update(from: channelData[0], count: n)
                if channelCount > 1 {
                    for c in 1..<channelCount {
                        vDSP_vadd(dst, 1, channelData[c], 1, dst, 1, vDSP_Length(n))
                    }
                    var scale = 1.0 / Float(channelCount)
                    vDSP_vsmul(dst, 1, &scale, dst, 1, vDSP_Length(n))
                }
            }
            pending.append(contentsOf: mono)

            var pos = 0
            while pos + fftSize <= pending.count {
                pending.withUnsafeBufferPointer { bp in
                    guard let base = bp.baseAddress else { return }
                    fft.process(base + pos)
                }
                let mags = fft.magnitudes
                var lo: Float = 0, md: Float = 0, hi: Float = 0
                for i in lowLo..<lowHi { lo += mags[i] }
                for i in midLo..<midHi { md += mags[i] }
                for i in highLo..<highHi { hi += mags[i] }
                lowMag.append(lo / Float(lowHi - lowLo))
                midMag.append(md / Float(midHi - midLo))
                highMag.append(hi / Float(highHi - highLo))
                pos += hopSize
            }
            if pos > 0 { pending.removeFirst(pos) }

            if let progress {
                let ratio = Double(file.framePosition) / Double(totalFrames)
                progress(min(0.7, ratio * 0.7))
            }
        }

        guard lowMag.count > 8 else { throw GrooveAnalyzerError.emptyFile }

        return SpectralFeatures(
            frameRate: sampleRate / Double(hopSize),
            duration: Double(totalFrames) / sampleRate,
            lowFlux: flux(lowMag),
            midFlux: flux(midMag),
            highFlux: flux(highMag),
            lowMag: lowMag,
            midMag: midMag,
            highMag: highMag
        )
    }

    // MARK: - 2. フラックスと白色化

    private static func flux(_ magnitude: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: magnitude.count)
        guard magnitude.count > 1 else { return out }
        for i in 1..<magnitude.count {
            let d = magnitude[i] - magnitude[i - 1]
            out[i] = d > 0 ? d : 0
        }
        return out
    }

    /// 局所平均・局所標準偏差で正規化する（曲の音量差や録音の癖に強くする）
    private static func whitened(_ x: [Float], frameRate: Double, windowSeconds: Double = 0.7) -> [Float] {
        let n = x.count
        guard n > 4 else { return x }
        let w = max(3, Int(windowSeconds * frameRate))

        var prefix = [Double](repeating: 0, count: n + 1)
        var prefixSq = [Double](repeating: 0, count: n + 1)
        for i in 0..<n {
            let v = Double(x[i])
            prefix[i + 1] = prefix[i] + v
            prefixSq[i + 1] = prefixSq[i] + v * v
        }

        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let a = max(0, i - w)
            let b = min(n, i + w + 1)
            let c = Double(b - a)
            let mean = (prefix[b] - prefix[a]) / c
            let variance = max(0, (prefixSq[b] - prefixSq[a]) / c - mean * mean)
            let sd = variance.squareRoot()
            let v = (Double(x[i]) - mean) / (sd + 1e-5)
            out[i] = Float(max(0, v))
        }
        return out
    }

    private static func smoothed(_ x: [Float], radius: Int) -> [Float] {
        guard radius > 0, x.count > radius * 2 + 1 else { return x }
        var out = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let a = max(0, i - radius)
            let b = min(x.count - 1, i + radius)
            var s: Float = 0
            for j in a...b { s += x[j] }
            out[i] = s / Float(b - a + 1)
        }
        return out
    }

    // MARK: - 3. テンポ推定と拍追跡

    private struct TrackedBeats {
        var times: [TimeInterval]
        /// 拍の周期（秒）
        var period: TimeInterval
    }

    private static func trackBeats(envelope: [Float], frameRate: Double, duration: TimeInterval) -> TrackedBeats {
        let n = envelope.count
        let fallbackPeriod: TimeInterval = 0.5

        guard n > Int(frameRate * 4) else {
            return TrackedBeats(times: uniformGrid(period: fallbackPeriod, duration: duration), period: fallbackPeriod)
        }

        // --- 自己相関によるテンポ推定 ---
        let minLag = max(2, Int(60.0 / 190.0 * frameRate))
        let maxLag = min(n - 2, Int(60.0 / 62.0 * frameRate))
        guard maxLag > minLag + 2 else {
            return TrackedBeats(times: uniformGrid(period: fallbackPeriod, duration: duration), period: fallbackPeriod)
        }

        var acf = [Double](repeating: 0, count: maxLag + 1)
        for lag in minLag...maxLag {
            var sum = 0.0
            var i = 0
            let limit = n - lag
            while i < limit {
                sum += Double(envelope[i]) * Double(envelope[i + lag])
                i += 1
            }
            acf[lag] = sum / Double(limit)
        }

        func acfAt(_ lag: Int) -> Double {
            (lag >= minLag && lag <= maxLag) ? acf[lag] : 0
        }

        var bestLag = minLag
        var bestScore = -Double.greatestFiniteMagnitude
        for lag in minLag...maxLag {
            let bpm = 60.0 * frameRate / Double(lag)
            // 人が「これがビート」と感じやすい125BPM付近を優先する事前分布
            let prior = exp(-0.5 * pow(log2(bpm / 125.0) / 0.85, 2))
            let comb = acf[lag] + 0.5 * acfAt(lag * 2) + 0.25 * acfAt(lag * 3)
            let score = comb * prior
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }

        // 放物線補間でラグを小数精度に上げる
        var periodFrames = Double(bestLag)
        if bestLag > minLag, bestLag < maxLag {
            let y0 = acf[bestLag - 1], y1 = acf[bestLag], y2 = acf[bestLag + 1]
            let denom = y0 - 2 * y1 + y2
            if abs(denom) > 1e-12 {
                let delta = 0.5 * (y0 - y2) / denom
                if abs(delta) < 1 { periodFrames += delta }
            }
        }
        periodFrames = max(2, periodFrames)

        // --- 動的計画法による拍追跡（テンポの揺れに追従する） ---
        let tightness = 100.0
        let lo = max(1, Int((periodFrames * 0.5).rounded()))
        let hi = max(lo + 1, Int((periodFrames * 2.0).rounded()))
        let span = hi - lo + 1

        var txwt = [Double](repeating: 0, count: span)
        for k in 0..<span {
            let d = Double(lo + k)
            txwt[k] = -tightness * pow(log(d / periodFrames), 2)
        }

        var cumscore = [Double](repeating: 0, count: n)
        var backlink = [Int](repeating: -1, count: n)

        for t in 0..<n {
            var best = -Double.greatestFiniteMagnitude
            var bestTau = -1
            for k in 0..<span {
                let tau = t - (lo + k)
                if tau < 0 { break }
                let s = cumscore[tau] + txwt[k]
                if s > best {
                    best = s
                    bestTau = tau
                }
            }
            if bestTau < 0 {
                cumscore[t] = Double(envelope[t])
                backlink[t] = -1
            } else {
                cumscore[t] = Double(envelope[t]) + best
                backlink[t] = bestTau
            }
        }

        // 終端から逆にたどる
        let tailStart = max(0, n - Int(periodFrames * 2))
        var endIndex = tailStart
        var endScore = -Double.greatestFiniteMagnitude
        for t in tailStart..<n where cumscore[t] > endScore {
            endScore = cumscore[t]
            endIndex = t
        }

        var frames: [Int] = []
        var cursor = endIndex
        var guardCount = 0
        while cursor >= 0, guardCount < n + 8 {
            frames.append(cursor)
            let prev = backlink[cursor]
            if prev < 0 || prev >= cursor { break }
            cursor = prev
            guardCount += 1
        }
        frames.reverse()

        guard frames.count >= 4 else {
            let p = periodFrames / frameRate
            return TrackedBeats(times: uniformGrid(period: p, duration: duration), period: p)
        }

        // フレーム→秒。サブフレーム精度に補間する
        var times: [TimeInterval] = frames.map { f in
            refinedTime(frame: f, envelope: envelope, frameRate: frameRate)
        }

        let measuredPeriod = medianInterval(times) ?? (periodFrames / frameRate)

        times = fillGaps(times, period: measuredPeriod)
        times = extended(times, period: measuredPeriod, duration: duration)

        return TrackedBeats(times: times, period: measuredPeriod)
    }

    private static func refinedTime(frame: Int, envelope: [Float], frameRate: Double) -> TimeInterval {
        var offset = 0.0
        if frame > 0, frame < envelope.count - 1 {
            let y0 = Double(envelope[frame - 1])
            let y1 = Double(envelope[frame])
            let y2 = Double(envelope[frame + 1])
            let denom = y0 - 2 * y1 + y2
            if abs(denom) > 1e-9 {
                let delta = 0.5 * (y0 - y2) / denom
                if abs(delta) < 0.5 { offset = delta }
            }
        }
        return (Double(frame) + offset) / frameRate
    }

    private static func medianInterval(_ times: [TimeInterval]) -> TimeInterval? {
        guard times.count > 2 else { return nil }
        var intervals: [TimeInterval] = []
        intervals.reserveCapacity(times.count - 1)
        for i in 1..<times.count { intervals.append(times[i] - times[i - 1]) }
        intervals.sort()
        let v = intervals[intervals.count / 2]
        return v > 0.15 ? v : nil
    }

    /// 拍が抜けた区間（イントロの静寂など）を等間隔で埋める
    private static func fillGaps(_ times: [TimeInterval], period: TimeInterval) -> [TimeInterval] {
        guard times.count > 1, period > 0 else { return times }
        var out: [TimeInterval] = [times[0]]
        for i in 1..<times.count {
            let gap = times[i] - times[i - 1]
            let count = Int((gap / period).rounded())
            if count > 1, count < 400 {
                for k in 1..<count {
                    out.append(times[i - 1] + gap * Double(k) / Double(count))
                }
            }
            out.append(times[i])
        }
        return out
    }

    /// 曲頭・曲尾まで拍グリッドを延長する（イントロやアウトロでも体験が途切れないように）
    private static func extended(_ times: [TimeInterval], period: TimeInterval, duration: TimeInterval) -> [TimeInterval] {
        guard let first = times.first, let last = times.last, period > 0 else { return times }
        var out = times

        var t = first - period
        var head: [TimeInterval] = []
        while t > 0.05, head.count < 400 {
            head.append(t)
            t -= period
        }
        out.insert(contentsOf: head.reversed(), at: 0)

        var u = last + period
        while u < duration - 0.05, out.count < 20000 {
            out.append(u)
            u += period
        }
        return out
    }

    /// テンポを「人が足で踏める範囲」（76〜152BPM）へ畳む。
    ///
    /// 自己相関は8分音符を拍として掴むことが多く、実測でも 97BPM の曲が 195BPM として出た。
    /// そのままだと足跡が毎秒3歩以上動いて指で追えず、16分グリッドも77msまで詰まって
    /// 触覚が団子になる。ここで倍テンポを畳み、半テンポは割って、体で踏める拍に揃える。
    private static func foldedTempo(
        times: [TimeInterval],
        period: TimeInterval,
        lowFlux: [Float],
        frameRate: Double
    ) -> (times: [TimeInterval], period: TimeInterval) {
        var times = times
        var period = period

        // 速すぎる：1つおきに間引く（低域が強い方の位相を残す）
        var folds = 0
        while period > 0, 60.0 / period > 152, times.count >= 8, folds < 2 {
            var bestPhase = 0
            var bestScore = -Double.greatestFiniteMagnitude
            for phase in 0..<2 {
                var score = 0.0
                for (i, t) in times.enumerated() where i % 2 == phase {
                    score += Double(sampleMax(lowFlux, time: t, frameRate: frameRate, radius: 2))
                }
                if score > bestScore {
                    bestScore = score
                    bestPhase = phase
                }
            }
            times = times.enumerated().filter { $0.offset % 2 == bestPhase }.map { $0.element }
            period *= 2
            folds += 1
        }

        // 遅すぎる：中間に拍を挿す
        var splits = 0
        while period > 0, 60.0 / period < 68, times.count >= 2, splits < 2 {
            var out: [TimeInterval] = [times[0]]
            out.reserveCapacity(times.count * 2)
            for i in 1..<times.count {
                out.append((times[i - 1] + times[i]) / 2)
                out.append(times[i])
            }
            times = out
            period /= 2
            splits += 1
        }

        return (times, period)
    }

    private static func uniformGrid(period: TimeInterval, duration: TimeInterval) -> [TimeInterval] {
        guard period > 0, duration > 0 else { return [] }
        var out: [TimeInterval] = []
        var t = 0.0
        while t < duration, out.count < 20000 {
            out.append(t)
            t += period
        }
        return out
    }

    // MARK: - 4. ダウンビート推定

    private static func estimateDownbeatOffset(
        beatTimes: [TimeInterval],
        lowFlux: [Float],
        midFlux: [Float],
        frameRate: Double
    ) -> Int {
        guard beatTimes.count >= 8 else { return 0 }
        var bestOffset = 0
        var bestScore = -Double.greatestFiniteMagnitude

        for offset in 0..<4 {
            var score = 0.0
            for (i, t) in beatTimes.enumerated() {
                let phase = ((i - offset) % 4 + 4) % 4
                let low = Double(sampleMax(lowFlux, time: t, frameRate: frameRate, radius: 2))
                let mid = Double(sampleMax(midFlux, time: t, frameRate: frameRate, radius: 2))
                switch phase {
                case 0: score += low * 1.6 + mid * 0.2
                case 2: score += low * 0.8 + mid * 0.5
                default: score += mid * 0.45 - low * 0.25
                }
            }
            if score > bestScore {
                bestScore = score
                bestOffset = offset
            }
        }
        return bestOffset
    }

    private static func sampleMax(_ values: [Float], time: TimeInterval, frameRate: Double, radius: Int) -> Float {
        guard !values.isEmpty else { return 0 }
        let center = Int((time * frameRate).rounded())
        let a = max(0, center - radius)
        let b = min(values.count - 1, center + radius)
        guard a <= b else { return 0 }
        var best: Float = 0
        for i in a...b where values[i] > best { best = values[i] }
        return best
    }

    // MARK: - 5. 打点の分類

    private static func buildHits(
        beats: [GrooveBeat],
        beatTimes: [TimeInterval],
        lowFlux: [Float],
        midFlux: [Float],
        highFlux: [Float],
        frameRate: Double
    ) -> [GrooveHit] {
        guard beats.count > 1 else { return [] }

        // グリッド上の値を集めて、その曲に合った閾値を決める
        var lowSamples: [Float] = []
        var midSamples: [Float] = []
        var highSamples: [Float] = []
        lowSamples.reserveCapacity(beats.count * 4)

        var gridTimes: [(time: TimeInterval, bar: Int, step: Int, beatInBar: Int, onBeat: Bool)] = []
        gridTimes.reserveCapacity(beats.count * 4)
        /// 小節頭だけを集めた強さ。アクセント（キメ）の閾値をここから決める。
        var downbeatSums: [Float] = []

        for i in 0..<(beats.count - 1) {
            let b = beats[i]
            let span = beatTimes[i + 1] - beatTimes[i]
            guard span > 0.05, span < 2.5 else { continue }
            for s in 0..<4 {
                let t = beatTimes[i] + span * Double(s) / 4.0
                gridTimes.append((time: t, bar: b.bar, step: b.beatInBar * 4 + s, beatInBar: b.beatInBar, onBeat: s == 0))
                let low = sampleMax(lowFlux, time: t, frameRate: frameRate, radius: 1)
                let mid = sampleMax(midFlux, time: t, frameRate: frameRate, radius: 1)
                lowSamples.append(low)
                midSamples.append(mid)
                highSamples.append(sampleMax(highFlux, time: t, frameRate: frameRate, radius: 1))
                if s == 0, b.beatInBar == 0 {
                    downbeatSums.append(low + mid)
                }
            }
        }

        guard !gridTimes.isEmpty else { return [] }

        let kickThreshold = max(0.45, percentile(lowSamples, 0.72))
        let snareThreshold = max(0.45, percentile(midSamples, 0.74))
        let hatThreshold = max(0.35, percentile(highSamples, 0.62))
        // 小節頭のうち上位12%程度をキメにする（おおよそ8小節に1回）
        let accentThreshold = downbeatSums.isEmpty ? Float.greatestFiniteMagnitude : percentile(downbeatSums, 0.88)

        var hits: [GrooveHit] = []
        hits.reserveCapacity(gridTimes.count)

        for (index, g) in gridTimes.enumerated() {
            let low = lowSamples[index]
            let mid = midSamples[index]
            let high = highSamples[index]

            if g.onBeat {
                // 拍の上は必ず鳴らす。
                //
                // 実測すると、キックとスネアが同時に鳴る曲では低域が常に勝ってしまい、
                // 4拍すべてがキックになって「毎拍おなじ触感」＝グルーヴが消えていた。
                // ポップスの骨格は 1・3拍＝キック、2・4拍＝スネア のバックビートなので、
                // その定石を軸にし、片方が圧倒的なときだけ入れ替える。
                let isBackbeat = g.beatInBar % 2 == 1
                let lowScore = low / kickThreshold
                let midScore = mid / snareThreshold

                var kind: HitKind
                if isBackbeat {
                    kind = (midScore < 0.35 && lowScore >= 1.2) ? .kick : .snare
                } else {
                    kind = (lowScore < 0.35 && midScore >= 1.2) ? .snare : .kick
                }

                var strength = kind == .kick
                    ? normalize(low, threshold: kickThreshold)
                    : normalize(mid, threshold: snareThreshold)

                if low + mid >= accentThreshold, g.beatInBar == 0 {
                    kind = .accent
                    strength = 1.0
                }
                strength = max(strength, g.beatInBar == 0 ? 0.88 : 0.74)
                hits.append(GrooveHit(time: g.time, kind: kind, strength: min(1, strength), bar: g.bar, step: g.step))
            } else {
                if low >= kickThreshold * 1.12 {
                    hits.append(GrooveHit(time: g.time, kind: .kick, strength: min(1, normalize(low, threshold: kickThreshold)), bar: g.bar, step: g.step))
                } else if mid >= snareThreshold * 1.12 {
                    hits.append(GrooveHit(time: g.time, kind: .snare, strength: min(1, normalize(mid, threshold: snareThreshold)), bar: g.bar, step: g.step))
                } else if high >= hatThreshold * 1.35 {
                    hits.append(GrooveHit(time: g.time, kind: .hat, strength: min(1, normalize(high, threshold: hatThreshold)), bar: g.bar, step: g.step))
                } else if g.step % 2 == 0, high >= hatThreshold * 0.75 {
                    hits.append(GrooveHit(time: g.time, kind: .hat, strength: 0.4, bar: g.bar, step: g.step))
                } else if high >= hatThreshold * 0.5 {
                    hits.append(GrooveHit(time: g.time, kind: .ghost, strength: 0.28, bar: g.bar, step: g.step))
                }
            }
        }

        return merged(hits)
    }

    private static func normalize(_ value: Float, threshold: Float) -> Float {
        guard threshold > 0 else { return 0.7 }
        return min(1, max(0.3, 0.55 + 0.45 * (value - threshold) / (threshold * 1.6)))
    }

    /// 近すぎる打点は触覚的に潰れるので、強い方だけ残す
    private static func merged(_ hits: [GrooveHit]) -> [GrooveHit] {
        guard hits.count > 1 else { return hits }
        let sorted = hits.sorted { $0.time < $1.time }
        var out: [GrooveHit] = []
        out.reserveCapacity(sorted.count)
        for hit in sorted {
            if let last = out.last, hit.time - last.time < 0.035 {
                if hit.kind.weight * Double(hit.strength) > last.kind.weight * Double(last.strength) {
                    out[out.count - 1] = hit
                }
            } else {
                out.append(hit)
            }
        }
        return out
    }

    private static func percentile(_ values: [Float], _ p: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let idx = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))
        return sorted[idx]
    }

    // MARK: - 6. ビジュアル用エネルギーカーブ

    private struct EnergyCurves {
        var low: [Float]
        var mid: [Float]
        var high: [Float]
    }

    private static func buildEnergyCurves(features: SpectralFeatures) -> EnergyCurves {
        EnergyCurves(
            low: resampleEnergy(features.lowMag, from: features.frameRate, duration: features.duration, release: 0.16),
            mid: resampleEnergy(features.midMag, from: features.frameRate, duration: features.duration, release: 0.13),
            high: resampleEnergy(features.highMag, from: features.frameRate, duration: features.duration, release: 0.10)
        )
    }

    private static func resampleEnergy(_ magnitude: [Float], from frameRate: Double, duration: TimeInterval, release: Double) -> [Float] {
        guard !magnitude.isEmpty, frameRate > 0 else { return [] }

        // 95パーセンタイルで正規化して、曲ごとの音量差を吸収する
        let peak = max(1e-6, percentile(magnitude, 0.95))
        let outCount = max(1, Int(duration * energyFrameRate) + 1)
        var out = [Float](repeating: 0, count: outCount)

        let decay = Float(exp(-1.0 / (release * energyFrameRate)))
        var envelope: Float = 0

        for j in 0..<outCount {
            let srcPos = Double(j) / energyFrameRate * frameRate
            let i0 = Int(srcPos)
            let value: Float
            if i0 >= magnitude.count - 1 {
                value = magnitude[magnitude.count - 1]
            } else {
                let frac = Float(srcPos - Double(i0))
                value = magnitude[i0] * (1 - frac) + magnitude[i0 + 1] * frac
            }
            let normalized = min(1.4, value / peak)
            envelope = normalized > envelope ? normalized : envelope * decay + normalized * (1 - decay)
            out[j] = min(1, envelope)
        }
        return out
    }

    private static func buildBarEnergy(beats: [GrooveBeat], curves: EnergyCurves, duration: TimeInterval) -> [Float] {
        guard let maxBar = beats.map(\.bar).max(), maxBar >= 0 else { return [] }
        var sums = [Float](repeating: 0, count: maxBar + 1)
        var counts = [Float](repeating: 0, count: maxBar + 1)

        for beat in beats where beat.bar >= 0 {
            let idx = Int(beat.time * energyFrameRate)
            guard idx >= 0, idx < curves.low.count else { continue }
            let e = curves.low[idx] * 0.5 + curves.mid[idx] * 0.3 + curves.high[idx] * 0.2
            sums[beat.bar] += e
            counts[beat.bar] += 1
        }

        var out = [Float](repeating: 0.5, count: maxBar + 1)
        for i in 0...maxBar where counts[i] > 0 {
            out[i] = min(1, sums[i] / counts[i])
        }
        return out
    }
}

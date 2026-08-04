import AVFoundation

struct BeatDetectionResult {
    let beatTimestamps: [TimeInterval]
    let estimatedBPM: Double?
}

enum BeatDetectorError: Error {
    case bufferAllocationFailed
    case noChannelData
    case fileTooLarge
}

/// エネルギーピーク検出による簡易拍検出（本格的なBPM解析ライブラリは使わず、割り切った精度で実装）
enum BeatDetector {
    private static let windowSize = 1024
    /// 直近何ウィンドウ分の平均エネルギーと比較するか（44.1kHzで約1秒相当）
    private static let historyWindowCount = 43
    /// 瞬間エネルギーが直近平均のこの倍率を超えたら拍とみなす
    private static let sensitivity: Float = 1.3
    /// 拍と拍の最小間隔（連続検出を防ぐ。300BPM相当が検出上限になる）
    private static let minBeatInterval: TimeInterval = 0.2

    static func detectBeats(fileURL: URL) throws -> BeatDetectionResult {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat

        guard file.length > 0, file.length <= Int64(UInt32.max) else {
            throw BeatDetectorError.fileTooLarge
        }
        let frameCount = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw BeatDetectorError.bufferAllocationFailed
        }
        try file.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw BeatDetectorError.noChannelData
        }

        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        let frameLength = Int(buffer.frameLength)

        // 全チャンネルを平均してモノラル化
        var samples = [Float](repeating: 0, count: frameLength)
        for channel in 0..<channelCount {
            let data = channelData[channel]
            for i in 0..<frameLength {
                samples[i] += data[i]
            }
        }
        if channelCount > 1 {
            let inv = 1.0 / Float(channelCount)
            for i in 0..<frameLength {
                samples[i] *= inv
            }
        }

        let windowCount = frameLength / windowSize
        guard windowCount > 0 else {
            return BeatDetectionResult(beatTimestamps: [], estimatedBPM: nil)
        }

        // ウィンドウごとのエネルギー（二乗平均）を計算
        var windowEnergies = [Float](repeating: 0, count: windowCount)
        for w in 0..<windowCount {
            var sum: Float = 0
            let start = w * windowSize
            for i in start..<(start + windowSize) {
                sum += samples[i] * samples[i]
            }
            windowEnergies[w] = sum / Float(windowSize)
        }

        var beatTimestamps: [TimeInterval] = []
        var lastBeatTime: TimeInterval = -.greatestFiniteMagnitude

        for w in 0..<windowCount {
            let historyStart = max(0, w - historyWindowCount)
            guard historyStart < w else { continue }
            let history = windowEnergies[historyStart..<w]

            let average = history.reduce(0, +) / Float(history.count)
            guard average > 0 else { continue }

            if windowEnergies[w] > average * sensitivity {
                let time = TimeInterval(w * windowSize) / sampleRate
                if time - lastBeatTime >= minBeatInterval {
                    beatTimestamps.append(time)
                    lastBeatTime = time
                }
            }
        }

        return BeatDetectionResult(
            beatTimestamps: beatTimestamps,
            estimatedBPM: estimateBPM(from: beatTimestamps)
        )
    }

    private static func estimateBPM(from timestamps: [TimeInterval]) -> Double? {
        guard timestamps.count > 1 else { return nil }
        let intervals = zip(timestamps, timestamps.dropFirst()).map { $1 - $0 }
        guard !intervals.isEmpty else { return nil }
        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
        guard averageInterval > 0 else { return nil }
        return 60.0 / averageInterval
    }
}

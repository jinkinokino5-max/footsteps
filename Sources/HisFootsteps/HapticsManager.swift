import CoreHaptics

final class HapticsManager {
    static let shared = HapticsManager()

    private var engine: CHHapticEngine?
    private var beatPatternPlayer: CHHapticPatternPlayer?

    var isSupported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private init() {
        prepareEngine()
    }

    private func prepareEngine() {
        guard isSupported else { return }
        do {
            engine = try CHHapticEngine()
            engine?.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            try engine?.start()
        } catch {
            print("Haptic engine failed to start: \(error)")
        }
    }

    /// Phase 0/1の疎通確認用：単発のインパクト振動を鳴らす
    func playTestTap() {
        guard let engine else { return }

        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to play haptic: \(error)")
        }
    }

    /// Phase 4：拍タイムスタンプ配列に合わせた振動パターンを1つのCHHapticPatternとして事前スケジューリングし再生する。
    /// 音楽側の再生開始呼び出しと極力近いタイミングで呼ぶことで、簡易的な同期を成立させる（フレーム精度の同期は狙わない）。
    func playBeatPattern(beatTimestamps: [TimeInterval]) {
        guard let engine, isSupported, !beatTimestamps.isEmpty else { return }

        stopBeatPattern()

        let events = beatTimestamps.map { timestamp -> CHHapticEvent in
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            return CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: timestamp)
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            beatPatternPlayer = player
        } catch {
            print("Failed to play beat pattern: \(error)")
        }
    }

    func stopBeatPattern() {
        try? beatPatternPlayer?.stop(atTime: CHHapticTimeImmediate)
        beatPatternPlayer = nil
    }
}

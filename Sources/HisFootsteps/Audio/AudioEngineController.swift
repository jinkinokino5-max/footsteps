import AVFoundation
import Combine
import Foundation

/// 楽曲の再生と、「今、曲の何秒目か」を高精度で返す時計。
///
/// ハプティクスも足跡もビジュアルも、すべてこの時計を唯一の基準にして動く。
/// `Date()` ではなくオーディオのレンダリング時刻を使うことで、長い曲でもズレが蓄積しない。
final class AudioEngineController: ObservableObject {
    static let shared = AudioEngineController()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 2)

    private var file: AVAudioFile?
    private var lastKnownTime: TimeInterval = 0
    private var completionHandler: (() -> Void)?

    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?

    private(set) var duration: TimeInterval = 0

    /// 低域を持ち上げて、スピーカーでもキックの体感を出す
    var punchEQEnabled: Bool = true {
        didSet { applyEQ() }
    }

    private init() {
        engine.attach(player)
        engine.attach(eq)
        configureEQBands()
        applyEQ()
        registerNotifications()
    }

    // MARK: - 時計

    /// 曲頭からの再生位置（秒）。再生していないときは最後に分かっていた位置を返す。
    var currentTime: TimeInterval {
        guard player.isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else {
            return lastKnownTime
        }
        let time = Double(playerTime.sampleTime) / playerTime.sampleRate
        lastKnownTime = max(0, time)
        return lastKnownTime
    }

    // MARK: - 読み込み / 再生

    @discardableResult
    func load(song: Song) -> Bool {
        stop()
        do {
            let audioFile = try AVAudioFile(forReading: song.url)
            let format = audioFile.processingFormat
            guard format.sampleRate > 0 else {
                errorMessage = "曲のフォーマットを解釈できませんでした"
                return false
            }
            engine.connect(player, to: eq, format: format)
            engine.connect(eq, to: engine.mainMixerNode, format: format)
            engine.prepare()

            file = audioFile
            duration = Double(audioFile.length) / format.sampleRate
            lastKnownTime = 0
            errorMessage = nil
            return true
        } catch {
            file = nil
            duration = 0
            errorMessage = "曲の読み込みに失敗しました: \(error.localizedDescription)"
            return false
        }
    }

    func play(onFinish: (() -> Void)? = nil) {
        guard let file else { return }
        do {
            try activateSession()
            if !engine.isRunning { try engine.start() }

            player.stop()
            lastKnownTime = 0
            completionHandler = onFinish

            player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.isPlaying else { return }
                    self.isPlaying = false
                    let handler = self.completionHandler
                    self.completionHandler = nil
                    handler?()
                }
            }
            player.play()
            isPlaying = true
        } catch {
            errorMessage = "再生に失敗しました: \(error.localizedDescription)"
        }
    }

    func stop() {
        completionHandler = nil
        if player.isPlaying { player.stop() }
        isPlaying = false
        lastKnownTime = 0
    }

    /// 曲を止めずにエンジンだけ落としたい場面（バックグラウンド遷移など）
    func shutdown() {
        stop()
        if engine.isRunning { engine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - セッション / EQ

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
    }

    private func configureEQBands() {
        guard eq.bands.count >= 2 else { return }
        let low = eq.bands[0]
        low.filterType = .lowShelf
        low.frequency = 95
        low.gain = 0
        low.bypass = false

        let presence = eq.bands[1]
        presence.filterType = .parametric
        presence.frequency = 3200
        presence.bandwidth = 1.2
        presence.gain = 0
        presence.bypass = false
    }

    private func applyEQ() {
        guard eq.bands.count >= 2 else { return }
        eq.bands[0].gain = punchEQEnabled ? 4.5 : 0
        eq.bands[1].gain = punchEQEnabled ? 1.8 : 0
        eq.globalGain = punchEQEnabled ? -2.0 : 0
    }

    // MARK: - 割り込み対応

    private func registerNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
    }
}

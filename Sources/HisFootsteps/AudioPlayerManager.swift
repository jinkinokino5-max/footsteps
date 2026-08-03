import AVFoundation
import MediaPlayer

/// AVAudioEngineで選択曲を再生するクラス（Phase 2疎通確認用）
final class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?

    @Published var isPlaying = false
    @Published var loadError: String?

    private init() {
        engine.attach(playerNode)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    @discardableResult
    func load(item: MPMediaItem) -> Bool {
        stop()
        audioFile = nil

        guard let assetURL = item.assetURL else {
            loadError = "この曲はローカルに保存されていないため再生できません（Apple Music DRM等）"
            return false
        }

        do {
            let file = try AVAudioFile(forReading: assetURL)
            engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)
            audioFile = file
            loadError = nil
            return true
        } catch {
            loadError = "曲の読み込みに失敗しました: \(error.localizedDescription)"
            return false
        }
    }

    func play() {
        guard let audioFile else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning {
                try engine.start()
            }

            playerNode.stop()
            playerNode.scheduleFile(audioFile, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    self?.isPlaying = false
                }
            }
            playerNode.play()
            isPlaying = true
        } catch {
            loadError = "再生に失敗しました: \(error.localizedDescription)"
        }
    }

    func stop() {
        playerNode.stop()
        isPlaying = false
    }
}

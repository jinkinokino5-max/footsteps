import AVFoundation

/// AVAudioEngineでアプリ内蔵の楽曲（BundledSong）を再生するクラス
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
    func load(song: BundledSong) -> Bool {
        stop()
        audioFile = nil

        do {
            let file = try AVAudioFile(forReading: song.url)
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

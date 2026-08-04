import Combine
import Foundation

/// 曲の解析を進捗つきで実行し、結果をキャッシュに残す係。
final class AnalysisCoordinator: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var isRunning = false
    @Published private(set) var statusText: String = ""
    @Published var errorMessage: String?

    private let queue = DispatchQueue(label: "com.hisfootsteps.analysis", qos: .userInitiated)

    func analyze(song: Song, completion: @escaping (GrooveMap) -> Void) {
        guard !isRunning else { return }

        if let cached = GrooveMapStore.load(for: song) {
            statusText = "解析済みのグルーヴを読み込みました"
            progress = 1
            completion(cached)
            return
        }

        isRunning = true
        progress = 0
        errorMessage = nil
        statusText = "波形を読み込んでいます"

        queue.async { [weak self] in
            do {
                var lastTickedStep = -1
                let map = try GrooveAnalyzer.analyze(url: song.url, songID: song.id) { value in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.progress = value
                        self.statusText = Self.stageText(for: value)
                        // 待ち時間も触覚で見せる。10%進むごとに小さく打つ。
                        let step = Int(value * 10)
                        if step > lastTickedStep {
                            lastTickedStep = step
                            HapticConductor.shared.playSample(.hat, profile: .standard)
                        }
                    }
                }
                GrooveMapStore.save(map, for: song)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isRunning = false
                    self.progress = 1
                    completion(map)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isRunning = false
                    self.errorMessage = "解析に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    private static func stageText(for progress: Double) -> String {
        switch progress {
        case ..<0.7: return "周波数帯ごとに音の立ち上がりを抽出しています"
        case ..<0.85: return "テンポと拍の位置を追跡しています"
        case ..<0.94: return "キック・スネア・ハットを聞き分けています"
        default: return "振り付けを組み立てています"
        }
    }
}

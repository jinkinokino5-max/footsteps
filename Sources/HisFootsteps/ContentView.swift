import SwiftUI

struct ContentView: View {
    @State private var lastTappedAt: Date?
    @State private var songs: [BundledSong] = []
    @State private var selectedSong: BundledSong?
    @StateObject private var player = AudioPlayerManager.shared
    @State private var isAnalyzingBeats = false
    @State private var beatResult: BeatDetectionResult?
    @State private var beatAnalysisError: String?
    @State private var footstepScheduler = BeatScheduler()
    @State private var beatBounceCounter = 0
    @State private var isLeftFoot = true

    var body: some View {
        VStack(spacing: 24) {
            Text("His Footsteps")
                .font(.title)
                .bold()

            Text("Beat Trainer - Pipeline & Haptics Test")
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(systemName: "shoeprints.fill")
                .font(.system(size: 56))
                .symbolEffect(.bounce, value: beatBounceCounter)
                .offset(x: isLeftFoot ? -40 : 40)
                .animation(.easeInOut(duration: 0.15), value: isLeftFoot)
                .frame(height: 80)

            Button("ハプティクスをテスト") {
                HapticsManager.shared.playTestTap()
                lastTappedAt = Date()
            }
            .buttonStyle(.borderedProminent)

            if !HapticsManager.shared.isSupported {
                Text("この端末はハプティクス非対応です")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if let lastTappedAt {
                Text("最終テスト: \(lastTappedAt.formatted(date: .omitted, time: .standard))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("内蔵曲")
                .font(.headline)

            if songs.isEmpty {
                Text("内蔵曲がありません\n(Resources/Musicに曲ファイルを追加してください)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 8) {
                    ForEach(songs) { song in
                        Button {
                            selectedSong = song
                            player.load(song: song)
                            beatResult = nil
                            beatAnalysisError = nil
                        } label: {
                            HStack {
                                Text(song.displayName)
                                Spacer()
                                if selectedSong?.id == song.id {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if selectedSong != nil {
                    Button(player.isPlaying ? "停止" : "再生") {
                        if player.isPlaying {
                            player.stop()
                            HapticsManager.shared.stopBeatPattern()
                            footstepScheduler.cancel()
                        } else {
                            player.play()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(player.loadError != nil)

                    Button(isAnalyzingBeats ? "解析中..." : "拍を解析") {
                        analyzeBeats()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAnalyzingBeats || player.loadError != nil)

                    if let beatResult {
                        VStack(spacing: 4) {
                            if let bpm = beatResult.estimatedBPM {
                                Text("推定BPM: \(String(format: "%.1f", bpm))")
                            }
                            Text("検出した拍の数: \(beatResult.beatTimestamps.count)")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        if !beatResult.beatTimestamps.isEmpty {
                            Button("ビートに合わせて再生") {
                                HapticsManager.shared.playBeatPattern(beatTimestamps: beatResult.beatTimestamps)
                                footstepScheduler.cancel()
                                footstepScheduler = BeatScheduler()
                                footstepScheduler.schedule(beatTimestamps: beatResult.beatTimestamps) {
                                    beatBounceCounter += 1
                                    isLeftFoot.toggle()
                                }
                                player.play()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(player.isPlaying || player.loadError != nil)
                        }
                    }

                    if let beatAnalysisError {
                        Text(beatAnalysisError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            if let loadError = player.loadError {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .onAppear {
            songs = BundledSongLibrary.loadAll()
        }
    }

    private func analyzeBeats() {
        guard let selectedSong else { return }
        isAnalyzingBeats = true
        beatResult = nil
        beatAnalysisError = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try BeatDetector.detectBeats(fileURL: selectedSong.url)
                DispatchQueue.main.async {
                    self.beatResult = result
                    self.isAnalyzingBeats = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.beatAnalysisError = "拍検出に失敗しました: \(error.localizedDescription)"
                    self.isAnalyzingBeats = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

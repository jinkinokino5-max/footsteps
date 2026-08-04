import SwiftUI

struct ContentView: View {
    @State private var lastTappedAt: Date?
    @State private var songs: [BundledSong] = []
    @State private var selectedSong: BundledSong?
    @StateObject private var player = AudioPlayerManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Text("His Footsteps")
                .font(.title)
                .bold()

            Text("Beat Trainer - Pipeline & Haptics Test")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                        } else {
                            player.play()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(player.loadError != nil)
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
}

#Preview {
    ContentView()
}

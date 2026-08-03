import MediaPlayer
import SwiftUI

struct ContentView: View {
    @State private var lastTappedAt: Date?
    @State private var showPicker = false
    @State private var selectedItem: MPMediaItem?
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

            Button("曲を選択") {
                showPicker = true
            }
            .buttonStyle(.bordered)

            if let selectedItem {
                VStack(spacing: 4) {
                    Text(selectedItem.title ?? "不明な曲")
                        .font(.headline)
                    if let artist = selectedItem.artist {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

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

            if let loadError = player.loadError {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .sheet(isPresented: $showPicker) {
            MediaPicker(
                onPick: { item in
                    showPicker = false
                    selectedItem = item
                    player.load(item: item)
                },
                onCancel: {
                    showPicker = false
                }
            )
        }
    }
}

#Preview {
    ContentView()
}

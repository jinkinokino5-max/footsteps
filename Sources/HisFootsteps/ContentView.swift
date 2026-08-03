import SwiftUI

struct ContentView: View {
    @State private var lastTappedAt: Date?

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
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

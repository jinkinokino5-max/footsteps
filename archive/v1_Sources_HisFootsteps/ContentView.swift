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

    @StateObject private var followTracker = FollowTracker()
    @State private var currentBeatIndex = 0
    @State private var touchLocation: CGPoint?
    @State private var stageSize: CGSize = .zero
    @State private var isTrackingRun = false
    @State private var followSummary: FollowSummary?
    @State private var trackingToken = UUID()
    @State private var selectedMode: AppMode = .stepFocused
    @State private var playbackStartDate: Date?
    @State private var touchHistory: [(time: TimeInterval, location: CGPoint)] = []

    var body: some View {
        VStack(spacing: 24) {
            headerSection

            modePicker

            followStage
                .allowsHitTesting(selectedMode.isFollowJudgeEnabled)

            hapticsTestSection

            Divider()

            songLibrarySection
        }
        .padding()
        .onAppear {
            songs = BundledSongLibrary.loadAll()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("His Footsteps")
                .font(.title)
                .bold()

            Text("Beat Trainer - Pipeline & Haptics Test")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modePicker: some View {
        Picker("モード", selection: $selectedMode) {
            ForEach(AppMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var hapticsTestSection: some View {
        VStack(spacing: 8) {
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
    }

    private var songLibrarySection: some View {
        VStack(spacing: 8) {
            Text("内蔵曲")
                .font(.headline)

            if songs.isEmpty {
                Text("内蔵曲がありません\n(Resources/Musicに曲ファイルを追加してください)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                songListView

                if selectedSong != nil {
                    selectedSongControls
                }
            }

            if let loadError = player.loadError {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var songListView: some View {
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
    }

    private var selectedSongControls: some View {
        VStack(spacing: 8) {
            Button(player.isPlaying ? "停止" : "再生") {
                if player.isPlaying {
                    stopBeatSyncedPlayback()
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

            beatResultView

            if let beatAnalysisError {
                Text(beatAnalysisError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if let followSummary {
                followSummaryView(followSummary)
            }
        }
    }

    @ViewBuilder
    private var beatResultView: some View {
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
                    startBeatSyncedPlayback(beatTimestamps: beatResult.beatTimestamps)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(player.isPlaying || player.loadError != nil)
            }
        }
    }

    private func followSummaryView(_ summary: FollowSummary) -> some View {
        VStack(spacing: 4) {
            Text("追従精度: \(String(format: "%.1f", summary.accuracyPercent))%")
                .font(.headline)
            Text(summary.comment)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let timingComment = summary.timingComment {
                Text(timingComment)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// 足跡の目標軌跡と、指の追従位置を表示・記録するステージ（Phase6：指のなぞり追従判定）
    private var followStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)

            footstepMarker

            if let touchLocation, selectedMode.isFollowJudgeEnabled {
                Circle()
                    .stroke(Color.blue, lineWidth: 3)
                    .frame(width: 36, height: 36)
                    .position(touchLocation)
            }
        }
        .frame(height: 220)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { stageSize = proxy.size }
                    .onChange(of: proxy.size) { _, newSize in stageSize = newSize }
            }
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    touchLocation = value.location
                    if let playbackStartDate {
                        let elapsed = Date().timeIntervalSince(playbackStartDate)
                        touchHistory.append((time: elapsed, location: value.location))
                        touchHistory.removeAll { elapsed - $0.time > 1.5 }
                    }
                }
                .onEnded { _ in touchLocation = nil }
        )
    }

    private var footstepMarker: some View {
        let target = FootstepPath.position(forBeatIndex: currentBeatIndex, in: stageSize)
        return Image(systemName: "shoeprints.fill")
            .font(.system(size: 40))
            .foregroundStyle(.orange)
            .symbolEffect(.bounce, value: beatBounceCounter)
            .position(target)
            .animation(.easeInOut(duration: 0.15), value: currentBeatIndex)
    }

    private func startBeatSyncedPlayback(beatTimestamps: [TimeInterval]) {
        let token = UUID()
        trackingToken = token

        currentBeatIndex = 0
        followSummary = nil
        followTracker.reset()
        touchHistory = []
        playbackStartDate = Date()
        isTrackingRun = selectedMode.isFollowJudgeEnabled

        HapticsManager.shared.playBeatPattern(beatTimestamps: beatTimestamps, intensity: selectedMode.hapticIntensity)
        footstepScheduler.cancel()
        footstepScheduler = BeatScheduler()
        footstepScheduler.schedule(beatTimestamps: beatTimestamps) {
            if selectedMode.isFollowJudgeEnabled {
                let target = FootstepPath.position(forBeatIndex: currentBeatIndex, in: stageSize)
                let maxAcceptableDistance = max(stageSize.width, stageSize.height) * 0.25
                followTracker.record(
                    beatIndex: currentBeatIndex,
                    beatTime: beatTimestamps[currentBeatIndex],
                    targetPosition: target,
                    touchHistory: touchHistory,
                    maxAcceptableDistance: maxAcceptableDistance
                )
            }
            currentBeatIndex += 1
            beatBounceCounter += 1
        }
        player.play()

        if let lastBeat = beatTimestamps.last {
            DispatchQueue.main.asyncAfter(deadline: .now() + lastBeat + 0.6) {
                guard trackingToken == token else { return }
                finishTracking()
            }
        }
    }

    private func stopBeatSyncedPlayback() {
        player.stop()
        HapticsManager.shared.stopBeatPattern()
        footstepScheduler.cancel()
        finishTracking()
    }

    private func finishTracking() {
        guard isTrackingRun else { return }
        isTrackingRun = false
        let maxAcceptableDistance = max(stageSize.width, stageSize.height) * 0.25
        followSummary = followTracker.summary(maxAcceptableDistance: maxAcceptableDistance)
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

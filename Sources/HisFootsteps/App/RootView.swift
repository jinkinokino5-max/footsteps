import SwiftUI

/// 画面遷移の親。オンボーディング → 選曲 → 本番 → 結果 の一本道。
struct RootView: View {
    private enum Screen {
        case onboarding
        case select
        case perform
        case result
    }

    @StateObject private var settings = AppSettings()
    @StateObject private var analysis = AnalysisCoordinator()

    @State private var screen: Screen = .onboarding
    @State private var songs: [Song] = []
    @State private var engine: PerformanceEngine?
    @State private var result: PerformanceResult?
    @State private var currentSong: Song?
    @State private var currentMap: GrooveMap?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: bootstrap)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active, screen == .perform {
                engine?.finish()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .onboarding:
            OnboardingView(settings: settings) {
                go(to: .select)
            }
            .transition(.opacity)

        case .select:
            SongSelectView(
                settings: settings,
                analysis: analysis,
                songs: songs,
                onLibraryChanged: reloadLibrary,
                onStart: startPerformance
            )
            .transition(.opacity)

        case .perform:
            if let engine {
                PerformanceView(engine: engine) {
                    engine.finish()
                }
                .transition(.opacity)
            } else {
                Color.black
            }

        case .result:
            if let result {
                ResultView(
                    result: result,
                    onRetry: retry,
                    onBackToSelect: { go(to: .select) }
                )
                .transition(.opacity)
            } else {
                Color.black
            }
        }
    }

    // MARK: - 遷移

    private func bootstrap() {
        guard songs.isEmpty else { return }
        GrooveMapStore.purgeOldVersions()
        songs = SongLibrary.loadAll()
        HapticConductor.shared.restartEngineIfNeeded()
        if settings.hasOnboarded {
            screen = .select
        }
    }

    private func reloadLibrary() {
        songs = SongLibrary.loadAll()
    }

    private func go(to next: Screen) {
        if next != .perform {
            engine?.stop()
            engine = nil
        }
        withAnimation(.easeInOut(duration: 0.28)) {
            screen = next
        }
    }

    private func startPerformance(song: Song, map: GrooveMap) {
        currentSong = song
        currentMap = map
        launchEngine(song: song, map: map)
    }

    private func retry() {
        guard let song = currentSong, let map = currentMap else {
            go(to: .select)
            return
        }
        launchEngine(song: song, map: map)
    }

    private func launchEngine(song: Song, map: GrooveMap) {
        engine?.stop()
        let newEngine = PerformanceEngine(
            song: song,
            map: map,
            mode: settings.mode,
            profile: settings.hapticProfile
        )
        newEngine.onFinished = { summary in
            result = summary
            withAnimation(.easeInOut(duration: 0.4)) {
                screen = .result
            }
        }
        engine = newEngine
        withAnimation(.easeInOut(duration: 0.28)) {
            screen = .perform
        }
        newEngine.start()
    }
}

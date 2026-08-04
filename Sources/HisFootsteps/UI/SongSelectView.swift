import Combine
import SwiftUI

/// 曲・モード・振動強度を選ぶ「楽屋」。
struct SongSelectView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var analysis: AnalysisCoordinator
    let songs: [Song]
    var onStart: (Song, GrooveMap) -> Void

    @State private var selected: Song?
    @State private var showsCalibration = false

    var body: some View {
        ZStack {
            Theme.stageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    modeSection
                    powerSection
                    songSection
                    calibrationSection
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
            }

            VStack {
                Spacer()
                startBar
            }

            if analysis.isRunning {
                AnalysisOverlay(analysis: analysis)
            }
        }
        .onAppear {
            if selected == nil { selected = songs.first }
        }
    }

    // MARK: - パーツ

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SELECT THE GROOVE")
                .font(Theme.label(11))
                .tracking(4)
                .foregroundStyle(Theme.textSecondary)
            Text("His Footsteps")
                .font(Theme.display(32))
                .foregroundStyle(Theme.goldSheen)
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("MODE")
            HStack(spacing: 8) {
                ForEach(PerformanceMode.allCases) { mode in
                    modeCard(mode)
                }
            }
        }
    }

    private func modeCard(_ mode: PerformanceMode) -> some View {
        let isSelected = settings.mode == mode
        return Button {
            settings.mode = mode
            HapticConductor.shared.playSample(.hat, profile: settings.hapticProfile)
        } label: {
            VStack(spacing: 5) {
                Text(mode.rawValue)
                    .font(Theme.label(13))
                    .tracking(2)
                Text(mode.japaneseName)
                    .font(Theme.label(11))
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(isSelected ? Color.black : Theme.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AnyShapeStyle(Theme.goldSheen) : AnyShapeStyle(Color.white.opacity(0.05)))
            )
        }
        .buttonStyle(.plain)
    }

    private var powerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("HAPTIC POWER")
                Spacer()
                Button("試す") {
                    HapticConductor.shared.playSample(.kick, profile: settings.hapticProfile)
                }
                .font(Theme.label(12))
                .foregroundStyle(Theme.neon)
            }

            HStack(spacing: 8) {
                ForEach(HapticProfile.allCases) { profile in
                    profileChip(profile)
                }
            }

            Text(settings.hapticProfile.description)
                .font(Theme.label(11))
                .foregroundStyle(Theme.textSecondary)

            if HapticConductor.shared.isLowPowerModeEnabled {
                Text("低電力モードがオンのあいだ、iPhoneは振動しません。")
                    .font(Theme.label(11))
                    .foregroundStyle(Theme.ember)
            }
        }
    }

    private func profileChip(_ profile: HapticProfile) -> some View {
        let isSelected = settings.hapticProfile == profile
        return Button {
            settings.hapticProfile = profile
            HapticConductor.shared.playSample(.kick, profile: profile)
        } label: {
            Text(profile.rawValue)
                .font(Theme.label(13))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(isSelected ? Color.black : Theme.textSecondary)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? AnyShapeStyle(Theme.goldSheen) : AnyShapeStyle(Color.white.opacity(0.05)))
                )
        }
        .buttonStyle(.plain)
    }

    private var songSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("TRACK")
            if songs.isEmpty {
                Text("内蔵曲がありません。Resources/Music に曲ファイルを置いてビルドしてください。")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(songs) { song in
                    songRow(song)
                }
            }
        }
    }

    private func songRow(_ song: Song) -> some View {
        let isSelected = selected?.id == song.id
        return Button {
            selected = song
            HapticConductor.shared.playSample(.snare, profile: settings.hapticProfile)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? AnyShapeStyle(Theme.goldSheen) : AnyShapeStyle(Color.white.opacity(0.07)))
                        .frame(width: 44, height: 44)
                    Image(systemName: isSelected ? "waveform" : "music.note")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isSelected ? Color.black : Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(Theme.label(15))
                        .foregroundStyle(Theme.textPrimary)
                    Text(cachedLabel(for: song))
                        .font(Theme.label(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(isSelected ? 0.09 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Theme.gold.alpha(0.6) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func cachedLabel(for song: Song) -> String {
        if let map = GrooveMapStore.load(for: song) {
            return "\(Int(map.bpm.rounded())) BPM ・ 解析済み"
        }
        return "未解析（初回のみ数秒かかります）"
    }

    private var calibrationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsCalibration.toggle() }
            } label: {
                HStack {
                    sectionTitle("FINE TUNE")
                    Spacer()
                    Image(systemName: showsCalibration ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if showsCalibration {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("振動のタイミング　\(Int(settings.hapticLeadMs)) ms")
                            .font(Theme.label(12))
                            .foregroundStyle(Theme.textPrimary)
                        Slider(value: $settings.hapticLeadMs, in: -60...60, step: 5)
                            .tint(Theme.gold)
                        Text("振動が遅れて感じるときは右へ。")
                            .font(Theme.label(10))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Toggle(isOn: $settings.punchEQ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("低音ブースト")
                                .font(Theme.label(12))
                                .foregroundStyle(Theme.textPrimary)
                            Text("スピーカー再生でもキックの体感を厚くする")
                                .font(Theme.label(10))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.gold)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
            }
        }
    }

    private var startBar: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, Color.black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .frame(height: 28)
            Button {
                startSelected()
            } label: {
                Text(selected == nil ? "曲を選んでください" : "踊る")
                    .font(Theme.label(18))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(RoundedRectangle(cornerRadius: 15).fill(Theme.goldSheen))
                    .opacity(selected == nil ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(selected == nil || analysis.isRunning)
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
            .background(Color.black.opacity(0.85))
        }
    }

    private func startSelected() {
        guard let song = selected else { return }
        analysis.analyze(song: song) { map in
            onStart(song, map)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.label(10))
            .tracking(3)
            .foregroundStyle(Theme.textSecondary)
    }
}

/// 解析中の演出。棒立ちの「解析中...」ではなく、波形が組み上がる様子を見せる。
struct AnalysisOverlay: View {
    @ObservedObject var analysis: AnalysisCoordinator
    @State private var phase: Double = 0
    private let ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: 22) {
                Canvas { context, size in
                    drawWave(context: &context, size: size)
                }
                .frame(height: 120)
                .padding(.horizontal, 30)

                VStack(spacing: 8) {
                    Text("\(Int(analysis.progress * 100))%")
                        .font(Theme.mono(30))
                        .foregroundStyle(Theme.gold)
                    Text(analysis.statusText)
                        .font(Theme.label(12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if let error = analysis.errorMessage {
                    Text(error)
                        .font(Theme.label(12))
                        .foregroundStyle(Theme.ember)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
            }
        }
        .onReceive(ticker) { _ in phase += 0.09 }
    }

    private func drawWave(context: inout GraphicsContext, size: CGSize) {
        let bars = 46
        let width = size.width / CGFloat(bars)
        for i in 0..<bars {
            let ratio = Double(i) / Double(bars)
            let active = ratio <= analysis.progress
            let wobble = sin(phase + Double(i) * 0.45) * 0.5 + 0.5
            let h = size.height * CGFloat(0.12 + wobble * (active ? 0.85 : 0.16))
            let rect = CGRect(
                x: CGFloat(i) * width + width * 0.22,
                y: (size.height - h) / 2,
                width: width * 0.56,
                height: h
            )
            let color = active ? Theme.gold : Color.white.opacity(0.12)
            context.fill(Path(roundedRect: rect, cornerRadius: width * 0.28), with: .color(color))
        }
    }
}

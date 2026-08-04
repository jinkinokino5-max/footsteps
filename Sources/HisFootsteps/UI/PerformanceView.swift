import SwiftUI

/// 本番のステージ。指を置いて、光る足跡を追う。
struct PerformanceView: View {
    @ObservedObject var engine: PerformanceEngine
    var onExit: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                StageCanvas(engine: engine)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(in: proxy.size))
                    .allowsHitTesting(engine.mode.judgesFollow)

                hud
                    .allowsHitTesting(false)

                stopButtonLayer

                if engine.phase == .countIn {
                    countInOverlay
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                engine.updateTouch(value.location, in: size)
            }
            .onEnded { _ in
                engine.updateTouch(nil, in: size)
            }
    }

    // MARK: - HUD

    private var hud: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 54)
        .padding(.bottom, 34)
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(engine.song.title)
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(Int(engine.map.bpm.rounded())) BPM ・ \(engine.mode.japaneseName)")
                    .font(Theme.label(10))
                    .tracking(1)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
    }

    /// 停止ボタンだけは指の操作を受け取る。HUD全体を当たり判定にすると
    /// 画面をなぞる指がHUDに吸われてステージに届かなくなる。
    private var stopButtonLayer: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    engine.finish()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 54)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if engine.mode.judgesFollow {
                comboRow
            }
            progressBar
            hintRow
        }
    }

    private var comboRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(engine.combo)")
                    .font(Theme.mono(engine.combo >= 10 ? 34 : 26))
                    .foregroundStyle(engine.combo >= 10 ? Theme.gold : Theme.textPrimary)
                Text(engine.heat >= 1 ? "FEVER" : "COMBO")
                    .font(Theme.label(9))
                    .tracking(2)
                    .foregroundStyle(engine.heat >= 1 ? Theme.ember : Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(engine.score)")
                    .font(Theme.mono(22))
                    .foregroundStyle(Theme.textPrimary)
                Text("SCORE")
                    .font(Theme.label(9))
                    .tracking(2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var playbackRatio: CGFloat {
        guard engine.map.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, engine.audioTime / engine.map.duration)))
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(Theme.goldSheen)
                    .frame(width: proxy.size.width * playbackRatio)
            }
        }
        .frame(height: 3)
    }

    private var hintRow: some View {
        HStack {
            Text(engine.mode.judgesFollow ? "指を置いたまま、光る足跡を追う" : "両足のステップを、ただ浴びる")
                .font(Theme.label(10))
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
            Spacer()
            Text("BAR \(max(0, engine.currentBar) + 1)")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
        }
    }

    // MARK: - カウントイン

    private var countInOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(engine.countInLabel)
                    .font(Theme.display(96))
                    .foregroundStyle(Theme.goldSheen)
                    .id(engine.countInLabel)
                    .transition(.scale.combined(with: .opacity))
                Text("指を画面に置いて")
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .animation(.easeOut(duration: 0.12), value: engine.countInLabel)
    }
}

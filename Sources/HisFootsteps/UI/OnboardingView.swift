import Combine
import SwiftUI

/// 起動直後。真っ暗な劇場で、まず「彼の鼓動」を手のひらに置く。
struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    var onStart: () -> Void

    @State private var pulse: Bool = false
    @State private var beatCount: Int = 0
    private let heartbeat = Timer.publish(every: 1.15, on: .main, in: .common).autoconnect()

    private var haptics: HapticConductor { HapticConductor.shared }

    var body: some View {
        ZStack {
            Theme.stageBackground.ignoresSafeArea()
            glow

            VStack(spacing: 0) {
                Spacer(minLength: 24)
                titleBlock
                Spacer(minLength: 18)
                pulseCircle
                Spacer(minLength: 18)
                instruction
                warnings
                Spacer(minLength: 20)
                startButton
                Spacer(minLength: 14)
            }
            .padding(.horizontal, 28)
        }
        .onReceive(heartbeat) { _ in
            beatCount += 1
            withAnimation(.easeOut(duration: 0.16)) { pulse = true }
            withAnimation(.easeIn(duration: 0.55).delay(0.16)) { pulse = false }
            haptics.playHeartbeat(profile: settings.hapticProfile)
        }
    }

    private var glow: some View {
        RadialGradient(
            colors: [Theme.gold.alpha(0.16), Theme.gold.alpha(0.03), .clear],
            center: .center,
            startRadius: 4,
            endRadius: 320
        )
        .ignoresSafeArea()
        .blendMode(.plusLighter)
    }

    private var titleBlock: some View {
        VStack(spacing: -6) {
            Text("HIS")
                .font(Theme.display(46))
                .foregroundStyle(Theme.goldSheen)
            Text("FOOTSTEPS")
                .font(Theme.display(40))
                .foregroundStyle(Theme.goldSheen)
            Text("BEAT  TRAINER")
                .font(Theme.label(11))
                .tracking(6)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 10)
        }
    }

    private var pulseCircle: some View {
        ZStack {
            Circle()
                .stroke(Theme.gold.alpha(0.35), lineWidth: 1)
                .frame(width: pulse ? 210 : 150, height: pulse ? 210 : 150)
                .opacity(pulse ? 0 : 0.9)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.spotWarm.alpha(pulse ? 0.55 : 0.18), Theme.gold.alpha(0.05), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: 110
                    )
                )
                .frame(width: 220, height: 220)
                .blendMode(.plusLighter)

            Circle()
                .stroke(Theme.gold.alpha(0.8), lineWidth: 2)
                .frame(width: pulse ? 132 : 118, height: pulse ? 132 : 118)

            VStack(spacing: 4) {
                Text("\(beatCount % 4 + 1)")
                    .font(Theme.mono(30))
                    .foregroundStyle(Theme.spotWarm)
                Text("触れて確かめる")
                    .font(Theme.label(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(height: 224)
        .contentShape(Circle())
        .onTapGesture {
            haptics.playSample(.accent, profile: settings.hapticProfile)
        }
    }

    private var instruction: some View {
        VStack(spacing: 10) {
            Text("iPhoneを机に平置きしてください。")
                .font(Theme.label(16))
                .foregroundStyle(Theme.textPrimary)
            Text("画面に指を置いたまま、光る足跡を追う。\nビートは、指先から入ってくる。")
                .font(Theme.label(13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }

    @ViewBuilder
    private var warnings: some View {
        VStack(spacing: 6) {
            if !haptics.isSupported {
                warningRow("この端末はTaptic Engine非対応です。振動なしで体験します。", critical: true)
            }
            if haptics.isLowPowerModeEnabled {
                warningRow("低電力モードがオンです。iPhoneの振動が止まります。設定＞バッテリーでオフにしてください。", critical: true)
            }
        }
        .padding(.top, 14)
    }

    private func warningRow(_ text: String, critical: Bool) -> some View {
        Text(text)
            .font(Theme.label(11))
            .foregroundStyle(critical ? Theme.ember : Theme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.ember.alpha(0.10))
            )
    }

    private var startButton: some View {
        Button {
            settings.hasOnboarded = true
            haptics.playSample(.accent, profile: settings.hapticProfile)
            onStart()
        } label: {
            Text("ステージへ")
                .font(Theme.label(17))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.goldSheen)
                )
        }
        .buttonStyle(.plain)
    }
}

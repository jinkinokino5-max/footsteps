import SwiftUI

/// 幕が下りたあと。数字ではなく「次に何を直すか」を渡す。
struct ResultView: View {
    let result: PerformanceResult
    var onRetry: () -> Void
    var onBackToSelect: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Theme.stageBackground.ignoresSafeArea()
            RadialGradient(
                colors: [Theme.gold.alpha(0.15), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 460
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)

            ScrollView {
                VStack(spacing: 22) {
                    rankBlock
                    headline
                    statGrid
                    judgementBreakdown
                    adviceBlock
                    buttons
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 24)
                .padding(.top, 44)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { appeared = true }
            HapticConductor.shared.playSample(.accent, profile: .brutal)
        }
    }

    private var rankBlock: some View {
        VStack(spacing: 2) {
            Text("RANK")
                .font(Theme.label(10))
                .tracking(5)
                .foregroundStyle(Theme.textSecondary)
            Text(result.rank)
                .font(Theme.display(88))
                .foregroundStyle(Theme.goldSheen)
                .scaleEffect(appeared ? 1 : 0.7)
                .opacity(appeared ? 1 : 0)
            Text(result.songTitle)
                .font(Theme.label(13))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var headline: some View {
        Text(result.headline)
            .font(Theme.label(16))
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
    }

    private var statGrid: some View {
        HStack(spacing: 10) {
            statCard(title: "SCORE", value: "\(result.score)")
            statCard(title: "ACCURACY", value: String(format: "%.1f%%", result.accuracyPercent))
            statCard(title: "MAX COMBO", value: "\(result.maxCombo)")
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(Theme.label(9))
                .tracking(2)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.mono(18))
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.05)))
    }

    private var judgementBreakdown: some View {
        VStack(spacing: 8) {
            ForEach(Judgement.allCases, id: \.rawValue) { judgement in
                HStack {
                    Text(judgement.label)
                        .font(Theme.label(12))
                        .foregroundStyle(color(for: judgement))
                        .frame(width: 76, alignment: .leading)
                    barView(count: result.counts[judgement] ?? 0, total: max(1, result.totalSteps), color: color(for: judgement))
                    Text("\(result.counts[judgement] ?? 0)")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }

    private func barView(count: Int, total: Int, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(color.alpha(0.8))
                    .frame(width: proxy.size.width * CGFloat(appeared ? Double(count) / Double(total) : 0))
            }
        }
        .frame(height: 7)
        .animation(.easeOut(duration: 0.7), value: appeared)
    }

    private func color(for judgement: Judgement) -> Color {
        switch judgement {
        case .perfect: return Theme.flash
        case .great: return Theme.gold
        case .good: return Theme.neon
        case .miss: return Theme.ember
        }
    }

    private var adviceBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COACH")
                .font(Theme.label(9))
                .tracking(3)
                .foregroundStyle(Theme.textSecondary)
            Text(result.advice)
                .font(Theme.label(13))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(timingText)
                .font(Theme.label(11))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private var timingText: String {
        let ms = Int((result.timingBias * 1000).rounded())
        if ms > 8 { return "平均 \(ms)ms 遅れ" }
        if ms < -8 { return "平均 \(-ms)ms 先走り" }
        return "タイミングのズレ ほぼゼロ"
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                onRetry()
            } label: {
                Text("もう一度踊る")
                    .font(Theme.label(17))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.goldSheen))
            }
            .buttonStyle(.plain)

            Button {
                onBackToSelect()
            } label: {
                Text("曲を選び直す")
                    .font(Theme.label(15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }
}

import SwiftUI

/// アプリ全体のビジュアルトーン。
/// 真っ黒なステージに、スポットライトの琥珀色とネオンの青を差す「劇場」の配色。
enum Theme {
    // MARK: - Colors

    static let stageBlack = Color(red: 0.02, green: 0.02, blue: 0.035)
    static let deepNight = Color(red: 0.05, green: 0.05, blue: 0.09)

    /// スポットライトの光。少し暖色に振った白。
    static let spotWarm = Color(red: 1.0, green: 0.94, blue: 0.78)
    /// 足跡・アクセントのゴールド。
    static let gold = Color(red: 1.0, green: 0.80, blue: 0.35)
    static let deepGold = Color(red: 0.85, green: 0.55, blue: 0.12)
    /// 指カーソルのネオンシアン。
    static let neon = Color(red: 0.35, green: 0.92, blue: 1.0)
    /// キック時のブルームに使う赤み。
    static let ember = Color(red: 1.0, green: 0.42, blue: 0.22)
    /// PERFECT判定の白。
    static let flash = Color.white

    static let textPrimary = Color(white: 0.96)
    static let textSecondary = Color(white: 0.62)

    // MARK: - Gradients

    static var stageBackground: LinearGradient {
        LinearGradient(
            colors: [deepNight, stageBlack, Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var goldSheen: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.92, blue: 0.66), gold, deepGold],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Fonts

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
}

extension Color {
    /// 0...1のアルファを掛けた新しい色を返す簡易ヘルパー。
    func alpha(_ value: Double) -> Color {
        opacity(max(0, min(1, value)))
    }
}

import SwiftUI

/// 足跡（ダンスシューズのソール）の輪郭。
/// SFシンボルのアイコンではなく、左右で非対称な実物の形を描くことで「人が踏んだ跡」に見せる。
enum FootprintShape {

    /// 0...1の正方形に収まる右足のソール（つま先が上）
    static let unitPath: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 0.57, y: 0.015))
        // 外側（小指側）のふくらみ
        path.addCurve(
            to: CGPoint(x: 0.93, y: 0.255),
            control1: CGPoint(x: 0.79, y: 0.02),
            control2: CGPoint(x: 0.93, y: 0.115)
        )
        // 土踏まずのくびれ
        path.addCurve(
            to: CGPoint(x: 0.735, y: 0.565),
            control1: CGPoint(x: 0.93, y: 0.40),
            control2: CGPoint(x: 0.775, y: 0.465)
        )
        // かかとの外側
        path.addCurve(
            to: CGPoint(x: 0.80, y: 0.875),
            control1: CGPoint(x: 0.695, y: 0.665),
            control2: CGPoint(x: 0.815, y: 0.725)
        )
        // かかと底
        path.addCurve(
            to: CGPoint(x: 0.455, y: 0.995),
            control1: CGPoint(x: 0.79, y: 0.955),
            control2: CGPoint(x: 0.645, y: 0.995)
        )
        path.addCurve(
            to: CGPoint(x: 0.185, y: 0.855),
            control1: CGPoint(x: 0.285, y: 0.995),
            control2: CGPoint(x: 0.185, y: 0.945)
        )
        // 内側（親指側）はほぼ直線的
        path.addCurve(
            to: CGPoint(x: 0.30, y: 0.545),
            control1: CGPoint(x: 0.185, y: 0.715),
            control2: CGPoint(x: 0.325, y: 0.655)
        )
        path.addCurve(
            to: CGPoint(x: 0.245, y: 0.185),
            control1: CGPoint(x: 0.275, y: 0.435),
            control2: CGPoint(x: 0.205, y: 0.315)
        )
        path.addCurve(
            to: CGPoint(x: 0.57, y: 0.015),
            control1: CGPoint(x: 0.285, y: 0.055),
            control2: CGPoint(x: 0.425, y: 0.015)
        )
        path.closeSubpath()
        return path
    }()

    /// 指定の矩形に収めた足跡。`mirrored`で左足になる。
    static func path(in rect: CGRect, mirrored: Bool) -> Path {
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        transform = transform.scaledBy(x: rect.width, y: rect.height)
        if mirrored {
            transform = transform.translatedBy(x: 1, y: 0).scaledBy(x: -1, y: 1)
        }
        return unitPath.applying(transform)
    }

    /// ソール内部のライン（踏み面の分割）。足跡らしさを一段上げる装飾。
    static func innerPath(in rect: CGRect, mirrored: Bool) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.24, y: 0.44))
        path.addQuadCurve(to: CGPoint(x: 0.78, y: 0.40), control: CGPoint(x: 0.52, y: 0.50))
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        transform = transform.scaledBy(x: rect.width, y: rect.height)
        if mirrored {
            transform = transform.translatedBy(x: 1, y: 0).scaledBy(x: -1, y: 1)
        }
        return path.applying(transform)
    }
}

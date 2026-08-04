import SwiftUI

/// ステージ1枚を描き切るレンダラー。
///
/// ぼかしフィルタは使わず、放射グラデーションと加算合成（plusLighter）だけで発光を作る。
/// これで60fpsを守りながら、劇場のような奥行きを出す。
struct StageRenderer {
    let engine: PerformanceEngine
    let size: CGSize

    private var horizon: CGFloat { size.height * 0.26 }
    private var stageTop: CGFloat { size.height * 0.30 }

    /// 正規化座標(0...1)をステージ上のピクセル座標へ
    private func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    /// 奥ほど小さく見せるための倍率。床の遠近と足跡の大きさが噛み合って初めて
    /// 「舞台の上に立っている」ように見える。
    private func depthScale(_ normalizedY: CGFloat) -> CGFloat {
        0.62 + 0.62 * min(1, max(0, normalizedY))
    }

    func render(into context: inout GraphicsContext) {
        // 背景だけは揺らさない（揺らすと画面端に隙間が出るため）
        drawBackground(&context)

        var stage = context
        stage.translateBy(
            x: engine.shakeOffset.x * size.width,
            y: engine.shakeOffset.y * size.height
        )

        drawCrowdFlashes(&stage)
        drawFloor(&stage)
        drawBeams(&stage)
        drawSpotlight(&stage)
        drawTrailPath(&stage)
        drawFootprintMarks(&stage)
        drawPreview(&stage)
        drawCurrentFoot(&stage)
        drawFinger(&stage)
        drawParticles(&stage)
        drawFlashes(&context)
        drawPopups(&stage)
    }

    // MARK: - 背景

    private func drawBackground(_ context: inout GraphicsContext) {
        let full = Path(CGRect(origin: .zero, size: size))
        context.fill(full, with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.045, green: 0.045, blue: 0.075),
                Color(red: 0.015, green: 0.015, blue: 0.028),
                Color.black
            ]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        ))

        // 客席側のもや。低域に合わせてゆっくり明滅する。
        let haze = 0.05 + engine.lowLevel * 0.10
        radial(
            &context,
            center: CGPoint(x: size.width * 0.5, y: horizon),
            radius: size.width * 0.95,
            yScale: 0.55,
            colors: [Theme.spotWarm.alpha(haze), Theme.spotWarm.alpha(0)],
            additive: true
        )
    }

    // MARK: - 床

    private func drawFloor(_ context: inout GraphicsContext) {
        let rows = 15
        let scroll = engine.barPhase
        var layer = context
        layer.blendMode = .plusLighter

        // キックのたびに、床を手前から奥へ光の帯が走る
        let rippleAge = engine.audioTime - engine.lastKickTime
        let ripplePosition = 1.0 - rippleAge * 2.6
        let rippleAlive = rippleAge >= 0 && rippleAge < 0.42

        for i in -1..<rows {
            let u = (Double(i) + scroll) / Double(rows)
            guard u > 0 else { continue }
            let y = horizon + (size.height - horizon) * CGFloat(pow(u, 2.5))
            guard y > horizon, y < size.height + 4 else { continue }
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))

            let base = 0.045 + 0.20 * pow(u, 1.6)
            let pulse = engine.lowLevel * 0.30 * pow(u, 2.0)
            var ripple = 0.0
            if rippleAlive {
                let distance = abs(u - ripplePosition)
                if distance < 0.13 {
                    ripple = (1 - distance / 0.13) * (1 - rippleAge / 0.42) * 0.55
                }
            }
            layer.stroke(
                line,
                with: .color(Theme.gold.alpha(base + pulse + ripple)),
                lineWidth: 0.6 + CGFloat(u) * 1.4 + CGFloat(ripple) * 2.2
            )
        }

        let vanishing = CGPoint(x: size.width * 0.5, y: horizon)
        for j in -7...7 {
            let bottomX = size.width * 0.5 + CGFloat(j) * size.width * 0.175
            var line = Path()
            line.move(to: vanishing)
            line.addLine(to: CGPoint(x: bottomX, y: size.height))
            let fade = 0.05 + 0.05 * engine.lowLevel
            layer.stroke(line, with: .linearGradient(
                Gradient(colors: [Theme.gold.alpha(0), Theme.gold.alpha(fade)]),
                startPoint: vanishing,
                endPoint: CGPoint(x: bottomX, y: size.height)
            ), lineWidth: 0.8)
        }
    }

    // MARK: - 客席のフラッシュ

    /// 暗がりに散らす観客のカメラフラッシュの位置。毎フレーム作り直さないよう固定で持つ。
    private static let crowdFlashes: [(point: CGPoint, phase: Double, rate: Double)] = {
        var state: UInt64 = 0xA13F_09C4_7721_55E1
        func next() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state % 100_000) / 100_000.0
        }
        return (0..<34).map { _ in
            (
                point: CGPoint(x: 0.02 + next() * 0.96, y: 0.17 + next() * 0.11),
                phase: next() * 6.28,
                rate: 0.5 + next() * 2.2
            )
        }
    }()

    private func drawCrowdFlashes(_ context: inout GraphicsContext) {
        var layer = context
        layer.blendMode = .plusLighter
        let t = engine.audioTime
        let burst = engine.accentFlash * 0.9 + engine.snareFlash * 0.35

        for flash in StageRenderer.crowdFlashes {
            // 各点が別々の周期で瞬く。キメの瞬間だけ一斉に焚かれる。
            let twinkle = max(0, sin(t * flash.rate + flash.phase))
            let intensity = pow(twinkle, 14) + burst * pow(twinkle, 3) * 0.8
            guard intensity > 0.02 else { continue }

            let center = point(flash.point)
            let r = size.width * 0.0035 * CGFloat(1 + intensity * 2)
            layer.fill(
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                with: .color(Color.white.alpha(min(0.85, intensity)))
            )
            layer.fill(
                Path(ellipseIn: CGRect(x: center.x - r * 2.6, y: center.y - r * 2.6, width: r * 5.2, height: r * 5.2)),
                with: .color(Color.white.alpha(min(0.16, intensity * 0.2)))
            )
        }
    }

    // MARK: - 舞台照明（客席側から舐めるように走る光の帯）

    private func drawBeams(_ context: inout GraphicsContext) {
        let sweep = engine.barPhase * 2 * .pi
        var layer = context
        layer.blendMode = .plusLighter

        let sources = [
            (origin: CGPoint(x: -size.width * 0.10, y: -size.height * 0.05), phase: 0.0, color: Theme.neon),
            (origin: CGPoint(x: size.width * 1.10, y: -size.height * 0.05), phase: Double.pi, color: Theme.ember)
        ]

        for source in sources {
            let angle = sin(sweep + source.phase) * 0.42
            let reach = size.height * 1.35
            let center = CGPoint(
                x: source.origin.x + CGFloat(sin(angle + 0.6)) * reach,
                y: source.origin.y + reach
            )
            let halfWidth = size.width * 0.10
            var beam = Path()
            beam.move(to: CGPoint(x: source.origin.x - 6, y: source.origin.y))
            beam.addLine(to: CGPoint(x: center.x - halfWidth, y: center.y))
            beam.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y))
            beam.addLine(to: CGPoint(x: source.origin.x + 6, y: source.origin.y))
            beam.closeSubpath()

            let strength = 0.035 + engine.midLevel * 0.05 + engine.snareFlash * 0.05
            layer.fill(beam, with: .linearGradient(
                Gradient(colors: [source.color.alpha(strength), source.color.alpha(strength * 0.25), source.color.alpha(0)]),
                startPoint: source.origin,
                endPoint: center
            ))
        }
    }

    // MARK: - 歩いた軌跡

    private func drawTrailPath(_ context: inout GraphicsContext) {
        // 直近の数歩だけ繋ぐ。全部繋ぐと折り返しが重なって落書きのように見える。
        let all = engine.footprints
        guard all.count > 1 else { return }
        let marks = all.count > 7 ? Array(all.suffix(7)) : all

        var layer = context
        layer.blendMode = .plusLighter

        // 左右の足を直接繋ぐとジグザグの落書きになる。
        // 隣り合う足跡の中点＝重心を繋いで、身体が通った線として見せる。
        var centers: [CGPoint] = []
        for i in 0..<(marks.count - 1) {
            let a = point(marks[i].position)
            let b = point(marks[i + 1].position)
            centers.append(CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
        }
        guard centers.count > 1 else { return }

        var path = Path()
        path.move(to: centers[0])
        for i in 1..<centers.count {
            let previous = centers[i - 1]
            let current = centers[i]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: current, control: mid)
        }

        layer.stroke(path, with: .color(Theme.gold.alpha(0.06)), lineWidth: 8)
        layer.stroke(path, with: .color(Theme.gold.alpha(0.16)), lineWidth: 1.8)
    }

    // MARK: - スポットライト

    private func drawSpotlight(_ context: inout GraphicsContext) {
        let focus = point(engine.target.position)
        let intensity = 0.30 + engine.lowLevel * 0.30 + engine.kickFlash * 0.22

        // 天井から降りてくる光の柱。3枚重ねて中心を濃くする。
        var layer = context
        layer.blendMode = .plusLighter
        let apex = CGPoint(x: size.width * 0.5, y: -size.height * 0.12)
        for (index, spread) in [1.0, 0.62, 0.33].enumerated() {
            let spreadScale = CGFloat(spread)
            let halfWidth = size.width * 0.42 * spreadScale
            let apexHalf = size.width * 0.035 * spreadScale
            var cone = Path()
            cone.move(to: CGPoint(x: apex.x - apexHalf, y: apex.y))
            cone.addLine(to: CGPoint(x: focus.x - halfWidth, y: size.height * 1.05))
            cone.addLine(to: CGPoint(x: focus.x + halfWidth, y: size.height * 1.05))
            cone.addLine(to: CGPoint(x: apex.x + apexHalf, y: apex.y))
            cone.closeSubpath()
            let strength = intensity * (0.10 + Double(index) * 0.055)
            layer.fill(cone, with: .linearGradient(
                Gradient(colors: [Theme.spotWarm.alpha(strength * 1.2), Theme.spotWarm.alpha(strength * 0.25), Theme.spotWarm.alpha(0)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            ))
        }

        // 足元の光溜まり
        radial(
            &context,
            center: focus,
            radius: size.width * CGFloat(0.26 + engine.kickFlash * 0.06),
            yScale: 0.42,
            colors: [
                Theme.spotWarm.alpha(0.30 + engine.kickFlash * 0.22),
                Theme.spotWarm.alpha(0.08),
                Theme.spotWarm.alpha(0)
            ],
            additive: true
        )
    }

    // MARK: - 足跡

    private func drawFootprintMarks(_ context: inout GraphicsContext) {
        let now = engine.audioTime
        let length = size.height * 0.100

        for mark in engine.footprints {
            let age = now - mark.birth
            guard age >= -0.05, age < 4.5 else { continue }
            let fade = max(0, 1 - age / 4.5)
            let freshness = max(0, 1 - age / 0.45)
            let alpha = 0.14 + 0.6 * fade * fade + 0.35 * freshness
            guard alpha > 0.07 else { continue }

            drawSole(
                &context,
                at: point(mark.position),
                rotation: mark.rotation,
                length: length * depthScale(mark.position.y),
                foot: mark.foot,
                fillAlpha: alpha * (mark.accent ? 1.0 : 0.85),
                glow: freshness * (mark.accent ? 1.3 : 0.9),
                color: mark.accent ? Theme.spotWarm : Theme.gold
            )
        }
    }

    /// 次に踏む場所をゴーストで先出しする。ここが無いと初見では足跡に追いつけない。
    private func drawPreview(_ context: inout GraphicsContext) {
        guard !engine.previewMoves.isEmpty else { return }
        let length = size.height * 0.098
        var layer = context
        layer.blendMode = .plusLighter

        // 今いる場所から次の場所へ向かう案内線
        if let next = engine.previewMoves.first {
            let from = point(engine.target.position)
            let to = point(next.position)
            var guideline = Path()
            guideline.move(to: from)
            let control = CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - size.height * 0.035)
            guideline.addQuadCurve(to: to, control: control)
            layer.stroke(
                guideline,
                with: .color(Theme.spotWarm.alpha(0.18)),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [4, 8])
            )
        }

        for (index, move) in engine.previewMoves.enumerated() {
            let alpha = 0.34 - Double(index) * 0.10
            guard alpha > 0.02 else { continue }
            let center = point(move.position)
            let rect = footRect(at: center, length: length * depthScale(move.position.y))
            let sole = rotated(
                FootprintShape.path(in: rect, mirrored: move.foot.mirrored),
                around: center,
                degrees: move.rotation
            )
            layer.fill(sole, with: .color(Theme.spotWarm.alpha(alpha * 0.16)))
            layer.stroke(
                sole,
                with: .color(Theme.spotWarm.alpha(alpha * 0.95)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4])
            )
        }
    }

    private func drawCurrentFoot(_ context: inout GraphicsContext) {
        let state = engine.target
        let center = point(state.position)
        let length = size.height * 0.122 * CGFloat(state.scale) * depthScale(state.position.y)

        // 拍に合わせて広がるリング
        let ringPhase = engine.beatPhase
        let ringRadius = length * (0.55 + CGFloat(ringPhase) * 1.5)
        let ringAlpha = (1 - ringPhase) * (0.42 + engine.kickFlash * 0.3)
        var ringLayer = context
        ringLayer.blendMode = .plusLighter
        ringLayer.stroke(
            Path(ellipseIn: CGRect(
                x: center.x - ringRadius,
                y: center.y - ringRadius * 0.42,
                width: ringRadius * 2,
                height: ringRadius * 0.84
            )),
            with: .color(Theme.gold.alpha(ringAlpha)),
            lineWidth: 1.6 + CGFloat(engine.kickFlash) * 2.0
        )

        // 着地の閃光
        if state.landing > 0.01 {
            radial(
                &context,
                center: center,
                radius: length * (1.0 + CGFloat(state.landing) * 1.4),
                yScale: 0.5,
                colors: [Theme.flash.alpha(state.landing * 0.5), Theme.gold.alpha(state.landing * 0.18), Theme.gold.alpha(0)],
                additive: true
            )
        }

        drawSole(
            &context,
            at: center,
            rotation: state.rotation,
            length: length,
            foot: state.foot,
            fillAlpha: 1.0,
            glow: 1.4 + engine.kickFlash * 0.6 + engine.nearness * 0.5,
            color: Theme.spotWarm
        )
    }

    private func footRect(at center: CGPoint, length: CGFloat) -> CGRect {
        let width = length * 0.44
        return CGRect(x: center.x - width / 2, y: center.y - length / 2, width: width, height: length)
    }

    private func rotated(_ path: Path, around center: CGPoint, degrees: Double) -> Path {
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
        transform = transform.rotated(by: CGFloat(degrees * .pi / 180))
        transform = transform.translatedBy(x: -center.x, y: -center.y)
        return path.applying(transform)
    }

    private func drawSole(
        _ context: inout GraphicsContext,
        at center: CGPoint,
        rotation: Double,
        length: CGFloat,
        foot: Foot,
        fillAlpha: Double,
        glow: Double,
        color: Color
    ) {
        let rect = footRect(at: center, length: length)
        let sole = rotated(FootprintShape.path(in: rect, mirrored: foot.mirrored), around: center, degrees: rotation)

        if glow > 0.02 {
            radial(
                &context,
                center: center,
                radius: length * 0.95,
                yScale: 0.75,
                colors: [color.alpha(min(0.55, glow * 0.30)), color.alpha(0)],
                additive: true
            )
        }

        var layer = context
        layer.blendMode = .plusLighter
        layer.fill(sole, with: .linearGradient(
            Gradient(colors: [
                color.alpha(fillAlpha),
                Theme.gold.alpha(fillAlpha * 0.85),
                Theme.deepGold.alpha(fillAlpha * 0.55)
            ]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY),
            endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
        ))
        layer.stroke(sole, with: .color(Color.white.alpha(min(1, fillAlpha * 0.9))), lineWidth: fillAlpha > 0.9 ? 1.6 : 0.8)

        let inner = rotated(FootprintShape.innerPath(in: rect, mirrored: foot.mirrored), around: center, degrees: rotation)
        layer.stroke(inner, with: .color(Color.black.opacity(min(0.5, fillAlpha * 0.45))), lineWidth: 1.0)
    }

    // MARK: - 指

    private func drawFinger(_ context: inout GraphicsContext) {
        guard let touch = engine.touchPoint else { return }
        let center = point(touch)

        // 軌跡のコメット
        if engine.touchTrail.count > 1 {
            var layer = context
            layer.blendMode = .plusLighter
            for i in 1..<engine.touchTrail.count {
                let t = Double(i) / Double(engine.touchTrail.count)
                var seg = Path()
                seg.move(to: point(engine.touchTrail[i - 1]))
                seg.addLine(to: point(engine.touchTrail[i]))
                layer.stroke(seg, with: .color(Theme.neon.alpha(0.06 + 0.35 * t)), lineWidth: 1 + CGFloat(t) * 5)
            }
        }

        radial(
            &context,
            center: center,
            radius: size.height * 0.055,
            yScale: 1,
            colors: [Theme.neon.alpha(0.35 + engine.nearness * 0.3), Theme.neon.alpha(0)],
            additive: true
        )

        var layer = context
        layer.blendMode = .plusLighter
        let r = size.height * 0.022
        layer.stroke(
            Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
            with: .color(Theme.neon.alpha(0.9)),
            lineWidth: 2
        )

        // 足跡に近いほど、指と足を結ぶ光の糸が濃くなる
        if engine.nearness > 0.05 {
            var thread = Path()
            thread.move(to: center)
            thread.addLine(to: point(engine.target.position))
            layer.stroke(thread, with: .color(Theme.gold.alpha(engine.nearness * 0.55)), lineWidth: 1 + CGFloat(engine.nearness) * 2)
        }
    }

    // MARK: - 粒子

    private func drawParticles(_ context: inout GraphicsContext) {
        guard !engine.particles.isEmpty else { return }
        var layer = context
        layer.blendMode = .plusLighter

        for particle in engine.particles {
            let center = point(particle.position)
            let alpha = max(0, min(1, particle.life))
            let color: Color
            switch particle.tone {
            case 1: color = Theme.flash
            case 2: color = Theme.neon
            case 3: color = Theme.deepGold
            default: color = Theme.gold
            }
            let r = CGFloat(particle.size) * CGFloat(0.5 + alpha * 0.8)
            layer.fill(
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                with: .color(color.alpha(alpha * 0.9))
            )
        }
    }

    // MARK: - 閃光

    private func drawFlashes(_ context: inout GraphicsContext) {
        let full = Path(CGRect(origin: .zero, size: size))

        if engine.snareFlash > 0.02 {
            var layer = context
            layer.blendMode = .plusLighter
            let alpha = min(0.26, engine.snareFlash * 0.20)
            layer.fill(full, with: .linearGradient(
                Gradient(colors: [Theme.neon.alpha(alpha), Color.clear, Theme.neon.alpha(alpha)]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: 0)
            ))
        }

        if engine.accentFlash > 0.02 {
            var layer = context
            layer.blendMode = .plusLighter
            layer.fill(full, with: .color(Theme.flash.alpha(min(0.30, engine.accentFlash * 0.26))))
        }

        if engine.hatShimmer > 0.02 {
            var layer = context
            layer.blendMode = .plusLighter
            radial(
                &layer,
                center: CGPoint(x: size.width * 0.5, y: stageTop),
                radius: size.width * 0.8,
                yScale: 0.4,
                colors: [Theme.neon.alpha(engine.hatShimmer * 0.10), Theme.neon.alpha(0)],
                additive: true
            )
        }

        // ビネット（劇場の暗がり）
        radial(
            &context,
            center: CGPoint(x: size.width * 0.5, y: size.height * 0.55),
            radius: size.width * 1.25,
            yScale: 1.1,
            colors: [Color.black.opacity(0), Color.black.opacity(0.15), Color.black.opacity(0.72)],
            additive: false
        )
    }

    // MARK: - 判定表示

    private func drawPopups(_ context: inout GraphicsContext) {
        let now = engine.audioTime
        for popup in engine.popups {
            let age = now - popup.birth
            guard age >= 0, age < 0.75 else { continue }
            let alpha = 1 - age / 0.75
            let rise = CGFloat(age) * size.height * 0.07
            let center = point(popup.position)
            let color: Color
            switch popup.judgement {
            case .perfect: color = Theme.flash
            case .great: color = Theme.gold
            case .good: color = Theme.neon
            case .miss: color = Color(red: 0.9, green: 0.3, blue: 0.35)
            }
            let text = Text(popup.judgement.label)
                .font(Theme.label(popup.judgement == .perfect ? 22 : 17))
                .foregroundStyle(color.alpha(alpha))
            context.draw(text, at: CGPoint(x: center.x, y: center.y - size.height * 0.075 - rise), anchor: .center)
        }
    }

    // MARK: - 部品

    private func radial(
        _ context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        yScale: CGFloat,
        colors: [Color],
        additive: Bool
    ) {
        guard radius > 0.5 else { return }
        var layer = context
        if additive { layer.blendMode = .plusLighter }
        layer.translateBy(x: center.x, y: center.y)
        layer.scaleBy(x: 1, y: yScale)
        let rect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        layer.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(Gradient(colors: colors), center: .zero, startRadius: 0, endRadius: radius)
        )
    }
}

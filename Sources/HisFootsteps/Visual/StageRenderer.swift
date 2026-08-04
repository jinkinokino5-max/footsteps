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

    func render(into context: inout GraphicsContext) {
        drawBackground(&context)
        drawFloor(&context)
        drawSpotlight(&context)
        drawFootprintMarks(&context)
        drawPreview(&context)
        drawCurrentFoot(&context)
        drawFinger(&context)
        drawParticles(&context)
        drawFlashes(&context)
        drawPopups(&context)
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

        for i in 0..<rows {
            let u = (Double(i) + scroll) / Double(rows)
            let y = horizon + (size.height - horizon) * CGFloat(pow(u, 2.5))
            guard y > horizon, y < size.height + 4 else { continue }
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            let base = 0.045 + 0.20 * pow(u, 1.6)
            let pulse = engine.lowLevel * 0.30 * pow(u, 2.0)
            layer.stroke(line, with: .color(Theme.gold.alpha(base + pulse)), lineWidth: 0.6 + CGFloat(u) * 1.4)
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
            radius: size.width * CGFloat(0.34 + engine.kickFlash * 0.06),
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
        let length = size.height * 0.115

        for mark in engine.footprints {
            let age = now - mark.birth
            guard age >= -0.05, age < 4.5 else { continue }
            let fade = max(0, 1 - age / 4.5)
            let freshness = max(0, 1 - age / 0.45)
            let alpha = 0.14 + 0.6 * fade * fade + 0.35 * freshness

            drawSole(
                &context,
                at: point(mark.position),
                rotation: mark.rotation,
                length: length,
                foot: mark.foot,
                fillAlpha: alpha * (mark.accent ? 1.0 : 0.85),
                glow: freshness * (mark.accent ? 1.3 : 0.9),
                color: mark.accent ? Theme.spotWarm : Theme.gold
            )
        }
    }

    private func drawPreview(_ context: inout GraphicsContext) {
        guard !engine.previewMoves.isEmpty else { return }
        let length = size.height * 0.10
        for (index, move) in engine.previewMoves.enumerated() {
            let alpha = 0.30 - Double(index) * 0.09
            guard alpha > 0.02 else { continue }
            var layer = context
            layer.blendMode = .plusLighter
            let rect = footRect(at: point(move.position), length: length)
            var sole = FootprintShape.path(in: rect, mirrored: move.foot.mirrored)
            sole = rotated(sole, around: point(move.position), degrees: move.rotation)
            layer.stroke(sole, with: .color(Theme.neon.alpha(alpha)), lineWidth: 1.4)
        }
    }

    private func drawCurrentFoot(_ context: inout GraphicsContext) {
        let state = engine.target
        let center = point(state.position)
        let length = size.height * 0.135 * CGFloat(state.scale)

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
        layer.stroke(sole, with: .color(Theme.spotWarm.alpha(min(1, fillAlpha * 0.8))), lineWidth: 0.8)

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

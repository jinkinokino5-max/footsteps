import Combine
import CoreGraphics
import Foundation
import QuartzCore

/// 舞台に散る粒子（スパンコール／火花）。
struct Particle {
    /// ステージ内の正規化座標
    var position: CGPoint
    var velocity: CGVector
    var life: Double
    var decay: Double
    var size: Double
    /// 0=ゴールド 1=白 2=ネオン 3=残り火
    var tone: Int
    var spin: Double
}

/// 床に焼き付いた足跡。
struct FootprintMark {
    let id: Int
    let position: CGPoint
    let rotation: Double
    let foot: Foot
    let birth: TimeInterval
    let accent: Bool
    let style: MoveStyle
}

/// 判定の吹き出し。
struct JudgementPopup {
    let judgement: Judgement
    let position: CGPoint
    let birth: TimeInterval
    let combo: Int
}

/// ステージ上で起きるすべてを、オーディオの再生位置ひとつから駆動する中枢。
///
/// 毎フレーム（CADisplayLink）で
///   音の位置 → 足の位置・足跡・粒子・閃光・判定
/// を計算する。SwiftUI側はこの状態を描くだけに徹する。
final class PerformanceEngine: ObservableObject {
    enum Phase: Equatable {
        case countIn
        case playing
        case finished
    }

    // MARK: - 入力

    let song: Song
    let map: GrooveMap
    let choreography: Choreography
    let mode: PerformanceMode
    let profile: HapticProfile

    private let audio = AudioEngineController.shared
    private let haptics = HapticConductor.shared

    // MARK: - 公開状態（SwiftUIが購読）

    @Published private(set) var frameID: UInt64 = 0
    @Published private(set) var phase: Phase = .countIn
    @Published private(set) var countInLabel: String = "4"
    @Published private(set) var result: PerformanceResult?

    /// 演奏が終わったときに呼ばれる（画面遷移は呼び出し側が行う）
    var onFinished: ((PerformanceResult) -> Void)?

    // MARK: - 描画用の状態（毎フレーム更新、Canvasが直接読む）

    private(set) var audioTime: TimeInterval = 0
    private(set) var target: ChoreoState
    /// 両足モード（観賞）のときだけ入る。片足モードでは nil。
    private(set) var dualFeet: DualChoreoState?
    private(set) var footprints: [FootprintMark] = []
    private(set) var particles: [Particle] = []
    private(set) var popups: [JudgementPopup] = []

    private(set) var lowLevel: Double = 0
    private(set) var midLevel: Double = 0
    private(set) var highLevel: Double = 0

    /// 画面の揺れ（正規化。レンダラーが画面サイズを掛けて使う）
    private(set) var shakeOffset: CGPoint = .zero
    private var shakeAmount: Double = 0
    private var shakePhase: Double = 0

    private(set) var kickFlash: Double = 0
    /// 直近のキックの時刻（床を走る波紋の起点）
    private(set) var lastKickTime: TimeInterval = -10
    private(set) var snareFlash: Double = 0
    private(set) var accentFlash: Double = 0
    private(set) var hatShimmer: Double = 0

    /// 拍の中の位置（0で拍頭、1で次の拍）
    private(set) var beatPhase: Double = 0
    /// 小節の中の位置（0...1）
    private(set) var barPhase: Double = 0
    private(set) var currentBar: Int = 0

    private(set) var touchPoint: CGPoint?
    private(set) var touchTrail: [CGPoint] = []
    private(set) var nearness: Double = 0

    private(set) var combo: Int = 0
    private(set) var maxCombo: Int = 0
    private(set) var score: Int = 0
    private(set) var lastJudgement: Judgement?
    private(set) var lastJudgementTime: TimeInterval = -10

    /// コンボの熱量（0...1）。繋げるほど舞台が明るくなり、粒が増える。
    /// 数字が増えるだけでは手応えにならないので、ステージ自体を燃え上がらせる。
    var heat: Double {
        guard mode.judgesFollow else { return 0.35 }
        return min(1, Double(combo) / 45)
    }

    /// 先読み表示する次のステップ（モードによって1〜3歩先まで）
    private(set) var previewMoves: [StepMove] = []

    // MARK: - 内部

    private var displayLink: CADisplayLink?
    private var linkProxy: DisplayLinkProxy?

    private var visualHitIndex = 0
    private var footprintIndex = 0
    private var lastMoveIndexSeen = 0
    private var pendingJudgeIndex = 0
    private var judged: [JudgedStep] = []
    private var touchHistory: [(time: TimeInterval, point: CGPoint)] = []
    private var random = DeterministicRandom(seed: 0x5EED_1234)
    private var countInWorkItems: [DispatchWorkItem] = []

    init(song: Song, map: GrooveMap, mode: PerformanceMode, profile: HapticProfile) {
        self.song = song
        self.map = map
        self.mode = mode
        self.profile = profile
        self.choreography = Choreography.build(from: map)
        self.target = ChoreoState(
            position: CGPoint(x: 0.5, y: 0.62),
            rotation: 0,
            scale: 1,
            landing: 0,
            foot: .right,
            style: .plant,
            moveIndex: 0
        )
    }

    deinit {
        stopLink()
    }

    // MARK: - 開始と終了

    func start() {
        phase = .countIn
        audio.load(song: song)
        startLink()
        runCountIn()
    }

    private func runCountIn() {
        cancelCountIn()
        let period = min(0.7, max(0.32, map.beatPeriod))
        let labels = ["4", "3", "2", "1"]

        for i in 0..<4 {
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.phase == .countIn else { return }
                self.countInLabel = labels[i]
                self.haptics.playCountIn(isFinal: i == 3, profile: self.profile)
            }
            countInWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + period * Double(i), execute: item)
        }

        let startItem = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .countIn else { return }
            self.beginPlayback()
        }
        countInWorkItems.append(startItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + period * 4, execute: startItem)
    }

    private func cancelCountIn() {
        for item in countInWorkItems { item.cancel() }
        countInWorkItems.removeAll()
    }

    private func beginPlayback() {
        phase = .playing
        // 先に音を鳴らしてから触覚を仕掛ける。逆にすると、まだ再生位置が0のまま
        // 最初の0.5秒ぶんを予約してしまい、曲頭だけ振動が先走る。
        audio.play { [weak self] in
            self?.finish()
        }
        haptics.startSequence(map: map, profile: profile) { [weak self] in
            self?.audio.currentTime ?? 0
        }
    }

    func stop() {
        cancelCountIn()
        haptics.stopSequence()
        audio.stop()
        stopLink()
    }

    func finish() {
        guard phase != .finished else { return }
        cancelCountIn()
        haptics.stopSequence()
        audio.stop()
        stopLink()
        phase = .finished

        // まだ判定していない残りをミス扱いにはせず、実際に通過した分だけで採点する
        let summary = FollowJudge.summarize(
            steps: judged,
            songTitle: song.title,
            bpm: map.bpm,
            maxCombo: maxCombo,
            score: score
        )
        result = summary
        onFinished?(summary)
    }

    // MARK: - 入力

    func updateTouch(_ point: CGPoint?, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard let point else {
            touchPoint = nil
            return
        }
        let normalized = CGPoint(x: point.x / size.width, y: point.y / size.height)
        touchPoint = normalized
        touchHistory.append((time: audioTime, point: normalized))
        if touchHistory.count > 240 {
            touchHistory.removeFirst(touchHistory.count - 240)
        }
        touchTrail.append(normalized)
        if touchTrail.count > 22 {
            touchTrail.removeFirst(touchTrail.count - 22)
        }
    }

    // MARK: - フレーム更新

    private final class DisplayLinkProxy: NSObject {
        var callback: (() -> Void)?
        @objc func onFrame() { callback?() }
    }

    private func startLink() {
        stopLink()
        let proxy = DisplayLinkProxy()
        proxy.callback = { [weak self] in self?.step() }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.onFrame))
        link.add(to: .main, forMode: .common)
        linkProxy = proxy
        displayLink = link
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
        linkProxy = nil
    }

    private func step() {
        let previousTime = audioTime
        audioTime = phase == .playing ? audio.currentTime : 0
        let dt = max(1.0 / 120.0, min(0.05, audioTime - previousTime))

        updateLevels()
        updateTargetAndFootprints()
        consumeHits()
        updateJudging()
        updateParticles(dt: dt)
        decayFlashes(dt: dt)
        updatePreview()
        trimPopups()

        frameID &+= 1
    }

    private func updateLevels() {
        lowLevel = Double(map.low(at: audioTime))
        midLevel = Double(map.mid(at: audioTime))
        highLevel = Double(map.high(at: audioTime))

        if map.beatPeriod > 0 {
            let pos = map.beatPosition(at: audioTime)
            beatPhase = pos - floor(pos)
            let barPos = pos / 4
            barPhase = barPos - floor(barPos)
            currentBar = Int(floor(barPos))
        }
    }

    private func updateTargetAndFootprints() {
        if mode.usesDualFeet {
            let dual = choreography.dualState(at: audioTime)
            dualFeet = dual
            let active = dual.activeFoot == .left ? dual.left : dual.right
            // スポットライトや粒子は身体の中心（両足の中点）を追う
            target = ChoreoState(
                position: dual.center,
                rotation: active.rotation,
                scale: active.scale,
                landing: dual.landing,
                foot: dual.activeFoot,
                style: dual.style,
                moveIndex: dual.moveIndex
            )
        } else {
            dualFeet = nil
            target = choreography.state(at: audioTime)
        }

        // 通過したステップの足跡を床に焼き付ける
        let reached = choreography.firstMoveIndex(after: audioTime)
        if reached > lastMoveIndexSeen {
            for index in lastMoveIndexSeen..<min(reached, choreography.moves.count) {
                let move = choreography.moves[index]
                guard move.plants else { continue }
                footprintIndex += 1
                footprints.append(
                    FootprintMark(
                        id: footprintIndex,
                        position: move.position,
                        rotation: move.rotation,
                        foot: move.foot,
                        birth: move.time,
                        accent: move.accent,
                        style: move.style
                    )
                )
                spawnLandingDust(at: move.position, accent: move.accent)
            }
            // 描画コストの上限。古い足跡は薄くて見えないので持ち続ける意味がない。
            if footprints.count > 16 {
                footprints.removeFirst(footprints.count - 16)
            }
            lastMoveIndexSeen = reached
        }
    }

    private func consumeHits() {
        let hits = map.hits
        if visualHitIndex > 0, visualHitIndex <= hits.count, hits[max(0, visualHitIndex - 1)].time > audioTime + 1 {
            // 巻き戻しに追随
            visualHitIndex = 0
        }
        while visualHitIndex < hits.count, hits[visualHitIndex].time <= audioTime {
            let hit = hits[visualHitIndex]
            visualHitIndex += 1
            guard audioTime - hit.time < 0.2 else { continue }

            switch hit.kind {
            case .kick:
                kickFlash = min(1.2, kickFlash + Double(hit.strength) * 0.95)
                lastKickTime = hit.time
                shakeAmount = max(shakeAmount, 0.0042 * Double(hit.strength))
                spawnBurst(at: target.position, count: 7, tone: 0, power: Double(hit.strength))
            case .snare:
                snareFlash = min(1.2, snareFlash + Double(hit.strength) * 0.9)
                shakeAmount = max(shakeAmount, 0.0022 * Double(hit.strength))
                spawnBurst(at: target.position, count: 5, tone: 1, power: Double(hit.strength) * 0.8)
            case .accent:
                accentFlash = 1.2
                kickFlash = 1.2
                lastKickTime = hit.time
                shakeAmount = max(shakeAmount, 0.0125)
                spawnBurst(at: target.position, count: 26, tone: 0, power: 1.4)
                spawnBurst(at: target.position, count: 12, tone: 1, power: 1.1)
            case .hat, .openHat:
                hatShimmer = min(1, hatShimmer + 0.5)
            case .ghost:
                hatShimmer = min(1, hatShimmer + 0.18)
            }
        }
    }

    private func updateJudging() {
        guard mode.judgesFollow, phase == .playing else { return }
        let moves = choreography.moves

        while pendingJudgeIndex < moves.count,
              moves[pendingJudgeIndex].time < audioTime - FollowJudge.timingWindow {
            let move = moves[pendingJudgeIndex]
            let step = FollowJudge.judge(
                moveIndex: pendingJudgeIndex,
                targetTime: move.time,
                targetPosition: move.position,
                touchHistory: touchHistory,
                tolerance: mode.judgeTolerance
            )
            judged.append(step)
            pendingJudgeIndex += 1

            if step.judgement == .miss {
                combo = 0
            } else {
                combo += 1
                maxCombo = max(maxCombo, combo)
            }
            let comboBonus = min(300, combo * 4)
            score += step.judgement.score + (step.judgement == .miss ? 0 : comboBonus)

            lastJudgement = step.judgement
            lastJudgementTime = audioTime
            popups.append(
                JudgementPopup(
                    judgement: step.judgement,
                    position: move.position,
                    birth: audioTime,
                    combo: combo
                )
            )

            if step.judgement == .perfect {
                haptics.playPerfect(profile: profile)
                spawnBurst(at: move.position, count: 10, tone: 2, power: 0.9)
            }
        }

        // 指と足跡の近さ（描画の吸着表現に使う）
        if let touchPoint {
            let dx = Double(touchPoint.x - target.position.x)
            let dy = Double(touchPoint.y - target.position.y)
            let distance = (dx * dx + dy * dy).squareRoot()
            nearness = max(0, 1 - distance / 0.22)
        } else {
            nearness = 0
        }
    }

    private func trimPopups() {
        popups.removeAll { audioTime - $0.birth > 0.75 }
        footprints.removeAll { audioTime - $0.birth > 4.5 }
    }

    private func updatePreview() {
        // 「今向かっている一歩」の次から先を見せる（今の一歩は実体で描かれているため）
        let start = choreography.firstMoveIndex(after: audioTime) + 1
        let end = min(choreography.moves.count, start + mode.previewCount)
        previewMoves = start < end ? Array(choreography.moves[start..<end]) : []
    }

    // MARK: - 粒子

    private func spawnBurst(at position: CGPoint, count: Int, tone: Int, power: Double) {
        let amount = Int(Double(count) * mode.spectacle * (1 + heat * 0.9))
        guard amount > 0 else { return }
        for _ in 0..<amount {
            let angle = random.range(0, .pi * 2)
            let speed = random.range(0.12, 0.55) * power
            particles.append(
                Particle(
                    position: position,
                    velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed * 0.75),
                    life: 1,
                    decay: random.range(1.1, 2.4),
                    size: random.range(1.6, 4.6) * (0.7 + power * 0.5),
                    tone: tone,
                    spin: random.range(-6, 6)
                )
            )
        }
        capParticles()
    }

    private func spawnLandingDust(at position: CGPoint, accent: Bool) {
        let count = accent ? 14 : 6
        for _ in 0..<count {
            let angle = random.range(.pi * 0.15, .pi * 0.85)
            let speed = random.range(0.05, 0.22)
            particles.append(
                Particle(
                    position: position,
                    velocity: CGVector(dx: cos(angle) * speed, dy: -abs(sin(angle)) * speed * 0.6),
                    life: 1,
                    decay: random.range(1.6, 3.0),
                    size: random.range(1.2, 3.0),
                    tone: accent ? 1 : 3,
                    spin: random.range(-3, 3)
                )
            )
        }
        capParticles()
    }

    private func capParticles() {
        if particles.count > 220 {
            particles.removeFirst(particles.count - 220)
        }
    }

    private func updateParticles(dt: Double) {
        guard !particles.isEmpty else { return }
        let step = CGFloat(dt)
        let gravity = CGFloat(0.42 * dt)
        let drag = CGFloat(1 - 1.4 * dt)
        for i in particles.indices {
            particles[i].position.x += particles[i].velocity.dx * step
            particles[i].position.y += particles[i].velocity.dy * step
            particles[i].velocity.dy += gravity
            particles[i].velocity.dx *= drag
            particles[i].life -= particles[i].decay * dt
        }
        particles.removeAll { $0.life <= 0 }
    }

    private func decayFlashes(dt: Double) {
        let fast = exp(-dt * 7.5)
        let slow = exp(-dt * 4.2)
        kickFlash *= fast
        snareFlash *= fast
        accentFlash *= slow
        hatShimmer *= exp(-dt * 11)

        shakePhase += dt * 41
        shakeAmount *= exp(-dt * 9.5)
        if shakeAmount < 0.00005 {
            shakeAmount = 0
            shakeOffset = .zero
        } else {
            shakeOffset = CGPoint(
                x: CGFloat(sin(shakePhase) * shakeAmount),
                y: CGFloat(cos(shakePhase * 1.37) * shakeAmount * 0.65)
            )
        }
    }
}

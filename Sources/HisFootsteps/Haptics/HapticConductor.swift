import CoreHaptics
import Foundation
import UIKit

/// 曲の進行に合わせて、常に「少し先」のハプティクスだけを予約し続ける指揮者。
///
/// 曲全体を一括で1つのパターンにすると、再生位置とのズレを直せない。
/// ここでは 60ms ごとに「今から 0.55 秒先まで」を予約し直すことで、
/// オーディオの実再生位置に毎回吸着させ、5分の曲でもズレない同期を作る。
final class HapticConductor {
    static let shared = HapticConductor()

    private var engine: CHHapticEngine?
    private var players: [CHHapticPatternPlayer] = []
    private let playersLock = NSLock()

    private let queue = DispatchQueue(label: "com.hisfootsteps.haptics", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    private var map: GrooveMap?
    private var hits: [GrooveHit] = []
    private var clock: (() -> TimeInterval)?
    private var profile: HapticProfile = .brutal

    private var nextHitIndex = 0
    private var scheduledUntil: TimeInterval = 0
    private var nextBedTime: TimeInterval = 0

    private let lookAhead: TimeInterval = 0.50
    private let tickInterval: TimeInterval = 0.12

    /// 端末ごとの体感ズレを詰めるための補正（正の値ほど振動が早くなる）
    var leadTime: TimeInterval = 0

    var isSupported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// 低電力モードではiPhoneのTaptic Engineが止まる。ここが「振動が弱い」の最大の原因になりやすい。
    var isLowPowerModeEnabled: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private init() {
        prepareEngine()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartEngineIfNeeded()
        }
    }

    // MARK: - エンジン

    private func prepareEngine() {
        guard isSupported else { return }
        do {
            let engine = try CHHapticEngine()
            // 音は一切鳴らさないので、オーディオセッションを奪わない設定にする
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false
            engine.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            engine.stoppedHandler = { _ in }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    func restartEngineIfNeeded() {
        guard isSupported else { return }
        if engine == nil {
            prepareEngine()
        } else {
            try? engine?.start()
        }
    }

    // MARK: - 単発再生

    func play(events: [CHHapticEvent]) {
        guard let engine, !events.isEmpty else { return }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            retain(player)
        } catch {
            // 触覚が鳴らなくても体験は継続させる
        }
    }

    func playSample(_ kind: HitKind, profile: HapticProfile) {
        play(events: HapticDesigner.events(for: kind, at: 0, strength: 1, profile: profile))
    }

    func playHeartbeat(profile: HapticProfile) {
        play(events: HapticDesigner.heartbeatEvents(profile: profile))
    }

    func playPerfect(profile: HapticProfile) {
        play(events: HapticDesigner.perfectSparkle(at: 0, profile: profile))
    }

    func playCountIn(isFinal: Bool, profile: HapticProfile) {
        play(events: HapticDesigner.countInEvents(at: 0, isFinal: isFinal, profile: profile))
    }

    // MARK: - 曲に同期した連続再生

    func startSequence(map: GrooveMap, profile: HapticProfile, clock: @escaping () -> TimeInterval) {
        stopSequence()
        guard isSupported, engine != nil else { return }
        restartEngineIfNeeded()

        queue.sync {
            self.map = map
            self.hits = map.hits
            self.profile = profile
            self.clock = clock
            self.nextHitIndex = 0
            self.scheduledUntil = 0
            self.nextBedTime = 0
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: tickInterval, leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    func stopSequence() {
        timer?.cancel()
        timer = nil
        queue.sync {
            self.clock = nil
            self.map = nil
            self.hits = []
            self.nextHitIndex = 0
            self.scheduledUntil = 0
        }
        releaseAllPlayers()
    }

    // MARK: - スケジューリング本体

    private func tick() {
        guard let engine, let clock, let map else { return }
        let audioNow = clock() + leadTime
        guard audioNow.isFinite, audioNow >= 0 else { return }

        let horizon = audioNow + lookAhead
        let windowStart = max(scheduledUntil, audioNow + 0.015)
        guard horizon > windowStart else { return }

        // 予約済みの位置が再生位置より大きく遅れている（＝曲が巻き戻った）場合は打点位置を取り直す
        if scheduledUntil < audioNow - 0.5 {
            nextHitIndex = firstHitIndex(after: windowStart)
            nextBedTime = 0
        }

        var events: [CHHapticEvent] = []

        while nextHitIndex < hits.count, hits[nextHitIndex].time < horizon {
            let hit = hits[nextHitIndex]
            nextHitIndex += 1
            guard hit.time >= windowStart else { continue }
            events += HapticDesigner.events(
                for: hit.kind,
                at: hit.time - windowStart,
                strength: hit.strength,
                profile: profile
            )
        }

        if profile.grooveBed {
            events += bedEvents(from: windowStart, to: horizon, map: map)
        }

        scheduledUntil = horizon
        guard !events.isEmpty else { return }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            let delay = windowStart - audioNow
            try player.start(atTime: engine.currentTime + max(0, delay))
            retain(player)
        } catch {
            // 一度失敗してもエンジンを立て直して次のtickで復帰させる
            try? engine.start()
        }
    }

    private func firstHitIndex(after time: TimeInterval) -> Int {
        var low = 0
        var high = hits.count
        while low < high {
            let mid = (low + high) / 2
            if hits[mid].time < time { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// 16分グリッド上に低周波のうねりを敷く。強い打点の直近は避けて音像を濁さない。
    private func bedEvents(from start: TimeInterval, to end: TimeInterval, map: GrooveMap) -> [CHHapticEvent] {
        let step = map.beatPeriod / 4
        guard step > 0.03 else { return [] }

        if nextBedTime < start {
            let n = ceil((start - map.firstBeatTime) / step)
            nextBedTime = map.firstBeatTime + n * step
            if nextBedTime < start { nextBedTime = start }
        }

        var out: [CHHapticEvent] = []
        var t = nextBedTime
        var guardCount = 0
        while t < end, guardCount < 64 {
            guardCount += 1
            if !hasStrongHit(near: t) {
                if let event = HapticDesigner.bedEvent(
                    at: t - start,
                    duration: step * 0.9,
                    lowEnergy: map.low(at: t),
                    profile: profile
                ) {
                    out.append(event)
                }
            }
            t += step
        }
        nextBedTime = t
        return out
    }

    private func hasStrongHit(near time: TimeInterval) -> Bool {
        let index = firstHitIndex(after: time - 0.06)
        var i = index
        while i < hits.count, hits[i].time < time + 0.06 {
            switch hits[i].kind {
            case .kick, .accent, .snare: return true
            default: break
            }
            i += 1
        }
        return false
    }

    private func retain(_ player: CHHapticPatternPlayer) {
        playersLock.lock()
        defer { playersLock.unlock() }
        players.append(player)
        if players.count > 16 {
            players.removeFirst(players.count - 16)
        }
    }

    private func releaseAllPlayers() {
        playersLock.lock()
        let snapshot = players
        players.removeAll()
        playersLock.unlock()
        for player in snapshot {
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
    }
}

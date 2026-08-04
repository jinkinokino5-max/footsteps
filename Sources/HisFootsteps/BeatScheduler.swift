import Foundation

/// 拍タイムスタンプ配列に合わせて、再生開始からの相対時間でコールバックを呼ぶ簡易スケジューラー（Phase5: 足跡アニメーション用）
final class BeatScheduler {
    private var isCancelled = false

    func schedule(beatTimestamps: [TimeInterval], onBeat: @escaping () -> Void) {
        isCancelled = false
        let startTime = DispatchTime.now()

        for timestamp in beatTimestamps {
            let deadline = startTime + timestamp
            DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
                guard let self, !self.isCancelled else { return }
                onBeat()
            }
        }
    }

    func cancel() {
        isCancelled = true
    }
}

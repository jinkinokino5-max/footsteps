import SwiftUI

/// ステージ全体を1枚のCanvasとして描く。
/// PerformanceEngineがフレームごとに`frameID`を更新するので、このViewはそれに合わせて再描画される。
struct StageCanvas: View {
    @ObservedObject var engine: PerformanceEngine

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            StageRenderer(engine: engine, size: size).render(into: &context)
        }
    }
}

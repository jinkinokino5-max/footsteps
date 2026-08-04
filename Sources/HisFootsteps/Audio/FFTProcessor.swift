import Accelerate

/// vDSPの実数FFTを1インスタンスで使い回すための薄いラッパー。
/// 解析ループの内側で毎回セットアップを作り直すと極端に遅くなるため、バッファごと保持する。
final class FFTProcessor {
    let size: Int
    let binCount: Int

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: UnsafeMutablePointer<Float>
    private let windowed: UnsafeMutablePointer<Float>
    private let realp: UnsafeMutablePointer<Float>
    private let imagp: UnsafeMutablePointer<Float>

    /// 直近の`process(_:)`で得られた振幅スペクトル（長さ`binCount`）
    let magnitudes: UnsafeMutablePointer<Float>

    init?(size: Int) {
        guard size >= 8, (size & (size - 1)) == 0 else { return nil }
        let log2n = vDSP_Length(round(log2(Double(size))))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }

        self.size = size
        self.binCount = size / 2
        self.log2n = log2n
        self.setup = setup

        window = UnsafeMutablePointer<Float>.allocate(capacity: size)
        window.initialize(repeating: 0, count: size)
        vDSP_hann_window(window, vDSP_Length(size), Int32(vDSP_HANN_NORM))

        windowed = UnsafeMutablePointer<Float>.allocate(capacity: size)
        windowed.initialize(repeating: 0, count: size)

        realp = UnsafeMutablePointer<Float>.allocate(capacity: binCount)
        realp.initialize(repeating: 0, count: binCount)
        imagp = UnsafeMutablePointer<Float>.allocate(capacity: binCount)
        imagp.initialize(repeating: 0, count: binCount)
        magnitudes = UnsafeMutablePointer<Float>.allocate(capacity: binCount)
        magnitudes.initialize(repeating: 0, count: binCount)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        window.deallocate()
        windowed.deallocate()
        realp.deallocate()
        imagp.deallocate()
        magnitudes.deallocate()
    }

    /// `input`は長さ`size`のモノラルサンプル。結果は`magnitudes`に入る。
    func process(_ input: UnsafePointer<Float>) {
        vDSP_vmul(input, 1, window, 1, windowed, 1, vDSP_Length(size))

        var split = DSPSplitComplex(realp: realp, imagp: imagp)
        windowed.withMemoryRebound(to: DSPComplex.self, capacity: binCount) { complexPtr in
            vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(binCount))
        }

        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvmags(&split, 1, magnitudes, 1, vDSP_Length(binCount))

        var count = Int32(binCount)
        vvsqrtf(magnitudes, magnitudes, &count)
    }
}

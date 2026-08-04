import Accelerate
import AVFoundation
import Foundation

enum AudioDecoderError: Error, LocalizedError {
    case cannotOpen
    case noAudioTrack
    case producedNothing

    var errorDescription: String? {
        switch self {
        case .cannotOpen:
            return "音声ファイルを開けませんでした"
        case .noAudioTrack:
            return "このファイルに音声トラックが見つかりませんでした"
        case .producedNothing:
            return "音声をデコードできませんでした（対応していない形式か、ファイルが壊れている可能性があります）"
        }
    }
}

/// 曲をモノラルのFloatサンプル列へデコードする。
///
/// なぜ2経路あるか:
/// `AVAudioFile.length` はMP3などの圧縮音源では**推定値**でしかない。
/// そのため終端付近で `read(into:)` が「失敗したのにNSErrorを埋めない」状態になり、
/// Swift側では `Foundation._GenericObjCError error 0`（＝The operation couldn't be completed）
/// という中身の無いエラーとして飛んでくる。
/// AVAudioFileで取り切れなかった場合は、より頑健なAVAssetReaderへ切り替える。
enum AudioDecoder {
    /// 解析対象の長さの上限（メモリ保護）。これを超える曲は先頭だけを解析する。
    /// 48kHzモノラルFloatで10分＝約115MB。これ以上は端末が耐えられない可能性がある。
    static let maxDuration: TimeInterval = 10 * 60

    struct Decoded {
        let samples: [Float]
        let sampleRate: Double

        var duration: TimeInterval {
            sampleRate > 0 ? Double(samples.count) / sampleRate : 0
        }
    }

    // MARK: - 入口

    static func decodeMono(url: URL, onProgress: ((Double) -> Void)? = nil) throws -> Decoded {
        var primary: Decoded?
        var primaryError: Error?
        var expectedFrames = 0

        do {
            let result = try decodeWithAudioFile(url: url, onProgress: onProgress, expectedFrames: &expectedFrames)
            primary = result
        } catch {
            primaryError = error
        }

        // 取り分が推定の85%未満なら、途中で読み取りが尽きた可能性が高い
        let looksTruncated: Bool
        if let primary, expectedFrames > 0 {
            looksTruncated = Double(primary.samples.count) < Double(expectedFrames) * 0.85
        } else {
            looksTruncated = primary == nil
        }

        if looksTruncated, let fallback = try? decodeWithAssetReader(url: url, onProgress: onProgress) {
            if let primary, primary.samples.count >= fallback.samples.count {
                return primary
            }
            if !fallback.samples.isEmpty {
                return fallback
            }
        }

        if let primary, !primary.samples.isEmpty { return primary }

        if let primaryError {
            // ObjC由来の中身が無いエラー（The operation couldn't be completed）は
            // そのまま見せても原因が分からないので、意味のあるメッセージへ置き換える。
            let nsError = primaryError as NSError
            if nsError.domain.contains("_GenericObjCError") {
                throw AudioDecoderError.producedNothing
            }
            throw primaryError
        }
        throw AudioDecoderError.producedNothing
    }

    // MARK: - 経路1: AVAudioFile

    private static func decodeWithAudioFile(
        url: URL,
        onProgress: ((Double) -> Void)?,
        expectedFrames: inout Int
    ) throws -> Decoded {
        guard let file = try? AVAudioFile(forReading: url) else {
            throw AudioDecoderError.cannotOpen
        }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = file.length
        guard sampleRate > 0, totalFrames > 0 else { throw AudioDecoderError.producedNothing }

        let limit = min(totalFrames, Int64(maxDuration * sampleRate))
        expectedFrames = Int(limit)

        let chunkCapacity: AVAudioFrameCount = 1 << 16
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkCapacity) else {
            throw AudioDecoderError.cannotOpen
        }

        let channelCount = Int(format.channelCount)
        var samples = [Float]()
        samples.reserveCapacity(Int(limit))

        // `while true` で読み続けると、推定長を過ぎた最後の1回で必ず失敗する。
        // 必ず残りフレーム数で頭打ちにし、失敗しても取れた分で続行する。
        while file.framePosition < limit {
            let remaining = limit - file.framePosition
            let want = AVAudioFrameCount(min(Int64(chunkCapacity), remaining))
            if want == 0 { break }

            do {
                try file.read(into: buffer, frameCount: want)
            } catch {
                if samples.isEmpty { throw error }
                break
            }

            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            guard let channelData = buffer.floatChannelData else { break }

            appendMonoMix(
                from: channelData,
                channelCount: channelCount,
                frames: frames,
                into: &samples
            )

            onProgress?(Double(samples.count) / Double(limit))
        }

        guard !samples.isEmpty else { throw AudioDecoderError.producedNothing }
        return Decoded(samples: samples, sampleRate: sampleRate)
    }

    private static func appendMonoMix(
        from channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frames: Int,
        into samples: inout [Float]
    ) {
        var mono = [Float](repeating: 0, count: frames)
        mono.withUnsafeMutableBufferPointer { mp in
            guard let dst = mp.baseAddress else { return }
            dst.update(from: channelData[0], count: frames)
            if channelCount > 1 {
                for c in 1..<channelCount {
                    vDSP_vadd(dst, 1, channelData[c], 1, dst, 1, vDSP_Length(frames))
                }
                var scale = 1.0 / Float(channelCount)
                vDSP_vsmul(dst, 1, &scale, dst, 1, vDSP_Length(frames))
            }
        }
        samples.append(contentsOf: mono)
    }

    // MARK: - 経路2: AVAssetReader（圧縮音源に強い）

    private static let fallbackSampleRate: Double = 44100

    private static func decodeWithAssetReader(url: URL, onProgress: ((Double) -> Void)?) throws -> Decoded {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw AudioDecoderError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: fallbackSampleRate
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioDecoderError.producedNothing }
        reader.add(output)
        guard reader.startReading() else { throw AudioDecoderError.producedNothing }

        let seconds = CMTimeGetSeconds(asset.duration)
        let expected = seconds.isFinite && seconds > 0
            ? Int(min(seconds, maxDuration) * fallbackSampleRate)
            : 0
        let limit = expected > 0 ? expected : Int(maxDuration * fallbackSampleRate)

        var samples = [Float]()
        if expected > 0 { samples.reserveCapacity(expected) }

        while samples.count < limit, let sampleBuffer = output.copyNextSampleBuffer() {
            if let block = CMSampleBufferGetDataBuffer(sampleBuffer) {
                var totalLength = 0
                var dataPointer: UnsafeMutablePointer<CChar>?
                let status = CMBlockBufferGetDataPointer(
                    block,
                    atOffset: 0,
                    lengthAtOffsetOut: nil,
                    totalLengthOut: &totalLength,
                    dataPointerOut: &dataPointer
                )
                if status == noErr, let dataPointer, totalLength >= MemoryLayout<Float>.size {
                    let count = totalLength / MemoryLayout<Float>.size
                    let floats = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: count)
                    samples.append(contentsOf: UnsafeBufferPointer(start: floats, count: count))
                }
            }
            _ = CMSampleBufferInvalidate(sampleBuffer)

            if expected > 0 {
                onProgress?(Double(samples.count) / Double(expected))
            }
        }

        reader.cancelReading()
        guard !samples.isEmpty else { throw AudioDecoderError.producedNothing }
        return Decoded(samples: samples, sampleRate: fallbackSampleRate)
    }
}

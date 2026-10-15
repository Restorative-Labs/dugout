import Accelerate
import AVFoundation
import CoreVideo
import Foundation
import ImageIO

/// The upright, downscaled luma the segmentation math runs on.
///
/// The JS drew each video frame — upright, as the browser displays it — onto a 192×108 canvas
/// (motion) and a 480×270 canvas (ball), then computed luma. Here the luma comes straight from the
/// decoder's Y plane and is scaled with vImage. Two differences from the browser, both in the
/// INPUT, not in the logic (which is held to the JS by SegmentParityTests): the decoder's luma
/// (BT.709 for HD) instead of the browser's 0.299/0.587/0.114 recomputation from RGB, and vImage's
/// resampling instead of canvas drawImage's. Both are small next to the 18 and 26 thresholds.
struct GrayScaler {
    let orientation: CGImagePropertyOrientation

    /// (motion grid, ball grid) for one decoded frame.
    func grays(_ frame: CVPixelBuffer) -> (motion: [UInt8], ball: [UInt8]) {
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        let planar = CVPixelBufferIsPlanar(frame)
        var src = vImage_Buffer(
            data: planar ? CVPixelBufferGetBaseAddressOfPlane(frame, 0) : CVPixelBufferGetBaseAddress(frame),
            height: vImagePixelCount(planar ? CVPixelBufferGetHeightOfPlane(frame, 0) : CVPixelBufferGetHeight(frame)),
            width: vImagePixelCount(planar ? CVPixelBufferGetWidthOfPlane(frame, 0) : CVPixelBufferGetWidth(frame)),
            rowBytes: planar ? CVPixelBufferGetBytesPerRowOfPlane(frame, 0) : CVPixelBufferGetBytesPerRow(frame))
        return (scaled(&src, Tuning.motionW, Tuning.motionH), scaled(&src, Tuning.ballW, Tuning.ballH))
    }

    /// Scale the (stored-orientation) luma so that, once turned upright, it is w×h.
    private func scaled(_ src: inout vImage_Buffer, _ w: Int, _ h: Int) -> [UInt8] {
        let quarterTurn = orientation == .right || orientation == .left
        // For a sideways-stored frame, scale to h×w first, then rotate the small image — far
        // cheaper than rotating the full-resolution frame.
        let sw = quarterTurn ? h : w, sh = quarterTurn ? w : h
        var small = [UInt8](repeating: 0, count: sw * sh)
        small.withUnsafeMutableBytes { raw in
            var dst = vImage_Buffer(data: raw.baseAddress, height: vImagePixelCount(sh), width: vImagePixelCount(sw), rowBytes: sw)
            vImageScale_Planar8(&src, &dst, nil, vImage_Flags(kvImageNoFlags))
        }
        let rotation: Int
        switch orientation {
        case .right: rotation = kRotate90DegreesClockwise
        case .left: rotation = kRotate90DegreesCounterClockwise
        case .down: rotation = kRotate180DegreesClockwise
        default: return small
        }
        var out = [UInt8](repeating: 0, count: w * h)
        small.withUnsafeMutableBytes { sRaw in
            out.withUnsafeMutableBytes { dRaw in
                var s = vImage_Buffer(data: sRaw.baseAddress, height: vImagePixelCount(sh), width: vImagePixelCount(sw), rowBytes: sw)
                var d = vImage_Buffer(data: dRaw.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w)
                vImageRotate90_Planar8(&s, &d, UInt8(rotation), 0, vImage_Flags(kvImageNoFlags))
            }
        }
        return out
    }
}

/// Channel 0 of the clip's audio as floats, at the file's own sample rate (segment.js decoded it
/// with an AudioContext at the device rate; the 10 ms envelope makes the rate immaterial).
enum AudioPCM {
    static func channel0(of asset: AVAsset) async throws -> (samples: [Float], rate: Double)? {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { return nil }
        var samples: [Float] = []
        var rate = 0.0
        var channels = 1
        while let buffer = output.copyNextSampleBuffer() {
            if rate == 0, let fmt = CMSampleBufferGetFormatDescription(buffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee {
                rate = asbd.mSampleRate
                channels = max(1, Int(asbd.mChannelsPerFrame))
            }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            // interleaved: take every `channels`-th sample, starting at channel 0
            if channels == 1 { samples.append(contentsOf: data) }
            else { samples.append(contentsOf: stride(from: 0, to: data.count, by: channels).map { data[$0] }) }
        }
        if reader.status == .failed || rate == 0 { return nil }
        return (samples, rate)
    }
}

/// js/segment.js segment(), minus keyframes: find the swings in a clip.
public struct SegmentationResult {
    public var swings: [SwingSpan]
    public var capHit: String?
    public var durationSec: Double
    public var info: VideoTrackInfo
    public var sampleCount: Int
    public var audioPeakCount: Int
    public var ballTrackCount: Int
    /// The ball detector found so many "tracks" it was tracking noise, so it was ignored.
    public var ballSaturated: Bool
    public var skipped: FrameReadReport
}

/// Sees every frame's measured grids — used by the parity runner to feed the JS the identical input.
public typealias GrayObserver = (_ t: Double, _ motion: [UInt8], _ ball: [UInt8]) -> Void

public enum Segmenter {
    public static func segment(_ url: URL, progress: ((Double) -> Void)? = nil,
                               observer: GrayObserver? = nil,
                               audioObserver: ((_ samples: [Float], _ rate: Double) -> Void)? = nil) async throws -> SegmentationResult {
        let reader = try await FrameReader.open(url)
        let scaler = GrayScaler(orientation: reader.info.orientation)

        // ---- motion + ball pass (sampleMotion, every decoded frame) ----
        var samples: [MotionSample] = []
        var ballFrames: [BallFrame] = []
        var prevMotion: [Float]? = nil
        var prevBall: [UInt8]? = nil
        let skipped = try reader.forEachFrame { t, frame in
            let (m8, b) = scaler.grays(frame)
            observer?(t, m8, b)
            let m = m8.map(Float.init)
            let fresh = t > (samples.last?.t ?? -1)
            if let pm = prevMotion, fresh { samples.append(MotionSample(t: t, e: SegmentMath.diffEnergy(m, pm))) }
            if let pb = prevBall, fresh { ballFrames.append(BallFrame(t: t, blobs: SegmentMath.ballBlobs(cur: b, prev: pb))) }
            prevMotion = m
            prevBall = b
            if reader.info.duration > 0 { progress?(min(1, t / reader.info.duration)) }
        }

        // ---- audio transients (confirmatory only) ----
        var peaks: [Double] = []
        if let pcm = try? await AudioPCM.channel0(of: reader.asset) {
            audioObserver?(pcm.samples, pcm.rate)
            peaks = SegmentMath.audioPeaks(samples: pcm.samples, sampleRate: pcm.rate)
        }

        // ---- ball tracks, with the saturation guard ----
        var tracks = SegmentMath.linkBallTracks(ballFrames)
        let saturated = tracks.count > Tuning.ballMaxTracks
        if saturated { tracks = [] }   // a gate that matches everything is worse than no gate

        let swings = SegmentMath.findSwings(samples: samples, peaks: peaks, ballTracks: tracks)
        let capped = SegmentMath.applyCaps(swings, durationSec: reader.info.duration)
        return SegmentationResult(swings: capped.swings, capHit: capped.capHit, durationSec: reader.info.duration,
                                  info: reader.info, sampleCount: samples.count, audioPeakCount: peaks.count,
                                  ballTrackCount: saturated ? 0 : tracks.count, ballSaturated: saturated, skipped: skipped)
    }
}

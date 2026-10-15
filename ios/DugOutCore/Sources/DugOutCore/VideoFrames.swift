import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ImageIO

public enum DugOutCoreError: Error, CustomStringConvertible {
    case noVideoTrack(URL)
    case readerFailed(String)

    public var description: String {
        switch self {
        case .noVideoTrack(let url): return "No video track in \(url.lastPathComponent)"
        case .readerFailed(let why): return "Could not read video frames: \(why)"
        }
    }
}

/// What the clip says about itself before any frame is decoded.
public struct VideoTrackInfo: Equatable {
    /// Four-character codec code: "hvc1" is HEVC (what an iPhone records), "avc1" is H.264.
    public var codec: String
    /// Encoded pixel size, before rotation. An upright iPhone clip is stored sideways (1920×1080)
    /// and carries `orientation` to say how to turn it.
    public var width: Int
    public var height: Int
    /// How the stored pixels must be turned to stand the picture upright. Vision needs this:
    /// a sideways person is a much harder pose problem than an upright one.
    public var orientation: CGImagePropertyOrientation
    /// The frame rate the file *claims*. The real spacing is in `ClipTimeline.timestamps`.
    public var nominalFPS: Double
    public var duration: Double
    /// Stretches of the movie timeline with no media behind them (an edit list's "empty edits").
    /// iPhone clips open with one of ~0.19 s. They are timeline structure, not dropped frames.
    public var emptyEdits: [ClosedRange<Double>]
}

/// Which way up the picture is, from the rotation an iPhone stores on the video track.
///
/// iPhones never rotate the pixels themselves; they record sideways and attach a transform that
/// the player applies. Only the four right-angle rotations occur from the rear camera, which is
/// what DugOut films with. Mirrored transforms (front camera, determinant < 0) are NOT supported:
/// this reads only the rotation, so a mirrored clip would get a plausible but wrong orientation.
public func imageOrientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
    // atan2(b, a) is the transform's rotation angle; divide by 90° and round to a quarter turn.
    let quarterTurns = Int((atan2(transform.b, transform.a) / (.pi / 2)).rounded())
    switch quarterTurns {
    case 1: return .right            // 90°: filmed holding the phone upright (portrait)
    case -1: return .left            // 270°: portrait, phone upside down
    case 2, -2: return .down         // 180°: landscape, phone turned the other way
    default: return .up              // 0°: landscape, as stored
    }
}

/// Decodes a clip frame by frame with AVAssetReader, handing over each frame with its real
/// presentation timestamp — the moment that frame is meant to be shown.
///
/// This is the native replacement for the JS layer's frame sampling. The JS sampled a playing
/// <video> element and *estimated* frame times; here each timestamp comes from the file itself.
public final class FrameReader {
    public let url: URL
    public let info: VideoTrackInfo
    private let asset: AVURLAsset
    private let track: AVAssetTrack

    private init(url: URL, asset: AVURLAsset, track: AVAssetTrack, info: VideoTrackInfo) {
        self.url = url
        self.asset = asset
        self.track = track
        self.info = info
    }

    /// Opens a clip and reads its header. `async` because AVFoundation loads track properties
    /// lazily and asks callers to await them rather than block.
    public static func open(_ url: URL) async throws -> FrameReader {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw DugOutCoreError.noVideoTrack(url)
        }
        let (size, transform, fps, formats, segments) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions, .segments)
        let duration = try await asset.load(.duration)
        let codec = formats.first.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "????"
        let info = VideoTrackInfo(
            codec: codec,
            width: Int(size.width.rounded()),
            height: Int(size.height.rounded()),
            orientation: imageOrientation(for: transform),
            nominalFPS: Double(fps),
            duration: duration.seconds,
            emptyEdits: segments.filter(\.isEmpty).map {
                let r = $0.timeMapping.target
                return r.start.seconds...(r.start + r.duration).seconds
            })
        return FrameReader(url: url, asset: asset, track: track, info: info)
    }

    /// Calls `body` once per decoded frame, in presentation order, until the clip ends or the
    /// frame time passes `upTo` seconds.
    ///
    /// Frames arrive as CVPixelBuffers — the raw decoded image, not a copy — at full encoded
    /// resolution. They are only valid inside `body`; do not keep them.
    ///
    /// Frames that are not camera footage are counted and skipped, never silently dropped and
    /// never handed on — see `FrameReadReport`.
    @discardableResult
    public func forEachFrame(upTo: Double? = nil,
                             _ body: (_ t: Double, _ frame: CVPixelBuffer) throws -> Void) throws -> FrameReadReport {
        let reader = try AVAssetReader(asset: asset)
        // Ask for decoded pixels in the camera's native YUV layout: no colour conversion, and it
        // is a format Vision accepts directly. Without outputSettings the reader would hand back
        // compressed samples in *decode* order, which is not presentation order for HEVC.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ])
        output.alwaysCopiesSampleData = false   // hand over the decoder's buffer, don't copy it
        reader.add(output)
        guard reader.startReading() else {
            throw DugOutCoreError.readerFailed(reader.error?.localizedDescription ?? "startReading failed")
        }

        var report = FrameReadReport()
        while let sample = output.copyNextSampleBuffer() {
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if let upTo, t > upTo {
                reader.cancelReading()
                break
            }
            guard let frame = CMSampleBufferGetImageBuffer(sample) else {
                report.imageless += 1
                continue
            }
            // For an empty edit the reader still hands back a decoded frame — all black, no
            // marker on it — that no camera captured. Measured on every pitch clip. Skip it.
            if info.emptyEdits.contains(where: { t >= $0.lowerBound && t < $0.upperBound }) {
                report.editFiller += 1
                continue
            }
            // Each frame is a large buffer; draining the autorelease pool per frame keeps memory
            // flat across thousands of frames instead of growing until the loop ends.
            try autoreleasepool { try body(t, frame) }
        }
        if reader.status == .failed {
            throw DugOutCoreError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        return report
    }
}

/// Decoded samples that were not handed on as frames, and why.
public struct FrameReadReport: Equatable {
    /// Samples with no image at all (timing-only). Expected 0.
    public var imageless = 0
    /// Filler frames the reader synthesised for an empty edit. 1 on every iPhone pitch clip.
    public var editFiller = 0
}

/// P1.1 — every frame's real presentation time, and what that says about the frame spacing.
public struct ClipTimeline {
    public let info: VideoTrackInfo
    /// Seconds, one per decoded frame, in the order the reader delivered them.
    public let timestamps: [Double]
    /// Samples the decoder produced without an image. Expected to be 0.
    public let imagelessSamples: Int
    /// Black filler frames for empty edits, skipped (see `FrameReader.forEachFrame`).
    public let editFillerFrames: Int

    public static func read(_ url: URL) async throws -> ClipTimeline {
        let reader = try await FrameReader.open(url)
        var ts: [Double] = []
        let report = try reader.forEachFrame { t, _ in ts.append(t) }
        return ClipTimeline(info: reader.info, timestamps: ts,
                            imagelessSamples: report.imageless, editFillerFrames: report.editFiller)
    }

    /// Gap from each frame to the next.
    public var deltas: [Double] { zip(timestamps.dropFirst(), timestamps).map { $0 - $1 } }

    /// Every frame strictly later than the one before. A false here means nothing downstream
    /// can trust frame order.
    public var isMonotonic: Bool { deltas.allSatisfy { $0 > 0 } }

    public var minDelta: Double? { deltas.min() }
    public var medianDelta: Double? { Stats.median(deltas) }
    public var maxDelta: Double? { deltas.max() }

    /// Frames whose gap from the previous frame is off the nominal spacing (1 / nominalFPS) by
    /// more than `tolerance` (0.25 = 25%). `index` is the later frame of the pair. Variable frame
    /// rate shows up here — it is reported, never smoothed over.
    public func irregularDeltas(tolerance: Double = 0.25) -> [(index: Int, delta: Double)] {
        guard let expected = (info.nominalFPS > 0 ? 1 / info.nominalFPS : medianDelta) else { return [] }
        return deltas.enumerated().compactMap { i, d in
            abs(d - expected) > expected * tolerance ? (index: i + 1, delta: d) : nil
        }
    }
}

/// 'hvc1' etc. from the 32-bit code CoreMedia stores.
func fourCC(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    return String(bytes: bytes, encoding: .ascii) ?? String(code)
}

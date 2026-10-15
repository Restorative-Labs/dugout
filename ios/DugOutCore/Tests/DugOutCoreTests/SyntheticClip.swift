import AVFoundation
import CoreVideo
import Foundation

/// Writes a tiny H.264 clip whose frame timestamps we choose, so the timeline reader can be
/// checked against known answers on any Mac — no real footage needed.
enum SyntheticClip {
    /// - Parameters:
    ///   - ticks: each frame's presentation time in 1/600 s units (600 divides 24, 25, 30 and
    ///     60 fps exactly, which is why QuickTime uses it).
    ///   - transform: stored on the track the way an iPhone stores "this was filmed upright".
    static func write(to url: URL,
                      width: Int = 160, height: Int = 90,
                      ticks: [Int64],
                      transform: CGAffineTransform = .identity,
                      codec: AVVideoCodecType = .h264,
                      draw: ((_ frame: Int, _ pixels: UnsafeMutablePointer<UInt8>, _ width: Int, _ height: Int, _ rowBytes: Int) -> Void)? = nil) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.transform = transform
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: CMTime(value: ticks.first ?? 0, timescale: 600))

        for (i, tick) in ticks.enumerated() {
            while !input.isReadyForMoreMediaData { usleep(1_000) }
            guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let buffer = pb else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let draw {
                draw(i, CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self),
                     width, height, CVPixelBufferGetBytesPerRow(buffer))
            } else {
                // A different grey per frame so the encoder cannot collapse frames into one.
                memset(CVPixelBufferGetBaseAddress(buffer), Int32(40 + (i * 7) % 180),
                       CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: tick, timescale: 600)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished()
        let last = (ticks.last ?? 0) + 20
        writer.endSession(atSourceTime: CMTime(value: last, timescale: 600))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    /// Re-saves `source` with an empty edit of `emptyTicks`/600 s in front of it — the layout every
    /// iPhone pitch clip has (an empty edit of 0.188–0.204 s before the first real frame).
    static func withLeadingEmptyEdit(_ source: URL, emptyTicks: Int64, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let asset = AVURLAsset(url: source)
        let comp = AVMutableComposition()
        let full = CMTimeRange(start: .zero, duration: asset.duration)
        try comp.insertTimeRange(full, of: asset, at: .zero)
        comp.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: CMTime(value: emptyTicks, timescale: 600)))
        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        export.outputURL = url
        export.outputFileType = .mov
        let done = DispatchSemaphore(value: 0)
        export.exportAsynchronously { done.signal() }
        done.wait()
        if export.status != .completed { throw export.error ?? CocoaError(.fileWriteUnknown) }
    }

    static func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dugoutcore-\(name).mov")
    }

    /// Fill a BGRA frame with one grey level, then paint grey-level rectangles on it.
    static func paint(_ px: UnsafeMutablePointer<UInt8>, _ w: Int, _ h: Int, _ rowBytes: Int,
                      background: UInt8, rects: [(x: Int, y: Int, w: Int, h: Int, v: UInt8)]) {
        for y in 0..<h { memset(px + y * rowBytes, Int32(background), w * 4) }
        for r in rects {
            for y in max(0, r.y)..<min(h, r.y + r.h) {
                for x in max(0, r.x)..<min(w, r.x + r.w) {
                    let o = y * rowBytes + x * 4
                    px[o] = r.v; px[o + 1] = r.v; px[o + 2] = r.v; px[o + 3] = 255
                }
            }
        }
    }
}

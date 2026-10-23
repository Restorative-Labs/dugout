import AVFoundation
import CoreGraphics
import XCTest
@testable import DugOutCore

/// The video-facing half of P1.3: decoding and measuring frames. (The decisions made from those
/// measurements are held to the JS by SegmentParityTests.)
final class SegmenterTests: XCTestCase {

    /// A white ball crosses a dark, still scene: every frame after the first yields one motion sample,
    /// and the ball pass links the moving blobs into tracks.
    func testMeasuresMotionAndFindsAFlyingBall() async throws {
        let w = 960, h = 540, n = 30
        let url = SyntheticClip.tempURL("ball")
        try SyntheticClip.write(to: url, width: w, height: h, ticks: (0..<n).map { Int64($0) * 20 }) { i, px, fw, fh, rb in
            // ball: 12 px square moving right 24 px/frame (→ ~6 px square, 12 px/step at 480×270)
            SyntheticClip.paint(px, fw, fh, rb, background: 30, rects: [(x: 100 + i * 24, y: 260, w: 12, h: 12, v: 250)])
        }
        var observed = 0
        let result = try await Segmenter.segment(url, observer: { _, m, b in
            observed += 1
            XCTAssertEqual(m.count, Tuning.motionW * Tuning.motionH)
            XCTAssertEqual(b.count, Tuning.ballW * Tuning.ballH)
        })
        XCTAssertEqual(observed, n)
        XCTAssertEqual(result.sampleCount, n - 1)          // samples start at the second frame (JS: prev && fresh)
        // Frame differencing marks both where the ball IS and where it WAS (the patch it vacated
        // changes too), so one ball that moves more than its own width per frame leaves two parallel
        // trails. That is segment.js's behaviour as well — the gate only needs one near the swing.
        XCTAssertEqual(result.ballTrackCount, 2, "one flying ball = its leading and its vacated trail")
        XCTAssertFalse(result.ballSaturated)
    }

    /// The grids must be upright the way the browser drew them. Checked against AVFoundation's own
    /// upright rendering (AVAssetImageGenerator with the track transform), not against reasoning.
    func testGridsAreUprightForEveryStoredRotation() async throws {
        let w = 320, h = 180
        let transforms: [CGAffineTransform] = [
            .identity,
            CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(h), ty: 0),     // portrait
            CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: CGFloat(w)),     // portrait, upside-down phone
            CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: CGFloat(w), ty: CGFloat(h)),
        ]
        for (k, transform) in transforms.enumerated() {
            let url = SyntheticClip.tempURL("orient\(k)")
            // one bright block near the stored top-left corner — asymmetric, so any wrong turn shows
            try SyntheticClip.write(to: url, width: w, height: h, ticks: (0..<3).map { Int64($0) * 20 },
                                    transform: transform) { _, px, fw, fh, rb in
                SyntheticClip.paint(px, fw, fh, rb, background: 20, rects: [(x: 10, y: 10, w: 60, h: 30, v: 240)])
            }
            var grid: [UInt8] = []
            _ = try await Segmenter.segment(url, observer: { _, _, b in grid = b })
            let mine = Self.centroid(grid, Tuning.ballW, Tuning.ballH)

            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            let image = try await gen.image(at: .zero).image
            let truth = Self.centroid(of: image)
            XCTAssertEqual(mine.x, truth.x, accuracy: 0.03, "transform \(k): x")
            XCTAssertEqual(mine.y, truth.y, accuracy: 0.03, "transform \(k): y")
        }
    }

    /// Normalised centroid of the bright pixels in a grey grid.
    static func centroid(_ g: [UInt8], _ w: Int, _ h: Int) -> (x: Double, y: Double) {
        var sx = 0.0, sy = 0.0, n = 0.0
        for y in 0..<h { for x in 0..<w where g[y * w + x] > 128 { sx += Double(x); sy += Double(y); n += 1 } }
        return (sx / n / Double(w), sy / n / Double(h))
    }

    static func centroid(of image: CGImage) -> (x: Double, y: Double) {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return centroid(px, w, h)
    }

    /// Clearing a video in the Lab cancels its analysis: the pipeline must stop reading frames and
    /// throw, not finish and hand back a result for a video that is gone.
    func testCancelledAnalysisStopsAndReturnsNothing() async throws {
        let url = SyntheticClip.tempURL("cancelled")
        try SyntheticClip.write(to: url, width: 320, height: 180, ticks: (0..<300).map { Int64($0) * 20 })
        let task = Task { try await RoundAnalyzer.analyze(url) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled analysis must not produce a result")
        } catch is CancellationError {
        }
    }
}

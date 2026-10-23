import XCTest
@testable import DugOutCore

/// R-02: internal scores never cross an API boundary. An app that imports DugOutCore must have no
/// way to get one out — not by encoding a result, not by reflecting over it, not by printing it.
final class PrivacyTests: XCTestCase {

    private func sampleResults() -> (SwingSpan, SwingAnalysis, CheckpointMark) {
        let span = SwingSpan(start: 1, end: 3, contactT: 2, audioConfirmed: true, confidence: 0.8125)
        let analysis = SwingAnalysis(ok: true, reason: nil, faults: ["CT-05": FaultReading(conf: 0.8125, lowConfidence: false)],
                                     orientation: Orientation(dir: 1, frontIsLeft: true, weak: false), contactU: 0.62, trackLength: 24)
        let mark = CheckpointMark(pass: false, assessed: true, internalScore: 0.8125, faultIds: ["CT-05"], evidenceSwingIds: ["s0"])
        return (span, analysis, mark)
    }

    func testResultTypesAreNotEncodable() {
        XCTAssertFalse(SwingSpan.self is Encodable.Type, "SwingSpan must not be Encodable — it carries a confidence")
        XCTAssertFalse(SwingAnalysis.self is Encodable.Type, "SwingAnalysis must not be Encodable — it carries fault confidences")
        XCTAssertFalse(CheckpointMark.self is Encodable.Type, "CheckpointMark must not be Encodable — it carries internalScore")
        XCTAssertFalse([String: CheckpointMark].self is Encodable.Type)
    }

    func testReflectionAndPrintingShowNoScore() {
        let (span, analysis, mark) = sampleResults()
        for value in [span, analysis, mark] as [Any] {
            let labels = Mirror(reflecting: value).children.compactMap(\.label)
            for hidden in ["internalScore", "faults", "confidence", "contactU"] {
                XCTAssertFalse(labels.contains(hidden), "\(type(of: value)) reflects \(hidden)")
            }
            var dumped = ""
            dump(value, to: &dumped)
            for text in [String(describing: value), String(reflecting: value), dumped] {
                XCTAssertFalse(text.contains("0.8125"), "\(type(of: value)) prints an internal number")
                XCTAssertFalse(text.contains("0.62"), "\(type(of: value)) prints an internal number")
            }
        }
    }

    /// The parity tooling (same package) still sees everything it compares against the JS.
    func testPackageParityEncodingKeepsTheJSShape() throws {
        let (span, analysis, mark) = sampleResults()
        let s = try XCTUnwrap(try ParityJSON.object(span) as? [String: Any])
        XCTAssertEqual(Set(s.keys), ["start", "end", "contactT", "audioConfirmed", "confidence"])
        let a = try XCTUnwrap(try ParityJSON.object(analysis) as? [String: Any])
        XCTAssertEqual(Set(a.keys), ["ok", "faults", "orientation", "contactU", "trackLength"])
        let m = try XCTUnwrap(try ParityJSON.object(["contact": mark]) as? [String: [String: Any]])
        XCTAssertEqual(Set(m["contact"]?.keys ?? [:].keys), ["pass", "assessed", "internalScore", "faultIds", "evidenceSwingIds"])
        // an unassessed mark still carries internalScore: null, as the JS object does
        let none = CheckpointMark(pass: true, assessed: false, internalScore: nil, faultIds: [], evidenceSwingIds: [])
        let n = try XCTUnwrap(try ParityJSON.object(none) as? [String: Any])
        XCTAssertTrue(n["internalScore"] is NSNull)
    }
}

import Foundation

/// The JS-shaped JSON of a result, internal numbers included — for the parity harness only.
///
/// `package` access: this package's tests and probe tools can call it; an app that imports
/// DugOutCore cannot see it. The public result types (SwingSpan, SwingAnalysis, CheckpointMark)
/// are deliberately NOT Codable and hide their internals from Mirror, so app code has no route to
/// an internal score or confidence (R-02: scores never cross an API boundary).
package protocol ParityEncodable {
    func parityEncode(to encoder: Encoder) throws
}

package enum ParityJSON {
    /// JSONSerialization object (dictionary, array, number, …) of `value`.
    package static func object<T: ParityEncodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(Box(value: value)), options: [.fragmentsAllowed])
    }
}

/// Bridges a ParityEncodable into Encodable without making the public type Encodable.
struct Box<T: ParityEncodable>: Encodable {
    let value: T
    func encode(to encoder: Encoder) throws { try value.parityEncode(to: encoder) }
}

extension Array: ParityEncodable where Element: ParityEncodable {
    package func parityEncode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        for x in self { try c.encode(Box(value: x)) }
    }
}

extension Dictionary: ParityEncodable where Key == String, Value: ParityEncodable {
    package func parityEncode(to encoder: Encoder) throws {
        try mapValues { Box(value: $0) }.encode(to: encoder)
    }
}

extension SwingSpan: ParityEncodable {
    package func parityEncode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(contactT, forKey: .contactT)
        try c.encode(audioConfirmed, forKey: .audioConfirmed)
        try c.encode(confidence, forKey: .confidence)
    }
}

extension SwingAnalysis: ParityEncodable {
    package func parityEncode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ok, forKey: .ok)
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encode(faults, forKey: .faults)
        try c.encodeIfPresent(orientation, forKey: .orientation)
        try c.encodeIfPresent(contactU, forKey: .contactU)
        try c.encodeIfPresent(trackLength, forKey: .trackLength)
    }
}

extension CheckpointMark: ParityEncodable {
    // internalScore is always present in the JS object (null when unassessed); keep the same shape
    package func parityEncode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pass, forKey: .pass)
        try c.encode(assessed, forKey: .assessed)
        try c.encode(internalScore, forKey: .internalScore)
        try c.encode(faultIds, forKey: .faultIds)
        try c.encode(evidenceSwingIds, forKey: .evidenceSwingIds)
    }
}

// Mirror / dump / print show only what may be shown (R-02, R-13).
extension SwingSpan: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, children: ["start": start, "end": end, "contactT": contactT, "audioConfirmed": audioConfirmed])
    }
}

extension SwingAnalysis: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, children: ["ok": ok, "reason": reason as Any, "orientation": orientation as Any,
                                "trackLength": trackLength as Any, "faultIds": faultIds])
    }
}

extension CheckpointMark: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, children: ["pass": pass, "assessed": assessed, "faultIds": faultIds, "evidenceSwingIds": evidenceSwingIds])
    }
}

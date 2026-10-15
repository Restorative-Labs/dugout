import Foundation

/// SplitMix64 — a tiny deterministic generator, so randomised parity tests fail the same way
/// every run and any failure can be replayed from its seed.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
    mutating func int(_ lo: Int, _ hi: Int) -> Int { lo + Int(next() % UInt64(hi - lo + 1)) }
    mutating func chance(_ p: Double) -> Bool { unit() < p }
}

/// Compare two JSON-shaped trees (the Swift side encoded the same way), allowing a relative
/// tolerance on numbers only for floating-point rounding. Returns the first difference.
func jsonDifference(_ a: Any?, _ b: Any?, at path: String = "$", tolerance: Double = 1e-9) -> String? {
    switch (a, b) {
    case (nil, nil), (is NSNull, is NSNull), (nil, is NSNull), (is NSNull, nil):
        return nil
    case let (x as [String: Any], y as [String: Any]):
        if Set(x.keys) != Set(y.keys) { return "\(path): keys \(x.keys.sorted()) vs \(y.keys.sorted())" }
        for k in x.keys.sorted() { if let d = jsonDifference(x[k], y[k], at: "\(path).\(k)", tolerance: tolerance) { return d } }
        return nil
    case let (x as [Any], y as [Any]):
        if x.count != y.count { return "\(path): \(x.count) items vs \(y.count)" }
        for i in x.indices { if let d = jsonDifference(x[i], y[i], at: "\(path)[\(i)]", tolerance: tolerance) { return d } }
        return nil
    case let (x as NSNumber, y as NSNumber):
        let xb = CFGetTypeID(x) == CFBooleanGetTypeID(), yb = CFGetTypeID(y) == CFBooleanGetTypeID()
        if xb || yb { return xb == yb && x.boolValue == y.boolValue ? nil : "\(path): \(x) vs \(y)" }
        let dx = x.doubleValue, dy = y.doubleValue
        if dx == dy { return nil }
        return abs(dx - dy) <= tolerance * max(1, abs(dx), abs(dy)) ? nil : "\(path): \(dx) vs \(dy)"
    case let (x as String, y as String):
        return x == y ? nil : "\(path): \"\(x)\" vs \"\(y)\""
    default:
        return "\(path): \(String(describing: a)) vs \(String(describing: b))"
    }
}

/// Encode an Encodable to the same Foundation-object shape JSONSerialization gives for JS output.
func jsonObject<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
}

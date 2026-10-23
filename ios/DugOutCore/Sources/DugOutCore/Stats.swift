import Foundation

public enum Stats {
    /// The p-th percentile (p in 0...100), interpolating linearly between the two closest ranks.
    /// That is numpy's default `percentile` definition, so every number this package reports can
    /// be re-checked from the CSV with one line of Python. Returns nil for no values.
    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = min(max(p, 0), 100) / 100 * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - Double(lo))
    }

    public static func median(_ values: [Double]) -> Double? { percentile(values, 50) }

    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

import Foundation

/// The tip library — every fault, fix, cue and drill the app is allowed to say — as typed values.
///
/// The data is not code: it is `Resources/tip-library.json`, bundled with the package. That file
/// is an EXPORT of `js/library.js` (which `scripts/build_library.py` generates from the trainer's
/// spreadsheet) made by `scripts/export_library_json.swift`. Never edit it by hand: the library is
/// closed and human-vetted (CANON R-06), and `TipLibraryTests` fails the moment the two differ.
///
/// Field names match library.js exactly, so the JSON decodes with no key mapping.
public struct TipLibrary: Decodable, Equatable {
    public let tips: [Tip]
    public let cueGlossary: [GlossaryEntry]
    public let schools: [School]
    public let engineRules: [EngineRule]
    /// Red-line phrases that must never reach output in any rendering path (CG-01, CG-02).
    public let deprecatedCues: [String]

    public func tip(id: String) -> Tip? { tips.first { $0.id == id } }

    /// Where the bundled JSON lives. `Bundle.module` is the resource bundle SwiftPM builds for
    /// this package — in the app it ships inside DugOut.app, on the Mac next to the test binary.
    public static func bundledURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "tip-library", withExtension: "json") else {
            throw TipLibraryError.notBundled
        }
        return url
    }

    public static func bundled() throws -> TipLibrary {
        try JSONDecoder().decode(TipLibrary.self, from: Data(contentsOf: bundledURL()))
    }

    // MARK: - Entries

    public struct Tip: Decodable, Equatable {
        public let id: String               // e.g. "ST-01"
        public let checkpoint: String       // one of the six (R-01), lower-case: "stance" … "finish"
        public let fault: String
        public let detection: String
        public let tip: String
        public let drills: [Drill]
        public let cues: [String]
        public let cuesToAvoid: [String]
        public let avoidPhrases: [String]
        public let ageBands: [String]       // "7-10", "11-13", "14-18"
        public let emphasize: [String]      // age bands where this tip leads
        public let schoolTags: [String]
        public let tier: String
        public let sources: String
        public let notes: String
        /// The detector that measures this fault, or nil when it cannot be measured offline
        /// (needs ball flight or bat tracking). Those faults are never guessed at.
        public let detector: String?
        public let isToggle: Bool

        enum CodingKeys: String, CodingKey, CaseIterable {
            case id, checkpoint, fault, detection, tip, drills, cues, cuesToAvoid, avoidPhrases,
                 ageBands, emphasize, schoolTags, tier, sources, notes, detector, isToggle
        }
        static var fieldNames: Set<String> { Set(CodingKeys.allCases.map(\.rawValue)) }
    }

    public struct Drill: Decodable, Equatable {
        public let name: String
        public let rung: String             // progression rung, e.g. "tee"
        public let weighted: Bool

        enum CodingKeys: String, CodingKey, CaseIterable { case name, rung, weighted }
        static var fieldNames: Set<String> { Set(CodingKeys.allCases.map(\.rawValue)) }
    }

    public struct GlossaryEntry: Decodable, Equatable {
        public let id: String
        public let phrases: [String]
        public let phrase: String
        public let status: String
        public let statusText: String
        public let lineage: String
        public let why: String
        public let replacement: String
        public let tier: String

        enum CodingKeys: String, CodingKey, CaseIterable {
            case id, phrases, phrase, status, statusText, lineage, why, replacement, tier
        }
        static var fieldNames: Set<String> { Set(CodingKeys.allCases.map(\.rawValue)) }
    }

    public struct School: Decodable, Equatable {
        public let preset: String
        public let lineage: String
        public let beliefs: String
        public let signatureCues: String
        public let emphasisIds: [String]
        public let tier: String
        public let notes: String

        enum CodingKeys: String, CodingKey, CaseIterable {
            case preset, lineage, beliefs, signatureCues, emphasisIds, tier, notes
        }
        static var fieldNames: Set<String> { Set(CodingKeys.allCases.map(\.rawValue)) }
    }

    public struct EngineRule: Decodable, Equatable {
        public let id: String
        public let rule: String
        public let meaning: String
        public let tier: String

        enum CodingKeys: String, CodingKey, CaseIterable { case id, rule, meaning, tier }
        static var fieldNames: Set<String> { Set(CodingKeys.allCases.map(\.rawValue)) }
    }
}

public enum TipLibraryError: Error, CustomStringConvertible {
    case notBundled
    public var description: String {
        "tip-library.json is not in the DugOutCore bundle — run scripts/export_library_json.swift"
    }
}

import Foundation
import JavaScriptCore
import XCTest
@testable import DugOutCore

/// The bundled tip library must be js/library.js, exactly — same tips, same ids, every field
/// identical, wording byte-for-byte. js/library.js is the original (generated from the trainer's
/// spreadsheet by scripts/build_library.py); tip-library.json is an export of it and is never
/// edited by hand. These tests are what stops the two drifting apart: regenerate library.js
/// without re-exporting and they fail.
final class TipLibraryTests: XCTestCase {

    /// js/library.js, evaluated the way the browser does (it is a JS literal, not JSON: unquoted
    /// keys, comments), then serialised to Foundation objects.
    private func jsOriginal() throws -> [String: Any] {
        let data = try XCTUnwrap(try evaluateLibrary("JSON.stringify(window.DUGOUT_LIBRARY)").data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// library.js's source text, and its header's own count ("// 29 tip entries · …").
    private func librarySource() throws -> String {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/DugOutCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // ios/DugOutCore
            .deletingLastPathComponent()   // ios
            .deletingLastPathComponent()   // repo root
        return try String(contentsOf: repo.appendingPathComponent("js/library.js"), encoding: .utf8)
    }

    /// Runs library.js the way the browser does, then evaluates `expression` against it.
    private func evaluateLibrary(_ expression: String) throws -> String {
        let ctx = try XCTUnwrap(JSContext())
        var jsError: String?
        ctx.exceptionHandler = { _, e in jsError = e?.toString() }
        ctx.evaluateScript("var window = {};")
        ctx.evaluateScript(try librarySource())
        let out = ctx.evaluateScript(expression)?.toString()
        XCTAssertNil(jsError, "library.js did not evaluate")
        return try XCTUnwrap(out)
    }

    private func bundledRaw() throws -> [String: Any] {
        let data = try Data(contentsOf: try TipLibrary.bundledURL())
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Asked for: same tips, every id, every field

    func testSameNumberOfTipsAndEveryIdPresent() throws {
        let js = try XCTUnwrap(try jsOriginal()["tips"] as? [[String: Any]])
        let library = try TipLibrary.bundled()

        XCTAssertEqual(library.tips.count, js.count)
        let header = try librarySource().components(separatedBy: "\n").first { $0.contains("tip entries") } ?? ""
        let declared = Int(header.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "")
        XCTAssertEqual(js.count, declared, "library.js header declares a different tip count")
        let jsIds = js.compactMap { $0["id"] as? String }
        XCTAssertEqual(Set(jsIds).count, jsIds.count, "duplicate tip id in library.js")
        XCTAssertEqual(library.tips.map(\.id), jsIds, "ids missing, extra or out of order")
    }

    func testEveryTipFieldMatchesTheJSOriginalExactly() throws {
        let js = try XCTUnwrap(try jsOriginal()["tips"] as? [[String: Any]])
        let bundled = try XCTUnwrap(try bundledRaw()["tips"] as? [[String: Any]])
        XCTAssertEqual(bundled.count, js.count)
        for (b, j) in zip(bundled, js) {
            let id = j["id"] as? String ?? "?"
            XCTAssertEqual(Set(b.keys), Set(j.keys), "\(id): field set differs")
            for key in j.keys.sorted() {
                guard let bv = b[key], let jv = j[key] else { continue }   // key-set mismatch reported above
                if let diff = firstDifference(bv, jv, at: "\(id).\(key)") { XCTFail(diff) }
            }
        }
    }

    /// The bundled file is exactly what the exporter makes from today's library.js — byte for byte.
    /// This is the test that cannot be fooled: not by Unicode that Swift's == calls equal, not by a
    /// duplicated key (Swift keeps the first value, JS and Python the last), not by reordering.
    func testBundledFileIsByteForByteTheExportOfLibraryJS() throws {
        let expected = try evaluateLibrary("JSON.stringify(window.DUGOUT_LIBRARY, null, 2)") + "\n"
        let bundled = try Data(contentsOf: try TipLibrary.bundledURL())
        XCTAssertTrue(bundled == Data(expected.utf8),
                      "tip-library.json is not the export of js/library.js — run: swift scripts/export_library_json.swift")
    }

    // MARK: - The rest of library.js comes too, exactly

    /// Glossary, school presets, engine rules and the red-line deprecated cues are part of the
    /// library. Dropping deprecatedCues would silently remove a safety rail (CG-01, CG-02).
    func testWholeLibraryMatchesIncludingGlossarySchoolsRulesAndDeprecatedCues() throws {
        let js = try jsOriginal()
        XCTAssertEqual(Set(js.keys), ["tips", "cueGlossary", "schools", "engineRules", "deprecatedCues"])
        if let diff = firstDifference(try bundledRaw(), js, at: "library") { XCTFail(diff) }
    }

    // MARK: - The typed loader

    /// Every field in the JSON has a home in the Swift types — a typed struct must not quietly
    /// drop one — and decoding library.js itself gives the same values as the bundle.
    func testTypedLoaderModelsEveryFieldAndMatchesTheOriginal() throws {
        let raw = try bundledRaw()
        func keys(_ section: String) -> Set<String> {
            Set(((raw[section] as? [[String: Any]]) ?? []).flatMap(\.keys))
        }
        XCTAssertEqual(keys("tips"), TipLibrary.Tip.fieldNames)
        XCTAssertEqual(keys("cueGlossary"), TipLibrary.GlossaryEntry.fieldNames)
        XCTAssertEqual(keys("schools"), TipLibrary.School.fieldNames)
        XCTAssertEqual(keys("engineRules"), TipLibrary.EngineRule.fieldNames)
        let drillKeys = Set(((raw["tips"] as? [[String: Any]]) ?? [])
            .flatMap { ($0["drills"] as? [[String: Any]]) ?? [] }.flatMap(\.keys))
        XCTAssertEqual(drillKeys, TipLibrary.Drill.fieldNames)

        let fromJS = try JSONDecoder().decode(TipLibrary.self,
                                              from: JSONSerialization.data(withJSONObject: try jsOriginal()))
        XCTAssertEqual(try TipLibrary.bundled(), fromJS)
    }

    func testLoaderGivesTypedValues() throws {
        let library = try TipLibrary.bundled()
        let st01 = try XCTUnwrap(library.tip(id: "ST-01"))
        XCTAssertEqual(st01.checkpoint, "stance")
        XCTAssertEqual(st01.drills.first?.name, "Mirror setup checks")
        XCTAssertEqual(st01.drills.first?.weighted, false)
        XCTAssertEqual(library.deprecatedCues, ["chop down at the ball", "squish the bug", "swing down"])
        XCTAssertTrue(library.tips.contains { $0.detector == nil }, "unmeasurable faults keep detector: null")
    }

    // MARK: - Exact comparison

    /// First place two JSON trees differ, or nil — used to NAME a difference. Strict: a boolean never
    /// equals a number (Foundation would call `true == 1`), null only equals null, strings compare by
    /// UTF-8 bytes. The byte-for-byte test above is the one that cannot be fooled.
    private func firstDifference(_ a: Any, _ b: Any, at path: String) -> String? {
        switch (a, b) {
        case let (a as [String: Any], b as [String: Any]):
            if Set(a.keys) != Set(b.keys) {
                return "\(path): keys differ — bundled \(a.keys.sorted()) vs library.js \(b.keys.sorted())"
            }
            for k in a.keys.sorted() {
                if let d = firstDifference(a[k]!, b[k]!, at: "\(path).\(k)") { return d }
            }
            return nil
        case let (a as [Any], b as [Any]):
            if a.count != b.count { return "\(path): \(a.count) items vs library.js \(b.count)" }
            for (i, pair) in zip(a, b).enumerated() {
                if let d = firstDifference(pair.0, pair.1, at: "\(path)[\(i)]") { return d }
            }
            return nil
        case let (a as String, b as String):
            // Byte comparison, not ==: Swift's String == treats canonically equivalent text as equal,
            // so a decomposed "≠" or a Greek question mark for ";" would pass it.
            return a.utf8.elementsEqual(b.utf8) ? nil : "\(path): \"\(a)\" vs library.js \"\(b)\" (UTF-8 differs)"
        case let (a as NSNumber, b as NSNumber):
            let aBool = CFGetTypeID(a) == CFBooleanGetTypeID(), bBool = CFGetTypeID(b) == CFBooleanGetTypeID()
            func show(_ n: NSNumber, _ isBool: Bool) -> String { isBool ? (n.boolValue ? "true" : "false") : "number \(n)" }
            return aBool == bBool && a == b ? nil : "\(path): \(show(a, aBool)) vs library.js \(show(b, bBool))"
        case (is NSNull, is NSNull):
            return nil
        default:
            return "\(path): \(type(of: a)) vs library.js \(type(of: b))"
        }
    }
}

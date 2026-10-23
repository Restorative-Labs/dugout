// Export js/library.js to the native tip library resource, unchanged.
//
//     swift scripts/export_library_json.swift
//
// Run it from the repo root every time scripts/build_library.py regenerates js/library.js.
// It only READS library.js (which is generated — never edit it) and writes
// ios/DugOutCore/Sources/DugOutCore/Resources/tip-library.json.
//
// library.js is a JavaScript literal (unquoted keys, comments), not JSON, so it is evaluated by
// JavaScriptCore — Apple's own JS engine, the one Safari runs it with — and serialised with
// JSON.stringify. That changes the punctuation around the data and nothing in it: every string
// comes out character for character. TipLibraryTests in ios/DugOutCore proves it on every run.
import Foundation
import JavaScriptCore

let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = repo.appendingPathComponent("js/library.js")
let target = repo.appendingPathComponent("ios/DugOutCore/Sources/DugOutCore/Resources/tip-library.json")

guard FileManager.default.fileExists(atPath: source.path) else {
    FileHandle.standardError.write("Run from the repo root: \(source.path) not found\n".data(using: .utf8)!)
    exit(1)
}

let ctx = JSContext()!
var failure: String?
ctx.exceptionHandler = { _, e in failure = e?.toString() }
ctx.evaluateScript("var window = {};")
ctx.evaluateScript(try String(contentsOf: source, encoding: .utf8))
let isLibrary = ctx.evaluateScript(
    "typeof window.DUGOUT_LIBRARY === 'object' && window.DUGOUT_LIBRARY !== null && Array.isArray(window.DUGOUT_LIBRARY.tips)")?.toBool() ?? false
let json = ctx.evaluateScript("JSON.stringify(window.DUGOUT_LIBRARY, null, 2)")?.toString()

guard failure == nil, isLibrary, let json else {
    FileHandle.standardError.write("library.js did not evaluate: \(failure ?? "no DUGOUT_LIBRARY")\n".data(using: .utf8)!)
    exit(1)
}
try (json + "\n").write(to: target, atomically: true, encoding: .utf8)
print("wrote \(target.path)")

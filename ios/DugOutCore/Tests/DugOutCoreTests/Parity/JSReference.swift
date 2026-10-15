import Foundation
import JavaScriptCore
import XCTest

/// The JavaScript pipeline, running for real inside JavaScriptCore — the reference the Swift port
/// is held to (P1.3 / P1.4 parity).
///
/// It loads the repo's own js/config.js, js/library.js, js/pose.js, js/segment.js and
/// js/evaluate.js, unmodified on disk. Only two things are done to them, in memory:
///   1. Browser-only globals the modules touch at load time (document, canvases, Blob, AudioContext,
///      createImageBitmap, console) are stubbed. None of the logic under test uses a stub's output
///      except where a test deliberately feeds data through one (audio samples, poses).
///   2. Each module's export line is widened so internal functions (ballBlobs, linkBallTracks,
///      geom, orient, …) can be called directly. The exact export line is asserted first — if it
///      ever changes in the JS, this throws instead of quietly testing something else.
/// console.* is a no-op: CFG.DEBUG would otherwise print detector confidences (R-13).
final class JSReference {
    let ctx: JSContext
    private(set) var jsError: String?

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Parity
            .deletingLastPathComponent()   // DugOutCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // ios/DugOutCore
            .deletingLastPathComponent()   // ios
            .deletingLastPathComponent()   // repo root
    }

    struct LoadError: Error, CustomStringConvertible { let description: String }

    init() throws {
        guard let ctx = JSContext() else { throw LoadError(description: "no JSContext") }
        self.ctx = ctx
        ctx.exceptionHandler = { [weak self] _, e in self?.jsError = e?.toString() }
        ctx.evaluateScript(Self.shims)
        try load("js/config.js")
        ctx.evaluateScript("window.DUGOUT_CONFIG.DEBUG = false;")   // belt and braces with the no-op console
        try load("js/library.js")
        try load("js/pose.js")
        try load("js/segment.js", widening:
            "window.DugoutSegment = { segment, primeVideo, loadVideo, releaseVideo, seekTo, findSwings, audioPeaks };",
            to: "window.DugoutSegment = { segment, primeVideo, loadVideo, releaseVideo, seekTo, findSwings, audioPeaks, ballBlobs, linkBallTracks, diffEnergy, medianSmooth };")
        try load("js/evaluate.js", widening:
            "window.DugoutEvaluate = {\n    analyzeSwing,",
            to: "window.DugoutEvaluate = {\n    geom, orient, maxDeriv, series, at, between, buildTrack, analyzeSwing,")
        // Poses come from the test, not from MoveNet: frames are passed as {t, blob: index} and the
        // estimate stub returns the pose the test supplied for that index.
        ctx.evaluateScript("""
            window.__poses = [];
            window.DugoutPose.estimate = async (bmp) => window.__poses[bmp.__index] || null;
        """)
        if let jsError { throw LoadError(description: "JS reference failed to load: \(jsError)") }
    }

    private func load(_ path: String, widening anchor: String? = nil, to replacement: String? = nil) throws {
        var source = try String(contentsOf: Self.repoRoot.appendingPathComponent(path), encoding: .utf8)
        if let anchor, let replacement {
            guard source.components(separatedBy: anchor).count == 2 else {
                throw LoadError(description: "\(path): export line changed — update JSReference before trusting parity")
            }
            source = source.replacingOccurrences(of: anchor, with: replacement)
        }
        jsError = nil
        ctx.evaluateScript(source, withSourceURL: URL(fileURLWithPath: path))
        if let jsError { throw LoadError(description: "\(path): \(jsError)") }
    }

    /// Evaluate and return JSON-decoded Foundation value. Async functions: pass an expression that
    /// produces a Promise; it is awaited (JSContext drains microtasks before evaluateScript returns).
    func json(_ expression: String) throws -> Any {
        jsError = nil
        ctx.evaluateScript("""
            window.__out = undefined; window.__err = undefined;
            Promise.resolve().then(() => (\(expression))).then(
              (v) => { window.__out = JSON.stringify(v === undefined ? null : v); },
              (e) => { window.__err = String(e && e.stack || e); });
        """)
        if let err = ctx.evaluateScript("window.__err")?.toString(), err != "undefined" {
            throw LoadError(description: "JS threw: \(err)")
        }
        if let jsError { throw LoadError(description: "JS error: \(jsError)") }
        guard let text = ctx.evaluateScript("window.__out")?.toString(), text != "undefined",
              let data = text.data(using: .utf8) else {
            throw LoadError(description: "JS produced no value for: \(expression.prefix(80))")
        }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Put a Swift value into the JS global scope (via JSON — exact for doubles, ints, strings).
    func set(_ name: String, json value: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        let text = String(decoding: data, as: UTF8.self)
        jsError = nil
        ctx.evaluateScript("window.\(name) = \(text);")
        if let jsError { throw LoadError(description: "set \(name): \(jsError)") }
    }

    /// A large buffer as a JS typed array, handed over without JSON (frames are 130k pixels).
    func setBytes(_ name: String, _ bytes: [UInt8]) {
        setTyped(name, kJSTypedArrayTypeUint8Array, bytes.withUnsafeBytes { Data($0) })
    }

    func setFloat32(_ name: String, _ values: [Float]) {
        setTyped(name, kJSTypedArrayTypeFloat32Array, values.withUnsafeBytes { Data($0) })
    }

    private func setTyped(_ name: String, _ type: JSTypedArrayType, _ data: Data) {
        let count = max(data.count, 1)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
        data.withUnsafeBytes { if let base = $0.baseAddress { buffer.copyMemory(from: base, byteCount: data.count) } }
        var exception: JSValueRef?
        // JS owns the buffer from here; the deallocator runs when the typed array is collected.
        let object = JSObjectMakeTypedArrayWithBytesNoCopy(
            ctx.jsGlobalContextRef, type, buffer, data.count,
            { bytes, _ in bytes?.deallocate() }, nil, &exception)
        ctx.globalObject.setValue(JSValue(jsValueRef: object, in: ctx), forProperty: name)
    }

    private static let shims = """
        var window = globalThis;
        var self = globalThis;
        var console = { log() {}, warn() {}, error() {}, info() {}, debug() {} };
        var navigator = { userAgent: 'JavaScriptCore parity harness' };
        var performance = { now: () => Date.now() };
        function setTimeout(fn) { return 0; }
        function clearTimeout() {}
        function requestAnimationFrame() { return 0; }
        var URL = { createObjectURL: () => 'blob:parity', revokeObjectURL() {} };
        function __ctx2d() { return { drawImage() {}, getImageData() { return { data: new Uint8ClampedArray(4) }; },
          fillRect() {}, clearRect() {}, set fillStyle(v) {}, toBlob() {} }; }
        var document = {
          createElement: () => ({ width: 0, height: 0, style: {}, getContext: __ctx2d,
                                  setAttribute() {}, addEventListener() {}, toBlob() {} }),
          body: { appendChild() {} }
        };
        class Blob { constructor(parts) { this.parts = parts || []; }
          arrayBuffer() { return Promise.resolve(new ArrayBuffer(0)); } }
        window.Blob = Blob;
        // audioPeaks(): the test supplies decoded mono samples + rate through __audio.
        window.__audio = { samples: new Float32Array(0), rate: 48000 };
        class AudioContext {
          decodeAudioData() { return Promise.resolve({ sampleRate: window.__audio.rate,
            getChannelData: () => window.__audio.samples }); }
          close() {}
        }
        window.AudioContext = AudioContext;
        // buildTrack(): frames are {t, blob: index}; the "bitmap" just carries the index through.
        window.__frameSize = { w: 540, h: 304 };
        window.createImageBitmap = async (blob) => ({ __index: blob, width: window.__frameSize.w,
                                                     height: window.__frameSize.h, close() {} });
    """
}

import Foundation
import Network

/// A tiny loopback-only HTTP/1.1 static file server (GET/HEAD) that serves the
/// bundled DugOut web app.
///
/// Why this exists: WKWebView loaded from a file:// URL blocks getUserMedia
/// (in-app round recording) and fetch() of local files (the MoveNet pose
/// model). Serving over http://127.0.0.1 — a secure context — makes camera
/// capture, model loading, <video> range playback, localStorage and IndexedDB
/// all behave exactly like the GitHub Pages deployment.
final class LocalHTTPServer {

    private var listener: NWListener?
    private let docRoot: URL
    private(set) var port: UInt16 = 0

    init(docRoot: URL) {
        self.docRoot = docRoot.standardizedFileURL
    }

    /// Starts the server on the first available port from a fixed list.
    /// A stable first-choice port keeps the web origin — and therefore
    /// localStorage/IndexedDB (profiles, rounds, clips) — stable across launches.
    @discardableResult
    func start() throws -> UInt16 {
        for candidate: UInt16 in [8384, 8484, 8584, 8684, 8784] {
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                params.requiredLocalEndpoint = NWEndpoint.hostPort(
                    host: .ipv4(.loopback),
                    port: NWEndpoint.Port(rawValue: candidate)!
                )
                let l = try NWListener(using: params)
                l.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                l.start(queue: .global(qos: .userInitiated))
                listener = l
                port = candidate
                return candidate
            } catch {
                continue
            }
        }
        throw NSError(domain: "DugOutServer", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "No loopback port available"
        ])
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { connection.cancel(); return }
            var buf = buffer
            if let data = data { buf.append(data) }

            if let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<headerEnd.lowerBound], as: UTF8.self)
                self.respond(connection, requestHead: head)
            } else if error != nil || isComplete || buf.count > 128 * 1024 {
                connection.cancel()
            } else {
                self.receiveRequest(connection, buffer: buf)
            }
        }
    }

    // MARK: - Request → response

    private func respond(_ connection: NWConnection, requestHead: String) {
        let lines = requestHead.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendSimple(connection, status: "400 Bad Request"); return
        }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendSimple(connection, status: "400 Bad Request"); return
        }
        let method = parts[0]
        guard method == "GET" || method == "HEAD" else {
            sendSimple(connection, status: "405 Method Not Allowed"); return
        }

        // Path: strip query/fragment, percent-decode, sanitize.
        var rawPath = parts[1]
        if let q = rawPath.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            rawPath = String(rawPath[..<q])
        }
        let decoded = rawPath.removingPercentEncoding ?? rawPath
        guard !decoded.contains("..") else {
            sendSimple(connection, status: "403 Forbidden"); return
        }
        var relPath = decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded
        if relPath.isEmpty { relPath = "index.html" }

        var fileURL = docRoot.appendingPathComponent(relPath)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
            fileURL.appendPathComponent("index.html")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let full = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            sendSimple(connection, status: "404 Not Found"); return
        }

        // Byte-range support (required for <video> playback through WKWebView).
        var status = "200 OK"
        var body = full
        var extraHeaders = ""
        if let rangeLine = lines.first(where: { $0.lowercased().hasPrefix("range:") }),
           let range = Self.parseRange(rangeLine, totalLength: full.count) {
            status = "206 Partial Content"
            body = full.subdata(in: range)
            extraHeaders = "Content-Range: bytes \(range.lowerBound)-\(range.upperBound - 1)/\(full.count)\r\n"
        }

        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(Self.mimeType(for: fileURL.pathExtension))\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Cache-Control: no-store\r\n"
        header += extraHeaders
        header += "Connection: close\r\n\r\n"

        var response = Data(header.utf8)
        if method == "GET" { response.append(body) }
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendSimple(_ connection: NWConnection, status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Parses "Range: bytes=start-end" (also "start-" and "-suffix" forms).
    static func parseRange(_ line: String, totalLength: Int) -> Range<Int>? {
        guard totalLength > 0,
              let eq = line.firstIndex(of: "="),
              line.lowercased().contains("bytes") else { return nil }
        let spec = line[line.index(after: eq)...]
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: ",")[0]          // first range only
        let ends = spec.components(separatedBy: "-")
        guard ends.count == 2 else { return nil }

        if ends[0].isEmpty {                          // "-suffix": last N bytes
            guard let suffix = Int(ends[1]), suffix > 0 else { return nil }
            let start = max(0, totalLength - suffix)
            return start..<totalLength
        }
        guard let start = Int(ends[0]), start >= 0, start < totalLength else { return nil }
        if ends[1].isEmpty {                          // "start-": to the end
            return start..<totalLength
        }
        guard let end = Int(ends[1]), end >= start else { return nil }
        return start..<min(end + 1, totalLength)
    }

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css":         return "text/css; charset=utf-8"
        case "js", "mjs":   return "text/javascript; charset=utf-8"
        case "json":        return "application/json"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "svg":         return "image/svg+xml"
        case "webp":        return "image/webp"
        case "ico":         return "image/x-icon"
        case "mp4", "m4v":  return "video/mp4"
        case "mov":         return "video/quicktime"
        case "webm":        return "video/webm"
        case "bin":         return "application/octet-stream"
        case "wasm":        return "application/wasm"
        case "woff":        return "font/woff"
        case "woff2":       return "font/woff2"
        case "txt", "md":   return "text/plain; charset=utf-8"
        default:            return "application/octet-stream"
        }
    }
}

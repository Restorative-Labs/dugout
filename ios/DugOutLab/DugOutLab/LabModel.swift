import CoreTransferable
import DugOutCore
import Foundation
import Observation
import UniformTypeIdentifiers

// DugOut Lab — a TEST SCREEN for the native pipeline. It never ships: it is its own app target in
// its own project, not part of DugOut.app or any TestFlight build of it, and its target is set to
// SKIP_INSTALL so an archive of it contains no app.
//
// Privacy (R-13, R-30): the picked video exists only in this app's own temporary folder, only
// while it is being looked at. Everything in that folder — the Lab's copy and the system's copy
// from the Photos picker — is deleted when another video is picked, when "Clear" is tapped, when
// the app leaves the foreground, when an analysis fails, and at every launch. Clearing also
// cancels an analysis in flight, and a result that arrives for a cleared video is thrown away.
// While the app is not active its screen is covered, so the app-switcher snapshot holds no frame.
// Nothing is logged — there is no print, NSLog or os_log anywhere in this target — and nothing is
// sent: there is no networking code and AirPlay is off. Only PASS / FAIL is shown, never a score
// (R-02); DugOutCore's result types keep their internal numbers out of reach (not Codable, hidden
// from reflection).

/// A movie from the Photos picker, moved into the lab's scratch folder.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dir = LabModel.workDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let target = dir.appendingPathComponent("clip-\(UUID().uuidString).\(ext)")
            // the system's copy is ours to take: move it, so only one copy of the video ever exists
            if received.isOriginalFile { try FileManager.default.copyItem(at: received.file, to: target) }
            else { try FileManager.default.moveItem(at: received.file, to: target) }
            return PickedMovie(url: target)
        }
    }
}

@MainActor
@Observable
final class LabModel {
    enum Phase {
        case idle
        case importing
        case analyzing(stage: String, fraction: Double)
        case done(RoundResult)
        case failed(String)
    }

    var phase: Phase = .idle
    private(set) var videoURL: URL?
    /// Bumped by every pick and every Clear. Work started under an older generation is stale: its
    /// result is dropped and its file deleted. Views watch it to pop back to the list.
    private(set) var generation = 0
    private var work: Task<Void, Never>?

    /// Where the Lab keeps the one video it is looking at.
    nonisolated static var workDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DugOutLab", isDirectory: true)
    }

    init() { Self.purge() }

    /// Delete everything in this app's temporary folder, hidden items included: the Lab's copy and
    /// any copy the system made while importing from Photos. Nothing else lives there.
    nonisolated static func purge() {
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: item)
        }
    }

    func clear() {
        newGeneration()
        phase = .idle
        Self.purge()
    }

    /// A new pick is starting: stop and forget the old one. Returns the pick's generation.
    func beginImport() -> Int {
        newGeneration()
        phase = .importing
        return generation
    }

    func importFailed(_ g: Int, _ message: String) {
        guard g == generation else { return }
        phase = .failed(message)
    }

    func analyze(_ movie: PickedMovie, generation g: Int) {
        guard g == generation else {                      // cleared or re-picked while importing
            try? FileManager.default.removeItem(at: movie.url)
            return
        }
        videoURL = movie.url
        phase = .analyzing(stage: "Opening", fraction: 0)
        let url = movie.url
        work = Task.detached(priority: .userInitiated) { [weak self] in
            var shown = (stage: "", fraction: -1.0)
            do {
                let result = try await RoundAnalyzer.analyze(url) { stage, fraction in
                    // one screen update per percent, not one per decoded frame
                    guard stage != shown.stage || fraction - shown.fraction >= 0.01 else { return }
                    shown = (stage, fraction)
                    Task { @MainActor [weak self] in self?.show(.analyzing(stage: stage, fraction: fraction), for: g) }
                }
                await self?.show(.done(result), for: g)
            } catch is CancellationError {
                // cleared: clear() already deleted the file and reset the screen
            } catch {
                await self?.failed(g, deleting: url)
            }
        }
    }

    private func newGeneration() {
        work?.cancel()
        work = nil
        generation += 1
        if let old = videoURL { try? FileManager.default.removeItem(at: old) }
        videoURL = nil
    }

    private func show(_ p: Phase, for g: Int) {
        guard g == generation else { return }
        phase = p
    }

    private func failed(_ g: Int, deleting url: URL) {
        guard g == generation else { return }
        try? FileManager.default.removeItem(at: url)       // nothing is being looked at: don't keep it
        videoURL = nil
        phase = .failed("That video could not be analysed.")
    }
}

import CoreTransferable
import DugOutCore
import Foundation
import Observation
import UniformTypeIdentifiers

// DugOut Lab — a TEST SCREEN for the native pipeline. It never ships: it is its own app target in
// its own project, not part of DugOut.app or any TestFlight build of it.
//
// Privacy (R-13, R-30): the picked video is copied into this app's own temporary folder only for
// as long as it is being looked at, and deleted when another is picked, when "Clear" is tapped,
// when the app goes to the background, and at every launch. Nothing is logged — there is no
// print, NSLog or os_log anywhere in this target — and nothing is sent anywhere: there is no
// networking code. Only PASS / FAIL is shown, never a score (R-02); the scores are not even
// readable from here (they are internal to DugOutCore).

/// A movie from the Photos picker, copied into the lab's scratch folder.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dir = LabModel.workDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = dir.appendingPathComponent("clip-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
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

    /// The only place a video ever sits: this app's own temporary folder.
    nonisolated static var workDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DugOutLab", isDirectory: true)
    }

    init() { Self.purge() }

    /// Delete every copied video.
    nonisolated static func purge() {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    func clear() {
        videoURL = nil
        phase = .idle
        Self.purge()
    }

    func analyze(_ movie: PickedMovie) {
        // only one video at a time on disk
        if let old = videoURL, old != movie.url { try? FileManager.default.removeItem(at: old) }
        videoURL = movie.url
        phase = .analyzing(stage: "Opening", fraction: 0)
        let url = movie.url
        Task.detached(priority: .userInitiated) {
            do {
                let result = try await RoundAnalyzer.analyze(url) { stage, fraction in
                    Task { @MainActor in self.phase = .analyzing(stage: stage, fraction: fraction) }
                }
                await MainActor.run { self.phase = .done(result) }
            } catch {
                await MainActor.run { self.phase = .failed("That video could not be analysed.") }
            }
        }
    }
}

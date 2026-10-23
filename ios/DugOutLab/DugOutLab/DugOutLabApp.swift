import DugOutCore
import PhotosUI
import SwiftUI

@main
struct DugOutLabApp: App {
    @State private var model = LabModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(.dark)
                // covered whenever not active (.inactive comes first), so the app-switcher snapshot
                // the system saves to disk shows no frame and no skeleton (R-30)
                .overlay { if scenePhase != .active { PrivacyCover() } }
        }
        .onChange(of: scenePhase) { _, phase in
            // leaving the app throws the video away — nothing outlives a look at it
            if phase == .background { model.clear() }
        }
    }
}

struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("DugOut Lab").font(.headline).foregroundStyle(.secondary)
        }
    }
}

struct ContentView: View {
    @Bindable var model: LabModel
    @State private var pick: PhotosPickerItem?
    @State private var path: [Int] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Text("Test build — never ships. The video stays on this phone, is deleted when you leave, and nothing is saved, logged or sent.")
                        .font(.footnote).foregroundStyle(.secondary)
                    PhotosPicker(selection: $pick, matching: .videos, photoLibrary: .shared()) {
                        Label("Pick a video", systemImage: "film")
                    }
                }
                content
            }
            .navigationTitle("DugOut Lab")
            .toolbar {
                if model.videoURL != nil { Button("Clear") { model.clear(); pick = nil } }
            }
            .onChange(of: pick) { _, item in
                guard let item else { return }
                let g = model.beginImport()
                Task {
                    do {
                        guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                            model.importFailed(g, "That item is not a video."); return
                        }
                        model.analyze(movie, generation: g)
                    } catch {
                        model.importFailed(g, "That video could not be opened.")
                    }
                }
            }
            // a new pick or a Clear: leave any swing being watched — its video is gone
            .onChange(of: model.generation) { _, _ in path = [] }
            .navigationDestination(for: Int.self) { index in
                if case .done(let result) = model.phase, let videoURL = model.videoURL,
                   let swing = result.swings.first(where: { $0.index == index }) {
                    SwingDetailView(swing: swing, videoURL: videoURL, info: result.segmentation.info)
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .importing:
            Section { ProgressView("Copying the video…") }
        case .analyzing(let stage, let fraction):
            Section { ProgressView(value: fraction) { Text(stage) } }
        case .failed(let message):
            Section { Text(message).foregroundStyle(.orange) }
        case .done(let result):
            RoundSections(result: result)
        }
    }
}

struct RoundSections: View {
    let result: RoundResult

    /// Never call an ungraded round "clean": if no checkpoint could be measured, say so. (The JS
    /// app's composeFeedback() celebrates that case as a clean round — a defect, filed.)
    private var focusLine: String {
        if let f = result.focus { return "Focus: \(Tuning.checkpointLabel[f] ?? f)" }
        let graded = result.roundMarks.values.contains { $0.assessed }
        return graded ? "Focus: none — every graded checkpoint passed" : "Nothing could be graded on this video"
    }

    var body: some View {
        Section("Round") {
            MarksRow(marks: result.roundMarks)
            Text(focusLine).font(.subheadline)
        }
        Section(result.swings.isEmpty ? "No swings found" : "\(result.swings.count) swing\(result.swings.count == 1 ? "" : "s")") {
            ForEach(result.swings, id: \.index) { swing in
                NavigationLink(value: swing.index) { SwingRow(swing: swing) }
            }
        }
        Section {
            Text("Segmentation constants are PROVISIONAL — tuned on Slo-mo footage (CANON R-41).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SwingRow: View {
    let swing: AnalyzedSwing
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Swing \(swing.index + 1) · \(String(format: "%.1f", swing.span.start))–\(String(format: "%.1f", swing.span.end)) s")
                .font(.headline)
            if swing.analysis.ok { MarksRow(marks: swing.marks) }
            else { Text("Not analysed (\(swing.analysis.reason ?? "unknown"))").font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 2)
    }
}

/// The six checkpoints: PASS, FAIL, or — when nothing measurable existed. Never a number (R-02).
struct MarksRow: View {
    let marks: [String: CheckpointMark]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Tuning.checkpoints, id: \.self) { cp in
                let m = marks[cp]
                let text = m.map { $0.assessed ? ($0.pass ? "PASS" : "FAIL") : "—" } ?? "?"
                VStack(spacing: 2) {
                    Text(Tuning.checkpointLabel[cp] ?? cp).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(text).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(text == "PASS" ? Color.green : text == "FAIL" ? Color.orange : Color.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
            }
        }
    }
}

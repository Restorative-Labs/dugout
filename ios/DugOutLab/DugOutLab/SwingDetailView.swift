import AVKit
import DugOutCore
import ImageIO
import SwiftUI

/// One swing: the video looping over the swing window, the body pose drawn over it, and the six
/// marks. Joints Vision is less than 0.3 sure of are drawn faded — the same floor the evaluator
/// uses (POSE_MIN_SCORE), so what looks faded is what the checkpoints ignored.
struct SwingDetailView: View {
    let swing: AnalyzedSwing
    let videoURL: URL
    let info: VideoTrackInfo

    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var overlay: [OverlayFrame] = []
    @State private var now: Double = 0
    @State private var loadingPose = true
    @State private var rate: Float = 0.25
    @State private var observers: [Any] = []
    @State private var endObserver: NSObjectProtocol?
    @State private var overlayTask: Task<[OverlayFrame], Error>?

    /// The picture as displayed (upright), for fitting the overlay to the video.
    private var uprightAspect: CGFloat {
        let quarterTurn = info.orientation == .right || info.orientation == .left
        let w = CGFloat(quarterTurn ? info.height : info.width), h = CGFloat(quarterTurn ? info.width : info.height)
        return h > 0 ? w / h : 16 / 9
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ZStack {
                    if let player {
                        VideoPlayer(player: player) {
                            SkeletonOverlay(frame: nearestFrame(to: now), aspect: uprightAspect)
                                .allowsHitTesting(false)
                        }
                    } else {
                        Color.black
                    }
                    if loadingPose { ProgressView("Reading the pose…").padding().background(.ultraThinMaterial, in: Capsule()) }
                }
                .aspectRatio(uprightAspect, contentMode: .fit)

                Picker("Speed", selection: $rate) {
                    Text("¼×").tag(Float(0.25)); Text("½×").tag(Float(0.5)); Text("1×").tag(Float(1))
                }
                .pickerStyle(.segmented)
                .onChange(of: rate) { _, r in
                    player?.defaultRate = r                          // the play button resumes at this speed
                    if player?.timeControlStatus == .playing { player?.rate = r }
                }

                if swing.analysis.ok {
                    MarksRow(marks: swing.marks)
                } else {
                    Text("Not analysed (\(swing.analysis.reason ?? "unknown"))").foregroundStyle(.secondary)
                }
                Text("Contact at \(String(format: "%.2f", swing.span.contactT)) s\(swing.span.audioConfirmed ? " (heard)" : " (from motion)") · faded joints are under 0.3 confidence")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Swing \(swing.index + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await start() }
        .onDisappear { stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player?.pause() } }
    }

    private func start() async {
        let p = AVPlayer(url: videoURL)
        p.allowsExternalPlayback = false                       // no AirPlay: the video never leaves the phone (R-30)
        p.usesExternalPlaybackWhileExternalScreenIsActive = false
        p.defaultRate = rate
        let startTime = CMTime(seconds: swing.span.start, preferredTimescale: 600)
        await p.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        // left before the player was ready: never start it (it would loop on, unseen and audible)
        guard !Task.isCancelled else { p.pause(); return }

        // loop the swing window. The window can run past the clip's end (end padding is not
        // clamped to the duration), so loop on whichever comes first: the window's end or the clip's.
        let loopEnd = min(swing.span.end, info.duration - 0.05)
        let restart: @Sendable () -> Void = { [weak p] in
            p?.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in p?.rate = p?.defaultRate ?? 0.25 }
        }
        let loop = p.addBoundaryTimeObserver(forTimes: [NSValue(time: CMTime(seconds: loopEnd, preferredTimescale: 600))],
                                             queue: .main, using: restart)
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem,
                                                             queue: .main) { _ in restart() }
        let tick = p.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { t in
            now = t.seconds
        }
        observers = [loop, tick]
        player = p
        p.rate = rate

        let url = videoURL, s = swing.span.start, e = swing.span.end
        let task = Task.detached(priority: .userInitiated) { try await PoseOverlay.frames(url, from: s, to: e) }
        overlayTask = task
        let frames = (try? await task.value) ?? []
        guard !Task.isCancelled else { return }
        overlay = frames
        loadingPose = false
    }

    private func stop() {
        overlayTask?.cancel()
        overlayTask = nil
        if let player { observers.forEach { player.removeTimeObserver($0) }; player.pause() }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        observers = []
        player = nil
    }

    private func nearestFrame(to t: Double) -> OverlayFrame? {
        guard !overlay.isEmpty else { return nil }
        var lo = 0, hi = overlay.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if overlay[mid].t < t { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0, abs(overlay[lo - 1].t - t) < abs(overlay[lo].t - t) { lo -= 1 }
        return abs(overlay[lo].t - t) < 0.2 ? overlay[lo] : nil
    }
}

/// Bones and joints drawn over the aspect-fit video rectangle.
struct SkeletonOverlay: View {
    let frame: OverlayFrame?
    let aspect: CGFloat

    static let bones: [(String, String)] = [
        ("left_shoulder", "right_shoulder"), ("left_hip", "right_hip"),
        ("left_shoulder", "left_hip"), ("right_shoulder", "right_hip"),
        ("left_shoulder", "left_elbow"), ("left_elbow", "left_wrist"),
        ("right_shoulder", "right_elbow"), ("right_elbow", "right_wrist"),
        ("left_hip", "left_knee"), ("left_knee", "left_ankle"),
        ("right_hip", "right_knee"), ("right_knee", "right_ankle"),
        ("nose", "left_shoulder"), ("nose", "right_shoulder"),
    ]

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard let frame else { return }
                // the video is aspect-fit inside the player; place the overlay on the same rectangle
                let box = size.width / size.height > aspect
                    ? CGRect(x: (size.width - size.height * aspect) / 2, y: 0, width: size.height * aspect, height: size.height)
                    : CGRect(x: 0, y: (size.height - size.width / aspect) / 2, width: size.width, height: size.width / aspect)
                func point(_ name: String) -> (CGPoint, Double)? {
                    guard let j = frame.joints[name] else { return nil }
                    return (CGPoint(x: box.minX + j.x * box.width, y: box.minY + j.y * box.height), j.confidence)
                }
                for (a, b) in Self.bones {
                    guard let (pa, ca) = point(a), let (pb, cb) = point(b) else { continue }
                    var path = Path(); path.move(to: pa); path.addLine(to: pb)
                    let faded = ca < Tuning.poseMinScore || cb < Tuning.poseMinScore
                    ctx.stroke(path, with: .color(.yellow.opacity(faded ? 0.25 : 0.9)), lineWidth: 3)
                }
                for name in Pose.jointNames {
                    guard let (p, c) = point(name) else { continue }
                    let r: CGFloat = name.contains("wrist") || name.contains("elbow") ? 5 : 4
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                             with: .color((c < Tuning.poseMinScore ? Color.white.opacity(0.3) : Color.cyan)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

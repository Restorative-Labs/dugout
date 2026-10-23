// swift-tools-version: 6.0
//
// DugOutCore — the native analysis pipeline (Phase 1 of the native rebuild, docs/NATIVE-P1.md).
//
// A Swift package rather than app code so the pipeline can be built, run and tested from the
// terminal on a Mac against real clips, with no phone and no app launch:
//
//     cd ios/DugOutCore
//     swift test                                   # unit tests; real-clip tests skip unless
//                                                  # DUGOUT_CLIPS points at the test-clips folder
//     swift run -c release dugout-probe timeline <clip.mov>
//     swift run -c release dugout-probe pose <clip.mov> --csv <out.csv>
//
// The iOS app target links the library too (ios/DugOut.xcodeproj), so it is compiled for iOS 15
// on every app build — but nothing in the app calls it yet.
import PackageDescription

let package = Package(
    name: "DugOutCore",
    // iOS matches the app's deployment target (do not raise it without saying so). macOS is where
    // the tests run; 12 is the first version with the async AVAsset loading APIs used here.
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "DugOutCore", targets: ["DugOutCore"]),
        .executable(name: "dugout-probe", targets: ["dugout-probe"]),
    ],
    targets: [
        // The tip library ships as data, not code: an exact export of js/library.js.
        .target(name: "DugOutCore", resources: [.copy("Resources/tip-library.json")]),
        // Test-only output (the per-frame pose CSV). Deliberately NOT a product: the app links the
        // DugOutCore library alone, so code that writes keypoints to disk never ships in it.
        .target(name: "ProbeOutput", dependencies: ["DugOutCore"]),
        .executableTarget(name: "dugout-probe", dependencies: ["DugOutCore", "ProbeOutput"]),
        .testTarget(name: "DugOutCoreTests", dependencies: ["DugOutCore", "ProbeOutput"]),
    ],
    // Swift 5 language mode: AVFoundation and Vision types are not yet annotated for Swift 6's
    // strict concurrency checking, and this code is deliberately synchronous, so the stricter
    // mode would add noise without catching anything real here.
    swiftLanguageModes: [.v5]
)

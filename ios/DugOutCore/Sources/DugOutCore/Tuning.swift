import Foundation

/// Every number the pipeline runs on, copied AS-IS from js/config.js.
///
/// PROVISIONAL — ALL OF THEM (CANON R-41). These were tuned on iPhone Slo-mo exports played back
/// ~8× slowed, so every `…Sec` value and every per-frame motion threshold was measured in playback
/// time. Real-time footage (the 1080p / 60 fps clips from 2026-10-15 on) will need them
/// re-measured. Do NOT change one here to make a test pass: a new value is a CANON amendment with
/// a measurement behind it (docs/NATIVE-P1.md).
///
/// `portedConstants` lists them under their config.js names; SegmentParityTests checks every one
/// against the live config.js, so the two cannot drift apart silently.
public enum Tuning {
    // round caps (DUG-34)
    public static let capSeconds = 90.0
    public static let capSwings = 15

    // the spine (R-01)
    public static let checkpoints = ["stance", "load", "stride", "hips", "contact", "finish"]
    public static let checkpointLabel = ["stance": "Stance", "load": "Load", "stride": "Stride",
                                         "hips": "Hips Fire", "contact": "Contact", "finish": "Finish"]
    public static let contactAnchor = 0.62
    public static let phaseWindows: [String: [Double]] = [
        "stance": [0.00, 0.14], "load": [0.12, 0.34], "stride": [0.32, 0.52],
        "hips": [0.50, 0.62], "contact": [0.58, 0.72], "finish": [0.72, 1.00],
    ]

    // pass/fail — internal scores are never displayed (R-02)
    public static let passThresholds: [String: Double] = [
        "stance": 0.6, "load": 0.6, "stride": 0.6, "hips": 0.6, "contact": 0.6, "finish": 0.6,
    ]
    public static let passThresholdDefault = 0.6
    public static let minFaultSwings = 2          // ER-03
    public static let minFaultShare = 0.25

    // segmentation: motion
    public static let motionW = 192, motionH = 108
    public static let motionPixelDelta = 18.0
    public static let motionSmoothSec = 0.24
    public static let motionSmoothWin = 5
    public static let spikeEnterMult = 2.4        // R-14: PROVISIONAL even before R-41
    public static let spikeExitMult = 1.6
    public static let minSwingSec = 0.08

    // segmentation: ball
    public static let ballW = 480, ballH = 270
    public static let ballPixelDelta = 26.0
    public static let ballMinArea = 4
    public static let ballMaxArea = 140
    public static let ballMaxAspect = 3.0
    public static let ballMinTrack = 3
    public static let ballMaxJump = 110.0
    public static let ballMinDisp = 45.0
    public static let ballNearSec = 0.7
    public static let ballMinStraight = 0.82
    public static let ballMinSpeed = 120.0
    public static let ballMaxTracks = 80
    public static let minGapSec = 0.9
    public static let prePadSec = 1.0
    public static let postPadSec = 1.0
    public static let audioConfirmSec = 0.75      // R-21: PROVISIONAL even before R-41
    public static let gateAudioSec = 1.0
    public static let maxSpikeMult = 12.0
    public static let swingTightenSec = 3.0
    public static let keyframesPerSwing = 24
    public static let keyframeWidth = 540

    // pose
    public static let poseSamplesPerSwing = 16
    public static let poseMinScore = 0.3

    public static let ageBands = ["7-10", "11-13", "14-18"]

    /// Not ported, on purpose: KEYFRAME_QUALITY (native keeps no JPEGs), POSE_CROP_PAD /
    /// POSE_CROP_SIZE / MODEL_URL (Vision replaces MoveNet, no crop hack), DEBUG (R-13), and the
    /// UI / profile / feedback-copy settings, which belong to later phases.
    static let portedConstants: [String: Any] = [
        "CAP_SECONDS": capSeconds, "CAP_SWINGS": capSwings,
        "CHECKPOINTS": checkpoints, "CHECKPOINT_LABEL": checkpointLabel,
        "CONTACT_ANCHOR": contactAnchor, "PHASE_WINDOWS": phaseWindows,
        "PASS_THRESHOLDS": passThresholds, "PASS_THRESHOLD_DEFAULT": passThresholdDefault,
        "MIN_FAULT_SWINGS": minFaultSwings, "MIN_FAULT_SHARE": minFaultShare,
        "MOTION_W": motionW, "MOTION_H": motionH, "MOTION_PIXEL_DELTA": motionPixelDelta,
        "MOTION_SMOOTH_SEC": motionSmoothSec, "MOTION_SMOOTH_WIN": motionSmoothWin,
        "SPIKE_ENTER_MULT": spikeEnterMult, "SPIKE_EXIT_MULT": spikeExitMult, "MIN_SWING_SEC": minSwingSec,
        "BALL_W": ballW, "BALL_H": ballH, "BALL_PIXEL_DELTA": ballPixelDelta,
        "BALL_MIN_AREA": ballMinArea, "BALL_MAX_AREA": ballMaxArea, "BALL_MAX_ASPECT": ballMaxAspect,
        "BALL_MIN_TRACK": ballMinTrack, "BALL_MAX_JUMP": ballMaxJump, "BALL_MIN_DISP": ballMinDisp,
        "BALL_NEAR_SEC": ballNearSec, "BALL_MIN_STRAIGHT": ballMinStraight, "BALL_MIN_SPEED": ballMinSpeed,
        "BALL_MAX_TRACKS": ballMaxTracks, "MIN_GAP_SEC": minGapSec,
        "PRE_PAD_SEC": prePadSec, "POST_PAD_SEC": postPadSec,
        "AUDIO_CONFIRM_SEC": audioConfirmSec, "GATE_AUDIO_SEC": gateAudioSec,
        "MAX_SPIKE_MULT": maxSpikeMult, "SWING_TIGHTEN_SEC": swingTightenSec,
        "KEYFRAMES_PER_SWING": keyframesPerSwing, "KEYFRAME_WIDTH": keyframeWidth,
        "POSE_SAMPLES_PER_SWING": poseSamplesPerSwing, "POSE_MIN_SCORE": poseMinScore,
        "AGE_BANDS": ageBands,
    ]
}

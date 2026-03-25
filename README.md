# TriTap Test

The reference and testing app for [TypingAuthSDK](https://github.com/khooten/TypingAuthSDK) — a behavioral biometric authentication system that identifies users by how they type a passcode.

TriTap Test is a development tool for training, testing, and analyzing the typing biometric engine. Use it to enroll your typing pattern, test authentication accuracy, run impostor experiments, and explore per-feature diagnostics.

## What This App Does

### Train
Type your 6-digit passcode 40+ times to build your biometric profile. The app captures 14 measurements per keystroke (timing, touch position, motion, tremor, finger drift) and stores them as raw reference samples on-device.

### Test
Authenticate against your trained profile. The app shows:
- Overall pass/fail with confidence score
- Per-digit match quality (which keystrokes matched and which didn't)
- Score history with visual pass/fail indicators
- Me/Impostor toggle for labeling test attempts

### Diagnostics
Deep analysis of your biometric profile:
- Per-feature tolerance values (adaptive, tightening over time)
- Recent attempt history from SwiftData with per-feature pass/fail indicators
- Feature discrimination analysis (when labeled impostor data is available)
- Block cause tracking — which features are causing rejections

### Continuous Learning
High-confidence passes (80%+ average digit quality) are automatically absorbed as new training samples. The model tightens around your typing patterns over time without manual retraining.

## How It Works

See the [TypingAuthSDK README](https://github.com/khooten/TypingAuthSDK) for the full technical explanation of the AND-gate matching algorithm, relative feature normalization, adaptive per-feature tolerances, and Secure Enclave challenge-response protocol.

### Key Results

In testing with multiple users:
- **Genuine acceptance rate**: ~100% (authorized user passes consistently)
- **Impostor rejection rate**: ~92% per attempt (without seeing scores or having the passcode)
- **With 3-attempt lockout**: Combined impostor success rate drops to near zero
- **No server required**: All biometric data stays on-device

## Building

1. Clone this repo
2. Open `TriTap.xcodeproj` in Xcode
3. The TypingAuthSDK is included as a local Swift Package
4. Build and run on a **real iOS device** (CoreMotion sensors required)

> Note: The app requires a physical device. Simulator builds will compile but motion/tremor features will report zeros.

## Project Structure

```
TriTap/
  TriTap.xcodeproj
  TriTapTest/
    Sources/
      TriTapTestApp.swift  -- App entry point with SwiftData setup
      ContentView.swift    -- Navigation root
      PersonalModeView.swift -- Train/Test/Diagnostics hub
      PersonalCaptureViewController.swift -- UIKit keyboard + capture
      DiagnosticsView.swift -- Feature analysis and attempt history
      AttemptRecord.swift  -- SwiftData models for persistent history
      SwiftDataSampleStore.swift -- SwiftData-backed training sample storage
    Assets.xcassets/
  TypingAuthSDK/           -- Local Swift Package (the biometric engine)
```

## Related Projects

- [TypingAuthSDK](https://github.com/khooten/TypingAuthSDK) -- The core biometric engine (Swift Package)
- [TriTap Auth](https://github.com/khooten/TriTapAuth) -- Production authenticator app with Secure Enclave challenge-response

## Background

This project originated from a bank security engagement investigating FaceID vulnerabilities. The goal: an authentication method that can't be defeated by holding a phone up to someone's face, lifting a fingerprint, or shoulder-surfing a passcode. The result is a system where knowing the passcode isn't enough -- you have to type it the way the authorized user types it.

## Three Factors, One Gesture

| Factor | How TriTap delivers it |
|--------|----------------------|
| **Something you know** | The passcode digits |
| **Something you have** | The specific device (training data is local, non-exportable) |
| **Something you are** | Your unique typing biometrics |

## License

Apache License 2.0 -- see [LICENSE](LICENSE) for details.

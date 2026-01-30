# Gamma Stimulator Changelog

## v1.1.0 - Safety & Quality Update

### Safety Features

#### Epilepsy Warning & Consent
- Added first-launch safety dialog warning about photosensitive epilepsy risks
- Users must acknowledge the warning before using flash features
- Consent is stored and only shown once
- Includes specific warnings about high-risk frequencies (15-25 Hz)

#### Headphone Detection
- App now detects audio output device before starting binaural beats
- Shows warning if using speakers (binaural effect requires stereo headphones)
- Detects headphone disconnection during playback and alerts user
- Supports wired headphones, AirPods, and Bluetooth audio

#### Audio Interruption Handling
- Properly handles phone calls and other audio interruptions
- Automatically pauses stimulation when interrupted
- Posts notifications for UI updates during interruptions

### Bug Fixes

#### Timer Bug Fix
- Fixed sequence timer not accounting for Flow State ramp time
- Changed from `durationMinutes * 60` to `effectiveDurationSeconds`
- Flow State steps now correctly include the 8.5-minute ramp period

#### Proper Mute Implementation
- Removed hacky delayed `setVolume(0)` calls for light-only mode
- Added `muted` parameter to `BinauralBeatGenerator.start()`
- Muted mode now properly skips fade-in

### Code Quality Improvements

#### Type-Safe Notifications
Added `Notification.Name` extensions:
- `.sequenceStarted`
- `.sequencePaused`
- `.sequenceResumed`
- `.sequenceStopped`
- `.sequenceCompleted`
- `.frequencyChanged`
- `.startFrequencySequence`
- `.audioInterrupted`
- `.audioInterruptionEnded`

#### UserDefaults Keys
Added `UserDefaultsKey` constants:
- `safetyConsentGiven`
- `safetyConsentDate`
- `savedSequence`
- `selectedFrequency`
- `lastBackgroundDate`
- `sessionState`

#### Other Improvements
- Removed unused `import Accelerate` from BinauralBeatGenerator
- Fixed force unwraps with safe initialization patterns
- Added `SafetyManager` singleton for consent tracking
- Added `AudioRouteManager` singleton for audio route detection

### Accessibility

#### VoiceOver Support
- Added `accessibilityLabel` to all interactive elements
- Added `accessibilityHint` describing actions
- AuroraView now has `.adjustable` trait for brightness control
- Sequence step cells describe their full configuration

#### Accessible Elements
- Main stimulation view with brightness swipe hints
- Sequence control buttons with state descriptions
- Sequence step cards with frequency, duration, and mode info
- Add/Edit segment form controls

### New Features

#### Tap-to-Edit Sequences
- Sequence step cards can now be tapped to edit
- Edit sheet pre-populates all fields with existing values
- Header changes to "Edit Segment" in edit mode
- Button changes to "Save Changes" in edit mode

#### Session State Persistence
- Sessions are saved when paused or backgrounded
- Can resume sessions after app restart (within 1 hour)
- Shows "Resume Previous Session?" alert on restore
- Tracks `currentStepIndex`, `remainingSeconds`, `stepStartDate`

### Files Changed

| File | Changes |
|------|---------|
| `AppModels.swift` | SafetyManager, AudioRouteManager, Notification.Name, UserDefaultsKey |
| `ViewController.swift` | Safety warning, headphone check, interruption handling, accessibility |
| `BinauralBeatGenerator.swift` | Removed Accelerate, added `start(muted:)` |
| `FrequencySequenceManager.swift` | Timer fix, session persistence, `updateStep()` |
| `SequenceBuilderViewController.swift` | Tap-to-edit, accessibility |
| `AddSequenceStepViewController.swift` | Edit mode support, accessibility |

---

## v1.0.0 - Initial Release

- Gamma wave stimulation via synchronized light and audio
- Support for Delta (2Hz), Theta (6Hz), Alpha (10Hz), Beta (17Hz), Gamma (40Hz)
- Binaural beat generation with dual-carrier mode
- Flow State program with automatic frequency ramping (14→12→10→8 Hz)
- Resonate Binaural mode (0.5 Hz ultra-slow)
- Visual stimulation via screen flash and LED torch
- Sequence builder for multi-step stimulation protocols
- Apple Watch integration for sleep monitoring
- Sleep stage detection via accelerometer
- Automatic stimulation during deep sleep phases

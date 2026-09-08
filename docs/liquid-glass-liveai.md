# Live AI Liquid Glass redesign

Implemented 2026-09-08 from the approved three-screen concept. Voice mode follows the system light/dark theme, with coral user messages and neutral assistant cards. Vision mode uses the current glasses frame with a dark contrast treatment, glass message cards and a glass header. The mode selector and bottom hide/show/end dock use native iOS 26 regular glass. Device name/link status comes from `GlassesDeviceStatus`; AI connection/listening/response status is displayed separately. Voice mode does not render any residual video frame.

`LiveAIView` remains the lifecycle adapter. Its startup, disappearance, stop-reason and error-alert block is unchanged from the previous version. Mode/stop actions still call `LiveAIManager`; no backend, permissions, persistence, provider or shortcut changes were made. `LiveAIDashboard` takes value inputs and action closures so fixtures can render without instantiating the manager or starting audio, network or camera work. The waveform is an activity symbol, not an audio-level meter. It stops animating when Reduce Motion is enabled.

Controls are bounded at Dynamic Type XXXL to preserve usable mode and stop actions; message text keeps the full accessibility size. Device names truncate visually with a complete accessibility label. Top metadata and privacy disclosure stay outside the transcript viewport; content can still scroll behind the bottom glass dock. Reduce Transparency falls back to opaque surfaces. Added dashboard strings are available in Chinese and English.

## Validation

- Final simulator appearance XCTest passed: `/tmp/liveai-glass-layout-final.xcresult`. Seven scenarios: voice light/dark, vision, largest Dynamic Type plus long device name, English, no device and AI connecting. Largest-text scrolling checks the settled bottom position after LazyVStack resolves row heights.
- Reduce Transparency XCTest passed with the actual simulator setting enabled: `/tmp/liveai-glass-reduced.xcresult`; setting restored to off. This capture predates the final top-viewport separation but uses the same fallback material.
- Final signed physical-device build passed: `/tmp/liveai-glass-ready-device.log`; app at `/tmp/turbometa-home-device-build/Build/Products/Debug-iphoneos/CameraAccess.app`.
- Localization plist syntax and diff whitespace checks passed.
- Screenshots in `screenshots/liveai-liquid-glass/` are actual SwiftUI renders with test-only conversations and the existing plant image fixture. They are not captures of a real glasses session.

## Remaining device checks

After reconnecting the authorized iPhone, the latest build passed (`/tmp/liveai-phone-build.log`) and this redesign was installed successfully. Automatic launch was denied because the phone was locked. Verify actual hide/show, mode switching and failed switching, stream updates, speech playback, end-session and foreground/cold-start shortcuts after reconnecting. Appearance tests do not claim an end-to-end session regression. Small-screen hardware and VoiceOver speech have not been manually exercised. No real personal conversation data was modified during tests.

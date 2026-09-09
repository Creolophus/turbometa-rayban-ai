# TurboMeta · Ray-Ban Meta AI Assistant (Fork)

English | [简体中文](README.md)

> **This repository is a modified fork of [Turbo1123/turbometa-rayban-ai](https://github.com/Turbo1123/turbometa-rayban-ai), not an independently created project built from scratch.** Thanks to Turbo1123 and the upstream contributors for the foundation. This fork is maintained at [Creolophus/turbometa-rayban-ai](https://github.com/Creolophus/turbometa-rayban-ai), primarily for iOS UI, interaction and reliability improvements. Visit upstream for its release history and author support channels.

TurboMeta connects to glasses through the Meta Wearables DAT SDK and provides AI conversations, image recognition, translation and voice notes. Cloud features require your own provider account and API keys.

## Interface preview

<div align="center">
  <img src="screenshots/home-liquid-glass-dark.png" width="390" alt="TurboMeta iOS Home in dark mode" />
  <p>iOS Home · Liquid Glass dark mode</p>
</div>

## Changes in this fork

| Area | Changes |
| --- | --- |
| iOS interface | Consistent Liquid Glass styling for Home, Records, Live AI and translation, with system light/dark themes |
| Device status | Actual glasses name and connection state on Home |
| 3D glasses | Drag to rotate and double-tap to expand; approximately 30,000 triangles on Home, original detail in full-screen; cached still image when idle |
| Records | Grouped content and category filters, with scrolling behind a fixed glass filter bar |
| Translation reliability | Explicit failure, empty and timeout states; improved source/response association, graceful completion, playback queue and background persistence |
| Translation interface | Audio-only translation, removal of visual enhancement, scrolling behind the glass language bar, and local metadata-only diagnostics |

These UI and model changes target iOS. Android does not automatically receive them. CPU and memory improvements from model reduction still require device measurements; triangle reduction does not imply proportional resource savings.

## Features and platforms

- **Live AI:** real-time multimodal conversations using glasses audio and video.
- **Quick Vision:** photo recognition with Siri / Shortcuts entry points.
- **Live translation:** selectable languages and microphone; speech output depends on the target language and provider configuration.
- **Voice notes:** recording, transcription and local record management.
- **Explore:** OpenClaw, live streaming, RTMP and LeanEat entry points; availability depends on the current version. WordLearn remains planned.
- **Records and gallery:** access and manage locally saved content.

The iOS app uses SwiftUI, RealityKit, Combine and Meta Wearables DAT SDK. Android uses Kotlin and Jetpack Compose; see the [Android README](android/README.md). Packages published in upstream Releases are upstream builds and do not necessarily include this fork's changes.

## Build and run on iOS

### Requirements

- Xcode with the iOS 26 SDK (Xcode 26 or later).
- An iPhone running iOS 26.0 or later. Simulators support some UI and offline tests; glasses integration needs a physical device.
- Apple signing configuration, Meta Wearables developer configuration and compatible glasses.

### Setup

```bash
git clone https://github.com/Creolophus/turbometa-rayban-ai.git
cd turbometa-rayban-ai
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
open CameraAccess.xcodeproj
```

1. Create an application in the [Meta Wearables Developer Center](https://wearables.developer.meta.com/).
2. Set `META_APP_ID`, `CLIENT_TOKEN`, `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER` in your local `Config/Secrets.xcconfig`. This file is Git-ignored; do not commit credentials.
3. Pair glasses in the Meta companion app and enable developer / DAT SDK preview configuration as required by current Meta documentation.
4. Select the **TurboMeta** scheme, your signing Team and the connected iPhone in Xcode, then run.
5. Configure AI providers and API keys in TurboMeta Settings and grant permissions required by the features you use.

Build and test from the command line, replacing the simulator name with an installed device:

```bash
xcodebuild -project CameraAccess.xcodeproj -scheme TurboMeta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

xcodebuild test -project CameraAccess.xcodeproj -scheme TurboMeta \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Create Alibaba Cloud keys in the [Model Studio console](https://bailian.console.aliyun.com/) and enter them in the app. Use the matching settings for other providers. Region, model support, quota and network availability affect feature availability. Never hardcode or commit API keys.

## Usage notes

- **Home model:** drag to rotate, double-tap to expand; pinch to zoom and reset in full-screen.
- **Translation:** check the language direction before starting. Allow completion after stopping; an empty or incomplete result is not a successful translation.
- **Quick Vision:** open the app once to complete setup, then add its action in Apple Shortcuts. Lock-screen, background and camera access depend on iOS and Meta SDK restrictions.
- **OpenClaw:** enter your Gateway address, port and token in Settings and complete device pairing on the gateway. Consult the [official OpenClaw documentation](https://docs.openclaw.ai/) for deployment and access control.

For connection issues, check companion-app pairing, permissions and developer configuration. For AI failures, check connectivity, keys, region and quota. Include device, OS version and reproduction steps when reporting issues; remove credentials and private content from logs.

## Data and diagnostics

- Conversations, translations, notes and photos may be saved locally by their respective features and managed in the corresponding screens.
- Cloud AI features send relevant audio, images or text to the selected provider. This is not a fully offline application.
- Persistent translation diagnostics contain time, event associations, status, output lengths and elapsed time, but no source text, translated text or audio.
- Diagnostic files live under `Library/Application Support/TurboMeta/Diagnostics/` in the app container. They rotate across two approximately 1 MB files; files unmodified for over seven days are removed on a subsequent write. Diagnostics are excluded from system backups and stored separately from translation history.

## Development documentation

- [iOS architecture and development guide](docs/ios-secondary-development-guide.md)
- [Meta DAT SDK 0.6.0 migration](docs/meta-dat-sdk-0.6.0-migration.md)
- [Home design](docs/liquid-glass-home.md) · [Records design](docs/liquid-glass-records.md) · [Live AI design](docs/liquid-glass-liveai.md)
- [Wayfarer assets, simplification script and validation](docs/wayfarer/README.md)
- [Translation audit and fixes](docs/reviews/live-translate-audit-2026-09-09.md)

Design notes and older screenshots may describe previous iterations. Current code and running builds are authoritative. Successful builds and model-format checks do not replace functional or performance testing on a device.

## Contributions, attribution and license

Report issues specific to this fork through [this repository's Issues](https://github.com/Creolophus/turbometa-rayban-ai/issues) or a pull request. Confirmed general upstream issues may also be reported to the original repository.

- **Direct upstream:** [Turbo1123/turbometa-rayban-ai](https://github.com/Turbo1123/turbometa-rayban-ai). Credit for the foundation remains with its author and contributors.
- **SDK and sample code:** Meta Platforms, Inc. provides the Meta Wearables DAT SDK and related samples, subject to their respective terms.
- **License:** [MIT License](LICENSE), retaining `Copyright (c) 2025 Turbo1123`. Changes in this fork do not replace upstream attribution or alter third-party SDK and asset license terms.

Thanks to the upstream author, contributors, SDK developers and service providers.

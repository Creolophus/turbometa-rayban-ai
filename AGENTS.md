# Repository Guidelines

## Project Structure & Module Organization

TurboMeta has two mobile clients. The iOS SwiftUI app lives in `CameraAccess/`, organized into `Views/`, `ViewModels/`, `Services/`, `Managers/`, `Models/`, and `Utilities/`; images and colors are in `Assets.xcassets`, while translations are in `en.lproj` and `zh-Hans.lproj`. iOS integration tests and fixtures are under `CameraAccessTests/`. The Xcode project and shared scheme are in `CameraAccess.xcodeproj`.

The Android Jetpack Compose app is rooted at `android/`. Kotlin sources are in `android/app/src/main/java/com/smartview/glassai/`, resources in `android/app/src/main/res/`, and dependency versions in `android/gradle/libs.versions.toml`. Repository screenshots and promotional artwork belong in `screenshots/` and `ad/`.

## Build, Test, and Development Commands

- `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` creates the required local iOS signing/Meta configuration.
- `open CameraAccess.xcodeproj` opens the iOS app; select the shared `TurboMeta` scheme and a physical iPhone or simulator.
- `xcodebuild -project CameraAccess.xcodeproj -scheme TurboMeta -destination 'platform=iOS Simulator,name=iPhone 16' build` performs a command-line iOS build. Adjust the simulator name to one installed locally.
- `xcodebuild test -project CameraAccess.xcodeproj -scheme TurboMeta -destination 'platform=iOS Simulator,name=iPhone 16'` runs XCTest.
- `cd android && ./gradlew assembleDebug` builds a debug APK.
- `cd android && ./gradlew test lint` runs Android unit checks and lint; `./gradlew installDebug` installs on a connected device.

## Coding Style & Naming Conventions

Follow the surrounding Swift or Kotlin style; use four-space indentation in production sources and keep one primary type per file. Name types and SwiftUI/Compose views in `UpperCamelCase`, functions and properties in `lowerCamelCase`, and tests as `testBehaviorUnderCondition`. Preserve the existing MVVM split: UI state belongs in view models, external calls in services, and persisted models in `Models/` or `data/`. No repository-wide formatter is configured, so use Xcode/Android Studio formatting and keep imports tidy.

## Testing Guidelines

iOS tests use XCTest and the Meta mock-device SDK. Add focused tests to `CameraAccessTests/`, place media fixtures in `CameraAccessTests/Assets/`, and avoid real network credentials. Android currently has no committed test suite; new logic should add JVM tests under `android/app/src/test/` or instrumentation tests under `android/app/src/androidTest/`.

## Commit & Pull Request Guidelines

History follows Conventional Commit prefixes such as `feat:`, `fix:`, `docs:`, and `chore:`; keep subjects concise and scoped to one change. Pull requests should explain behavior and platform impact, list verification commands/devices, link related issues, and include screenshots or recordings for UI changes. Never commit `Config/Secrets.xcconfig`, API keys, tokens, signing files, or generated build artifacts.

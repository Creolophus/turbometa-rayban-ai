# iOS Records Liquid Glass redesign

Implemented 2026-09-08. Records now opens a combined chronological archive, with full-text search and All / Live AI / Translation / Notes / Vision filters. LeanEat and WordLearn are also available as filters, each opening a simple Coming soon page without records or deletion actions. Day groups use rounded surfaces, colored category icons and saved vision thumbnails. The existing detail views remain in use. Selection is scoped to visible search results; changing a query clears selection and changing a filter exits selection. Deletion requires confirmation. Translation rows represent complete sessions; deletion reloads the session so newly appended turns are included. Failed persistence leaves remaining records visible and reports failure.

`RecordEntry` adapts existing persisted models, with category + UUID identity. `RecordsLibraryViewModel` aggregates, searches, groups and manages selection through an injectable store. Conversation and vision writes publish refresh notifications; translation notifications and audio library updates also refresh the archive. No storage migration or Android changes.

## Validation

- TurboMeta simulator build: passed (iOS 26.5, iPhone 17 Pro).
- TurboMeta signed physical-device build: passed, `/tmp/turbometa-home-device-build/Build/Products/Debug-iphoneos/CameraAccess.app`.
- Seven RecordsLibraryTests passed: chronology/day grouping/deduplication, cross-category UUID isolation, complete-text search/filter intersection, visible-only selection, current-data deletion, failure handling, edited-note refresh and whole-session translation deletion including new turns.
- RecordsVisualTests passed: light, dark, English, largest accessibility text size, selection and empty state; largest-text archive scrolls to the last record. Final attachments include saved plant-thumbnail rendering.
- Screenshots under `screenshots/records-liquid-glass/` are actual SwiftUI renders hosted in a simulator with a native TabView and test-only records. They do not contain personal records or seed the production stores. Other tabs in this visual harness are placeholders.
- Project/localization plist syntax and `git diff --check`: passed.
- Results: `/tmp/records-final-tests.xcresult` (7 data tests + appearance test), `/tmp/records-visual-final.xcresult` (final thumbnails and scroll verification).

## Remaining device verification

After reconnecting the authorized iPhone 17 Pro, the latest signed build (including LeanEat and WordLearn placeholders) was installed successfully on 2026-09-08. Automatic launch was denied because the phone was locked. Unlock and open TurboMeta to verify real-record detail navigation, media playback and confirmed deletion. These interactions were preserved in code but were not manually exercised on personal data. Small-screen hardware, VoiceOver speech and Reduce Transparency device checks remain unverified for this tab.


## Fixed glass filters (2026-09-08)

The archive now scrolls behind a fixed native regular-glass capsule below search. The capsule belongs to the horizontal viewport, so the glass stays fixed while its seven filter buttons scroll. Measured filter height drives top scroll-content margins, including Dynamic Type. A 12pt top fade softens the content boundary without letting records draw over search. Reduce Transparency uses an opaque card background.

Simulator appearance tests passed for light/dark, English, largest Dynamic Type, selection, empty archive, search and both coming-soon pages. Scroll checks cover initial position, 150pt overlap, bottom and return to top. Reduce Transparency was enabled through device settings, verified by XCTest and restored to off afterward. Screenshots are in `screenshots/records-liquid-glass/filters/`; fixture records remain test-only. Results: `/tmp/records-glass-final.xcresult` and `/tmp/records-glass-reduced.xcresult`. Signed device build passed (`/tmp/records-glass-device-final.log`).

After reconnection, this follow-up was built and installed successfully on the physical iPhone 17 Pro (`/tmp/records-glass-phone-build.log`). The subsequent launch attempt returned CoreDevice 4016 because connectivity became unavailable. Actual touch-gesture arbitration and device visual checks remain pending; automated screenshots exercise layout and programmatic scrolling, not finger gestures. The installed app can be opened manually.

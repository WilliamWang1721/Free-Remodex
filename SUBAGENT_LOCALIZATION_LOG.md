# Sub-Agent Localization Log

## Summary
Implemented Simplified Chinese localization groundwork for the owned mobile surface by adding a `zh-Hans.lproj` resource bundle, a minimal formatted-string helper, and a broad first-pass translation across onboarding, home, about, and sidebar flows.

## What Was Translated
- Onboarding flow: welcome copy, features page, setup steps, CTA labels.
- Home surface: connection-state labels, reconnect/update guidance, bridge update sheet copy, notification accessibility copy.
- Sidebar surface: empty states, project picker copy, archive/delete confirmations, settings status labels, relative-time labels, subagent affordances, search/new chat labels.
- About screen: major explanatory sections, architecture labels, pairing/security copy, encryption specs, resilience and desktop integration copy.
- Runtime-generated strings: formatted labels such as `STEP %d`, `Archived (%d)`, `Show %d more`, archive/delete dialog titles, relative-time labels, diff accessibility values, and reconnect/error fallback strings in `Views/Home/ContentViewModel.swift`.

## Infrastructure Added
- Added `CodexMobile/CodexMobile/zh-Hans.lproj/Localizable.strings` for Simplified Chinese resources.
- Added `CodexMobile/CodexMobile/RemodexLocalization.swift` with a tiny `L10n` helper for formatted runtime strings that SwiftUI literals do not localize automatically.
- Updated helper-driven views to use `LocalizedStringKey` or `L10n.string(...)` where plain runtime `String` values would otherwise stay English.

## Remaining Work
- Strings outside this ownership boundary are still not part of this first pass, including non-owned surfaces such as main conversation/turn UI, broader settings/account flows, QR pairing entry surfaces outside `Views/Home/*`, and service-layer/server-driven copy not exposed through this owned view set.
- `SettingsView.swift` was intentionally not edited because it already has active unrelated changes and was outside the safe path unless a narrow string-only edit became necessary.
- Server-provided strings like `prompt.title`, `prompt.message`, and arbitrary error payloads will only localize if their upstream producers are localized separately.

## Files Touched
- `CodexMobile/CodexMobile/RemodexLocalization.swift`
- `CodexMobile/CodexMobile/zh-Hans.lproj/Localizable.strings`
- `CodexMobile/CodexMobile/Views/AboutRemodexView.swift`
- `CodexMobile/CodexMobile/Views/Onboarding/OnboardingView.swift`
- `CodexMobile/CodexMobile/Views/Onboarding/OnboardingFeaturesPage.swift`
- `CodexMobile/CodexMobile/Views/Onboarding/OnboardingStepPage.swift`
- `CodexMobile/CodexMobile/Views/Home/ThreadCompletionBannerView.swift`
- `CodexMobile/CodexMobile/Views/Home/HomeEmptyStateView.swift`
- `CodexMobile/CodexMobile/Views/Home/BridgeUpdateSheet.swift`
- `CodexMobile/CodexMobile/Views/Home/ContentViewModel.swift`
- `CodexMobile/CodexMobile/Views/SidebarView.swift`
- `CodexMobile/CodexMobile/Views/Sidebar/ArchivedChatsView.swift`
- `CodexMobile/CodexMobile/Views/Sidebar/SidebarFloatingSettingsButton.swift`
- `CodexMobile/CodexMobile/Views/Sidebar/SidebarRelativeTimeFormatter.swift`
- `CodexMobile/CodexMobile/Views/Sidebar/SidebarThreadGrouping.swift`
- `CodexMobile/CodexMobile/Views/Sidebar/SidebarThreadListView.swift`
- `CodexMobile/CodexMobile/Views/Sidebar/SidebarThreadRowView.swift`

## Validation
- Attempted an `xcodebuild` simulator build for compile validation.
- The build process did not return output in this environment during the session window, so final compile confirmation is still pending.

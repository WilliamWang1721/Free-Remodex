# Subagent Model Runtime Work Log

## Changes
- Extended custom model persistence to store reasoning configuration mode and custom reasoning-level labels.
- Added support for inherited default reasoning levels and custom raw/display-name reasoning levels in the Settings custom-model editor.
- Updated runtime model merging so a selected thread model can stay available as a synthetic placeholder even when it is missing from the current runtime model list.
- Synced active runtime selections from source/resumed threads so continuation, reuse, and fork flows keep the thread's model identifier, reasoning effort, and service tier behavior.

## Files Touched
- `CodexMobile/CodexMobile/Models/CodexModelOption.swift`
- `CodexMobile/CodexMobile/Models/CodexReasoningEffortOption.swift`
- `CodexMobile/CodexMobile/Services/CodexService+RuntimeConfig.swift`
- `CodexMobile/CodexMobile/Services/CodexService+ThreadsTurns.swift`
- `CodexMobile/CodexMobile/Views/Turn/TurnComposerMetaMapper.swift`
- `CodexMobile/CodexMobile/Views/SettingsView.swift`
- `SUBAGENT_MODEL_RUNTIME_LOG.md`

## Verification
- Attempted `xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'generic/platform=iOS' -derivedDataPath /tmp/remodex-derived-2 CODE_SIGNING_ALLOWED=NO build`.
- The build progressed into project compilation but failed in the existing asset-catalog step (`Remodex.icon` / `actool`) before a clean end-to-end app build could complete.

## Open Risks
- Composer views outside the owned file set still derive some labels from raw reasoning-effort strings, so custom display names are guaranteed in Settings and persisted data, but may not appear everywhere until those non-owned call sites are updated.
- Thread-specific reasoning/service-tier inheritance depends on locally persisted override records; if an older thread never stored those overrides, the app can preserve its model name but may fall back to the current/default reasoning or speed selection.
- The worktree already contained unrelated edits in several owned files before this task; overlap risk is highest if another agent is also changing model/runtime selection logic in the same files.

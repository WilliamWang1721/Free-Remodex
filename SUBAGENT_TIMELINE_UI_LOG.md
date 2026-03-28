# Subagent Timeline UI Log

## Summary
- Added timeline task-activity grouping so completed tool/task phases collapse into a compact summary row with elapsed time and a show/hide control.
- Held assistant final-answer prose while it is still streaming, so the answer appears only after completion instead of token-by-token.
- Fixed markdown rendering by letting parsed attributed markdown preserve bold emphasis and paragraph spacing instead of overriding it with a single font modifier.
- Tuned adaptive glass surfaces toward a brighter, whiter, less transparent treatment for chat/composer UI.

## Files Touched
- `CodexMobile/CodexMobile/Views/Turn/TurnTimelineReducer.swift`
- `CodexMobile/CodexMobile/Views/Turn/TurnTimelineView.swift`
- `CodexMobile/CodexMobile/Views/Turn/TurnMessageComponents.swift`
- `CodexMobile/CodexMobile/Views/Shared/AdaptiveGlassModifier.swift`
- `SUBAGENT_TIMELINE_UI_LOG.md`

## Change Details
- `TurnTimelineReducer.swift`
  - Added `TurnTimelineTaskPhaseGroup` and grouping logic for contiguous task/tool system activity that immediately precedes a finalized assistant answer.
- `TurnTimelineView.swift`
  - Added summary-row rendering for grouped task activity.
  - Added per-group expand/collapse state.
  - Added compact elapsed-time formatting for the collapsed summary.
- `TurnMessageComponents.swift`
  - Assistant streaming rows now hide prose until the message is finalized.
  - Message row equality now ignores streaming assistant text churn so hidden final-answer deltas do not force unnecessary row redraws.
  - Markdown text rendering now preserves parsed markdown emphasis and spacing.
- `AdaptiveGlassModifier.swift`
  - Added a brighter base fill and subtle border to reduce liquid-glass transparency and increase readability on chat/composer surfaces.

## Verification
- Reviewed diffs in the owned files after patching.
- `git diff --check` passed for the touched files.
- Attempted `xcodebuild` and `swiftc -parse` verification, but both commands stalled in this sandbox without returning actionable output.

## Open Risks
- The task-activity collapse currently groups contiguous system activity directly before a completed assistant answer within the visible timeline slice. If a future server flow interleaves additional non-collapsible system rows in that region, those rows will remain outside the summary.
- Markdown now favors formatting correctness over forcing the selected prose font onto every markdown run, so assistant markdown may follow the system’s attributed markdown typography more closely than other app prose.

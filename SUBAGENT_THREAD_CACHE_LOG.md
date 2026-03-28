# Thread Cache Work Log

## Summary
- Added an encrypted on-device thread-list cache snapshot so the mobile chat/thread list can hydrate immediately on cold launch and reconnect.
- Restored cached threads during `CodexService` initialization before live sync, while preserving local archive/delete flags and persisted thread renames/fork ancestry.
- Updated thread-list sync to do one authoritative full-list reconciliation after reconnect when cached threads exist, then fall back to the existing lightweight incremental polling.
- During authoritative reconciliation, server-missing threads that were previously known from server list state are removed locally, while local-only placeholders still survive normal incremental polls.

## Files Touched
- `CodexMobile/CodexMobile/Services/CodexMessagePersistence.swift`
- `CodexMobile/CodexMobile/Services/CodexService.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Sync.swift`

## Details
- `CodexMessagePersistence.swift`
  - Added `CodexThreadListCacheSnapshot` and `CodexThreadListPersistence`.
  - Stores the thread cache in Application Support as encrypted `codex-thread-list-v1.bin` using a dedicated Keychain-backed AES key (`codex.local.threadListKey`).
  - Persists both visible cached threads and the set of thread ids last observed from server thread-list responses.
- `CodexService.swift`
  - Added init-time hydration from the thread-list cache.
  - Added fallback reconstruction from persisted message timelines when no thread-list cache file exists yet, so upgrades can still show a non-empty list before the first successful sync.
  - Reapplies persisted local decorations after hydration: archived state, deleted filtering, rename overrides, and stored fork origins.
  - Added debounced persistence for both thread array changes and cached server-thread-id changes.
- `CodexService+Sync.swift`
  - Added `hasPerformedThreadListSyncSinceConnect` reset in `clearHydrationCaches()` so each reconnect can do one authoritative reconciliation pass.
  - First post-connect sync now fetches the full active + archived server list when cached local threads exist; later syncs keep using the prior recent-list limit.
  - Reconciliation now updates the cached server-thread-id set, keeps local-only rows during incremental polling, and removes server-missing cached rows during authoritative refresh.
  - Local removals now also drop the removed id from cached server-thread-id metadata.

## Migration / Compatibility
- Existing message history persistence is unchanged.
- Existing installs with no thread-list cache file will synthesize a temporary thread list from persisted message timelines on first launch after upgrade, then persist the new thread-list cache for later launches.
- No schema migration is required for old installs because absence of `codex-thread-list-v1.bin` is treated as "no cache yet".

## Open Risks
- The first reconnect after hydrating only from message-history fallback treats those synthesized thread ids as candidates for authoritative cleanup; if any truly local-only placeholder thread ids exist outside server truth, they may be removed on that first full sync.
- I did not change manual `listThreads(limit:)` outside the owned files, so the stronger deletion cleanup behavior is guaranteed on reconnect/startup sync but not on every other code path that asks for a limited manual list refresh.
- `xcodebuild` verification was started but did not finish within the available turn time, so compile verification is still inconclusive.

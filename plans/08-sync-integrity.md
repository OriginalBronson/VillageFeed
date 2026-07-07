# Plan 08 — Sync Integrity & Offline Resilience

The sync layer is deliberately "best-effort last-write-wins" (`SyncService.swift`
says so, and flags 'no offline queue/retry' in a comment). That was right for a
prototype. With real users, three of the current behaviors are silent data loss, and
data loss in this app means *someone's dinner plans evaporate* — worse than a crash,
because nobody knows it happened.

## Bugs found in review (fix before launch, independent of the bigger work)

### B1. `pushProfile` erases remote photos
`pushProfile` only sets `photo_path` when `me.photo` is `.data(...)` (a freshly picked
image). After a pull, photos come back as `.remote(url)` — so the next profile push
(any bio edit → Submit for review) writes `photo_path: nil` and **deletes the user's
photo pointer server-side**. Same logic hole for every dish photo in the loop below
it. Fix: carry the existing `photo_path` through the round-trip (store it on the
model or resolve `.remote` URLs back to paths) and only overwrite when there's new
`.data`.

### B2. Delete-then-insert dish sync loses dishes on partial failure
`pushProfile` does `delete all my dishes` → `insert current dishes`. A network drop
between the two leaves the account dish-less on the server, and the next pull
propagates the loss back to the device. Fix: upsert by dish id + delete only ids no
longer present (or wrap in an RPC so it's transactional server-side).

### B3. Match truth computed twice, differently
`AppStore.swipe` decides "matched!" from local `likesYou` while
`SyncService.recordSwipe` separately computes `mutual_like` server-side and writes
the match row — fire-and-forget, result discarded. The user can see a celebration
sheet for a match that never persisted (or miss one that did). Fix: in synced mode,
the server RPC's answer *is* the outcome — await it for the sheet (sub-second), and
have plan 04's push notification cover the crossing-swipes race.

## The structural fix: a tiny outbox

Every mutation today is `Task { await sync?.foo() }` with `try? / log`. Any failure
(elevator, dead spot, Supabase blip) silently drops a swipe, message, block, or
report — **blocks and reports are safety actions; those failing silently is the worst
version of this**.

Design (deliberately small — not a sync framework):

- `Outbox`: an ordered, persisted queue of pending operations
  (`enum PendingOp: Codable` — swipe, message, block, report, joinGroup, leaveGroup,
  pushProfile…), stored in the existing JSON snapshot alongside everything else.
- All `AppStore` mutations enqueue instead of firing Tasks; a single drainer sends
  ops in order, removes on success, retries with backoff on failure, and drains on:
  app foreground, connectivity regained (`NWPathMonitor`), and after each pull.
- Server side is already safe for this: swipes/blocks/members are upserts,
  messages insert by client-generated UUID — so retries are idempotent today.
  Keep that property as new ops get added (plans 05/07).
- UI: nothing new except plan 03-X3's "showing saved data" banner and plan 07's
  failed-message retry state, both of which read outbox state.

## Pull-side gaps

- **Realtime resilience**: the message subscription is opened once at sign-in and
  never re-established after a socket drop or long background. On foreground
  (`scenePhase == .active`): re-pull + resubscribe. (Today foregrounding does
  nothing; only backgrounding persists.)
- **Pull clobbering local edits**: `applyRemote` replaces `people`/`groups`
  wholesale. Fine for others' data; but my own membership changes still in the
  outbox must be re-applied on top of a pull (drain-then-pull ordering handles most
  of it — document the invariant and test it).
- The 500-message pull cap will silently truncate history for chatty groups —
  becomes plan 07's pagination; noted here so pagination lands with sync, not UI-only.

## Testing hooks (feeds plan 11)

The `SyncService` is concrete and untested. Extract a `SyncBackend` protocol
(pull/push ops) so `AppStore`+`Outbox` can be tested against a scripted fake:
"message sent while offline survives relaunch and reaches the backend exactly once"
is the test that proves this plan.

## Sequencing

B1–B3 are patch-sized: do them immediately (B1/B2 are active data loss for any
TestFlight user). The outbox is ~2–3 days including tests; ship before public
launch — beta scale will mask these failures, launch scale won't.

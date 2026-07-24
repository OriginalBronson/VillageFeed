> **Synthesis note (salvaged from a parallel working copy).**
> This UX review was written against the July-6 baseline (commit `938cf2a`) on a
> separate machine. This branch is ~6 commits further along (compliance, backend
> hardening, chat v2, handoff planner, push, trust), so several backlog items below
> were **already resolved here independently**. Verified status as of this synthesis:
>
> | Item | Status in this codebase | Evidence |
> |---|---|---|
> | B1 — own profile never pulled | ✅ Resolved | `SyncService.fetchMyProfile()` + sign-in hydration |
> | B2 — Plus sold but never delivered | ✅ Resolved | `supabase/functions/sync-entitlement`, `syncEntitlement(jws:)` |
> | B8 — age gate / consent not recorded | ✅ Resolved | `0007_tos_acceptance.sql`, `LegalDocs.swift` |
> | B10 — blocks one-directional | ✅ Resolved | `0008_backend_hardening.sql` filters both directions |
> | B14 — no push notifications | ✅ Resolved | `PushManager.swift`, `0011_push_notifications.sql`, `send-push` |
> | B16 — core loop has no transaction | ✅ Resolved | `0012_handoff_planner.sql`, `HandoffPlannerViews.swift` |
> | Part 1 §1,2,3,8,9 (matches/undo/recovery/unmatch/seeking) | ✅ Present | done here independently; unmatch + undo-swipe ported in this synthesis |
> | B3–B7, B9, B11–B13, B15, B17–B27 | ⚠️ Not re-verified | carried forward — triage against current code before actioning |
>
> The rest of the document is the original review, preserved verbatim as a backlog
> source. Treat P0/P1 rows as candidates to confirm, not open bugs, until checked
> against the files named above.
>
> **Relationship to `plans/03-ux-review.md`:** that file is this project's *own*
> curated, screen-by-screen audit — the one that drove feature plans 04–07 and was
> acted on. This file is a *second, external* review imported from a parallel working
> copy; keep it as a backend-heavy backlog cross-check, not a competing source of
> truth. Where the two overlap, `plans/03` is authoritative.

---

# VillageFeed — UX review & backlog

Full-stack review of the app as of this commit: every SwiftUI view, `AppStore`,
`SyncService`, and the five (now six) Supabase migrations. Part 1 is what was found and
fixed; Part 2 is the prioritised backlog of everything else, front end and back.

Verification: `xcodebuild test … -destination 'platform=iOS Simulator,name=iPhone 17'`
→ **33 tests, all passing**.

---

## Part 1 — Implemented in this pass

### 1. Matches never happened for real (synced mode) — *backend + frontend*

`likesYou` is hardcoded `false` when building profiles from server rows (it's
entitlement-gated data), and the deck's match check read `person.likesYou`. Meanwhile
`recordSwipe` **already asked the server** `mutual_like` and returned the truthful
answer — and the caller threw it away with `await sync?.recordSwipe(...)` as a bare
statement. Net effect: outside demo mode, swiping right on someone who liked you
produced *nothing*. The single most damaging bug in the app — the core promise silently
didn't work.

Also, `matches` were never pulled. They lived only in local JSON, so a reinstall or a
second device lost every match.

- `AppStore.swipe` now captures the server's mutual verdict and publishes `pendingMatch`.
- `RemoteSnapshot` carries `matchedIDs`; `pull()` reads the `matches` table.
- `applyRemote` treats server matches as truth.
- Consolidated the two competing `.sheet(item:)` modifiers into one bound to
  `store.pendingMatch` — stacking two sheets presenting the same content on one view is
  a known SwiftUI race.

### 2. Undone swipes and passed groups came back — *backend*

`undoLastSwipe` restored the card locally but left the `swipes` row on the server, so
the next pull re-hid it. Group passes were never recorded at all, so every passed group
reappeared on refresh, forever.

- Added `SyncService.deleteSwipe`, called from `undoLastSwipe`.
- Group passes now write a `target_kind = 'group'` swipe row.

### 3. No password recovery — *frontend + backend*

Email/password was offered with no reset path. Forgetting your password meant losing
the account.

- `AuthSession`: `sendPasswordReset`, `updatePassword`, `.passwordRecovery` event
  handling, `handleDeepLink`, `cancelPasswordRecovery`.
- `ForgotPasswordSheet` (prefilled from the sign-in field) and `SetNewPasswordSheet`.
- `onOpenURL` in the app root so the emailed link is honoured.

**Review note on the first draft of this feature:** `SetNewPasswordSheet` shipped with
`.interactiveDismissDisabled()` and no cancel button. Recovery links expire — a user
whose token had lapsed would be sealed in an undismissable sheet with no route back to
sign-in. Fixed by adding a Cancel that ends recovery *and signs out* (the emailed link
already establishes a live session; leaving it active would strand someone signed in
under a password they don't know). Also cleared stale `lastError` on both sheets, which
otherwise opened showing an unrelated error from a previous sign-in attempt.

### 4. Dishes could be created but never edited — *frontend*

One typo in a dish name or portion count meant delete-and-retype, losing the photo.
`DishEditorSheet` now takes an optional `Dish` and serves both add and edit; dish rows
in Profile are tappable. Editing preserves the dish `id` (so the server row and its
uploaded photo stay associated) and preserves an existing photo when the picker isn't
touched.

Caught alongside: `.onDelete` on dishes never called `persist()` — deleted dishes
returned on relaunch. Fixed.

### 5. Joining a group was blind — *frontend*

Tapping a person card opened a detail sheet; tapping a group card did nothing, yet
right-swiping *immediately joined*. Users committed to a table without seeing who was
at it. New `GroupPreviewSheet` shows members, their dishes and portions, dietary tags,
and — deliberately foregrounded — **every allergen declared at that table**, which is
the one thing worth knowing before joining a food-sharing group.

### 6. Refresh existed only when the deck was empty — *frontend*

`.refreshable` was attached solely to the empty-state view. A stale deck or stale group
chat had no manual refresh at all. Added a toolbar refresh to Discover (synced mode
only) and `.refreshable` to both the Groups list and group detail. Pull logic moved to
`AppStore.refreshFromServer()` rather than duplicated per view.

### 7. Chat timestamps lied — *frontend*

Messages rendered with `Text(date, style: .time)` — time only. A message from last
Tuesday read as though it arrived today, in an app where the chat's main job is agreeing
*when* to hand off food. Now: time today, "Yesterday HH:MM", weekday within a week,
full date beyond. Chat also auto-scrolls to the newest message (it sits mid-`List`, so
a busy table previously opened on old messages with new arrivals off-screen).

### 8. Unmatching required blocking — *frontend + backend*

The only way to undo a match was to **block** the person, which is a safety action with
safety consequences. Added swipe-to-unmatch with a confirmation, `SyncService.deleteMatch`,
and migration `0006_unmatch.sql` granting participants `delete` on `matches` (previously
insert/select only, so the delete would have silently failed RLS).

Unmatching deliberately keeps the swipe row, so an unmatched person doesn't resurface in
the deck.

### 9. "Seeking new members" silently reverted — *frontend + backend*

The toggle mutated `store.groups[idx]` directly: no `persist()`, no sync, no
`rebuildDeck()`. It reset on relaunch and never reached the server, so a group that
closed itself kept being advertised to everyone else. Now routed through
`AppStore.setSeekingMembers` → `SyncService.updateGroupSeeking`.

### 10. Documentation drift

The README's test command pinned `name=iPhone 16`, which resolves against `OS:latest`
and fails on this machine (iPhone 16 exists only on the 18.4 runtime). Updated, with a
note on how to find a valid destination.

**Tests added:** unmatch semantics (and its no-op case), dish edit-in-place identity
preservation, rejection of dishes not owned, date-aware timestamp bucketing, and the
seeking-members toggle gating the deck.

---

## Part 2 — Backlog

Ordered by what will actually hurt. **P0 = blocks launch or loses user data.**

### P0 — Launch blockers

| # | Area | Issue |
|---|---|---|
| B1 | Backend | **Your own profile is never pulled.** `pull()` does `.neq("id", userID)`, so `me` is only ever local. Sign in on a second device or after a reinstall and you get the *seeded demo profile* ("You", Maplewood, Classic Lasagna) — and the next `pushProfile` overwrites your real server profile with it. Silent, total profile loss. Needs own-profile+dishes fetch into `me` and a conflict rule for unsynced local edits. |
| B2 | Backend | **Plus is sold but never delivered.** `is_plus` is only settable by the service role, and no App Store Server Notification webhook exists. A user can complete the StoreKit subscription and `who_liked_me()` still returns empty, because the server never learns they paid. Paid feature is non-functional in synced mode. |
| B3 | Backend | **`pushProfile` drops already-uploaded photos.** `photo_path` is only set when the photo is `.data`; a `.remote` photo (i.e. one already uploaded) pushes `nil` and clears the column. Currently masked by B1 — `me.photo` never becomes `.remote` because own-profile is never pulled — so **fixing B1 without fixing this turns a latent bug into live photo loss.** Fix together. |
| B4 | Frontend | **No report/block path outside the Discover deck.** If a match or group member becomes abusive *in chat*, there is no way to report them — the flag button exists only on the top deck card. Add report/block to `PersonDetailSheet`, group member rows, match rows, and individual messages. This is the safety gap most likely to matter. |
| B5 | Frontend | **The moderation queue ships to every user.** `ProfileView` links "Review queue" for everyone, letting any user approve/ban locally and enter an Anthropic API key. It's local-only theatre (server `review_cases` is service-role and never read by the app), but it looks authoritative. Gate behind a moderator role or strip from release builds. |
| B6 | Frontend | **Paywall lacks App Store-required disclosure.** No terms link, no privacy link, no renewal/duration copy, no manage-subscription route. Guideline 3.1.2 rejection. |
| B7 | Backend | **New profiles default to `pendingReview` with no reviewer.** `handle_new_user` inserts `pendingReview`, RLS shows only `active` profiles, and nothing in production promotes them. Every real signup is invisible to everyone, forever. Needs auto-approve, an AI triage on write, or a real moderation dashboard. |
| B8 | Compliance | **Age gate isn't recorded.** The onboarding 17+ and food-risk toggles are local `@State`, discarded on tap. `profiles.birth_year` exists and is never written. No evidence of consent for a food-sharing app with a stated minimum age. |

### P1 — Serious, pre-scale

| # | Area | Issue |
|---|---|---|
| B9 | Backend | `pull()` fetches **every active profile and every dish in the database**, unbounded and ungeofenced. Breaks past a few hundred users and hands the whole user table to any signed-in client. Needs neighborhood/radius filtering, pagination, and a narrower select. |
| B10 | Backend | **Blocks are one-directional.** Only `blocker_id = me` is pulled, so someone who blocked *you* still appears in your deck. Filter both directions server-side. |
| B11 | Backend | `merge_groups` checks membership of the destination but not the source, and only that the source is `open_to_merge`. You can absorb another group's members into yours without their consent. |
| B12 | Backend | **No offline queue or retry.** Every write is `try?`-and-log. Send a message in a dead zone and it's gone with no error surfaced. (Acknowledged in-code, but it's user-visible loss.) |
| B13 | Frontend | **Sync failures are invisible.** `try? await sync.pull()` swallows errors; a failed initial pull leaves the user staring at an empty or seeded world with no explanation and no retry. Needs a loading state and an error banner. |
| B14 | Frontend | **No push notifications.** New match, new message, someone joined your group — all invisible unless the app is open. For this category it's the top retention complaint. |
| B15 | Frontend | **No remote image caching.** `AsyncImage` refetches on every card render; the deck flickers and burns bandwidth. |
| B16 | Product | **The core loop has no transaction.** Portions are a static number that never decrements; nothing records that a trade happened, when, or where. "Cook once, eat all week" currently means "chat about it and hope." Needs a claim/handoff model — even a minimal one. |
| B17 | Frontend | **Dietary tags are decorative.** Declared, displayed, and never used to filter or rank the deck. In an app where allergens are a safety matter, an allergy sufferer has to read every card manually. Add deck filters (dietary, neighborhood, has-photo). |

### P2 — Quality and polish

| # | Area | Issue |
|---|---|---|
| B18 | Frontend | Profile edits only reach the server via **"Submit profile for review"**. Change your bio and never tap it → never syncs. Conversely, every trivial edit forces a full re-review. Separate "save" from "resubmit". |
| B19 | Backend | `pushProfile` deletes all dishes then re-inserts them, non-atomically. A mid-flight failure loses every dish. Make it an upsert-and-prune in one RPC. |
| B20 | Frontend | Dynamic Type / accessibility: fixed 280pt card photos clip at large text sizes; `FlowLayoutish` is a hardcoded 3-per-row approximation that breaks with long tag names; deck cards carry no VoiceOver labels (the action-row buttons do, which is a good start). |
| B21 | Frontend | Group members' full profiles aren't reachable from group detail — you can't inspect who you're eating with after joining. |
| B22 | Frontend | No "likes I sent" view; no way to withdraw a like. |
| B23 | Frontend | Group merge is irreversible behind a single alert, and `openToMerge` is never exposed in the UI at all. |
| B24 | Frontend | Chat: 500-message pull limit, no pagination, no unread badge or indicator on the Groups tab. |
| B25 | Frontend | Demo mode's empty deck says "Pull to refresh — new cooks join every day", which is false offline; and `hasOnboarded` survives account deletion. |
| B26 | Security | Anthropic API key stored in plaintext `@AppStorage`. Dev-only by intent, but it ships in the UI (see B5). |
| B27 | Backend | Group messages have no length cap or rate limit — spam and payload-size exposure. |

---

## Recommended order

1. **B1 + B3 together** (own-profile pull and photo-path preservation — dangerous apart).
2. **B4, B5** — the safety and moderation surface.
3. **B7, B8, B6** — signup actually works, consent recorded, paywall compliant.
4. **B2** — make Plus deliver what it charges for.
5. **B9, B10** — before any real user volume.

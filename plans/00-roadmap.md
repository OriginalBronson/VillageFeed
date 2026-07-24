# VillageFeed — Deployment Roadmap (plan index)

Goal: take the current build (local-first SwiftUI app + Supabase backend, v0.1) to an
approved App Store release. This file is the index and sequencing; each linked plan is
self-contained.

## The plan series

| # | Doc | What it covers | Blocking for submission? |
|---|-----|----------------|--------------------------|
| 1 | [01-app-store-compliance.md](01-app-store-compliance.md) | Everything Apple will reject us for: Sign in with Apple, subscription paywall requirements, hosted privacy policy, hiding internal tooling, App Store Connect setup | **Yes — every item** |
| 2 | [02-backend-hardening.md](02-backend-hardening.md) | Server-side gaps the client currently papers over: report rate limit, bidirectional blocks, match truth on the server, email confirmation, photo bucket privacy | Yes for the security items |
| 3 | [03-ux-review.md](03-ux-review.md) | Full walkthrough audit of every screen, framed as the complaints real users would file | Partially — the P1 fixes |
| 4 | [04-feature-notifications.md](04-feature-notifications.md) | Push notifications for matches, messages, group joins | No, but expect immediate 1-star "app never tells me anything" reviews without it |
| 5 | [05-feature-handoff-planner.md](05-feature-handoff-planner.md) | Closing the core loop: actually scheduling the food handoff | No, but the product doesn't deliver its promise without it |
| 6 | [06-feature-discovery-filters.md](06-feature-discovery-filters.md) | Dietary filters + structured neighborhoods so the deck shows food you can eat, from people actually near you | No, but the #1 predictable complaint |
| 7 | [07-feature-chat-upgrade.md](07-feature-chat-upgrade.md) | A real chat screen (currently a Form section), message reporting, unread state | Message reporting is a safety-launch item |
| 8 | [08-sync-integrity.md](08-sync-integrity.md) | Three found data-loss bugs (profile-photo erasure, dish delete-then-insert, divergent match truth) + an outbox for offline writes | **B1–B3 bug fixes: yes** |
| 9 | [09-terms-and-food-law.md](09-terms-and-food-law.md) | Terms of Service (none exists today), prohibited-foods policy, counsel checklist for cottage-food law | **Yes — ToS is a launch gate** |
| 10 | [10-trust-and-reputation.md](10-trust-and-reputation.md) | Trade counts, tenure badges, verified cook — trust signals from actions, not star ratings | No — post-launch |
| 11 | [11-testing-and-release.md](11-testing-and-release.md) | Sync + RLS test coverage, release pipeline, TestFlight protocol, device matrix | Pipeline + device pass: yes |
| 12 | [12-launch-density-playbook.md](12-launch-density-playbook.md) | Founding-neighborhood strategy, invite loop, waitlist, expansion rule | No code-blocker, but start recruiting now — longest pole |

## Sequencing

**Phase 0 — Start immediately, runs in parallel with everything.**
Plan 08 bug fixes B1–B3 (active data loss for any tester), plan 09 ToS draft +
counsel booking, and plan 12 founding-cook recruiting (the longest pole in the
whole schedule and it's not engineering).

**Phase 1 — Submission blockers (do first, mostly independent).**
Everything in plan 01, plus from plan 02: server-side report limit, bidirectional
blocks, re-enable email confirmation. From plan 03: the P1 fixes (remove
moderation/demo surfaces from the consumer build, paywall legal links, seeded fake
profiles). Plan 11's release pipeline lands here so every TestFlight build is
CI-built. Target: a build that would pass App Review.

**Phase 2 — "Don't get 1-starred in week one."**
Plan 04 (notifications) and plan 06 (filters + neighborhoods). These are the two gaps
every user hits in their first session. Ship in the launch build if timeline allows,
first update otherwise.

**Phase 3 — Product completeness.**
Plan 05 (handoff planner), plan 07 (chat upgrade), plan 08's outbox, and plan 10 v1
(trade counts ride plan 05's schema). These turn matches into actual traded meals —
retention lives here.

**Continuous:** TestFlight from the end of Phase 1 following plan 11's protocol.
Real-device testing has not happened yet (per repo history); do it before any
external beta. Plan 12's pilot begins the day external TestFlight opens.

## Current state (verified against the code, 2026-07-07)

- 4-tab SwiftUI app (Discover / Groups / Likes / Profile), local JSON persistence,
  demo mode with 10 seeded profiles when `SupabaseConfig.anonKey` is empty (it
  currently is — the shipped binary must have it filled).
- Supabase backend exists (project `swjnmgfyvagkyugsndiv`), 5 migrations, RLS
  everywhere, `moderate-profile` and `delete-account` edge functions, realtime chat.
- StoreKit 2 subscription (`app.villagefeed.plus.monthly`) with a local
  `Products.storekit` file; the App Store Connect product does not exist yet.
- Safety shipped: report → instant freeze, review queue (AI-triage optional),
  instant block, client-side report rate limit, age gate + food-risk acknowledgment,
  per-dish allergen notes, account deletion.
- Known-open safety items are tracked in `SAFETY-NOTES.md`; plans 02 and 07 absorb
  the pre-launch ones.

## Definition of "ready to submit"

Status as of 2026-07-17 — code side executed on branch `plans/app-store-readiness`;
remaining items are browser work (DISPATCH-3.md), counsel, and physical-device passes.

- [x] Plan 01 code items (SIWA, paywall legal/retry, moderation gated, demo seeding gated, Info.plist, contact) — App Store Connect/portal steps queued in DISPATCH-3
- [x] Plan 02 security items in migration 0008 (server report limit, bidirectional block, match trigger, frozen write lockout) — **apply via DISPATCH-3**; email confirm is a held launch phase
- [x] Plan 03 P1+P2 done (no internal tooling, no seeded people in configured builds, paywall links, merge consent, card preview, blocked list, a11y pass, offline states)
- [x] Message reporting + delete-own + unread model (plan 07); chat is a real screen
- [x] Plan 08 bugs B1–B3 fixed + outbox with drain-then-pull, connectivity/foreground drains, resubscribe
- [ ] Terms of Service **drafted** (docs/terms-of-service.md) — hosting (DISPATCH-3) and **counsel review still open (launch gate)**
- [x] Release pipeline (release.yml, tag-triggered) + Release-config CI + pgTAP RLS job; device checklist written (docs/device-checklist.md) — **device pass not yet run**
- [ ] App runs correctly on a physical iPhone signed in against production Supabase (needs anon key + migrations applied — DISPATCH-3)
- [ ] One full end-to-end trade tested by two real accounts on TestFlight

Also shipped beyond the gate list: plans 04 (push), 05 (handoff planner),
06 (filters + ZIP), 10 (trust v1), 12 (invite loop, village threshold),
02-P2 (incidents, appeal copy, moderator build).

High-leverage pass (2026-07-24) — the imported backlog fully triaged (verdicts in
[docs/ux-review.md](../docs/ux-review.md)) and plan 13's pre-launch items built:
- [x] Plan 13 #2: dietary conflict warning at pledge time (the cheapest safety
  feature left — the app knew both facts and now says so)
- [x] Plan 13 #1: first-trade guide card for new two-person groups
- [x] Message rate limit server-side (migration 0016) + client cap so an oversize
  message can't poison the outbox (ux-review B27)
- [x] Dishes pull scoped to visible cooks + profiles bounded; image cache sized
  for the deck (ux-review B9 partial, B15)
- Deferred, with reasons recorded in docs/ux-review.md: B9's geofenced RLS +
  pagination (needs a cross-area visibility decision), plan 13 #3 reminder push
  (pg_cron dashboard work → next DISPATCH round), B21/B22/B24/B25 (P2 polish)

Synthesis pass (2026-07-24) — salvaged from a parallel working copy and adapted to
the outbox architecture:
- [x] Unmatch as a light-touch alternative to blocking (migration 0015, `.unmatch`
  outbox op, swipe-to-unmatch in Groups)
- [x] `undoLastSwipe` now deletes the swipe server-side (`.deleteSwipe` op) so the
  rescued card doesn't refreeze on the next pull
- [x] Group detail sheet surfaces allergens declared at the table
- See [`docs/ux-review.md`](../docs/ux-review.md) for the imported external backlog
  (several P0/P1 items already resolved here; status map at the top of that file)

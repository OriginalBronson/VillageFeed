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

## Sequencing

**Phase 1 — Submission blockers (do first, mostly independent).**
Everything in plan 01, plus from plan 02: server-side report limit, bidirectional
blocks, re-enable email confirmation. From plan 03: the P1 fixes (remove
moderation/demo surfaces from the consumer build, paywall legal links, seeded fake
profiles). Target: a build that would pass App Review.

**Phase 2 — "Don't get 1-starred in week one."**
Plan 04 (notifications) and plan 06 (filters + neighborhoods). These are the two gaps
every user hits in their first session. Ship in the launch build if timeline allows,
first update otherwise.

**Phase 3 — Product completeness.**
Plan 05 (handoff planner) and plan 07 (chat upgrade). These turn matches into actual
traded meals — retention lives here.

**Continuous:** TestFlight from the end of Phase 1. Real-device testing has not
happened yet (per repo history); do it before any external beta.

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

- [ ] Plan 01 checklist fully green (compliance)
- [ ] Plan 02 security items done (server report limit, bidirectional block, email confirm)
- [ ] Plan 03 P1 items done (no internal tooling in consumer UI, no fake seeded people in prod, paywall links)
- [ ] Message reporting from plan 07 (SAFETY-NOTES launch item)
- [ ] App runs correctly on a physical iPhone signed in against production Supabase
- [ ] One full end-to-end trade tested by two real accounts on TestFlight

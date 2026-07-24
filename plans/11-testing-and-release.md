# Plan 11 — Testing & Release Engineering

Current state, honestly assessed: the unit suite is genuinely good — 28 tests
covering the local store's matching, groups, moderation, blocking, persistence, and
DTO mapping. The gaps are everything *around* that well-tested core: zero coverage
of `SyncService`, zero coverage of the RLS policies the security story depends on,
no UI/device testing, and no release pipeline (CI builds and tests on simulator only).

## A. Close the test gaps (ordered by risk)

### A1. Sync layer (biggest gap, worst failure mode)
Plan 08 extracts a `SyncBackend` protocol; the tests that matter:
- pushProfile round-trip preserves photos/dishes when nothing changed (regression
  net for bugs 08-B1/B2)
- outbox: op enqueued offline → survives relaunch → delivered exactly once
- pull + pending local ops reconcile (drain-then-pull invariant)
- match outcome follows the backend's answer, not local `likesYou` (08-B3)

### A2. RLS policy tests (the security claims, actually checked)
Every security property in plans 01/02 is a Postgres policy nobody executes in CI.
Supabase supports SQL-based policy tests (pgTAP) run against a local
`supabase start` stack. One GitHub Actions job, seeded with three users
(A, B blocked-by-A, C frozen), asserting: B can't see A; C appears in no one's pull;
non-members can't read/insert group messages; report #6 in 24h is rejected;
`is_plus` can't be self-granted (migration 0005's whole point — currently unverified
by any test). ~1 day to stand up; it converts the security section from "we believe"
to "CI checks".

### A3. UI smoke tests (thin by design)
Not a big XCUITest suite — five flows that break embarrassingly: launch → onboard →
gate toggles enable button; swipe right → match sheet appears; join group → send
message renders; paywall opens with price (StoreKit config); delete-account confirm
appears. Run on one simulator in CI. Snapshot testing is deliberately skipped at
this stage (churny while the UX plans land).

### A4. Device matrix (manual, pre-TestFlight)
Real-device validation has never happened. One afternoon, physical devices:
smallest supported (SE-class) + largest, light/dark, Dynamic Type XL, airplane-mode
mid-session (exercises plan 08), photo upload over cellular. Write findings into
issues; repeat before each release using the same checklist committed as
`docs/device-checklist.md`.

## B. Release pipeline

- **Versioning**: adopt `MARKETING_VERSION`/build-number discipline now (1.0.0 /
  auto-incremented build via agvtool or CI run number).
- **CI additions** to the existing workflow: Release-config build (catches
  `#if DEBUG` leaks — plan 01 depends on this), unit + UI smoke on PR, pgTAP job.
- **Archive & upload**: `xcodebuild archive` + `-exportArchive` with cloud signing
  (Xcode-managed certs) uploaded via `xcrun altool`/App Store Connect API key from
  CI, or fastlane if preferred — either way, the rule is *no hand-built archives*;
  every TestFlight build comes from a tagged commit.
- **Secrets discipline**: the anon key can live in the repo (publishable);
  the App Store Connect API key and APNs p8 (plan 04) go in GitHub Actions secrets.

## C. TestFlight protocol

1. **Internal** (you + 2–3 trusted people): after Phase 1 of the roadmap. Goal:
   crash-free sessions, plan 08 bugs fixed, one real two-account trade.
2. **External beta** (the plan-12 founding neighborhood, ~20–50 people): needs Beta
   App Review (lighter than full review but real — the plan 01 P1 items must already
   be done). Collect via a single feedback channel (TestFlight feedback + one group
   chat *in the app itself* — dogfood table talk as the beta forum).
3. **Exit criteria to submit**: crash-free rate >99.5% over a week, zero P1 bugs
   open, one complete organic trade (two beta users who don't know each other).

## D. On-call for a one-person team

Launch week reality: you are support, moderation, and ops. Prepare: the moderator
build (plan 02-§7) on your phone, Supabase dashboard bookmarks for reports/logs, a
saved-reply doc for the five predictable support emails (can't sign in, delete my
data, reported someone, got frozen, refund → Apple's flow). One hour of prep that
prevents launch-week panic.

## Sequencing

A1 rides plan 08 (same PR). A2 + B are a focused ~2 days, independent of everything.
A3 before external beta; A4 the afternoon the first TestFlight build exists.

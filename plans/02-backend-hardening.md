# Plan 02 — Backend Hardening

The client is currently the enforcement point for several rules that only matter if
they can't be bypassed. Anything enforced only in Swift is enforced for honest users
only. This plan moves the load-bearing rules server-side and closes data-exposure gaps.

## P1 — before launch

### 1. Server-side report rate limit
`AppStore.maxReportsPerDay = 5` lives entirely in the client (`reportDates` in local
JSON). A hostile user with a REST client can file unlimited reports, and each report
**instantly freezes the target** — that's a weaponizable griefing vector against the
very mechanism that protects people (SAFETY-NOTES item 8).

- Migration: a `before insert` trigger on `reports` that counts the reporter's rows in
  the trailing 24h and raises an exception past 5. Keep the client-side check for the
  friendly error message; the trigger is the real wall.
- While in there: make repeat reports of the same subject by the same reporter a
  no-op (unique index on `(reporter_id, subject_id)` per open case) so one person
  can't multi-freeze.

### 2. Bidirectional blocks
Today blocking hides *them from you* (client-side filter). The blocked person still
sees the blocker in their deck, can re-like them, and can read their profile — for a
harassment scenario that's backwards.

- The `blocks` table exists; add block filtering to the neighborhood-pull RPC / RLS
  policies so a profile is excluded in **both** directions server-side.
- Also exclude blocked users' `group_messages` rows server-side (client filters today).
- Add an "Unblock" management list (see plan 03, finding P5) once blocks are
  authoritative on the server.

### 3. Match truth on the server
`UserProfile.likesYou` ships to the client for everyone in the pull, and match
detection runs in `AppStore.swipe`. Two problems:
- **Paywall bypass**: the free tier hides who-liked-you behind a blur, but the data
  (`likesYou`) is in the local snapshot — anyone with a proxy sees it. The
  `who_liked_me` RPCs (count free / identities Plus) already exist; make the pull
  **omit** `likesYou` entirely and derive matches server-side.
- **Integrity**: matches should be computed from mutual `swipes` rows in a trigger or
  RPC, not client-declared.

### 4. Re-enable email confirmation
Deliberately off for TestFlight-era testing (DISPATCH-2 §2). Turn back on at launch —
unconfirmed emails + a social app is a spam-account machine. Coordinate with the App
Review demo account (pre-confirm it manually).

### 5. Photo bucket exposure
The privacy policy admits photos are "publicly readable by URL". Paths are UUIDs
(unguessable), which is tolerable at launch, but:
- Verify bucket listing is disabled (public *read by URL* ≠ public *list*).
- Deleted accounts: confirm `delete-account` removes storage objects, not just rows —
  orphaned photos of deleted users is a GDPR problem. Check
  `supabase/functions/delete-account/index.ts` covers the storage bucket; if not, add it.

### 6. Frozen/banned enforcement server-side
Check that RLS actually excludes `frozen`/`banned` profiles from the neighborhood
pull and from `group_messages` inserts. If the freeze trigger only flips a column the
client happens to filter on, a modified client ignores it. (Migration 0001 has the
report-freeze trigger; verify read policies also check status.)

## P2 — shortly after launch

### 7. Moderator tooling off-device
Plan 01 removes the in-app review queue from the consumer build. The queue still
needs a home: simplest is a `MODERATOR_BUILD` scheme of the same app distributed via
TestFlight internal to just you; RLS gives `is_moderator` accounts read/write on
`review_queue`. A web dashboard can wait.

### 8. Appeal flow (SAFETY-NOTES item 8)
A frozen user currently sees a "Frozen" badge and nothing else. Minimum viable
appeal: a canned "Your profile is under review — reply to this email to appeal"
message with the support address. Ship the copy at launch; the workflow can be manual.

### 9. Incident reports ("this food made me sick") — SAFETY-NOTES item 1
Distinct from profile reports; needs its own reason category, pauses the cook's
*dishes* (not their whole profile) pending review, and gets prioritized human review.
Schema: `incident_reports` table keyed to dish + reporter, plus a `paused` flag on
dishes surfaced in the pull.

### 10. Operational basics
- Crash reporting: none exists. Xcode Organizer crash logs are the zero-dependency
  baseline; MetricKit if we want more. Avoid third-party analytics at launch (keeps
  the privacy label clean).
- Supabase backups: confirm PITR/backup tier on the project before real user data.
- CI (`ci.yml` exists): add a Release-configuration build to catch `#if DEBUG`-only
  compilation mistakes before archive day.

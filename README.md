# VillageFeed

**Make one dish, eat many.** Cook once, eat all week — swipe to find neighbors to trade
home-cooked meal portions with, form supper groups (2+ people), and turn one giant lasagna
into a week of different dinners.

## What's here (v0.1 — local prototype, no backend)

- **Sign-in & first run** — branded sign-in / create-account screen (validation, show/hide
  password, password reset by email that deep-links back into the app), then a four-step
  **profile creation wizard** (name & neighborhood → photo & bio → dietary pills → first
  dish) ending in submit-for-review. Returning users hydrate their profile from the server,
  so signing in on a new device restores your card.
- **Discover** — Tinder-style card deck of nearby cooks *and* open supper groups. Right-swipe
  a cook → match if mutual; right-swipe a group → join it. Cards show the main photo (person
  or dish), advertised dishes with portion counts, and dietary-constraint pills.
- **Groups** — your supper groups: members + this week's dishes, **table-talk group chat**
  (live over Supabase Realtime when synced), a "seeking members" toggle, group-to-group
  **merge**, and leave-group. Groups start at 2 people (a match can seed one); you can be a
  solo member of many groups. Matches get their own section with a start-a-group shortcut.
- **Likes** — the paid tier. Free users see a blurred grid + count; **VillageFeed Plus**
  (StoreKit 2 subscription, `app.villagefeed.plus.monthly`, simulator-testable via
  `Products.storekit`) reveals everyone who swiped right on you. Purchases sync
  server-side: the app posts the signed transaction to the `sync-entitlement` edge
  function, which verifies Apple's certificate chain before unlocking the
  `who_liked_me()` identities RPC. Premium roadmap: `docs/premium-features.md`.
- **Profile** — name/neighborhood/bio, photo picker (use yourself or a dish as the main
  photo), dietary pills, dish advertising with **photos, blurbs, portions, and allergen
  notes** (images downscaled to 1200px JPEG before upload), submit-for-review, an in-app
  privacy & safety explainer (full policy in `docs/privacy-policy.md`), and **account
  deletion** via the `delete-account` edge function (App Store 5.1.1(v)).
- **Moderation** — report → instant freeze → review queue. Queue items can be triaged by the
  Claude API (`claude-haiku-4-5`) or resolved directly by a human (no API cost). See
  `SAFETY-NOTES.md` for the launch-blocking safety list.

## Backend (Supabase)

- **Auth**: email/password + **Sign in with Google** (Supabase OAuth via
  `ASWebAuthenticationSession`, callback `villagefeed://auth-callback`); password-reset
  emails reuse the same callback to deep-link into an in-app "new password" sheet. With
  `SupabaseConfig.swift` unfilled the app runs in demo mode on seeded data.
- **Schema**: `supabase/migrations/0001_init.sql` — profiles, dishes, groups +
  membership, swipes, matches, blocks, reports, review queue; RLS on every
  table; report trigger freezes the subject server-side; photos bucket.
- **Sync**: `SyncService.swift` pulls the neighborhood (profiles/dishes/groups)
  and mirrors swipes, matches, blocks, reports, and group actions. Local JSON
  persistence (`Persistence.swift`) keeps state across relaunches either way.
- **Moderation**: `supabase/functions/moderate-profile` runs the AI triage
  server-side with a secret key; the in-app key path remains for local dev.
- **Entitlements**: `supabase/functions/sync-entitlement` verifies StoreKit 2
  signed transactions (Apple root pinned, `appAccountToken` must match the
  signed-in user) and maintains `is_plus` + `plus_expires_at`, which gate
  `who_liked_me()` (migrations 0002/0006).
- **Setup**: `DISPATCH.md` is the browser runbook (Supabase project, Google
  OAuth client, provider config, secrets) plus the morning terminal checklist.

## Build & test

- Requires Xcode 16+. Open `VillageFeed.xcodeproj`, run the `VillageFeed` scheme.
- CLI: `xcodebuild test -project VillageFeed.xcodeproj -scheme VillageFeed -destination 'platform=iOS Simulator,name=iPhone 16'`
- The scheme references `Products.storekit`, so Plus purchases work in the simulator.
- AI moderation: set an Anthropic API key in Profile → Moderation (dev-only convenience —
  production must proxy through a server).

## Copy bank

- Make one dish, eat many.
- Cook once, eat all week.
- Your table, multiplied.
- The neighborhood is the menu.

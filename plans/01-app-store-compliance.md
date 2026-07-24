# Plan 01 — App Store Compliance

Everything on this list is a rejection or a hard prerequisite. Ordered so the code
changes come first (they gate the build), then App Store Connect work (browser tasks —
add to a DISPATCH round).

## A. Code changes in the app

### A1. Sign in with Apple (Guideline 4.8) — REQUIRED
We offer "Continue with Google". Apple's rule: any app using a third-party login must
also offer a login option with privacy-respecting minimums — in practice, Sign in with
Apple. **Without this we will be rejected.**

- Add the `Sign in with Apple` capability to the target.
- Supabase supports Apple as an OAuth provider; wire it the same way Google is wired
  in `AuthSession.swift` (`ASAuthorizationController` natively rather than the web
  session — better UX and Apple prefers it).
- Place the Apple button *above* the Google button in `SignInView` (Apple's HIG asks
  for equal-or-greater prominence).
- Dispatch item: enable the Apple provider in Supabase Auth settings; create the
  Services ID / key in the Apple Developer portal.

### A2. Subscription paywall requirements (Guideline 3.1.2)
`PaywallSheet` in `LikesView.swift` is missing legally required elements:

- Functional links to the **privacy policy** and **Terms of Use (EULA)** inside the
  paywall. (Apple's standard EULA is fine — link to it.)
- State that the subscription **auto-renews monthly** and how to cancel. Today the
  sheet shows only price/month and three benefit bullets.
- Remove the `#if DEBUG` "unlock Plus" toggle from any build submitted for review —
  DEBUG isn't compiled into Release, so this is fine as-is, but verify the archive is
  a Release build.
- The binary must not reference `Products.storekit` behavior at review time; the real
  product must exist in App Store Connect (section B4) and load. Handle the
  product-load-failure state in the paywall (today the button says "Subscribe" with
  no price — show a retry, not a dead button).

### A3. Remove internal tooling from the consumer build — REQUIRED
Two things in the shipping UI are internal tools and will confuse users and reviewers:

- **Profile → Moderation → Review queue** (`ModerationView`): every user currently
  sees the moderation queue with AI-verdict buttons. Gate it behind an admin flag
  (e.g. an `is_moderator` column checked at sign-in) or remove from the consumer
  build entirely (`#if MODERATOR_BUILD`). A reviewer who taps this will ask questions
  we don't want to answer during review.
- **The in-app Anthropic API key field** (`AIReviewer` path): dev convenience per the
  README; must not ship. Moderation triage already runs server-side via the
  `moderate-profile` edge function — delete the client key path.

### A4. Demo mode and seeded data must not ship
- `SupabaseConfig.anonKey` is empty → the app currently runs in demo mode with 10
  fictional profiles (Maya, Dario, …). A reviewer would experience fake people and a
  fake "It's a trade!" — that's a 2.3.1 misleading-content risk, and real users would
  swipe on ghosts.
- Fill the anon key for release builds (it's publishable, safe to embed).
- In synced mode, `applyRemote` replaces seeded people — but only after a successful
  pull. Ensure a signed-in user with no network never sees seed people: gate seeding
  on `!SupabaseConfig.isConfigured`.
- Decide what a *real* empty neighborhood looks like (see plan 03, finding D1) — the
  reviewer will likely be the only user in their area.

### A5. Info.plist / project settings
- `ITSAppUsesNonExemptEncryption = NO` (skips the export-compliance question every build).
- Verify display name, bundle version/build strings, and the app icon set render on
  device (icon exists in the asset catalog — confirm all required sizes).
- `PhotosPicker` runs out-of-process, so no photo-library usage string is needed —
  nothing to add there. If plan 06's coarse-location option ships later,
  `NSLocationWhenInUseUsageDescription` becomes required then.

### A6. UGC requirements (Guideline 1.2) — mostly done, verify
Apps with user-generated content need: content reporting ✓ (profiles), blocking ✓,
a way to filter objectionable content ✓ (review-before-publish), **and published
developer contact info**. Two gaps:
- Chat messages are not reportable — plan 07 covers it; it's required, not optional.
- Add a "Contact us" (mailto) row in Profile → About, and support URL in App Store
  Connect. Use a product address, not a personal Gmail (see B2).

## B. App Store Connect / browser work (queue as DISPATCH-3)

### B1. Host the privacy policy at a public URL
`docs/privacy-policy.md` must live at a stable HTTPS URL (GitHub Pages is fine).
Referenced from: App Store Connect app record, the paywall (A2), and the in-app
Privacy & safety sheet (`ProfileView.swift` currently says "will be hosted before
release" — replace with the link).

### B2. Replace the personal contact email
The privacy policy and review-queue contact is `bronson.p.thomas@gmail.com`. Set up
`support@` / `privacy@` on a domain (or at minimum a dedicated product mailbox) before
the policy is published — this address becomes permanently public.

### B3. App record + metadata
- Create the app record (bundle ID `com.bronsongarcia.VillageFeed`), category Food & Drink
  (secondary: Social Networking).
- **Age rating: complete the questionnaire to land at 17+** — required by our own age
  gate and appropriate for meeting-strangers UGC.
- Screenshots (6.9" and 6.5" minimum), description, keywords, promo text. The copy
  bank in README.md is the marketing voice.
- App Privacy "nutrition label": declare Contact Info (email), User Content (photos,
  messages, bio), Identifiers (user ID), Purchases; dietary tags fall under
  "Health & Fitness"-adjacent sensitive info — declare under User Content honestly.
  All "linked to you"; none used for tracking (we have no ads/analytics — keep it
  that way at launch to keep this label clean and skip the ATT prompt entirely).

### B4. Subscription product
- Create subscription group + `app.villagefeed.plus.monthly` in App Store Connect,
  with localized display name, price, and the required subscription screenshot.
- Paid Apps agreement + banking/tax forms must be complete before any paid product
  clears review — start this early, it has multi-day latency.

### B5. Review notes for the submission
Reviewers can't see another user, so provide: a demo account (pre-seeded with a
match and a group so Likes/Groups aren't empty), a sentence explaining the
trade/report/freeze model, and a note that food exchange is non-commercial. Apps
about meeting strangers + home-cooked food will get a careful review — the safety
story in `SAFETY-NOTES.md` is an asset; summarize it in the notes.

### B6. Supabase production settings
- Re-enable email confirmation (deliberately off for testing per DISPATCH-2) — do
  this *at* launch, coordinated with B5's demo account which should be pre-confirmed.
- Confirm both edge functions deployed; `ANTHROPIC_API_KEY` secret set (round 1 ✓).

## C. Suggested order

1. A1 (SIWA — biggest code item, needs portal work too)
2. A3 + A4 (rip out internal tooling and demo leakage)
3. A2 + A5 + A6 (small code items)
4. B1 + B2 (hosting + email — unblock policy links in A2)
5. B3 + B4 (App Store Connect, start Paid Apps agreement immediately)
6. TestFlight internal build → real-device pass → B5/B6 → submit

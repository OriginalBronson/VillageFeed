# Device Checklist (plan 11-A4)

Run on **physical devices** before every TestFlight/App Store build. One
afternoon; write findings as GitHub issues. Devices: smallest supported
(SE-class) + a large one (Pro Max-class).

## Environment sweep (repeat the core loop in each)

- [ ] Light mode / dark mode
- [ ] Dynamic Type at XL and XXL (cards, pills, chat bubbles, paywall)
- [ ] VoiceOver: swipe the deck, read a card summary, get a match announcement

## Core loop

- [ ] Fresh install → onboarding → gate toggles enable the button → ToS links open
- [ ] Create account (email) → profile wizard → submit → "in review" copy shows
- [ ] Sign in with Apple → account created, name prefilled where Apple provided it
- [ ] Sign in with Google → returning profile hydrates (photo included)
- [ ] Swipe right → match sheet appears only when the server confirms (airplane-mode swipe shows no false celebration)
- [ ] Join a group → join system message appears in table talk
- [ ] Send messages → delivered; long-press → report / delete own
- [ ] Unread badges: Groups tab + group rows + chat row; clear after reading
- [ ] Push notifications (physical device only): match, message (suppressed while reading that chat), member joined, approval; taps deep-link correctly
- [ ] Pledge a dish → system message; propose handoff → RSVP chips; after the time passes → check-in row
- [ ] Paywall: price loads (retry state if network blocked), links work, purchase in sandbox, blur lifts with the welcome banner
- [ ] Restore purchases on a second device

## Failure modes

- [ ] Airplane mode mid-session: banner appears; swipes/messages/blocks queue; back online → everything drains (check server rows), no duplicates
- [ ] Force-quit with a queued message → relaunch → message still marked sending → delivers
- [ ] Photo upload over cellular (large HEIC) → downscaled, completes
- [ ] Reinstall while signed in → profile round-trips from the server, photo included, wizard does NOT re-run
- [ ] Delete account → confirm profile, dishes, photos (storage bucket!), messages gone server-side

## Contrast / a11y spot checks

- [ ] Orange pills on white and dark backgrounds ≥ 3:1 (WCAG large-text)
- [ ] Green trade badge readable in dark mode
- [ ] All tap targets ≥ 44pt (undo/report buttons under the deck)

# VillageFeed

**Make one dish, eat many.** Cook once, eat all week — swipe to find neighbors to trade
home-cooked meal portions with, form supper groups (2+ people), and turn one giant lasagna
into a week of different dinners.

## What's here (v0.1 — local prototype, no backend)

- **Discover** — Tinder-style card deck of nearby cooks *and* open supper groups. Right-swipe
  a cook → match if mutual; right-swipe a group → join it. Cards show the main photo (person
  or dish), advertised dishes with portion counts, and dietary-constraint pills.
- **Groups** — your supper groups: members + this week's dishes, a "seeking members" toggle,
  and group-to-group **merge**. Groups start at 2 people (a match can seed one); you can be a
  solo member of many groups.
- **Likes** — the paid tier. Free users see a blurred grid + count; **VillageFeed Plus**
  (StoreKit 2 subscription, `app.villagefeed.plus.monthly`, simulator-testable via
  `Products.storekit`) reveals everyone who swiped right on you.
- **Profile** — name/neighborhood/bio, photo picker (use yourself or a dish as the main
  photo), dietary pills, dish advertising, and submit-for-review.
- **Moderation** — report → instant freeze → review queue. Queue items can be triaged by the
  Claude API (`claude-haiku-4-5`) or resolved directly by a human (no API cost). See
  `SAFETY-NOTES.md` for the launch-blocking safety list.

Data is seeded in-memory (`AppStore.swift`) — the store is the seam where a backend
(Supabase or similar) slots in later.

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

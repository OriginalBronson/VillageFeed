# Plan 06 — Discovery Filters & Real Neighborhoods

**Complaints this prevents:** "I'm vegan and every card is brisket" and "it matched
me with someone 40 minutes away." Both are first-session experiences, which makes
them the most likely 1-star reviews in week one. Two workstreams, shippable
separately.

## A. Dietary compatibility

The data already exists on both sides (`dietaryTags` per profile, allergen notes per
dish) — the deck just ignores it.

### A1. Hard screens (automatic, no UI)
Never show a card that's *incompatible by declaration*: e.g. viewer has
`nutAllergy` and every dish on the card declares nuts; viewer is `vegan`/`halal`/
`kosher` and no dish on the card is plausibly compatible. Be conservative —
allergen notes are free text, so only auto-screen on the *structured* tags, and when
unsure, show the card. Implement as a scoring pass in `rebuildDeck()` (client) first;
move into the pull RPC when the deck goes server-driven.

### A2. Soft ranking
Sort compatible-and-appealing first: shared tags (vegetarian viewer ↔ vegetarian
cook), then same-neighborhood (existing rule), then dish photo present. Keep it a
simple additive score — no ML, fully explainable.

### A3. Filter sheet (user control)
A filter button on Discover's nav bar: toggle chips for "must be" tags
(vegetarian, gluten-free, …) and "never show" allergens. Persist in the profile.
**Important honesty rule:** when filters empty the deck, say so ("No gluten-free
cooks nearby yet — 4 cooks hidden by your filters") rather than showing the generic
empty state; otherwise filters get blamed as "the app is dead".

## B. Structured neighborhoods

Free-text neighborhood breaks matching (typos/synonyms), sorting, and honesty about
distance. Options considered:

1. **Precise location + radius** — rejected: contradicts the safety posture
   (SAFETY-NOTES §3: never expose distance precise enough to triangulate) and adds a
   location-permission + privacy-label cost.
2. **Curated neighborhood list per metro** — rejected for launch: an ops treadmill.
3. **Recommended: self-reported area at fixed coarse granularity.** Ask for ZIP/postal
   code at profile setup, store only the ZIP, and *display* the neighborhood label the
   user types (label = vanity, ZIP = matching truth). "Nearby" = same or adjacent ZIP
   (static adjacency via prefix match at launch — same first 4 digits — upgradeable
   to a real adjacency table later without schema change).

Changes:
- `profiles.area_code text` column; profile setup (plan 03-O1) and Profile form get a
  ZIP field with "used only to sort nearby cooks — never shown" caption. Shown on
  cards stays the friendly label.
- Deck sort: same ZIP → adjacent ZIP → rest; cards show "~your area" / "nearby" /
  "farther out" pills instead of raw labels from strangers.
- Privacy policy already says "we never collect precise location" — a ZIP is coarse
  but *is* new collection: add one line to the policy (plan 01-B1 before hosting).

## Cold-start tie-in

With ZIPs, the D1 empty state (plan 03) can be honest and motivating: "3 cooks in
07040 · 11 nearby — invite a neighbor to unlock your village." An invite share-sheet
(pre-written message + App Store link) belongs in this workstream; hyperlocal apps
grow or die on this loop.

## Sequencing

A1+A2 are a day and need no migration — do them immediately. A3 ~1 day. B is ~2 days
including migration and profile-setup touchpoints. Ship A with the launch build if
possible; B in the same release as plan 03-O1 profile setup (both touch onboarding).

# VillageFeed Plus — premium feature candidates

What Plus is for: funding a village-run kitchen table without degrading the free
experience or paywalling anything safety-critical. Trading stays free; Plus sells
convenience, reach, and delight.

## Shipped

- **See who liked you.** Everyone who swiped right on you, even before a match.
  StoreKit 2 subscription; server-verified via the `sync-entitlement` edge
  function so the `who_liked_me()` RPC only unlocks for real subscribers.

## Strong candidates (roughly ordered)

1. **Fresh-batch alerts.** Plus cooks can notify their neighborhood when they
   post a new dish ("Maya just posted 8 portions of eggplant parm"). High
   perceived value, directly drives the core loop, naturally rate-limited
   (say, one per week) so it can't become spam.
2. **Neighborhood passport.** Browse and trade beyond your home neighborhood —
   the free deck stays local, Plus roams the whole city. Cleanly additive; the
   free tier loses nothing.
3. **Advanced deck filters.** Filter Discover by dietary tags, portion counts,
   or "has photos of the actual dish." Free keeps the default deck; Plus curates.
4. **Bigger menu.** Free advertises up to 2 dishes; Plus gets an unlimited menu
   plus a "coming this week" schedule so neighbors can plan around your cooking.
5. **Full swipe rewind.** Free keeps the current one-card undo; Plus can rewind
   through the session's history to rescue any accidental pass.
6. **Supper-group tools.** Larger groups, a potluck rotation planner ("who cooks
   which night"), and calendar export. Charged to the group creator, benefits
   the whole group — good word-of-mouth mechanics.
7. **Weekly batch boost.** One card boost per week that surfaces you earlier in
   neighbors' decks. Keep it scarce and label it — boosts must never make the
   free deck feel worse or bury unpaid cooks entirely.
8. **Supporter flair.** A subtle "village patron" badge and profile accents.
   Zero product risk, pure support signal.
9. **Annual plan.** Same features, ~2 months free — pricing candidate rather
   than a feature, but usually the highest-leverage revenue change.

## Deliberately not premium

- **Safety features.** Blocking, reporting, allergen notes, moderation, and the
  incident flow stay free forever — paywalled safety is a liability, not a
  feature (see `SAFETY-NOTES.md`).
- **Verified-cook badge.** Verification builds marketplace trust; selling it
  turns it into a scam vector. If it costs us money to run, it's a cost of
  doing business, not an upsell.
- **Matching or messaging caps.** The network is young — throttling the core
  loop to force upgrades would shrink the village Plus depends on.
- **Anything that moves money for food.** Trading portions ≠ selling food;
  payment features trigger food-service licensing law (see `SAFETY-NOTES.md` §6).

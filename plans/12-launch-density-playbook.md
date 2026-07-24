# Plan 12 — Launch & Density Playbook

**The failure mode this prevents:** a technically perfect App Store launch into
fifty cities at once, producing one lonely cook per ZIP code, an empty deck for
everyone, and a dead app with good reviews of the *idea*. VillageFeed's unit of
success is not downloads — it's **one neighborhood where trades happen weekly**.
Every hyperlocal product that worked (early Nextdoor, Buy Nothing groups) launched
as a density strategy, not a distribution strategy.

This plan is product work + founder legwork; it has almost no code in it, which is
exactly why it needs a written plan — nothing on the engineering board forces it to
happen.

## A. The founding-village model

1. **Pick one launch neighborhood** — realistically, yours. Criteria: you can
   personally recruit 20 cooks; favorable food-law state (plan 09-B feeds this);
   walkable density so handoffs are genuinely convenient.
2. **Recruit 15–25 founding cooks by hand** before the app is public: neighbors,
   local Buy Nothing / mutual-aid groups, a flyer at the farmers market. The pitch
   is the copy bank line ("cook once, eat all week"), not "try my app".
   These people are the external TestFlight cohort (plan 11-C2).
3. **Founder-as-concierge for the first month**: personally seed 2–3 supper groups,
   pledge a real dish weekly, propose the first handoffs. The app's job is to make
   the *second* month self-sustaining.
4. **Define the health metric now**: weekly completed handoffs per active
   neighborhood (plan 05's check-in makes it measurable). Target for calling the
   pilot successful: ≥3 groups completing handoffs 3 weeks running without founder
   involvement. Everything else (downloads, swipes, matches) is vanity relative to
   this number.

## B. Product mechanics that serve density (small code items)

- **Invite loop with attribution**: share-sheet invite from the empty deck and from
  group detail ("your group has room — invite a neighbor"), carrying a referral code
  so we know which loops work. The empty-state invite is plan 03-D1; this adds the
  group-side loop and the attribution column.
- **Waitlist outside the launch area**: when a signup's ZIP (plan 06-B) has no
  active village, be honest — "VillageFeed hasn't reached 07040 yet. You're #3
  here; we'll notify you at 15." Converts dead-app first impressions into a
  growth signal, and tells us where to expand. (One table, one screen, one push.)
- **Village threshold, not user threshold**: unlock Discover in a new ZIP cluster
  only when ~10 cooks with dishes exist there; until then, everyone local sees the
  waitlist count and the invite tools. Painful to gate, but an empty deck teaches
  users the app is dead — a filling waitlist teaches them it's coming.

## C. App Store presence (supports the strategy rather than fighting it)

- Screenshots/description sell the *founding-village story* ("start your village")
  rather than implying an existing crowd — honest, and converts the reality of
  low density into an invitation. Keywords: meal swap, batch cooking, supper club,
  neighbors, meal prep.
- Launch PR is local, not tech: neighborhood Facebook/Nextdoor groups, the local
  paper's food column, the farmers-market newsletter. One good local story beats
  a Product Hunt launch for this product.

## D. Expansion rule

No second metro until the first hits the health metric for 6 consecutive weeks.
Then expansion = repeat A2–A3 with a local champion instead of the founder
(recruit them from the waitlist's densest ZIP).

## Sequencing

A1–A2 start **now** — recruiting runs in parallel with all engineering phases and
is the longest pole. B's waitlist + threshold ride the plan 06-B ZIP work. C lands
with plan 01-B3 metadata. The pilot begins the day external TestFlight opens.

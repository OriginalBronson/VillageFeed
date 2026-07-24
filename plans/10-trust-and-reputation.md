# Plan 10 — Trust & Reputation

**Complaint this prevents:** "I matched with 'Maria' whose profile was three stock
photos of paella, planned a whole handoff, and got stood up. How was I supposed to
know?" Swiping on strangers' home cooking requires more trust than swiping on dates —
the food goes *inside you*. Today every profile looks equally credible the moment
it clears review, and nothing a user does well ever becomes visible.

This is the moat feature: matching UIs are commodity; a believable neighbor-trust
signal is not. It builds directly on plan 05's check-in (the data source) and
SAFETY-NOTES item 7 (photo authenticity / fake profiles).

## Principles

- **Signals from actions, not opinions.** No 5-star ratings of neighbors — star
  ratings on people turn a village into Yelp, invite retaliation, and are mostly
  noise at our scale. Everything below derives from *verifiable events*.
- **Positive-only in public.** Negative signals route to moderation (reports,
  incident flow), never onto a public profile. A neighborhood app where people can
  see they've been downvoted by neighbors is a social disaster.

## v1 signals (cheap, all from existing/planned data)

Shown as small badges on `PersonCard` / `PersonDetailSheet`:

1. **Trades completed** — count of plan-05 handoffs where the member pledged and the
   check-in wasn't "didn't show". "🍲 12 trades" is the single strongest signal and
   costs one query.
2. **Member since / neighbor tenure** — "On VillageFeed since March". Fake profiles
   are new profiles; tenure is free anti-fraud.
3. **Reliability, privately enforced** — repeated "didn't show" check-ins don't show
   on the profile; they open a review case at a threshold (e.g. 3 in 30 days).
   Moderation handles it; the public surface stays kind.

## v2 — Verified cook (needs product decision + a bit of infra)

- **Photo verification** (the dating-app pose-match pattern): user submits a
  liveness selfie matching a prompted gesture; compare against profile photo.
  v2 implementation: human review of the pair via the existing review queue — at
  early scale that's minutes/week and needs zero new ML. Grants a ✓ badge.
- **Dish authenticity nudge** (lighter, food-specific): dish photos taken through an
  in-app camera flow get a "📷 shot in-app" mark. Cheap, opt-in, and directly
  attacks the stock-photo-paella problem without biometrics.
- Hash-matching known-bad images at upload (SAFETY-NOTES) belongs in the storage
  pipeline when scale justifies it; not before.

## Schema sketch

```sql
-- v1 needs only views over plan-05 tables + profiles.created_at
create view trade_counts as
  select member_id, count(*) as trades
  from handoff_rsvps r join handoffs h on ...
  where r.status = 'went' group by member_id;

alter table profiles add column verified_at timestamptz;  -- v2
```
Counts ride along in the pull; no client schema changes beyond two optional fields
on `UserProfile`.

## What we deliberately don't build

- Public reviews/comments on people, star ratings, "top cook" leaderboards
  (leaderboards create losers; villages don't need losers).
- ID-document verification (KYC vendor cost + data liability wildly out of
  proportion at launch scale).

## Sequencing

v1 rides plan 05's schema — build in the same release or the one after. v2 verified
cook is post-launch, once there are enough users for fakes to be worth anyone's
time. Estimated: v1 ~1–2 days once plan 05 exists; v2 ~2–3 days plus review-queue ops.

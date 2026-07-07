# Plan 05 — Handoff Planner ("This Week's Table")

**Complaint this prevents:** "Cute app, but we matched and then… nothing. We texted
back and forth about where to meet, she forgot, and I ate eight portions of my own
ragù again." The app currently ends at the match; the product promise ("one lasagna
becomes seven dinners") happens entirely off-app, unassisted. This is the retention
feature.

It's also the top SAFETY-NOTES item (meeting strangers): the app should actively
steer handoffs to public places, and today that guidance is one line of chat
placeholder text.

## Concept

Each group gets a lightweight weekly cycle — not a calendar app, three states:

1. **Pledge** — each member marks what they're bringing this week: pick one of your
   profile dishes + portion count. Replaces the current "first profile dish" guess in
   "This week's table" with actual commitments. Non-pledgers show as "sitting out
   this week" (guilt-free — sustainable cadence beats streaks).
2. **Plan the handoff** — one member proposes place + time; members tap **I'll be
   there**. Place is a *named public spot* chosen from suggestion chips (library,
   farmers market, park, school pickup) or free text — with a persistent hint that
   public spots are the norm. Never a structured "home address" field: the design
   should make sharing an address feel like the exception it should be.
3. **Done** — after the handoff time passes, a one-tap "How'd it go?" check-in per
   member: 👍 / "someone didn't show" / **report a problem** (routes to the incident
   flow, plan 02-§9). The check-in doubles as the safety touchpoint from
   SAFETY-NOTES ("in-app check-in after first trades").

## Data model

```sql
table week_pledges  (id, group_id, member_id, dish_id, portions, week_start date)
table handoffs      (id, group_id, spot text, at timestamptz, proposed_by, week_start)
table handoff_rsvps (handoff_id, member_id, status)  -- going / can't
```
RLS: group-members-only on all three (same pattern as `group_messages`). Week
boundary = local Monday; server stores the date, client computes "this week".

## UI

- `GroupDetailView`'s "This week's table" section becomes the pledge list +
  "Add your dish" button (reuses dish picker from profile) + handoff card (proposed
  spot/time, RSVP chips, propose button when none exists).
- Post system messages into table talk on pledge/proposal/RSVP ("Sam pledged 12
  portions of Smoked Brisket 🍖") — the chat becomes the activity feed for free, and
  plan 04's message pushes carry the news.
- Discover group cards can then show real liveness: "traded 6 portions last week"
  beats "3 members".

## Explicitly deferred

- Portion-for-portion fairness accounting/ledgers — social pressure is the v1
  enforcement; ledgers make neighbors feel audited.
- Recurring schedules, multiple handoffs per week, delivery coordination.
- Maps/geocoding — the spot is a text label on purpose (no location permissions,
  no precise-location privacy surface).

## Sequencing

Depends on nothing; lands best after plan 07 (chat is the surface the system
messages live in). Estimated ~3–4 days client + 1 day migrations/RPCs.

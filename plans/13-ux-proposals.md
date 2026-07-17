# Plan 13 — Proposed: the features that finish the experience

Plans 01–12 are executed (see 00-roadmap status). This doc proposes what to
build *next*, chosen by walking the product as three people: a brand-new cook,
a member of a working supper group, and a cook whose group went quiet. Each
proposal says what breaks without it, in complaint form — same discipline as
plan 03. Ordered by product consequence, not engineering fun.

## P1 — Close the loops the launch build opens

### 1. First-trade guide for new two-person groups
**Complaint prevented:** "We matched, started a 'group', and then stared at an
empty chat. Neither of us knew what was supposed to happen next."
A match now creates a two-person group with a pledge system and a handoff
planner — but nothing *sequences* them for first-timers. Proposal: new groups
show a three-step guide card at the top of group detail (① both pledge a dish
→ ② agree on a public spot → ③ check in after), each step lighting up as it
completes, disappearing after the first completed trade. The mechanics all
exist; this is choreography, not features. ~1 day.
*Principle in play: a feature isn't done when it's possible — it's done when
the first-time path through it is obvious.*

### 2. Dietary conflict warning at pledge time
**Complaint prevented:** "I'm nut-allergic and my group's 'this week's table'
was pecan pie. The app knew both facts."
Discover already hard-screens allergens (plan 06), but *inside a group* the
deck's protection doesn't apply. When pledging, if the dish's allergen note
matches a group member's declared allergy tag, show an inline warning ("Maya
has a nut allergy — consider your other dishes or note cross-contamination").
Warning, not a block: neighbors talk. Half a day; pure client logic over data
already on-device. This is the single cheapest safety feature left.

### 3. Handoff reminder push
**Complaint prevented:** "She forgot. I stood at the farmers market with a
crockpot."
The quiet-app rule (plan 04) says: only push when a human acted toward you — a
handoff *you RSVP'd to* qualifies. One reminder, ~2 hours before, to "going"
RSVPs only. Server-side: pg_cron job scanning upcoming handoffs → send-push.
~1 day including the cron migration. This is the retention feature's seatbelt:
one no-show can kill a young group.

## P2 — Trust and rhythm (first post-launch month)

### 4. Verified cook v2 (already designed in plan 10)
Photo-verification via the existing review queue + the "📷 shot in-app" mark
for dish photos taken with an in-app camera. Build when fakes are worth
anyone's time — the trigger metric is the first fake-profile report from a
real neighborhood, not a calendar date.

### 5. Recurring handoffs for established groups
**Complaint prevented:** "Every single week we re-type 'library, thursday,
5:30'."
Plan 05 deferred this deliberately. Trigger: a group completes 3 consecutive
weeks with the same spot/time → offer "Make Thursdays 5:30 at the library your
usual?" One tap pre-creates each week's handoff; anyone can still edit. The
detection is a 5-line query over data we already record. ~1–2 days.
*Principle: earn automation from observed behavior instead of asking upfront —
settings screens are where good defaults go to die.*

### 6. "Your village plate" — personal trade history
**Complaint prevented (subtle, retention-shaped):** "I couldn't tell you if
this app is doing anything for me."
A small Profile section: meals traded, portions shared, cooks met, current
streak-free tally ("14 dinners you didn't cook"). All derivable from
handoff/pledge history. Positive-only, private-only — no leaderboards
(plan 10's rule: villages don't need losers). ~1 day.

## P3 — Density tools (when expansion starts, per plan 12's rule)

### 7. Waitlist notify-at-threshold
The village-threshold screen (built) counts cooks but can't *tell* waiting
users when the village unlocks. Server piece: on the profile push that tips a
ZIP cluster past 10, send-push to that cluster's waiting devices ("Your
village is live — 10 cooks in 07040"). Rides existing webhook + token infra.

### 8. Neighborhood champion toolkit
Plan 12-D expansion needs a local champion per new metro. In-product support:
a "founding cook" badge (tenure signal variant), plus an invite dashboard
(your code's signup count — the referred_by column already records it).

## Deliberately not proposed

- **Payments/tips** — triggers licensing law, breaks the gift economy (ToS §4).
- **Star ratings** — plan 10's reasoning stands; check-ins carry the signal.
- **Precise location/maps for handoffs** — safety posture (SAFETY-NOTES §3).
- **Feed/stories/social surface** — the product is the trade, not the scroll.
  Every hour on a feed is an hour not cooking.
- **iPad / macOS** — iPhone-only until a village asks for it.

## Suggested order

1–3 before public launch if the timeline allows (all three are days, not
weeks, and each guards the first real trade — the moment the product either
proves itself or doesn't). 4–6 from live-usage triggers. 7–8 gated on the
plan 12 expansion rule (first metro healthy 6 consecutive weeks).

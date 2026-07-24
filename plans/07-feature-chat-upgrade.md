# Plan 07 — Chat Upgrade (Table Talk v2)

**Complaint this prevents:** "The 'chat' is a text field at the bottom of a settings
page that shows the last 30 messages." Chat is where every trade is actually
arranged; after launch it will be the most-used surface in the app. It also carries a
**launch-blocking safety item**: messages cannot be reported (SAFETY-NOTES §5 — group
chat needs message reporting before real users).

## 1. Dedicated chat screen

Pull table talk out of `GroupDetailView`'s Form into a real messaging view:

- `GroupChatView` pushed from a prominent "Table talk" row (with last-message
  preview + unread count) in group detail.
- Standard mechanics: `ScrollViewReader` pinned to latest, inverted-feel scrolling
  through full history (paginate by 50 via the existing pull; drop the
  `.suffix(30)` cap), message bubbles grouped by sender with day separators,
  keyboard-attached input bar (`safeAreaInset`), send-in-flight state.
- Keep the existing realtime subscription; add optimistic-send reconciliation
  (message appears immediately, marked failed-retry if the insert errors — today a
  failed `sendMessage` sync is silent).

## 2. Unread model (shared with plan 04)

- `group_members.last_read_at timestamptz` — set on chat appear/disappear.
- Unread count per group = messages newer than that; surfaces as: Groups tab badge,
  bold group rows, count on the Table-talk row. Plan 04 reuses it to suppress pushes
  for the group you're currently reading.

## 3. Message safety (launch-blocking)

- **Report message**: long-press context menu → report (reuses `ReportReason` +
  the existing report pipeline and rate limit). A reported message freezes the
  *sender* per the existing report-trigger semantics and attaches the message text
  to the review case so the moderator sees the actual content.
- **Delete my message**: long-press → delete (RLS: sender-only delete). Required
  companion to reporting — people need to remove their own mistakes.
- Blocked users' messages already filtered client-side; plan 02-§2 makes it
  server-side. Keep the client filter for instant effect.

## 4. Small trust details

- Sender identity: show the sender's avatar (tap → `PersonDetailSheet`, which after
  plan 03-D5 carries report/block) so "who is this person in my group" is one tap.
- System messages (member joined/left, pledges from plan 05) render as centered
  captions, distinct from human messages.
- Copy nudge stays: keep the "agree on portions and a public handoff spot" hint as
  the empty-chat state, now styled as a system message.

## Sequencing

Do this **before** plan 04's message pushes (unread model) and **before/with** plan
05 (system messages live here). Message reporting (§3) is required for launch even
if the rest slips — it's ~half a day on its own against the existing pipeline.
Full plan: ~3 days client + small migrations (`last_read_at`, delete policy,
report-message linkage).

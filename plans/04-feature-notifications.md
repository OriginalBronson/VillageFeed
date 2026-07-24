# Plan 04 — Push Notifications

**Complaint this prevents:** "I matched with someone and found out three days later.
By then she'd given the lasagna to someone else." A trade app with silent matches and
silent chat doesn't work — every session currently starts by chance.

## Scope (v1)

Notify on exactly four events, all high-signal:

1. **New match** — "🎉 You and Maya both want to trade" → opens Groups tab (matches section)
2. **New group message** — "Sam (Maplewood Supper Swap): brisket's ready Thursday" → opens that group's chat
3. **Someone joined your group** — "Priya joined Old Town Stew Crew" → opens group
4. **Profile approved** — "You're live in Discover" → opens Profile

Explicitly *not* in v1: like notifications ("someone liked you" — this is paywall
bait and earns notification fatigue + resentment), digest emails, marketing pushes.
A quiet app that only speaks when a human acted toward you is a differentiator here.

## Architecture

- **APNs via Supabase**: store the device token in a `device_tokens` table
  (user_id, token, updated_at; RLS: owner-only). Refresh token on every launch.
- **Delivery**: one new edge function `send-push` holding the APNs key (p8) as a
  secret. Database webhooks (Supabase → edge function) fire it on inserts to
  `matches`, `group_messages`, `group_members`, and on `profiles.status`
  transitioning to `active`.
- For message pushes, respect blocks (plan 02-§2) and skip when the sender is the
  recipient. Payload contains IDs only + display text; no need for rich media v1.
- **Client**: request permission *contextually*, not at launch — the right moment is
  immediately after the first match ("Want to know when Maya replies?"). Pre-permission
  soft-prompt sheet, then the system dialog. Launch-time permission prompts get ~40%
  denial and there's no recovering.
- Deep-link routing: a lightweight `NotificationRouter` that sets the selected tab +
  presented group. The tab view in `VillageFeedApp.RootView` needs a
  `@State selection` binding first (it's currently unmanaged).

## Badging / in-app state

- App icon badge = unread messages + unanswered matches (clear on open).
- This work shares the "unread" model with plan 07 (chat upgrade) — build the
  `last_read_at` per-group column there first; notifications then reuse it to
  suppress pushes for conversations you're actively looking at.

## Apple-side setup (dispatch items)

- Enable Push Notifications capability + create the APNs key in the developer portal.
- Store the p8 key as a Supabase secret.
- Test on a physical device (pushes don't work in simulator pre-iOS 16 style; token
  flows should still be verified on hardware regardless).

## Sequencing

Build after plan 07's unread model if both are in flight; otherwise ship v1 with
matches + approvals only (no unread dependency) and add message pushes with plan 07.
Estimated: edge function + webhooks ~1 day, client permission/routing ~1–2 days,
device testing ~half day.

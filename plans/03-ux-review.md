# Plan 03 — UX Review

A screen-by-screen audit of the current build, framed as the complaint a real user
would leave in an App Store review. Each finding has a priority:

- **P1** — fix before submission (reviewer- or trust-breaking)
- **P2** — fix in launch window (predictable 1–3-star review otherwise)
- **P3** — quality; schedule opportunistically

The four biggest P2 themes have their own feature plans (04–07); they're
cross-referenced, not duplicated, here.

---

## Onboarding & sign-in

**O1 (P2) — "I did the tutorial, then it made me sign in, then dumped me on strangers."**
Order today: 4-page onboarding → sign-in → Discover. Nothing prompts you to build
your own profile, so new users swipe with an empty bio, no dishes, and the seed name
"You". Since cooks-with-dishes get traded with most (the app's own empty-state copy
says so), this quietly ruins the new user's first week.
→ Add a profile-setup step after first sign-in: name, neighborhood, one dish, photo
optional. Three fields, skippable, but defaulted into the flow.

**O2 (P1) — legal gate incomplete.** The age/food-risk toggles are good, but there's
no link to Terms of Service or the privacy policy at signup — for an app with real
safety exposure, acceptance needs to be attached to *something readable*. Add "By
continuing you agree to the [Terms] and [Privacy Policy]" under the gate toggles
(URLs from plan 01-B1).

**O3 (P2) — "It signed me out and I lost everything?"** Onboarding completion is an
`@AppStorage` bool, profile lives in local JSON keyed to nothing. Reinstall → profile
gone unless it synced. Verify a signed-in reinstall round-trips the profile from the
server (photo included), and that `hasOnboarded` is skipped when an existing account
signs in.

**O4 (P3) —** password field has no minimum-requirements hint and sign-up errors
surface raw Supabase strings (`auth.lastError`). Map the common ones ("already
registered", "weak password") to human copy.

## Discover

**D1 (P2) — "There's nobody on this app."** The cold-start / empty-deck state is the
most important screen in a hyperlocal app and today it says "That's everyone nearby —
pull to refresh." For a launch-day user in an empty neighborhood, that's the whole
app. → Give the empty state a job: share-sheet invite button ("Every village starts
with two cooks — invite a neighbor"), and show *how many* cooks exist in adjacent
neighborhoods to set expectations honestly. Ties into plan 06 (structured
neighborhoods) and is why the App Review demo account needs seeded matches (01-B5).

**D2 (P2) — "Why is it showing brisket to a vegan?"** No dietary filtering — the deck
ignores both parties' tags entirely. Predictably the single loudest complaint for a
food app. → Plan 06.

**D3 (P2) — "Everyone is 40 minutes away."** Neighborhood is free text
(`"Maplewood"`), and same-neighborhood-first sorting breaks on any typo or synonym
("Maplewood" vs "maplewood" vs "Maplewood Heights"). → Plan 06.

**D4 (P3) — group cards can't be inspected.** Tapping a person card opens
`PersonDetailSheet`; tapping a group card does nothing — you must join a group to see
its members' dishes. Swiping right on strangers' word alone is a weird ask. → Add a
`GroupDetailSheet` (members, dishes, neighborhood spread) on tap.

**D5 (P3) — report/block placement.** The flag button under the deck only targets the
top card, and there's no report/block inside `PersonDetailSheet` — the very screen
where you'd notice a problem. Add it to the sheet toolbar. (Message reporting: plan 07.)

**D6 (P3) — undo semantics.** The undo button silently does nothing if the swipe
produced a match/join (by design). Rather than a dead tap, disable it in that state —
`lastSwipedCard` already knows.

## Groups

**G1 (P2) — "The chat is a text box inside a settings form."** Table talk renders as
rows in a `List` section, capped at the last 30 messages, keyboard fights the form,
no scroll-to-latest, no unread indication anywhere (no badge on the tab, no bold row).
Chat is where trades actually get arranged — it's the most-used surface after launch
and currently the weakest. → Plan 07.

**G2 (P2) — "I posted my lasagna but nobody brought anything."** "This week's table"
lists each member's *first profile dish* — there's no concept of what anyone is
actually contributing *this week*, no portion accounting, no handoff arrangement. The
core promise (one dish in, seven dinners out) has no UI. → Plan 05.

**G3 (P1) — merge is a loaded gun.** Any member can merge another *entire group* into
yours with one confirm, no consent from either group's other members, and the
confirmation is phrased as a feature ("More cooks, more dishes"). Griefing and
awkwardness both. Minimum fix for launch: only allow merge when *you* are in both
groups, or turn merge into a *proposal* posted to both groups' chats requiring an
accept from someone in the other group. Also `openToMerge` exists on the model but
isn't user-visible — expose the toggle next to "Seeking new members".

**G4 (P3) —** matches with no shared group show "Start group", but once started
there's no way to *rename* a group or change its emoji. Add rename/emoji edit in
group detail (creator or any member — pick simple).

## Likes / paywall

**L1 (P1) — paywall legal links + auto-renew disclosure missing.** Covered in plan
01-A2; noted here because it's also user trust: people screenshot paywalls that hide
terms.

**L2 (P2) — "I paid and it's the same grid."** After purchase the sheet dismisses but
nothing celebrates or routes you — the blur just quietly disappears behind the sheet.
Small fix, big feel: on successful purchase, dismiss, un-blur with a spring
animation, and show a one-time "Say hi to the cooks who liked you" banner.

**L3 (P3) —** free-tier blurred grid uses local `likesYou` data (plan 02-§3 makes the
server withhold identities; after that the blurred cells become placeholders — make
sure the design still reads as "real people waiting", e.g. count + generic avatars,
not broken images).

## Profile

**P1 (P1) — "What is a Review queue and why do I have moderation powers?"** The
Moderation section with a badge count ships to every user. Remove/gate (plan 01-A3).

**P2 (P2) — "I edited my profile and vanished from Discover for a day."** Submitting
for review sets `pendingReview` (invisible in Discover) with no explanation of how
long, and nothing tells you when you're approved. Interim fix: copy under the button
("Reviews usually complete within a few hours") + keep the *previous approved
version* live while the edit is in review (server-side: review the delta, don't
unpublish). Notification on approval → plan 04.

**P3 (P2) — no card preview.** You build your profile in a form but never see the
card strangers swipe on. "Preview my card" button rendering `PersonCard(person:
store.me)` in a sheet — cheap to build, prevents the "my card looks broken" class of
complaints, and increases dish-photo adoption.

**P4 (P3) — dish editing is add/delete only.** `DishEditorSheet` only creates; to fix
a typo or update portions you delete and re-enter (and lose the photo). Make rows tap
to edit, reusing the same sheet.

**P5 (P3) — no blocked-users list.** Blocking is permanent and invisible; a
misjudged block on a neighbor is unrecoverable. Add Profile → Account → Blocked
users with unblock (after plan 02-§2 makes blocks server-authoritative).

**P6 (P3) — emoji picker is a raw text field** that accepts any string. Constrain to
a small curated food-emoji grid.

## Cross-cutting

**X1 (P2) — no notifications at all.** Matches, messages, group joins, review
approval — all silent. The app only works if people return unprompted. → Plan 04.

**X2 (P2) — accessibility pass.** Good bones (action buttons duplicate the swipe
gesture, several a11y labels exist). Gaps: cards themselves have no VoiceOver
summary (name/neighborhood/dishes as one element), dietary pills and the
orange-on-white palette need a contrast check, Dynamic Type at XXL breaks the
two-row pill layout (`FlowLayoutish` — replace with a real `Layout`), and the
match/joined alerts should be announced. One focused day of work; do it before
screenshots so the fixes are in marketing images too.

**X3 (P3) — loading/error states.** `refresh()` and `sync` failures are all
`try?`-silent. Minimum: a subtle "Couldn't reach the village — showing saved data"
banner when a pull fails, and a spinner state for the first-ever pull (currently the
seeded/empty UI flashes first).

**X4 (P3) — iPad & orientation.** Nothing is iPad-adapted; either set
iPhone-only targeting in the project (fine for v1, one checkbox) or budget a layout
pass. Recommend iPhone-only at launch.

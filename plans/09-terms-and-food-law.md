# Plan 09 — Terms of Service & Food-Law Compliance

There is currently **no Terms of Service anywhere in the repo**. For most apps that's
a formality; for this one it's the legal backbone of the entire safety posture.
SAFETY-NOTES item 1 calls foodborne-illness liability "the existential risk for the
product" and then points at documents that don't exist yet. The onboarding gate
(plan 03-O2) and the UGC guideline (plan 01-A6) both need a ToS URL to link to.

**This plan produces drafts and a checklist for counsel — a lawyer must review before
launch. Budget for a real consultation; this is the one place not to self-serve.**

## A. Terms of Service — what ours must cover beyond boilerplate

1. **Nature of the service**: VillageFeed is a venue connecting neighbors; it does
   not prepare, inspect, handle, or guarantee any food. Trades are private,
   non-commercial arrangements between users.
2. **Assumption of risk + release**: home-prepared, uninspected food; users assume
   the risk and release the platform — the contractual version of the onboarding
   acknowledgment (which currently exists as a toggle with no document behind it —
   the gate must record *which ToS version* was accepted, with a timestamp column
   on `profiles`).
3. **No commerce**: portions may not be sold, bartered for money, or solicited for
   payment (selling triggers food-service licensing; the moderation prompt already
   treats it as a violation — the ToS makes it enforceable).
4. **Prohibited foods list**: the categories many cottage-food regimes prohibit even
   non-commercially — raw milk, home-canned low-acid goods, wild-harvested
   mushrooms, undercooked/raw meat preparations, alcohol. Enforceable via the
   moderation prompt + report reasons.
5. **Honest-disclosure duty**: allergen declaration is a user obligation, and
   misdeclaration is a bannable offense — this converts our per-dish allergen UI
   from a courtesy into a term.
6. **Enforcement**: freeze/ban authority, the appeal path (plan 02-§8), 17+
   eligibility, and account-deletion effect.
7. Standard: arbitration/class-waiver decision (counsel call), governing law,
   indemnification, UGC license (limited: display within the app only).

## B. Food-law research checklist (for counsel)

- **Cottage food / food-freedom laws are state-by-state**, and most regulate *sale*,
  not *gifting/trading* — but a few states treat regular organized exchange as
  distribution. Question for counsel: does a recurring supper-group swap constitute
  "distribution to the public" anywhere we launch?
- Practical mitigation regardless of answer: launch geography is ours to pick
  (plan 12) — pick the first metro partly on favorable food-freedom law
  (e.g. states with broad food-freedom statutes) and expand with a per-state
  gating switch if counsel says it matters.
- Good-Samaritan food-donation acts (federal Bill Emerson Act + state equivalents)
  cover *donations* — worth asking whether structuring trades as mutual gifting
  meaningfully changes exposure.
- Insurance: ask about platform liability coverage once there's revenue; note in
  the risk register either way.

## C. Product changes this drives (small, concrete)

- `docs/terms-of-service.md` drafted (same pipeline as the privacy policy: repo →
  hosted URL, plan 01-B1).
- Onboarding gate links both docs and stores `tos_version` + `accepted_at` on the
  profile row (migration). Re-prompt on material ToS changes (compare versions at
  sign-in).
- Prohibited-foods list embedded in three places from one source of truth: the ToS,
  the moderation prompt in `moderate-profile/index.ts`, and a short human-readable
  line in the dish editor ("No raw milk, home-canned, or wild-mushroom dishes").
- Add "Prohibited food" as a `ReportReason`.

## Sequencing

Draft A and C now (a solid draft makes the counsel hour cheap); the counsel review
happens in parallel with Phase 1 code work and is a launch gate. B's geography
question feeds plan 12's beta-metro choice, so ask it early.

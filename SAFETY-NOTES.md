# VillageFeed — Safety Notes

What ships today, and the safety issues that must be addressed before real users.

## Shipped in v0.1

- **Report → instant freeze.** Reporting a profile immediately sets it `frozen`: it vanishes
  from the Discover deck and the Likes surface and is queued for review. Unfreezing requires
  an explicit approval (human, or AI with a clear "approve" verdict).
- **New-profile review.** Profiles are submitted for review before publishing (status
  `pendingReview` → `active` on approval).
- **AI-backed, human-optional review.** Each queued case can be triaged by the Claude API
  (`claude-haiku-4-5`, cheap classification tier) which returns approve / reject / escalate.
  Only clear approvals auto-resolve; rejections and escalations wait for a human. A human can
  also resolve any case directly with zero API cost — this is the "human participates to cut
  API costs" path.
- **Instant blocking, independent of moderation** (never waits on a reviewer; also hides the
  blocked user's chat messages), plus a **report rate limit** (5 per rolling 24h, client-side)
  so the instant-freeze trigger can't be spammed. A server-side limit on the `reports` table
  should mirror this before launch.
- **Age gate + food-risk acknowledgment** required to finish onboarding; **per-dish allergen
  notes** are structured fields shown on cards.

## Must address before launch (in rough priority order)

1. **Foodborne illness & allergen liability.** This is the existential risk for the product.
   - Prominent, acknowledged disclaimer that food is home-prepared and uninspected.
   - Allergen self-declaration per dish (not just per profile), with "prepared in a kitchen
     that handles nuts/shellfish" style cross-contamination flags.
   - Check cottage-food / home-kitchen laws per state — some jurisdictions prohibit even
     non-commercial exchange of certain foods (raw milk, home-canned low-acid goods, etc.).
     Terms of service must ban the prohibited categories; moderation prompt already treats
     unsafe-food advertising as a violation.
   - An incident-report flow distinct from profile reports ("this food made me sick"), with
     the ability to pause a cook's dishes pending review.
2. **Meeting strangers for handoffs.**
   - Recommend/facilitate public exchange points (library, farmers market, porch drop) rather
     than in-home handoffs; never publish exact home addresses — neighborhood granularity only.
   - Share-my-exchange plan with a friend; in-app check-in after first trades.
3. **Location privacy.** Coarse locations only on cards; fuzz any map pins; never expose
   distance precise enough to triangulate a home.
4. **Minors.** Age-gate at signup (17+ App Store rating); moderation should reject profiles
   that appear to be minors.
5. **Harassment & blocking.** Client-side instant block shipped; make it bidirectional
   server-side (the blocked user shouldn't see the blocker either). Group chat exists —
   membership-gated by RLS; add message reporting.
6. **Money and commerce.** Trading portions ≠ selling food. Ban payment solicitation
   (moderation prompt covers it) — selling home-cooked food triggers food-service licensing
   law and payment-scam vectors.
7. **Photo authenticity / fake profiles.** At scale: liveness or photo-match verification for
   the "verified cook" badge; hash-match known bad images at upload.
8. **Moderation hardening.** Rate-limit reports (report-bombing can weaponize instant freeze
   against innocent users — mitigate with reporter reputation and fast human review);
   moderator audit log; appeal flow for frozen/banned users; the Anthropic API key must move
   server-side (never ship a key in the client — the in-app key field is a dev convenience).
9. **Data practices.** Dietary restrictions are health-adjacent data: minimize collection,
   encrypt in transit/at rest server-side, and support account+data deletion (GDPR/CCPA).

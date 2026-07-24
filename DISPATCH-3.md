# DISPATCH-3.md — round 3 browser tasks for Claude dispatch

You are executing browser tasks for VillageFeed (iOS meal-trading app; Supabase
project `swjnmgfyvagkyugsndiv`, repo github.com/OriginalBronson/VillageFeed).
Rounds 1–2 (DISPATCH.md, DISPATCH-2.md) are complete. Work through phases in
order. If a step fails or looks different than described, stop that phase and
report — don't guess. Make no purchases or plan changes unless a phase
explicitly says to.

## Ready to dispatch

### Phase 1 — Supabase: apply migrations 0007–0014
**Goal:** everything the new build needs server-side: ToS acceptance, report
rate limit + bidirectional blocks + match trigger (hardening), chat unread
model + message reporting, ZIP area codes, push token registry, the handoff
planner + incident reports, trust signals, and referral attribution.
**Steps:**
1. https://supabase.com/dashboard → project `villagefeed` → SQL Editor.
2. Run Appendices **A through H** below, one query each, **in order**
   (0007 → 0014). Each should report success; record any error verbatim and
   stop (don't retry with modifications).
**Bring back:** success/error text for each appendix.
**Done when:** `select tos_version, area_code, referred_by from profiles limit 1`
runs, and `select tgname from pg_trigger where tgname in
('before_report_insert','on_swipe_upserted','on_incident_report','on_rsvp_no_show');`
returns four rows.

### Phase 1b — Supabase: deploy/refresh the edge functions
**Goal:** delete-account now removes ALL the user's photos (GDPR fix);
moderate-profile knows the prohibited-foods policy; send-push is new (plan 04).
**Steps:**
1. Dashboard → Edge Functions. For `delete-account` and `moderate-profile`:
   edit code → replace with the current file from the repo
   (github.com/OriginalBronson/VillageFeed, branch `plans/app-store-readiness`
   or `main` once merged, under `supabase/functions/<name>/index.ts`) → Deploy.
2. Create a new function `send-push` with the repo's
   `supabase/functions/send-push/index.ts`. Deploy it with **JWT verification
   disabled** (it verifies the service-role key itself).
   (Alternative for Bronson locally: `supabase login && supabase functions deploy delete-account moderate-profile && supabase functions deploy send-push --no-verify-jwt`.)
**Bring back:** deploy confirmations.
**Done when:** all three functions show the new code; `send-push` exists.

### Phase 1c — Supabase: database webhooks for push (plan 04)
**Goal:** row changes fire send-push automatically.
**Steps:** Dashboard → Database → Webhooks → create four, all pointing at the
`send-push` edge function (choose "Supabase Edge Function" as target, method
POST, add the service-role Authorization header if the form offers it):
1. `matches` — events: INSERT
2. `group_messages` — events: INSERT
3. `group_members` — events: INSERT
4. `profiles` — events: UPDATE
**Bring back:** the four webhook names/ids.
**Done when:** all four show enabled in the webhook list.

### Phase 1d — Apple Developer portal: APNs key (plan 04)
**Goal:** the key send-push signs its APNs JWTs with.
**Steps:**
1. https://developer.apple.com/account → Keys → create key "VillageFeed APNs"
   with **Apple Push Notifications service (APNs)** enabled. Download the .p8
   (one chance), record the Key ID and Team ID.
2. Also enable the **Push Notifications capability** on the App ID
   `com.bronsongarcia.VillageFeed` (Identifiers → the app id → capability list).
3. In Supabase → Edge Functions → send-push → Secrets, set:
   `APNS_KEY_P8` = file contents, `APNS_KEY_ID`, `APNS_TEAM_ID`,
   `APNS_TOPIC` = `com.bronsongarcia.VillageFeed`, `APNS_ENV` = `sandbox`
   (switch to `production` for App Store builds at launch).
**Bring back:** Key ID + confirmation secrets are set (never paste the .p8 into chat or the repo).
**Done when:** the four secrets exist on the function.

### Phase 2 — GitHub Pages: host the legal docs
**Goal:** privacy policy + ToS at stable public HTTPS URLs (App Store requirement).
**Steps:**
1. Go to https://github.com/OriginalBronson/VillageFeed → Settings → Pages.
2. Source: "Deploy from a branch"; Branch: `main`, folder `/docs`. Save.
3. Wait for the Pages build (Actions tab), then open
   `https://originalbronson.github.io/VillageFeed/privacy-policy` and
   `https://originalbronson.github.io/VillageFeed/terms-of-service` — GitHub
   Pages renders the `.md` files at these extensionless URLs.
**Bring back:** the two final working URLs (paste into `LegalDocs.swift`
`termsURL`/`privacyURL` and App Store Connect later).
**Done when:** both URLs render in a logged-out incognito window.

### Phase 3 — Apple Developer portal: Sign in with Apple (plan 01-A1)
**Goal:** enable the SIWA capability server-side so the new in-app Apple button works.
**Steps:**
1. https://developer.apple.com/account → Certificates, Identifiers & Profiles → Identifiers.
2. Open the App ID `com.bronsongarcia.VillageFeed` (create it if missing, platform iOS).
3. Enable the **Sign in with Apple** capability → Save.
4. Create a **Services ID** (e.g. `com.bronsongarcia.VillageFeed.signin`) with Sign in with Apple enabled; configure it with primary App ID = the app.
5. Keys → create a new key with **Sign in with Apple** enabled, primary App ID = the app. Download the `.p8` once; record the Key ID and your Team ID.
**Bring back:** Key ID, Team ID, Services ID, and the .p8 file (keep out of the repo; needed for Phase 4).
**Done when:** the App ID shows Sign in with Apple enabled.

### Phase 4 — Supabase: enable the Apple auth provider
**Goal:** Supabase accepts Apple identity tokens from the app (native flow).
**Steps:**
1. https://supabase.com/dashboard → project `villagefeed` → Authentication → Sign In / Up → Providers → Apple.
2. Enable it. For the **native iOS flow**, add `com.bronsongarcia.VillageFeed` to "Authorized Client IDs". (Secret/Services-ID fields are only needed for web OAuth — fill them from Phase 3 if the form requires them.)
**Bring back:** confirmation it's enabled.
**Done when:** provider list shows Apple enabled.

### Phase 5 — Supabase: fill the anon key into the app (plan 01-A4)
**Goal:** release builds must not run in demo mode with fictional people.
**Steps:**
1. Project Settings → Data API → copy the **anon/public** key.
**Bring back:** the anon key — paste into `VillageFeed/SupabaseConfig.swift` `anonKey` (it is publishable; safe to commit).
**Done when:** the key is in the repo and the app signs in against production.

### Phase 6 — App Store Connect: app record, metadata, subscription (plan 01-B3/B4)
**Goal:** the app record and paid product exist so the binary can be submitted.
**Steps:**
1. https://appstoreconnect.apple.com → My Apps → **+ New App**: platform iOS, bundle ID `com.bronsongarcia.VillageFeed`, name "VillageFeed", primary language English (U.S.), SKU `villagefeed-ios`.
2. Category: **Food & Drink**; secondary **Social Networking**.
3. Age rating questionnaire: answer honestly for meeting-strangers UGC — target **17+** (unrestricted web access No; user-generated content Yes).
4. App Privacy label: declare **Contact Info (email)**, **User Content (photos, messages, bio; dietary tags under user content)**, **Identifiers (user ID)**, **Purchases** — all "linked to you", none "used for tracking".
5. Monetization → Subscriptions: create group "VillageFeed Plus" → product `app.villagefeed.plus.monthly`, monthly, pick price tier, display name "VillageFeed Plus". Upload the required review screenshot later (any paywall screenshot works).
6. **Business → Agreements**: start/complete the **Paid Apps agreement** + banking/tax forms NOW — multi-day latency, blocks any paid product.
**Bring back:** confirmation of each; note anything blocked on banking info only Bronson can enter.
**Done when:** app record exists, subscription shows "Ready to submit" (or blocked only on banking), age rating 17+.

### Phase 7 — Supabase: production auth settings (plan 01-B6, AT LAUNCH — hold until told)
**Goal:** re-enable email confirmation for launch. **Do not run this phase until the launch dispatch says so** — it breaks the frictionless TestFlight signup flow.
**Steps:**
1. Authentication → Sign In / Up → enable "Confirm email".
2. Manually confirm the App Review demo account (Authentication → Users → the demo user → confirm).
**Bring back:** confirmation.
**Done when:** new signups require email confirmation; demo account still signs in.

### Phase 8 — Supabase: photo bucket privacy check (plan 02-§5)
**Goal:** verify public read-by-URL ≠ public listing.
**Steps:**
1. Storage → `photos` bucket → confirm it is "Public" (read by URL is intended).
2. In an incognito window, try `https://swjnmgfyvagkyugsndiv.supabase.co/storage/v1/object/list/photos` (POST is normally required — a plain GET should 4xx) and confirm the dashboard shows no anonymous LIST policy on `storage.objects` (SQL Editor: `select * from pg_policies where tablename = 'objects';` — only the three policies from migration 0001 should exist: insert own / update own / public select).
**Bring back:** the policy list output.
**Done when:** no listing path works anonymously.

## Not dispatchable — for Bronson personally

- **Book a food-law / platform-liability consultation.** Bring
  `docs/counsel-checklist.md` and `docs/terms-of-service.md`. The ToS draft is
  a launch gate (plan 09); the launch-state question feeds the beta-metro
  choice (plan 12). Ask the geography question (checklist Q1) early.
- **Set up a product mailbox** (`support@` on a domain, or at minimum a
  dedicated mailbox — not bronson.p.thomas@gmail.com). It becomes permanently
  public in the privacy policy and App Store record (plan 01-B2).

## Handed off

*(nothing yet)*

## Done

*(nothing yet)*

---

## Appendix A — migration 0007 (ToS acceptance)

```sql
-- Terms-of-Service acceptance record (plan 09-C). The onboarding gate's
-- acknowledgment toggle now has a document behind it: the client stamps which
-- ToS version was accepted and when, pushed with the profile. A material ToS
-- change bumps the app's version constant and the client re-prompts.

alter table public.profiles
  add column tos_version text,
  add column tos_accepted_at timestamptz;

-- 0005 revoked the blanket UPDATE grant; extend the column allowlist so
-- clients can record their own acceptance (still owner-row-only via RLS).
grant update (tos_version, tos_accepted_at)
  on table public.profiles to authenticated;
```

## Appendix B — migration 0008 (backend hardening + merge consent)

```sql
-- Backend hardening (plan 02, P1 items). Moves the load-bearing safety rules
-- server-side: anything enforced only in Swift is enforced for honest users only.

-- ============ 1. Server-side report rate limit ============
-- The client's 5-per-24h limit lives in local JSON; a REST client bypasses it
-- and each report instantly freezes its target — a weaponizable griefing
-- vector (SAFETY-NOTES §8). The trigger is the real wall; the client check
-- stays only for the friendly error message.

create function public.enforce_report_limit()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if (select count(*) from public.reports
      where reporter_id = new.reporter_id
        and created_at > now() - interval '24 hours') >= 5 then
    raise exception 'report limit reached (5 per 24h)';
  end if;
  -- Repeat report of a subject who already has an open case by the same
  -- reporter is a silent no-op: one person can't multi-freeze one target.
  if exists (select 1 from public.reports r
             join public.review_cases c on c.subject_id = r.subject_id and not c.resolved
             where r.reporter_id = new.reporter_id
               and r.subject_id = new.subject_id) then
    return null; -- skip the insert (and therefore the freeze trigger)
  end if;
  return new;
end;
$$;

create trigger before_report_insert
  before insert on public.reports
  for each row execute function public.enforce_report_limit();

-- ============ 2. Bidirectional blocks ============
-- Blocking previously hid them-from-you only (client filter). Server-side,
-- a block now removes visibility in BOTH directions. Policies can't read the
-- blocks table under the caller's RLS (they'd only see their own rows), so
-- the check runs security definer.

create function public.is_blocked_either_way(other uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = auth.uid() and blocked_id = other)
       or (blocker_id = other and blocked_id = auth.uid())
  );
$$;

drop policy "profiles are browsable when active" on public.profiles;
create policy "profiles are browsable when active"
  on public.profiles for select
  to authenticated
  using (
    id = auth.uid()
    or (status = 'active' and not public.is_blocked_either_way(id))
  );

-- Blocked users' chat rows disappear server-side too (client filter stays
-- for instant effect on the blocker's device).
drop policy "members read their group chat" on public.group_messages;
create policy "members read their group chat"
  on public.group_messages for select
  to authenticated
  using (
    public.is_group_member(group_id)
    and not public.is_blocked_either_way(sender_id)
  );

-- Likes surfaces respect blocks in both directions as well.
create or replace function public.who_liked_me_count()
returns int
language sql
security definer set search_path = public
stable
as $$
  select count(*)::int from public.swipes s
  join public.profiles p on p.id = s.swiper_id and p.status = 'active'
  where s.target_id = auth.uid() and s.target_kind = 'person' and s.liked
    and not public.is_blocked_either_way(s.swiper_id);
$$;

create or replace function public.who_liked_me()
returns setof uuid
language sql
security definer set search_path = public
stable
as $$
  select s.swiper_id from public.swipes s
  join public.profiles p on p.id = s.swiper_id and p.status = 'active'
  where s.target_id = auth.uid() and s.target_kind = 'person' and s.liked
    and not public.is_blocked_either_way(s.swiper_id)
    and exists (
      select 1 from public.profiles me
      where me.id = auth.uid() and me.is_plus
        and (me.plus_expires_at is null or me.plus_expires_at > now())
    );
$$;

-- ============ 3. Match truth on the server ============
-- Matches are now created by a trigger from mutual swipe rows — never
-- client-declared. This also closes the crossing-swipes race: whichever
-- swipe lands second creates the match row atomically. The client's
-- mutual_like RPC remains as the immediate "did we match?" answer.

create function public.handle_swipe_match()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.liked and new.target_kind = 'person' and exists (
    select 1 from public.swipes
    where swiper_id = new.target_id and target_id = new.swiper_id
      and target_kind = 'person' and liked
  ) then
    insert into public.matches (a, b)
    values (least(new.swiper_id, new.target_id), greatest(new.swiper_id, new.target_id))
    on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger on_swipe_upserted
  after insert or update on public.swipes
  for each row execute function public.handle_swipe_match();

-- ============ 6. Frozen/banned enforcement server-side ============
-- Frozen/banned profiles are already invisible in the pull (0001's select
-- policy requires status = 'active'). Close the write side: a frozen or
-- banned account can't post chat messages or file reports with a modified
-- client either.

drop policy "members write as themselves" on public.group_messages;
create policy "members write as themselves"
  on public.group_messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_group_member(group_id)
    and exists (select 1 from public.profiles me
                where me.id = auth.uid() and me.status not in ('frozen', 'banned'))
  );

drop policy "users file reports" on public.reports;
create policy "users file reports"
  on public.reports for insert
  to authenticated
  with check (
    reporter_id = auth.uid()
    and reporter_id <> subject_id
    and exists (select 1 from public.profiles me
                where me.id = auth.uid() and me.status <> 'banned')
  );

-- ============ Merge consent (plan 03-G3) ============
-- The v1 rule let any member absorb a *stranger's* group. Now the caller
-- must belong to BOTH groups; open_to_merge stays as the source's consent bit.
create or replace function public.merge_groups(source uuid, dest uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_group_member(dest) then
    raise exception 'caller is not a member of the destination group';
  end if;
  if not public.is_group_member(source) then
    raise exception 'caller is not a member of the source group';
  end if;
  if not exists (select 1 from public.groups where id = source and open_to_merge) then
    raise exception 'source group is not open to merging';
  end if;
  insert into public.group_members (group_id, member_id)
    select dest, member_id from public.group_members where group_id = source
    on conflict do nothing;
  delete from public.groups where id = source;
end;
$$;
```

## Appendix C — migration 0009 (chat upgrade)

```sql
-- Chat upgrade (plan 07): unread model, delete-own-message, message
-- reporting with content attached, and system messages.

-- ============ Unread model (plan 07-§2, shared with plan 04) ============
alter table public.group_members
  add column last_read_at timestamptz not null default now();

-- Members may update their own membership row (only last_read_at is
-- client-relevant; joined_at is set on insert and harmless to touch).
create policy "members update own membership"
  on public.group_members for update
  to authenticated
  using (member_id = auth.uid())
  with check (member_id = auth.uid());

-- ============ Delete my message (plan 07-§3) ============
-- Required companion to reporting — people need to remove their own mistakes.
create policy "senders delete own messages"
  on public.group_messages for delete
  to authenticated
  using (sender_id = auth.uid());

-- ============ System messages (plan 07-§4, carries plan 05 events) ============
-- Rendered as centered captions ("Sam pledged 12 portions…"), distinct from
-- human messages. Sender is the acting member, so the existing insert policy
-- applies unchanged.
alter table public.group_messages
  add column is_system boolean not null default false;

-- ============ Message reports carry the message text (plan 07-§3) ============
-- A reported message freezes the sender per the existing trigger; the review
-- case now shows the moderator the actual content.
alter table public.reports
  add column detail text not null default '';

create or replace function public.handle_new_report()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles set status = 'frozen', updated_at = now()
    where id = new.subject_id and status <> 'banned';
  insert into public.review_cases (subject_id, trigger_kind, trigger_detail)
    values (new.subject_id, 'report',
            case when new.detail = '' then new.reason
                 else new.reason || ' — message: "' || left(new.detail, 500) || '"' end);
  return new;
end;
$$;
```

## Appendix D — migration 0010 (ZIP area codes)

```sql
-- Structured neighborhoods (plan 06-B): self-reported ZIP at fixed coarse
-- granularity. The typed neighborhood label stays the display vanity; the ZIP
-- is the matching truth ("nearby" = same or prefix-adjacent ZIP). Never shown
-- to other users' clients raw — only used to sort/bucket the deck.

alter table public.profiles
  add column area_code text not null default ''
  check (char_length(area_code) <= 10);

grant update (area_code)
  on table public.profiles to authenticated;
```

## Appendix E — migration 0011 (push token registry)

```sql
-- Push notifications (plan 04): device-token registry. Delivery runs through
-- the send-push edge function, fired by database webhooks on: matches insert,
-- group_messages insert, group_members insert, and profiles.status → active
-- (webhook creation is a dashboard step — see DISPATCH-3).

create table public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  updated_at timestamptz not null default now()
);

create index device_tokens_user on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- Owner-only: a client can register/replace/remove its own tokens and see
-- nothing else. The edge function reads with the service role.
create policy "users manage own device tokens"
  on public.device_tokens for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
```

## Appendix F — migration 0012 (handoff planner + incident reports)

```sql
-- Handoff planner (plan 05): pledge → plan → done. Three tables, all
-- group-members-only (same RLS pattern as group_messages). Week boundary is
-- the local Monday; the server stores the date, the client computes "this week".
-- Also: incident reports ("this food made me sick", plan 02-§9) — distinct
-- from profile reports; pauses the dish, not the whole cook.

-- ============ Pledges ============
create table public.week_pledges (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  member_id uuid not null references public.profiles (id) on delete cascade,
  dish_id uuid references public.dishes (id) on delete set null,
  dish_name text not null default '',   -- denormalized: pledge survives dish edits
  dish_emoji text not null default '🍲',
  portions int not null default 6 check (portions between 1 and 50),
  week_start date not null,
  created_at timestamptz not null default now(),
  unique (group_id, member_id, week_start)  -- one pledge per member per week
);

alter table public.week_pledges enable row level security;

create policy "members read group pledges"
  on public.week_pledges for select
  to authenticated
  using (public.is_group_member(group_id));

create policy "members manage own pledges"
  on public.week_pledges for all
  to authenticated
  using (member_id = auth.uid())
  with check (member_id = auth.uid() and public.is_group_member(group_id));

-- ============ Handoffs ============
create table public.handoffs (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  spot text not null check (char_length(spot) between 1 and 120),
  at timestamptz not null,
  proposed_by uuid not null references public.profiles (id) on delete cascade,
  week_start date not null,
  created_at timestamptz not null default now(),
  unique (group_id, week_start)  -- one handoff per group per week (v1)
);

alter table public.handoffs enable row level security;

create policy "members read group handoffs"
  on public.handoffs for select
  to authenticated
  using (public.is_group_member(group_id));

create policy "members propose handoffs"
  on public.handoffs for insert
  to authenticated
  with check (proposed_by = auth.uid() and public.is_group_member(group_id));

create policy "proposers update their handoffs"
  on public.handoffs for update
  to authenticated
  using (proposed_by = auth.uid());

create policy "proposers delete their handoffs"
  on public.handoffs for delete
  to authenticated
  using (proposed_by = auth.uid());

-- ============ RSVPs + check-ins ============
-- status: going / cant (pre-handoff). checkin: good / no_show / problem
-- (post-handoff "How'd it go?" — the safety touchpoint from SAFETY-NOTES).
create table public.handoff_rsvps (
  handoff_id uuid not null references public.handoffs (id) on delete cascade,
  member_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'going' check (status in ('going', 'cant')),
  checkin text check (checkin in ('good', 'no_show', 'problem')),
  updated_at timestamptz not null default now(),
  primary key (handoff_id, member_id)
);

alter table public.handoff_rsvps enable row level security;

create policy "members read rsvps for their groups"
  on public.handoff_rsvps for select
  to authenticated
  using (exists (select 1 from public.handoffs h
                 where h.id = handoff_id and public.is_group_member(h.group_id)));

create policy "members manage own rsvps"
  on public.handoff_rsvps for all
  to authenticated
  using (member_id = auth.uid())
  with check (member_id = auth.uid()
              and exists (select 1 from public.handoffs h
                          where h.id = handoff_id and public.is_group_member(h.group_id)));

-- ============ Incident reports (plan 02-§9) ============
alter table public.dishes add column paused boolean not null default false;

create table public.incident_reports (
  id uuid primary key default gen_random_uuid(),
  dish_id uuid not null references public.dishes (id) on delete cascade,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  detail text not null default '',
  created_at timestamptz not null default now()
);

alter table public.incident_reports enable row level security;

create policy "users file incident reports"
  on public.incident_reports for insert
  to authenticated
  with check (reporter_id = auth.uid());

create policy "reporters see own incident reports"
  on public.incident_reports for select
  to authenticated
  using (reporter_id = auth.uid());

-- An incident pauses the DISH (not the cook's whole profile) and opens a
-- prioritized review case for the dish's owner.
create function public.handle_incident_report()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  dish_owner uuid;
  dish_label text;
begin
  select owner_id, name into dish_owner, dish_label from public.dishes where id = new.dish_id;
  update public.dishes set paused = true where id = new.dish_id;
  insert into public.review_cases (subject_id, trigger_kind, trigger_detail)
    values (dish_owner, 'report',
            'INCIDENT (' || dish_label || '): ' || coalesce(nullif(new.detail, ''), 'no detail'));
  return new;
end;
$$;

create trigger on_incident_report
  after insert on public.incident_reports
  for each row execute function public.handle_incident_report();

-- Paused dishes disappear from everyone else's pull (owner still sees them).
drop policy "dishes visible with their owner" on public.dishes;
create policy "dishes visible with their owner"
  on public.dishes for select
  to authenticated
  using (
    owner_id = auth.uid()
    or (not paused
        and exists (select 1 from public.profiles p
                    where p.id = owner_id and p.status = 'active'))
  );
```

## Appendix G — migration 0013 (trust signals)

```sql
-- Trust & reputation v1 (plan 10): signals from actions, not opinions.
-- Public surface is positive-only; negative signals route to moderation.

-- ============ Who didn't show (attribution for the private signal) ============
-- The check-in "someone didn't show" now names the member so the threshold
-- can be enforced per person — still never shown publicly.
alter table public.handoff_rsvps
  add column no_show_member uuid references public.profiles (id) on delete set null;

-- ============ Trade counts (the public signal) ============
-- Completed trades = handoffs where the member pledged that week and their own
-- check-in was 'good'. One count per member, readable by anyone signed in
-- (the underlying tables stay members-only; the view is the deliberate window).
create view public.trade_counts
with (security_invoker = false) as
  select r.member_id, count(*)::int as trades
  from public.handoff_rsvps r
  join public.handoffs h on h.id = r.handoff_id
  join public.week_pledges p
    on p.group_id = h.group_id and p.member_id = r.member_id and p.week_start = h.week_start
  where r.checkin = 'good'
  group by r.member_id;

grant select on public.trade_counts to authenticated;

-- ============ Reliability, privately enforced ============
-- 3+ named no-shows in 30 days opens a review case; nothing public changes.
create function public.handle_no_show_threshold()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.no_show_member is not null then
    if (select count(*) from public.handoff_rsvps
        where no_show_member = new.no_show_member
          and updated_at > now() - interval '30 days') >= 3
       and not exists (select 1 from public.review_cases
                       where subject_id = new.no_show_member and not resolved) then
      insert into public.review_cases (subject_id, trigger_kind, trigger_detail)
        values (new.no_show_member, 'report', 'RELIABILITY: 3+ no-show check-ins in 30 days');
    end if;
  end if;
  return new;
end;
$$;

create trigger on_rsvp_no_show
  after insert or update on public.handoff_rsvps
  for each row execute function public.handle_no_show_threshold();
```

## Appendix H — migration 0014 (referral attribution)

```sql
-- Invite attribution (plan 12-B): the invite message carries a short code
-- (first 8 hex chars of the inviter's user id); the setup wizard lets a new
-- cook paste it. Which invite loops actually work becomes a one-query answer:
--   select referred_by, count(*) from profiles group by 1;

alter table public.profiles
  add column referred_by text not null default ''
  check (char_length(referred_by) <= 16);

grant update (referred_by)
  on table public.profiles to authenticated;
```

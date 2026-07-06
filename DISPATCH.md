# DISPATCH.md — browser tasks for Claude dispatch

Instructions to complete in Google Chrome. Work top to bottom; each section says
what to record at the end. Record all outputs in a single summary at the end so
Bronson can paste them into the project.

## 1. Create the Supabase project

1. Go to https://supabase.com/dashboard and sign in (Bronson's account — reuse the
   org that hosts the existing "SpaceEngine/GetSpaced" project).
2. Click **New project**. Name: `villagefeed`. Generate (and record) a strong
   database password. Region: closest US region. Free tier is fine.
3. Wait for provisioning to finish.
4. Go to **Project Settings → Data API** and record:
   - **Project URL** (looks like `https://<ref>.supabase.co`)
   - **anon/public key**

## 2. Run the schema migration

1. In the project, open **SQL Editor → New query**.
2. Paste the entire SQL from **Appendix A** at the bottom of this document and
   click **Run**. Then do the same with **Appendix B** in a second query. (Identical to `supabase/migrations/0001_init.sql` in the repo.)
3. Confirm it reports success. If any statement fails, record the exact error
   text and stop this section (don't retry with modifications).

## 3. Google Cloud OAuth client (for "Continue with Google")

1. Go to https://console.cloud.google.com/ and sign in with the same Google
   account.
2. Create a new project named `VillageFeed` (or reuse an existing personal one).
3. Navigate to **APIs & Services → OAuth consent screen**:
   - User type: **External**. App name: `VillageFeed`. Add Bronson's email as
     support + developer contact. Scopes: just the default (email, profile,
     openid). Add Bronson's email as a test user. Save.
4. Navigate to **APIs & Services → Credentials → Create credentials →
   OAuth client ID**:
   - Application type: **Web application** (yes, web — Supabase brokers the
     OAuth flow, the iOS app opens it in a browser sheet).
   - Name: `villagefeed-supabase`.
   - Authorized redirect URI: `https://<ref>.supabase.co/auth/v1/callback`
     (substitute the project ref from step 1.4).
   - Create, and record the **Client ID** and **Client secret**.

## 4. Enable the Google provider in Supabase

1. Back in the Supabase dashboard: **Authentication → Sign In / Providers → Google**.
2. Toggle it on, paste the Client ID and Client secret from step 3.
3. In **Authentication → URL Configuration**, add `villagefeed://auth-callback`
   to the **Redirect URLs** list. Save.

## 5. Anthropic API key for server-side moderation

1. Go to https://console.anthropic.com/ and sign in.
2. Create a new API key named `villagefeed-moderation` in the default workspace.
   Record the key (starts `sk-ant-`).
3. In the Supabase dashboard, go to **Edge Functions → Secrets** (or Project
   Settings → Edge Functions) and add a secret: name `ANTHROPIC_API_KEY`,
   value = the key just created.

## 6. Final summary to report back

Produce one block containing:
- Supabase Project URL and anon key  → to paste into `VillageFeed/SupabaseConfig.swift`
- Database password (label clearly)
- Google OAuth Client ID (secret stays only in Supabase — do not echo it)
- Confirmation that: migration ran clean, Google provider is enabled,
  redirect URL added, ANTHROPIC_API_KEY secret set.

## 7. Record the summary durably

Open https://github.com/OriginalBronson/VillageFeed/issues/new (sign into
GitHub as OriginalBronson if needed), title the issue
**"Dispatch results: Supabase + Google setup"**, paste the section-6 summary
**minus the database password and any secret values** (those go only in the
direct reply to Bronson — never into the issue), and submit.

## Not for dispatch — Bronson's local terminal (morning checklist)

```sh
cd ~/Desktop/VillageFeed
# 1. Paste the Supabase URL + anon key from dispatch's summary into
#    VillageFeed/SupabaseConfig.swift, rebuild, then commit + push.
# 2. Deploy the moderation function (needs Supabase CLI: brew install supabase/tap/supabase):
supabase link --project-ref <ref>
supabase functions deploy moderate-profile
```

## Not yet (future dispatch runs)

- App Store Connect app record + TestFlight (blocked on Apple Developer
  Program membership).

## Appendix A — schema migration SQL

Paste everything between the fences into the Supabase SQL editor:

```sql
-- VillageFeed initial schema. Run in the Supabase SQL editor (see DISPATCH.md).

-- ============ profiles ============
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null default '',
  neighborhood text not null default '',
  bio text not null default '',
  photo_path text,                          -- storage path in the photos bucket
  dietary_tags text[] not null default '{}',
  status text not null default 'pendingReview'
    check (status in ('active', 'pendingReview', 'frozen', 'banned')),
  birth_year int,                           -- age gate: must imply 17+
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Everyone signed-in can browse ACTIVE profiles; you can always see your own.
create policy "profiles are browsable when active"
  on public.profiles for select
  to authenticated
  using (status = 'active' or id = auth.uid());

create policy "users insert own profile"
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

-- Users may edit their own profile but NOT change moderation status
-- (status transitions happen via the service role / edge functions only).
create policy "users update own profile"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and status = (select p.status from public.profiles p where p.id = auth.uid()));

-- Create a pending profile row on signup.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============ dishes ============
create table public.dishes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  emoji text not null default '🍲',
  blurb text not null default '',
  portions int not null default 6 check (portions between 1 and 50),
  allergen_note text not null default '',   -- e.g. "contains nuts; kitchen handles shellfish"
  photo_path text,
  created_at timestamptz not null default now()
);

alter table public.dishes enable row level security;

create policy "dishes visible with their owner"
  on public.dishes for select
  to authenticated
  using (
    owner_id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = owner_id and p.status = 'active')
  );

create policy "owners manage own dishes"
  on public.dishes for all
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- ============ groups ============
create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  emoji text not null default '🍽️',
  seeking_members boolean not null default true,
  open_to_merge boolean not null default true,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  member_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, member_id)
);

alter table public.groups enable row level security;
alter table public.group_members enable row level security;

create function public.is_group_member(gid uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.group_members
    where group_id = gid and member_id = auth.uid()
  );
$$;

create policy "groups visible when seeking or mine"
  on public.groups for select
  to authenticated
  using (seeking_members or public.is_group_member(id));

create policy "signed-in users create groups"
  on public.groups for insert
  to authenticated
  with check (created_by = auth.uid());

create policy "members update their groups"
  on public.groups for update
  to authenticated
  using (public.is_group_member(id));

create policy "membership visible to fellow members and seekers"
  on public.group_members for select
  to authenticated
  using (
    member_id = auth.uid()
    or public.is_group_member(group_id)
    or exists (select 1 from public.groups g where g.id = group_id and g.seeking_members)
  );

create policy "users join groups themselves"
  on public.group_members for insert
  to authenticated
  with check (member_id = auth.uid());

create policy "users leave groups themselves"
  on public.group_members for delete
  to authenticated
  using (member_id = auth.uid());

-- ============ swipes & matches ============
create table public.swipes (
  swiper_id uuid not null references public.profiles (id) on delete cascade,
  target_id uuid not null,                  -- profile OR group id
  target_kind text not null check (target_kind in ('person', 'group')),
  liked boolean not null,
  created_at timestamptz not null default now(),
  primary key (swiper_id, target_id)
);

alter table public.swipes enable row level security;

create policy "users manage own swipes"
  on public.swipes for all
  to authenticated
  using (swiper_id = auth.uid())
  with check (swiper_id = auth.uid());

-- A user may check ONLY whether a specific person liked them back — the
-- "who liked you" list (paid tier) is served by an entitlement-checking
-- edge function with the service role, never by direct table reads.
create function public.mutual_like(other uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.swipes
    where swiper_id = other and target_id = auth.uid()
      and target_kind = 'person' and liked
  );
$$;

create table public.matches (
  a uuid not null references public.profiles (id) on delete cascade,
  b uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (a, b),
  check (a < b)
);

alter table public.matches enable row level security;

create policy "participants see their matches"
  on public.matches for select
  to authenticated
  using (a = auth.uid() or b = auth.uid());

create policy "participants create their matches"
  on public.matches for insert
  to authenticated
  with check ((a = auth.uid() or b = auth.uid()) and public.mutual_like(case when a = auth.uid() then b else a end));

-- ============ blocks (instant, independent of moderation) ============
create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

alter table public.blocks enable row level security;

create policy "users manage own blocks"
  on public.blocks for all
  to authenticated
  using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid());

-- ============ reports & review queue ============
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  subject_id uuid not null references public.profiles (id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now()
);

alter table public.reports enable row level security;

create policy "users file reports"
  on public.reports for insert
  to authenticated
  with check (reporter_id = auth.uid() and reporter_id <> subject_id);

create policy "reporters see own reports"
  on public.reports for select
  to authenticated
  using (reporter_id = auth.uid());

-- Instant freeze + review case on report (service-side effect via trigger).
create table public.review_cases (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.profiles (id) on delete cascade,
  trigger_kind text not null check (trigger_kind in ('report', 'new_profile')),
  trigger_detail text not null default '',
  ai_verdict text check (ai_verdict in ('approve', 'reject', 'escalate')),
  ai_rationale text,
  resolved boolean not null default false,
  resolved_by text,                          -- 'ai' | moderator identifier
  created_at timestamptz not null default now()
);

alter table public.review_cases enable row level security;
-- No client policies: the review queue is service-role only (moderation
-- dashboard / edge functions). RLS enabled with no policy = no client access.

create function public.handle_new_report()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles set status = 'frozen', updated_at = now()
    where id = new.subject_id and status <> 'banned';
  insert into public.review_cases (subject_id, trigger_kind, trigger_detail)
    values (new.subject_id, 'report', new.reason);
  return new;
end;
$$;

create trigger on_report_created
  after insert on public.reports
  for each row execute function public.handle_new_report();

-- ============ storage ============
insert into storage.buckets (id, name, public)
values ('photos', 'photos', true)
on conflict (id) do nothing;

create policy "users upload own photos"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "users update own photos"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "photos are publicly readable"
  on storage.objects for select
  using (bucket_id = 'photos');
```

## Appendix B — likes + merge migration SQL

```sql
-- Who-liked-you (paid tier) + group merge. Run after 0001_init.sql.

-- Plus entitlement flag. Set by App Store server-notification webhook later;
-- until that exists a moderator can flip it manually for testers.
alter table public.profiles add column is_plus boolean not null default false;

-- Free tier: how many active cooks liked me (count only, no identities).
create function public.who_liked_me_count()
returns int
language sql
security definer set search_path = public
stable
as $$
  select count(*)::int from public.swipes s
  join public.profiles p on p.id = s.swiper_id and p.status = 'active'
  where s.target_id = auth.uid() and s.target_kind = 'person' and s.liked;
$$;

-- Paid tier: the identities. Empty unless the caller's profile has is_plus.
create function public.who_liked_me()
returns setof uuid
language sql
security definer set search_path = public
stable
as $$
  select s.swiper_id from public.swipes s
  join public.profiles p on p.id = s.swiper_id and p.status = 'active'
  where s.target_id = auth.uid() and s.target_kind = 'person' and s.liked
    and exists (select 1 from public.profiles me where me.id = auth.uid() and me.is_plus);
$$;

-- Merge `source` into `dest`: caller must be a member of dest, and source must
-- be open to merging. Members move, the source group is deleted.
create function public.merge_groups(source uuid, dest uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_group_member(dest) then
    raise exception 'caller is not a member of the destination group';
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

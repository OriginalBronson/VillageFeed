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

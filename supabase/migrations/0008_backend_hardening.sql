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

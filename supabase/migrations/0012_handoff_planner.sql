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

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

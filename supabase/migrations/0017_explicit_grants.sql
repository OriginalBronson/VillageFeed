-- Explicit Data API grants (Supabase platform change, May 30 2026).
-- New Supabase projects no longer auto-grant table/function privileges in
-- the public schema to anon/authenticated/service_role, and existing
-- projects lose the automatic grants on Oct 30 2026:
--   https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically
-- The CI local stack (CLI `latest`) already follows the new default, which
-- is how the pgTAP job caught this. These grants restore exactly the access
-- surface the RLS policies were written against; RLS stays the row gate.
--
-- profiles UPDATE is deliberately NOT re-granted at table level: 0005/0007/
-- 0010/0014 grant column-level UPDATE only, keeping is_plus and status
-- service-role-writable. A blanket UPDATE grant here would undo that.
--
-- Every table added after this migration must ship its own grants.

-- ============ authenticated: one grant set per policy surface ============
grant select, insert                 on public.profiles         to authenticated;
grant select, insert, update, delete on public.dishes           to authenticated;
grant select, insert, update         on public.groups           to authenticated;
grant select, insert, update, delete on public.group_members    to authenticated;
grant select, insert,         delete on public.group_messages   to authenticated;
grant select, insert, update, delete on public.swipes           to authenticated;
grant select, insert,         delete on public.matches          to authenticated;
grant select, insert, update, delete on public.blocks           to authenticated;
grant select, insert                 on public.reports          to authenticated;
grant select, insert, update, delete on public.device_tokens    to authenticated;
grant select, insert, update, delete on public.week_pledges     to authenticated;
grant select, insert, update, delete on public.handoffs         to authenticated;
grant select, insert, update, delete on public.handoff_rsvps    to authenticated;
grant select, insert                 on public.incident_reports to authenticated;
-- trade_counts (view): granted in 0013. review_cases: moderation-only,
-- no client access — service_role covers it below.

-- RPCs the app calls directly.
grant execute on function public.mutual_like(uuid)        to authenticated;
grant execute on function public.merge_groups(uuid, uuid) to authenticated;
grant execute on function public.who_liked_me()           to authenticated;
grant execute on function public.who_liked_me_count()     to authenticated;
-- Helpers referenced inside RLS policies execute as the querying role, so
-- authenticated needs EXECUTE on them too (they stay security definer for
-- the cross-row reads).
grant execute on function public.is_group_member(uuid)        to authenticated;
grant execute on function public.is_blocked_either_way(uuid)  to authenticated;

-- ============ service_role: edge functions need full DML ============
-- (delete-account, moderate-profile, send-push, sync-entitlement)
grant select, insert, update, delete on all tables in schema public to service_role;

-- anon intentionally gets nothing: every policy is `to authenticated`, and
-- the pre-auth client only touches auth endpoints and public storage.

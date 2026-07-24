-- RLS policy tests (plan 11-A2): the security claims, actually executed.
-- Run locally:  supabase start && supabase test db
-- CI: the pgtap job in .github/workflows/ci.yml runs the same command.
--
-- Seeds three users — A, B (blocked by A), C (frozen) — and asserts the
-- properties plans 01/02 rely on. Uses pgTAP + the standard trick of
-- impersonating users by setting request.jwt.claims.

begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

-- ---------- Seed users ----------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local'),
  ('00000000-0000-0000-0000-00000000000c', 'c@test.local');
-- handle_new_user trigger created pending profiles; activate + arrange states.
update public.profiles set status = 'active', name = 'A'
  where id = '00000000-0000-0000-0000-00000000000a';
update public.profiles set status = 'active', name = 'B'
  where id = '00000000-0000-0000-0000-00000000000b';
update public.profiles set status = 'frozen', name = 'C'
  where id = '00000000-0000-0000-0000-00000000000c';

-- A blocks B.
insert into public.blocks (blocker_id, blocked_id) values
  ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b');

-- A group owned by A, with A as its only member.
insert into public.groups (id, name, created_by) values
  ('00000000-0000-0000-0000-000000000e01', 'A''s table', '00000000-0000-0000-0000-00000000000a');
insert into public.group_members (group_id, member_id) values
  ('00000000-0000-0000-0000-000000000e01', '00000000-0000-0000-0000-00000000000a');
insert into public.group_messages (group_id, sender_id, text) values
  ('00000000-0000-0000-0000-000000000e01', '00000000-0000-0000-0000-00000000000a', 'members only');

-- ---------- Helper: impersonate ----------
create or replace function test_as(uid text) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end;
$$;

-- ---------- Bidirectional blocks (migration 0008) ----------
select test_as('00000000-0000-0000-0000-00000000000b');
select is(
  (select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
  0, 'B (blocked by A) cannot see A''s profile');

select test_as('00000000-0000-0000-0000-00000000000a');
select is(
  (select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000000b'),
  0, 'A cannot see B either — blocks are bidirectional');

-- ---------- Frozen exclusion (0001 select policy) ----------
select is(
  (select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000000c'),
  0, 'frozen C appears in no one''s pull');

select test_as('00000000-0000-0000-0000-00000000000c');
select is(
  (select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000000c'),
  1, 'C still sees their own frozen profile');

-- ---------- Frozen write lockout (0008) ----------
select throws_ok(
  $$ insert into public.group_messages (group_id, sender_id, text)
     values ('00000000-0000-0000-0000-000000000e01', '00000000-0000-0000-0000-00000000000c', 'hi') $$,
  '42501', null, 'frozen C cannot post chat messages');

-- ---------- Non-members can't read or write group chat ----------
select test_as('00000000-0000-0000-0000-00000000000b');
select is(
  (select count(*)::int from public.group_messages
   where group_id = '00000000-0000-0000-0000-000000000e01'),
  0, 'non-member B cannot read the group''s messages');
select throws_ok(
  $$ insert into public.group_messages (group_id, sender_id, text)
     values ('00000000-0000-0000-0000-000000000e01', '00000000-0000-0000-0000-00000000000b', 'let me in') $$,
  '42501', null, 'non-member B cannot write into the group');

-- ---------- Report rate limit (0008 trigger) ----------
-- Seeding needs superuser: drop the impersonation left over from the
-- previous section before touching auth.users / profiles.status.
select set_config('role', 'none', true);
-- 5 reports against C land (each auto-freezes + opens a case; duplicates are
-- no-ops, so spread across seeded synthetic subjects).
insert into auth.users (id, email)
  select ('00000000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid,
         'victim' || i || '@test.local'
  from generate_series(20, 24) i;
update public.profiles set status = 'active' where name = '';
select test_as('00000000-0000-0000-0000-00000000000b');
select lives_ok(
  $$ insert into public.reports (reporter_id, subject_id, reason)
     select '00000000-0000-0000-0000-00000000000b',
            ('00000000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid,
            'Scam or spam'
     from generate_series(20, 24) i $$,
  'first five reports in 24h are accepted');
select throws_like(
  $$ insert into public.reports (reporter_id, subject_id, reason)
     values ('00000000-0000-0000-0000-00000000000b',
             '00000000-0000-0000-0000-00000000000c', 'Scam or spam') $$,
  '%report limit%', 'report #6 in 24h is rejected server-side');

-- ---------- Paid-tier column lock (0005/0006) ----------
select test_as('00000000-0000-0000-0000-00000000000a');
select throws_ok(
  $$ update public.profiles set is_plus = true
     where id = '00000000-0000-0000-0000-00000000000a' $$,
  '42501', null, 'is_plus cannot be self-granted');
select throws_ok(
  $$ update public.profiles set status = 'active'
     where id = '00000000-0000-0000-0000-00000000000a' $$,
  '42501', null, 'status cannot be self-written');

-- ---------- ToS acceptance IS client-writable (0007) ----------
select lives_ok(
  $$ update public.profiles set tos_version = '1.0-draft', tos_accepted_at = now()
     where id = '00000000-0000-0000-0000-00000000000a' $$,
  'users can record their own ToS acceptance');

select * from finish();
rollback;

# DISPATCH-2.md — round 2 browser tasks for Claude dispatch

Round 1 (DISPATCH.md) is complete — project `swjnmgfyvagkyugsndiv` exists with
migrations 0001/0002 applied, Google provider enabled, `ANTHROPIC_API_KEY` set
(see GitHub issue #1). This round layers on what was built since.

Work top to bottom in Google Chrome; record outcomes for the final summary.

## 1. Apply the two new migrations

In https://supabase.com/dashboard → project `villagefeed` → **SQL Editor**:

1. New query → paste **Appendix A** (group chat) → Run. If it errors with
   "relation group_messages already exists", Bronson already applied it via CLI
   — note that and continue.
2. New query → paste **Appendix B** (realtime publication) → Run. If it errors
   with "already member of publication", same deal — note and continue.

## 2. Auth settings for TestFlight-era testing

1. **Authentication → Sign In / Providers → Email**: turn **off**
   "Confirm email" for now (instant email/password signup while testing;
   re-enabling before public launch is on the roadmap and should be noted in
   the summary as a deliberate temporary state).
2. **Authentication → URL Configuration**: confirm `villagefeed://auth-callback`
   is still listed in Redirect URLs (added in round 1).

## 3. Verify edge functions

Open **Edge Functions** in the dashboard. Expected: `moderate-profile` and
`delete-account` both listed (Bronson deploys them via CLI — see terminal
checklist below). If either is missing, just record that; do not try to
create functions from the dashboard.

## 4. Optional: mark Bronson's account as Plus (only if it exists)

In **Authentication → Users**, check whether a user with email
`bronson.p.thomas@gmail.com` exists (it will only exist after he signs in from
the app at least once). If yes, run this in the SQL editor:

```sql
update public.profiles set is_plus = true
where id = (select id from auth.users where email = 'bronson.p.thomas@gmail.com');
```

If the user doesn't exist yet, skip and note it — this SQL is rerunnable later.

## 5. Summary

Reply with: which migrations applied vs were already present, email
confirmation state, which edge functions are deployed, whether is_plus was
set. Then append the same summary as a comment on GitHub issue #1
(https://github.com/OriginalBronson/VillageFeed/issues/1) — no secrets in the
issue.

## Not for dispatch — Bronson's terminal (do this BEFORE or alongside round 2)

```sh
cd ~/Desktop/VillageFeed && git pull
# 1. Paste the anon key (from your round-1 notes) into VillageFeed/SupabaseConfig.swift
#    (URL is already filled in). Build & run — sign up, then everything is live.
# 2. supabase link --project-ref swjnmgfyvagkyugsndiv
#    supabase db push --include-all          # applies 0003 + 0004 if dispatch didn't
#    supabase functions deploy moderate-profile
#    supabase functions deploy delete-account
```

## Appendix A — 0003_group_messages.sql

```sql
create table public.group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  text text not null check (char_length(text) between 1 and 2000),
  sent_at timestamptz not null default now()
);

create index group_messages_group_sent on public.group_messages (group_id, sent_at);

alter table public.group_messages enable row level security;

create policy "members read their group chat"
  on public.group_messages for select
  to authenticated
  using (public.is_group_member(group_id));

create policy "members write as themselves"
  on public.group_messages for insert
  to authenticated
  with check (sender_id = auth.uid() and public.is_group_member(group_id));
```

## Appendix B — 0004_realtime.sql

```sql
alter publication supabase_realtime add table public.group_messages;
```

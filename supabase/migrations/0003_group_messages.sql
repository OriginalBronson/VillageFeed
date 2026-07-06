-- Group chat ("table talk"). Run after 0002_likes_and_merge.sql.
-- Delivery is pull-based for now; enabling supabase_realtime on this table is
-- the follow-up when live updates are wanted.

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

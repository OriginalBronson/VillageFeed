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

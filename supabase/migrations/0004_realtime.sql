-- Live chat delivery: expose group_messages inserts over Realtime.
-- RLS still applies — subscribers only receive rows for groups they belong to.

alter publication supabase_realtime add table public.group_messages;

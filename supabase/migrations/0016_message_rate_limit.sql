-- Message rate limit (ux-review B27). Length was already capped at 2000 chars
-- in 0003; this adds the flood wall. Same pattern as 0008's report limit: the
-- trigger is the real enforcement, any client-side courtesy is just UX.
--
-- 20 messages/minute is deliberately generous — a fast human coordinating a
-- handoff won't hit it; a script or a stuck retry loop will.

create function public.enforce_message_rate_limit()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if (select count(*) from public.group_messages
      where sender_id = new.sender_id
        and sent_at > now() - interval '1 minute') >= 20 then
    raise exception 'message rate limit reached (20 per minute)';
  end if;
  return new;
end;
$$;

create trigger before_message_insert
  before insert on public.group_messages
  for each row execute function public.enforce_message_rate_limit();

-- Entitlement expiry. The sync-entitlement edge function records the
-- subscription's expiry alongside is_plus, and who_liked_me() now checks it —
-- so a lapsed subscription stops unlocking identities even if the client
-- never checks in again. Null means no expiry (manual moderator grant).
-- The column privileges from 0005 already exclude this column from the
-- authenticated UPDATE grant, so only the service role can write it.

alter table public.profiles add column plus_expires_at timestamptz;

create or replace function public.who_liked_me()
returns setof uuid
language sql
security definer set search_path = public
stable
as $$
  select s.swiper_id from public.swipes s
  join public.profiles p on p.id = s.swiper_id and p.status = 'active'
  where s.target_id = auth.uid() and s.target_kind = 'person' and s.liked
    and exists (
      select 1 from public.profiles me
      where me.id = auth.uid() and me.is_plus
        and (me.plus_expires_at is null or me.plus_expires_at > now())
    );
$$;

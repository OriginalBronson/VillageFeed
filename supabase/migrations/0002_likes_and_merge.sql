-- Who-liked-you (paid tier) + group merge. Run after 0001_init.sql.

-- Plus entitlement flag. Set by App Store server-notification webhook later;
-- until that exists a moderator can flip it manually for testers.
alter table public.profiles add column is_plus boolean not null default false;

-- Free tier: how many active cooks liked me (count only, no identities).
create function public.who_liked_me_count()
returns int
language sql
security definer set search_path = public
stable
as $$
  select count(*)::int from public.swipes s
  join public.profiles p on p.id = s.swiper_id and p.status = 'active'
  where s.target_id = auth.uid() and s.target_kind = 'person' and s.liked;
$$;

-- Paid tier: the identities. Empty unless the caller's profile has is_plus.
create function public.who_liked_me()
returns setof uuid
language sql
security definer set search_path = public
stable
as $$
  select s.swiper_id from public.swipes s
  join public.profiles p on p.id = s.swiper_id and p.status = 'active'
  where s.target_id = auth.uid() and s.target_kind = 'person' and s.liked
    and exists (select 1 from public.profiles me where me.id = auth.uid() and me.is_plus);
$$;

-- Merge `source` into `dest`: caller must be a member of dest, and source must
-- be open to merging. Members move, the source group is deleted.
create function public.merge_groups(source uuid, dest uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_group_member(dest) then
    raise exception 'caller is not a member of the destination group';
  end if;
  if not exists (select 1 from public.groups where id = source and open_to_merge) then
    raise exception 'source group is not open to merging';
  end if;
  insert into public.group_members (group_id, member_id)
    select dest, member_id from public.group_members where group_id = source
    on conflict do nothing;
  delete from public.groups where id = source;
end;
$$;

-- Invite attribution (plan 12-B): the invite message carries a short code
-- (first 8 hex chars of the inviter's user id); the setup wizard lets a new
-- cook paste it. Which invite loops actually work becomes a one-query answer:
--   select referred_by, count(*) from profiles group by 1;

alter table public.profiles
  add column referred_by text not null default ''
  check (char_length(referred_by) <= 16);

grant update (referred_by)
  on table public.profiles to authenticated;

-- Structured neighborhoods (plan 06-B): self-reported ZIP at fixed coarse
-- granularity. The typed neighborhood label stays the display vanity; the ZIP
-- is the matching truth ("nearby" = same or prefix-adjacent ZIP). Never shown
-- to other users' clients raw — only used to sort/bucket the deck.

alter table public.profiles
  add column area_code text not null default ''
  check (char_length(area_code) <= 10);

grant update (area_code)
  on table public.profiles to authenticated;

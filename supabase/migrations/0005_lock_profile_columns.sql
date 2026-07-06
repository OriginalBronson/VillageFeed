-- Security fix: clients could UPDATE their own profiles row including is_plus
-- (the RLS policy only pinned status), silently unlocking the paid tier.
-- Postgres column-level privileges close this: drop the blanket UPDATE grant
-- and re-grant only the user-editable columns. is_plus and status are then
-- writable solely by the service role (entitlement webhook / moderation).

revoke update on table public.profiles from authenticated, anon;

grant update (name, neighborhood, bio, photo_path, dietary_tags, birth_year, updated_at)
  on table public.profiles to authenticated;

-- Terms-of-Service acceptance record (plan 09-C). The onboarding gate's
-- acknowledgment toggle now has a document behind it: the client stamps which
-- ToS version was accepted and when, pushed with the profile. A material ToS
-- change bumps the app's version constant and the client re-prompts.

alter table public.profiles
  add column tos_version text,
  add column tos_accepted_at timestamptz;

-- 0005 revoked the blanket UPDATE grant; extend the column allowlist so
-- clients can record their own acceptance (still owner-row-only via RLS).
grant update (tos_version, tos_accepted_at)
  on table public.profiles to authenticated;

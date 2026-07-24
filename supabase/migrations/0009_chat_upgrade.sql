-- Chat upgrade (plan 07): unread model, delete-own-message, message
-- reporting with content attached, and system messages.

-- ============ Unread model (plan 07-§2, shared with plan 04) ============
alter table public.group_members
  add column last_read_at timestamptz not null default now();

-- Members may update their own membership row (only last_read_at is
-- client-relevant; joined_at is set on insert and harmless to touch).
create policy "members update own membership"
  on public.group_members for update
  to authenticated
  using (member_id = auth.uid())
  with check (member_id = auth.uid());

-- ============ Delete my message (plan 07-§3) ============
-- Required companion to reporting — people need to remove their own mistakes.
create policy "senders delete own messages"
  on public.group_messages for delete
  to authenticated
  using (sender_id = auth.uid());

-- ============ System messages (plan 07-§4, carries plan 05 events) ============
-- Rendered as centered captions ("Sam pledged 12 portions…"), distinct from
-- human messages. Sender is the acting member, so the existing insert policy
-- applies unchanged.
alter table public.group_messages
  add column is_system boolean not null default false;

-- ============ Message reports carry the message text (plan 07-§3) ============
-- A reported message freezes the sender per the existing trigger; the review
-- case now shows the moderator the actual content.
alter table public.reports
  add column detail text not null default '';

create or replace function public.handle_new_report()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles set status = 'frozen', updated_at = now()
    where id = new.subject_id and status <> 'banned';
  insert into public.review_cases (subject_id, trigger_kind, trigger_detail)
    values (new.subject_id, 'report',
            case when new.detail = '' then new.reason
                 else new.reason || ' — message: "' || left(new.detail, 500) || '"' end);
  return new;
end;
$$;

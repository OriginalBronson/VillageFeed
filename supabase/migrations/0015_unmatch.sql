-- Unmatch: matches were insert/select-only, so the only way for a user to undo a
-- match was to block the other person — far too blunt for "we never actually
-- traded". Either participant may delete their own match row.
--
-- (Salvaged from a parallel working copy; renumbered 0006 -> 0015 to sit after
-- the launch-readiness migration series.)

create policy "participants remove their matches"
  on public.matches for delete
  to authenticated
  using (a = auth.uid() or b = auth.uid());

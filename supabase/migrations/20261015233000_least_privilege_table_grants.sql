-- Remove browser table privileges that are not required by the current UI.
-- Teacher registration writes assignments through its protected SECURITY DEFINER RPC.

revoke delete on table public.classes, public.people, public.teacher_classes
  from authenticated;
revoke insert, update on table public.teacher_classes
  from authenticated;

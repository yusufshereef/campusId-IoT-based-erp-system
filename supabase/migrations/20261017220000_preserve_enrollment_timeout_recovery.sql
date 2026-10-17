-- Keep the established enrollment timeout recovery when admins refresh status.
-- DELETE_FINGERPRINT is deliberately excluded because a claimed delete may have
-- changed physical sensor state and must remain recoverable by its command ID.
create or replace function public.get_fingerprint_statuses()
returns table(person_id uuid, device_code text, display_name text, slot_id integer,
  enrollment_status text, command_id uuid, command_status text, error_message text)
language plpgsql volatile security definer
set search_path=pg_catalog,public
as $$
begin
  if auth.uid() is null or not public.is_administrator() then return; end if;
  update public.device_commands dc set status='failed',completed_at=now(),updated_at=now(),
    error_message='Terminal confirmation timed out; inspect sensor before retry'
  where dc.command_type='ENROLL_FINGERPRINT' and dc.status in ('pending','processing')
    and coalesce(dc.claimed_at,dc.created_at)<now()-interval '10 minutes';
  return query
  with latest_commands as (
    select distinct on (dc.payload->>'person_id') (dc.payload->>'person_id')::uuid person_id,
      dc.id,dc.status,dc.error_message,dc.device_id,dc.command_type
    from public.device_commands dc order by dc.payload->>'person_id',dc.created_at desc
  )
  select p.id,coalesce(d.device_code,enrolled.device_code),coalesce(d.display_name,enrolled.display_name),
    enrolled.slot_id,
    case when enrolled.slot_id is not null and latest.command_type='DELETE_FINGERPRINT' and latest.status in ('pending','processing') then 'delete_processing'
      when enrolled.slot_id is not null then 'enrolled'
      when latest.command_type='DELETE_FINGERPRINT' and latest.status='failed' then 'delete_failed'
      when latest.command_type='DELETE_FINGERPRINT' and latest.status='completed' then 'not_enrolled'
      when latest.status in ('pending','processing') then 'in_progress'
      when latest.status='failed' then 'failed' else 'not_enrolled' end,
    latest.id,latest.status,latest.error_message
  from public.people p left join latest_commands latest on latest.person_id=p.id
  left join public.devices d on d.id=latest.device_id
  left join lateral (select fm.slot_id,dv.device_code,dv.display_name from public.fingerprint_mappings fm
    join public.devices dv on dv.device_code=fm.device_id where fm.person_id=p.id and fm.status='active'
    order by fm.created_at desc limit 1) enrolled on true
  where p.role='student';
end;
$$;
notify pgrst,'reload schema';

-- Serialize enrollment and deletion as one device-level lifecycle.
create or replace function public.create_enrollment_command(
  p_person_id uuid, p_device_id uuid
)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  command_id uuid;
  device_code text;
  active_command public.device_commands;
begin
  if auth.uid() is null or not public.is_administrator() then
    raise exception 'Administrator access is required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.people
                 where id = p_person_id and role = 'student' and active) then
    raise exception 'Active student was not found' using errcode = '23503';
  end if;

  -- Both lifecycle request functions lock this row before checking commands.
  select d.device_code into device_code
  from public.devices d where d.id = p_device_id for update;
  if device_code is null or not exists (
    select 1 from public.devices d where d.id = p_device_id
      and d.last_seen_at >= now() - interval '25 seconds'
      and d.sensor_ready
  ) then
    raise exception 'Terminal is offline or unavailable' using errcode = '55000';
  end if;

  update public.device_commands dc
  set status = 'failed', completed_at = now(), updated_at = now(),
      error_message = 'Terminal confirmation timed out; inspect sensor before retry'
  where dc.device_id = p_device_id and dc.command_type = 'ENROLL_FINGERPRINT'
    and dc.status in ('pending', 'processing')
    and coalesce(dc.claimed_at, dc.created_at) < now() - interval '10 minutes';

  select dc.* into active_command
  from public.device_commands dc
  where dc.device_id = p_device_id
    and dc.command_type in ('ENROLL_FINGERPRINT', 'DELETE_FINGERPRINT')
    and dc.status in ('pending', 'processing')
  order by dc.created_at limit 1;
  if active_command.id is not null then
    if active_command.command_type = 'ENROLL_FINGERPRINT'
       and active_command.payload ->> 'person_id' = p_person_id::text then
      return active_command.id;
    end if;
    raise exception 'Another fingerprint command is already in progress'
      using errcode = '55000';
  end if;

  if exists (select 1 from public.fingerprint_mappings fm
             where fm.device_id = device_code and fm.person_id = p_person_id
               and fm.status = 'active') then
    raise exception 'Student is already enrolled on this terminal'
      using errcode = '23505';
  end if;
  insert into public.device_commands (device_id, command_type, payload)
  select p_device_id, 'ENROLL_FINGERPRINT',
         jsonb_build_object('person_id', p.id, 'display_name', p.full_name)
  from public.people p where p.id = p_person_id
  returning id into command_id;
  return command_id;
end;
$$;

-- Repeated identical intent is idempotent. A different workflow may not adopt
-- an in-flight delete because it would change the promised post-delete action.
create or replace function public.create_fingerprint_delete_command(
  p_person_id uuid, p_workflow text default 'remove'
)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  command_id uuid;
  mapping public.fingerprint_mappings;
  device public.devices;
  active_command public.device_commands;
begin
  if auth.uid() is null or not public.is_administrator() then
    raise exception 'Administrator access is required' using errcode = '42501';
  end if;
  if p_workflow not in ('remove','reenroll','student_delete') then
    raise exception 'Invalid fingerprint workflow';
  end if;
  perform 1 from public.people where id = p_person_id and role = 'student' for update;
  if not found then raise exception 'Student was not found'; end if;
  select * into mapping from public.fingerprint_mappings
   where person_id = p_person_id and status = 'active' for update;
  if not found then raise exception 'Student has no active fingerprint mapping'; end if;
  if (select count(*) from public.fingerprint_mappings
      where person_id = p_person_id and status = 'active') <> 1 then
    raise exception 'Student must have exactly one active fingerprint mapping';
  end if;
  select d.* into device from public.devices d
   where d.device_code = mapping.device_id for update;
  if device.id is null or device.last_seen_at is null
     or device.last_seen_at < now() - interval '25 seconds' then
    raise exception 'Terminal is offline' using errcode = '55000';
  end if;
  if not device.sensor_ready then
    raise exception 'Fingerprint sensor is unavailable' using errcode = '55000';
  end if;
  select * into active_command from public.device_commands dc
   where dc.device_id = device.id and dc.status in ('pending', 'processing')
   order by dc.created_at limit 1;
  if active_command.id is not null then
    if active_command.command_type = 'DELETE_FINGERPRINT'
       and active_command.payload ->> 'person_id' = p_person_id::text then
      if active_command.payload ->> 'workflow' is distinct from p_workflow then
        raise exception 'Another fingerprint workflow is already in progress'
          using errcode = '55000';
      end if;
      return active_command.id;
    end if;
    raise exception 'Another fingerprint command is already in progress'
      using errcode = '55000';
  end if;
  insert into public.device_commands(device_id, command_type, payload, reserved_slot)
  values (device.id, 'DELETE_FINGERPRINT',
    jsonb_build_object('person_id', p_person_id, 'slot_id', mapping.slot_id,
                       'workflow', p_workflow), mapping.slot_id)
  returning id into command_id;
  return command_id;
end;
$$;

notify pgrst, 'reload schema';

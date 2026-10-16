-- A terminal has one enrollment operation at a time. The existing device row
-- is locked by create_enrollment_command before testing this constraint.
create unique index if not exists device_commands_one_active_enrollment_idx
  on public.device_commands (device_id)
  where command_type = 'ENROLL_FINGERPRINT'
    and status in ('pending', 'processing');

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

  -- Serialize double clicks and concurrent browser sessions for this device.
  select d.device_code into device_code
  from public.devices d where d.id = p_device_id for update;
  if device_code is null or not exists (
    select 1 from public.devices d where d.id = p_device_id
      and d.last_seen_at >= now() - interval '25 seconds'
  ) then
    raise exception 'Terminal is offline' using errcode = '55000';
  end if;

  update public.device_commands dc
  set status = 'failed', completed_at = now(), updated_at = now(),
      error_message = 'Terminal confirmation timed out; inspect sensor before retry'
  where dc.device_id = p_device_id and dc.command_type = 'ENROLL_FINGERPRINT'
    and dc.status in ('pending', 'processing')
    and coalesce(dc.claimed_at, dc.created_at) < now() - interval '10 minutes';

  select dc.* into active_command
  from public.device_commands dc
  where dc.device_id = p_device_id and dc.command_type = 'ENROLL_FINGERPRINT'
    and dc.status in ('pending', 'processing')
  order by dc.created_at limit 1;
  if active_command.id is not null then
    if active_command.payload ->> 'person_id' = p_person_id::text then
      return active_command.id;
    end if;
    raise exception 'Another enrollment is already in progress'
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

create or replace function public.claim_device_command(p_device_id uuid)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  command public.device_commands;
begin
  update public.device_commands dc
  set status = 'failed', completed_at = now(), updated_at = now(),
      error_message = 'Terminal confirmation timed out; inspect sensor before retry'
  where dc.device_id = p_device_id and dc.command_type = 'ENROLL_FINGERPRINT'
    and dc.status in ('pending', 'processing')
    and coalesce(dc.claimed_at, dc.created_at) < now() - interval '10 minutes';

  select * into command from public.device_commands
  where device_id = p_device_id and status = 'pending'
  order by created_at for update skip locked limit 1;
  if command.id is null then return null; end if;
  update public.device_commands
  set status = 'processing', claimed_at = now(), updated_at = now()
  where id = command.id;
  return jsonb_build_object('id', command.id,
                            'command_type', command.command_type,
                            'payload', command.payload);
end;
$$;

create or replace function public.complete_device_command(
  p_command_id uuid, p_device_id uuid, p_success boolean,
  p_template_id integer default null, p_error_message text default null
)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  command public.device_commands;
  device_code text;
  person_id uuid;
begin
  select dc.* into command from public.device_commands dc
  where dc.id = p_command_id and dc.device_id = p_device_id for update;
  if command.id is null then
    raise exception 'Command was not found' using errcode = 'P0002';
  end if;
  if command.status = 'completed' then
    return jsonb_build_object('status', 'completed', 'result', command.result);
  end if;
  if command.status = 'cancelled' then
    return jsonb_build_object('status', 'cancelled');
  end if;
  if command.status = 'failed' and command.error_message is distinct from
      'Terminal confirmation timed out; inspect sensor before retry' then
    return jsonb_build_object('status', 'failed');
  end if;
  if command.status = 'failed' and exists (
    select 1 from public.device_commands newer
    where newer.device_id = p_device_id and newer.created_at > command.created_at
  ) then
    return jsonb_build_object('status', 'failed');
  end if;
  if command.status = 'pending' then
    raise exception 'Command was not claimed' using errcode = '55000';
  end if;

  person_id := (command.payload ->> 'person_id')::uuid;
  select d.device_code into device_code from public.devices d
  where d.id = p_device_id;
  if p_success then
    if p_template_id is null or p_template_id <= 0 then
      raise exception 'A valid template ID is required';
    end if;
    -- The unique device/slot and device/person constraints are the final guard.
    -- Keep the command and mapping transition in this one transaction.
    begin
      insert into public.fingerprint_mappings (device_id, slot_id, person_id)
      values (device_code, p_template_id, person_id);
    exception when unique_violation then
      update public.device_commands
      set status = 'failed', completed_at = now(), updated_at = now(),
          error_message = 'Template or student mapping conflict; inspect sensor'
      where id = p_command_id;
      return jsonb_build_object('status', 'failed');
    end;
    update public.device_commands
    set status = 'completed', completed_at = now(), updated_at = now(),
        result = jsonb_build_object('template_id', p_template_id),
        error_message = null
    where id = p_command_id;
    update public.people set fingerprint_status = 'enrolled'
    where id = person_id;
    return jsonb_build_object('status', 'completed');
  end if;
  update public.device_commands
  set status = 'failed', completed_at = now(), updated_at = now(),
      error_message = left(coalesce(p_error_message, 'Enrollment failed'), 500)
  where id = p_command_id;
  return jsonb_build_object('status', 'failed');
end;
$$;

create or replace function public.get_fingerprint_statuses()
returns table (
  person_id uuid, device_code text, display_name text, slot_id integer,
  enrollment_status text, command_id uuid, command_status text,
  error_message text
)
language plpgsql volatile security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null or not public.is_administrator() then return; end if;
  -- Resolve abandoned commands whenever an administrator observes status.
  update public.device_commands dc
  set status = 'failed', completed_at = now(), updated_at = now(),
      error_message = 'Terminal confirmation timed out; inspect sensor before retry'
  where dc.command_type = 'ENROLL_FINGERPRINT'
    and dc.status in ('pending', 'processing')
    and coalesce(dc.claimed_at, dc.created_at) < now() - interval '10 minutes';

  return query
  with latest_commands as (
    select distinct on (dc.payload ->> 'person_id')
      (dc.payload ->> 'person_id')::uuid as person_id, dc.id, dc.status,
      dc.error_message, dc.device_id
    from public.device_commands dc
    order by dc.payload ->> 'person_id', dc.created_at desc
  )
  select p.id, coalesce(d.device_code, enrolled.device_code),
         coalesce(d.display_name, enrolled.display_name), enrolled.slot_id,
         case when enrolled.slot_id is not null then 'enrolled'
              when latest.status in ('pending', 'processing') then 'in_progress'
              when latest.status = 'failed' then 'failed'
              else 'not_enrolled' end,
         latest.id, latest.status, latest.error_message
  from public.people p
  left join latest_commands latest on latest.person_id = p.id
  left join public.devices d on d.id = latest.device_id
  left join lateral (
    select fm.slot_id, dv.device_code, dv.display_name
    from public.fingerprint_mappings fm
    join public.devices dv on dv.device_code = fm.device_id
    where fm.person_id = p.id and fm.status = 'active'
    order by fm.created_at desc limit 1
  ) enrolled on true
  where p.role = 'student';
end;
$$;

-- The sensor index can be empty even when a backend mapping still owns a slot.
-- Include every database-reserved location in the claimed command response.
create or replace function public.claim_device_command(p_device_id uuid)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  command public.device_commands;
  reserved_slots jsonb;
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

  select coalesce(jsonb_agg(fm.slot_id order by fm.slot_id), '[]'::jsonb)
    into reserved_slots
  from public.fingerprint_mappings fm
  join public.devices d on d.device_code = fm.device_id
  where d.id = p_device_id;

  update public.device_commands
  set status = 'processing', claimed_at = now(), updated_at = now()
  where id = command.id;
  return jsonb_build_object('id', command.id,
                            'command_type', command.command_type,
                            'payload', command.payload,
                            'reserved_slots', reserved_slots);
end;
$$;

-- Reject conflicting retries without changing an already completed mapping.
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
    if not p_success or p_template_id is distinct from
        (command.result ->> 'template_id')::integer then
      return jsonb_build_object('status', 'rejected', 'error', 'Conflicting completion result');
    end if;
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

alter table public.device_commands
  add column if not exists reserved_slot integer
  check (reserved_slot is null or reserved_slot between 1 and 1023);

create index if not exists device_commands_reserved_slot_idx
  on public.device_commands(device_id, reserved_slot)
  where reserved_slot is not null;

drop function if exists public.claim_device_command(uuid);

create function public.claim_device_command(
  p_device_id uuid,
  p_capacity integer
)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  command public.device_commands;
  device_code text;
  allocated_slot integer;
begin
  if p_capacity is null or p_capacity < 1 or p_capacity > 1023 then
    return null;
  end if;

  update public.device_commands dc
  set status = 'failed', completed_at = now(), updated_at = now(),
      error_message = 'Terminal confirmation timed out; inspect sensor before retry'
  where dc.device_id = p_device_id and dc.command_type = 'ENROLL_FINGERPRINT'
    and dc.status in ('pending', 'processing')
    and coalesce(dc.claimed_at, dc.created_at) < now() - interval '10 minutes';

  select * into command
  from public.device_commands
  where device_id = p_device_id and status = 'pending'
  order by created_at
  for update skip locked
  limit 1;
  if command.id is null then return null; end if;

  select d.device_code into device_code
  from public.devices d where d.id = p_device_id;

  select available.slot_id into allocated_slot
  from generate_series(1, p_capacity) as available(slot_id)
  where not exists (
    select 1 from public.fingerprint_mappings fm
    where fm.device_id = device_code and fm.slot_id = available.slot_id
  )
  and not exists (
    select 1 from public.device_commands reserved
    where reserved.device_id = p_device_id
      and reserved.id <> command.id
      and reserved.reserved_slot = available.slot_id
  )
  order by available.slot_id
  limit 1;

  if allocated_slot is null then
    update public.device_commands
    set status = 'failed', completed_at = now(), updated_at = now(),
        error_message = 'Fingerprint storage full'
    where id = command.id;
    return null;
  end if;

  update public.device_commands
  set status = 'processing', claimed_at = now(), updated_at = now(),
      reserved_slot = allocated_slot
  where id = command.id;
  return jsonb_build_object(
    'id', command.id,
    'command_type', command.command_type,
    'payload', command.payload,
    'reserved_slot', allocated_slot
  );
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
    if p_template_id is null or p_template_id <= 0 or
       p_template_id is distinct from command.reserved_slot then
      update public.device_commands
      set status = 'failed', completed_at = now(), updated_at = now(),
          error_message = 'Reserved slot mismatch; inspect sensor'
      where id = p_command_id;
      return jsonb_build_object('status', 'failed');
    end if;
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
      error_message = left(coalesce(p_error_message, 'Enrollment failed'), 500),
      reserved_slot = case
        when coalesce(p_error_message, '') like 'Storage uncertain%' then reserved_slot
        else null
      end
  where id = p_command_id;
  return jsonb_build_object('status', 'failed');
end;
$$;

revoke all on function public.claim_device_command(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.claim_device_command(uuid, integer)
  to service_role;
revoke all on function public.complete_device_command(uuid, uuid, boolean, integer, text)
  from public, anon, authenticated;
grant execute on function public.complete_device_command(uuid, uuid, boolean, integer, text)
  to service_role;

notify pgrst, 'reload schema';

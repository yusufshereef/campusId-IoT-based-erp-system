-- CampusID Milestone 3: administrator-triggered terminal enrollment commands.
create table if not exists public.device_commands (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.devices(id) on delete cascade,
  command_type text not null check (command_type in ('ENROLL_FINGERPRINT')),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  claimed_at timestamptz,
  completed_at timestamptz,
  error_message text,
  result jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists device_commands_pending_idx
  on public.device_commands(device_id, status, created_at);

alter table public.device_commands enable row level security;
revoke all on table public.device_commands from public, anon, authenticated;

create or replace function public.create_enrollment_command(
  p_person_id uuid,
  p_device_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  command_id uuid;
  device_code text;
begin
  if auth.uid() is null or not public.is_administrator() then
    raise exception 'Administrator access is required' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.people
    where id = p_person_id and role = 'student' and active
  ) then
    raise exception 'Active student was not found' using errcode = '23503';
  end if;

  select d.device_code into device_code
  from public.devices d
  where d.id = p_device_id
    and d.last_seen_at is not null
    and d.last_seen_at >= now() - interval '15 seconds';
  if device_code is null then
    raise exception 'Terminal is offline' using errcode = '55000';
  end if;

  if exists (
    select 1 from public.fingerprint_mappings fm
    where fm.device_id = device_code and fm.person_id = p_person_id
      and fm.status = 'active'
  ) then
    raise exception 'Student is already enrolled on this terminal'
      using errcode = '23505';
  end if;

  if exists (
    select 1 from public.device_commands dc
    where dc.device_id = p_device_id
      and dc.command_type = 'ENROLL_FINGERPRINT'
      and dc.status in ('pending', 'processing')
  ) then
    raise exception 'Another enrollment is already in progress'
      using errcode = '55000';
  end if;

  insert into public.device_commands (device_id, command_type, payload)
  select p_device_id, 'ENROLL_FINGERPRINT',
    jsonb_build_object(
      'person_id', p.id,
      'display_name', p.full_name
    )
  from public.people p
  where p.id = p_person_id
  returning id into command_id;
  return command_id;
end;
$$;

create or replace function public.claim_device_command(p_device_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  command public.device_commands;
begin
  select * into command
  from public.device_commands
  where device_id = p_device_id and status = 'pending'
  order by created_at
  for update skip locked
  limit 1;

  if command.id is null then
    return null;
  end if;

  update public.device_commands
  set status = 'processing', claimed_at = now(), updated_at = now()
  where id = command.id;

  return jsonb_build_object(
    'id', command.id,
    'command_type', command.command_type,
    'payload', command.payload
  );
end;
$$;

create or replace function public.complete_device_command(
  p_command_id uuid,
  p_device_id uuid,
  p_success boolean,
  p_template_id integer default null,
  p_error_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  command public.device_commands;
  device_code text;
  person_id uuid;
begin
  select dc.*
  into command
  from public.device_commands dc
  join public.devices d on d.id = dc.device_id
  where dc.id = p_command_id and dc.device_id = p_device_id
  for update;
  select d.device_code into device_code
  from public.devices d
  where d.id = p_device_id;

  if command.id is null then
    raise exception 'Command was not found' using errcode = 'P0002';
  end if;
  if command.status = 'completed' then
    return jsonb_build_object('status', 'completed', 'result', command.result);
  end if;
  if command.status in ('failed', 'cancelled') then
    return jsonb_build_object('status', command.status);
  end if;

  person_id := (command.payload ->> 'person_id')::uuid;
  if p_success then
    if p_template_id is null or p_template_id <= 0 then
      raise exception 'A valid template ID is required';
    end if;
    insert into public.fingerprint_mappings (device_id, slot_id, person_id)
    values (device_code, p_template_id, person_id)
    on conflict (device_id, person_id) do update
      set slot_id = excluded.slot_id, status = 'active';
    update public.device_commands
    set status = 'completed',
        completed_at = now(),
        updated_at = now(),
        result = jsonb_build_object('template_id', p_template_id),
        error_message = null
    where id = p_command_id;
    update public.people
    set fingerprint_status = 'enrolled'
    where id = person_id;
  else
    update public.device_commands
    set status = 'failed',
        completed_at = now(),
        updated_at = now(),
        error_message = left(coalesce(p_error_message, 'Enrollment failed'), 500)
    where id = p_command_id;
  end if;
  return jsonb_build_object('status', case when p_success then 'completed' else 'failed' end);
end;
$$;

create or replace function public.get_fingerprint_statuses()
returns table (
  person_id uuid,
  device_code text,
  display_name text,
  slot_id integer,
  enrollment_status text,
  command_id uuid,
  command_status text,
  error_message text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with latest_commands as (
    select distinct on (dc.payload ->> 'person_id')
      (dc.payload ->> 'person_id')::uuid as person_id,
      dc.id,
      dc.status,
      dc.error_message,
      dc.device_id
    from public.device_commands dc
    order by dc.payload ->> 'person_id', dc.created_at desc
  )
  select p.id,
         coalesce(d.device_code, enrolled.device_code),
         coalesce(d.display_name, enrolled.display_name),
         enrolled.slot_id,
         case
           when enrolled.slot_id is not null then 'enrolled'
           when latest.status in ('pending', 'processing') then 'in_progress'
           when latest.status = 'failed' then 'failed'
           else 'not_enrolled'
         end,
         latest.id,
         latest.status,
         latest.error_message
  from public.people p
  left join latest_commands latest on latest.person_id = p.id
  left join public.devices d on d.id = latest.device_id
  left join lateral (
    select fm.slot_id, dv.device_code, dv.display_name
    from public.fingerprint_mappings fm
    join public.devices dv on dv.device_code = fm.device_id
    where fm.person_id = p.id and fm.status = 'active'
    order by fm.created_at desc
    limit 1
  ) enrolled on true
  where p.role = 'student'
    and (select public.is_administrator());
$$;

grant execute on function public.create_enrollment_command(uuid, uuid)
  to authenticated;
grant execute on function public.get_fingerprint_statuses()
  to authenticated;
revoke all on function public.claim_device_command(uuid)
  from public, anon, authenticated;
revoke all on function public.complete_device_command(uuid, uuid, boolean, integer, text)
  from public, anon, authenticated;

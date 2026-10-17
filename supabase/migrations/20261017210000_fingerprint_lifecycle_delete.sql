-- Physical deletion is acknowledged before its authoritative mapping is removed.
alter table public.device_commands drop constraint if exists device_commands_command_type_check;
alter table public.device_commands add constraint device_commands_command_type_check
  check (command_type in ('ENROLL_FINGERPRINT', 'DELETE_FINGERPRINT'));

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
  if (select count(*) from public.fingerprint_mappings where person_id = p_person_id and status = 'active') <> 1 then
    raise exception 'Student must have exactly one active fingerprint mapping';
  end if;
  select d.* into device from public.devices d where d.device_code = mapping.device_id for update;
  if device.id is null or device.last_seen_at is null or device.last_seen_at < now() - interval '25 seconds' then
    raise exception 'Terminal is offline' using errcode = '55000';
  end if;
  if not device.sensor_ready then raise exception 'Fingerprint sensor is unavailable' using errcode = '55000'; end if;
  select * into active_command from public.device_commands dc
   where dc.device_id = device.id and dc.status in ('pending', 'processing')
   order by dc.created_at limit 1;
  if active_command.id is not null then
    if active_command.command_type = 'DELETE_FINGERPRINT'
       and active_command.payload ->> 'person_id' = p_person_id::text then
      return active_command.id;
    end if;
    raise exception 'Another fingerprint command is already in progress' using errcode = '55000';
  end if;
  insert into public.device_commands(device_id, command_type, payload, reserved_slot)
  values (device.id, 'DELETE_FINGERPRINT',
    jsonb_build_object('person_id', p_person_id, 'slot_id', mapping.slot_id, 'workflow', p_workflow), mapping.slot_id)
  returning id into command_id;
  return command_id;
end;
$$;

create or replace function public.claim_device_command(p_device_id uuid, p_capacity integer)
returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  command public.device_commands;
  device_code text;
  allocated_slot integer;
  reserved_slots jsonb;
begin
  if p_capacity is null or p_capacity < 1 or p_capacity > 1023 then return null; end if;
  -- Enrollment timeouts are uncertain, so keep their slot reserved. A delete timeout
  -- is also uncertain and must remain visible for an operator to reconcile.
  update public.device_commands dc set status = 'failed', completed_at = now(), updated_at = now(),
    error_message = 'Terminal confirmation timed out; inspect sensor before retry'
  where dc.device_id = p_device_id and dc.command_type = 'ENROLL_FINGERPRINT'
    and dc.status in ('pending', 'processing')
    and coalesce(dc.claimed_at, dc.created_at) < now() - interval '10 minutes';
  select * into command from public.device_commands
   where device_id = p_device_id and status = 'pending'
   order by created_at for update skip locked limit 1;
  if command.id is null then return null; end if;
  select d.device_code into device_code from public.devices d where d.id = p_device_id;
  select coalesce(jsonb_agg(fm.slot_id order by fm.slot_id), '[]'::jsonb)
    into reserved_slots from public.fingerprint_mappings fm
    where fm.device_id = device_code;
  if command.command_type = 'ENROLL_FINGERPRINT' then
    select available.slot_id into allocated_slot from generate_series(1, p_capacity) available(slot_id)
    where not exists (select 1 from public.fingerprint_mappings fm where fm.device_id = device_code and fm.slot_id = available.slot_id)
      and not exists (select 1 from public.device_commands dc where dc.device_id = p_device_id and dc.id <> command.id and dc.reserved_slot = available.slot_id)
    order by available.slot_id limit 1;
    if allocated_slot is null then
      update public.device_commands set status='failed', completed_at=now(), updated_at=now(), error_message='Fingerprint storage full' where id=command.id;
      return null;
    end if;
  else
    allocated_slot := command.reserved_slot;
    if allocated_slot is null or allocated_slot < 1 or allocated_slot > p_capacity
       or not exists (select 1 from public.fingerprint_mappings fm
         where fm.device_id=device_code and fm.slot_id=allocated_slot
           and fm.person_id=(command.payload->>'person_id')::uuid and fm.status='active') then
      update public.device_commands set status='failed', completed_at=now(), updated_at=now(), error_message='Fingerprint mapping changed; inspect terminal' where id=command.id;
      return null;
    end if;
  end if;
  update public.device_commands set status='processing', claimed_at=now(), updated_at=now(),
    reserved_slot=allocated_slot where id=command.id;
  return jsonb_build_object('id',command.id,'command_type',command.command_type,
    'payload',command.payload,'reserved_slot',allocated_slot,'reserved_slots',reserved_slots);
end;
$$;

create or replace function public.complete_device_command(
  p_command_id uuid, p_device_id uuid, p_success boolean,
  p_template_id integer default null, p_error_message text default null
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  command public.device_commands;
  device_code text;
  person_id uuid;
  command_slot integer;
  student_deleted boolean := false;
begin
  select dc.* into command from public.device_commands dc
   where dc.id=p_command_id and dc.device_id=p_device_id for update;
  if command.id is null then raise exception 'Command was not found' using errcode='P0002'; end if;
  if command.status='completed' then
    if command.command_type='DELETE_FINGERPRINT' and p_success
       and p_template_id is not distinct from (command.result->>'slot_id')::integer then
      return jsonb_build_object('status','completed','result',command.result);
    end if;
    if command.command_type='ENROLL_FINGERPRINT' and p_success
       and p_template_id is not distinct from (command.result->>'template_id')::integer then
      return jsonb_build_object('status','completed','result',command.result);
    end if;
    return jsonb_build_object('status','rejected','error','Conflicting completion result');
  end if;
  if command.status in ('cancelled') then return jsonb_build_object('status',command.status); end if;
  if command.status='pending' then raise exception 'Command was not claimed' using errcode='55000'; end if;
  person_id := (command.payload->>'person_id')::uuid;
  command_slot := command.reserved_slot;
  select d.device_code into device_code from public.devices d where d.id=p_device_id;
  if command.command_type='DELETE_FINGERPRINT' then
    if p_template_id is distinct from command_slot then
      return jsonb_build_object('status','rejected','error','Conflicting slot result');
    end if;
    if command.status='failed' then
      if p_success then return jsonb_build_object('status','rejected','error','Conflicting physical result'); end if;
      return jsonb_build_object('status','failed');
    end if;
    if p_success then
      delete from public.fingerprint_mappings fm
       where fm.device_id=device_code and fm.person_id=person_id and fm.slot_id=command_slot and fm.status='active';
      if not found then
        return jsonb_build_object('status','rejected','error','Authoritative mapping changed');
      end if;
      update public.device_commands dc set reserved_slot=null
       where dc.device_id=p_device_id and dc.command_type='DELETE_FINGERPRINT'
         and dc.payload->>'person_id'=person_id::text and dc.reserved_slot=command_slot
         and dc.status='failed';
      update public.people set fingerprint_status='not_enrolled' where id=person_id;
      update public.device_commands set status='completed', completed_at=now(), updated_at=now(),
        result=jsonb_build_object('physical_deleted',true,'slot_id',command_slot), error_message=null,
        reserved_slot=null where id=p_command_id;
      if command.payload->>'workflow'='reenroll' then
        insert into public.device_commands(device_id,command_type,payload)
        select p_device_id,'ENROLL_FINGERPRINT',jsonb_build_object('person_id',p.id,'display_name',p.full_name)
        from public.people p where p.id=person_id and p.role='student' and p.active;
      end if;
      if command.payload->>'workflow'='student_delete'
         and not exists(select 1 from public.attendance_records ar where ar.student_id=person_id)
         and not exists(select 1 from public.attendance_record_audit aa where aa.old_student_id=person_id or aa.new_student_id=person_id)
         and not exists(select 1 from public.fingerprint_mappings fm where fm.person_id=person_id)
         and not exists(select 1 from public.device_commands ec where ec.command_type='ENROLL_FINGERPRINT'
           and ec.payload->>'person_id'=person_id::text and ec.status in ('pending','processing')) then
        delete from public.user_roles ur where ur.person_id=person_id;
        delete from public.people p where p.id=person_id and p.role='student';
        student_deleted := found;
        update public.device_commands set result=jsonb_build_object('physical_deleted',true,
          'slot_id',command_slot,'student_deleted',student_deleted) where id=p_command_id;
      end if;
      return jsonb_build_object('status','completed');
    end if;
    update public.device_commands set status='failed', completed_at=now(), updated_at=now(),
      result=jsonb_build_object('physical_deleted',false,'slot_id',command_slot),
      error_message=left(coalesce(p_error_message,'Fingerprint deletion failed'),500) where id=p_command_id;
    return jsonb_build_object('status','failed');
  end if;
  if command.status='failed' and command.error_message is distinct from 'Terminal confirmation timed out; inspect sensor before retry' then
    return jsonb_build_object('status','failed');
  end if;
  if p_success then
    if p_template_id is null or p_template_id <> command_slot then return jsonb_build_object('status','rejected','error','Reserved slot mismatch'); end if;
    begin
      insert into public.fingerprint_mappings(device_id,slot_id,person_id) values(device_code,p_template_id,person_id);
    exception when unique_violation then
      update public.device_commands set status='failed', completed_at=now(), updated_at=now(), error_message='Template or student mapping conflict; inspect sensor' where id=p_command_id;
      return jsonb_build_object('status','failed');
    end;
    update public.device_commands set status='completed', completed_at=now(), updated_at=now(), result=jsonb_build_object('template_id',p_template_id), error_message=null where id=p_command_id;
    update public.people set fingerprint_status='enrolled' where id=person_id;
    return jsonb_build_object('status','completed');
  end if;
  update public.device_commands set status='failed', completed_at=now(), updated_at=now(),
    error_message=left(coalesce(p_error_message,'Enrollment failed'),500),
    reserved_slot=case when coalesce(p_error_message,'') like 'Storage uncertain%' then reserved_slot else null end
    where id=p_command_id;
  return jsonb_build_object('status','failed');
end;
$$;

create or replace function public.get_fingerprint_statuses()
returns table(person_id uuid, device_code text, display_name text, slot_id integer,
  enrollment_status text, command_id uuid, command_status text, error_message text)
language sql stable security definer set search_path=pg_catalog,public
as $$
  with latest_commands as (
    select distinct on (dc.payload->>'person_id') (dc.payload->>'person_id')::uuid person_id,
      dc.id,dc.status,dc.error_message,dc.device_id,dc.command_type
    from public.device_commands dc
    order by dc.payload->>'person_id',dc.created_at desc
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
  where p.role='student' and (select public.is_administrator());
$$;

grant execute on function public.create_fingerprint_delete_command(uuid,text) to authenticated;
revoke all on function public.create_fingerprint_delete_command(uuid,text) from public,anon;
revoke all on function public.claim_device_command(uuid,integer) from public,anon,authenticated;
grant execute on function public.claim_device_command(uuid,integer) to service_role;
revoke all on function public.complete_device_command(uuid,uuid,boolean,integer,text) from public,anon,authenticated;
grant execute on function public.complete_device_command(uuid,uuid,boolean,integer,text) to service_role;
notify pgrst,'reload schema';

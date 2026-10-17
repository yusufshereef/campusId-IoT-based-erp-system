-- Cleanup tombstones reuse device_commands and reserve their exact hardware slot.
alter table public.device_commands
  add column if not exists attempts integer not null default 0,
  add column if not exists next_retry_at timestamptz;

create or replace function public.create_enrollment_command(
  p_person_id uuid, p_device_id uuid
)
returns uuid
language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare
  command_id uuid;
  device_code text;
  active_command public.device_commands;
begin
  if auth.uid() is null or not public.is_administrator() then
    raise exception 'Administrator access is required' using errcode='42501';
  end if;
  perform 1 from public.people
   where id=p_person_id and role='student' and active for key share;
  if not found then raise exception 'Active student was not found' using errcode='23503'; end if;
  select d.device_code into device_code from public.devices d
   where d.id=p_device_id for update;
  if device_code is null or not exists(select 1 from public.devices d
    where d.id=p_device_id and d.last_seen_at>=now()-interval '25 seconds'
      and d.sensor_ready) then
    raise exception 'Terminal is offline or unavailable' using errcode='55000';
  end if;
  update public.device_commands dc set status='failed',completed_at=now(),updated_at=now(),
    error_message='Terminal confirmation timed out; inspect sensor before retry'
  where dc.device_id=p_device_id and dc.command_type='ENROLL_FINGERPRINT'
    and dc.status in ('pending','processing')
    and coalesce(dc.claimed_at,dc.created_at)<now()-interval '10 minutes';
  select dc.* into active_command from public.device_commands dc
  where dc.device_id=p_device_id and dc.status in ('pending','processing')
    and (dc.command_type='ENROLL_FINGERPRINT' or
         (dc.command_type='DELETE_FINGERPRINT' and
          dc.payload->>'cleanup_only' is distinct from 'true'))
  order by dc.created_at limit 1;
  if active_command.id is not null then
    if active_command.command_type='ENROLL_FINGERPRINT'
       and active_command.payload->>'person_id'=p_person_id::text then
      return active_command.id;
    end if;
    raise exception 'Another fingerprint command is already in progress' using errcode='55000';
  end if;
  if exists(select 1 from public.fingerprint_mappings fm where fm.device_id=device_code
      and fm.person_id=p_person_id and fm.status='active') then
    raise exception 'Student is already enrolled on this terminal' using errcode='23505';
  end if;
  insert into public.device_commands(device_id,command_type,payload)
  select p_device_id,'ENROLL_FINGERPRINT',
    jsonb_build_object('person_id',p.id,'display_name',p.full_name)
  from public.people p where p.id=p_person_id returning id into command_id;
  return command_id;
end;
$$;

create or replace function public.delete_student(p_person_id uuid)
returns boolean
language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare
  student public.people;
  target record;
  cleanup_id uuid;
  has_cleanup_target boolean := false;
begin
  if auth.uid() is null or not public.is_administrator() then
    raise exception 'Administrator access is required' using errcode='42501';
  end if;
  select p.* into student from public.people p where p.id=p_person_id for update;
  if student.id is null or student.role<>'student' then
    raise exception 'Student was not found';
  end if;
  if exists(select 1 from public.fingerprint_mappings fm
      left join public.devices d on d.device_code=fm.device_id
      where fm.person_id=p_person_id and d.id is null) then
    raise exception 'Fingerprint device is unknown; student was not deleted';
  end if;
  if exists(select 1 from public.device_commands dc
      where dc.command_type='ENROLL_FINGERPRINT'
        and dc.payload->>'person_id'=p_person_id::text
        and dc.status='processing' and dc.reserved_slot is null) then
    raise exception 'Active enrollment has no authoritative slot; student was not deleted';
  end if;

  -- If an enrollment was claimed, preserve its exact slot as an anonymous
  -- cleanup job. Unclaimed commands are safe to cancel without touching hardware.
  for target in
    select dc.device_id,dc.reserved_slot slot_id
    from public.device_commands dc
    where dc.command_type='ENROLL_FINGERPRINT'
      and dc.payload->>'person_id'=p_person_id::text
      and dc.status in ('processing','failed','completed','cancelled')
      and dc.reserved_slot is not null
    union
    select d.id,fm.slot_id from public.fingerprint_mappings fm
      join public.devices d on d.device_code=fm.device_id where fm.person_id=p_person_id
    union
    select dc.device_id,coalesce(dc.reserved_slot,
      (dc.payload->>'slot_id')::integer) from public.device_commands dc
    where dc.command_type='DELETE_FINGERPRINT'
      and dc.payload->>'person_id'=p_person_id::text
      and dc.status in ('pending','processing','failed','cancelled')
      and coalesce(dc.reserved_slot,(dc.payload->>'slot_id')::integer) is not null
  loop
    has_cleanup_target:=true;
    if target.slot_id is null or target.slot_id < 1 then
      raise exception 'Fingerprint slot is invalid; student was not deleted';
    end if;
    select dc.id into cleanup_id from public.device_commands dc
      where dc.device_id=target.device_id and dc.command_type='DELETE_FINGERPRINT'
        and coalesce(dc.reserved_slot,(dc.payload->>'slot_id')::integer)=target.slot_id
        and dc.status in ('pending','processing','failed')
      order by dc.created_at limit 1 for update;
    if cleanup_id is null then
      insert into public.device_commands(device_id,command_type,payload,reserved_slot)
      values(target.device_id,'DELETE_FINGERPRINT',
        jsonb_build_object('cleanup_only',true,'slot_id',target.slot_id),target.slot_id);
    else
      update public.device_commands set payload=jsonb_build_object(
          'cleanup_only',true,'slot_id',target.slot_id),
        reserved_slot=target.slot_id,
        status=case when status in ('failed','cancelled') then 'pending' else status end,
        completed_at=case when status in ('failed','cancelled') then null else completed_at end,
        error_message=null,next_retry_at=null,updated_at=now()
      where id=cleanup_id;
    end if;
  end loop;
  if student.fingerprint_status='enrolled' and not has_cleanup_target then
    raise exception 'Enrolled fingerprint has no authoritative slot; student was not deleted';
  end if;

  update public.device_commands dc set status='cancelled',reserved_slot=null,
    payload='{"retired":true}'::jsonb,completed_at=now(),updated_at=now()
  where dc.command_type='ENROLL_FINGERPRINT'
    and dc.payload->>'person_id'=p_person_id::text and dc.status='pending';
  update public.device_commands dc set payload=case
      when dc.reserved_slot is null then '{"retired":true}'::jsonb
      else jsonb_build_object('retired',true,'slot_id',dc.reserved_slot) end,
    reserved_slot=null,updated_at=now()
  where dc.command_type='ENROLL_FINGERPRINT'
    and dc.payload->>'person_id'=p_person_id::text
    and dc.status in ('processing','failed','completed','cancelled');
  update public.device_commands dc set payload=case
      when coalesce(dc.reserved_slot,(dc.payload->>'slot_id')::integer) is not null
        and dc.status in ('pending','processing','failed','cancelled')
        then jsonb_build_object('cleanup_only',true,
          'slot_id',coalesce(dc.reserved_slot,(dc.payload->>'slot_id')::integer))
      else '{"retired":true}'::jsonb end,
    status=case when dc.status='pending' and dc.reserved_slot is null
      then 'cancelled' else dc.status end,
    reserved_slot=case
      when dc.status in ('pending','processing','failed') and dc.reserved_slot is null
        then (dc.payload->>'slot_id')::integer
      when dc.status='cancelled' then null else dc.reserved_slot end,
    updated_at=now()
  where dc.command_type='DELETE_FINGERPRINT'
    and dc.payload->>'person_id'=p_person_id::text;
  update public.device_commands dc set payload='{"retired":true}'::jsonb,
    reserved_slot=null,
    status=case when dc.command_type='DELETE_FINGERPRINT' and dc.status='pending'
                    and dc.reserved_slot is null then 'cancelled' else dc.status end,
    updated_at=now() where dc.payload->>'person_id'=p_person_id::text;

  -- Attendance and audit rows are student-specific ERP data. Remove audit first
  -- because it references attendance rows with RESTRICT.
  delete from public.attendance_record_audit aa
  where aa.old_student_id=p_person_id or aa.new_student_id=p_person_id
     or aa.attendance_record_id in (select ar.id from public.attendance_records ar
                                    where ar.student_id=p_person_id);
  delete from public.attendance_records ar where ar.student_id=p_person_id;
  delete from public.fingerprint_mappings fm where fm.person_id=p_person_id;
  delete from public.user_roles ur where ur.person_id=p_person_id;
  delete from public.people p where p.id=p_person_id;
  return true;
end;
$$;

create or replace function public.delete_teacher(p_person_id uuid)
returns boolean
language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare teacher public.people;
begin
  if auth.uid() is null or not public.is_administrator() then
    raise exception 'Administrator access is required' using errcode='42501';
  end if;
  select p.* into teacher from public.people p where p.id=p_person_id for update;
  if teacher.id is null or teacher.role<>'teacher' then raise exception 'Teacher was not found'; end if;
  delete from public.teacher_classes tc where tc.teacher_id=p_person_id;
  delete from public.user_roles ur where ur.person_id=p_person_id;
  delete from public.people p where p.id=p_person_id;
  return true;
end;
$$;

create or replace function public.claim_device_command(p_device_id uuid,p_capacity integer)
returns jsonb
language plpgsql security definer
set search_path=pg_catalog,public
as $$
declare
  command public.device_commands;
  candidate public.device_commands;
  device_code text;
  allocated_slot integer;
  reserved_slots jsonb;
begin
  if p_capacity is null or p_capacity<1 or p_capacity>1023 then return null; end if;
  -- Re-offer a claimed cleanup whose local result may have been lost on reboot.
  -- The slot remains reserved; firmware probes that exact slot before mutation.
  update public.device_commands dc set status='pending',completed_at=null,
    next_retry_at=null,error_message='Cleanup result is uncertain; reconcile the same slot',
    updated_at=now()
  where dc.device_id=p_device_id and dc.command_type='DELETE_FINGERPRINT'
    and dc.payload->>'cleanup_only'='true' and dc.status='processing'
    and dc.claimed_at<now()-interval '2 minutes';
  update public.device_commands dc set status='pending',completed_at=null,
    next_retry_at=null,updated_at=now()
  where dc.device_id=p_device_id and dc.command_type='DELETE_FINGERPRINT'
    and dc.payload->>'cleanup_only'='true' and dc.status='failed'
    and dc.next_retry_at<=now();
  update public.device_commands dc set status='failed',completed_at=now(),updated_at=now(),
    error_message='Terminal confirmation timed out; inspect sensor before retry'
  where dc.device_id=p_device_id and dc.command_type='ENROLL_FINGERPRINT'
    and dc.payload->>'retired' is distinct from 'true'
    and dc.status in ('pending','processing')
    and coalesce(dc.claimed_at,dc.created_at)<now()-interval '10 minutes';
  select * into candidate from public.device_commands dc
    where dc.device_id=p_device_id and dc.status='pending'
    order by dc.created_at limit 1;
  if candidate.id is null then return null; end if;
  if candidate.command_type='ENROLL_FINGERPRINT'
     and candidate.payload->>'retired' is distinct from 'true' then
    perform 1 from public.people where id=(candidate.payload->>'person_id')::uuid
      and role='student' and active for key share;
    if not found then
      update public.device_commands set status='cancelled',completed_at=now(),updated_at=now(),
        error_message='Student no longer exists or is inactive'
      where id=candidate.id and status='pending';
      return null;
    end if;
  end if;
  select * into command from public.device_commands dc
    where dc.id=candidate.id and dc.status='pending'
    for update skip locked;
  if command.id is null then return null; end if;
  select d.device_code into device_code from public.devices d where d.id=p_device_id;
  select coalesce(jsonb_agg(fm.slot_id order by fm.slot_id),'[]'::jsonb)
    into reserved_slots from public.fingerprint_mappings fm where fm.device_id=device_code;
  if command.command_type='ENROLL_FINGERPRINT' then
    select available.slot_id into allocated_slot from generate_series(1,p_capacity) available(slot_id)
    where not exists(select 1 from public.fingerprint_mappings fm
        where fm.device_id=device_code and fm.slot_id=available.slot_id)
      and not exists(select 1 from public.device_commands dc
        where dc.device_id=p_device_id and dc.id<>command.id
          and dc.reserved_slot=available.slot_id)
    order by available.slot_id limit 1;
    if allocated_slot is null then
      update public.device_commands set status='failed',completed_at=now(),updated_at=now(),
        error_message='Fingerprint storage full' where id=command.id;
      return null;
    end if;
  elsif command.payload->>'cleanup_only'='true' then
    allocated_slot:=command.reserved_slot;
    if allocated_slot is null or allocated_slot<1 or allocated_slot>p_capacity
       or allocated_slot is distinct from (command.payload->>'slot_id')::integer then
      update public.device_commands set status='failed',error_message='Cleanup slot validation failed',
        next_retry_at=now()+interval '1 minute',updated_at=now() where id=command.id;
      return null;
    end if;
  else
    allocated_slot:=command.reserved_slot;
    if allocated_slot is null or allocated_slot<1 or allocated_slot>p_capacity
       or not exists(select 1 from public.fingerprint_mappings fm
          where fm.device_id=device_code and fm.slot_id=allocated_slot
            and fm.person_id=(command.payload->>'person_id')::uuid and fm.status='active') then
      update public.device_commands set status='failed',completed_at=now(),updated_at=now(),
        error_message='Fingerprint mapping changed; inspect terminal' where id=command.id;
      return null;
    end if;
  end if;
  update public.device_commands set status='processing',claimed_at=now(),updated_at=now(),
    reserved_slot=allocated_slot,attempts=attempts+1 where id=command.id;
  return jsonb_build_object('id',command.id,'command_type',command.command_type,
    'payload',command.payload,'reserved_slot',allocated_slot,'reserved_slots',reserved_slots);
end;
$$;

create or replace function public.complete_device_command(
  p_command_id uuid,p_device_id uuid,p_success boolean,
  p_template_id integer default null,p_error_message text default null
) returns jsonb
language plpgsql security definer
set search_path=pg_catalog,public
as $$
#variable_conflict use_variable
declare
  command public.device_commands;
  person_id uuid;
  device_code text;
  command_slot integer;
begin
  select dc.* into command from public.device_commands dc
    where dc.id=p_command_id and dc.device_id=p_device_id;
  if command.id is null then raise exception 'Command was not found' using errcode='P0002'; end if;
  if (command.command_type='ENROLL_FINGERPRINT'
      and command.payload->>'retired' is distinct from 'true') or
     (command.command_type='DELETE_FINGERPRINT'
      and command.payload->>'cleanup_only' is distinct from 'true'
      and command.payload ? 'person_id') then
    perform 1 from public.people where id=(command.payload->>'person_id')::uuid for update;
  end if;
  select dc.* into command from public.device_commands dc
    where dc.id=p_command_id and dc.device_id=p_device_id for update;
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
  command_slot:=coalesce(command.reserved_slot,
    (command.payload->>'slot_id')::integer);
  if command.status='cancelled' then return jsonb_build_object('status','cancelled'); end if;
  if command.status='pending' and not (
      command.command_type='DELETE_FINGERPRINT'
      and command.payload->>'cleanup_only'='true'
      and command.claimed_at is not null and command.attempts>0
      and p_template_id is not distinct from command_slot) then
    raise exception 'Command was not claimed' using errcode='55000';
  end if;
  if command.command_type='DELETE_FINGERPRINT' then
    if p_template_id is distinct from command_slot then
      if command.payload->>'cleanup_only'='true' then
        update public.device_commands set status='failed',completed_at=now(),updated_at=now(),
          error_message='Cleanup ACK slot mismatch',next_retry_at=now()+interval '1 minute'
          where id=p_command_id;
      end if;
      return jsonb_build_object('status','rejected','error','Conflicting slot result');
    end if;
    if command.payload->>'cleanup_only'='true' then
      if command.claimed_at is null or command.attempts<1 then
        return jsonb_build_object('status','rejected','error','Cleanup was not claimed');
      end if;
      if p_success then
        update public.device_commands set status='completed',completed_at=now(),updated_at=now(),
          result=jsonb_build_object('physical_deleted',true,'slot_id',command_slot),
          error_message=null,next_retry_at=null,reserved_slot=null where id=p_command_id;
        return jsonb_build_object('status','completed');
      end if;
      update public.device_commands set status='failed',completed_at=now(),updated_at=now(),
        result=jsonb_build_object('physical_deleted',false,'slot_id',command_slot),
        error_message=left(coalesce(p_error_message,'Fingerprint cleanup failed'),500),
        next_retry_at=now()+interval '1 minute' where id=p_command_id;
      return jsonb_build_object('status','failed');
    end if;
    person_id:=(command.payload->>'person_id')::uuid;
    select d.device_code into device_code from public.devices d where d.id=p_device_id;
    if command.status='failed' and command.error_message is distinct from
       'Terminal confirmation timed out; inspect sensor before retry' then
      if p_success and command.error_message ilike '%uncertain%' then null;
      elsif not p_success then return jsonb_build_object('status','failed');
      else return jsonb_build_object('status','rejected','error','Conflicting physical result'); end if;
    end if;
    if p_success then
      delete from public.fingerprint_mappings fm where fm.device_id=device_code
        and fm.person_id=person_id and fm.slot_id=command_slot and fm.status='active';
      if not found then return jsonb_build_object('status','rejected','error','Authoritative mapping changed'); end if;
      update public.device_commands set status='completed',completed_at=now(),updated_at=now(),
        result=jsonb_build_object('physical_deleted',true,'slot_id',command_slot),
        error_message=null,reserved_slot=null where id=p_command_id;
      update public.people set fingerprint_status='not_enrolled' where id=person_id;
      if command.payload->>'workflow'='reenroll' then
        insert into public.device_commands(device_id,command_type,payload)
        select p_device_id,'ENROLL_FINGERPRINT',jsonb_build_object('person_id',p.id,'display_name',p.full_name)
          from public.people p where p.id=person_id and p.role='student' and p.active
          and not exists(select 1 from public.device_commands e where e.device_id=p_device_id
            and e.command_type='ENROLL_FINGERPRINT' and e.status in ('pending','processing'));
      end if;
      return jsonb_build_object('status','completed');
    end if;
    update public.device_commands set status='failed',completed_at=now(),updated_at=now(),
      result=jsonb_build_object('physical_deleted',false,'slot_id',command_slot),
      error_message=left(coalesce(p_error_message,'Fingerprint deletion failed'),500)
      where id=p_command_id;
    return jsonb_build_object('status','failed');
  end if;
  if command.payload->>'retired'='true' then
    if p_success and p_template_id is distinct from command_slot then
      return jsonb_build_object('status','rejected','error','Conflicting retired enrollment slot');
    end if;
    update public.device_commands set status=case when p_success then 'completed' else 'failed' end,
      completed_at=now(),updated_at=now(),reserved_slot=null,
      result=case when p_success then jsonb_build_object('template_id',command_slot,'retired',true)
                  else jsonb_build_object('retired',true) end,
      error_message=case when p_success then null else left(coalesce(p_error_message,'Enrollment ended after student deletion'),500) end
      where id=p_command_id;
    return jsonb_build_object('status',case when p_success then 'completed' else 'failed' end);
  end if;
  if command.status='failed' and command.error_message is distinct from
     'Terminal confirmation timed out; inspect sensor before retry' then
    return jsonb_build_object('status','failed');
  end if;
  person_id:=(command.payload->>'person_id')::uuid;
  select d.device_code into device_code from public.devices d where d.id=p_device_id;
  if p_success then
    if p_template_id is null or p_template_id is distinct from command_slot then
      return jsonb_build_object('status','rejected','error','Reserved slot mismatch');
    end if;
    begin
      insert into public.fingerprint_mappings(device_id,slot_id,person_id)
      values(device_code,p_template_id,person_id);
    exception when unique_violation then
      update public.device_commands set status='failed',completed_at=now(),updated_at=now(),
        error_message='Template or student mapping conflict; inspect sensor' where id=p_command_id;
      return jsonb_build_object('status','failed');
    end;
    update public.device_commands set status='completed',completed_at=now(),updated_at=now(),
      result=jsonb_build_object('template_id',p_template_id),error_message=null where id=p_command_id;
    update public.people set fingerprint_status='enrolled' where id=person_id;
    return jsonb_build_object('status','completed');
  end if;
  update public.device_commands set status='failed',completed_at=now(),updated_at=now(),
    error_message=left(coalesce(p_error_message,'Enrollment failed'),500),
    reserved_slot=case when coalesce(p_error_message,'') like 'Storage uncertain%' then reserved_slot else null end
    where id=p_command_id;
  return jsonb_build_object('status','failed');
end;
$$;

notify pgrst,'reload schema';

create or replace function public.create_enrollment_command(
  p_person_id uuid,
  p_device_id uuid
)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  command_id uuid;
  device_code text;
  active_command public.device_commands;
  student_id uuid;
begin
  if auth.uid() is null or not public.is_administrator() then
    raise exception 'Administrator access is required' using errcode = '42501';
  end if;

  -- Coordinate enrollment creation with delete_student's row lock.
  select p.id into student_id
  from public.people p
  where p.id = p_person_id and p.role = 'student' and p.active
  for key share;
  if student_id is null then
    raise exception 'Active student was not found' using errcode = '23503';
  end if;

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
  from public.people p where p.id = student_id
  returning id into command_id;
  return command_id;
end;
$$;

create or replace function public.delete_student(p_person_id uuid)
returns boolean
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  student public.people;
begin
  if auth.uid() is null or not public.is_administrator() then
    raise exception 'Administrator access is required' using errcode = '42501';
  end if;

  select p.* into student from public.people p
  where p.id = p_person_id for update;
  if student.id is null or student.role <> 'student' then
    raise exception 'Student was not found';
  end if;

  if exists (select 1 from public.fingerprint_mappings fm
             where fm.person_id = p_person_id) or
     student.fingerprint_status = 'enrolled' then
    raise exception 'Remove the student''s fingerprint before deleting this student.';
  end if;

  if exists (select 1 from public.device_commands dc
             where dc.command_type = 'ENROLL_FINGERPRINT'
               and dc.payload ->> 'person_id' = p_person_id::text
               and dc.status in ('pending', 'processing')) then
    raise exception 'Resolve the student''s active fingerprint enrollment before deleting this student.';
  end if;

  -- A retained slot or a completed result can indicate a sensor template even
  -- if an inconsistent/missing mapping row would otherwise let deletion pass.
  if exists (select 1 from public.device_commands dc
             where dc.command_type = 'ENROLL_FINGERPRINT'
               and dc.payload ->> 'person_id' = p_person_id::text
               and (dc.reserved_slot is not null or
                    (dc.status = 'completed' and
                     coalesce(dc.result, '{}'::jsonb) ? 'template_id'))) then
    raise exception 'Remove the student''s fingerprint before deleting this student.';
  end if;

  if exists (select 1 from public.attendance_records ar
             where ar.student_id = p_person_id) or
     exists (select 1 from public.attendance_record_audit ara
             where ara.old_student_id = p_person_id
                or ara.new_student_id = p_person_id) then
    raise exception 'Student has attendance history and cannot be deleted.';
  end if;

  -- Failed/cancelled attempts have no stored template or retained reservation.
  delete from public.device_commands dc
  where dc.command_type = 'ENROLL_FINGERPRINT'
    and dc.payload ->> 'person_id' = p_person_id::text;

  -- Remove the public role link only; leave the Auth account untouched.
  delete from public.user_roles ur where ur.person_id = p_person_id;
  delete from public.people p where p.id = p_person_id;
  return true;
end;
$$;

create or replace function public.delete_teacher(p_person_id uuid)
returns boolean
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  teacher public.people;
begin
  if auth.uid() is null or not public.is_administrator() then
    raise exception 'Administrator access is required' using errcode = '42501';
  end if;

  select p.* into teacher from public.people p
  where p.id = p_person_id for update;
  if teacher.id is null or teacher.role <> 'teacher' then
    raise exception 'Teacher was not found';
  end if;

  if exists (select 1 from public.teacher_classes tc
             where tc.teacher_id = p_person_id) then
    raise exception 'Reassign or remove this teacher from their classes before deleting.';
  end if;

  -- Public role link is removed; the related Supabase Auth account remains.
  delete from public.user_roles ur where ur.person_id = p_person_id;
  delete from public.people p where p.id = p_person_id;
  return true;
end;
$$;

create or replace function public.delete_class(p_class_id uuid)
returns boolean
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  class_record public.classes;
begin
  if auth.uid() is null or not public.is_administrator() then
    raise exception 'Administrator access is required' using errcode = '42501';
  end if;

  select c.* into class_record from public.classes c
  where c.id = p_class_id for update;
  if class_record.id is null then
    raise exception 'Class was not found';
  end if;

  if exists (select 1 from public.people p where p.class_id = p_class_id) or
     exists (select 1 from public.teacher_classes tc where tc.class_id = p_class_id) then
    raise exception 'Move or remove assigned students and teachers before deleting this class.';
  end if;

  if exists (select 1 from public.attendance_records ar
             where ar.class_id = p_class_id) or
     exists (select 1 from public.attendance_record_audit ara
             where ara.old_class_id = p_class_id
                or ara.new_class_id = p_class_id) then
    raise exception 'Class has attendance history and cannot be deleted.';
  end if;

  delete from public.classes c where c.id = p_class_id;
  return true;
end;
$$;

-- All record deletion must pass through the guarded RPCs, even for admins.
revoke delete on table public.people, public.classes from authenticated;

drop policy if exists "administrators manage people" on public.people;
create policy "administrators insert people"
  on public.people for insert to authenticated
  with check (public.is_administrator());
create policy "administrators update people"
  on public.people for update to authenticated
  using (public.is_administrator())
  with check (public.is_administrator());

drop policy if exists "administrators manage classes" on public.classes;
create policy "administrators insert classes"
  on public.classes for insert to authenticated
  with check (public.is_administrator());
create policy "administrators update classes"
  on public.classes for update to authenticated
  using (public.is_administrator())
  with check (public.is_administrator());

revoke all on function public.delete_student(uuid) from public, anon, authenticated;
revoke all on function public.delete_teacher(uuid) from public, anon, authenticated;
revoke all on function public.delete_class(uuid) from public, anon, authenticated;
grant execute on function public.delete_student(uuid) to authenticated;
grant execute on function public.delete_teacher(uuid) to authenticated;
grant execute on function public.delete_class(uuid) to authenticated;

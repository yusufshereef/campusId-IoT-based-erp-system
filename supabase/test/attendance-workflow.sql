-- Run only in the disposable Supabase test project after all migrations.
-- The final ROLLBACK removes every fixture and audit row.

begin;

do $$
declare
  admin_user uuid := gen_random_uuid();
  teacher_user uuid := gen_random_uuid();
  unassigned_teacher_user uuid := gen_random_uuid();
  teacher_person uuid;
  unassigned_teacher_person uuid;
  assigned_class uuid;
  hidden_class uuid;
  active_student uuid;
  inactive_student uuid;
  teacher_record uuid;
  audit_count integer;
  visible_count integer;
  affected_count integer;
begin
  insert into auth.users (id, aud, role, email)
  values
    (admin_user, 'authenticated', 'authenticated',
      'qa-attendance-admin-20261016@example.invalid'),
    (teacher_user, 'authenticated', 'authenticated',
      'qa-attendance-teacher-20261016@example.invalid'),
    (unassigned_teacher_user, 'authenticated', 'authenticated',
      'qa-attendance-unassigned-20261016@example.invalid');

  insert into public.user_roles (user_id, role)
  values (admin_user, 'administrator');

  insert into public.classes (name, section, academic_year)
  values ('QA Attendance Assigned 20261016', 'A', 'isolated')
  returning id into assigned_class;

  insert into public.classes (name, section, academic_year)
  values ('QA Attendance Hidden 20261016', 'B', 'isolated')
  returning id into hidden_class;

  insert into public.people (full_name, role, employee_id)
  values (
    'QA Attendance Teacher 20261016', 'teacher',
    'QA-ATT-TEACHER-20261016'
  )
  returning id into teacher_person;

  insert into public.people (full_name, role, employee_id)
  values (
    'QA Attendance Unassigned Teacher 20261016', 'teacher',
    'QA-ATT-UNASSIGNED-20261016'
  )
  returning id into unassigned_teacher_person;

  insert into public.user_roles (user_id, role, person_id)
  values
    (teacher_user, 'teacher', teacher_person),
    (unassigned_teacher_user, 'teacher', unassigned_teacher_person);

  insert into public.teacher_classes (teacher_id, class_id)
  values (teacher_person, assigned_class);

  insert into public.people (
    full_name, role, roll_number, class_id
  )
  values (
    'QA Active Student 20261016', 'student',
    'QA-ATT-ACTIVE-20261016', assigned_class
  )
  returning id into active_student;

  insert into public.people (
    full_name, role, roll_number, class_id, active
  )
  values (
    'QA Inactive Student 20261016', 'student',
    'QA-ATT-INACTIVE-20261016', assigned_class, false
  )
  returning id into inactive_student;

  set role anon;
  begin
    select count(*) into visible_count from public.attendance_records;
    if visible_count <> 0 then
      raise exception 'anonymous attendance read was allowed';
    end if;
  exception when sqlstate '42501' then
    null;
  end;
  begin
    insert into public.attendance_records (
      class_id, student_id, attendance_date, status, recorded_by_user_id
    )
    values (
      assigned_class, active_student, date '2026-10-16', 'present', admin_user
    );
    raise exception 'anonymous attendance insert was allowed';
  exception when sqlstate '42501' then
    null;
  end;
  reset role;

  set role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', teacher_user::text, 'role', 'authenticated')::text,
    true
  );

  insert into public.attendance_records (
    class_id, student_id, attendance_date, status, recorded_by_user_id,
    client_event_id
  )
  values (
    assigned_class, active_student, date '2026-10-16', 'present', teacher_user,
    gen_random_uuid()
  )
  returning id into teacher_record;

  begin
    insert into public.attendance_records (
      class_id, student_id, attendance_date, status, recorded_by_user_id
    )
    values (
      assigned_class, active_student, date '2026-10-16', 'late', teacher_user
    );
    raise exception 'duplicate attendance was accepted';
  exception when unique_violation then
    null;
  end;

  begin
    insert into public.attendance_records (
      class_id, student_id, attendance_date, status, recorded_by_user_id
    )
    values (
      assigned_class, inactive_student, date '2026-10-17', 'present', teacher_user
    );
    raise exception 'inactive student attendance was accepted';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.attendance_records (
      class_id, student_id, attendance_date, status, recorded_by_user_id
    )
    values (
      hidden_class, active_student, date '2026-10-17', 'present', teacher_user
    );
    raise exception 'wrong-class attendance was accepted';
  exception when sqlstate '42501' or check_violation then
    null;
  end;

  begin
    insert into public.attendance_records (
      class_id, student_id, attendance_date, status, recorded_by_user_id
    )
    values (
      assigned_class, teacher_person, date '2026-10-17', 'present', teacher_user
    );
    raise exception 'non-student attendance was accepted';
  exception when check_violation then
    null;
  end;

  begin
    update public.attendance_records
    set recorded_by_user_id = unassigned_teacher_user
    where id = teacher_record;
    raise exception 'attendance attribution was changed';
  exception when check_violation then
    null;
  end;

  update public.attendance_records
  set status = 'late'
  where id = teacher_record;
  if not exists (
    select 1
    from public.attendance_records
    where id = teacher_record
      and status = 'late'
      and recorded_by_user_id = teacher_user
  ) then
    raise exception 'assigned teacher could not correct attendance';
  end if;

  begin
    insert into public.fingerprint_mappings (
      device_id, slot_id, person_id
    )
    values ('QA-ATT-DEVICE-20261016', 1, active_student);
    raise exception 'teacher fingerprint mapping insert was allowed';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    select count(*) into visible_count from public.fingerprint_mappings;
    if visible_count <> 0 then
      raise exception 'teacher fingerprint mapping read was allowed';
    end if;
  exception when sqlstate '42501' then
    null;
  end;
  reset role;

  set role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', unassigned_teacher_user::text, 'role', 'authenticated'
    )::text,
    true
  );
  select count(*) into visible_count
  from public.attendance_records
  where class_id = assigned_class;
  if visible_count <> 0 then
    raise exception 'unassigned teacher could read attendance';
  end if;
  begin
    insert into public.attendance_records (
      class_id, student_id, attendance_date, status, recorded_by_user_id
    )
    values (
      assigned_class, active_student, date '2026-10-18',
      'present', unassigned_teacher_user
    );
    raise exception 'unassigned teacher attendance insert was allowed';
  exception when sqlstate '42501' then
    null;
  end;
  reset role;

  set role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', admin_user::text, 'role', 'authenticated')::text,
    true
  );
  update public.attendance_records
  set status = 'excused'
  where id = teacher_record;
  if not exists (
    select 1
    from public.attendance_records
    where id = teacher_record
      and status = 'excused'
      and recorded_by_user_id = teacher_user
  ) then
    raise exception 'administrator could not correct attendance';
  end if;
  select count(*) into audit_count
  from public.attendance_record_audit
  where attendance_record_id = teacher_record;
  if audit_count <> 2 then
    raise exception 'expected two attendance audit rows, got %', audit_count;
  end if;
  begin
    insert into public.attendance_records (
      class_id, student_id, attendance_date, status, recorded_by_user_id
    )
    values (
      hidden_class, active_student, date '2026-10-20', 'present', admin_user
    );
    raise exception 'administrator accepted wrong-class attendance';
  exception when check_violation then
    null;
  end;
  update public.people
  set active = false
  where id = active_student;
  select count(*) into visible_count
  from public.attendance_records
  where id = teacher_record;
  if visible_count <> 1 then
    raise exception 'historical attendance was hidden after deactivation';
  end if;
  select count(*) into audit_count
  from public.attendance_record_audit
  where attendance_record_id = teacher_record;
  if audit_count <> 2 then
    raise exception 'attendance audit rows were not preserved';
  end if;
  begin
    insert into public.attendance_records (
      class_id, student_id, attendance_date, status, recorded_by_user_id
    )
    values (
      assigned_class, active_student, date '2026-10-19', 'present', admin_user
    );
    raise exception 'administrator inserted attendance for inactive student';
  exception when check_violation then
    null;
  end;
end;
$$;

rollback;

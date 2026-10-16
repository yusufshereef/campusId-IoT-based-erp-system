-- Exercise the production deletion RPC bodies against temporary copies only.
begin;
set local plpgsql.check_asserts = on;
select set_config('test.is_admin', 'false', true);

create temp table deletion_test_results (test text, passed boolean, detail text);
create temp table people (like public.people including all);
create temp table classes (like public.classes including all);
create temp table teacher_classes (like public.teacher_classes including all);
create temp table fingerprint_mappings (like public.fingerprint_mappings including all);
create temp table device_commands (like public.device_commands including all);
create temp table user_roles (like public.user_roles including all);
create temp table attendance_records (like public.attendance_records including all);
create temp table attendance_record_audit
  (like public.attendance_record_audit including all);

create function pg_temp.test_is_admin()
returns boolean language sql stable
as $$ select coalesce(current_setting('test.is_admin', true), 'false') = 'true' $$;

do $$
declare
  function_row record;
  definition text;
  table_name text;
begin
  for function_row in
    select p.oid, p.proname from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('delete_student', 'delete_teacher', 'delete_class')
  loop
    definition := pg_get_functiondef(function_row.oid);
    definition := replace(definition, 'public.' || function_row.proname,
                          'pg_temp.' || function_row.proname);
    foreach table_name in array array[
      'people', 'classes', 'teacher_classes', 'fingerprint_mappings',
      'device_commands', 'user_roles', 'attendance_records',
      'attendance_record_audit'
    ] loop
      definition := replace(definition, 'public.' || table_name,
                            'pg_temp.' || table_name);
    end loop;
    definition := replace(definition, 'auth.uid()', 'gen_random_uuid()');
    definition := replace(definition, 'public.is_administrator()',
                          'pg_temp.test_is_admin()');
    execute definition;
  end loop;
end;
$$;

do $$
declare
  no_enrollment_student uuid := gen_random_uuid();
  failed_student uuid := gen_random_uuid();
  mapped_student uuid := gen_random_uuid();
  active_student uuid := gen_random_uuid();
  attended_student uuid := gen_random_uuid();
  uncertain_student uuid := gen_random_uuid();
  unassigned_teacher uuid := gen_random_uuid();
  assigned_teacher uuid := gen_random_uuid();
  empty_class uuid := gen_random_uuid();
  student_class uuid := gen_random_uuid();
  teacher_class uuid := gen_random_uuid();
  attended_class uuid := gen_random_uuid();
  failure_message text;
  linked_user uuid := gen_random_uuid();
begin
  assert not has_table_privilege('authenticated', 'public.people', 'delete'),
    'Authenticated users can bypass the guarded student delete RPC';
  assert not has_table_privilege('authenticated', 'public.classes', 'delete'),
    'Authenticated users can bypass the guarded class delete RPC';
  assert not has_function_privilege('anon', 'public.delete_student(uuid)', 'execute'),
    'Anonymous users can execute student deletion';
  assert has_function_privilege('authenticated', 'public.delete_student(uuid)', 'execute'),
    'Authenticated administrators cannot call the student delete RPC';
  insert into deletion_test_results values ('direct delete privileges are blocked', true, null);

  insert into pg_temp.classes (id, name, section, academic_year)
  values (empty_class, 'Empty', 'A', '2026-27'),
         (student_class, 'Student use', 'A', '2026-27'),
         (teacher_class, 'Teacher use', 'A', '2026-27'),
         (attended_class, 'Attendance history', 'A', '2026-27');

  insert into pg_temp.people
    (id, full_name, role, roll_number, employee_id, class_id, fingerprint_status)
  values (no_enrollment_student, 'No enrollment', 'student', 'S-1', null,
          student_class, 'not_enrolled'),
         (failed_student, 'Failed attempt', 'student', 'S-2', null,
          student_class, 'failed'),
         (mapped_student, 'Mapped student', 'student', 'S-3', null,
          student_class, 'enrolled'),
         (active_student, 'Active command', 'student', 'S-4', null,
          student_class, 'pending'),
         (attended_student, 'Attendance student', 'student', 'S-5', null,
          student_class, 'not_enrolled'),
         (uncertain_student, 'Uncertain template', 'student', 'S-6', null,
          student_class, 'failed'),
         (unassigned_teacher, 'Unassigned', 'teacher', null, 'T-1', null,
          'not_enrolled'),
         (assigned_teacher, 'Assigned', 'teacher', null, 'T-2', null,
          'not_enrolled');

  insert into pg_temp.user_roles (user_id, role, person_id)
  values (linked_user, 'teacher', unassigned_teacher);
  insert into pg_temp.fingerprint_mappings (device_id, slot_id, person_id)
  values ('terminal', 1, mapped_student);
  insert into pg_temp.teacher_classes (teacher_id, class_id)
  values (assigned_teacher, teacher_class);
  insert into pg_temp.device_commands (device_id, command_type, payload, status)
  values (gen_random_uuid(), 'ENROLL_FINGERPRINT',
          jsonb_build_object('person_id', failed_student), 'failed'),
         (gen_random_uuid(), 'ENROLL_FINGERPRINT',
          jsonb_build_object('person_id', active_student), 'processing'),
         (gen_random_uuid(), 'ENROLL_FINGERPRINT',
          jsonb_build_object('person_id', uncertain_student), 'failed');
  update pg_temp.device_commands set reserved_slot = 2
  where payload ->> 'person_id' = uncertain_student::text;
  insert into pg_temp.attendance_records
    (class_id, student_id, attendance_date, status, recorded_by_user_id)
  values (attended_class, attended_student, current_date, 'present', linked_user);
  insert into pg_temp.attendance_record_audit
    (attendance_record_id, changed_by_user_id, old_status, new_status,
     old_class_id, new_class_id, old_student_id, new_student_id)
  values (gen_random_uuid(), linked_user, 'absent', 'present', attended_class,
          attended_class, attended_student, attended_student);
  delete from pg_temp.attendance_records;

  -- RPC guards reject every delete for non-administrators.
  begin
    perform pg_temp.delete_student(no_enrollment_student);
    raise exception 'Non-admin student delete unexpectedly succeeded';
  exception when insufficient_privilege then
    insert into deletion_test_results values ('student delete is admin-only', true, null);
  end;
  begin
    perform pg_temp.delete_teacher(unassigned_teacher);
    raise exception 'Non-admin teacher delete unexpectedly succeeded';
  exception when insufficient_privilege then
    insert into deletion_test_results values ('teacher delete is admin-only', true, null);
  end;
  begin
    perform pg_temp.delete_class(empty_class);
    raise exception 'Non-admin class delete unexpectedly succeeded';
  exception when insufficient_privilege then
    insert into deletion_test_results values ('class delete is admin-only', true, null);
  end;

  perform set_config('test.is_admin', 'true', true);
  assert pg_temp.delete_student(no_enrollment_student), 'Not-enrolled student delete failed';
  assert not exists (select 1 from pg_temp.people where id = no_enrollment_student),
    'Not-enrolled student remains';
  insert into deletion_test_results values ('not-enrolled student delete', true, null);

  assert pg_temp.delete_student(failed_student), 'Failed-enrollment student delete failed';
  assert not exists (select 1 from pg_temp.device_commands
                     where payload ->> 'person_id' = failed_student::text),
    'Failed enrollment history was not cleaned';
  insert into deletion_test_results values ('failed enrollment does not block delete', true, null);

  begin
    perform pg_temp.delete_student(mapped_student);
    raise exception 'Mapped student delete unexpectedly succeeded';
  exception when raise_exception then
    get stacked diagnostics failure_message = message_text;
    assert failure_message = 'Remove the student''s fingerprint before deleting this student.',
      'Mapped student returned a wrong blocking reason';
    insert into deletion_test_results values ('fingerprint mapping blocks student delete', true, null);
  end;
  begin
    perform pg_temp.delete_student(active_student);
    raise exception 'Active command student delete unexpectedly succeeded';
  exception when raise_exception then
    get stacked diagnostics failure_message = message_text;
    assert failure_message like 'Resolve the student%active fingerprint enrollment%';
    insert into deletion_test_results values ('active command blocks student delete', true, null);
  end;
  begin
    perform pg_temp.delete_student(uncertain_student);
    raise exception 'Uncertain stored template delete unexpectedly succeeded';
  exception when raise_exception then
    get stacked diagnostics failure_message = message_text;
    assert failure_message = 'Remove the student''s fingerprint before deleting this student.';
    insert into deletion_test_results values ('uncertain slot blocks student delete', true, null);
  end;
  begin
    perform pg_temp.delete_student(attended_student);
    raise exception 'Student with attendance delete unexpectedly succeeded';
  exception when raise_exception then
    get stacked diagnostics failure_message = message_text;
    assert failure_message = 'Student has attendance history and cannot be deleted.';
    insert into deletion_test_results values ('attendance history blocks student delete', true, null);
  end;

  assert pg_temp.delete_teacher(unassigned_teacher), 'Unassigned teacher delete failed';
  assert not exists (select 1 from pg_temp.user_roles where person_id = unassigned_teacher),
    'Teacher role link was not removed';
  insert into deletion_test_results values ('unassigned teacher delete unlinks role', true, null);
  begin
    perform pg_temp.delete_teacher(assigned_teacher);
    raise exception 'Assigned teacher delete unexpectedly succeeded';
  exception when raise_exception then
    get stacked diagnostics failure_message = message_text;
    assert failure_message = 'Reassign or remove this teacher from their classes before deleting.';
    insert into deletion_test_results values ('class assignment blocks teacher delete', true, null);
  end;

  assert pg_temp.delete_class(empty_class), 'Empty class delete failed';
  insert into deletion_test_results values ('empty class delete', true, null);
  begin
    perform pg_temp.delete_class(student_class);
    raise exception 'Class with student unexpectedly deleted';
  exception when raise_exception then
    get stacked diagnostics failure_message = message_text;
    assert failure_message = 'Move or remove assigned students and teachers before deleting this class.';
    insert into deletion_test_results values ('student assignment blocks class delete', true, null);
  end;
  begin
    perform pg_temp.delete_class(teacher_class);
    raise exception 'Class with teacher unexpectedly deleted';
  exception when raise_exception then
    get stacked diagnostics failure_message = message_text;
    assert failure_message = 'Move or remove assigned students and teachers before deleting this class.';
    insert into deletion_test_results values ('teacher assignment blocks class delete', true, null);
  end;
  begin
    perform pg_temp.delete_class(attended_class);
    raise exception 'Class with attendance unexpectedly deleted';
  exception when raise_exception then
    get stacked diagnostics failure_message = message_text;
    assert failure_message = 'Class has attendance history and cannot be deleted.';
    insert into deletion_test_results values ('attendance history blocks class delete', true, null);
  end;
end;
$$;

select * from deletion_test_results order by test;
rollback;

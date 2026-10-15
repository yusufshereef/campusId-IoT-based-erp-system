-- Run only in a disposable Supabase test project after all migrations.
-- This test creates temporary Auth users and records inside one transaction.
-- The final rollback removes every fixture.

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
  visible_count integer;
  affected_count integer;
begin
  insert into auth.users (id, aud, role, email)
  values
    (admin_user, 'authenticated', 'authenticated',
      'qa-admin-20261015@example.invalid'),
    (teacher_user, 'authenticated', 'authenticated',
      'qa-teacher-20261015@example.invalid'),
    (unassigned_teacher_user, 'authenticated', 'authenticated',
      'qa-unassigned-teacher-20261015@example.invalid');

  insert into public.user_roles (user_id, role)
  values (admin_user, 'administrator');

  insert into public.classes (name, section, academic_year)
  values ('QA Security Assigned 20261015', 'A', 'isolated')
  returning id into assigned_class;

  insert into public.classes (name, section, academic_year)
  values ('QA Security Hidden 20261015', 'B', 'isolated')
  returning id into hidden_class;

  insert into public.people (
    full_name, role, employee_id, fingerprint_status
  )
  values (
    'QA Security Teacher 20261015', 'teacher',
    'QA-SEC-TEACHER-20261015', 'not_enrolled'
  )
  returning id into teacher_person;

  insert into public.people (
    full_name, role, employee_id, fingerprint_status
  )
  values (
    'QA Security Unassigned Teacher 20261015', 'teacher',
    'QA-SEC-UNASSIGNED-20261015', 'not_enrolled'
  )
  returning id into unassigned_teacher_person;

  insert into public.user_roles (user_id, role, person_id)
  values
    (teacher_user, 'teacher', teacher_person),
    (unassigned_teacher_user, 'teacher', unassigned_teacher_person);

  insert into public.teacher_classes (teacher_id, class_id)
  values (teacher_person, assigned_class);

  insert into public.people (
    full_name, role, roll_number, class_id, fingerprint_status
  )
  values (
    'QA Security Student 20261015', 'student',
    'QA-SEC-STUDENT-20261015', assigned_class, 'not_enrolled'
  );

  if has_schema_privilege('anon', 'public', 'CREATE') then
    raise exception 'anonymous role has CREATE privilege on public schema';
  end if;
  if has_schema_privilege('authenticated', 'public', 'CREATE') then
    raise exception 'authenticated role has CREATE privilege on public schema';
  end if;

  set role anon;
  begin
    select count(*) into visible_count from public.classes;
    if visible_count <> 0 then
      raise exception 'anonymous class read was allowed';
    end if;
  exception when sqlstate '42501' then
    null;
  end;
  begin
    insert into public.classes (name, section, academic_year)
    values ('QA Security Anonymous 20261015', 'X', 'isolated');
    raise exception 'anonymous class insert was allowed';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    perform public.register_teacher_with_classes(
      'QA Anonymous Teacher',
      'QA-SEC-ANONYMOUS-20261015',
      array[assigned_class]::uuid[]
    );
    raise exception 'anonymous teacher RPC call was allowed';
  exception when sqlstate '42501' then
    null;
  end;
  reset role;

  set role authenticated;
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', unassigned_teacher_user::text,
      'role', 'authenticated'
    )::text,
    true
  );
  select count(*) into visible_count
  from public.classes
  where id = assigned_class;
  if visible_count <> 0 then
    raise exception 'unassigned teacher could read assigned class';
  end if;
  begin
    insert into public.people (
      full_name, role, roll_number, class_id, fingerprint_status
    )
    values (
      'QA Security Unauthorized Student', 'student',
      'QA-SEC-UNAUTHORIZED-20261015', assigned_class, 'not_enrolled'
    );
    raise exception 'unassigned teacher people insert was allowed';
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

  select count(*) into visible_count
  from public.classes
  where id = assigned_class;
  if visible_count <> 1 then
    raise exception 'teacher could not read assigned class';
  end if;

  select count(*) into visible_count
  from public.classes
  where id = hidden_class;
  if visible_count <> 0 then
    raise exception 'teacher could read unassigned class';
  end if;

  begin
    insert into public.classes (name, section, academic_year)
    values ('QA Security Unauthorized 20261015', 'X', 'isolated');
    raise exception 'teacher class insert was allowed';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    update public.classes
    set academic_year = 'unauthorized'
    where id = assigned_class;
    get diagnostics affected_count = row_count;
    if affected_count <> 0 then
      raise exception 'teacher class update was allowed';
    end if;
  exception when sqlstate '42501' then
    null;
  end;

  begin
    delete from public.classes
    where id = assigned_class;
    get diagnostics affected_count = row_count;
    if affected_count <> 0 then
      raise exception 'teacher class delete was allowed';
    end if;
  exception when sqlstate '42501' then
    null;
  end;

  begin
    update public.people
    set active = not active
    where id = teacher_person;
    get diagnostics affected_count = row_count;
    if affected_count <> 0 then
      raise exception 'teacher people update was allowed';
    end if;
  exception when sqlstate '42501' then
    null;
  end;

  begin
    delete from public.people
    where id = teacher_person;
    get diagnostics affected_count = row_count;
    if affected_count <> 0 then
      raise exception 'teacher people delete was allowed';
    end if;
  exception when sqlstate '42501' then
    null;
  end;

  begin
    insert into public.teacher_classes (teacher_id, class_id)
    values (teacher_person, hidden_class);
    raise exception 'teacher assignment insert was allowed';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    update public.teacher_classes
    set class_id = hidden_class
    where teacher_id = teacher_person
      and class_id = assigned_class;
    get diagnostics affected_count = row_count;
    if affected_count <> 0 then
      raise exception 'teacher assignment update was allowed';
    end if;
  exception when sqlstate '42501' then
    null;
  end;

  begin
    delete from public.teacher_classes
    where teacher_id = teacher_person
      and class_id = assigned_class;
    get diagnostics affected_count = row_count;
    if affected_count <> 0 then
      raise exception 'teacher assignment delete was allowed';
    end if;
  exception when sqlstate '42501' then
    null;
  end;

  begin
    perform public.register_teacher_with_classes(
      'QA Unauthorized Teacher',
      'QA-SEC-UNAUTHORIZED-20261015',
      array[assigned_class]::uuid[]
    );
    raise exception 'teacher RPC call was allowed';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    insert into public.fingerprint_mappings (
      device_id, slot_id, person_id
    )
    values ('QA-SEC-UNAUTHORIZED-DEVICE-20261015', 1, teacher_person);
    raise exception 'teacher fingerprint mapping insert was allowed';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    update public.fingerprint_mappings
    set status = 'inactive'
    where device_id = 'QA-SEC-UNAUTHORIZED-DEVICE-20261015';
    get diagnostics affected_count = row_count;
    if affected_count <> 0 then
      raise exception 'teacher fingerprint mapping update was allowed';
    end if;
  exception when sqlstate '42501' then
    null;
  end;

  begin
    delete from public.fingerprint_mappings
    where device_id = 'QA-SEC-UNAUTHORIZED-DEVICE-20261015';
    get diagnostics affected_count = row_count;
    if affected_count <> 0 then
      raise exception 'teacher fingerprint mapping delete was allowed';
    end if;
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
    json_build_object('sub', admin_user::text, 'role', 'authenticated')::text,
    true
  );
  insert into public.classes (name, section, academic_year)
  values ('QA Security Administrator 20261015', 'C', 'isolated');
  select count(*) into visible_count
  from public.classes
  where id in (assigned_class, hidden_class);
  if visible_count <> 2 then
    raise exception 'administrator could not read both classes';
  end if;
  perform public.register_teacher_with_classes(
    'QA Security Administrator Teacher',
    'QA-SEC-ADMIN-TEACHER-20261015',
    array[assigned_class]::uuid[]
  );
  reset role;
end;
$$;

rollback;

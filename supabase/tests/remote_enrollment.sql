-- Transactional regression tests. All fixtures and cloned functions are
-- temporary; public application rows are never modified.
begin;
set local plpgsql.check_asserts = on;
create temp table enrollment_test_results (test text, passed boolean, detail text);
create temp table old_mapping_probe (
  device_id text, slot_id integer, person_id uuid,
  unique (device_id, person_id)
);
do $$
declare
  person_id uuid := gen_random_uuid();
begin
  begin
    -- Exact ambiguous conflict target from the original completion function.
    insert into old_mapping_probe (device_id, slot_id, person_id)
    values ('probe', 2, person_id)
    on conflict (device_id, person_id) do update set slot_id = excluded.slot_id;
    raise exception 'Expected original completion SQL to fail';
  exception when ambiguous_column then
    insert into enrollment_test_results values
      ('original success-path regression', true, SQLSTATE || ': ' || SQLERRM);
  end;
end;
$$;

create temp table devices (like public.devices including all);
create temp table people (like public.people including all);
create temp table device_commands (like public.device_commands including all);
create temp table fingerprint_mappings (like public.fingerprint_mappings including all);

do $$
declare
  function_row record;
  definition text;
  table_name text;
begin
  for function_row in
    select p.oid, p.proname from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'create_enrollment_command', 'claim_device_command',
      'complete_device_command', 'get_fingerprint_statuses')
  loop
    definition := pg_get_functiondef(function_row.oid);
    definition := replace(definition, 'public.' || function_row.proname,
                          'pg_temp.' || function_row.proname);
    foreach table_name in array array['devices', 'people', 'device_commands', 'fingerprint_mappings']
    loop
      definition := replace(definition, 'public.' || table_name, 'pg_temp.' || table_name);
    end loop;
    -- Only the temporary copies bypass auth to exercise business logic without
    -- creating users or changing production roles/RLS.
    definition := replace(definition, 'auth.uid()', 'gen_random_uuid()');
    definition := replace(definition, 'public.is_administrator()', 'true');
    execute definition;
  end loop;
end;
$$;

do $$
declare
  test_device uuid := gen_random_uuid();
  student_one uuid := gen_random_uuid();
  student_two uuid := gen_random_uuid();
  student_three uuid := gen_random_uuid();
  command_one uuid;
  command_two uuid;
  command_three uuid;
  answer jsonb;
begin
  insert into pg_temp.devices (id, device_code, display_name, secret_hash, last_seen_at)
  values (test_device, 'enrollment-test', 'Temporary test', repeat('0', 64), now());
  insert into pg_temp.people (id, full_name, role, roll_number, class_id)
  values (student_one, 'Test One', 'student', 'test-1', gen_random_uuid()),
         (student_two, 'Test Two', 'student', 'test-2', gen_random_uuid()),
         (student_three, 'Test Three', 'student', 'test-3', gen_random_uuid());

  command_one := pg_temp.create_enrollment_command(student_one, test_device);
  assert pg_temp.create_enrollment_command(student_one, test_device) = command_one,
    'Duplicate create must return the same command';
  assert (select count(*) = 1 from pg_temp.device_commands), 'Duplicate command inserted';
  answer := pg_temp.claim_device_command(test_device);
  assert answer ->> 'id' = command_one::text, 'Wrong command claimed';
  assert pg_temp.claim_device_command(test_device) is null, 'Processing command re-claimed';
  assert (select enrollment_status = 'in_progress' and command_id = command_one
          from pg_temp.get_fingerprint_statuses() where person_id = student_one),
    'Reload did not rediscover active command';
  insert into enrollment_test_results values ('duplicate create / claim / reload', true, null);

  answer := pg_temp.complete_device_command(command_one, test_device, true, 2);
  assert answer ->> 'status' = 'completed', 'Success completion failed';
  answer := pg_temp.complete_device_command(command_one, test_device, true, 2);
  assert answer ->> 'status' = 'completed', 'Identical ACK retry failed';
  assert (select count(*) = 1 from pg_temp.fingerprint_mappings), 'Duplicate mapping';
  answer := pg_temp.complete_device_command(command_one, test_device, true, 3);
  assert answer ->> 'status' = 'rejected', 'Conflicting slot accepted';
  answer := pg_temp.complete_device_command(command_one, test_device, false);
  assert answer ->> 'status' = 'rejected', 'Conflicting result accepted';
  assert (select enrollment_status = 'enrolled' and slot_id = 2
          from pg_temp.get_fingerprint_statuses() where person_id = student_one),
    'Status did not become enrolled';
  insert into enrollment_test_results values ('success / repeated ACK / conflicting ACK', true, null);

  command_two := pg_temp.create_enrollment_command(student_two, test_device);
  perform pg_temp.claim_device_command(test_device);
  answer := pg_temp.complete_device_command(command_two, test_device, false, null, 'Finger mismatch');
  assert answer ->> 'status' = 'failed', 'Failure completion failed';
  assert not exists (select 1 from pg_temp.fingerprint_mappings where person_id = student_two),
    'Failure created mapping';
  assert (select enrollment_status = 'failed' and error_message = 'Finger mismatch'
          from pg_temp.get_fingerprint_statuses() where person_id = student_two),
    'Status did not become failed';
  insert into enrollment_test_results values ('failure completion / failed status', true, null);

  command_two := pg_temp.create_enrollment_command(student_two, test_device);
  perform pg_temp.claim_device_command(test_device);
  update pg_temp.device_commands set claimed_at = now() - interval '11 minutes'
  where id = command_two;
  perform pg_temp.get_fingerprint_statuses();
  assert (select status = 'failed' from pg_temp.device_commands where id = command_two),
    'Stale command remained processing';
  answer := pg_temp.complete_device_command(command_two, test_device, true, 3);
  assert answer ->> 'status' = 'completed', 'Late ACK for unchanged command failed';
  insert into enrollment_test_results values ('stale recovery / same-command late ACK', true, null);

  command_three := pg_temp.create_enrollment_command(student_three, test_device);
  answer := pg_temp.claim_device_command(test_device);
  assert answer -> 'reserved_slots' = '[2,3]'::jsonb, 'Mapped slots not reserved';
  answer := pg_temp.complete_device_command(command_three, test_device, true, 2);
  assert answer ->> 'status' = 'failed', 'Conflicting mapping accepted';
  assert (select count(*) = 2 from pg_temp.fingerprint_mappings), 'Mapping conflict changed rows';
  insert into enrollment_test_results values ('reserved slots / mapping collision', true, null);
end;
$$;
select * from enrollment_test_results order by test;
rollback;

-- Exercise entity deletion and cleanup allocation against temporary copies.
begin;
set local plpgsql.check_asserts = on;
create temp table lifecycle_results(test text, passed boolean, detail text);
create temp table devices (like public.devices including all);
create temp table people (like public.people including all);
create temp table classes (like public.classes including all);
create temp table teacher_classes (like public.teacher_classes including all);
create temp table fingerprint_mappings (like public.fingerprint_mappings including all);
create temp table device_commands (like public.device_commands including all);
create temp table user_roles (like public.user_roles including all);
create temp table attendance_records (like public.attendance_records including all);
create temp table attendance_record_audit (like public.attendance_record_audit including all);

create function pg_temp.test_is_admin()
returns boolean language sql stable as $$ select true $$;

do $$
declare fn record; definition text; table_name text;
begin
  for fn in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in
      ('delete_student','delete_teacher','delete_class','create_enrollment_command',
       'claim_device_command','complete_device_command')
  loop
    definition:=pg_get_functiondef(fn.oid);
    definition:=replace(definition,'public.'||fn.proname,'pg_temp.'||fn.proname);
    foreach table_name in array array['devices','people','classes','teacher_classes',
      'fingerprint_mappings','device_commands','user_roles','attendance_records',
      'attendance_record_audit'] loop
      definition:=replace(definition,'public.'||table_name,'pg_temp.'||table_name);
    end loop;
    definition:=replace(definition,'auth.uid()','gen_random_uuid()');
    definition:=replace(definition,'public.is_administrator()','pg_temp.test_is_admin()');
    execute definition;
  end loop;
end $$;

do $$
declare
  v_device_id uuid:=gen_random_uuid();
  room_id uuid:=gen_random_uuid();
  teacher_room_id uuid:=gen_random_uuid();
  v_student_id uuid:=gen_random_uuid();
  no_fingerprint_student uuid:=gen_random_uuid();
  active_enrollment_student uuid:=gen_random_uuid();
  other_student uuid:=gen_random_uuid();
  reuse_student uuid:=gen_random_uuid();
  v_teacher_id uuid:=gen_random_uuid();
  cleanup_id uuid;
  command_id uuid;
  claimed jsonb;
begin
  insert into pg_temp.devices(id,device_code,display_name,secret_hash,last_seen_at,sensor_ready)
    values(v_device_id,'offline-terminal','Offline terminal',repeat('a',64),now()-interval '5 minutes',false);
  insert into pg_temp.classes(id,name,section) values
    (room_id,'Lifecycle','A'),(teacher_room_id,'Teacher only','A');
  insert into pg_temp.people(id,full_name,role,roll_number,class_id,fingerprint_status)
    values(v_student_id,'Private Name','student','ROLL-PRIVATE',room_id,'enrolled'),
      (no_fingerprint_student,'No Fingerprint','student','ROLL-NONE',room_id,'not_enrolled'),
      (active_enrollment_student,'In Flight','student','ROLL-FLIGHT',room_id,'pending'),
      (other_student,'New Student','student','ROLL-NEW',room_id,'not_enrolled');
  insert into pg_temp.fingerprint_mappings(device_id,slot_id,person_id)
    values('offline-terminal',2,v_student_id),('offline-terminal',1,gen_random_uuid());
  assert pg_temp.delete_student(no_fingerprint_student),
    'Offline delete without a fingerprint failed';
  assert not exists(select 1 from pg_temp.people where id=no_fingerprint_student),
    'Student without a fingerprint was not deleted';
  insert into pg_temp.lifecycle_results values('student without fingerprint deletes offline',true,null);

  assert pg_temp.delete_student(v_student_id),
    'Student deletion depended on terminal health';
  assert not exists(select 1 from pg_temp.people where id=v_student_id),
    'Student ERP row was not deleted synchronously';
  assert not exists(select 1 from pg_temp.fingerprint_mappings fm where fm.person_id=v_student_id),
    'Student mapping was retained after delete';
  assert (select count(*)=1 from pg_temp.device_commands dc where dc.device_id=v_device_id
    and command_type='DELETE_FINGERPRINT' and reserved_slot=2
    and payload=jsonb_build_object('cleanup_only',true,'slot_id',2)
    and status='pending'), 'Offline cleanup tombstone was not created anonymously';
  assert not exists(select 1 from pg_temp.device_commands
    where payload::text like '%Private Name%' or payload::text like '%ROLL-PRIVATE%'
       or payload->>'person_id'=v_student_id::text),
    'Deleted student identifiers remain in command payloads';
  assert pg_temp.delete_student(active_enrollment_student),
    'Deleting a student with claimed enrollment failed';
  insert into pg_temp.lifecycle_results values('offline student delete is synchronous and anonymous',true,null);

  update pg_temp.devices set last_seen_at=now(),sensor_ready=true where id=v_device_id;
  select id into cleanup_id from pg_temp.device_commands where command_type='DELETE_FINGERPRINT'
    and reserved_slot=2 and payload->>'cleanup_only'='true';
  claimed:=pg_temp.claim_device_command(v_device_id,4);
  command_id:=(claimed->>'id')::uuid;
  assert command_id=cleanup_id,
    'Cleanup tombstone was not claimable without a mapping';
  command_id:=pg_temp.create_enrollment_command(other_student,v_device_id);
  claimed:=pg_temp.claim_device_command(v_device_id,4);
  assert (claimed->>'reserved_slot')::integer=3,
    'Allocator reused the pending-delete slot instead of choosing another free slot';
  assert (pg_temp.complete_device_command(command_id,v_device_id,true,3,null)->>'status')='completed',
    'Enrollment in an unrelated free slot did not complete';
  insert into pg_temp.lifecycle_results values('allocator skips cleanup slot',true,null);

  update pg_temp.device_commands set claimed_at=now()-interval '3 minutes' where id=cleanup_id;
  claimed:=pg_temp.claim_device_command(v_device_id,4);
  assert claimed->>'id'=cleanup_id::text and (claimed->>'reserved_slot')::integer=2,
    'Reboot recovery did not re-offer the same uncertain cleanup slot';

  assert (pg_temp.complete_device_command(cleanup_id,v_device_id,false,2,'Sensor error')->>'status')='failed',
    'Cleanup failure was not retained';
  assert (select reserved_slot=2 and next_retry_at is not null
    from pg_temp.device_commands where id=cleanup_id),
    'Uncertain cleanup did not keep its slot blocked';
  update pg_temp.device_commands set next_retry_at=now()-interval '1 second' where id=cleanup_id;
  claimed:=pg_temp.claim_device_command(v_device_id,4);
  assert claimed->>'id'=cleanup_id::text and (claimed->>'reserved_slot')::integer=2,
    'Cleanup retry changed the target slot';
  assert (pg_temp.complete_device_command(cleanup_id,v_device_id,true,2,null)->>'status')='completed',
    'Cleanup success did not release its slot';
  assert (select reserved_slot is null from pg_temp.device_commands where id=cleanup_id),
    'Confirmed cleanup slot was not released';
  insert into pg_temp.lifecycle_results values('ACK failure retries exact slot and releases only on success',true,null);

  select id into cleanup_id from pg_temp.device_commands where command_type='DELETE_FINGERPRINT'
    and reserved_slot=4 and payload->>'cleanup_only'='true';
  claimed:=pg_temp.claim_device_command(v_device_id,4);
  assert claimed->>'id'=cleanup_id::text and (claimed->>'reserved_slot')::integer=4,
    'Retired in-flight enrollment cleanup was not queued';
  assert (pg_temp.complete_device_command(cleanup_id,v_device_id,true,4,null)->>'status')='completed',
    'Retired enrollment cleanup did not complete';
  insert into pg_temp.people(id,full_name,role,roll_number,class_id,fingerprint_status)
    values(reuse_student,'Reuse','student','ROLL-REUSE',room_id,'not_enrolled');
  command_id:=pg_temp.create_enrollment_command(reuse_student,v_device_id);
  claimed:=pg_temp.claim_device_command(v_device_id,4);
  assert (claimed->>'reserved_slot')::integer=2,
    'Confirmed cleanup slot did not become reusable';
  assert (pg_temp.complete_device_command(command_id,v_device_id,true,2,null)->>'status')='completed',
    'Enrollment into confirmed-free slot failed';
  insert into pg_temp.lifecycle_results values('confirmed cleanup slot is reusable',true,null);

  insert into pg_temp.device_commands(device_id,command_type,payload,status,reserved_slot)
    values(v_device_id,'ENROLL_FINGERPRINT',jsonb_build_object(
      'person_id',active_enrollment_student,'display_name','In Flight'),
      'processing',4);
  assert pg_temp.delete_student(active_enrollment_student),
    'Deleting a student with claimed enrollment failed';
  assert (select payload->>'retired'='true' and payload->>'slot_id'='4'
      and reserved_slot is null from pg_temp.device_commands
    where command_type='ENROLL_FINGERPRINT' and payload->>'slot_id'='4'),
    'Claimed enrollment retained deleted student identity';
  select id into cleanup_id from pg_temp.device_commands where command_type='DELETE_FINGERPRINT'
    and reserved_slot=4 and payload->>'cleanup_only'='true';
  claimed:=pg_temp.claim_device_command(v_device_id,4);
  assert claimed->>'id'=cleanup_id::text and (claimed->>'reserved_slot')::integer=4,
    'Retired in-flight enrollment cleanup was not queued';
  assert (pg_temp.complete_device_command(cleanup_id,v_device_id,true,4,null)->>'status')='completed',
    'Retired enrollment cleanup did not complete';

  insert into pg_temp.people(id,full_name,role,employee_id)
    values(v_teacher_id,'Teacher','teacher','T-1');
  insert into pg_temp.teacher_classes(teacher_id,class_id) values(v_teacher_id,teacher_room_id);
  begin
    perform pg_temp.delete_class(teacher_room_id);
    raise exception 'Class with teacher mapping unexpectedly deleted';
  exception when raise_exception then
    if sqlerrm='Class with teacher mapping unexpectedly deleted' then raise; end if;
  end;
  assert pg_temp.delete_teacher(v_teacher_id), 'Teacher deletion failed';
  assert not exists(select 1 from pg_temp.teacher_classes tc where tc.teacher_id=v_teacher_id),
    'Teacher-class mappings were retained';
  assert exists(select 1 from pg_temp.classes where id=teacher_room_id),
    'Teacher deletion removed its class';
  assert pg_temp.delete_class(teacher_room_id),
    'Class retained after teacher delete could not be deleted';
  insert into pg_temp.lifecycle_results values('teacher delete clears links and preserves class',true,null);

  begin
    perform pg_temp.delete_class(room_id);
    raise exception 'Class with student records unexpectedly deleted';
  exception when raise_exception then
    if sqlerrm='Class with student records unexpectedly deleted' then raise; end if;
  end;
  assert pg_temp.delete_student(other_student), 'Offline mapped student deletion failed';
  assert pg_temp.delete_student(reuse_student), 'Reused-slot student delete failed';
  assert pg_temp.delete_class(room_id), 'Unassigned class deletion failed';
  insert into pg_temp.lifecycle_results values('mapped class blocked and empty class deleted',true,null);
end $$;

select * from pg_temp.lifecycle_results order by test;
rollback;

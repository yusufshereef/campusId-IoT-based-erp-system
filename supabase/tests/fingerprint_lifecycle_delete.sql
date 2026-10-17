-- Exercise the destructive workflow against temporary table/function copies only.
begin;
set local plpgsql.check_asserts = on;
create temp table lifecycle_results(test text, passed boolean, detail text);
create temp table devices (like public.devices including all);
create temp table people (like public.people including all);
create temp table device_commands (like public.device_commands including all);
create temp table fingerprint_mappings (like public.fingerprint_mappings including all);
create temp table user_roles (like public.user_roles including all);
create temp table attendance_records (like public.attendance_records including all);
create temp table attendance_record_audit (like public.attendance_record_audit including all);

do $$
declare r record; definition text; table_name text;
begin
  for r in select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in (
      'create_fingerprint_delete_command','claim_device_command',
      'complete_device_command','get_fingerprint_statuses')
  loop
    select pg_get_functiondef(p.oid) into definition from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=r.proname
      order by p.oid desc limit 1;
    definition := replace(definition,'public.'||r.proname,'pg_temp.'||r.proname);
    foreach table_name in array array['devices','people','device_commands','fingerprint_mappings',
      'user_roles','attendance_records','attendance_record_audit'] loop
      definition := replace(definition,'public.'||table_name,'pg_temp.'||table_name);
    end loop;
    definition := replace(definition,'auth.uid()','gen_random_uuid()');
    definition := replace(definition,'public.is_administrator()','true');
    execute definition;
  end loop;
end $$;

do $$
declare
  d uuid:=gen_random_uuid(); d2 uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); c uuid; answer jsonb;
  failed_s uuid:=gen_random_uuid(); failed_c uuid;
begin
  insert into pg_temp.devices(id,device_code,display_name,secret_hash,last_seen_at,sensor_ready)
    values(d,'lifecycle-test','Temporary terminal',repeat('0',64),now(),true),
          (d2,'lifecycle-failure','Temporary terminal 2',repeat('1',64),now(),true);
  insert into pg_temp.people(id,full_name,role,roll_number,class_id)
    values(s,'Lifecycle student','student','life-1',gen_random_uuid()),
          (failed_s,'Failure student','student','life-2',gen_random_uuid());
  insert into pg_temp.fingerprint_mappings(device_id,slot_id,person_id)
    values('lifecycle-test',3,s),('lifecycle-failure',4,failed_s);

  c:=pg_temp.create_fingerprint_delete_command(s,'reenroll');
  answer:=pg_temp.claim_device_command(d,64);
  assert answer->>'id'=c::text and (answer->>'reserved_slot')::integer=3,
    'Delete did not bind to the authoritative slot';
  answer:=pg_temp.complete_device_command(c,d,true,3,null);
  assert answer->>'status'='completed','Physical success was not acknowledged';
  assert not exists(select 1 from pg_temp.fingerprint_mappings where person_id=s),
    'Successful deletion retained the mapping';
  assert (select count(*)=1 from pg_temp.device_commands where command_type='ENROLL_FINGERPRINT'
    and payload->>'person_id'=s::text),'Re-enrollment was not queued exactly once';
  answer:=pg_temp.complete_device_command(c,d,true,3,null);
  assert answer->>'status'='completed','Duplicate success ACK was not idempotent';
  assert (select count(*)=1 from pg_temp.device_commands where command_type='ENROLL_FINGERPRINT'
    and payload->>'person_id'=s::text),'Duplicate ACK queued another enrollment';
  insert into pg_temp.lifecycle_results values('delete success and re-enroll ordering',true,null);

  failed_c:=pg_temp.create_fingerprint_delete_command(failed_s,'remove');
  answer:=pg_temp.claim_device_command(d2,64);
  assert answer->>'id'=failed_c::text and (answer->>'reserved_slot')::integer=4,
    'Failure test claimed the wrong command';
  answer:=pg_temp.complete_device_command(failed_c,d2,false,4,'Sensor rejected deletion');
  assert answer->>'status'='failed','Physical failure was not reported';
  assert exists(select 1 from pg_temp.fingerprint_mappings where person_id=failed_s and slot_id=4),
    'Physical failure removed the mapping';
  insert into pg_temp.lifecycle_results values('physical failure retains mapping',true,null);
end $$;
select * from pg_temp.lifecycle_results order by test;
rollback;

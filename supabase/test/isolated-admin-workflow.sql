-- Run only in a disposable Supabase test project.
-- The final ROLLBACK guarantees that this script leaves no rows behind.
begin;

do $$
begin
  if to_regclass('public.classes') is null
     or to_regclass('public.people') is null
     or to_regclass('public.teacher_classes') is null
     or to_regclass('public.fingerprint_mappings') is null
     or to_regprocedure(
       'public.register_teacher_with_classes(text,text,uuid[])'
     ) is null then
    raise exception 'isolated test schema is incomplete';
  end if;
end;
$$;

do $$
declare
  class_a uuid;
  class_b uuid;
  teacher_id uuid;
  assignment_count integer;
begin
  insert into public.classes (name, section, academic_year)
  values ('QA CampusID Test 20261010', 'A', 'isolated')
  returning id into class_a;

  insert into public.classes (name, section, academic_year)
  values ('QA CampusID Test 20261010', 'B', 'isolated')
  returning id into class_b;

  teacher_id := public.register_teacher_with_classes(
    'QA CampusID Test Teacher 20261010',
    'QA-TEACHER-20261010',
    array[class_a, class_b, class_a]::uuid[]
  );

  if not exists (
    select 1 from public.people
    where id = teacher_id
      and role = 'teacher'
      and employee_id = 'QA-TEACHER-20261010'
  ) then
    raise exception 'teacher record was not created';
  end if;

  select count(*) into assignment_count
  from public.teacher_classes
  where public.teacher_classes.teacher_id = teacher_id
    and public.teacher_classes.class_id in (class_a, class_b);
  if assignment_count <> 2 then
    raise exception 'expected exactly two teacher assignments, got %',
      assignment_count;
  end if;

  begin
    perform public.register_teacher_with_classes(
      'QA Duplicate Teacher',
      'QA-TEACHER-20261010',
      array[class_a, class_b]::uuid[]
    );
    raise exception 'duplicate employee ID was accepted';
  exception when unique_violation then
    null;
  end;

  begin
    perform public.register_teacher_with_classes(
      'QA Invalid Class Teacher',
      'QA-INVALID-20261010',
      array['00000000-0000-0000-0000-000000000000']::uuid[]
    );
    raise exception 'invalid class ID was accepted';
  exception when foreign_key_violation then
    if exists (
      select 1 from public.people
      where employee_id = 'QA-INVALID-20261010'
    ) then
      raise exception 'invalid class left a partial teacher record';
    end if;
  end;
end;
$$;

-- Inspect the successful test data before the rollback.
select p.id as teacher_id, p.full_name, p.employee_id,
       tc.class_id, c.name, c.section
from public.people p
join public.teacher_classes tc on tc.teacher_id = p.id
join public.classes c on c.id = tc.class_id
where p.employee_id = 'QA-TEACHER-20261010'
order by c.section;

rollback;

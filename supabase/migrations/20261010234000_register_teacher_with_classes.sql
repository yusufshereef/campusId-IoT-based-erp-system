-- Registers a teacher and all of its class assignments in one transaction.
-- The secure schema baseline defines the administrator authorization helper.
create or replace function public.register_teacher_with_classes(
  p_full_name text,
  p_employee_id text,
  p_class_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  teacher_id uuid;
begin
  if auth.uid() is null or not public.is_administrator() then
    raise exception 'Administrator access is required'
      using errcode = '42501';
  end if;

  if length(trim(coalesce(p_full_name, ''))) = 0
     or length(trim(coalesce(p_employee_id, ''))) = 0
     or coalesce(cardinality(p_class_ids), 0) = 0 then
    raise exception 'Teacher name, employee ID, and at least one class are required'
      using errcode = '23514';
  end if;

  insert into public.people (
    full_name,
    role,
    employee_id,
    fingerprint_status
  )
  values (
    trim(p_full_name),
    'teacher',
    trim(p_employee_id),
    'not_enrolled'
  )
  returning id into teacher_id;

  insert into public.teacher_classes (teacher_id, class_id)
  select teacher_id, class_id
  from (
    select distinct class_id
    from unnest(p_class_ids) as requested(class_id)
  ) as unique_classes;

  return teacher_id;
end;
$$;

revoke all on function public.register_teacher_with_classes(text, text, uuid[])
  from public, anon, authenticated;
grant execute on function public.register_teacher_with_classes(text, text, uuid[])
  to authenticated;

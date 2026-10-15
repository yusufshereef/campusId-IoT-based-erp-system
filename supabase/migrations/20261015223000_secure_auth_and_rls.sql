-- Security hardening for the CampusID prototype.
-- Apply manually in Supabase SQL Editor after the existing schema/migrations.
-- The first administrator must be inserted manually by the project owner; this
-- migration never grants administrator access to anonymous or all-authenticated users.

-- Keep SECURITY DEFINER lookup paths from being shadowed by untrusted users.
revoke create on schema public from public;
revoke create on schema public from anon, authenticated;

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('administrator', 'teacher')),
  person_id uuid unique references public.people(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.user_roles enable row level security;

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select role
  from public.user_roles
  where user_id = (select auth.uid())
$$;

create or replace function public.is_administrator()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.user_roles
    where user_id = (select auth.uid())
      and role = 'administrator'
  )
$$;

create or replace function public.is_teacher_for_class(requested_class_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.teacher_classes tc on tc.teacher_id = ur.person_id
    where ur.user_id = (select auth.uid())
      and ur.role = 'teacher'
      and tc.class_id = requested_class_id
  )
$$;

revoke all on table public.classes, public.people, public.teacher_classes,
  public.fingerprint_mappings, public.user_roles
  from public, anon, authenticated;

grant select on table public.classes, public.people, public.teacher_classes
  to authenticated;
grant insert, update, delete on table public.classes, public.people,
  public.teacher_classes to authenticated;

drop policy if exists "demo classes read" on public.classes;
drop policy if exists "demo classes add" on public.classes;
drop policy if exists "demo people read" on public.people;
drop policy if exists "demo people add" on public.people;
drop policy if exists "demo people update" on public.people;
drop policy if exists "demo teacher classes read" on public.teacher_classes;
drop policy if exists "demo teacher classes add" on public.teacher_classes;
drop policy if exists "demo fingerprint mappings read" on public.fingerprint_mappings;
drop policy if exists "demo fingerprint mappings add" on public.fingerprint_mappings;
drop policy if exists "demo fingerprint mappings update" on public.fingerprint_mappings;

drop policy if exists "authenticated classes read" on public.classes;
create policy "authenticated classes read"
  on public.classes for select to authenticated
  using (public.is_administrator() or public.is_teacher_for_class(id));

drop policy if exists "administrators manage classes" on public.classes;
create policy "administrators manage classes"
  on public.classes for all to authenticated
  using (public.is_administrator())
  with check (public.is_administrator());

drop policy if exists "authenticated people read" on public.people;
create policy "authenticated people read"
  on public.people for select to authenticated
  using (
    public.is_administrator()
    or (
      role = 'student'
      and class_id is not null
      and public.is_teacher_for_class(class_id)
    )
    or (
      role = 'teacher'
      and exists (
        select 1
        from public.user_roles ur
        where ur.user_id = (select auth.uid())
          and ur.person_id = people.id
          and ur.role = 'teacher'
      )
    )
  );

drop policy if exists "administrators manage people" on public.people;
create policy "administrators manage people"
  on public.people for all to authenticated
  using (public.is_administrator())
  with check (public.is_administrator());

drop policy if exists "authenticated teacher assignments read"
  on public.teacher_classes;
create policy "authenticated teacher assignments read"
  on public.teacher_classes for select to authenticated
  using (
    public.is_administrator()
    or exists (
      select 1
      from public.user_roles ur
      where ur.user_id = (select auth.uid())
        and ur.role = 'teacher'
        and ur.person_id = teacher_classes.teacher_id
    )
  );

drop policy if exists "administrators manage teacher assignments"
  on public.teacher_classes;
create policy "administrators manage teacher assignments"
  on public.teacher_classes for all to authenticated
  using (public.is_administrator())
  with check (public.is_administrator());

drop policy if exists "browser fingerprint mappings blocked"
  on public.fingerprint_mappings;
create policy "browser fingerprint mappings blocked"
  on public.fingerprint_mappings for all to authenticated
  using (false)
  with check (false);

drop policy if exists "users read own role"
  on public.user_roles;
create policy "users read own role"
  on public.user_roles for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on function public.current_user_role() from public, anon, authenticated;
grant execute on function public.current_user_role() to authenticated;
revoke all on function public.is_administrator() from public, anon, authenticated;
grant execute on function public.is_administrator() to authenticated;
revoke all on function public.is_teacher_for_class(uuid)
  from public, anon, authenticated;
grant execute on function public.is_teacher_for_class(uuid) to authenticated;

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
    full_name, role, employee_id, fingerprint_status
  )
  values (
    trim(p_full_name), 'teacher', trim(p_employee_id), 'not_enrolled'
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

revoke all on table public.user_roles from anon, authenticated;
grant select on table public.user_roles to authenticated;

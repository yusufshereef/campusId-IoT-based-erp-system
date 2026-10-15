-- CampusID secure database baseline.
-- Run this file before the timestamped migrations.
-- It intentionally grants no anonymous access and creates no administrator.
create extension if not exists pgcrypto;

-- Keep SECURITY DEFINER lookup paths from being shadowed by untrusted users.
revoke create on schema public from public;

create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  section text not null default 'A' check (length(trim(section)) > 0),
  academic_year text,
  created_at timestamptz not null default now(),
  unique(name, section, academic_year)
);

create table if not exists public.people (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (length(trim(full_name)) > 0),
  role text not null check (role in ('student', 'teacher')),
  roll_number text unique,
  employee_id text unique,
  class_id uuid references public.classes(id) on delete restrict,
  fingerprint_slot integer check (fingerprint_slot is null or fingerprint_slot > 0),
  fingerprint_status text not null default 'not_enrolled'
    check (fingerprint_status in ('not_enrolled', 'pending', 'enrolled', 'failed')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint role_identifier_check check (
    (role = 'student' and roll_number is not null
      and employee_id is null and class_id is not null)
    or
    (role = 'teacher' and employee_id is not null
      and roll_number is null and class_id is null)
  )
);

create table if not exists public.teacher_classes (
  teacher_id uuid not null references public.people(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (teacher_id, class_id)
);

create table if not exists public.fingerprint_mappings (
  id uuid primary key default gen_random_uuid(),
  device_id text not null,
  slot_id integer not null check (slot_id > 0),
  person_id uuid not null references public.people(id) on delete restrict,
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  unique(device_id, slot_id),
  unique(device_id, person_id)
);

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('administrator', 'teacher')),
  person_id uuid unique references public.people(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists people_role_idx on public.people(role);
create index if not exists people_class_idx on public.people(class_id);
create index if not exists teacher_classes_class_idx
  on public.teacher_classes(class_id);
create index if not exists fingerprint_mappings_person_idx
  on public.fingerprint_mappings(person_id);

alter table public.classes enable row level security;
alter table public.people enable row level security;
alter table public.teacher_classes enable row level security;
alter table public.fingerprint_mappings enable row level security;
alter table public.user_roles enable row level security;

-- Remove policies from the original demo baseline if this file is rerun.
drop policy if exists "demo classes read" on public.classes;
drop policy if exists "demo classes add" on public.classes;
drop policy if exists "demo people read" on public.people;
drop policy if exists "demo people add" on public.people;
drop policy if exists "demo people update" on public.people;
drop policy if exists "demo teacher classes read" on public.teacher_classes;
drop policy if exists "demo teacher classes add" on public.teacher_classes;
drop policy if exists "demo fingerprint mappings read"
  on public.fingerprint_mappings;
drop policy if exists "demo fingerprint mappings add"
  on public.fingerprint_mappings;
drop policy if exists "demo fingerprint mappings update"
  on public.fingerprint_mappings;

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
grant insert, update on table public.classes, public.people
  to authenticated;

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

drop policy if exists "users read own role" on public.user_roles;
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

-- If this baseline is rerun over an older deployment, remove the legacy
-- anonymous RPC grant as well. The function is created by the migration below.
do $$
begin
  if to_regprocedure(
    'public.register_teacher_with_classes(text,text,uuid[])'
  ) is not null then
    revoke all on function public.register_teacher_with_classes(text, text, uuid[])
      from public, anon, authenticated;
  end if;
end;
$$;

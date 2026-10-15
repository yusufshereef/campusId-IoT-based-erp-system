-- DEMO ONLY: this policy makes tables publicly readable/writable via the public key.
-- Use fake data only until you add Supabase Auth and restrictive RLS policies.
create extension if not exists pgcrypto;
create table if not exists public.classes (
 id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name))>0),
 section text not null default 'A' check(length(trim(section))>0), academic_year text,
 created_at timestamptz not null default now(), unique(name,section,academic_year));
create table if not exists public.people (
 id uuid primary key default gen_random_uuid(), full_name text not null check(length(trim(full_name))>0),
 role text not null check(role in ('student','teacher')), roll_number text unique, employee_id text unique,
 class_id uuid references public.classes(id) on delete restrict,
 fingerprint_slot integer check(fingerprint_slot is null or fingerprint_slot>0),
 fingerprint_status text not null default 'not_enrolled' check(fingerprint_status in ('not_enrolled','pending','enrolled','failed')),
 active boolean not null default true, created_at timestamptz not null default now(),
 constraint role_identifier_check check((role='student' and roll_number is not null and employee_id is null and class_id is not null) or (role='teacher' and employee_id is not null and roll_number is null and class_id is null)));
create table if not exists public.teacher_classes (
 teacher_id uuid not null references public.people(id) on delete cascade,
 class_id uuid not null references public.classes(id) on delete restrict,
 created_at timestamptz not null default now(), primary key(teacher_id,class_id));
create table if not exists public.fingerprint_mappings (
 id uuid primary key default gen_random_uuid(), device_id text not null, slot_id integer not null check(slot_id>0),
 person_id uuid not null references public.people(id) on delete restrict,
 status text not null default 'active' check(status in ('active','inactive')), created_at timestamptz not null default now(),
 unique(device_id,slot_id), unique(device_id,person_id));
create index if not exists people_role_idx on public.people(role);
create index if not exists people_class_idx on public.people(class_id);
create index if not exists teacher_classes_class_idx on public.teacher_classes(class_id);
create index if not exists fingerprint_mappings_person_idx on public.fingerprint_mappings(person_id);
alter table public.classes enable row level security;
alter table public.people enable row level security;
alter table public.teacher_classes enable row level security;
alter table public.fingerprint_mappings enable row level security;
drop policy if exists "demo classes read" on public.classes;
create policy "demo classes read" on public.classes for select to anon,authenticated using(true);
drop policy if exists "demo classes add" on public.classes;
create policy "demo classes add" on public.classes for insert to anon,authenticated with check(true);
drop policy if exists "demo people read" on public.people;
create policy "demo people read" on public.people for select to anon,authenticated using(true);
drop policy if exists "demo people add" on public.people;
create policy "demo people add" on public.people for insert to anon,authenticated with check(true);
drop policy if exists "demo people update" on public.people;
create policy "demo people update" on public.people for update to anon,authenticated using(true) with check(true);
drop policy if exists "demo teacher classes read" on public.teacher_classes;
create policy "demo teacher classes read" on public.teacher_classes for select to anon,authenticated using(true);
drop policy if exists "demo teacher classes add" on public.teacher_classes;
create policy "demo teacher classes add" on public.teacher_classes for insert to anon,authenticated with check(true);
drop policy if exists "demo fingerprint mappings read" on public.fingerprint_mappings;
create policy "demo fingerprint mappings read" on public.fingerprint_mappings for select to anon,authenticated using(true);
drop policy if exists "demo fingerprint mappings add" on public.fingerprint_mappings;
create policy "demo fingerprint mappings add" on public.fingerprint_mappings for insert to anon,authenticated with check(true);
drop policy if exists "demo fingerprint mappings update" on public.fingerprint_mappings;
create policy "demo fingerprint mappings update" on public.fingerprint_mappings for update to anon,authenticated using(true) with check(true);

-- Keep teacher creation and all class assignments atomic.
create or replace function public.register_teacher_with_classes(
  p_full_name text,
  p_employee_id text,
  p_class_ids uuid[]
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  teacher_id uuid;
begin
  if length(trim(coalesce(p_full_name, ''))) = 0
     or length(trim(coalesce(p_employee_id, ''))) = 0
     or coalesce(cardinality(p_class_ids), 0) = 0 then
    raise exception 'Teacher name, employee ID, and at least one class are required'
      using errcode = '23514';
  end if;

  insert into public.people (full_name, role, employee_id, fingerprint_status)
  values (trim(p_full_name), 'teacher', trim(p_employee_id), 'not_enrolled')
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
grant execute on function public.register_teacher_with_classes(text, text, uuid[])
  to anon, authenticated;
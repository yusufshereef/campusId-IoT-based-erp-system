-- Attendance records with class-scoped authorization and immutable attribution.
-- Apply after the security and least-privilege migrations.

create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null
    references public.classes(id) on delete restrict,
  student_id uuid not null
    references public.people(id) on delete restrict,
  attendance_date date not null,
  status text not null
    check (status in ('present', 'absent', 'late', 'excused')),
  recorded_by_user_id uuid not null
    references auth.users(id) on delete restrict,
  client_event_id uuid unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, class_id, attendance_date)
);

create index if not exists attendance_records_class_date_idx
  on public.attendance_records(class_id, attendance_date);
create index if not exists attendance_records_student_date_idx
  on public.attendance_records(student_id, attendance_date);
create index if not exists attendance_records_recorded_by_idx
  on public.attendance_records(recorded_by_user_id);

create table if not exists public.attendance_record_audit (
  id uuid primary key default gen_random_uuid(),
  attendance_record_id uuid not null
    references public.attendance_records(id) on delete restrict,
  changed_by_user_id uuid
    references auth.users(id) on delete restrict,
  old_status text not null,
  new_status text not null,
  old_class_id uuid not null,
  new_class_id uuid not null,
  old_student_id uuid not null,
  new_student_id uuid not null,
  changed_at timestamptz not null default now()
);

create index if not exists attendance_record_audit_record_idx
  on public.attendance_record_audit(attendance_record_id, changed_at);

create or replace function public.validate_attendance_record()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'UPDATE'
     and new.recorded_by_user_id is distinct from old.recorded_by_user_id then
    raise exception 'Attendance attribution cannot be changed'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.people p
    where p.id = new.student_id
      and p.role = 'student'
      and p.class_id = new.class_id
      and p.active
  ) then
    raise exception
      'Attendance requires an active student assigned to the selected class'
      using errcode = '23514';
  end if;

  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;
  return new;
end;
$$;

create or replace function public.audit_attendance_record_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if old.status is distinct from new.status
     or old.class_id is distinct from new.class_id
     or old.student_id is distinct from new.student_id then
    insert into public.attendance_record_audit (
      attendance_record_id,
      changed_by_user_id,
      old_status,
      new_status,
      old_class_id,
      new_class_id,
      old_student_id,
      new_student_id
    )
    values (
      old.id,
      (select auth.uid()),
      old.status,
      new.status,
      old.class_id,
      new.class_id,
      old.student_id,
      new.student_id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists attendance_record_validation
  on public.attendance_records;
create trigger attendance_record_validation
before insert or update on public.attendance_records
for each row execute function public.validate_attendance_record();

drop trigger if exists attendance_record_update_audit
  on public.attendance_records;
create trigger attendance_record_update_audit
after update on public.attendance_records
for each row execute function public.audit_attendance_record_update();

alter table public.attendance_records enable row level security;
alter table public.attendance_record_audit enable row level security;

revoke all on table public.attendance_records, public.attendance_record_audit
  from public, anon, authenticated;
grant select, insert, update on table public.attendance_records
  to authenticated;
grant select on table public.attendance_record_audit to authenticated;

drop policy if exists "authenticated attendance read"
  on public.attendance_records;
create policy "authenticated attendance read"
  on public.attendance_records for select to authenticated
  using (
    public.is_administrator()
    or public.is_teacher_for_class(class_id)
  );

drop policy if exists "administrators and teachers record attendance"
  on public.attendance_records;
create policy "administrators and teachers record attendance"
  on public.attendance_records for insert to authenticated
  with check (
    (
      public.is_administrator()
      and recorded_by_user_id = (select auth.uid())
    )
    or (
      public.is_teacher_for_class(class_id)
      and recorded_by_user_id = (select auth.uid())
    )
  );

drop policy if exists "administrators and teachers correct attendance"
  on public.attendance_records;
create policy "administrators and teachers correct attendance"
  on public.attendance_records for update to authenticated
  using (
    public.is_administrator()
    or public.is_teacher_for_class(class_id)
  )
  with check (
    public.is_administrator()
    or public.is_teacher_for_class(class_id)
  );

drop policy if exists "administrators read attendance audit"
  on public.attendance_record_audit;
create policy "administrators read attendance audit"
  on public.attendance_record_audit for select to authenticated
  using (public.is_administrator());

revoke all on function public.validate_attendance_record()
  from public, anon, authenticated;
revoke all on function public.audit_attendance_record_update()
  from public, anon, authenticated;

-- CampusID Milestone 2: provisioned terminal health and secure heartbeat metadata.
create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  device_code text not null unique
    check (device_code ~ '^[a-z0-9][a-z0-9-]*$'),
  display_name text not null check (length(trim(display_name)) > 0),
  secret_hash text not null check (secret_hash ~ '^[0-9a-f]{64}$'),
  last_seen_at timestamptz,
  firmware_version text,
  sensor_ready boolean not null default false,
  pending_event_count integer not null default 0
    check (pending_event_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists devices_last_seen_idx
  on public.devices(last_seen_at);

alter table public.devices enable row level security;

revoke all on table public.devices from public, anon, authenticated;
grant select (
  id,
  device_code,
  display_name,
  last_seen_at,
  firmware_version,
  sensor_ready,
  pending_event_count,
  created_at,
  updated_at
) on table public.devices to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'devices'
      and policyname = 'authorized users read devices'
  ) then
    create policy "authorized users read devices"
      on public.devices for select to authenticated
      using (
        public.is_administrator()
        or public.current_user_role() = 'teacher'
      );
  end if;
end
$$;

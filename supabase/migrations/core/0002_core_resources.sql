-- Core: bookable resources (staff, equipment, rooms) and their unavailability.
create table resource_types (
  code text primary key,
  label text not null
);

create table resources (
  id uuid primary key default gen_random_uuid(),
  resource_type_code text not null references resource_types(code) on delete restrict,
  name text not null,
  linked_staff_user_id uuid references staff_users(id) on delete set null,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table resource_leave (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid not null references resources(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text,
  created_by_staff_id uuid references staff_users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint chk_resource_leave_range check (ends_at > starts_at)
);

create index idx_resources_type on resources(resource_type_code);
create index idx_resource_leave_resource_range on resource_leave using gist (resource_id, tstzrange(starts_at, ends_at));

-- Core: generic deliverables/line-items concept, reusable across industries
-- (wedding: Album/Teaser/Trailer...; clinic: Prescription/Lab Report...).
create table deliverable_types (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  default_price numeric(12,2), -- null = included/no separate charge by default
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table booking_deliverables (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id) on delete cascade,
  deliverable_type_id uuid not null references deliverable_types(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending', 'in_progress', 'delivered')),
  price_override numeric(12,2), -- snapshotted actual price if it differs from default
  is_included boolean not null default false,
  delivered_at timestamptz,
  metadata jsonb not null default '{}'::jsonb, -- industry-specific detail, e.g. {photo_link_url} or {diagnosis, medicines:[...]}
  created_at timestamptz not null default now()
);

create table booking_attachments (
  id uuid primary key default gen_random_uuid(),
  booking_deliverable_id uuid references booking_deliverables(id) on delete cascade,
  booking_id uuid references bookings(id) on delete cascade,
  storage_path text, -- Supabase Storage object path
  external_url text, -- externally hosted link (e.g. Google Drive photo links)
  label text,
  created_at timestamptz not null default now(),
  constraint chk_attachment_target check (storage_path is not null or external_url is not null)
);

create index idx_booking_deliverables_booking on booking_deliverables(booking_id);
create index idx_booking_attachments_booking on booking_attachments(booking_id);
create index idx_booking_attachments_deliverable on booking_attachments(booking_deliverable_id);

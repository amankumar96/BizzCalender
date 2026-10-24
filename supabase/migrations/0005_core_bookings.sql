-- Core: leads (inquiry -> booked via offline advance -> converted to customer),
-- bookings, and the line items / resource assignments underneath a booking.
create table leads (
  id uuid primary key default gen_random_uuid(),
  contact_name text not null,
  contact_phone text not null,
  contact_email text,
  source text, -- 'website' | 'referral' | 'walk_in' | ...
  preferred_event_date date,
  is_date_flexible boolean not null default false,
  flexible_date_from date,
  flexible_date_to date,
  interested_service_ids uuid[],
  stage text not null default 'inquiry' check (stage in ('inquiry', 'booked', 'lost')),
  created_by_staff_id uuid references staff_users(id) on delete set null,
  converted_by_staff_id uuid references staff_users(id) on delete set null,
  converted_customer_id uuid references customers(id) on delete set null,
  advance_payment_transaction_id uuid, -- fk added in 0006_core_payments.sql once payment_transactions exists
  converted_at timestamptz,
  booking_id uuid, -- fk added below after bookings exists
  notes text,
  created_at timestamptz not null default now(),
  constraint chk_lead_flexible_range check (flexible_date_to is null or flexible_date_from is null or flexible_date_to >= flexible_date_from)
);

create table bookings (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id) on delete restrict,
  created_by_staff_id uuid references staff_users(id) on delete set null,
  lead_id uuid references leads(id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'completed', 'cancelled')),
  event_type text not null, -- free label e.g. 'wedding' | 'pre_wedding' | 'consultation'
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  slot_definition_id uuid not null references slot_definitions(id) on delete restrict,
  package_id uuid references packages(id) on delete set null,
  total_amount numeric(12,2) not null check (total_amount >= 0),
  currency text not null default 'INR',
  notes text,
  created_at timestamptz not null default now(),
  constraint chk_booking_range check (ends_at > starts_at)
);

alter table leads add constraint fk_leads_booking foreign key (booking_id) references bookings(id) on delete set null;

create table booking_services (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id) on delete cascade,
  service_id uuid not null references services(id) on delete restrict,
  rate_card_id uuid references rate_cards(id) on delete set null, -- null if fully covered by a package
  quantity int not null default 1 check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0) -- snapshotted at booking time
);

create table booking_addons (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id) on delete cascade,
  addon_id uuid not null references addons(id) on delete restrict,
  quantity int not null default 1 check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0) -- snapshotted at booking time
);

create table booking_resources (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id) on delete cascade,
  resource_id uuid not null references resources(id) on delete restrict,
  role_label text, -- e.g. 'cameraman' | 'assistant' | 'doctor'
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'confirmed' check (status in ('confirmed', 'cancelled')),
  constraint chk_booking_resource_range check (ends_at > starts_at),
  -- DB-level double-booking guard: no two non-cancelled assignments for the same
  -- resource may have overlapping time windows.
  exclude using gist (resource_id with =, tstzrange(starts_at, ends_at) with &&) where (status <> 'cancelled')
);

create index idx_leads_created_by on leads(created_by_staff_id);
create index idx_leads_converted_by on leads(converted_by_staff_id);
create index idx_leads_stage on leads(stage);
create index idx_bookings_customer on bookings(customer_id);
create index idx_bookings_lead on bookings(lead_id);
create index idx_bookings_range on bookings using gist (tstzrange(starts_at, ends_at));
create index idx_booking_services_booking on booking_services(booking_id);
create index idx_booking_addons_booking on booking_addons(booking_id);
create index idx_booking_resources_booking on booking_resources(booking_id);

-- Derives red/green/grey state for every candidate slot of one resource on one day.
-- state: 'booked' (red), 'available' (green), 'unavailable' (grey). Color itself is
-- never stored -- clients render red/green/grey from this 'state' value.
create or replace function fn_resource_day_state(p_resource_id uuid, p_slot_definition_id uuid, p_date date)
returns table(starts_at timestamptz, ends_at timestamptz, state text)
language plpgsql stable security definer as $$
declare
  v_weekday int := extract(dow from p_date);
  v_is_working boolean;
begin
  select is_working_day into v_is_working from working_hours_templates where weekday = v_weekday;
  if not found or not v_is_working then
    return query select p_date::timestamptz, (p_date + 1)::timestamptz, 'unavailable'::text;
    return;
  end if;

  return query
  select
    c.starts_at,
    c.ends_at,
    case
      when exists (
        select 1 from blocked_dates bd
        where (bd.resource_id is null or bd.resource_id = p_resource_id)
          and tstzrange(bd.starts_at, bd.ends_at) && tstzrange(c.starts_at, c.ends_at)
      ) then 'unavailable'
      when exists (
        select 1 from resource_leave rl
        where rl.resource_id = p_resource_id
          and tstzrange(rl.starts_at, rl.ends_at) && tstzrange(c.starts_at, c.ends_at)
      ) then 'unavailable'
      when exists (
        select 1 from booking_resources br
        where br.resource_id = p_resource_id
          and br.status <> 'cancelled'
          and tstzrange(br.starts_at, br.ends_at) && tstzrange(c.starts_at, c.ends_at)
      ) then 'booked'
      else 'available'
    end as state
  from fn_generate_candidate_slots(p_slot_definition_id, p_date) c;
end;
$$;

-- Convenience wrapper: same as fn_resource_day_state but across a date range.
create or replace function fn_calendar_slots(p_resource_id uuid, p_slot_definition_id uuid, p_date_from date, p_date_to date)
returns table(slot_date date, starts_at timestamptz, ends_at timestamptz, state text)
language plpgsql stable security definer as $$
declare
  d date;
begin
  for d in select generate_series(p_date_from, p_date_to, interval '1 day')::date loop
    return query
    select d, s.starts_at, s.ends_at, s.state
    from fn_resource_day_state(p_resource_id, p_slot_definition_id, d) s;
  end loop;
end;
$$;

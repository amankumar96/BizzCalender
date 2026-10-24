-- Core: one generic slot model for full_day / half_day / fixed_slot events,
-- plus SQL functions that DERIVE red/green/grey calendar state at query time
-- (color is never stored).
create table working_hours_templates (
  weekday int primary key check (weekday between 0 and 6), -- 0 = Sunday .. 6 = Saturday
  opens_at time not null default '09:00',
  closes_at time not null default '18:00',
  is_working_day boolean not null default true
);

create table slot_definitions (
  id uuid primary key default gen_random_uuid(),
  service_id uuid references services(id) on delete cascade,
  event_kind text not null check (event_kind in ('full_day', 'half_day', 'fixed_slot')),
  duration_minutes int check (duration_minutes > 0), -- full_day / half_day: length of one bookable unit
  slot_length_minutes int check (slot_length_minutes > 0), -- fixed_slot: granularity
  window_start_time time, -- fixed_slot (and optionally half_day): daily window start
  window_end_time time,   -- fixed_slot (and optionally half_day): daily window end
  max_concurrent_bookings int not null default 1 check (max_concurrent_bookings > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint chk_slot_def_shape check (
    (event_kind in ('full_day', 'half_day') and duration_minutes is not null)
    or (event_kind = 'fixed_slot' and slot_length_minutes is not null)
  )
);

create table blocked_dates (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid references resources(id) on delete cascade, -- null = company-wide
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text,
  created_at timestamptz not null default now(),
  constraint chk_blocked_dates_range check (ends_at > starts_at)
);

create index idx_slot_definitions_service on slot_definitions(service_id);
create index idx_blocked_dates_resource_range on blocked_dates using gist (coalesce(resource_id, '00000000-0000-0000-0000-000000000000'::uuid), tstzrange(starts_at, ends_at));

-- Generates candidate (starts_at, ends_at) windows for one calendar day, independent of
-- any specific resource or existing bookings. full_day -> 1 whole-day slot; half_day ->
-- as many duration_minutes chunks as fit in working hours; fixed_slot -> walks the
-- configured window in slot_length_minutes steps.
create or replace function fn_generate_candidate_slots(p_slot_definition_id uuid, p_date date)
returns table(starts_at timestamptz, ends_at timestamptz)
language plpgsql stable as $$
declare
  v_def slot_definitions%rowtype;
  v_wh working_hours_templates%rowtype;
  v_weekday int;
  v_cursor timestamptz;
  v_window_start timestamptz;
  v_window_end timestamptz;
begin
  select * into v_def from slot_definitions where id = p_slot_definition_id;
  if not found then
    return;
  end if;

  v_weekday := extract(dow from p_date);
  select * into v_wh from working_hours_templates where weekday = v_weekday;
  if not found or not v_wh.is_working_day then
    return; -- non-working day: no candidate slots at all
  end if;

  if v_def.event_kind = 'full_day' then
    starts_at := p_date::timestamptz;
    ends_at := starts_at + (v_def.duration_minutes || ' minutes')::interval;
    return next;

  elsif v_def.event_kind = 'half_day' then
    v_window_start := p_date + coalesce(v_def.window_start_time, v_wh.opens_at);
    v_window_end := p_date + coalesce(v_def.window_end_time, v_wh.closes_at);
    v_cursor := v_window_start;
    while v_cursor + (v_def.duration_minutes || ' minutes')::interval <= v_window_end loop
      starts_at := v_cursor;
      ends_at := v_cursor + (v_def.duration_minutes || ' minutes')::interval;
      return next;
      v_cursor := ends_at;
    end loop;

  elsif v_def.event_kind = 'fixed_slot' then
    v_window_start := p_date + coalesce(v_def.window_start_time, v_wh.opens_at);
    v_window_end := p_date + coalesce(v_def.window_end_time, v_wh.closes_at);
    v_cursor := v_window_start;
    while v_cursor + (v_def.slot_length_minutes || ' minutes')::interval <= v_window_end loop
      starts_at := v_cursor;
      ends_at := v_cursor + (v_def.slot_length_minutes || ' minutes')::interval;
      return next;
      v_cursor := ends_at;
    end loop;
  end if;
end;
$$;

-- fn_resource_day_state and fn_calendar_slots (the red/green/grey derivation functions)
-- live in 0005_core_bookings.sql because they read booking_resources, which is created
-- there -- plpgsql's check_function_bodies validates referenced tables at CREATE time.

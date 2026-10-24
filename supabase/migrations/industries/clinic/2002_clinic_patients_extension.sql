-- Doctor's Clinic industry extension: structured medical history beyond what
-- customers + booking_deliverables.metadata can hold. Pure addition -- FKs into core,
-- core tables untouched.
create table patients (
  customer_id uuid primary key references customers(id) on delete cascade,
  allergies text,
  chronic_conditions text,
  blood_group text,
  emergency_contact_phone text,
  created_at timestamptz not null default now()
);

alter table patients enable row level security;

create policy patients_admin_all on patients for all using (fn_is_admin()) with check (fn_is_admin());
create policy patients_staff_all on patients for all using (fn_is_staff()) with check (fn_is_staff());
create policy patients_self_read on patients for select using (
  exists (select 1 from customers c where c.id = customer_id and c.auth_user_id = auth.uid())
);

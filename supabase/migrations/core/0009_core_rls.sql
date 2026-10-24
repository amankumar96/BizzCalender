-- Core: RLS helper functions + policies. auth.uid() anchors both staff and customer
-- identity; these helpers branch on which application table actually contains it.
create or replace function fn_is_staff()
returns boolean language sql stable security definer as $$
  select exists (select 1 from staff_users where id = auth.uid() and status = 'active');
$$;

create or replace function fn_has_role(p_role text)
returns boolean language sql stable security definer as $$
  select exists (
    select 1 from staff_user_roles
    where staff_user_id = auth.uid() and role_code = p_role
  );
$$;

create or replace function fn_is_admin()
returns boolean language sql stable security definer as $$
  select fn_has_role('admin');
$$;

create or replace function fn_is_customer()
returns boolean language sql stable security definer as $$
  select exists (select 1 from customers where auth_user_id = auth.uid());
$$;

create or replace function fn_current_customer_id()
returns uuid language sql stable security definer as $$
  select id from customers where auth_user_id = auth.uid();
$$;

-- Enable RLS everywhere.
alter table companies enable row level security;
alter table staff_users enable row level security;
alter table roles enable row level security;
alter table staff_user_roles enable row level security;
alter table customers enable row level security;
alter table resource_types enable row level security;
alter table resources enable row level security;
alter table resource_leave enable row level security;
alter table services enable row level security;
alter table rate_cards enable row level security;
alter table addons enable row level security;
alter table packages enable row level security;
alter table package_items enable row level security;
alter table working_hours_templates enable row level security;
alter table slot_definitions enable row level security;
alter table blocked_dates enable row level security;
alter table leads enable row level security;
alter table bookings enable row level security;
alter table booking_services enable row level security;
alter table booking_addons enable row level security;
alter table booking_resources enable row level security;
alter table payment_transactions enable row level security;
alter table payment_webhooks_log enable row level security;
alter table deliverable_types enable row level security;
alter table booking_deliverables enable row level security;
alter table booking_attachments enable row level security;
alter table notifications enable row level security;

-- Config/catalog tables: admin manages, staff reads, anonymous reads active rows
-- (powers the public booking UI's service/pricing display).
create policy companies_admin_all on companies for all using (fn_is_admin()) with check (fn_is_admin());
create policy companies_staff_read on companies for select using (fn_is_staff());

create policy resource_types_admin_all on resource_types for all using (fn_is_admin()) with check (fn_is_admin());
create policy resource_types_read_all on resource_types for select using (true);

create policy services_admin_all on services for all using (fn_is_admin()) with check (fn_is_admin());
create policy services_staff_read on services for select using (fn_is_staff());
create policy services_public_read on services for select using (is_active and auth.role() = 'anon');

create policy rate_cards_admin_all on rate_cards for all using (fn_is_admin()) with check (fn_is_admin());
create policy rate_cards_staff_read on rate_cards for select using (fn_is_staff());
create policy rate_cards_public_read on rate_cards for select using (is_active and auth.role() = 'anon');

create policy addons_admin_all on addons for all using (fn_is_admin()) with check (fn_is_admin());
create policy addons_staff_read on addons for select using (fn_is_staff());
create policy addons_public_read on addons for select using (is_active and auth.role() = 'anon');

create policy packages_admin_all on packages for all using (fn_is_admin()) with check (fn_is_admin());
create policy packages_staff_read on packages for select using (fn_is_staff());
create policy packages_public_read on packages for select using (is_active and auth.role() = 'anon');

create policy package_items_admin_all on package_items for all using (fn_is_admin()) with check (fn_is_admin());
create policy package_items_read on package_items for select using (fn_is_staff() or auth.role() = 'anon');

create policy deliverable_types_admin_all on deliverable_types for all using (fn_is_admin()) with check (fn_is_admin());
create policy deliverable_types_read on deliverable_types for select using (fn_is_staff() or auth.role() = 'anon');

create policy working_hours_admin_all on working_hours_templates for all using (fn_is_admin()) with check (fn_is_admin());
create policy working_hours_read on working_hours_templates for select using (true);

create policy slot_definitions_admin_all on slot_definitions for all using (fn_is_admin()) with check (fn_is_admin());
create policy slot_definitions_read on slot_definitions for select using (true);

-- Resources: admin manages; staff reads; active resources are readable publicly
-- (needed to list bookable resources in the self-service UI), but leave/blocked-date
-- detail stays staff-only -- public availability is exposed only via fn_calendar_slots.
create policy resources_admin_all on resources for all using (fn_is_admin()) with check (fn_is_admin());
create policy resources_staff_read on resources for select using (fn_is_staff());
create policy resources_public_read on resources for select using (is_active and auth.role() = 'anon');

create policy resource_leave_staff_all on resource_leave for all using (fn_is_staff()) with check (fn_is_staff());
create policy blocked_dates_staff_all on blocked_dates for all using (fn_is_staff()) with check (fn_is_staff());

-- Staff identity tables: admin manages; a staff member can read their own row/roles.
create policy staff_users_admin_all on staff_users for all using (fn_is_admin()) with check (fn_is_admin());
create policy staff_users_self_read on staff_users for select using (id = auth.uid());

create policy roles_read_all on roles for select using (fn_is_staff());
create policy roles_admin_all on roles for all using (fn_is_admin()) with check (fn_is_admin());

create policy staff_user_roles_admin_all on staff_user_roles for all using (fn_is_admin()) with check (fn_is_admin());
create policy staff_user_roles_self_read on staff_user_roles for select using (staff_user_id = auth.uid());

-- Customers: admin/staff manage; a customer can read/update only their own row.
create policy customers_admin_all on customers for all using (fn_is_admin()) with check (fn_is_admin());
create policy customers_staff_all on customers for all using (fn_is_staff()) with check (fn_is_staff());
create policy customers_self_read on customers for select using (auth_user_id = auth.uid());
create policy customers_self_update on customers for update using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());

-- Leads: admin sees everything; a staff/sales user sees leads they generated or
-- closed (attribution-scoped per the lead-conversion requirement). No customer or
-- anonymous access -- lead capture and advance-payment recording go through Edge
-- Functions using the service role so attribution fields can't be forged client-side.
create policy leads_admin_all on leads for all using (fn_is_admin()) with check (fn_is_admin());
create policy leads_owner_all on leads for all
  using (fn_is_staff() and (created_by_staff_id = auth.uid() or converted_by_staff_id = auth.uid()))
  with check (fn_is_staff() and (created_by_staff_id = auth.uid() or converted_by_staff_id = auth.uid()));

-- Bookings & line items: admin/staff operate on company bookings; a customer is
-- restricted to their own bookings; no anonymous row access (availability is exposed
-- only through fn_calendar_slots / fn_resource_day_state).
create policy bookings_admin_all on bookings for all using (fn_is_admin()) with check (fn_is_admin());
create policy bookings_staff_all on bookings for all using (fn_is_staff()) with check (fn_is_staff());
create policy bookings_customer_own on bookings for all
  using (fn_is_customer() and customer_id = fn_current_customer_id())
  with check (fn_is_customer() and customer_id = fn_current_customer_id());

create policy booking_services_staff_all on booking_services for all using (fn_is_staff()) with check (fn_is_staff());
create policy booking_services_customer_own on booking_services for select using (
  exists (select 1 from bookings b where b.id = booking_id and b.customer_id = fn_current_customer_id())
);

create policy booking_addons_staff_all on booking_addons for all using (fn_is_staff()) with check (fn_is_staff());
create policy booking_addons_customer_own on booking_addons for select using (
  exists (select 1 from bookings b where b.id = booking_id and b.customer_id = fn_current_customer_id())
);

create policy booking_resources_staff_all on booking_resources for all using (fn_is_staff()) with check (fn_is_staff());
create policy booking_resources_customer_own on booking_resources for select using (
  exists (select 1 from bookings b where b.id = booking_id and b.customer_id = fn_current_customer_id())
);

-- Payments: admin full; customer reads their own via the booking join; all writes
-- happen through Edge Functions using the service role (gateway webhooks, offline
-- advance recording), never direct client inserts.
create policy payment_transactions_admin_all on payment_transactions for all using (fn_is_admin()) with check (fn_is_admin());
create policy payment_transactions_customer_read on payment_transactions for select using (
  exists (select 1 from bookings b where b.id = booking_id and b.customer_id = fn_current_customer_id())
);
create policy payment_webhooks_log_admin_all on payment_webhooks_log for all using (fn_is_admin()) with check (fn_is_admin());

-- Deliverables & attachments: staff manage bookings they fulfil; customer reads own.
create policy booking_deliverables_staff_all on booking_deliverables for all using (fn_is_staff()) with check (fn_is_staff());
create policy booking_deliverables_customer_own on booking_deliverables for select using (
  exists (select 1 from bookings b where b.id = booking_id and b.customer_id = fn_current_customer_id())
);
create policy booking_attachments_staff_all on booking_attachments for all using (fn_is_staff()) with check (fn_is_staff());
create policy booking_attachments_customer_own on booking_attachments for select using (
  exists (select 1 from bookings b where b.id = booking_id and b.customer_id = fn_current_customer_id())
);

-- Notifications: admin sees all; a staff/customer recipient reads their own.
create policy notifications_admin_all on notifications for all using (fn_is_admin()) with check (fn_is_admin());
create policy notifications_staff_own on notifications for select using (recipient_type = 'staff' and recipient_id = auth.uid());
create policy notifications_customer_own on notifications for select using (recipient_type = 'customer' and recipient_id = fn_current_customer_id());

-- Grant execute on the availability functions to anonymous + authenticated so the
-- public booking UI can render red/green/grey without any table-level access.
grant execute on function fn_generate_candidate_slots(uuid, date) to anon, authenticated;
grant execute on function fn_resource_day_state(uuid, uuid, date) to anon, authenticated;
grant execute on function fn_calendar_slots(uuid, uuid, date, date) to anon, authenticated;

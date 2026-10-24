-- Doctor's Clinic industry extension: validates that the core schema needs zero
-- changes for a second, very different vertical. Purely additive seed data + one
-- fixed_slot slot definition (15-min appointment slots, 9am-12pm).
do $$
declare
  v_company_id uuid;
  v_consult_id uuid;
  v_followup_id uuid;
begin
  insert into companies (name, industry_code, timezone, default_currency)
  values ('Sample Clinic', 'clinic', 'Asia/Kolkata', 'INR')
  returning id into v_company_id;

  insert into services (name, requires_resource_type_code, category) values
    ('General Consultation', 'staff', 'consultation') returning id into v_consult_id;
  insert into services (name, requires_resource_type_code, category) values
    ('Follow-up Consultation', 'staff', 'consultation') returning id into v_followup_id;

  insert into rate_cards (service_id, tier_label, duration_minutes, price) values
    (v_consult_id, '15min', 15, 500),
    (v_followup_id, '15min', 15, 300);

  insert into slot_definitions (service_id, event_kind, slot_length_minutes, window_start_time, window_end_time) values
    (v_consult_id, 'fixed_slot', 15, '09:00', '12:00'),
    (v_followup_id, 'fixed_slot', 15, '09:00', '12:00');

  insert into deliverable_types (name, default_price, is_active) values
    ('Prescription', null, true),
    ('Lab Report', null, true);
end $$;

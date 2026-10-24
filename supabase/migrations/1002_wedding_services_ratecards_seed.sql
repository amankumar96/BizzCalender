-- Wedding Photography industry extension: company row, services, duration-tiered rate
-- cards, addons, the flat-override package, and slot definitions -- seeded from the
-- real client rate card supplied for this tenant. Purely additive: only inserts into
-- core's tenant-editable tables, no core schema changes.
do $$
declare
  v_company_id uuid;
  v_candid_photo_id uuid;
  v_candid_video_id uuid;
  v_trad_photo_id uuid;
  v_trad_video_id uuid;
  v_editing_id uuid;
  v_prewedding_id uuid;
  v_candid_photo_12hr uuid;
  v_candid_video_12hr uuid;
  v_drone_addon_id uuid;
  v_combo_package_id uuid;
begin
  insert into companies (name, industry_code, timezone, default_currency)
  values ('Sample Wedding Photography Co.', 'wedding_photography', 'Asia/Kolkata', 'INR')
  returning id into v_company_id;

  -- Services
  insert into services (name, requires_resource_type_code, category) values
    ('Candid Photographer', 'staff', 'photography') returning id into v_candid_photo_id;
  insert into services (name, requires_resource_type_code, category) values
    ('Candid Videographer', 'staff', 'videography') returning id into v_candid_video_id;
  insert into services (name, requires_resource_type_code, category) values
    ('Traditional Photographer', 'staff', 'photography') returning id into v_trad_photo_id;
  insert into services (name, requires_resource_type_code, category) values
    ('Traditional Videographer', 'staff', 'videography') returning id into v_trad_video_id;
  insert into services (name, category) values
    ('Editing', 'post_production') returning id into v_editing_id;
  insert into services (name, category) values
    ('Pre-Wedding Shoot', 'photography') returning id into v_prewedding_id;

  -- Rate cards: each 2-person team service gets 12hr / 5hr / 24hr tiers
  insert into rate_cards (service_id, tier_label, duration_minutes, price) values
    (v_candid_photo_id, '12hr', 720, 10000),
    (v_candid_photo_id, '5hr', 300, 8000),
    (v_candid_photo_id, '24hr', 1440, 15000);
  select id into v_candid_photo_12hr from rate_cards where service_id = v_candid_photo_id and tier_label = '12hr';

  insert into rate_cards (service_id, tier_label, duration_minutes, price) values
    (v_candid_video_id, '12hr', 720, 10000),
    (v_candid_video_id, '5hr', 300, 8000),
    (v_candid_video_id, '24hr', 1440, 15000);
  select id into v_candid_video_12hr from rate_cards where service_id = v_candid_video_id and tier_label = '12hr';

  insert into rate_cards (service_id, tier_label, duration_minutes, price) values
    (v_trad_photo_id, '12hr', 720, 7000),
    (v_trad_photo_id, '5hr', 300, 5000),
    (v_trad_photo_id, '24hr', 1440, 10000);

  insert into rate_cards (service_id, tier_label, duration_minutes, price) values
    (v_trad_video_id, '12hr', 720, 7000),
    (v_trad_video_id, '5hr', 300, 5000),
    (v_trad_video_id, '24hr', 1440, 10000);

  -- Editing: flat minimum price
  insert into rate_cards (service_id, tier_label, duration_minutes, price) values
    (v_editing_id, 'flat_minimum', 60, 5000);

  -- Pre-wedding shoot: flat per-day price
  insert into rate_cards (service_id, tier_label, duration_minutes, price) values
    (v_prewedding_id, 'flat_day', 1440, 35000);

  -- Addons
  insert into addons (name, price) values ('Drone', 5000) returning id into v_drone_addon_id;

  -- Package: full-day combo (2 photographers + 2 videographers, 12hr, Delhi NCR) at a
  -- flat override price that intentionally does not equal the sum of its parts.
  insert into packages (name, description, package_price) values
    ('Full Day Combo (2 Photographers + 2 Videographers, 12hr, Delhi NCR)',
     '2 Candid Photographers + 2 Candid Videographers for a 12 hour wedding event in Delhi NCR.',
     85000)
    returning id into v_combo_package_id;

  insert into package_items (package_id, service_id, quantity, rate_card_id) values
    (v_combo_package_id, v_candid_photo_id, 2, v_candid_photo_12hr),
    (v_combo_package_id, v_candid_video_id, 2, v_candid_video_12hr);

  -- Slot definitions: wedding/pre-wedding events are full_day or half_day bookings.
  insert into slot_definitions (service_id, event_kind, duration_minutes) values
    (null, 'full_day', 1440); -- generic 24hr event slot (e.g. pre-wedding, full wedding day)
  insert into slot_definitions (service_id, event_kind, duration_minutes) values
    (null, 'half_day', 720); -- 12hr half-day event slot
  insert into slot_definitions (service_id, event_kind, duration_minutes) values
    (null, 'half_day', 300); -- 5hr half-day event slot
end $$;

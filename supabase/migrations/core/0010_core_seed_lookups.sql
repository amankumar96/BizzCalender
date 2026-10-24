-- Core: lookup seed data common to every tenant project.
insert into roles (code, label) values
  ('admin', 'Admin'),
  ('sales', 'Sales'),
  ('staff', 'Staff');

insert into resource_types (code, label) values
  ('staff', 'Staff Member'),
  ('equipment', 'Equipment'),
  ('room', 'Room');

-- Default working hours: Mon-Sat 09:00-18:00, Sunday closed. Admin can edit any time.
insert into working_hours_templates (weekday, opens_at, closes_at, is_working_day) values
  (0, '09:00', '18:00', false), -- Sunday
  (1, '09:00', '18:00', true),
  (2, '09:00', '18:00', true),
  (3, '09:00', '18:00', true),
  (4, '09:00', '18:00', true),
  (5, '09:00', '18:00', true),
  (6, '09:00', '18:00', true);

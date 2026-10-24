-- Wedding Photography industry extension: deliverable catalog.
-- Purely additive seed data into the core deliverable_types table -- no schema changes.
insert into deliverable_types (name, default_price, is_active) values
  ('Album', 10000, true),
  ('Teaser (1 min)', null, true),
  ('Trailer (5 min)', null, true),
  ('Long Video (edited)', null, true),
  ('Instagram Reel', null, true),
  ('Wedding Invitation', null, true),
  ('Edited Photos', null, true),
  ('Unlimited Raw (customer-provided hard drive)', null, true),
  ('Photo Link URLs', null, true);

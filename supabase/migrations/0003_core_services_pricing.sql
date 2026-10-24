-- Core: services catalog, duration-tiered rate cards, addons, and flat-override packages.
create table services (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  requires_resource_type_code text references resource_types(code) on delete set null,
  category text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table rate_cards (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references services(id) on delete cascade,
  tier_label text not null,
  duration_minutes int not null check (duration_minutes > 0),
  price numeric(12,2) not null check (price >= 0),
  currency text not null default 'INR',
  valid_from date not null default current_date,
  valid_to date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint chk_rate_card_validity check (valid_to is null or valid_to >= valid_from)
);

create table addons (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  price numeric(12,2) not null check (price >= 0),
  currency text not null default 'INR',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table packages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  package_price numeric(12,2) not null check (package_price >= 0),
  currency text not null default 'INR',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table package_items (
  id uuid primary key default gen_random_uuid(),
  package_id uuid not null references packages(id) on delete cascade,
  service_id uuid not null references services(id) on delete restrict,
  quantity int not null default 1 check (quantity > 0),
  rate_card_id uuid references rate_cards(id) on delete set null
);

create index idx_rate_cards_service on rate_cards(service_id);
create index idx_package_items_package on package_items(package_id);

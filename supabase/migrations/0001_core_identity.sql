-- Core: identity & org. Shared across every tenant project regardless of industry.
create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create table companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  industry_code text not null,
  timezone text not null default 'Asia/Kolkata',
  default_currency text not null default 'INR',
  created_at timestamptz not null default now()
);

create table staff_users (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  email text,
  status text not null default 'active' check (status in ('active', 'disabled')),
  created_at timestamptz not null default now()
);

create table roles (
  code text primary key,
  label text not null
);

create table staff_user_roles (
  staff_user_id uuid not null references staff_users(id) on delete cascade,
  role_code text not null references roles(code) on delete restrict,
  primary key (staff_user_id, role_code)
);

create table customers (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  full_name text not null,
  phone text not null unique,
  email text,
  created_by_staff_id uuid references staff_users(id) on delete set null,
  notes text,
  created_at timestamptz not null default now()
);

create index idx_customers_auth_user_id on customers(auth_user_id);
create index idx_staff_user_roles_staff_user_id on staff_user_roles(staff_user_id);

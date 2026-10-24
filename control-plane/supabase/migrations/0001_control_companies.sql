-- Control plane: registry of every tenant company -> its dedicated Supabase project.
-- This is its own separate, minimal Supabase project (not a tenant project).
create extension if not exists pgcrypto;

create table control_companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  industry_code text not null,
  supabase_project_url text not null,
  supabase_anon_key text not null,
  supabase_service_role_key_secret_ref text not null, -- reference into a secrets manager/Vault, never the raw key
  status text not null default 'provisioning' check (status in ('provisioning', 'active', 'suspended', 'cancelled')),
  subscription_plan text,
  subscription_renews_at date,
  created_at timestamptz not null default now()
);

create table control_company_admins (
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references control_companies(id) on delete cascade,
  primary key (auth_user_id, company_id)
);

alter table control_companies enable row level security;
alter table control_company_admins enable row level security;

-- A logged-in admin can only see companies they are linked to via control_company_admins.
create policy control_companies_admin_read on control_companies for select using (
  exists (
    select 1 from control_company_admins a
    where a.company_id = control_companies.id and a.auth_user_id = auth.uid()
  )
);

create policy control_company_admins_self_read on control_company_admins for select using (auth_user_id = auth.uid());

-- All writes (provisioning, status changes) go through the company_onboarding_bootstrap
-- Edge Function using the service role -- no direct client insert/update policy.

-- Core: pluggable payment ledger. 'provider' is free text so no single gateway is
-- hardcoded (razorpay/stripe/offline_cash/offline_upi/...). booking_id is nullable so
-- an offline advance can be recorded against a lead before a booking formally exists.
create table payment_transactions (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references bookings(id) on delete set null,
  lead_id uuid references leads(id) on delete set null,
  provider text not null,
  provider_reference text,
  recorded_by_staff_id uuid references staff_users(id) on delete set null, -- set for staff-recorded offline payments
  amount numeric(12,2) not null check (amount >= 0),
  currency text not null default 'INR',
  status text not null default 'created' check (status in ('created', 'pending', 'succeeded', 'failed', 'refunded')),
  direction text not null default 'charge' check (direction in ('charge', 'refund')),
  raw_payload jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table payment_webhooks_log (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  event_id text not null,
  payload jsonb not null,
  processed_at timestamptz,
  received_at timestamptz not null default now(),
  unique (provider, event_id)
);

alter table leads add constraint fk_leads_advance_payment foreign key (advance_payment_transaction_id) references payment_transactions(id) on delete set null;

create index idx_payment_transactions_booking on payment_transactions(booking_id);
create index idx_payment_transactions_lead on payment_transactions(lead_id);

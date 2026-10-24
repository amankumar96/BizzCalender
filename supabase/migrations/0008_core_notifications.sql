-- Core: outbound notification queue (SMS/push/WhatsApp/email), dispatched by an Edge Function.
create table notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_type text not null check (recipient_type in ('customer', 'staff')),
  recipient_id uuid not null,
  channel text not null check (channel in ('push', 'sms', 'email', 'whatsapp')),
  template_code text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued', 'sent', 'failed')),
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index idx_notifications_recipient on notifications(recipient_type, recipient_id);
create index idx_notifications_status on notifications(status);

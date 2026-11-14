-- 0004_invitations_activity.sql
-- Запрошення та універсальний журнал подій.

create table public.invitations (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references public.companies (id) on delete cascade,
  object_id       uuid,
  email           text not null check (email = lower(btrim(email)) and char_length(email) between 3 and 254),
  company_role    public.company_role,
  object_role     public.object_role,
  invited_by      uuid references public.profiles (id) on delete set null,
  -- Зберігається лише SHA-256 хеш токена; сам токен показується один раз при створенні.
  token_hash      text not null unique,
  status          public.invitation_status not null default 'pending',
  expires_at      timestamptz not null,
  last_issued_at  timestamptz not null default now(),
  accepted_by     uuid references public.profiles (id) on delete set null,
  accepted_at     timestamptz,
  revoked_at      timestamptz,
  -- Фактичне надсилання листів на етапі 1 НЕ реалізоване: delivery_status лишається 'not_sent'.
  delivery_status text not null default 'not_sent' check (delivery_status in ('not_sent', 'sent', 'failed')),
  email_sent_at   timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  foreign key (object_id, company_id)
    references public.construction_objects (id, company_id) on delete cascade,
  check (company_role is not null or object_role is not null),
  check (company_role is distinct from 'owner'),
  check (object_role is null or object_id is not null)
);

-- Не більше одного активного запрошення на (компанія, об'єкт, email).
create unique index invitations_one_pending_idx
  on public.invitations (company_id, coalesce(object_id, '00000000-0000-0000-0000-000000000000'::uuid), email)
  where status = 'pending';
create index invitations_company_idx on public.invitations (company_id, created_at desc);
create index invitations_object_idx on public.invitations (object_id);
create index invitations_email_idx on public.invitations (email);

create trigger invitations_set_updated_at
  before update on public.invitations
  for each row execute function public.set_updated_at();

-- Універсальний append-only журнал подій. Модулі Measure/Tools/Workforce
-- писатимуть сюди з відповідним module.
create table public.activity_log (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies (id) on delete cascade,
  object_id   uuid,
  actor_id    uuid references public.profiles (id) on delete set null,
  module      text not null default 'platform' check (module in ('platform', 'measure', 'tools', 'workforce')),
  action      text not null check (char_length(action) between 1 and 80),
  entity_type text not null check (char_length(entity_type) between 1 and 80),
  entity_id   uuid,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  foreign key (object_id, company_id)
    references public.construction_objects (id, company_id) on delete cascade
);

create index activity_log_company_created_idx on public.activity_log (company_id, created_at desc);
create index activity_log_object_created_idx on public.activity_log (object_id, created_at desc);

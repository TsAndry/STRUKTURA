-- 0003_objects.sql
-- Будівельні об'єкти та їхні учасники.
-- Усі майбутні модулі (Measure, Tools, Workforce) посилаються на construction_objects.id.

create table public.construction_objects (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references public.companies (id) on delete restrict,
  name             text not null check (char_length(btrim(name)) between 2 and 160),
  type             public.object_type not null default 'apartment',
  address          text check (address is null or char_length(address) <= 300),
  description      text check (description is null or char_length(description) <= 4000),
  status           public.object_status not null default 'planned',
  start_date       date,
  planned_end_date date,
  foreman_id       uuid references public.profiles (id) on delete set null,
  created_by       uuid references public.profiles (id) on delete set null,
  archived_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (start_date is null or planned_end_date is null or planned_end_date >= start_date),
  -- Потрібно для складених зовнішніх ключів, які унеможливлюють підміну company_id.
  unique (id, company_id)
);

create index construction_objects_company_status_idx
  on public.construction_objects (company_id, status);
create index construction_objects_company_created_idx
  on public.construction_objects (company_id, created_at desc);
create index construction_objects_foreman_idx
  on public.construction_objects (foreman_id);

create trigger construction_objects_set_updated_at
  before update on public.construction_objects
  for each row execute function public.set_updated_at();

create table public.object_members (
  id         uuid primary key default gen_random_uuid(),
  object_id  uuid not null,
  company_id uuid not null,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role       public.object_role not null,
  added_by   uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Складений ключ: object_id і company_id завжди узгоджені на рівні БД.
  foreign key (object_id, company_id)
    references public.construction_objects (id, company_id) on delete cascade,
  -- Етап 1: одна роль користувача на одному об'єкті (див. D-006).
  unique (object_id, user_id)
);

create index object_members_user_id_idx on public.object_members (user_id);
create index object_members_company_id_idx on public.object_members (company_id);

create trigger object_members_set_updated_at
  before update on public.object_members
  for each row execute function public.set_updated_at();

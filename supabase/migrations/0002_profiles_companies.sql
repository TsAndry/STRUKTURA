-- 0002_profiles_companies.sql
-- Профілі користувачів, компанії, членство в компаніях.

-- ---------------------------------------------------------------- profiles
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  first_name    text not null default '' check (char_length(first_name) <= 100),
  last_name     text not null default '' check (char_length(last_name) <= 100),
  email         text not null default '' check (char_length(email) <= 254),
  phone         text check (phone is null or char_length(phone) <= 32),
  avatar_url    text check (avatar_url is null or char_length(avatar_url) <= 2048),
  platform_role public.platform_role not null default 'user',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Профіль створюється автоматично при реєстрації в Supabase Auth.
-- platform_role НІКОЛИ не береться з raw_user_meta_data (її контролює користувач).
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, first_name, last_name, phone)
  values (
    new.id,
    coalesce(new.email, ''),
    left(coalesce(btrim(new.raw_user_meta_data ->> 'first_name'), ''), 100),
    left(coalesce(btrim(new.raw_user_meta_data ->> 'last_name'), ''), 100),
    left(nullif(btrim(new.raw_user_meta_data ->> 'phone'), ''), 32)
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.handle_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set email = coalesce(new.email, '') where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row
  when (old.email is distinct from new.email)
  execute function public.handle_user_email_change();

-- --------------------------------------------------------------- companies
create table public.companies (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 2 and 120),
  description text check (description is null or char_length(description) <= 2000),
  logo_url    text check (logo_url is null or char_length(logo_url) <= 2048),
  phone       text check (phone is null or char_length(phone) <= 32),
  email       text check (email is null or char_length(email) <= 254),
  address     text check (address is null or char_length(address) <= 300),
  status      public.company_status not null default 'active',
  owner_id    uuid not null references public.profiles (id) on delete restrict,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index companies_owner_id_idx on public.companies (owner_id);

create trigger companies_set_updated_at
  before update on public.companies
  for each row execute function public.set_updated_at();

-- --------------------------------------------------------- company_members
create table public.company_members (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role       public.company_role not null,
  invited_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, user_id)
);

-- Рівно один власник на компанію.
create unique index company_members_single_owner_idx
  on public.company_members (company_id) where role = 'owner';
create index company_members_user_id_idx on public.company_members (user_id);

create trigger company_members_set_updated_at
  before update on public.company_members
  for each row execute function public.set_updated_at();

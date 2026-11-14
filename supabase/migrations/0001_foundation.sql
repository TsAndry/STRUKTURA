-- 0001_foundation.sql
-- Розширення, перелічувані типи (enum) та спільні службові функції.

create extension if not exists pgcrypto with schema extensions;

-- Ролі рівня платформи. super_admin зарезервований: на етапі 1 не дає неявного
-- доступу до даних компаній (див. docs/DECISIONS.md, D-007).
create type public.platform_role as enum ('super_admin', 'user');

-- Ролі рівня компанії.
create type public.company_role as enum (
  'owner',          -- власник компанії (рівно один на компанію)
  'admin',          -- адміністратор
  'foreman',        -- прораб
  'senior_worker',  -- старший працівник
  'worker',         -- працівник
  'surveyor',       -- замірник
  'designer',       -- проєктувальник
  'tool_keeper'     -- відповідальний за інструмент
);

-- Ролі рівня об'єкта. property_owner = власник НЕРУХОМОСТІ (замовник),
-- це НЕ те саме, що company_role 'owner' (власник компанії).
create type public.object_role as enum (
  'object_manager',  -- керівник об'єкта
  'foreman',         -- прораб
  'worker',          -- працівник
  'surveyor',        -- замірник
  'designer',        -- проєктувальник
  'property_owner',  -- власник нерухомості / замовник
  'intermediary'     -- посередник
);

create type public.company_status    as enum ('active', 'suspended', 'archived');
create type public.object_status     as enum ('planned', 'active', 'paused', 'completed', 'archived');
create type public.object_type       as enum ('apartment', 'house', 'office', 'commercial', 'building', 'other');
create type public.invitation_status as enum ('pending', 'accepted', 'revoked', 'expired');

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

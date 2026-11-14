-- 0006_rls_policies_and_grants.sql
-- RLS і привілеї на рівні стовпців. Принцип: клієнти (anon/authenticated) мають
-- мінімум прав; усі «чутливі» зміни (членство, ролі, запрошення, створення
-- компанії/об'єкта, журнал) виконуються лише через RPC-функції (див. 0008, 0009).

-- ------------------------------------------------------ privileges: tables
revoke all on public.profiles            from anon, authenticated;
revoke all on public.companies           from anon, authenticated;
revoke all on public.company_members     from anon, authenticated;
revoke all on public.construction_objects from anon, authenticated;
revoke all on public.object_members      from anon, authenticated;
revoke all on public.invitations         from anon, authenticated;
revoke all on public.activity_log        from anon, authenticated;

grant select on public.profiles, public.companies, public.company_members,
                public.construction_objects, public.object_members,
                public.activity_log
  to authenticated;

-- invitations: стовпець token_hash клієнтам не віддається взагалі.
grant select (id, company_id, object_id, email, company_role, object_role, invited_by,
              status, expires_at, last_issued_at, accepted_by, accepted_at, revoked_at,
              delivery_status, email_sent_at, created_at, updated_at)
  on public.invitations to authenticated;

-- Оновлення лише дозволених стовпців. platform_role, email, owner_id, status компанії,
-- company_id, created_by тощо через API змінити неможливо.
grant update (first_name, last_name, phone, avatar_url) on public.profiles to authenticated;
grant update (name, description, logo_url, phone, email, address) on public.companies to authenticated;
grant update (name, type, address, description, status, start_date, planned_end_date, foreman_id)
  on public.construction_objects to authenticated;

-- --------------------------------------------------------------------- RLS
alter table public.profiles             enable row level security;
alter table public.companies            enable row level security;
alter table public.company_members      enable row level security;
alter table public.construction_objects enable row level security;
alter table public.object_members       enable row level security;
alter table public.invitations          enable row level security;
alter table public.activity_log         enable row level security;

-- profiles
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.shares_context_with(id));

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- companies
create policy companies_select on public.companies
  for select to authenticated
  using (public.has_company_access(id));

create policy companies_update on public.companies
  for update to authenticated
  using (public.is_company_admin(id))
  with check (public.is_company_admin(id));

-- company_members (лише читання; зміни тільки через RPC)
create policy company_members_select on public.company_members
  for select to authenticated
  using (public.is_company_member(company_id));

-- construction_objects (створення — лише через create_object; видалення заборонено, є архівування)
create policy construction_objects_select on public.construction_objects
  for select to authenticated
  using (public.is_company_admin(company_id) or public.is_object_member(id));

create policy construction_objects_update on public.construction_objects
  for update to authenticated
  using (public.can_manage_object(id))
  with check (public.can_manage_object(id));

-- object_members (лише читання; зміни тільки через RPC)
create policy object_members_select on public.object_members
  for select to authenticated
  using (public.can_access_object(object_id));

-- invitations (лише читання тим, хто може ними керувати)
create policy invitations_select on public.invitations
  for select to authenticated
  using (
    public.is_company_admin(company_id)
    or (object_id is not null and public.can_manage_object(object_id))
  );

-- activity_log (append-only, запис лише через log_activity)
create policy activity_log_select on public.activity_log
  for select to authenticated
  using (
    (object_id is null and public.is_company_member(company_id))
    or (object_id is not null and public.can_access_object(object_id))
  );

-- ------------------------------------------------- privileges: functions
-- Supabase за замовчуванням видає EXECUTE ролям anon/authenticated на нові функції.
-- Спочатку забираємо, потім видаємо точково.
revoke all on function public.current_company_role(uuid)   from public, anon, authenticated;
revoke all on function public.is_company_member(uuid)      from public, anon, authenticated;
revoke all on function public.is_company_admin(uuid)       from public, anon, authenticated;
revoke all on function public.is_object_member(uuid)       from public, anon, authenticated;
revoke all on function public.has_company_access(uuid)     from public, anon, authenticated;
revoke all on function public.can_access_object(uuid)      from public, anon, authenticated;
revoke all on function public.can_manage_object(uuid)      from public, anon, authenticated;
revoke all on function public.shares_context_with(uuid)    from public, anon, authenticated;
revoke all on function public.log_activity(uuid, uuid, uuid, text, text, text, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.can_issue_invitation(uuid, uuid, public.company_role, public.object_role)
  from public, anon, authenticated;
revoke all on function public.handle_new_user()         from public, anon, authenticated;
revoke all on function public.handle_user_email_change() from public, anon, authenticated;

-- Функції, що використовуються в політиках RLS, виконуються від імені користувача,
-- тому authenticated потребує EXECUTE на них (вони повертають лише булеве значення
-- про самого викликача).
grant execute on function public.current_company_role(uuid)  to authenticated;
grant execute on function public.is_company_member(uuid)     to authenticated;
grant execute on function public.is_company_admin(uuid)      to authenticated;
grant execute on function public.is_object_member(uuid)      to authenticated;
grant execute on function public.has_company_access(uuid)    to authenticated;
grant execute on function public.can_access_object(uuid)     to authenticated;
grant execute on function public.can_manage_object(uuid)     to authenticated;
grant execute on function public.shares_context_with(uuid)   to authenticated;

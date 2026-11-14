-- 0008_rpc_companies_objects_members.sql
-- Захищені серверні операції (RPC). Усі — SECURITY DEFINER, з явною перевіркою
-- auth.uid() і прав викликача. Коди помилок описано в docs/DATABASE.md.

-- ----------------------------------------------------------- create_company
-- Атомарно: створює компанію + членство власника + запис у журналі.
create function public.create_company(
  p_name        text,
  p_description text default null,
  p_phone       text default null,
  p_email       text default null,
  p_address     text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_name text := btrim(coalesce(p_name, ''));
  v_id   uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 120 then
    raise exception 'invalid_company_name' using errcode = '22023';
  end if;
  if (select count(*) from public.companies c where c.owner_id = v_uid) >= 10 then
    raise exception 'company_limit_reached' using errcode = '54000';
  end if;

  insert into public.companies (name, description, phone, email, address, owner_id)
  values (
    v_name,
    nullif(btrim(p_description), ''),
    nullif(btrim(p_phone), ''),
    nullif(btrim(p_email), ''),
    nullif(btrim(p_address), ''),
    v_uid
  )
  returning id into v_id;

  insert into public.company_members (company_id, user_id, role)
  values (v_id, v_uid, 'owner');

  perform public.log_activity(v_id, null, v_uid, 'platform', 'company.created', 'company', v_id,
                              jsonb_build_object('name', v_name));
  return v_id;
end;
$$;

-- ------------------------------------------------------------- create_object
create function public.create_object(
  p_company_id       uuid,
  p_name             text,
  p_type             public.object_type default 'apartment',
  p_address          text default null,
  p_description      text default null,
  p_status           public.object_status default 'planned',
  p_start_date       date default null,
  p_planned_end_date date default null,
  p_foreman_id       uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_role public.company_role;
  v_name text := btrim(coalesce(p_name, ''));
  v_id   uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  v_role := public.current_company_role(p_company_id);
  if v_role is null or v_role not in ('owner', 'admin', 'foreman') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 160 then
    raise exception 'invalid_object_name' using errcode = '22023';
  end if;
  if p_status = 'archived' then
    raise exception 'invalid_initial_status' using errcode = '22023';
  end if;

  insert into public.construction_objects
    (company_id, name, type, address, description, status, start_date, planned_end_date, foreman_id, created_by)
  values
    (p_company_id, v_name, p_type, nullif(btrim(p_address), ''), nullif(btrim(p_description), ''),
     p_status, p_start_date, p_planned_end_date, p_foreman_id, v_uid)
  returning id into v_id;

  -- Прораб компанії, що створив об'єкт, одразу отримує керування ним.
  if v_role not in ('owner', 'admin') then
    insert into public.object_members (object_id, company_id, user_id, role, added_by)
    values (v_id, p_company_id, v_uid, 'object_manager', v_uid)
    on conflict (object_id, user_id) do nothing;
  end if;

  perform public.log_activity(p_company_id, v_id, v_uid, 'platform', 'object.created',
                              'construction_object', v_id, jsonb_build_object('name', v_name));
  return v_id;
end;
$$;

-- ------------------------------------------------- update_company_member_role
create function public.update_company_member_role(
  p_company_id uuid,
  p_user_id    uuid,
  p_role       public.company_role
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := (select auth.uid());
  v_caller_role public.company_role;
  v_target_role public.company_role;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  v_caller_role := public.current_company_role(p_company_id);
  if v_caller_role is null or v_caller_role not in ('owner', 'admin') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select cm.role into v_target_role
  from public.company_members cm
  where cm.company_id = p_company_id and cm.user_id = p_user_id
  for update;

  if v_target_role is null then
    raise exception 'member_not_found' using errcode = 'P0002';
  end if;
  if p_role = 'owner' or v_target_role = 'owner' then
    raise exception 'owner_role_immutable' using errcode = '42501';
  end if;
  if p_user_id = v_uid then
    raise exception 'cannot_change_own_role' using errcode = '42501';
  end if;
  if (p_role = 'admin' or v_target_role = 'admin') and v_caller_role <> 'owner' then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  update public.company_members set role = p_role
  where company_id = p_company_id and user_id = p_user_id;

  perform public.log_activity(p_company_id, null, v_uid, 'platform', 'member.role_changed',
                              'company_member', p_user_id,
                              jsonb_build_object('from', v_target_role, 'to', p_role));
end;
$$;

-- ----------------------------------------------------- remove_company_member
create function public.remove_company_member(
  p_company_id uuid,
  p_user_id    uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := (select auth.uid());
  v_caller_role public.company_role;
  v_target_role public.company_role;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  v_caller_role := public.current_company_role(p_company_id);
  if v_caller_role is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select cm.role into v_target_role
  from public.company_members cm
  where cm.company_id = p_company_id and cm.user_id = p_user_id
  for update;

  if v_target_role is null then
    raise exception 'member_not_found' using errcode = 'P0002';
  end if;
  if v_target_role = 'owner' then
    raise exception 'owner_role_immutable' using errcode = '42501';
  end if;

  if p_user_id <> v_uid then
    if v_caller_role not in ('owner', 'admin') then
      raise exception 'forbidden' using errcode = '42501';
    end if;
    if v_target_role = 'admin' and v_caller_role <> 'owner' then
      raise exception 'forbidden' using errcode = '42501';
    end if;
  end if;

  -- Внутрішні ролі на об'єктах компанії втрачаються разом із членством.
  update public.construction_objects set foreman_id = null
  where company_id = p_company_id and foreman_id = p_user_id;

  delete from public.object_members
  where company_id = p_company_id and user_id = p_user_id
    and role in ('object_manager', 'foreman', 'worker', 'surveyor', 'designer');

  delete from public.company_members
  where company_id = p_company_id and user_id = p_user_id;

  perform public.log_activity(p_company_id, null, v_uid, 'platform', 'member.removed',
                              'company_member', p_user_id, jsonb_build_object('role', v_target_role));
end;
$$;

-- ------------------------------------------------------------ add_object_member
-- Додає ІСНУЮЧОГО учасника компанії до об'єкта. Зовнішні ролі
-- (property_owner, intermediary) призначаються лише через запрошення.
create function public.add_object_member(
  p_object_id uuid,
  p_user_id   uuid,
  p_role      public.object_role
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_company uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.can_manage_object(p_object_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select o.company_id into v_company from public.construction_objects o where o.id = p_object_id;

  if p_role in ('property_owner', 'intermediary') then
    raise exception 'use_invitation_for_external_roles' using errcode = '22023';
  end if;
  if p_role = 'object_manager' and not public.is_company_admin(v_company) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.company_members cm
    where cm.company_id = v_company and cm.user_id = p_user_id
  ) then
    raise exception 'target_not_company_member' using errcode = '22023';
  end if;

  insert into public.object_members (object_id, company_id, user_id, role, added_by)
  values (p_object_id, v_company, p_user_id, p_role, v_uid)
  on conflict (object_id, user_id) do nothing;

  if not found then
    raise exception 'already_object_member' using errcode = '23505';
  end if;

  perform public.log_activity(v_company, p_object_id, v_uid, 'platform', 'member.added',
                              'object_member', p_user_id, jsonb_build_object('role', p_role));
end;
$$;

-- ------------------------------------------------- update_object_member_role
create function public.update_object_member_role(
  p_object_id uuid,
  p_user_id   uuid,
  p_role      public.object_role
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_company   uuid;
  v_old_role  public.object_role;
  v_is_admin  boolean;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.can_manage_object(p_object_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select o.company_id into v_company from public.construction_objects o where o.id = p_object_id;
  v_is_admin := public.is_company_admin(v_company);

  select om.role into v_old_role
  from public.object_members om
  where om.object_id = p_object_id and om.user_id = p_user_id
  for update;

  if v_old_role is null then
    raise exception 'member_not_found' using errcode = 'P0002';
  end if;
  if p_role in ('property_owner', 'intermediary') or v_old_role in ('property_owner', 'intermediary') then
    raise exception 'external_role_immutable' using errcode = '22023';
  end if;
  if (p_role = 'object_manager' or v_old_role = 'object_manager') and not v_is_admin then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_user_id = v_uid and not v_is_admin then
    raise exception 'cannot_change_own_role' using errcode = '42501';
  end if;

  update public.object_members set role = p_role
  where object_id = p_object_id and user_id = p_user_id;

  perform public.log_activity(v_company, p_object_id, v_uid, 'platform', 'member.role_changed',
                              'object_member', p_user_id,
                              jsonb_build_object('from', v_old_role, 'to', p_role));
end;
$$;

-- ------------------------------------------------------ remove_object_member
create function public.remove_object_member(
  p_object_id uuid,
  p_user_id   uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := (select auth.uid());
  v_company  uuid;
  v_old_role public.object_role;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.can_manage_object(p_object_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select o.company_id into v_company from public.construction_objects o where o.id = p_object_id;

  select om.role into v_old_role
  from public.object_members om
  where om.object_id = p_object_id and om.user_id = p_user_id
  for update;

  if v_old_role is null then
    raise exception 'member_not_found' using errcode = 'P0002';
  end if;
  if v_old_role = 'object_manager' and not public.is_company_admin(v_company) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  update public.construction_objects set foreman_id = null
  where id = p_object_id and foreman_id = p_user_id;

  delete from public.object_members where object_id = p_object_id and user_id = p_user_id;

  perform public.log_activity(v_company, p_object_id, v_uid, 'platform', 'member.removed',
                              'object_member', p_user_id, jsonb_build_object('role', v_old_role));
end;
$$;

-- -------------------------------------------------------------------- grants
revoke all on function public.create_company(text, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.create_object(uuid, text, public.object_type, text, text, public.object_status, date, date, uuid)
  from public, anon, authenticated;
revoke all on function public.update_company_member_role(uuid, uuid, public.company_role)
  from public, anon, authenticated;
revoke all on function public.remove_company_member(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.add_object_member(uuid, uuid, public.object_role)
  from public, anon, authenticated;
revoke all on function public.update_object_member_role(uuid, uuid, public.object_role)
  from public, anon, authenticated;
revoke all on function public.remove_object_member(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.create_company(text, text, text, text, text) to authenticated;
grant execute on function public.create_object(uuid, text, public.object_type, text, text, public.object_status, date, date, uuid) to authenticated;
grant execute on function public.update_company_member_role(uuid, uuid, public.company_role) to authenticated;
grant execute on function public.remove_company_member(uuid, uuid) to authenticated;
grant execute on function public.add_object_member(uuid, uuid, public.object_role) to authenticated;
grant execute on function public.update_object_member_role(uuid, uuid, public.object_role) to authenticated;
grant execute on function public.remove_object_member(uuid, uuid) to authenticated;

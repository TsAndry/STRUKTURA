-- 0005_helper_functions.sql
-- Централізовані перевірки дозволів. SECURITY DEFINER потрібен, щоб політики RLS
-- не рекурсували самі в себе; усі функції залежать лише від auth.uid() викликача.

create function public.current_company_role(p_company_id uuid)
returns public.company_role
language sql stable security definer set search_path = ''
as $$
  select cm.role
  from public.company_members cm
  where cm.company_id = p_company_id and cm.user_id = (select auth.uid());
$$;

create function public.is_company_member(p_company_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.company_members cm
    where cm.company_id = p_company_id and cm.user_id = (select auth.uid())
  );
$$;

-- Власник або адміністратор компанії.
create function public.is_company_admin(p_company_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.company_members cm
    where cm.company_id = p_company_id
      and cm.user_id = (select auth.uid())
      and cm.role in ('owner', 'admin')
  );
$$;

create function public.is_object_member(p_object_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.object_members om
    where om.object_id = p_object_id and om.user_id = (select auth.uid())
  );
$$;

-- Бачити компанію можуть її учасники та зовнішні учасники її об'єктів
-- (наприклад, власник нерухомості), щоб показати назву компанії.
create function public.has_company_access(p_company_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_company_member(p_company_id)
      or exists (
        select 1 from public.object_members om
        where om.company_id = p_company_id and om.user_id = (select auth.uid())
      );
$$;

-- Доступ до об'єкта: власник/адміністратор компанії або учасник об'єкта.
create function public.can_access_object(p_object_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.construction_objects o
    where o.id = p_object_id
      and (
        exists (
          select 1 from public.company_members cm
          where cm.company_id = o.company_id
            and cm.user_id = (select auth.uid())
            and cm.role in ('owner', 'admin')
        )
        or exists (
          select 1 from public.object_members om
          where om.object_id = o.id and om.user_id = (select auth.uid())
        )
      )
  );
$$;

-- Керування об'єктом: власник/адміністратор компанії або керівник/прораб цього об'єкта.
create function public.can_manage_object(p_object_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.construction_objects o
    where o.id = p_object_id
      and (
        exists (
          select 1 from public.company_members cm
          where cm.company_id = o.company_id
            and cm.user_id = (select auth.uid())
            and cm.role in ('owner', 'admin')
        )
        or exists (
          select 1 from public.object_members om
          where om.object_id = o.id
            and om.user_id = (select auth.uid())
            and om.role in ('object_manager', 'foreman')
        )
      )
  );
$$;

-- Чи має поточний користувач спільний контекст (компанія або об'єкт) з іншим користувачем.
-- Використовується для видимості профілів.
create function public.shares_context_with(p_target uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select
    exists (
      select 1
      from public.company_members me
      join public.company_members other on other.company_id = me.company_id
      where me.user_id = (select auth.uid()) and other.user_id = p_target
    )
    or exists (
      select 1
      from public.object_members me
      join public.object_members other on other.object_id = me.object_id
      where me.user_id = (select auth.uid()) and other.user_id = p_target
    )
    or exists (
      -- власник/адміністратор компанії бачить зовнішніх учасників об'єктів своєї компанії
      select 1
      from public.company_members me
      join public.object_members other on other.company_id = me.company_id
      where me.user_id = (select auth.uid())
        and me.role in ('owner', 'admin')
        and other.user_id = p_target
    )
    or exists (
      -- учасник об'єкта (зокрема замовник) бачить керівництво компанії-підрядника
      select 1
      from public.object_members me
      join public.company_members mgmt on mgmt.company_id = me.company_id
      where me.user_id = (select auth.uid())
        and mgmt.role in ('owner', 'admin')
        and mgmt.user_id = p_target
    );
$$;

-- Внутрішній запис у журнал подій. Клієнтам недоступний (див. 0006).
create function public.log_activity(
  p_company_id  uuid,
  p_object_id   uuid,
  p_actor_id    uuid,
  p_module      text,
  p_action      text,
  p_entity_type text,
  p_entity_id   uuid,
  p_metadata    jsonb default '{}'::jsonb
)
returns void
language sql security definer set search_path = ''
as $$
  insert into public.activity_log
    (company_id, object_id, actor_id, module, action, entity_type, entity_id, metadata)
  values
    (p_company_id, p_object_id, p_actor_id, p_module, p_action, p_entity_type, p_entity_id, coalesce(p_metadata, '{}'::jsonb));
$$;

-- Чи може поточний користувач видавати/перевидавати/відкликати таке запрошення.
create function public.can_issue_invitation(
  p_company_id   uuid,
  p_object_id    uuid,
  p_company_role public.company_role,
  p_object_role  public.object_role
)
returns boolean
language plpgsql stable security definer set search_path = ''
as $$
begin
  if p_company_role is not null then
    if not public.is_company_admin(p_company_id) then return false; end if;
    if p_company_role = 'owner' then return false; end if;
    if p_company_role = 'admin' and public.current_company_role(p_company_id) <> 'owner' then
      return false;
    end if;
  end if;

  if p_object_id is not null then
    if not exists (
      select 1 from public.construction_objects o
      where o.id = p_object_id and o.company_id = p_company_id
    ) then
      return false;
    end if;

    if p_object_role is not null then
      if not public.can_manage_object(p_object_id) then return false; end if;
      if p_object_role = 'object_manager' and not public.is_company_admin(p_company_id) then
        return false;
      end if;
    end if;
  elsif p_object_role is not null then
    return false;
  end if;

  return true;
end;
$$;

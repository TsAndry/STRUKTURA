-- 0010_measure_projects.sql
-- STRUCTURA Measure 2.1: обмірні проєкти, поверхи, приміщення.
-- Проєкт належить існуючому construction_objects (спільний object_id); окремих
-- таблиць об'єктів/компаній/користувачів Measure не має.
--
-- ВАЖЛИВО: площа приміщення НЕ зберігається. Її буде обчислено з геометрії
-- (замкнений контур) на етапі 2.3. До того площа «Не визначено».
-- Внутрішня одиниця геометрії — міліметри (coordinate_unit = 'mm').

create type public.measurement_project_status as enum ('draft', 'active', 'completed', 'archived');
create type public.measurement_room_status    as enum ('planned', 'in_progress', 'measured', 'archived');
create type public.measurement_room_type as enum (
  'kitchen', 'bedroom', 'living_room', 'corridor', 'toilet', 'bathroom',
  'wardrobe', 'pantry', 'balcony', 'loggia', 'technical', 'other'
);

-- ---------------------------------------------------------------- tables
create table public.measurement_projects (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null,
  object_id       uuid not null,
  name            text not null check (char_length(btrim(name)) between 2 and 160),
  description     text check (description is null or char_length(description) <= 4000),
  -- одиниці ВІДОБРАЖЕННЯ; геометрія завжди в мм
  display_units   text not null default 'm' check (display_units in ('m', 'cm', 'mm')),
  coordinate_unit text not null default 'mm' check (coordinate_unit = 'mm'),
  status          public.measurement_project_status not null default 'draft',
  -- замовник/посередник бачать проєкт лише коли його явно відкрито для клієнта
  client_visible  boolean not null default false,
  -- метадані редактора (сітка, прив'язки); геометрія тут НЕ зберігається
  editor_settings jsonb not null default '{}'::jsonb
    check (jsonb_typeof(editor_settings) = 'object' and pg_column_size(editor_settings) <= 65536),
  created_by      uuid references public.profiles (id) on delete set null,
  version         integer not null default 1,
  archived_at     timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  foreign key (object_id, company_id)
    references public.construction_objects (id, company_id) on delete restrict,
  unique (id, company_id)
);

create index measurement_projects_company_idx on public.measurement_projects (company_id, updated_at desc);
create index measurement_projects_object_idx  on public.measurement_projects (object_id, updated_at desc);

create table public.measurement_floors (
  id                       uuid primary key default gen_random_uuid(),
  company_id               uuid not null,
  project_id               uuid not null,
  name                     text not null check (char_length(btrim(name)) between 1 and 120),
  sort_order               integer not null,
  elevation_mm             integer not null default 0 check (elevation_mm between -20000 and 500000),
  default_room_height_mm   integer not null default 2700 check (default_room_height_mm between 1000 and 10000),
  version                  integer not null default 1,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  foreign key (project_id, company_id)
    references public.measurement_projects (id, company_id) on delete cascade,
  unique (id, project_id, company_id),
  -- відкладена перевірка дозволяє атомарно переставляти поверхи
  constraint measurement_floors_order_uq unique (project_id, sort_order) deferrable initially deferred
);

create index measurement_floors_project_idx on public.measurement_floors (project_id, sort_order);

create table public.measurement_rooms (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null,
  project_id  uuid not null,
  floor_id    uuid not null,
  name        text not null check (char_length(btrim(name)) between 1 and 120),
  room_type   public.measurement_room_type not null default 'other',
  -- NULL = використовується типова висота поверху
  height_mm   integer check (height_mm is null or height_mm between 1000 and 10000),
  description text check (description is null or char_length(description) <= 2000),
  status      public.measurement_room_status not null default 'planned',
  sort_order  integer not null,
  version     integer not null default 1,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  foreign key (floor_id, project_id, company_id)
    references public.measurement_floors (id, project_id, company_id) on delete cascade
);

create index measurement_rooms_floor_idx   on public.measurement_rooms (floor_id, sort_order);
create index measurement_rooms_project_idx on public.measurement_rooms (project_id);

-- ------------------------------------------------- версії та updated_at
create function public.bump_row_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.version := old.version + 1;
  return new;
end;
$$;

create trigger measurement_projects_set_updated_at before update on public.measurement_projects
  for each row execute function public.set_updated_at();
create trigger measurement_floors_set_updated_at before update on public.measurement_floors
  for each row execute function public.set_updated_at();
create trigger measurement_rooms_set_updated_at before update on public.measurement_rooms
  for each row execute function public.set_updated_at();

create trigger measurement_projects_bump_version before update on public.measurement_projects
  for each row execute function public.bump_row_version();
create trigger measurement_floors_bump_version before update on public.measurement_floors
  for each row execute function public.bump_row_version();
create trigger measurement_rooms_bump_version before update on public.measurement_rooms
  for each row execute function public.bump_row_version();

create function public.sync_measurement_project_archived_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'archived' and (tg_op = 'INSERT' or old.status <> 'archived') then
    new.archived_at := now();
  elsif new.status <> 'archived' then
    new.archived_at := null;
  end if;
  return new;
end;
$$;

create trigger measurement_projects_sync_archived_at
  before insert or update of status on public.measurement_projects
  for each row execute function public.sync_measurement_project_archived_at();

-- ---------------------------------------------- підстановка області (scope)
-- company_id / project_id / sort_order визначаються СЕРВЕРОМ з батьківського запису;
-- значення від клієнта ігноруються (захист від підміни).
create function public.prepare_measurement_floor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
begin
  select p.company_id into v_company
  from public.measurement_projects p
  where p.id = new.project_id
  for update;

  if v_company is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  new.company_id := v_company;
  select coalesce(max(f.sort_order), 0) + 1 into new.sort_order
  from public.measurement_floors f where f.project_id = new.project_id;
  return new;
end;
$$;

create trigger measurement_floors_prepare
  before insert on public.measurement_floors
  for each row execute function public.prepare_measurement_floor();

create function public.prepare_measurement_room()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project uuid;
  v_company uuid;
begin
  select f.project_id, f.company_id into v_project, v_company
  from public.measurement_floors f
  where f.id = new.floor_id;

  if v_project is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  new.project_id := v_project;
  new.company_id := v_company;
  select coalesce(max(r.sort_order), 0) + 1 into new.sort_order
  from public.measurement_rooms r where r.floor_id = new.floor_id;
  return new;
end;
$$;

create trigger measurement_rooms_prepare
  before insert on public.measurement_rooms
  for each row execute function public.prepare_measurement_room();

-- --------------------------------------------------------- перевірки прав
-- Редагувати Measure: owner/admin компанії або на об'єкті — керівник, прораб, замірник, проєктувальник.
-- Працівник (worker) і зовнішні учасники (замовник, посередник) — лише перегляд.
create function public.measure_can_edit_object(p_object_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.construction_objects o
    where o.id = p_object_id
      and (
        exists (
          select 1 from public.company_members cm
          where cm.company_id = o.company_id and cm.user_id = (select auth.uid())
            and cm.role in ('owner', 'admin')
        )
        or exists (
          select 1 from public.object_members om
          where om.object_id = o.id and om.user_id = (select auth.uid())
            and om.role in ('object_manager', 'foreman', 'surveyor', 'designer')
        )
      )
  );
$$;

-- Видаляти проєкти: owner/admin компанії або керівник обʼєкта.
create function public.measure_can_delete_object(p_object_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.construction_objects o
    where o.id = p_object_id
      and (
        exists (
          select 1 from public.company_members cm
          where cm.company_id = o.company_id and cm.user_id = (select auth.uid())
            and cm.role in ('owner', 'admin')
        )
        or exists (
          select 1 from public.object_members om
          where om.object_id = o.id and om.user_id = (select auth.uid())
            and om.role = 'object_manager'
        )
      )
  );
$$;

-- Переглядати: owner/admin компанії; внутрішні учасники обʼєкта; зовнішні — лише якщо client_visible.
create function public.measure_can_view(p_object_id uuid, p_company_id uuid, p_client_visible boolean)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_company_admin(p_company_id)
      or exists (
        select 1 from public.object_members om
        where om.object_id = p_object_id and om.user_id = (select auth.uid())
          and (om.role not in ('property_owner', 'intermediary') or p_client_visible)
      );
$$;

create function public.measure_can_view_project(p_project_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.measurement_projects p
    where p.id = p_project_id
      and public.measure_can_view(p.object_id, p.company_id, p.client_visible)
  );
$$;

create function public.measure_can_edit_project(p_project_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.measurement_projects p
    where p.id = p_project_id and public.measure_can_edit_object(p.object_id)
  );
$$;

-- ----------------------------------------------------------------- RPC
create function public.create_measurement_project(
  p_object_id            uuid,
  p_name                 text,
  p_description          text default null,
  p_display_units        text default 'm',
  p_status               public.measurement_project_status default 'draft',
  p_create_initial_floor boolean default true,
  p_initial_floor_name   text default 'Поверх 1'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_company uuid;
  v_ostatus public.object_status;
  v_name    text := btrim(coalesce(p_name, ''));
  v_id      uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.measure_can_edit_object(p_object_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select o.company_id, o.status into v_company, v_ostatus
  from public.construction_objects o where o.id = p_object_id;

  if v_ostatus = 'archived' then
    raise exception 'object_archived' using errcode = '22023';
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 160 then
    raise exception 'invalid_project_name' using errcode = '22023';
  end if;
  if p_display_units not in ('m', 'cm', 'mm') then
    raise exception 'invalid_units' using errcode = '22023';
  end if;
  if p_status = 'archived' then
    raise exception 'invalid_initial_status' using errcode = '22023';
  end if;

  insert into public.measurement_projects
    (company_id, object_id, name, description, display_units, status, created_by)
  values
    (v_company, p_object_id, v_name, nullif(btrim(p_description), ''), p_display_units, p_status, v_uid)
  returning id into v_id;

  if p_create_initial_floor then
    insert into public.measurement_floors (project_id, name)
    values (v_id, coalesce(nullif(btrim(p_initial_floor_name), ''), 'Поверх 1'));
  end if;

  return v_id;
end;
$$;

-- Атомарна зміна порядку поверхів: потрібно передати ВСІ поверхи проєкту в новому порядку.
create function public.reorder_measurement_floors(p_project_id uuid, p_floor_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_count integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.measure_can_edit_project(p_project_id) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  perform 1 from public.measurement_projects p where p.id = p_project_id for update;

  select count(*) into v_count from public.measurement_floors f where f.project_id = p_project_id;

  if p_floor_ids is null
     or cardinality(p_floor_ids) <> v_count
     or (select count(distinct u.id) from unnest(p_floor_ids) as u(id)) <> v_count
     or exists (
       select 1 from unnest(p_floor_ids) as u(id)
       where not exists (
         select 1 from public.measurement_floors f
         where f.id = u.id and f.project_id = p_project_id
       )
     )
  then
    raise exception 'floor_set_mismatch' using errcode = '22023';
  end if;

  update public.measurement_floors f
  set sort_order = o.ord::integer
  from unnest(p_floor_ids) with ordinality as o(id, ord)
  where f.id = o.id;
end;
$$;

-- ----------------------------------------------------- журнал подій (Measure)
create function public.log_measurement_project_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.log_activity(new.company_id, new.object_id, (select auth.uid()), 'measure',
      'project.created', 'measurement_project', new.id, jsonb_build_object('name', new.name));
    return new;
  elsif tg_op = 'UPDATE' then
    if new.status is distinct from old.status then
      perform public.log_activity(new.company_id, new.object_id, (select auth.uid()), 'measure',
        'project.status_changed', 'measurement_project', new.id,
        jsonb_build_object('name', new.name, 'from', old.status, 'to', new.status));
    end if;
    return new;
  else
    perform public.log_activity(old.company_id, old.object_id, (select auth.uid()), 'measure',
      'project.deleted', 'measurement_project', old.id, jsonb_build_object('name', old.name));
    return old;
  end if;
end;
$$;

create trigger measurement_projects_log_insert after insert on public.measurement_projects
  for each row execute function public.log_measurement_project_event();
create trigger measurement_projects_log_status after update of status on public.measurement_projects
  for each row execute function public.log_measurement_project_event();
create trigger measurement_projects_log_delete after delete on public.measurement_projects
  for each row execute function public.log_measurement_project_event();

create function public.log_measurement_child_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_object uuid;
begin
  select p.object_id into v_object from public.measurement_projects p where p.id = new.project_id;
  perform public.log_activity(new.company_id, v_object, (select auth.uid()), 'measure',
    case tg_table_name when 'measurement_floors' then 'floor.created' else 'room.created' end,
    case tg_table_name when 'measurement_floors' then 'measurement_floor' else 'measurement_room' end,
    new.id, jsonb_build_object('name', new.name, 'project_id', new.project_id));
  return new;
end;
$$;

create trigger measurement_floors_log_insert after insert on public.measurement_floors
  for each row execute function public.log_measurement_child_created();
create trigger measurement_rooms_log_insert after insert on public.measurement_rooms
  for each row execute function public.log_measurement_child_created();

-- ----------------------------------------------------- перегляд зі зведенням
-- security_invoker: RLS застосовується від імені користувача.
create view public.measurement_project_summaries
with (security_invoker = true) as
select
  p.id, p.company_id, p.object_id, o.name as object_name,
  p.name, p.description, p.display_units, p.status, p.client_visible,
  p.version, p.archived_at, p.created_at, p.updated_at,
  (select count(*) from public.measurement_floors f where f.project_id = p.id) as floors_count,
  (select count(*) from public.measurement_rooms r where r.project_id = p.id)  as rooms_count,
  greatest(
    p.updated_at,
    coalesce((select max(f.updated_at) from public.measurement_floors f where f.project_id = p.id), p.updated_at),
    coalesce((select max(r.updated_at) from public.measurement_rooms  r where r.project_id = p.id), p.updated_at)
  ) as last_edited_at
from public.measurement_projects p
join public.construction_objects o on o.id = p.object_id;

-- ------------------------------------------------------ привілеї та RLS
revoke all on public.measurement_projects, public.measurement_floors, public.measurement_rooms,
              public.measurement_project_summaries from anon, authenticated;

grant select on public.measurement_projects, public.measurement_floors, public.measurement_rooms,
                public.measurement_project_summaries to authenticated;

-- проєкти створюються лише через create_measurement_project
grant update (name, description, display_units, status, client_visible, editor_settings)
  on public.measurement_projects to authenticated;
grant delete on public.measurement_projects to authenticated;

grant insert (project_id, name, elevation_mm, default_room_height_mm) on public.measurement_floors to authenticated;
grant update (name, elevation_mm, default_room_height_mm) on public.measurement_floors to authenticated;
grant delete on public.measurement_floors to authenticated;

grant insert (floor_id, name, room_type, height_mm, description, status) on public.measurement_rooms to authenticated;
grant update (name, room_type, height_mm, description, status) on public.measurement_rooms to authenticated;
grant delete on public.measurement_rooms to authenticated;

alter table public.measurement_projects enable row level security;
alter table public.measurement_floors   enable row level security;
alter table public.measurement_rooms    enable row level security;

create policy measurement_projects_select on public.measurement_projects
  for select to authenticated
  using (public.measure_can_view(object_id, company_id, client_visible));
create policy measurement_projects_update on public.measurement_projects
  for update to authenticated
  using (public.measure_can_edit_object(object_id))
  with check (public.measure_can_edit_object(object_id));
create policy measurement_projects_delete on public.measurement_projects
  for delete to authenticated
  using (public.measure_can_delete_object(object_id));

create policy measurement_floors_select on public.measurement_floors
  for select to authenticated using (public.measure_can_view_project(project_id));
create policy measurement_floors_insert on public.measurement_floors
  for insert to authenticated with check (public.measure_can_edit_project(project_id));
create policy measurement_floors_update on public.measurement_floors
  for update to authenticated
  using (public.measure_can_edit_project(project_id))
  with check (public.measure_can_edit_project(project_id));
create policy measurement_floors_delete on public.measurement_floors
  for delete to authenticated using (public.measure_can_edit_project(project_id));

create policy measurement_rooms_select on public.measurement_rooms
  for select to authenticated using (public.measure_can_view_project(project_id));
create policy measurement_rooms_insert on public.measurement_rooms
  for insert to authenticated with check (public.measure_can_edit_project(project_id));
create policy measurement_rooms_update on public.measurement_rooms
  for update to authenticated
  using (public.measure_can_edit_project(project_id))
  with check (public.measure_can_edit_project(project_id));
create policy measurement_rooms_delete on public.measurement_rooms
  for delete to authenticated using (public.measure_can_edit_project(project_id));

-- функції
revoke all on function public.bump_row_version()                         from public, anon, authenticated;
revoke all on function public.sync_measurement_project_archived_at()     from public, anon, authenticated;
revoke all on function public.prepare_measurement_floor()                from public, anon, authenticated;
revoke all on function public.prepare_measurement_room()                 from public, anon, authenticated;
revoke all on function public.log_measurement_project_event()            from public, anon, authenticated;
revoke all on function public.log_measurement_child_created()            from public, anon, authenticated;
revoke all on function public.measure_can_edit_object(uuid)              from public, anon, authenticated;
revoke all on function public.measure_can_delete_object(uuid)            from public, anon, authenticated;
revoke all on function public.measure_can_view(uuid, uuid, boolean)      from public, anon, authenticated;
revoke all on function public.measure_can_view_project(uuid)             from public, anon, authenticated;
revoke all on function public.measure_can_edit_project(uuid)             from public, anon, authenticated;
revoke all on function public.create_measurement_project(uuid, text, text, text, public.measurement_project_status, boolean, text)
  from public, anon, authenticated;
revoke all on function public.reorder_measurement_floors(uuid, uuid[])   from public, anon, authenticated;

grant execute on function public.measure_can_edit_object(uuid)           to authenticated;
grant execute on function public.measure_can_delete_object(uuid)         to authenticated;
grant execute on function public.measure_can_view(uuid, uuid, boolean)   to authenticated;
grant execute on function public.measure_can_view_project(uuid)          to authenticated;
grant execute on function public.measure_can_edit_project(uuid)          to authenticated;
grant execute on function public.create_measurement_project(uuid, text, text, text, public.measurement_project_status, boolean, text) to authenticated;
grant execute on function public.reorder_measurement_floors(uuid, uuid[]) to authenticated;

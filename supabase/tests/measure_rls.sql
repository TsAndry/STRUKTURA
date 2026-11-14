-- supabase/tests/measure_rls.sql
-- Тест Measure 2.1: права, ізоляція двох компаній, замовник, підміна області, версії, поверхи.
-- Запуск: після шиму (лише для чистого PostgreSQL) і всіх міграцій:
--   psql -v ON_ERROR_STOP=1 -d <db> -f supabase/tests/measure_rls.sql
-- Усе виконується в транзакції з ROLLBACK. Кожна успішна перевірка друкує NOTICE "PASS: ...".

\set ON_ERROR_STOP on

\set as_super 'reset role;'
\set as_alice 'reset role; set local request.jwt.claims = ''{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}''; set local role authenticated;'
\set as_bob   'reset role; set local request.jwt.claims = ''{"sub":"b0000000-0000-0000-0000-000000000002","role":"authenticated"}''; set local role authenticated;'
\set as_carol 'reset role; set local request.jwt.claims = ''{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated"}''; set local role authenticated;'
\set as_dave  'reset role; set local request.jwt.claims = ''{"sub":"d0000000-0000-0000-0000-000000000004","role":"authenticated"}''; set local role authenticated;'
\set as_eve   'reset role; set local request.jwt.claims = ''{"sub":"e0000000-0000-0000-0000-000000000005","role":"authenticated"}''; set local role authenticated;'
\set as_zed   'reset role; set local request.jwt.claims = ''{"sub":"22222222-0000-0000-0000-000000000006","role":"authenticated"}''; set local role authenticated;'

begin;

create schema t;
grant usage on schema t to authenticated;

create function t.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if p_cond is not true then raise exception 'FAIL: %', p_msg; end if;
  raise notice 'PASS: %', p_msg;
end $$;

create function t.expect_err(p_sql text, p_expected text, p_msg text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like '%' || p_expected || '%' then
      raise notice 'PASS: % [%]', p_msg, sqlerrm;
      return;
    end if;
    raise exception 'FAIL: % -> unexpected error: %', p_msg, sqlerrm;
  end;
  raise exception 'FAIL: % -> expected error "%" but statement succeeded', p_msg, p_expected;
end $$;

create function t.rows_affected(p_sql text) returns integer language plpgsql as $$
declare n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end $$;

grant execute on all functions in schema t to authenticated;

insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('a0000000-0000-0000-0000-000000000001', 'alice@a.test',  '{"first_name":"Аліса"}', now()),
  ('b0000000-0000-0000-0000-000000000002', 'bob@b.test',    '{"first_name":"Боб"}', now()),
  ('c0000000-0000-0000-0000-000000000003', 'carol@a.test',  '{"first_name":"Керол"}', now()),
  ('d0000000-0000-0000-0000-000000000004', 'dave@a.test',   '{"first_name":"Дейв"}', now()),
  ('e0000000-0000-0000-0000-000000000005', 'eve@client.test', '{"first_name":"Єва"}', now()),
  ('22222222-0000-0000-0000-000000000006', 'zed@z.test',    '{"first_name":"Зед"}', now());

-- --------------------------------------------------------------- підготовка
:as_alice
select public.create_company('Альфа Буд') as co_a \gset
select public.create_object(:'co_a', 'Квартира A1', 'apartment') as ob_a1 \gset
select public.create_object(:'co_a', 'Офіс A2', 'office') as ob_a2 \gset
select (public.create_invitation(:'co_a', 'carol@a.test', 'worker'::public.company_role) ->> 'token') as tok_carol \gset
select (public.create_invitation(:'co_a', 'dave@a.test', 'surveyor'::public.company_role) ->> 'token') as tok_dave \gset
select (public.create_invitation(:'co_a', 'eve@client.test', null::public.company_role, :'ob_a1', 'property_owner'::public.object_role) ->> 'token') as tok_eve \gset

:as_bob
select public.create_company('Бета Груп') as co_b \gset
select public.create_object(:'co_b', 'Будинок B1', 'house') as ob_b1 \gset
select public.create_measurement_project(:'ob_b1', 'Обміри B1') as pr_b1 \gset
select id as fl_b1 from public.measurement_floors where project_id = :'pr_b1' \gset

:as_carol
select public.accept_invitation(:'tok_carol') as _ \gset
:as_dave
select public.accept_invitation(:'tok_dave') as _ \gset
:as_eve
select public.accept_invitation(:'tok_eve') as _ \gset

:as_alice
select public.add_object_member(:'ob_a1', 'c0000000-0000-0000-0000-000000000003', 'worker') as _ \gset
select public.add_object_member(:'ob_a1', 'd0000000-0000-0000-0000-000000000004', 'surveyor') as _ \gset

-- ---------------------------------------------- Alice: основний сценарій
select public.create_measurement_project(:'ob_a1', 'Обміри квартири', 'Опис', 'm') as pr_a1 \gset
select t.ok((select count(*) from public.measurement_floors where project_id = :'pr_a1') = 1,
            'проєкт створено разом із початковим поверхом');
select t.ok((select name from public.measurement_floors where project_id = :'pr_a1') = 'Поверх 1', 'початковий поверх називається «Поверх 1»');
select t.ok((select coordinate_unit from public.measurement_projects where id = :'pr_a1') = 'mm', 'внутрішня одиниця геометрії — мм');
select t.ok((select company_id from public.measurement_projects where id = :'pr_a1') = :'co_a'::uuid, 'company_id проєкту береться з об''єкта');
select id as fl_a1 from public.measurement_floors where project_id = :'pr_a1' \gset

insert into public.measurement_rooms (floor_id, name, room_type) values (:'fl_a1', 'Кухня', 'kitchen');
insert into public.measurement_rooms (floor_id, name, room_type) values (:'fl_a1', 'Коридор', 'corridor');
insert into public.measurement_rooms (floor_id, name, room_type, height_mm, description) values (:'fl_a1', 'Дитяча кімната', 'bedroom', 2600, 'власна назва для типу «спальня»');

select t.ok((select floors_count from public.measurement_project_summaries where id = :'pr_a1') = 1
        and (select rooms_count from public.measurement_project_summaries where id = :'pr_a1') = 3,
            'зведення: 1 поверх, 3 приміщення');
select t.ok((select object_name from public.measurement_project_summaries where id = :'pr_a1') = 'Квартира A1', 'зведення показує назву обʼєкта без дублювання в таблиці');
select t.ok((select room_type from public.measurement_rooms where name = 'Дитяча кімната') = 'bedroom', 'власна назва незалежна від типу приміщення');
select t.ok((select count(*) from information_schema.columns
             where table_schema = 'public' and table_name = 'measurement_rooms' and column_name ilike '%area%') = 0,
            'площа приміщення НЕ зберігається (немає вигаданих значень)');
select t.ok((select array_agg(sort_order order by sort_order) from public.measurement_rooms where floor_id = :'fl_a1') = array[1,2,3],
            'порядок приміщень призначається сервером: 1,2,3');

-- поверхи та порядок
insert into public.measurement_floors (project_id, name, elevation_mm) values (:'pr_a1', 'Підвал', -2700);
insert into public.measurement_floors (project_id, name, elevation_mm) values (:'pr_a1', 'Поверх 2', 2700);
select id as fl_base from public.measurement_floors where name = 'Підвал' and project_id = :'pr_a1' \gset
select id as fl_2 from public.measurement_floors where name = 'Поверх 2' and project_id = :'pr_a1' \gset
select t.ok((select array_agg(name order by sort_order) from public.measurement_floors where project_id = :'pr_a1') = array['Поверх 1','Підвал','Поверх 2'],
            'нові поверхи додаються в кінець');
select public.reorder_measurement_floors(:'pr_a1', array[:'fl_base', :'fl_a1', :'fl_2']::uuid[]) as _ \gset
select t.ok((select array_agg(name order by sort_order) from public.measurement_floors where project_id = :'pr_a1') = array['Підвал','Поверх 1','Поверх 2'],
            'порядок поверхів змінено атомарно');
select t.expect_err(format('select public.reorder_measurement_floors(%L, array[%L, %L]::uuid[])', :'pr_a1', :'fl_base', :'fl_a1'),
                    'floor_set_mismatch', 'перестановка без одного поверху відхиляється');
select t.expect_err(format('select public.reorder_measurement_floors(%L, array[%L, %L, %L]::uuid[])', :'pr_a1', :'fl_base', :'fl_base', :'fl_a1'),
                    'floor_set_mismatch', 'дублікат у перестановці відхиляється');
select t.expect_err(format('select public.reorder_measurement_floors(%L, array[%L, %L, %L]::uuid[])', :'pr_a1', :'fl_base', :'fl_a1', :'fl_b1'),
                    'floor_set_mismatch', 'чужий поверх у перестановці відхиляється');

-- обмеження цілісності
select t.expect_err(format('insert into public.measurement_floors (project_id, name, default_room_height_mm) values (%L, %L, 500)', :'pr_a1', 'Низький'),
                    'check constraint', 'типова висота поверху поза межами відхиляється');
select t.expect_err(format('insert into public.measurement_rooms (floor_id, name, height_mm) values (%L, %L, 20000)', :'fl_a1', 'Зависока'),
                    'check constraint', 'висота приміщення поза межами відхиляється');
select t.expect_err(format('select public.create_measurement_project(%L, %L, null, %L)', :'ob_a1', 'Ок', 'km'),
                    'invalid_units', 'невідомі одиниці відхиляються');
select t.expect_err(format('select public.create_measurement_project(%L, %L)', :'ob_a1', 'X'),
                    'invalid_project_name', 'занадто коротка назва проєкту');

-- версії (оптимістична конкуренція)
select version as v1 from public.measurement_rooms where name = 'Кухня' \gset
select t.ok(t.rows_affected(format('update public.measurement_rooms set name = %L where name = %L and version = %s', 'Кухня-вітальня', 'Кухня', :v1)) = 1,
            'оновлення з актуальною версією проходить');
select t.ok((select version from public.measurement_rooms where name = 'Кухня-вітальня') = :v1 + 1, 'версія зросла на 1');
select t.ok(t.rows_affected(format('update public.measurement_rooms set name = %L where name = %L and version = %s', 'Стара зміна', 'Кухня-вітальня', :v1)) = 0,
            'застарілий запит (стара версія) нічого не перезаписує');

-- привілеї стовпців / підміна області
select t.expect_err(format('insert into public.measurement_projects (company_id, object_id, name) values (%L, %L, %L)', :'co_a', :'ob_a1', 'Прямо'),
                    'permission denied', 'прямий INSERT проєкту заборонений (лише RPC)');
select t.expect_err(format('update public.measurement_projects set company_id = %L where id = %L', :'co_b', :'pr_a1'),
                    'permission denied', 'company_id проєкту змінити неможливо');
select t.expect_err(format('update public.measurement_projects set version = 99 where id = %L', :'pr_a1'),
                    'permission denied', 'версію не можна виставити вручну');
select t.expect_err(format('update public.measurement_floors set sort_order = 9 where id = %L', :'fl_a1'),
                    'permission denied', 'sort_order змінюється лише через reorder');
select t.expect_err(format('insert into public.measurement_floors (project_id, company_id, name) values (%L, %L, %L)', :'pr_a1', :'co_b', 'Підміна'),
                    'permission denied', 'company_id поверху від клієнта не приймається');
select t.expect_err(format('insert into public.measurement_rooms (floor_id, project_id, name) values (%L, %L, %L)', :'fl_a1', :'pr_b1', 'Підміна'),
                    'permission denied', 'project_id приміщення від клієнта не приймається');

-- підміна через чужий поверх
select t.expect_err(format('insert into public.measurement_rooms (floor_id, name) values (%L, %L)', :'fl_b1', 'У чужий поверх'),
                    'row-level security', 'Alice не може додати приміщення в поверх компанії B');
select t.expect_err(format('insert into public.measurement_floors (project_id, name) values (%L, %L)', :'pr_b1', 'У чужий проєкт'),
                    'row-level security', 'Alice не може додати поверх у проєкт компанії B');
select t.expect_err(format('select public.create_measurement_project(%L, %L)', :'ob_b1', 'Чужий обʼєкт'),
                    'forbidden', 'Alice не може створити проєкт на обʼєкті компанії B');
select t.expect_err(format('select public.reorder_measurement_floors(%L, array[%L]::uuid[])', :'pr_b1', :'fl_b1'),
                    'forbidden', 'Alice не може переставляти поверхи компанії B');
select t.ok((select count(*) from public.measurement_projects where id = :'pr_b1') = 0, 'Alice НЕ бачить проєкт компанії B');

-- ------------------------------------------------------ Bob: ізоляція
:as_bob
select t.ok((select count(*) from public.measurement_projects) = 1, 'Bob бачить лише свій проєкт');
select t.ok((select count(*) from public.measurement_floors) = 1, 'Bob бачить лише свій поверх');
select t.ok((select count(*) from public.measurement_rooms) = 0, 'Bob не бачить жодного чужого приміщення');
select t.ok((select count(*) from public.measurement_project_summaries) = 1, 'зведення Bob містить лише його проєкт');
select t.ok((select count(*) from public.measurement_project_summaries where id = :'pr_a1') = 0, 'зведення не розкриває проєкт A');
select t.expect_err(format('select public.create_measurement_project(%L, %L)', :'ob_a1', 'Вторгнення'),
                    'forbidden', 'Bob не може створити проєкт на обʼєкті A1');
select t.ok(t.rows_affected(format('update public.measurement_projects set name = %L where id = %L', 'hacked', :'pr_a1')) = 0, 'Bob не може перейменувати проєкт A');
select t.ok(t.rows_affected(format('delete from public.measurement_projects where id = %L', :'pr_a1')) = 0, 'Bob не може видалити проєкт A');
select t.ok(t.rows_affected(format('delete from public.measurement_floors where id = %L', :'fl_a1')) = 0, 'Bob не може видалити поверх A');
select t.ok(t.rows_affected(format('update public.measurement_rooms set name = %L where floor_id = %L', 'hacked', :'fl_a1')) = 0, 'Bob не може змінити приміщення A');
select t.expect_err(format('insert into public.measurement_rooms (floor_id, name) values (%L, %L)', :'fl_a1', 'Вторгнення'),
                    'row-level security', 'Bob не може додати приміщення до поверху A');
select t.ok((select count(*) from public.activity_log where module = 'measure' and company_id = :'co_a') = 0, 'Bob не бачить подій Measure компанії A');

-- --------------------------------------- Carol (працівник): лише перегляд
:as_carol
select t.ok((select count(*) from public.measurement_projects where id = :'pr_a1') = 1, 'працівник, доданий на обʼєкт, бачить проєкт');
select t.ok((select count(*) from public.measurement_rooms where project_id = :'pr_a1') = 3, 'працівник бачить приміщення');
select t.expect_err(format('select public.create_measurement_project(%L, %L)', :'ob_a1', 'Від працівника'),
                    'forbidden', 'працівник не може створити проєкт');
select t.expect_err(format('insert into public.measurement_floors (project_id, name) values (%L, %L)', :'pr_a1', 'Від працівника'),
                    'row-level security', 'працівник не може додати поверх');
select t.expect_err(format('insert into public.measurement_rooms (floor_id, name) values (%L, %L)', :'fl_a1', 'Від працівника'),
                    'row-level security', 'працівник не може додати приміщення');
select t.ok(t.rows_affected(format('update public.measurement_rooms set name = %L where floor_id = %L', 'hacked', :'fl_a1')) = 0, 'працівник не може редагувати приміщення');
select t.ok(t.rows_affected(format('update public.measurement_projects set name = %L where id = %L', 'hacked', :'pr_a1')) = 0, 'працівник не може редагувати проєкт');
select t.ok(t.rows_affected(format('delete from public.measurement_rooms where floor_id = %L', :'fl_a1')) = 0, 'працівник не може видаляти приміщення');
select t.expect_err(format('select public.reorder_measurement_floors(%L, array[%L,%L,%L]::uuid[])', :'pr_a1', :'fl_a1', :'fl_base', :'fl_2'),
                    'forbidden', 'працівник не може переставляти поверхи');

-- ------------------------------------------- Dave (замірник): редагування
:as_dave
select t.ok((select count(*) from public.measurement_projects where id = :'pr_a1') = 1, 'замірник бачить проєкт');
insert into public.measurement_rooms (floor_id, name, room_type) values (:'fl_a1', 'Спальня', 'bedroom');
select t.ok((select count(*) from public.measurement_rooms where floor_id = :'fl_a1') = 4, 'замірник додав приміщення');
select t.ok(t.rows_affected(format('update public.measurement_rooms set name = %L, status = %L where name = %L', 'Головна спальня', 'measured', 'Спальня')) = 1, 'замірник перейменував приміщення і змінив статус');
select t.ok(t.rows_affected(format('update public.measurement_projects set status = %L where id = %L', 'archived', :'pr_a1')) = 1, 'замірник може архівувати проєкт');
select t.ok((select archived_at is not null from public.measurement_projects where id = :'pr_a1'), 'archived_at заповнено при архівуванні');
select t.ok(t.rows_affected(format('update public.measurement_projects set status = %L where id = %L', 'active', :'pr_a1')) = 1, 'проєкт відновлено');
select t.ok((select archived_at is null from public.measurement_projects where id = :'pr_a1'), 'archived_at очищено при відновленні');
select t.ok(t.rows_affected(format('delete from public.measurement_projects where id = %L', :'pr_a1')) = 0, 'замірник НЕ може видалити проєкт (лише owner/admin/керівник обʼєкта)');
select t.expect_err(format('select public.create_measurement_project(%L, %L)', :'ob_a2', 'На обʼєкті без призначення'),
                    'forbidden', 'замірник не може створювати проєкти на обʼєкті, куди не призначений');

-- ------------------------------------------- Eve (замовник): за дозволом
:as_eve
select t.ok((select count(*) from public.measurement_projects) = 0, 'замовник НЕ бачить проєкт, поки його не відкрито для клієнта');
select t.ok((select count(*) from public.measurement_rooms) = 0, 'замовник НЕ бачить приміщень закритого проєкту');
select t.ok((select count(*) from public.measurement_project_summaries) = 0, 'зведення замовника порожнє');

:as_alice
select t.ok(t.rows_affected(format('update public.measurement_projects set client_visible = true where id = %L', :'pr_a1')) = 1, 'Alice відкрила проєкт для клієнта');

:as_eve
select t.ok((select count(*) from public.measurement_projects) = 1, 'замовник бачить відкритий для клієнта проєкт');
select t.ok((select count(*) from public.measurement_floors) = 3, 'замовник бачить поверхи відкритого проєкту');
select t.ok((select count(*) from public.measurement_rooms) = 4, 'замовник бачить приміщення відкритого проєкту');
select t.expect_err(format('insert into public.measurement_floors (project_id, name) values (%L, %L)', :'pr_a1', 'Від замовника'),
                    'row-level security', 'замовник не може додавати поверхи');
select t.expect_err(format('insert into public.measurement_rooms (floor_id, name) values (%L, %L)', :'fl_a1', 'Від замовника'),
                    'row-level security', 'замовник не може додавати приміщення');
select t.ok(t.rows_affected(format('update public.measurement_rooms set name = %L where project_id = %L', 'hacked', :'pr_a1')) = 0, 'замовник не може редагувати приміщення');
select t.ok(t.rows_affected(format('update public.measurement_projects set client_visible = false where id = %L', :'pr_a1')) = 0, 'замовник не може сам закрити/відкрити проєкт');
select t.ok(t.rows_affected(format('delete from public.measurement_projects where id = %L', :'pr_a1')) = 0, 'замовник не може видалити проєкт');
select t.expect_err(format('select public.create_measurement_project(%L, %L)', :'ob_a1', 'Від замовника'),
                    'forbidden', 'замовник не може створити проєкт');

-- ---------------------------------------------- Zed (сторонній), прямий доступ
:as_zed
select t.ok((select count(*) from public.measurement_projects) = 0, 'сторонній не бачить проєктів');
select t.ok((select count(*) from public.measurement_project_summaries where id = :'pr_a1') = 0, 'сторонній не бачить проєкт за прямим id');
select t.ok((select count(*) from public.measurement_floors where id = :'fl_a1') = 0, 'сторонній не бачить поверх за прямим id');

-- ------------------------------ Видалення проєкту та каскад; архівний обʼєкт
:as_alice
select public.create_measurement_project(:'ob_a1', 'Тимчасовий') as pr_tmp \gset
select id as fl_tmp from public.measurement_floors where project_id = :'pr_tmp' \gset
insert into public.measurement_rooms (floor_id, name) values (:'fl_tmp', 'Кімната');
select t.ok(t.rows_affected(format('delete from public.measurement_projects where id = %L', :'pr_tmp')) = 1, 'owner видалив проєкт');
select t.ok((select count(*) from public.measurement_floors where project_id = :'pr_tmp') = 0
        and (select count(*) from public.measurement_rooms where project_id = :'pr_tmp') = 0, 'поверхи й приміщення видалено каскадом');

select t.ok(t.rows_affected(format('update public.construction_objects set status = %L where id = %L', 'archived', :'ob_a2')) = 1, 'обʼєкт A2 архівовано');
select t.expect_err(format('select public.create_measurement_project(%L, %L)', :'ob_a2', 'На архівному'),
                    'object_archived', 'на архівному обʼєкті проєкт створити не можна');

-- журнал подій
select t.ok((select count(*) from public.activity_log where module = 'measure' and action = 'project.created') >= 2, 'журнал: створення проєктів (module=measure)');
select t.ok((select count(*) from public.activity_log where module = 'measure' and action = 'floor.created') >= 3, 'журнал: створення поверхів');
select t.ok((select count(*) from public.activity_log where module = 'measure' and action = 'room.created') >= 4, 'журнал: створення приміщень');
select t.ok((select count(*) from public.activity_log where module = 'measure' and action = 'project.status_changed') >= 2, 'журнал: зміна статусу проєкту');
select t.ok((select count(*) from public.activity_log where module = 'measure' and action = 'project.deleted') = 1, 'журнал: видалення проєкту');

reset role;
rollback;
\echo ВСІ ПЕРЕВІРКИ MEASURE ПРОЙДЕНО

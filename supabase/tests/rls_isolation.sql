-- supabase/tests/rls_isolation.sql
-- Інтеграційний тест ізоляції даних, ролей і запрошень на рівні БД.
-- Запуск (локально, після шиму і всіх міграцій; усе виконується в транзакції з ROLLBACK):
--   psql -v ON_ERROR_STOP=1 -d <db> -f supabase/tests/rls_isolation.sql
-- Для Supabase CLI: `supabase db reset`, потім виконати цей файл (шим не потрібен).
-- Кожна успішна перевірка друкує NOTICE "PASS: ...", будь-яка невдала — зупиняє скрипт.

\set ON_ERROR_STOP on

\set as_super  'reset role;'
\set as_alice  'reset role; set local request.jwt.claims = ''{"sub":"a0000000-0000-0000-0000-000000000001","role":"authenticated"}''; set local role authenticated;'
\set as_bob    'reset role; set local request.jwt.claims = ''{"sub":"b0000000-0000-0000-0000-000000000002","role":"authenticated"}''; set local role authenticated;'
\set as_carol  'reset role; set local request.jwt.claims = ''{"sub":"c0000000-0000-0000-0000-000000000003","role":"authenticated"}''; set local role authenticated;'
\set as_dave   'reset role; set local request.jwt.claims = ''{"sub":"d0000000-0000-0000-0000-000000000004","role":"authenticated"}''; set local role authenticated;'
\set as_eve    'reset role; set local request.jwt.claims = ''{"sub":"e0000000-0000-0000-0000-000000000005","role":"authenticated"}''; set local role authenticated;'
\set as_frank  'reset role; set local request.jwt.claims = ''{"sub":"f0000000-0000-0000-0000-000000000006","role":"authenticated"}''; set local role authenticated;'
\set as_hank   'reset role; set local request.jwt.claims = ''{"sub":"11111111-0000-0000-0000-000000000007","role":"authenticated"}''; set local role authenticated;'

begin;

-- ----------------------------------------------------------------- helpers
create schema t;
grant usage on schema t to authenticated;

create function t.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if p_cond is not true then raise exception 'FAIL: %', p_msg; end if;
  raise notice 'PASS: %', p_msg;
end $$;

-- Очікує помилку, повідомлення якої містить p_expected.
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

-- Виконує UPDATE і повертає кількість змінених рядків (RLS приховує чужі рядки без помилки).
create function t.rows_affected(p_sql text) returns integer language plpgsql as $$
declare n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end $$;

grant execute on all functions in schema t to authenticated;

-- ------------------------------------------------------------------- users
insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('a0000000-0000-0000-0000-000000000001', 'alice@a.test', '{"first_name":"Аліса","last_name":"Власниця","phone":"+380501110001","platform_role":"super_admin"}', now()),
  ('b0000000-0000-0000-0000-000000000002', 'bob@b.test',   '{"first_name":"Боб","last_name":"Власник"}', now()),
  ('c0000000-0000-0000-0000-000000000003', 'carol@a.test', '{"first_name":"Керол"}', now()),
  ('d0000000-0000-0000-0000-000000000004', 'dave@client.test', '{"first_name":"Дейв"}', now()),
  ('e0000000-0000-0000-0000-000000000005', 'eve@evil.test', '{"first_name":"Єва"}', now()),
  ('f0000000-0000-0000-0000-000000000006', 'frank@a.test', '{"first_name":"Френк"}', now()),
  ('11111111-0000-0000-0000-000000000007', 'hank@a.test', '{"first_name":"Генк"}', null);

select t.ok((select count(*) from public.profiles) = 7, 'профілі створюються тригером для всіх 7 користувачів');
select t.ok((select platform_role from public.profiles where email = 'alice@a.test') = 'user',
            'platform_role не береться з user_metadata (спроба підвищення ігнорується)');
select t.ok((select first_name from public.profiles where email = 'alice@a.test') = 'Аліса',
            'ім''я з метаданих реєстрації потрапляє в профіль');

-- ------------------------------------------------------ Alice: компанія A
:as_alice
select public.create_company('Альфа Буд', 'Будівельна компанія A') as co_a \gset
select public.create_object(:'co_a', 'Квартира 12', 'apartment', 'Київ, вул. Тестова 1') as ob_a1 \gset
select public.create_object(:'co_a', 'Офіс 7', 'office') as ob_a2 \gset
select (public.create_invitation(:'co_a', 'carol@a.test', 'worker'::public.company_role) ->> 'token') as tok_carol \gset
select (public.create_invitation(:'co_a', 'dave@client.test', null::public.company_role, :'ob_a1', 'property_owner'::public.object_role) ->> 'token') as tok_dave \gset
select (public.create_invitation(:'co_a', 'eve@evil.test', 'designer'::public.company_role) ->> 'token') as tok_eve \gset
select (public.create_invitation(:'co_a', 'frank@a.test', 'worker'::public.company_role) ->> 'token') as tok_frank1 \gset
select (public.create_invitation(:'co_a', 'hank@a.test', 'worker'::public.company_role) ->> 'token') as tok_hank \gset

select t.ok((select count(*) from public.companies) = 1, 'Alice бачить рівно одну компанію');
select t.ok((select role from public.company_members where user_id = 'a0000000-0000-0000-0000-000000000001') = 'owner',
            'створювач компанії атомарно став власником');
select t.ok((select owner_id from public.companies where id = :'co_a') = 'a0000000-0000-0000-0000-000000000001',
            'companies.owner_id = створювач');
select t.ok((select count(*) from public.construction_objects) = 2, 'Alice бачить свої 2 об''єкти');
select t.expect_err(format('select public.create_invitation(%L, %L, %L::public.company_role)', :'co_a', 'carol@a.test', 'worker'),
                    'duplicate_pending_invitation', 'повторне активне запрошення на ту саму адресу заборонене');
select t.expect_err(format('select public.create_invitation(%L, %L, %L::public.company_role)', :'co_a', 'x@a.test', 'owner'),
                    'forbidden', 'запросити з роллю owner неможливо');
select t.expect_err(format('select public.create_invitation(%L, %L, %L::public.company_role)', :'co_a', 'not-an-email', 'worker'),
                    'invalid_email', 'некоректний email відхиляється');
select t.ok((select count(*) from public.invitations) = 5, 'Alice бачить 5 своїх запрошень');
select t.expect_err('select token_hash from public.invitations', 'permission denied',
                    'стовпець token_hash недоступний навіть власнику компанії');
select t.expect_err(format('select public.create_object(%L, %L, %L, null, null, %L)', :'co_a', 'Архів', 'apartment', 'archived'),
                    'invalid_initial_status', 'об''єкт не можна створити одразу архівним');

-- ------------------------------------------------------- Bob: компанія B
:as_bob
select public.create_company('Бета Груп') as co_b \gset
select public.create_object(:'co_b', 'Будинок B1', 'house') as ob_b1 \gset

select t.ok((select count(*) from public.companies) = 1, 'Bob бачить рівно одну компанію (свою)');
select t.ok((select count(*) from public.companies where id = :'co_a') = 0, 'Bob НЕ бачить компанію A');
select t.ok((select count(*) from public.construction_objects where company_id = :'co_a') = 0, 'Bob НЕ бачить об''єкти A');
select t.ok((select count(*) from public.construction_objects) = 1, 'Bob бачить лише свій об''єкт');
select t.ok((select count(*) from public.company_members where company_id = :'co_a') = 0, 'Bob НЕ бачить учасників A');
select t.ok((select count(*) from public.object_members where company_id = :'co_a') = 0, 'Bob НЕ бачить учасників об''єктів A');
select t.ok((select count(*) from public.invitations where company_id = :'co_a') = 0, 'Bob НЕ бачить запрошення A');
select t.ok((select count(*) from public.activity_log where company_id = :'co_a') = 0, 'Bob НЕ бачить журнал подій A');
select t.ok((select count(*) from public.profiles where id = 'a0000000-0000-0000-0000-000000000001') = 0, 'Bob НЕ бачить профіль Alice');
select t.ok(t.rows_affected(format('update public.companies set name = %L where id = %L', 'hacked', :'co_a')) = 0,
            'Bob не може змінити компанію A (0 рядків)');
select t.ok(t.rows_affected(format('update public.construction_objects set name = %L where id = %L', 'hacked', :'ob_a1')) = 0,
            'Bob не може змінити об''єкт A (0 рядків)');
select t.expect_err(format('select public.create_invitation(%L, %L, %L::public.company_role)', :'co_a', 'spy@b.test', 'worker'),
                    'forbidden', 'Bob не може створити запрошення в компанії A');
select t.expect_err(format('select public.create_object(%L, %L)', :'co_a', 'Підміна'),
                    'forbidden', 'Bob не може створити об''єкт у компанії A (підміна company_id)');
select t.expect_err(format('select public.add_object_member(%L, %L, %L)', :'ob_a1', 'b0000000-0000-0000-0000-000000000002', 'worker'),
                    'forbidden', 'Bob не може додати себе до об''єкта A');
select t.expect_err(format('select public.update_company_member_role(%L, %L, %L)', :'co_a', 'c0000000-0000-0000-0000-000000000003', 'admin'),
                    'forbidden', 'Bob не може змінювати ролі в компанії A');
select t.expect_err(format('insert into public.company_members (company_id, user_id, role) values (%L, %L, %L)', :'co_a', 'b0000000-0000-0000-0000-000000000002', 'admin'),
                    'permission denied', 'пряма вставка в company_members заборонена');
select t.expect_err(format('insert into public.object_members (object_id, company_id, user_id, role) values (%L, %L, %L, %L)', :'ob_b1', :'co_b', 'b0000000-0000-0000-0000-000000000002', 'worker'),
                    'permission denied', 'пряма вставка в object_members заборонена');
select t.expect_err(format('insert into public.construction_objects (company_id, name) values (%L, %L)', :'co_a', 'Підміна'),
                    'permission denied', 'пряма вставка в construction_objects заборонена');
select t.expect_err(format('insert into public.companies (name, owner_id) values (%L, %L)', 'Фейк', 'b0000000-0000-0000-0000-000000000002'),
                    'permission denied', 'пряма вставка в companies заборонена (лише create_company)');
select t.expect_err(format('insert into public.invitations (company_id, email, company_role, token_hash, expires_at) values (%L, %L, %L, %L, now())', :'co_b', 'x@x.test', 'admin', 'abc'),
                    'permission denied', 'пряма вставка в invitations заборонена');
select t.expect_err(format('insert into public.activity_log (company_id, action, entity_type) values (%L, %L, %L)', :'co_b', 'fake', 'x'),
                    'permission denied', 'пряма вставка в activity_log заборонена');
select t.expect_err(format('select public.log_activity(%L, null, null, %L, %L, %L, null)', :'co_b', 'platform', 'fake', 'x'),
                    'permission denied', 'log_activity недоступна клієнтам');
select t.expect_err('update public.profiles set platform_role = ''super_admin'' where id = ''b0000000-0000-0000-0000-000000000002''',
                    'permission denied', 'самопризначення super_admin заборонене');
select t.expect_err(format('update public.companies set owner_id = %L where id = %L', 'b0000000-0000-0000-0000-000000000002', :'co_b'),
                    'permission denied', 'зміна owner_id через API заборонена');
select t.expect_err(format('update public.construction_objects set company_id = %L where id = %L', :'co_a', :'ob_b1'),
                    'permission denied', 'перенесення об''єкта в чужу компанію (підміна company_id) заборонене');
select t.expect_err(format('delete from public.construction_objects where id = %L', :'ob_b1'),
                    'permission denied', 'видалення об''єкта заборонене (є архівування)');
select t.expect_err(format('delete from public.activity_log where company_id = %L', :'co_b'),
                    'permission denied', 'журнал подій append-only');
select t.expect_err(format('select public.accept_invitation(%L)', :'tok_carol'),
                    'invitation_email_mismatch', 'Bob не може прийняти запрошення, адресоване Carol');

-- Власник A теж не може торкнутися компанії B
:as_alice
select t.ok(t.rows_affected(format('update public.construction_objects set name = %L where id = %L', 'hacked', :'ob_b1')) = 0,
            'Alice не може змінити об''єкт компанії B');
select t.expect_err(format('select public.add_object_member(%L, %L, %L)', :'ob_b1', 'a0000000-0000-0000-0000-000000000001', 'worker'),
                    'forbidden', 'Alice не може додати себе до об''єкта B');
select t.expect_err(format('select public.create_invitation(%L, %L, %L::public.company_role, %L, %L::public.object_role)', :'co_a', 'z@x.test', 'worker', :'ob_b1', 'worker'),
                    'forbidden', 'запрошення в компанії A не може посилатися на об''єкт B');
select t.ok((select count(*) from public.companies where id = :'co_b') = 0, 'Alice НЕ бачить компанію B');

-- На рівні БД складений ключ не дозволяє розбіжність object_id/company_id
:as_super
select t.expect_err(format('insert into public.object_members (object_id, company_id, user_id, role) values (%L, %L, %L, %L)', :'ob_b1', :'co_a', 'a0000000-0000-0000-0000-000000000001', 'worker'),
                    'foreign key constraint', 'БД відхиляє object_members з object_id від іншої компанії');
select t.expect_err(format('insert into public.activity_log (company_id, object_id, action, entity_type) values (%L, %L, %L, %L)', :'co_a', :'ob_b1', 'x', 'x'),
                    'foreign key constraint', 'БД відхиляє activity_log з object_id від іншої компанії');

-- --------------------------------------------------------- Eve (стороння)
:as_eve
select t.ok((select count(*) from public.companies) = 0, 'Eve без запрошень не бачить жодної компанії');
select t.ok((select count(*) from public.construction_objects) = 0, 'Eve без запрошень не бачить жодних об''єктів');
select t.expect_err(format('select public.accept_invitation(%L)', :'tok_carol'),
                    'invitation_email_mismatch', 'Eve не може прийняти запрошення Carol');
select t.expect_err(format('select public.accept_invitation(%L)', 'deadbeef'),
                    'invitation_not_found', 'вигаданий токен не працює');

-- ------------------------------------------------------ Carol (працівник)
:as_carol
select t.ok((public.get_invitation_preview(:'tok_carol') ->> 'email_matches')::boolean, 'preview: email Carol збігається');
select public.accept_invitation(:'tok_carol') as _ \gset
select t.ok((select count(*) from public.companies) = 1, 'Carol після прийняття бачить компанію A');
select t.ok((select role from public.company_members where user_id = 'c0000000-0000-0000-0000-000000000003') = 'worker', 'Carol отримала саме запрошену роль worker');
select t.ok((select count(*) from public.construction_objects) = 0, 'працівник без призначення на об''єкт не бачить об''єктів');
select t.ok((select count(*) from public.profiles where id = 'a0000000-0000-0000-0000-000000000001') = 1, 'Carol бачить профіль колеги по компанії');
select t.ok((select count(*) from public.invitations) = 0, 'Carol не бачить запрошень');
select t.expect_err(format('select public.accept_invitation(%L)', :'tok_carol'),
                    'invitation_already_accepted', 'повторне прийняття того ж запрошення неможливе');
select t.expect_err(format('select public.create_invitation(%L, %L, %L::public.company_role)', :'co_a', 'q@x.test', 'worker'),
                    'forbidden', 'працівник не може запрошувати');
select t.expect_err(format('select public.create_object(%L, %L)', :'co_a', 'Нове'),
                    'forbidden', 'працівник не може створювати об''єкти');
select t.expect_err(format('select public.update_company_member_role(%L, %L, %L)', :'co_a', 'c0000000-0000-0000-0000-000000000003', 'admin'),
                    'forbidden', 'працівник не може підвищити себе до admin');
select t.ok(t.rows_affected(format('update public.companies set name = %L where id = %L', 'hacked', :'co_a')) = 0,
            'працівник не може змінити компанію');
select t.expect_err(format('update public.company_members set role = %L where user_id = %L', 'admin', 'c0000000-0000-0000-0000-000000000003'),
                    'permission denied', 'прямий UPDATE company_members заборонений');

-- Alice призначає Carol на об'єкт A1
:as_alice
select public.add_object_member(:'ob_a1', 'c0000000-0000-0000-0000-000000000003', 'worker') as _ \gset
select t.expect_err(format('select public.add_object_member(%L, %L, %L)', :'ob_a1', 'c0000000-0000-0000-0000-000000000003', 'worker'),
                    'already_object_member', 'повторне додавання до об''єкта відхиляється');
select t.expect_err(format('select public.add_object_member(%L, %L, %L)', :'ob_a1', 'd0000000-0000-0000-0000-000000000004', 'property_owner'),
                    'use_invitation_for_external_roles', 'зовнішні ролі призначаються лише запрошеннями');
select t.expect_err(format('select public.update_company_member_role(%L, %L, %L)', :'co_a', 'a0000000-0000-0000-0000-000000000001', 'admin'),
                    'owner_role_immutable', 'роль власника компанії незмінна');
select t.expect_err(format('select public.update_company_member_role(%L, %L, %L)', :'co_a', 'c0000000-0000-0000-0000-000000000003', 'owner'),
                    'owner_role_immutable', 'роль owner не можна призначити через RPC');

:as_carol
select t.ok((select count(*) from public.construction_objects) = 1, 'Carol бачить лише призначений об''єкт A1 (не A2)');
select t.ok((select name from public.construction_objects) = 'Квартира 12', 'це саме об''єкт A1');
select t.ok(t.rows_affected(format('update public.construction_objects set name = %L where id = %L', 'hacked', :'ob_a1')) = 0,
            'працівник на об''єкті не може його редагувати');
select t.expect_err(format('select public.add_object_member(%L, %L, %L)', :'ob_a1', 'c0000000-0000-0000-0000-000000000003', 'object_manager'),
                    'forbidden', 'працівник не може призначити себе керівником об''єкта');

-- Прораб: валідація і автоматичне членство
:as_alice
select t.expect_err(format('update public.construction_objects set foreman_id = %L where id = %L', 'c0000000-0000-0000-0000-000000000003', :'ob_a2'),
                    'invalid_foreman', 'працівник (worker) не може бути прорабом об''єкта');
select t.expect_err(format('select public.create_object(%L, %L, %L, null, null, %L, null, null, %L)', :'co_a', 'Тестовий об''єкт', 'apartment', 'planned', 'd0000000-0000-0000-0000-000000000004'),
                    'invalid_foreman', 'сторонній користувач не може бути прорабом');
select public.update_company_member_role(:'co_a', 'c0000000-0000-0000-0000-000000000003', 'foreman') as _ \gset
select t.ok(t.rows_affected(format('update public.construction_objects set foreman_id = %L where id = %L', 'c0000000-0000-0000-0000-000000000003', :'ob_a2')) = 1,
            'Alice призначила Carol прорабом об''єкта A2');
select t.ok((select role from public.object_members where object_id = :'ob_a2' and user_id = 'c0000000-0000-0000-0000-000000000003') = 'foreman',
            'прораб автоматично став учасником об''єкта A2');

:as_carol
select t.ok((select count(*) from public.construction_objects) = 2, 'Carol-прораб бачить A1 і A2');
select t.ok(t.rows_affected(format('update public.construction_objects set description = %L where id = %L', 'ок', :'ob_a2')) = 1,
            'прораб об''єкта може редагувати цей об''єкт');
select t.ok(t.rows_affected(format('update public.construction_objects set description = %L where id = %L', 'ок', :'ob_a1')) = 0,
            'але не об''єкт, де він лише працівник');
select public.create_object(:'co_a', 'Об''єкт прораба') as ob_a3 \gset
select t.ok((select role from public.object_members where object_id = :'ob_a3' and user_id = 'c0000000-0000-0000-0000-000000000003') = 'object_manager',
            'прораб компанії, що створив об''єкт, став його керівником');

-- ---------------------------------------------------- Dave (замовник)
:as_dave
select public.accept_invitation(:'tok_dave') as _ \gset
select t.ok((select count(*) from public.companies) = 1, 'замовник бачить компанію-підрядника (лише назву/контакти)');
select t.ok((select count(*) from public.construction_objects) = 1, 'замовник бачить лише свій об''єкт A1');
select t.ok((select name from public.construction_objects) = 'Квартира 12', 'це об''єкт A1');
select t.ok((select count(*) from public.company_members) = 0, 'замовник НЕ бачить список учасників компанії');
select t.ok((select count(*) from public.invitations) = 0, 'замовник НЕ бачить запрошень');
select t.ok((select count(*) from public.activity_log where object_id is null) = 0, 'замовник НЕ бачить компанійських подій');
select t.ok((select count(*) from public.activity_log where object_id = :'ob_a1') > 0, 'замовник бачить події свого об''єкта');
select t.ok((select count(*) from public.activity_log where object_id = :'ob_a2') = 0, 'замовник НЕ бачить подій іншого об''єкта');
select t.ok((select count(*) from public.profiles where id = 'a0000000-0000-0000-0000-000000000001') = 1, 'замовник бачить керівництво компанії-підрядника');
select t.ok((select count(*) from public.profiles where id = 'b0000000-0000-0000-0000-000000000002') = 0, 'замовник НЕ бачить профілі чужих компаній');
select t.ok(t.rows_affected(format('update public.construction_objects set name = %L where id = %L', 'hacked', :'ob_a1')) = 0,
            'замовник не може редагувати об''єкт');
select t.expect_err(format('select public.create_invitation(%L, %L, null, %L, %L::public.object_role)', :'co_a', 'friend@x.test', :'ob_a1', 'worker'),
                    'forbidden', 'замовник не може запрошувати');
select t.expect_err(format('select public.create_object(%L, %L)', :'co_a', 'Нове'),
                    'forbidden', 'замовник не може створювати об''єкти компанії');

-- ------------------------------------- Журнал подій, статуси й архівування
:as_alice
select t.ok(t.rows_affected(format('update public.construction_objects set status = %L where id = %L', 'active', :'ob_a1')) = 1, 'Alice змінила статус A1 на active');
select t.ok((select count(*) from public.activity_log where action = 'object.status_changed' and object_id = :'ob_a1') = 1, 'зміну статусу записано в журнал');
select t.ok(t.rows_affected(format('update public.construction_objects set status = %L where id = %L', 'archived', :'ob_a1')) = 1, 'Alice архівувала A1');
select t.ok((select archived_at is not null from public.construction_objects where id = :'ob_a1'), 'archived_at заповнено при архівуванні');
select t.ok(t.rows_affected(format('update public.construction_objects set status = %L where id = %L', 'active', :'ob_a1')) = 1, 'об''єкт можна відновити');
select t.ok((select archived_at is null from public.construction_objects where id = :'ob_a1'), 'archived_at очищено при відновленні');
select t.ok((select count(*) from public.activity_log where action = 'company.created') = 1, 'журнал містить створення компанії');
select t.ok((select count(*) from public.activity_log where action = 'invitation.accepted') >= 2, 'журнал містить прийняття запрошень');

-- ------------------- Запрошення: ротація токена, відкликання, термін дії
select (public.create_invitation(:'co_a', 'bob@b.test', 'worker'::public.company_role) ->> 'token') as tok_bob \gset
select public.revoke_invitation((select id from public.invitations where email = 'bob@b.test')) as _ \gset
:as_bob
select t.expect_err(format('select public.accept_invitation(%L)', :'tok_bob'),
                    'invitation_revoked', 'відкликане запрошення не приймається');

:as_alice
select (public.resend_invitation((select id from public.invitations where email = 'frank@a.test')) ->> 'token') as tok_frank2 \gset
select t.ok(:'tok_frank1' <> :'tok_frank2', 'повторне надсилання видає новий токен');
select t.ok((select delivery_status from public.invitations where email = 'frank@a.test') = 'not_sent',
            'delivery_status чесно лишається not_sent (лист не надсилався)');
:as_frank
select t.expect_err(format('select public.accept_invitation(%L)', :'tok_frank1'),
                    'invitation_not_found', 'старий токен після ротації не працює');

:as_super
update public.invitations set expires_at = now() - interval '1 day' where email = 'eve@evil.test';
:as_eve
select t.expect_err(format('select public.accept_invitation(%L)', :'tok_eve'),
                    'invitation_expired', 'прострочене запрошення не приймається');
:as_alice
select (public.create_invitation(:'co_a', 'eve@evil.test', 'designer'::public.company_role) ->> 'token') as tok_eve2 \gset
select t.ok(:'tok_eve2' is not null, 'нове запрошення на ту саму адресу можливе після закінчення старого');

:as_hank
select t.expect_err(format('select public.accept_invitation(%L)', :'tok_hank'),
                    'email_not_confirmed', 'користувач з непідтвердженим email не може прийняти запрошення');

-- ------------------------------------------ Видалення учасника з компанії
:as_alice
select public.remove_company_member(:'co_a', 'c0000000-0000-0000-0000-000000000003') as _ \gset
select t.expect_err(format('select public.remove_company_member(%L, %L)', :'co_a', 'a0000000-0000-0000-0000-000000000001'),
                    'owner_role_immutable', 'власника компанії видалити не можна');
select t.ok((select foreman_id is null from public.construction_objects where id = :'ob_a2'), 'після видалення прораба foreman_id очищено');
:as_carol
select t.ok((select count(*) from public.companies) = 0, 'видалений учасник більше не бачить компанію');
select t.ok((select count(*) from public.construction_objects) = 0, 'видалений учасник більше не бачить об''єкти');

-- --------------------------------------------- Підсумок ізоляції компаній
:as_alice
select t.ok((select count(distinct company_id) from public.activity_log) = 1, 'журнал Alice містить події лише однієї компанії');
:as_bob
select t.ok((select count(distinct company_id) from public.activity_log) = 1
            and (select count(*) from public.activity_log where company_id = :'co_b') >= 2,
            'журнал Bob містить лише події його компанії B');

reset role;
rollback;
\echo ВСІ ПЕРЕВІРКИ ПРОЙДЕНО

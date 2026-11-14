# STRUCTURA — Журнал розробки

## 2026-11-14 — Запис №1: архітектура та БД-фундамент

**Реалізовано**

- Документація `docs/*` (8 файлів) за фактичним станом коду.
- Схема БД Етапу 1: `profiles`, `companies`, `company_members`, `construction_objects`, `object_members`, `invitations`,
  `activity_log`; RLS, привілеї стовпців, тригери, RPC (компанії, обʼєкти, учасники, запрошення).
- SQL-тест ізоляції та шим для локальної перевірки.
- `.gitignore`, `.env.example`, `README.md`.

**Файли**

`supabase/migrations/0001…0009_*.sql`, `supabase/tests/{rls_isolation.sql,_local_supabase_shim.sql,README.md}`,
`supabase/seed/README.md`, `docs/*.md`, `.gitignore`, `.env.example`, `README.md`.

**Міграції створено:** 0001 foundation · 0002 profiles/companies · 0003 objects · 0004 invitations/activity ·
0005 helper functions · 0006 RLS & grants · 0007 triggers · 0008 RPC компаній/обʼєктів/учасників · 0009 RPC запрошень.

**Протестовано:** див. `TESTING.md` — міграції та 113 SQL-перевірок пройдено на локальному PostgreSQL 16 із шимом (не реальний Supabase).

**Проблеми / блокери**

1. Підключення репозиторію `TsAndry/STRUKTURA` до сесії **відхилено** автоматичною перевіркою дозволів → вміст репозиторію не переглянуто,
   нічого не опубліковано, коміти — лише локальні.
2. Мережа для встановлення npm-пакетів вимкнена → каркас Next.js, дизайн-система, логотип, UI **не створено**.
3. Міграції не запускались на реальному Supabase.

**Наступний крок:** дозволити доступ до репозиторію й встановлення пакетів → створити Next.js-каркас (ROADMAP, завдання 2),
застосувати міграції до Supabase і повторити `rls_isolation.sql`.

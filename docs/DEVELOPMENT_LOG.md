# STRUCTURA — Журнал розробки

## 2026-11-15 — Запис №3: геометричний рушій Measure (чистий TypeScript)

**Контекст.** Мережа для `npm install` у цій розмові досі недоступна (налаштування «Allow network egress» застосовується лише в новій розмові),
тому каркас Next.js **не створено**. Зроблено ту частину, що не потребує мережі.

**Реалізовано:** `src/features/measure/engine/` — `types`, `tolerance`, `vector`, `segment`, `polygon`, `transform`, `camera2d`, `grid`, `units`, `index`;
4 файли тестів у `__tests__/`; `tsconfig.engine.json`.

**Протестовано:** `tsc --strict` ✅; 71 unit-тест ✅ (див. `TESTING.md`, прогін №3). Під час прогону знайдено й виправлено помилку `-0` у сітці.

**Не зроблено:** Snap Engine, selection/hit-test, інструменти, Undo/Redo (2.2); підключення до UI; усе, що потребує Next.js.
Свідомо **не додано** кореневий `package.json`: його створить `create-next-app`, а зайвий файл зламав би генерацію.

**Тимчасова сторінка.** Додано статичний `index.html` у корені (темна тема, логотип із семи смуг, чесний статус «сайт у розробці»), щоб Vercel
не показував 404. Перевірено лише локально в Chromium (десктоп 1280×800 і телефон 390×844, без горизонтального переповнення); **на Vercel не перевірялось**.
Працює, поки Framework Preset у Vercel = «Other». **Видалити `index.html` при створенні Next.js-каркаса** (і тоді ж перемкнути пресет на Next.js).

**Наступний крок:** нова розмова з увімкненим «Allow network egress» → каркас Next.js у корені репозиторію (рушій уже лежить у `src/`) →
видалити `index.html` → Vercel збере застосунок → UI Етапу 1.

## 2026-11-14 — Запис №2: Measure 2.1, БД-частина; публікація в GitHub

**Контекст.** Отримано промпти Measure 2.1 і 2.2. Застосунку Етапу 1 (Next.js) ще немає, а встановлення npm-пакетів у цій
розмові недоступне (`npm` не бачить реєстр). Тому реалізовано лише ту частину 2.1, яку можна повністю перевірити без мережі.
Етап 2.2 не розпочато.

**Реалізовано**

- Репозиторій `TsAndry/STRUKTURA` підключено (на початку був лише `README.md`), документацію й БД Етапу 1 опубліковано в `main`.
- Міграція `0010_measure_projects.sql`: `measurement_projects`, `measurement_floors`, `measurement_rooms`, view `measurement_project_summaries`,
  функції прав `measure_can_*`, RPC `create_measurement_project` і `reorder_measurement_floors`, тригери (область, версії, архівування, журнал), RLS і привілеї.
- Тест `supabase/tests/measure_rls.sql`.
- Оновлено документацію: ROADMAP (плани 2.2 і 2.3), DATABASE, TESTING, ARCHITECTURE (одиниці), DECISIONS (D-015…D-019), ROLES_AND_PERMISSIONS, MASTER_PLAN.

**Файли:** `supabase/migrations/0010_measure_projects.sql`, `supabase/tests/measure_rls.sql`, `docs/*`, `README.md`.

**Міграції:** 0010.

**Протестовано:** `measure_rls.sql` — 87 перевірок ✅; регресія `rls_isolation.sql` — 113 ✅ (PG16 + шим, не реальний Supabase).

**Не зроблено / проблеми**

1. Каркас Next.js, UI Measure (сторінка, дерево, форми), CAD-робоча область, геометричний рушій — не створено. Блокер: немає застосунку Етапу 1 і мережі для `npm install`.
2. Міграції не запускались на реальному Supabase.
3. Не перевірено дії від імені `admin`/`object_manager` у Measure (див. TESTING.md).

**Наступний крок:** нова розмова з увімкненим «Allow network egress» → каркас Next.js (Етап 1, завдання 2…) → UI Measure 2.1 → Measure 2.2.

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

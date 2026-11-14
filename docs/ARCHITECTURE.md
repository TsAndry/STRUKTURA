# STRUCTURA — Архітектура

> **Статус документа.** Розділи позначені: ✅ реалізовано й перевірено, 🟡 реалізовано, але перевірено частково,
> ⬜ заплановано (коду ще немає).

## 1. Стек

| Шар | Технологія | Статус |
|---|---|---|
| Фронтенд | Next.js (App Router), React, TypeScript strict, Tailwind CSS, shadcn/ui, Lucide | ⬜ проєкт ще не створено (див. розділ 6) |
| Дані на клієнті | TanStack Query (серверні дані), Zustand (стан UI), Zod (валідація) | ⬜ |
| Бекенд | Supabase Auth + PostgreSQL + RLS + RPC-функції | 🟡 SQL-шар є й перевірений на PostgreSQL 16 із шимом; на реальному Supabase **не** запускався |
| Майбутнє | R3F/Three.js, Konva, IndexedDB, експорт PDF/Excel/CSV, Web Bluetooth | ⬜ свідомо НЕ встановлюються на Етапі 1 |

## 2. Модель безпеки (реалізована в БД)

Три рівні, усі — на сервері/БД:

1. **Привілеї стовпців і таблиць.** `anon` не має доступу до жодної таблиці. `authenticated` має `SELECT` і
   обмежений `UPDATE` лише певних стовпців (напр., `platform_role`, `owner_id`, `company_id`, `token_hash` недоступні).
2. **RLS-політики.** Видимість рядків визначається функціями `is_company_member`, `is_company_admin`,
   `can_access_object`, `can_manage_object`, `has_company_access`, `shares_context_with` (`0005`).
3. **RPC (`SECURITY DEFINER`).** Усі зміни членства, ролей, запрошень, створення компанії та обʼєкта — лише через функції,
   що перевіряють `auth.uid()` і права. Прямі `INSERT/DELETE` на ці таблиці клієнтам заборонені.

Складені зовнішні ключі `(object_id, company_id)` унеможливлюють підміну `company_id`/`object_id` навіть при помилці в коді.

`service_role` ключ не використовується в клієнтському коді (і не повинен потрапляти в браузер).

## 3. Цільова структура застосунку ⬜

```text
src/
  app/
    (auth)/                 login, register, verify-email, forgot-password, reset-password
    (platform)/             захищений layout (перевірка сесії)
      dashboard/  companies/  objects/  objects/[id]/  measure/  tools/  workforce/  settings/
    invite/[token]/         прийняття запрошення
  components/ ui/ layout/ navigation/ shared/
  features/                 auth, companies, objects, invitations (етап 1);
                            measure, tools, workforce (лише заглушки-екрани)
  lib/ supabase/ permissions/ validation/ utils/
  hooks/  stores/  types/
supabase/ migrations/ seed/ tests/
docs/
```

Зміни відносно орієнтовної структури із завдання:

- додано `invite/[token]` (публічний вхід до прийняття запрошення, потребує входу) — маршрут поза `(platform)`;
- додано `supabase/tests/` для SQL-тестів ізоляції.

## 4. Межі модулів

- Модуль живе у `src/features/<module>` і `src/app/(platform)/<module>`; власних таблиць користувачів/компаній/обʼєктів **не створює**.
- Доступ до даних — лише через `lib/supabase` (типізований клієнт) і RPC/запити модуля; жодних прямих викликів між `features/*`
  модулів (взаємодія через спільні сутності БД й публічні хуки/типи).
- Права — лише через `lib/permissions` (дзеркало SQL-функцій для UI) + RLS як істина.
- Журнал: модулі пишуть у `activity_log` через серверні функції з `module = 'measure' | 'tools' | 'workforce'`.
  *Клієнтської функції запису в журнал поки немає — її буде додано разом з першим модулем, що потребує запису.*

## 5. Запрошення та листи

Етап 1 створює захищене посилання `/invite/<token>`. Токен — 256 біт випадковості, у БД лише SHA-256 хеш;
сам токен повертається один раз при створенні/повторній видачі. **Надсилання email не реалізоване**; `delivery_status`
лишається `not_sent`. Інтерфейс має чесно показувати «скопіюйте посилання», а не «лист надіслано».

## 6. Поточне обмеження середовища

У середовищі, де створювалась ця версія, мережа для встановлення npm-пакетів вимкнена, `next`, `@supabase/*`,
`zustand`, `shadcn/ui` тощо недоступні. Тому каркас Next.js **не створено** — це не імітується. Див. `DEVELOPMENT_LOG.md`.

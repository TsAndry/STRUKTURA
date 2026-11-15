# STRUCTURA

Єдина платформа для управління будівельною компанією (Measure · Tools · Workforce).

## Поточний стан

| Частина | Стан |
|---|---|
| Документація `docs/` | ✅ |
| Етап 1: схема БД, RLS, RPC (`0001…0009`) | ✅ перевірено на PostgreSQL 16 із шимом Supabase; на реальному Supabase — ще ні |
| Етап 1: SQL-тест ізоляції компаній | ✅ 113 перевірок |
| Measure 2.1: схема БД, RLS, RPC (`0010`) | ✅ перевірено так само |
| Measure 2.1: SQL-тест | ✅ 87 перевірок |
| Геометричний рушій Measure (`src/features/measure/engine`, чистий TS) | ✅ 71 unit-тест; не підключений до UI |
| Застосунок Next.js (UI, авторизація, Dashboard, Measure UI, CAD) | ⬜ **не створено** → сайт на Vercel показує 404 |
| Measure 2.2 (редактор стін) | ⬜ не розпочато |

Деталі: `docs/ROADMAP.md`, `docs/TESTING.md`, `docs/DEVELOPMENT_LOG.md`.

## Початок роботи

1. Створіть проєкт Supabase, скопіюйте `.env.example` → `.env.local`.
2. Застосуйте міграції: `supabase db push` (або `supabase db reset` локально).
3. Перевірте: `supabase/tests/README.md` (`rls_isolation.sql`, `measure_rls.sql`).

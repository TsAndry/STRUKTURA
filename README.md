# STRUCTURA

Єдина платформа для управління будівельною компанією (Measure · Tools · Workforce).

## Поточний стан (Етап 1)

| Частина | Стан |
|---|---|
| Документація `docs/` | ✅ |
| Схема БД, RLS, RPC (`supabase/migrations`) | ✅ перевірено на PostgreSQL 16 із шимом Supabase; на реальному Supabase — ще ні |
| SQL-тест ізоляції компаній (`supabase/tests`) | ✅ 113 перевірок |
| Застосунок Next.js (UI, авторизація, Dashboard…) | ⬜ **не створено** |

Деталі: `docs/ROADMAP.md`, `docs/TESTING.md`, `docs/DEVELOPMENT_LOG.md`.

## Початок роботи

1. Створіть проєкт Supabase, скопіюйте `.env.example` → `.env.local`.
2. Застосуйте міграції: `supabase db push` (або `supabase db reset` локально).
3. Перевірте ізоляцію: див. `supabase/tests/README.md`.

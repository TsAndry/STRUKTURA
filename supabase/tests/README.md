# SQL-тести

## Реальний Supabase (локально через CLI)

```bash
supabase start && supabase db reset          # застосовує supabase/migrations
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_isolation.sql
```

Те саме для `supabase/tests/measure_rls.sql` (запускати після `0010`). Кожен скрипт виконується в транзакції й завершується `ROLLBACK`; шим не потрібен. Він вставляє тестових користувачів у `auth.users`
напряму — запускайте лише на локальній/тестовій БД, **ніколи на продакшн**.

## Чистий PostgreSQL 16 (без Supabase)

```bash
createdb structura_test
psql -v ON_ERROR_STOP=1 -d structura_test -f supabase/tests/_local_supabase_shim.sql
for f in supabase/migrations/*.sql; do psql -v ON_ERROR_STOP=1 -d structura_test -f "$f"; done
psql -v ON_ERROR_STOP=1 -d structura_test -f supabase/tests/rls_isolation.sql
psql -v ON_ERROR_STOP=1 -d structura_test -f supabase/tests/measure_rls.sql
```

Очікуваний кінець виводу: `ВСІ ПЕРЕВІРКИ ПРОЙДЕНО` та `ВСІ ПЕРЕВІРКИ MEASURE ПРОЙДЕНО`. Вимагає розширення `pgcrypto`.

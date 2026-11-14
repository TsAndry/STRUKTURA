# STRUCTURA — База даних (Етап 1)

Міграції: `supabase/migrations/0001…0009`. Статус: застосовуються без помилок на PostgreSQL 16 (із шимом Supabase) —
див. `TESTING.md`. На реальному проєкті Supabase **ще не застосовувались**.

## 1. Таблиці

| Таблиця | Призначення | Ключові обмеження |
|---|---|---|
| `profiles` | Профіль користувача, `id` = `auth.users.id` | `platform_role` недоступний для запису через API; створюється тригером `on_auth_user_created` |
| `companies` | Компанії | `owner_id` → `profiles` (restrict); назва 2–120 символів |
| `company_members` | Членство й роль у компанії | `unique(company_id,user_id)`; частковий унікальний індекс: **один `owner` на компанію** |
| `construction_objects` | Обʼєкти | `unique(id, company_id)` (для складених FK); `planned_end_date >= start_date`; `archived_at` синхронізується зі статусом |
| `object_members` | Учасники обʼєкта й роль | FK `(object_id, company_id)` → обʼєкти; `unique(object_id,user_id)` |
| `invitations` | Запрошення | зберігається лише `token_hash`; частковий унікальний індекс: одне `pending` на (компанія, обʼєкт, email); `company_role <> 'owner'`; `object_role` вимагає `object_id` |
| `activity_log` | Append-only журнал подій | FK `(object_id, company_id)`; `module` ∈ platform/measure/tools/workforce |

Enum-типи: `platform_role`, `company_role`, `object_role`, `company_status`, `object_status`, `object_type`, `invitation_status`.

## 2. Функції

**Для політик RLS** (виконуються для викликача, повертають булеве/роль): `current_company_role`, `is_company_member`,
`is_company_admin`, `is_object_member`, `has_company_access`, `can_access_object`, `can_manage_object`, `shares_context_with`.

**Внутрішні** (недоступні клієнтам): `log_activity`, `can_issue_invitation`, тригерні функції.

**RPC для клієнта** (`authenticated`):

| Функція | Що робить |
|---|---|
| `create_company(...)` | Атомарно: компанія + членство `owner` + запис у журналі. Ліміт 10 власних компаній |
| `create_object(...)` | Створює обʼєкт (ролі owner/admin/foreman); прораб компанії стає `object_manager` обʼєкта |
| `update_company_member_role` / `remove_company_member` | Керування учасниками компанії (owner незмінний; admin змінює лише не-admin) |
| `add_object_member` / `update_object_member_role` / `remove_object_member` | Керування учасниками обʼєкта (лише внутрішні ролі) |
| `create_invitation` / `resend_invitation` / `revoke_invitation` | Життєвий цикл запрошень |
| `get_invitation_preview(token)` / `accept_invitation(token)` | Для сторінки `/invite/<token>` |

Коди/повідомлення помилок (для мапінгу в UI українською): `not_authenticated`(28000), `forbidden`(42501),
`owner_role_immutable`, `cannot_change_own_role`, `member_not_found`(P0002), `invalid_company_name`, `invalid_object_name`,
`invalid_initial_status`, `invalid_foreman`, `company_limit_reached`, `invalid_email`, `invalid_ttl`, `role_required`,
`object_required_for_object_role`, `already_member`, `duplicate_pending_invitation`, `invitation_not_found`,
`invitation_email_mismatch`, `invitation_already_accepted`, `invitation_revoked`, `invitation_expired`,
`invitation_not_resendable`, `invitation_not_revocable`, `email_not_confirmed`, `already_object_member`,
`target_not_company_member`, `use_invitation_for_external_roles`, `external_role_immutable`.

## 3. Тригери

`set_updated_at` (усі таблиці), `handle_new_user`, `handle_user_email_change`, `validate_object_foreman`,
`sync_object_archived_at`, `ensure_foreman_membership`, `log_object_status_change`.

## 4. Що журнал фіксує вже зараз

`company.created`, `object.created`, `object.status_changed`, `member.added`, `member.role_changed`, `member.removed`,
`invitation.created|resent|revoked|accepted`.

## 5. Відомі обмеження / відкладене

- Немає автоматичного переведення прострочених запрошень у статус `expired` (обчислюється на льоту; запис — при новому запрошенні).
  Планується фонове завдання (`pg_cron`).
- Немає передачі володіння компанією (ownership transfer) і архівування компанії через RPC.
- Немає Storage-бакетів і політик для логотипів/аватарів (`logo_url`, `avatar_url` — лише текстові поля).
- Немає серверного обмеження частоти запитів (rate limiting) для `accept_invitation` (токен 256 біт, перебір непрактичний, але ліміт варто додати).
- Одна роль користувача на обʼєкті (див. D-006).

## 6. Заплановані розширення (не створено)

- Measure: `measurement_projects (company_id, object_id, …)`, поверхи/приміщення/елементи, геометрія, матеріали, кошториси, акти.
- Tools: `tool_models`, `tool_units`, `tool_assignments` (унікальне «поточне» розміщення), `tool_events`.
- Workforce: `worker_profiles`, `time_entries`, `work_items`, `accruals` (унікальність «робота→нарахування»), `payments`.

Усі — з `company_id`, RLS на тих самих функціях і записом у `activity_log`.

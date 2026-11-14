-- 0007_triggers.sql
-- Тригери цілісності для об'єктів.

-- Прораб об'єкта має бути учасником компанії з роллю owner/admin/foreman.
create function public.validate_object_foreman()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.foreman_id is not null and (
       tg_op = 'INSERT' or new.foreman_id is distinct from old.foreman_id
     ) then
    if not exists (
      select 1 from public.company_members cm
      where cm.company_id = new.company_id
        and cm.user_id = new.foreman_id
        and cm.role in ('owner', 'admin', 'foreman')
    ) then
      raise exception 'invalid_foreman' using errcode = '22023',
        hint = 'Прораб має бути учасником компанії з роллю власника, адміністратора або прораба.';
    end if;
  end if;
  return new;
end;
$$;

create trigger construction_objects_validate_foreman
  before insert or update of foreman_id on public.construction_objects
  for each row execute function public.validate_object_foreman();

-- Підтримка archived_at узгодженою зі статусом.
create function public.sync_object_archived_at()
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

create trigger construction_objects_sync_archived_at
  before insert or update of status on public.construction_objects
  for each row execute function public.sync_object_archived_at();

-- Призначений прораб автоматично стає учасником об'єкта з роллю foreman.
create function public.ensure_foreman_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.foreman_id is not null then
    insert into public.object_members (object_id, company_id, user_id, role, added_by)
    values (new.id, new.company_id, new.foreman_id, 'foreman', (select auth.uid()))
    on conflict (object_id, user_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger construction_objects_ensure_foreman_membership
  after insert or update of foreman_id on public.construction_objects
  for each row execute function public.ensure_foreman_membership();

-- Журнал зміни статусу об'єкта.
create function public.log_object_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is distinct from old.status then
    perform public.log_activity(
      new.company_id, new.id, (select auth.uid()), 'platform',
      'object.status_changed', 'construction_object', new.id,
      jsonb_build_object('name', new.name, 'from', old.status, 'to', new.status)
    );
  end if;
  return new;
end;
$$;

create trigger construction_objects_log_status_change
  after update of status on public.construction_objects
  for each row execute function public.log_object_status_change();

revoke all on function public.validate_object_foreman()   from public, anon, authenticated;
revoke all on function public.sync_object_archived_at()   from public, anon, authenticated;
revoke all on function public.ensure_foreman_membership() from public, anon, authenticated;
revoke all on function public.log_object_status_change()  from public, anon, authenticated;

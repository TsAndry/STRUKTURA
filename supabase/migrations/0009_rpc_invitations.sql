-- 0009_rpc_invitations.sql
-- Запрошення: створення, повторна видача (ротація токена), відкликання,
-- попередній перегляд за токеном і прийняття.
--
-- ВАЖЛИВО: цей шар лише створює захищене посилання /invite/<token>.
-- Фактичне надсилання листів НЕ реалізоване; delivery_status лишається 'not_sent'.

create function public.create_invitation(
  p_company_id   uuid,
  p_email        text,
  p_company_role public.company_role default null,
  p_object_id    uuid default null,
  p_object_role  public.object_role default null,
  p_ttl_days     integer default 7
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_token text;
  v_id    uuid;
  v_exp   timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 254 then
    raise exception 'invalid_email' using errcode = '22023';
  end if;
  if p_ttl_days is null or p_ttl_days < 1 or p_ttl_days > 30 then
    raise exception 'invalid_ttl' using errcode = '22023';
  end if;
  if p_company_role is null and p_object_role is null then
    raise exception 'role_required' using errcode = '22023';
  end if;
  if p_object_role is not null and p_object_id is null then
    raise exception 'object_required_for_object_role' using errcode = '22023';
  end if;

  if not public.can_issue_invitation(p_company_id, p_object_id, p_company_role, p_object_role) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if p_company_role is not null and exists (
    select 1
    from public.company_members cm
    join public.profiles p on p.id = cm.user_id
    where cm.company_id = p_company_id and lower(p.email) = v_email
  ) then
    raise exception 'already_member' using errcode = '23505';
  end if;

  -- Прострочені pending-запрошення для цієї ж адреси закриваємо, щоб не блокувати нове.
  update public.invitations
  set status = 'expired'
  where company_id = p_company_id
    and object_id is not distinct from p_object_id
    and email = v_email
    and status = 'pending'
    and expires_at < now();

  if exists (
    select 1 from public.invitations i
    where i.company_id = p_company_id
      and i.object_id is not distinct from p_object_id
      and i.email = v_email
      and i.status = 'pending'
  ) then
    raise exception 'duplicate_pending_invitation' using errcode = '23505';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_exp   := now() + make_interval(days => p_ttl_days);

  insert into public.invitations
    (company_id, object_id, email, company_role, object_role, invited_by, token_hash, expires_at)
  values
    (p_company_id, p_object_id, v_email, p_company_role, p_object_role, v_uid,
     encode(extensions.digest(v_token, 'sha256'), 'hex'), v_exp)
  returning id into v_id;

  perform public.log_activity(p_company_id, p_object_id, v_uid, 'platform', 'invitation.created',
                              'invitation', v_id,
                              jsonb_build_object('email', v_email, 'company_role', p_company_role,
                                                 'object_role', p_object_role));

  return jsonb_build_object('invitation_id', v_id, 'token', v_token, 'expires_at', v_exp);
end;
$$;

-- Повторна видача: ротація токена (старе посилання перестає працювати) і продовження терміну.
create function public.resend_invitation(
  p_invitation_id uuid,
  p_ttl_days      integer default 7
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_inv   public.invitations;
  v_token text;
  v_exp   timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_ttl_days is null or p_ttl_days < 1 or p_ttl_days > 30 then
    raise exception 'invalid_ttl' using errcode = '22023';
  end if;

  select * into v_inv from public.invitations where id = p_invitation_id for update;
  if not found
     or not public.can_issue_invitation(v_inv.company_id, v_inv.object_id, v_inv.company_role, v_inv.object_role)
  then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if v_inv.status not in ('pending', 'expired') then
    raise exception 'invitation_not_resendable' using errcode = '22023';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_exp   := now() + make_interval(days => p_ttl_days);

  update public.invitations
  set token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex'),
      status = 'pending',
      expires_at = v_exp,
      last_issued_at = now(),
      delivery_status = 'not_sent',
      email_sent_at = null
  where id = p_invitation_id;

  perform public.log_activity(v_inv.company_id, v_inv.object_id, v_uid, 'platform',
                              'invitation.resent', 'invitation', v_inv.id,
                              jsonb_build_object('email', v_inv.email));

  return jsonb_build_object('invitation_id', v_inv.id, 'token', v_token, 'expires_at', v_exp);
end;
$$;

create function public.revoke_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_inv public.invitations;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_inv from public.invitations where id = p_invitation_id for update;
  if not found
     or not public.can_issue_invitation(v_inv.company_id, v_inv.object_id, v_inv.company_role, v_inv.object_role)
  then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if v_inv.status <> 'pending' then
    raise exception 'invitation_not_revocable' using errcode = '22023';
  end if;

  update public.invitations set status = 'revoked', revoked_at = now()
  where id = p_invitation_id;

  perform public.log_activity(v_inv.company_id, v_inv.object_id, v_uid, 'platform',
                              'invitation.revoked', 'invitation', v_inv.id,
                              jsonb_build_object('email', v_inv.email));
end;
$$;

-- Попередній перегляд для сторінки /invite/<token>. Повертає лише необхідний мінімум
-- і лише власнику дійсного токена; повну адресу email не розкриває.
create function public.get_invitation_preview(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_inv   public.invitations;
  v_email text;
  v_cname text;
  v_oname text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_inv
  from public.invitations i
  where i.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if not found then
    raise exception 'invitation_not_found' using errcode = 'P0002';
  end if;

  select u.email into v_email from auth.users u where u.id = v_uid;
  select c.name into v_cname from public.companies c where c.id = v_inv.company_id;
  select o.name into v_oname from public.construction_objects o where o.id = v_inv.object_id;

  return jsonb_build_object(
    'company_name', v_cname,
    'object_name', v_oname,
    'company_role', v_inv.company_role,
    'object_role', v_inv.object_role,
    'status', case when v_inv.status = 'pending' and v_inv.expires_at < now()
                   then 'expired' else v_inv.status::text end,
    'expires_at', v_inv.expires_at,
    'email_matches', lower(btrim(coalesce(v_email, ''))) = v_inv.email
  );
end;
$$;

create function public.accept_invitation(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_inv       public.invitations;
  v_email     text;
  v_confirmed timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select u.email, u.email_confirmed_at into v_email, v_confirmed
  from auth.users u where u.id = v_uid;

  if v_confirmed is null then
    raise exception 'email_not_confirmed' using errcode = '42501';
  end if;

  select * into v_inv
  from public.invitations i
  where i.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
  for update;

  if not found then
    raise exception 'invitation_not_found' using errcode = 'P0002';
  end if;
  if lower(btrim(coalesce(v_email, ''))) <> v_inv.email then
    raise exception 'invitation_email_mismatch' using errcode = '42501';
  end if;
  if v_inv.status = 'accepted' then
    raise exception 'invitation_already_accepted' using errcode = '22023';
  end if;
  if v_inv.status = 'revoked' then
    raise exception 'invitation_revoked' using errcode = '22023';
  end if;
  if v_inv.status = 'expired' or v_inv.expires_at < now() then
    raise exception 'invitation_expired' using errcode = '22023';
  end if;

  -- Існуюче членство не перезаписується (запрошення не може змінити чужу роль).
  if v_inv.company_role is not null then
    insert into public.company_members (company_id, user_id, role, invited_by)
    values (v_inv.company_id, v_uid, v_inv.company_role, v_inv.invited_by)
    on conflict (company_id, user_id) do nothing;
  end if;

  if v_inv.object_role is not null then
    insert into public.object_members (object_id, company_id, user_id, role, added_by)
    values (v_inv.object_id, v_inv.company_id, v_uid, v_inv.object_role, v_inv.invited_by)
    on conflict (object_id, user_id) do nothing;
  end if;

  update public.invitations
  set status = 'accepted', accepted_by = v_uid, accepted_at = now()
  where id = v_inv.id;

  perform public.log_activity(v_inv.company_id, v_inv.object_id, v_uid, 'platform',
                              'invitation.accepted', 'invitation', v_inv.id,
                              jsonb_build_object('company_role', v_inv.company_role,
                                                 'object_role', v_inv.object_role));

  return jsonb_build_object('company_id', v_inv.company_id, 'object_id', v_inv.object_id);
end;
$$;

revoke all on function public.create_invitation(uuid, text, public.company_role, uuid, public.object_role, integer)
  from public, anon, authenticated;
revoke all on function public.resend_invitation(uuid, integer) from public, anon, authenticated;
revoke all on function public.revoke_invitation(uuid)          from public, anon, authenticated;
revoke all on function public.get_invitation_preview(text)     from public, anon, authenticated;
revoke all on function public.accept_invitation(text)          from public, anon, authenticated;

grant execute on function public.create_invitation(uuid, text, public.company_role, uuid, public.object_role, integer) to authenticated;
grant execute on function public.resend_invitation(uuid, integer) to authenticated;
grant execute on function public.revoke_invitation(uuid)          to authenticated;
grant execute on function public.get_invitation_preview(text)     to authenticated;
grant execute on function public.accept_invitation(text)          to authenticated;

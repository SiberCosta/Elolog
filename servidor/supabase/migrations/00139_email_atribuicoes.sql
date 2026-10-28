-- v70 — Encaminhar um email a um funcionário para responder (atribuição). Quem tem acesso à caixa escolhe o colega
-- adequado; esse colega vê o email em «Atribuídos», pode lê-lo e responder-lhe, mesmo sem acesso ao resto da caixa.

create table if not exists email_atribuicoes (
  id            uuid primary key default gen_random_uuid(),
  caixa_id      uuid not null references caixas_email(id) on delete cascade,
  uid           bigint not null check (uid > 0),
  de            text not null default '',
  assunto       text not null default '',
  atribuido_a   uuid not null references auth.users(id) on delete cascade,
  atribuido_por uuid references auth.users(id) on delete set null,
  nota          text check (length(nota) <= 500),
  estado        text not null default 'aberto' check (estado in ('aberto', 'respondido')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (caixa_id, uid, atribuido_a)
);
alter table email_atribuicoes enable row level security;
revoke all on email_atribuicoes from anon, authenticated;

-- Funcionário ativo do âmbito da caixa (Elolog ou a empresa da caixa).
create or replace function private.email_da_equipa(p_user uuid, p_caixa uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from caixas_email c where c.id = p_caixa and case when c.empresa_id is null
    then exists (select 1 from administradores_plataforma where user_id = p_user and ativo)
    else exists (select 1 from funcionarios where id = p_user and ativo and empresa_id = c.empresa_id) end)
$$;

-- Acesso: inclui quem só tem emails atribuídos.
create or replace function public.servico_email_acesso(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('plataforma', private.email_pode(p_user, null),
    'empresa', (select empresa_id from funcionarios where id = p_user and ativo and papel = 'admin_empresa'),
    'delegado', exists (select 1 from caixas_email_acesso a where a.user_id = p_user and private.email_usar(p_user, a.caixa_id))
             or exists (select 1 from email_atribuicoes t where t.atribuido_a = p_user and private.email_da_equipa(p_user, t.caixa_id)))
$$;

-- Credenciais (nova versão; a antiga de 2 argumentos fica sem uso): caixa inteira (email_usar) ou só a mensagem atribuída (restrito = true).
create or replace function public.servico_email_credenciais2(p_user uuid, p_caixa uuid, p_uid bigint default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r caixas_email; v_senha text; v_restrito boolean := false;
begin
  select * into r from caixas_email where id = p_caixa;
  if not found then raise exception 'Caixa de email inexistente.'; end if;
  if not private.email_usar(p_user, p_caixa) then
    if p_uid is null or not private.email_da_equipa(p_user, p_caixa)
       or not exists (select 1 from email_atribuicoes where caixa_id = p_caixa and uid = p_uid and atribuido_a = p_user) then
      raise exception 'Caixa de email inexistente.'; end if;
    v_restrito := true;
  end if;
  select decrypted_secret into v_senha from vault.decrypted_secrets where id = r.segredo_id;
  return jsonb_build_object('elolog', r.empresa_id is null, 'gerir', private.email_pode(p_user, r.empresa_id), 'restrito', v_restrito,
    'email', r.email, 'nome', r.nome, 'imap_host', r.imap_host, 'imap_porta', r.imap_porta, 'smtp_host', r.smtp_host, 'smtp_porta', r.smtp_porta,
    'utilizador', r.utilizador, 'senha', v_senha);
end $$;

-- Colegas a quem se pode encaminhar (equipa da caixa, sem o próprio).
create or replace function public.servico_email_equipa(p_user uuid, p_caixa uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid;
begin
  if not private.email_usar(p_user, p_caixa) then raise exception 'Sem acesso a esta caixa.'; end if;
  select empresa_id into v_emp from caixas_email where id = p_caixa;
  return coalesce((select jsonb_agg(x order by x->>'nome') from (
      select jsonb_build_object('user_id', a.user_id, 'nome', a.nome, 'papel', a.papel) x from administradores_plataforma a
        where v_emp is null and a.ativo and a.user_id <> p_user
      union all
      select jsonb_build_object('user_id', f.id, 'nome', f.nome, 'papel', f.papel::text) from funcionarios f
        where v_emp is not null and f.empresa_id = v_emp and f.ativo and f.id <> p_user) t), '[]'::jsonb);
end $$;

-- Encaminhar: regista a atribuição e avisa o colega no chat da equipa.
create or replace function public.servico_email_atribuir(p_user uuid, p_caixa uuid, p_uid bigint, p_alvo uuid, p_de text, p_assunto text, p_nota text)
returns void language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  if not private.email_usar(p_user, p_caixa) then raise exception 'Sem acesso a esta caixa.'; end if;
  if p_alvo = p_user or not private.email_da_equipa(p_alvo, p_caixa) then raise exception 'Escolha um colega desta equipa.'; end if;
  insert into email_atribuicoes (caixa_id, uid, de, assunto, atribuido_a, atribuido_por, nota)
  values (p_caixa, p_uid, left(coalesce(p_de, ''), 300), left(coalesce(p_assunto, ''), 300), p_alvo, p_user, nullif(left(trim(coalesce(p_nota, '')), 500), ''))
  on conflict (caixa_id, uid, atribuido_a) do update set estado = 'aberto', nota = excluded.nota, atribuido_por = excluded.atribuido_por, updated_at = now();
  select email into v_email from caixas_email where id = p_caixa;
  insert into chat_mensagens (de, para, texto) values (p_user, p_alvo, left(
    '📧 Encaminhei-lhe um email para responder (' || v_email || '): «' || coalesce(nullif(p_assunto, ''), 'sem assunto') || '» de ' || coalesce(p_de, '') ||
    coalesce(E'\nNota: ' || nullif(trim(p_nota), ''), '') || E'\nAbra Email › Atribuídos.', 2000));
end $$;

-- Emails atribuídos ao utilizador (abertos primeiro).
create or replace function public.servico_email_atribuidos(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'caixa', t.caixa_id, 'caixa_email', c.email, 'uid', t.uid, 'de', t.de, 'assunto', t.assunto,
      'nota', t.nota, 'estado', t.estado, 'data', t.created_at, 'por', coalesce((select nome from administradores_plataforma where user_id = t.atribuido_por),
      (select nome from funcionarios where id = t.atribuido_por), '')) order by t.estado, t.created_at desc), '[]'::jsonb)
  from email_atribuicoes t join caixas_email c on c.id = t.caixa_id
  where t.atribuido_a = p_user and private.email_da_equipa(p_user, t.caixa_id)
$$;

create or replace function public.servico_email_respondido(p_user uuid, p_caixa uuid, p_uid bigint) returns void
language sql security definer set search_path = public as $$
  update email_atribuicoes set estado = 'respondido', updated_at = now() where caixa_id = p_caixa and uid = p_uid and atribuido_a = p_user
$$;

revoke all on function private.email_da_equipa(uuid, uuid), public.servico_email_credenciais2(uuid, uuid, bigint), public.servico_email_equipa(uuid, uuid),
  public.servico_email_atribuir(uuid, uuid, bigint, uuid, text, text, text), public.servico_email_atribuidos(uuid), public.servico_email_respondido(uuid, uuid, bigint)
  from public, anon, authenticated;
grant execute on function public.servico_email_credenciais2(uuid, uuid, bigint), public.servico_email_equipa(uuid, uuid),
  public.servico_email_atribuir(uuid, uuid, bigint, uuid, text, text, text), public.servico_email_atribuidos(uuid), public.servico_email_respondido(uuid, uuid, bigint) to service_role;
grant select, insert, update, delete on email_atribuicoes to service_role;

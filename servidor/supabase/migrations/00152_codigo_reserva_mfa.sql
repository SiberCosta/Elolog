-- v85 — 2.ª opção de verificação: CÓDIGO DE RESERVA (para quando não há acesso ao telemóvel).
-- Quem já usa a aplicação de autenticação (administração da plataforma e administrador da empresa) gera um código fixo
-- de 16 caracteres, mostrado UMA vez. Se perder o telemóvel, entra com a palavra-passe + este código.
-- Segurança: só se gera com o telemóvel confirmado (aal2); guardado só como hash (bcrypt); 5 tentativas por 15 min;
-- cada uso fica na auditoria e gera um aviso por email; vale só para a sessão em que foi usado (12 h); pode ser trocado.

create table if not exists codigos_reserva (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  hash       text not null,
  criado_em  timestamptz not null default now(),
  usado_em   timestamptz,
  usos       int not null default 0
);
create table if not exists sessoes_reserva (
  session_id uuid primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  valida_ate timestamptz not null
);
alter table codigos_reserva enable row level security;
alter table sessoes_reserva enable row level security;
revoke all on codigos_reserva, sessoes_reserva from anon, authenticated;

-- Sessão reforçada = código da aplicação (aal2) OU código de reserva usado nesta mesma sessão.
create or replace function private.sessao_reforcada() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2' or exists (select 1 from sessoes_reserva s
    where s.session_id::text = auth.jwt() ->> 'session_id' and s.user_id = auth.uid() and s.valida_ate > now()) $$;

create or replace function private.aal2() returns boolean
language sql stable security definer set search_path = public as $$ select private.sessao_reforcada() $$;

create or replace function private.minha_empresa() returns uuid
language sql stable security definer set search_path = public as $$ select f.empresa_id from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = auth.uid() and f.ativo and (f.papel <> 'admin_empresa' or private.sessao_reforcada())
     and not exists (select 1 from acessos_temporarios t where t.user_id = f.id) $$;
create or replace function private.meu_papel() returns papel_funcionario
language sql stable security definer set search_path = public as $$ select f.papel from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = auth.uid() and f.ativo and (f.papel <> 'admin_empresa' or private.sessao_reforcada())
     and not exists (select 1 from acessos_temporarios t where t.user_id = f.id) $$;

create or replace function private.mfa_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select valor from private.plataforma_config where chave = 'exigir_mfa_admin'), 'false') <> 'true'
      or private.sessao_reforcada() $$;

-- Gerar (ou trocar) o código. Só com o telemóvel confirmado nesta sessão (não com outro código de reserva).
create or replace function public.gerar_codigo_reserva() returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_alf text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; v_b bytea := extensions.gen_random_bytes(16); v_c text := ''; i int;
begin
  if auth.uid() is null then raise exception 'SESSAO_INVALIDA'; end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'MFA_NECESSARIO: confirme primeiro o código da aplicação de autenticação.'; end if;
  for i in 0..15 loop
    v_c := v_c || substr(v_alf, (get_byte(v_b, i) % 32) + 1, 1);
    if i in (3, 7, 11) then v_c := v_c || '-'; end if;
  end loop;
  insert into codigos_reserva (user_id, hash) values (auth.uid(), extensions.crypt(v_c, extensions.gen_salt('bf', 10)))
  on conflict (user_id) do update set hash = excluded.hash, criado_em = now(), usado_em = null, usos = 0;
  insert into auditoria (user_id, acao, entidade, entidade_id) values (auth.uid(), 'codigo_reserva_gerado', 'codigos_reserva', auth.uid()::text);
  return v_c;
end $$;

create or replace function public.estado_codigo_reserva() returns table (tem boolean, criado_em timestamptz, usado_em timestamptz)
language sql stable security definer set search_path = public as $$
  select true, c.criado_em, c.usado_em from codigos_reserva c where c.user_id = auth.uid()
  union all select false, null, null where not exists (select 1 from codigos_reserva where user_id = auth.uid()) $$;

-- Usar o código: depois da palavra-passe certa (sessão aal1). Erro = devolve false (não lança, para a auditoria ficar).
create or replace function public.usar_codigo_reserva(p_codigo text) returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare v_c text := upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g')); v_h text; v_sess uuid;
begin
  if auth.uid() is null then return false; end if;
  begin v_sess := (auth.jwt() ->> 'session_id')::uuid; exception when others then v_sess := null; end;
  if v_sess is null then return false; end if;
  if not public.servico_limite('reserva:' || auth.uid(), 5, 15) then
    insert into auditoria (user_id, acao, entidade, entidade_id, depois)
      values (auth.uid(), 'bloqueio_seguranca', 'codigos_reserva', auth.uid()::text, jsonb_build_object('motivo', 'demasiadas tentativas do código de reserva'));
    return false;
  end if;
  select hash into v_h from codigos_reserva where user_id = auth.uid();
  if v_h is null or length(v_c) <> 16
     or extensions.crypt(substr(v_c,1,4)||'-'||substr(v_c,5,4)||'-'||substr(v_c,9,4)||'-'||substr(v_c,13,4), v_h) <> v_h then
    insert into auditoria (user_id, acao, entidade, entidade_id) values (auth.uid(), 'codigo_reserva_errado', 'codigos_reserva', auth.uid()::text);
    return false;
  end if;
  insert into sessoes_reserva (session_id, user_id, valida_ate) values (v_sess, auth.uid(), now() + interval '12 hours')
  on conflict (session_id) do update set valida_ate = excluded.valida_ate where sessoes_reserva.user_id = auth.uid();
  update codigos_reserva set usado_em = now(), usos = usos + 1 where user_id = auth.uid();
  insert into auditoria (user_id, acao, entidade, entidade_id) values (auth.uid(), 'codigo_reserva_usado', 'codigos_reserva', auth.uid()::text);
  insert into notificacoes (user_id, tipo, titulo, corpo)
    values (auth.uid(), 'alerta_seguranca', 'Entrada com o código de reserva',
            'Alguém entrou na sua conta com o código de reserva. Se não foi você, mude já a palavra-passe e gere um novo código.');
  return true;
end $$;

-- Para as Edge Functions: a sessão (utilizador + session_id do token já validado) está reforçada?
create or replace function public.servico_sessao_reforcada(p_user uuid, p_session text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from sessoes_reserva s where s.user_id = p_user and s.session_id::text = p_session and s.valida_ate > now()) $$;

revoke all on function public.gerar_codigo_reserva(), public.estado_codigo_reserva(), public.usar_codigo_reserva(text),
  public.servico_sessao_reforcada(uuid, text) from public, anon;
grant execute on function public.gerar_codigo_reserva(), public.estado_codigo_reserva(), public.usar_codigo_reserva(text) to authenticated;
revoke all on function public.servico_sessao_reforcada(uuid, text) from authenticated;
grant execute on function public.servico_sessao_reforcada(uuid, text) to service_role;

-- O aviso de uso também segue por email.
create or replace function private.tipo_envia_email(p_tipo text) returns boolean language sql immutable set search_path = public as $$
  select p_tipo in ('novo_prestador', 'pedido_subscricao', 'pedido_cliente', 'apoio', 'nova_simulacao', 'empresa_aprovada',
    'empresa_recusada', 'pagamento_confirmado', 'simulacao_aceite', 'simulacao_recusada', 'estado_encomenda', 'fatura_emitida',
    'pagamento_recebido', 'alerta_seguranca') $$;

-- =====================================================================
-- Elolog · 0008 · Aviso por e-mail das decisões e das notificações
-- Depende de 0001–0007.
-- Cada notificação (tabela "notificacoes") passa a gerar linhas numa fila ("emails_fila"), uma por destinatário.
-- A Edge Function "enviar-emails" (chamada por agendamento) envia-as através do Brevo.
--
--  * A fila nunca bloqueia o negócio: se a criação da fila falhar, a notificação e a decisão continuam.
--  * Só recebem e-mail endereços CONFIRMADOS no serviço de contas (auth.users.email_confirmed_at). Isto impede que
--    alguém registe uma empresa com o e-mail de outra pessoa e lhe envie avisos.
--    ATENÇÃO: com "Confirm email" DESLIGADO no Supabase todos os endereços contam como confirmados e esta proteção
--    deixa de existir. Manter ligado.
--  * O conteúdo do e-mail é montado na Edge Function (modelos testáveis); aqui só se guardam os dados da notificação.
--  * Ninguém além do service_role lê ou escreve a fila (RLS ligado, sem políticas).
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- =====================================================================

create table emails_fila (
  id                uuid primary key default gen_random_uuid(),
  notificacao_id    uuid not null references notificacoes(id) on delete cascade,
  destinatario      text not null check (length(destinatario) <= 254 and destinatario ~* '^[^\s@]+@[^\s@]+\.[^\s@]+$'),
  destino           text not null check (destino in ('plataforma', 'empresa', 'utilizador')),
  tipo              text not null,
  titulo            text not null,
  corpo             text,
  estado            text not null default 'pendente' check (estado in ('pendente', 'a_enviar', 'enviado', 'falhou')),
  tentativas        int  not null default 0,
  proxima_tentativa timestamptz not null default now(),
  reservado_ate     timestamptz,
  fornecedor_id     text,                         -- identificador devolvido pelo Brevo
  erro              text,                         -- resumo curto (nunca a chave nem o corpo do e-mail)
  enviado_em        timestamptz,
  created_at        timestamptz not null default now(),
  unique (notificacao_id, destinatario)           -- uma notificação nunca gera dois e-mails para o mesmo endereço
);
create index emails_fila_pendentes on emails_fila (proxima_tentativa) where estado in ('pendente', 'a_enviar');
create index emails_fila_enviados  on emails_fila (enviado_em) where estado = 'enviado';
create index emails_fila_destinatario on emails_fila (destinatario, created_at);

alter table emails_fila enable row level security;      -- sem políticas: só o service_role
revoke all on emails_fila from anon, authenticated;

-- ---------- 1. Que tipos de notificação geram e-mail -------------------
create function private.tipo_envia_email(p_tipo text) returns boolean
language sql immutable as $$
  select p_tipo in ('novo_prestador', 'pedido_subscricao', 'pedido_cliente', 'apoio',
                    'nova_simulacao', 'empresa_aprovada', 'empresa_recusada', 'pagamento_confirmado',
                    'simulacao_aceite', 'simulacao_recusada', 'estado_encomenda')
$$;

-- ---------- 2. Quem recebe ---------------------------------------------
--  utilizador  → a pessoa da notificação (ex.: o cliente)
--  empresa     → os administradores ativos da empresa (e, para pedidos de simulação, também os operadores)
--  plataforma  → os administradores da plataforma
-- Só endereços confirmados. Sem duplicados.
create function private.destinatarios_email(p_n notificacoes)
returns table (email text, destino text)
language sql stable security definer set search_path = public, auth as $$
  select distinct lower(u.email)::text, 'utilizador'::text
    from auth.users u
   where p_n.user_id is not null and u.id = p_n.user_id and u.email is not null and u.email_confirmed_at is not null
  union
  select distinct lower(u.email)::text, 'empresa'::text
    from funcionarios f join auth.users u on u.id = f.id
   where p_n.empresa_id is not null and p_n.user_id is null
     and f.empresa_id = p_n.empresa_id and f.ativo and u.email is not null and u.email_confirmed_at is not null
     and (f.papel = 'admin_empresa' or (p_n.tipo = 'nova_simulacao' and f.papel = 'operador'))
  union
  select distinct lower(u.email)::text, 'plataforma'::text
    from administradores_plataforma a join auth.users u on u.id = a.user_id
   where p_n.para_plataforma and u.email is not null and u.email_confirmed_at is not null
$$;

-- ---------- 3. Notificação → fila --------------------------------------
create function private.enfileirar_emails() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not private.tipo_envia_email(new.tipo) then return new; end if;
  begin
    -- Anti-inundação: ninguém recebe mais de 30 e-mails em 24 h (ex.: um cliente a gerar centenas de simulações
    -- para um prestador). Os avisos continuam a existir dentro da aplicação; só o e-mail é omitido.
    insert into emails_fila (notificacao_id, destinatario, destino, tipo, titulo, corpo)
      select new.id, d.email, d.destino, new.tipo, new.titulo, new.corpo
        from private.destinatarios_email(new) d
       where (select count(*) from emails_fila q
               where q.destinatario = d.email and q.created_at > now() - interval '24 hours') < 30
      on conflict (notificacao_id, destinatario) do nothing;
  exception when others then
    -- Um problema com a fila NUNCA pode impedir a notificação nem a decisão que a originou.
    raise warning 'Elolog: não foi possível enfileirar e-mails da notificação %: %', new.id, sqlerrm;
  end;
  return new;
end $$;

create trigger trg_notificacoes_emails after insert on notificacoes
  for each row execute function private.enfileirar_emails();

-- ---------- 4. Funções de serviço (só service_role) --------------------
-- Reserva um lote para envio. Linhas "a_enviar" cuja reserva expirou (função interrompida) voltam a ser apanhadas.
-- Também: expira o que está há mais de 3 dias na fila (ficaria desatualizado) e apaga o histórico com mais de 90 dias.
create function public.servico_reservar_emails(p_max int default 20, p_reserva_min int default 5)
returns setof emails_fila
language plpgsql security definer set search_path = public as $$
declare v_ids uuid[];
begin
  if p_max < 1 or p_max > 100 or p_reserva_min < 1 then raise exception 'Parâmetros inválidos.'; end if;

  update emails_fila set estado = 'falhou', erro = 'Expirado: mais de 3 dias na fila.'
   where estado = 'pendente' and created_at < now() - interval '3 days';
  delete from emails_fila where estado in ('enviado', 'falhou') and created_at < now() - interval '90 days';

  -- skip locked: duas chamadas em simultâneo nunca reservam as mesmas linhas
  select array_agg(s.id) into v_ids from (
    select id from emails_fila
     where (estado = 'pendente' and proxima_tentativa <= now())
        or (estado = 'a_enviar' and reservado_ate < now())
     order by created_at
     limit p_max
     for update skip locked) s;
  if v_ids is null then return; end if;

  update emails_fila
     set estado = 'a_enviar', tentativas = tentativas + 1, reservado_ate = now() + make_interval(mins => p_reserva_min)
   where id = any (v_ids);

  return query select * from emails_fila where id = any (v_ids) order by created_at;
end $$;

-- Resultado de um envio. p_resultado:
--   enviado  → feito
--   repetir  → falha temporária: volta à fila com espera crescente (2, 4, 8, 16… min, no máximo 60); ao fim de 5 tentativas falha
--   falhou   → falha definitiva (ex.: endereço inválido)
--   libertar → não chegou a ser tentado (limite do fornecedor): volta à fila sem gastar tentativa
create function public.servico_marcar_email(p_id uuid, p_resultado text, p_fornecedor_id text default null, p_erro text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare v emails_fila;
begin
  select * into v from emails_fila where id = p_id for update;
  if not found then return; end if;
  if p_resultado = 'enviado' then
    update emails_fila set estado = 'enviado', enviado_em = now(), fornecedor_id = left(p_fornecedor_id, 120),
                           erro = null, reservado_ate = null where id = p_id;
  elsif p_resultado = 'falhou' then
    update emails_fila set estado = 'falhou', erro = left(coalesce(p_erro, 'Falha definitiva.'), 300), reservado_ate = null where id = p_id;
  elsif p_resultado = 'libertar' then
    update emails_fila set estado = 'pendente', tentativas = greatest(v.tentativas - 1, 0), reservado_ate = null,
                           proxima_tentativa = now() + interval '2 minutes', erro = left(p_erro, 300) where id = p_id;
  elsif p_resultado = 'repetir' then
    if v.tentativas >= 5 then
      update emails_fila set estado = 'falhou', erro = left(coalesce(p_erro, 'Falha temporária repetida.'), 300), reservado_ate = null where id = p_id;
    else
      update emails_fila set estado = 'pendente', reservado_ate = null, erro = left(p_erro, 300),
                             proxima_tentativa = now() + make_interval(mins => least(60, (2 ^ v.tentativas)::int)) where id = p_id;
    end if;
  else
    raise exception 'Resultado desconhecido: %', p_resultado;
  end if;
end $$;

-- E-mails enviados desde as 00:00 UTC (o Brevo repõe o limite diário à meia-noite UTC).
create function public.servico_emails_enviados_hoje() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from emails_fila
   where estado = 'enviado' and enviado_em >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC')
$$;

revoke execute on function
  public.servico_reservar_emails(int, int),
  public.servico_marcar_email(uuid, text, text, text),
  public.servico_emails_enviados_hoje()
  from public, anon, authenticated;
grant execute on function
  public.servico_reservar_emails(int, int),
  public.servico_marcar_email(uuid, text, text, text),
  public.servico_emails_enviados_hoje()
  to service_role;
revoke execute on function private.tipo_envia_email(text), private.destinatarios_email(notificacoes), private.enfileirar_emails() from public;

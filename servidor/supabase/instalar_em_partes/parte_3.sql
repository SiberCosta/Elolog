-- Elolog — instalação, parte 3 de 4 (00081_emails.sql a 00133_producao_parte3.sql). Correr pela ordem: 1, 2, 3, 4.
begin;
-- ===== 00081_emails.sql =====
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


-- ===== 00091_endurecer.sql =====
-- =====================================================================
-- Elolog · 0009 · Endurecimento das permissões do papel "anon" (OPCIONAL, recomendado)
-- Depende de 0001–0008.
-- Motivo: no Supabase, cada tabela e função nova em "public" recebe por omissão permissões para anon/authenticated.
-- A 0003 revogou as tabelas do anon, mas as criadas DEPOIS (sessoes_empresa, emails_fila...) voltaram a tê-las.
-- Nada fica exposto (o RLS bloqueia e não há políticas para anon), mas é uma camada de defesa a menos.
-- O visitante sem sessão só precisa de UMA coisa: validar_empresa() (1.º passo do login do prestador).
-- É isto que o teste 01 (01_instalacao.sql) assinala como AVISO.
-- NÃO FOI EXECUTADO: aplicar primeiro no projeto de teste e voltar a correr os testes 01 e 02.
-- =====================================================================
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon;
grant  execute on function public.validar_empresa(text, text, text) to anon;

-- Objetos futuros criados por este utilizador (o SQL Editor e as migrações correm como "postgres").
-- Se criar objetos com outro papel (ex.: supabase_admin), repita com "for role <papel>".
alter default privileges for role postgres in schema public revoke all on tables    from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke execute on functions from anon;


-- ===== 00101_painel.sql =====
-- =====================================================================
-- Elolog · 0010 · Indicadores reais do painel da administração (logística transitária)
-- Depende de 0001–0009.
-- Uma só chamada devolve tudo o que o painel mostra, calculado na base de dados (só leitura):
--   prestadores, subscrições e receita, clientes, funil comercial (simulação → proposta → encomenda → entrega),
--   pipeline logístico por estado da encomenda, alertas, rotas mais pedidas, prestadores mais ativos,
--   evolução semanal e atividade recente.
-- Só a administração da plataforma a pode executar. Não devolve dados pessoais (nomes de clientes, moradas, e-mails).
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- =====================================================================
create function public.painel_administracao(p_dias int default 30)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini timestamptz;
  v_res jsonb;
begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;
  if p_dias is null or p_dias not in (7, 14, 30, 60, 90, 180) then raise exception 'Período inválido: use 7, 30 ou 90 dias (ou o dobro, para comparar com o período anterior).'; end if;
  v_ini := now() - make_interval(days => p_dias);

  select jsonb_build_object(
    'gerado_em', now(),
    'periodo_dias', p_dias,

    'prestadores', (select jsonb_build_object(
        'ativos',              count(*) filter (where estado = 'aprovada'),
        'pendentes',           count(*) filter (where estado = 'pendente'),
        'suspensos',           count(*) filter (where estado = 'suspensa'),
        'recusados',           count(*) filter (where estado = 'rejeitada'),
        'pendentes_mais_48h',  count(*) filter (where estado = 'pendente' and created_at < now() - interval '48 hours'),
        'novos_periodo',       count(*) filter (where created_at >= v_ini))
      from empresas),

    -- receita recorrente mensal: subscrições ativas (as anuais a 1/12)
    'subscricoes', (select jsonb_build_object(
        'mrr',                     coalesce(sum(case when periodicidade = 'anual' then valor / 12 else valor end) filter (where estado = 'ativa'), 0),
        'ativas',                  count(*) filter (where estado = 'ativa'),
        'pagamentos_por_confirmar', count(*) filter (where estado = 'pendente' and pago_em is null),
        'valor_por_confirmar',     coalesce(sum(valor) filter (where estado = 'pendente' and pago_em is null), 0))
      from subscricoes),

    -- recibos internos emitidos ao confirmar pagamentos
    'receita', (select jsonb_build_object(
        'periodo', coalesce(sum(valor) filter (where tipo = 'recibo' and estado = 'paga' and emitida_em >= v_ini), 0),
        'mes',     coalesce(sum(valor) filter (where tipo = 'recibo' and estado = 'paga' and emitida_em >= date_trunc('month', now())), 0))
      from faturas_plataforma),

    'clientes', (select jsonb_build_object('total', count(*), 'novos_periodo', count(*) filter (where created_at >= v_ini)) from clientes),

    'funil', jsonb_build_object(
        'simulacoes', (select count(*) from simulacoes where estado <> 'rascunho' and enviada_em >= v_ini),
        'propostas',  (select count(*) from propostas where created_at >= v_ini),
        'aceites',    (select count(*) from propostas where estado = 'aceite' and created_at >= v_ini),
        'encomendas', (select count(*) from encomendas where created_at >= v_ini),
        'entregues',  (select count(*) from encomendas where estado = 'entregue' and created_at >= v_ini)),

    -- todos os estados aparecem, mesmo a zero (a ordem do fluxo é a do enum)
    'pipeline', (select jsonb_object_agg(e::text, coalesce(c.n, 0))
                   from unnest(enum_range(null::estado_encomenda)) e
                   left join (select estado, count(*) as n from encomendas group by estado) c on c.estado = e),

    'encomendas', (select jsonb_build_object(
        'em_curso',            count(*) filter (where estado not in ('entregue', 'cancelada')),
        'valor_em_curso',      coalesce(sum(preco_total) filter (where estado not in ('entregue', 'cancelada')), 0),
        'valor_periodo',       coalesce(sum(preco_total) filter (where created_at >= v_ini and estado <> 'cancelada'), 0),
        'paradas_mais_7d',     count(*) filter (where estado not in ('entregue', 'cancelada') and updated_at < now() - interval '7 days'),
        'canceladas_periodo',  count(*) filter (where estado = 'cancelada' and created_at >= v_ini))
      from encomendas),

    'rotas', coalesce((select jsonb_agg(r) from (
        select origem, destino, count(*) as pedidos, round(avg(preco_estimado), 2) as preco_medio
          from simulacoes where estado <> 'rascunho' and enviada_em >= v_ini
         group by origem, destino order by count(*) desc, origem, destino limit 5) r), '[]'::jsonb),

    'top_prestadores', coalesce((select jsonb_agg(t) from (
        select e.nome, count(*) as encomendas, coalesce(sum(o.preco_total), 0) as valor
          from encomendas o join empresas e on e.id = o.empresa_id
         where o.created_at >= v_ini and o.estado <> 'cancelada'
         group by e.nome order by count(*) desc, e.nome limit 5) t), '[]'::jsonb),

    -- últimas 8 semanas (segunda a domingo), incluindo a corrente
    'serie_semanal', (select jsonb_agg(s order by s.semana) from (
        select to_char(w, 'YYYY-MM-DD') as semana,
               (select count(*) from encomendas o where o.created_at >= w and o.created_at < w + interval '7 days') as encomendas,
               (select coalesce(sum(o.preco_total), 0) from encomendas o
                 where o.created_at >= w and o.created_at < w + interval '7 days' and o.estado <> 'cancelada') as valor
          from generate_series(date_trunc('week', now()) - interval '7 weeks', date_trunc('week', now()), interval '1 week') w) s),

    'apoio', (select jsonb_build_object('abertos', count(*) filter (where estado <> 'resolvido'),
                                        'escalados', count(*) filter (where estado = 'escalado')) from tickets),

    -- sem motivos nem dados pessoais: só o tipo de ação, quem agiu (papel), a empresa e quando
    'atividade', coalesce((select jsonb_agg(a) from (
        select au.acao, au.papel, e.nome as empresa, au.created_at
          from auditoria au left join empresas e on e.id = au.empresa_id
         order by au.created_at desc limit 8) a), '[]'::jsonb)
  ) into v_res;

  return v_res;
end $$;

revoke execute on function public.painel_administracao(int) from public, anon;
grant  execute on function public.painel_administracao(int) to authenticated;


-- ===== 00111_mfa_admin.sql =====
-- =====================================================================
-- Elolog · 0011 · Verificação em dois passos (TOTP) para a administração da plataforma
-- Depende de 0001–0010.
-- Com a regra LIGADA, só é administrador quem tem a sessão no nível aal2 (palavra-passe + código da aplicação de autenticação),
-- em todas as políticas e funções de administração (todas passam por private.e_admin_plataforma()).
-- DESLIGADA por omissão: ligar só depois de a administração ter registado o autenticador no 1.º acesso (senão ninguém entra).
--   ligar:     update private.plataforma_config set valor = 'true'  where chave = 'exigir_mfa_admin';
--   desligar:  update private.plataforma_config set valor = 'false' where chave = 'exigir_mfa_admin';   (recuperação, no SQL Editor)
-- Requer o MFA TOTP ativo no Supabase (Authentication → Multi-factor). NÃO FOI EXECUTADO: testar primeiro num projeto de teste.
-- =====================================================================
create table private.plataforma_config (chave text primary key, valor text not null);
revoke all on private.plataforma_config from public, anon, authenticated;     -- a API nunca a lê nem escreve
insert into private.plataforma_config values ('exigir_mfa_admin', 'false');

create function private.mfa_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select valor from private.plataforma_config where chave = 'exigir_mfa_admin'), 'false') <> 'true'
      or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
$$;
grant execute on function private.mfa_ok() to authenticated, service_role;

-- Mesmas assinaturas de 0003 e 0007 (as permissões de execução mantêm-se).
create or replace function private.e_admin_plataforma() returns boolean
language sql stable security definer set search_path = public as $$
  select private.mfa_ok() and exists (select 1 from administradores_plataforma where user_id = auth.uid())
$$;

create or replace function public.sou_admin_plataforma()
returns table (ok boolean, nome text)
language sql stable security definer set search_path = public as $$
  select true, a.nome from administradores_plataforma a where a.user_id = auth.uid() and private.mfa_ok()
$$;


-- ===== 00121_avisos_seguranca.sql =====
-- =====================================================================
-- Elolog · 0012 · Correções dos avisos de segurança do Supabase (aplicada no projeto «Elolog T» a 24/10/2026)
-- Depende de 0001–0011.
--   1. A vista empresas_disponiveis passa a respeitar as permissões de quem consulta (security_invoker)
--      e deixa de estar exposta na API: só as funções do servidor a usam (calcular_propostas, enviar_simulacao),
--      e essas correm como dono, por isso continuam a ver todas as empresas aprovadas.
--   2. search_path fixo nas funções internas que ainda não o tinham.
--   3. Tabelas internas (segredos, sessões, tentativas, fila de e-mails, contadores) sem qualquer privilégio
--      para anon/authenticated. O RLS já as bloqueava; isto é uma segunda camada.
-- =====================================================================
alter view public.empresas_disponiveis set (security_invoker = true);
revoke all on public.empresas_disponiveis from anon, authenticated;

alter function private.set_updated_at()                                   set search_path = public;
alter function private.bloquear_estado_direto()                           set search_path = public;
alter function private.proteger_preco_encomenda()                         set search_path = public;
alter function private.custo_recolha_por_km()                             set search_path = public;
alter function private.preco_com_tarifa(tarifas, int, numeric, numeric)   set search_path = public;
alter function private.permissoes_validas(text[])                         set search_path = public;
alter function private.tipo_envia_email(text)                             set search_path = public;

revoke all on public.empresa_segredos, public.sessoes_empresa, public.tentativas_gate,
              public.emails_fila, public.contadores from anon, authenticated;


-- ===== 00131_producao_parte1.sql =====
-- Elolog — produção, parte 1: tarefas agendadas (emails), documentos no armazenamento e faturas certificadas.
-- Depois de aplicar: select private.agendar_tarefas('https://<projeto>.supabase.co');  (uma vez por projeto)

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- ---------- 1. Tarefas agendadas ----------------------------------------------
-- O segredo do agendador é gerado aqui e fica no cofre (vault): nunca aparece em ficheiros nem no navegador.
-- As funções de servidor leem-no com a chave de serviço (servico_segredo_cron).
create or replace function private.chamar_funcao(p_nome text, p_corpo jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_url text; v_seg text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'url_projeto';
  select decrypted_secret into v_seg from vault.decrypted_secrets where name = 'cron_secret';
  if v_url is null or v_seg is null then return null; end if;
  return net.http_post(url := v_url || '/functions/v1/' || p_nome,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_seg),
    body := p_corpo, timeout_milliseconds := 55000);
end $$;
revoke all on function private.chamar_funcao(text, jsonb) from public, anon, authenticated;

create or replace function private.agendar_tarefas(p_url text)
returns text language plpgsql security definer set search_path = '' as $$
begin
  if p_url !~ '^https://[a-z0-9-]+\.supabase\.co$' then raise exception 'Endereço do projeto inválido: %', p_url; end if;
  if exists (select 1 from vault.secrets where name = 'url_projeto') then
    update vault.secrets set secret = p_url where name = 'url_projeto';
  else perform vault.create_secret(p_url, 'url_projeto', 'Endereço do projeto (tarefas agendadas)'); end if;
  if not exists (select 1 from vault.secrets where name = 'cron_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'cron_secret', 'Segredo das funções agendadas');
  end if;
  perform cron.schedule('elolog-emails', '*/5 * * * *', $c$select private.chamar_funcao('enviar-emails')$c$);
  perform cron.schedule('elolog-navios', '7,37 * * * *', $c$select private.chamar_funcao('navios-ais')$c$);
  perform cron.schedule('elolog-pagamentos', '*/10 * * * *', $c$select private.chamar_funcao('pagamentos', '{"acao":"verificar"}'::jsonb)$c$);
  perform cron.schedule('elolog-limpar-net', '17 3 * * *', $c$delete from net._http_response where created < now() - interval '2 days'$c$);
  return 'Tarefas agendadas: emails (5 min), navios (30 min), pagamentos (10 min), limpeza diária.';
end $$;
revoke all on function private.agendar_tarefas(text) from public, anon, authenticated;

create or replace function public.servico_segredo_cron() returns text
language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret' $$;
revoke all on function public.servico_segredo_cron() from public, anon, authenticated;
grant execute on function public.servico_segredo_cron() to service_role;

-- ---------- 2. Documentos no armazenamento ------------------------------------
-- Limite de 20 MB e só formatos de documento e imagem.
update storage.buckets set file_size_limit = 20971520,
  allowed_mime_types = array['application/pdf','image/jpeg','image/png','image/webp',
    'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
  where id = 'documentos';

-- A empresa vê os documentos que o cliente juntou às encomendas dela.
drop policy if exists docs_empresa_ver_cliente on documentos;
create policy docs_empresa_ver_cliente on documentos for select to authenticated
  using (encomenda_id is not null and exists (select 1 from encomendas en
         where en.id = documentos.encomenda_id and en.empresa_id = private.minha_empresa()));

-- O cliente só junta documentos às suas encomendas (ou ao seu perfil, sem encomenda).
drop policy if exists docs_cliente_criar on documentos;
create policy docs_cliente_criar on documentos for insert to authenticated
  with check (cliente_id = auth.uid() and empresa_id is null and enviado_por = auth.uid()
    and (encomenda_id is null or exists (select 1 from encomendas en where en.id = documentos.encomenda_id and en.cliente_id = auth.uid())));

-- ---------- 3. Faturas certificadas -------------------------------------------
-- A Elolog não emite faturas: a empresa carrega o PDF do seu programa certificado pela AT.
-- O QR da fatura (Portaria 195/2020) é lido no navegador e validado aqui antes de ficar registado.
create table if not exists faturas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  encomenda_id uuid references encomendas(id) on delete set null,
  cliente_id uuid,
  documento_id uuid references documentos(id) on delete set null,
  tipo_documento text not null,            -- FT, FR, FS, NC, ND
  numero text not null,                    -- ex.: FT A/123
  atcud text not null,                     -- ex.: JJHC3KYL-123
  data_emissao date not null,
  nif_emitente text not null,
  nif_adquirente text not null,
  total numeric(12,2) not null check (total >= 0),
  total_iva numeric(12,2) not null default 0,
  hash4 text,
  certificado text,
  qr_texto text not null,
  estado text not null default 'valida' check (estado in ('valida','anulada')),
  registada_por uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  unique (empresa_id, numero),
  unique (empresa_id, atcud)
);
alter table faturas enable row level security;
create policy faturas_empresa_ver on faturas for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro','operador']));
create policy faturas_cliente_ver on faturas for select to authenticated using (cliente_id = auth.uid());
create policy faturas_admin_ver on faturas for select to authenticated using (private.e_admin_plataforma());
revoke insert, update, delete on faturas from anon, authenticated;

create or replace function private.nif_valido(p text) returns boolean language plpgsql immutable set search_path = '' as $$
declare s int := 0; i int; d int;
begin
  if p = '999999990' then return true; end if;                -- consumidor final
  if p !~ '^[1-9][0-9]{8}$' then return false; end if;
  for i in 1..8 loop s := s + substr(p, i, 1)::int * (10 - i); end loop;
  d := 11 - (s % 11); if d >= 10 then d := 0; end if;
  return d = substr(p, 9, 1)::int;
end $$;


-- ===== 00132_producao_parte2.sql =====
-- Elolog — produção, parte 2: registo de faturas certificadas e pagamentos ifthenpay (Multibanco e MB WAY).

-- ---------- 1. Registar uma fatura a partir do QR da AT ---------------------------
create or replace function public.registar_fatura(p_documento uuid, p_qr text, p_encomenda uuid default null)
returns faturas language plpgsql security definer set search_path = public as $$
declare m jsonb := '{}'; parte text; k text; v text; e empresas; en encomendas; d documentos; f faturas;
        v_total numeric; v_data date; v_faturado numeric;
begin
  if not private.papel_em(array['admin_empresa','financeiro']) then raise exception 'Só o administrador ou o financeiro registam faturas.'; end if;
  select * into e from empresas where id = private.minha_empresa();
  select * into d from documentos where id = p_documento and empresa_id = e.id;
  if d.id is null then raise exception 'Documento não encontrado nesta empresa.'; end if;
  if length(coalesce(p_qr, '')) not between 20 and 1000 then raise exception 'Código QR da fatura em falta ou inválido.'; end if;
  foreach parte in array string_to_array(p_qr, '*') loop
    k := split_part(parte, ':', 1); v := substr(parte, length(k) + 2);
    if k <> '' then m := m || jsonb_build_object(k, v); end if;
  end loop;
  if not (m ? 'A' and m ? 'B' and m ? 'D' and m ? 'F' and m ? 'G' and m ? 'H' and m ? 'O') then
    raise exception 'O QR não tem os campos obrigatórios da AT (A, B, D, F, G, H, O).'; end if;
  if regexp_replace(m->>'A', '^PT', '') <> regexp_replace(coalesce(e.nif, ''), '^PT', '') then
    raise exception 'O NIF do emitente (%) não é o NIF da empresa.', m->>'A'; end if;
  if not private.nif_valido(m->>'B') then raise exception 'NIF do cliente inválido: %', m->>'B'; end if;
  if m->>'D' not in ('FT','FR','FS','NC','ND') then raise exception 'Tipo de documento não aceite: %', m->>'D'; end if;
  if coalesce(m->>'E', 'N') = 'A' then raise exception 'Esta fatura está anulada.'; end if;
  if m->>'H' !~ '^[A-Z0-9]{8,}-[0-9]+$' then raise exception 'ATCUD inválido: %', m->>'H'; end if;
  begin v_data := to_date(m->>'F', 'YYYYMMDD'); v_total := (m->>'O')::numeric;
  exception when others then raise exception 'Data ou total ilegíveis no QR.'; end;
  if v_data > current_date or v_data < current_date - 400 then raise exception 'Data da fatura fora do intervalo aceite.'; end if;
  if p_encomenda is not null then
    select * into en from encomendas where id = p_encomenda and empresa_id = e.id;
    if en.id is null then raise exception 'Encomenda não encontrada nesta empresa.'; end if;
    if en.cliente_nif is not null and m->>'B' <> '999999990' and m->>'B' <> en.cliente_nif then
      raise exception 'O NIF do cliente na fatura (%) não corresponde ao da encomenda.', m->>'B'; end if;
    select coalesce(sum(case when tipo_documento = 'NC' then -total else total end), 0) into v_faturado
      from faturas where encomenda_id = en.id and estado = 'valida';
    if m->>'D' <> 'NC' and en.preco_total is not null and v_faturado + v_total > en.preco_total + 0.01 then
      raise exception 'O total faturado (% €) passaria o preço da encomenda (% €).', v_faturado + v_total, en.preco_total; end if;
  end if;
  insert into faturas (empresa_id, encomenda_id, cliente_id, documento_id, tipo_documento, numero, atcud, data_emissao,
    nif_emitente, nif_adquirente, total, total_iva, hash4, certificado, qr_texto)
  values (e.id, en.id, en.cliente_id, d.id, m->>'D', m->>'G', m->>'H', v_data, m->>'A', m->>'B', v_total,
    coalesce(nullif(m->>'N', '')::numeric, 0), m->>'Q', m->>'R', p_qr)
  returning * into f;
  update documentos set categoria = 'fatura', visibilidade = case when en.id is null then visibilidade else 'cliente' end,
    encomenda_id = coalesce(en.id, encomenda_id) where id = d.id;
  if en.cliente_id is not null then
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (en.cliente_id, 'fatura_emitida', 'Fatura ' || f.numero, 'A fatura da encomenda ' || en.codigo || ' já está nos seus documentos.', 'faturas', f.id);
  end if;
  insert into auditoria (empresa_id, user_id, acao, entidade, entidade_id, depois)
  values (e.id, auth.uid(), 'registar_fatura', 'faturas', f.id::text, jsonb_build_object('numero', f.numero, 'total', f.total));
  return f;
exception when unique_violation then raise exception 'Esta fatura (número ou ATCUD) já foi registada.';
end $$;
revoke all on function public.registar_fatura(uuid, text, uuid) from public, anon;
grant execute on function public.registar_fatura(uuid, text, uuid) to authenticated;

create or replace function private.tipo_envia_email(p_tipo text) returns boolean language sql immutable set search_path = public as $$
  select p_tipo in ('novo_prestador', 'pedido_subscricao', 'pedido_cliente', 'apoio', 'nova_simulacao', 'empresa_aprovada',
    'empresa_recusada', 'pagamento_confirmado', 'simulacao_aceite', 'simulacao_recusada', 'estado_encomenda', 'fatura_emitida', 'pagamento_recebido') $$;

-- ---------- 2. Configuração de pagamentos da empresa ---------------------------
-- As chaves da ifthenpay ficam numa tabela sem acesso pela aplicação; só funções de servidor as leem.
create table if not exists empresa_pagamentos_config (
  empresa_id uuid primary key references empresas(id) on delete cascade,
  mb_key text, mbway_key text, chave_antiphishing text,
  ativo boolean not null default false, sandbox boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table empresa_pagamentos_config enable row level security;
revoke all on empresa_pagamentos_config from anon, authenticated;

create or replace function public.ver_config_pagamentos() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c empresa_pagamentos_config; mascara text := '••••';
begin
  if not private.papel_em(array['admin_empresa','financeiro']) then raise exception 'Sem permissão.'; end if;
  select * into c from empresa_pagamentos_config where empresa_id = private.minha_empresa();
  return jsonb_build_object('multibanco', case when c.mb_key is null then null else mascara || right(c.mb_key, 3) end,
    'mbway', case when c.mbway_key is null then null else mascara || right(c.mbway_key, 3) end,
    'antiphishing', c.chave_antiphishing is not null, 'ativo', coalesce(c.ativo, false), 'sandbox', coalesce(c.sandbox, true));
end $$;

create or replace function public.guardar_config_pagamentos(p_mb_key text, p_mbway_key text, p_antiphishing text, p_ativo boolean, p_sandbox boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid := private.minha_empresa(); limpa text;
begin
  if not private.papel_em(array['admin_empresa']) then raise exception 'Só o administrador da empresa altera os pagamentos.'; end if;
  foreach limpa in array array[p_mb_key, p_mbway_key] loop
    if nullif(trim(limpa), '') is not null and trim(limpa) !~ '^[A-Za-z0-9-]{6,40}$' then raise exception 'Chave ifthenpay com formato inválido.'; end if;
  end loop;
  if nullif(trim(p_antiphishing), '') is not null and length(trim(p_antiphishing)) < 12 then raise exception 'A chave anti-phishing deve ter pelo menos 12 caracteres.'; end if;
  insert into empresa_pagamentos_config (empresa_id) values (v_emp) on conflict (empresa_id) do nothing;
  update empresa_pagamentos_config set
    mb_key = coalesce(nullif(trim(p_mb_key), ''), mb_key), mbway_key = coalesce(nullif(trim(p_mbway_key), ''), mbway_key),
    chave_antiphishing = coalesce(nullif(trim(p_antiphishing), ''), chave_antiphishing),
    ativo = coalesce(p_ativo, ativo), sandbox = coalesce(p_sandbox, sandbox), updated_at = now()
  where empresa_id = v_emp;
  if p_ativo and exists (select 1 from empresa_pagamentos_config where empresa_id = v_emp
                         and (chave_antiphishing is null or (mb_key is null and mbway_key is null))) then
    raise exception 'Para ativar indique a chave anti-phishing e pelo menos uma chave (Multibanco ou MB WAY).'; end if;
  insert into auditoria (empresa_id, user_id, acao, entidade, entidade_id) values (v_emp, auth.uid(), 'config_pagamentos', 'empresas', v_emp::text);
  return public.ver_config_pagamentos();
end $$;
revoke all on function public.ver_config_pagamentos(), public.guardar_config_pagamentos(text, text, text, boolean, boolean) from public, anon;
grant execute on function public.ver_config_pagamentos(), public.guardar_config_pagamentos(text, text, text, boolean, boolean) to authenticated;


-- ===== 00133_producao_parte3.sql =====
-- Elolog — produção, parte 3: pedidos de pagamento (ifthenpay) e posições reais dos navios (AIS).

-- ---------- 1. Pedidos de pagamento ---------------------------------------------
create table if not exists pedidos_pagamento (
  id uuid primary key default gen_random_uuid(),
  order_id text not null unique check (length(order_id) <= 15),
  empresa_id uuid not null references empresas(id) on delete cascade,
  encomenda_id uuid not null references encomendas(id) on delete cascade,
  cliente_id uuid not null,
  metodo text not null check (metodo in ('multibanco','mbway')),
  valor numeric(12,2) not null check (valor > 0),
  estado text not null default 'pendente' check (estado in ('pendente','pago','expirado','recusado','erro')),
  request_id text, entidade text, referencia text, telemovel text, mensagem text,
  expira_em timestamptz, pago_em timestamptz, pagamento_id uuid references pagamentos(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists pedidos_pagamento_encomenda on pedidos_pagamento (encomenda_id, estado);
alter table pedidos_pagamento enable row level security;
create policy pedidos_cliente_ver on pedidos_pagamento for select to authenticated using (cliente_id = auth.uid());
create policy pedidos_empresa_ver on pedidos_pagamento for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro','operador']));
create policy pedidos_admin_ver on pedidos_pagamento for select to authenticated using (private.e_admin_plataforma());
revoke insert, update, delete on pedidos_pagamento from anon, authenticated;

-- Só a função de servidor «pagamentos» (chave de serviço) usa as três funções abaixo.
create or replace function public.servico_preparar_pedido(p_cliente uuid, p_encomenda text, p_metodo text, p_telemovel text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare en encomendas; c empresa_pagamentos_config; v_pago numeric; v_valor numeric; p pedidos_pagamento;
begin
  select * into en from encomendas where codigo = p_encomenda and cliente_id = p_cliente;
  if en.id is null then raise exception 'Encomenda não encontrada.'; end if;
  select * into c from empresa_pagamentos_config where empresa_id = en.empresa_id and ativo;
  if c.empresa_id is null then raise exception 'Esta empresa ainda não aceita pagamentos online.'; end if;
  if p_metodo = 'multibanco' and c.mb_key is null or p_metodo = 'mbway' and c.mbway_key is null then raise exception 'Método não disponível para esta empresa.'; end if;
  if p_metodo = 'mbway' and coalesce(p_telemovel, '') !~ '^9[1236][0-9]{7}$' then raise exception 'Indique um telemóvel português válido (9 dígitos).'; end if;
  if (select count(*) from pedidos_pagamento where encomenda_id = en.id and created_at > now() - interval '1 hour') >= 6 then
    raise exception 'Demasiados pedidos de pagamento seguidos. Tente daqui a pouco.'; end if;
  select coalesce(sum(valor), 0) into v_pago from pagamentos where encomenda_id = en.id and estado = 'pago';
  v_valor := round(coalesce(en.preco_total, 0) - v_pago, 2);
  if v_valor <= 0 then raise exception 'Esta encomenda já está paga.'; end if;
  -- Reaproveita uma referência Multibanco ainda válida com o mesmo valor.
  select * into p from pedidos_pagamento where encomenda_id = en.id and metodo = 'multibanco' and p_metodo = 'multibanco'
    and estado = 'pendente' and valor = v_valor and referencia is not null and (expira_em is null or expira_em > now()) limit 1;
  if p.id is not null then return jsonb_build_object('reutilizar', true, 'pedido', to_jsonb(p)); end if;
  update pedidos_pagamento set estado = 'expirado', updated_at = now() where encomenda_id = en.id and estado = 'pendente' and metodo = p_metodo;
  insert into pedidos_pagamento (order_id, empresa_id, encomenda_id, cliente_id, metodo, valor, telemovel)
  values ('EL' || upper(substr(md5(gen_random_uuid()::text), 1, 12)), en.empresa_id, en.id, p_cliente, p_metodo, v_valor, nullif(p_telemovel, ''))
  returning * into p;
  return jsonb_build_object('reutilizar', false, 'pedido', to_jsonb(p), 'sandbox', c.sandbox,
    'chave', case when p_metodo = 'multibanco' then c.mb_key else c.mbway_key end, 'descricao', 'Encomenda ' || en.codigo);
end $$;

create or replace function public.servico_atualizar_pedido(p_id uuid, p_estado text, p_dados jsonb)
returns void language sql security definer set search_path = public as $$
  update pedidos_pagamento set estado = coalesce(p_estado, estado), request_id = coalesce(p_dados->>'request_id', request_id),
    entidade = coalesce(p_dados->>'entidade', entidade), referencia = coalesce(p_dados->>'referencia', referencia),
    expira_em = coalesce((p_dados->>'expira_em')::timestamptz, expira_em), mensagem = left(coalesce(p_dados->>'mensagem', mensagem), 300),
    updated_at = now()
  where id = p_id and estado = 'pendente' $$;

-- Confirma um pagamento (aviso da ifthenpay ou verificação do MB WAY). Repetir não paga duas vezes.
create or replace function public.servico_confirmar_pedido(p_order_id text, p_chave text, p_valor numeric, p_origem text)
returns text language plpgsql security definer set search_path = public as $$
declare p pedidos_pagamento; c empresa_pagamentos_config; v_pag uuid; en encomendas;
begin
  select * into p from pedidos_pagamento where order_id = p_order_id for update;
  if p.id is null then return 'desconhecido'; end if;
  select * into c from empresa_pagamentos_config where empresa_id = p.empresa_id;
  if p_origem = 'aviso' and (c.chave_antiphishing is null or p_chave is distinct from c.chave_antiphishing) then return 'chave_invalida'; end if;
  if p.estado = 'pago' then return 'ja_pago'; end if;
  if abs(coalesce(p_valor, -1) - p.valor) > 0.009 then return 'valor_diferente'; end if;
  insert into pagamentos (empresa_id, encomenda_id, cliente_id, tipo, valor, estado, metodo, referencia, pago_em)
  values (p.empresa_id, p.encomenda_id, p.cliente_id, 'total', p.valor, 'pago',
    case when p.metodo = 'mbway' then 'MB WAY' else 'Multibanco' end, coalesce(p.referencia, p.request_id, p.order_id), now())
  returning id into v_pag;
  update pedidos_pagamento set estado = 'pago', pago_em = now(), pagamento_id = v_pag, updated_at = now() where id = p.id;
  select * into en from encomendas where id = p.encomenda_id;
  insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  values (p.cliente_id, 'pagamento_recebido', 'Pagamento recebido', 'Recebemos ' || p.valor || ' € da encomenda ' || en.codigo || '.', 'pagamentos', v_pag);
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  values (p.empresa_id, 'pagamento_recebido', 'Pagamento recebido · ' || en.codigo, p.valor || ' € por ' || p.metodo || '.', 'pagamentos', v_pag);
  insert into auditoria (empresa_id, acao, entidade, entidade_id, depois)
  values (p.empresa_id, 'pagamento_online', 'pagamentos', v_pag::text, jsonb_build_object('metodo', p.metodo, 'valor', p.valor, 'origem', p_origem));
  return 'pago';
end $$;

-- Pedidos MB WAY à espera, para a verificação periódica (caso o aviso não chegue).
create or replace function public.servico_pedidos_mbway_pendentes() returns table (id uuid, order_id text, request_id text, valor numeric, chave text, sandbox boolean)
language plpgsql security definer set search_path = public as $$
begin
  update pedidos_pagamento pp set estado = 'expirado', updated_at = now()
    where pp.estado = 'pendente' and (pp.metodo = 'mbway' and pp.created_at < now() - interval '30 minutes' or pp.expira_em < now());
  return query select pp.id, pp.order_id, pp.request_id, pp.valor, c.mbway_key, c.sandbox from pedidos_pagamento pp
    join empresa_pagamentos_config c on c.empresa_id = pp.empresa_id
    where pp.metodo = 'mbway' and pp.estado = 'pendente' and pp.request_id is not null limit 50;
end $$;

revoke all on function public.servico_preparar_pedido(uuid, text, text, text), public.servico_atualizar_pedido(uuid, text, jsonb),
  public.servico_confirmar_pedido(text, text, numeric, text), public.servico_pedidos_mbway_pendentes() from public, anon, authenticated;
grant execute on function public.servico_preparar_pedido(uuid, text, text, text), public.servico_atualizar_pedido(uuid, text, jsonb),
  public.servico_confirmar_pedido(text, text, numeric, text), public.servico_pedidos_mbway_pendentes() to service_role;

-- ---------- 2. Navios seguidos e posições AIS -----------------------------------
create table if not exists navios_seguidos (
  empresa_id uuid not null references empresas(id) on delete cascade,
  mmsi text not null check (mmsi ~ '^[0-9]{9}$'),
  nome text not null check (length(nome) between 2 and 80),
  viagem text, created_at timestamptz not null default now(),
  primary key (empresa_id, mmsi)
);
create table if not exists navios_posicoes (
  mmsi text primary key, nome text, imo text, latitude double precision, longitude double precision,
  velocidade_nos numeric, rumo numeric, destino text, eta timestamptz, posicao_em timestamptz, atualizado_em timestamptz not null default now()
);
alter table navios_seguidos enable row level security;
alter table navios_posicoes enable row level security;
create policy navios_seguidos_empresa on navios_seguidos for all to authenticated
  using (empresa_id = private.minha_empresa()) with check (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','armazem']));
create policy navios_posicoes_ver on navios_posicoes for select to authenticated
  using (private.e_admin_plataforma() or exists (select 1 from navios_seguidos s where s.mmsi = navios_posicoes.mmsi and s.empresa_id = private.minha_empresa()));
revoke insert, update, delete on navios_posicoes from anon, authenticated;

create or replace function public.servico_navios_seguidos() returns table (mmsi text) language sql stable security definer set search_path = public as $$
  select distinct mmsi from navios_seguidos order by 1 limit 50 $$;
revoke all on function public.servico_navios_seguidos() from public, anon, authenticated;
grant execute on function public.servico_navios_seguidos() to service_role;
commit;

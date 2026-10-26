-- =====================================================================
-- Elolog · TESTE 1 — Verificação da instalação (SÓ LEITURA: não altera nada)
-- Executar no SQL Editor do projeto de TESTE depois das migrações 0001–0011.
-- Devolve uma linha por verificação: OK, AVISO (convém rever) ou FALHA (corrigir).
-- Copie o resultado (ou só as linhas AVISO/FALHA) e envie-o para análise.
-- NÃO FOI EXECUTADO por quem o escreveu: se der erro de sintaxe, envie a mensagem.
-- =====================================================================
with esperadas_tabelas(nome) as (values ('administradores_plataforma'), ('armazens'), ('auditoria'),
    ('cliente_notas'), ('clientes'), ('contadores'), ('declaracoes_carga'), ('documentos'), ('emails_fila'),
    ('empresa_segredos'), ('empresas'), ('encomenda_historico'), ('encomenda_transicoes'), ('encomendas'),
    ('entregas'), ('faturas_plataforma'), ('funcionarios'), ('manifesto_encomendas'), ('manifestos'),
    ('notificacoes'), ('pagamentos'), ('pedidos_cliente'), ('planos'), ('propostas'), ('recibos_armazem'),
    ('regras_comissao'), ('regras_conformidade'), ('regras_financeiras'), ('sessoes_empresa'), ('simulacoes'),
    ('subscricoes'), ('tarifas'), ('tentativas_gate'), ('ticket_mensagens'), ('tickets'),
    ('trabalhos_terreno'), ('veiculos')), esperadas_publicas(nome) as (values ('abrir_sessao_empresa'),
    ('aceitar_proposta'), ('aceitar_simulacao'), ('calcular_propostas'), ('cancelar_simulacao'),
    ('confirmar_pagamento_subscricao'), ('decidir_empresa'), ('enviar_simulacao'), ('recusar_simulacao'),
    ('servico_admin_empresa'), ('servico_atualizar_funcionario'), ('servico_auditar'),
    ('servico_criar_funcionario'), ('servico_emails_enviados_hoje'), ('servico_encerrar_sessoes'),
    ('servico_limite'), ('servico_marcar_email'), ('servico_obter_funcionario'), ('servico_preparar_remocao'),
    ('servico_registar_prestador'), ('servico_reservar_emails'), ('servico_utilizador_existe'),
    ('servico_verificar_limite_funcionarios'), ('painel_administracao'), ('sessao_empresa_ativa'),
    ('sou_admin_plataforma'), ('terminar_sessao_empresa'), ('transitar_encomenda'), ('validar_empresa')),
esperadas_privadas(nome) as (values ('bloquear_estado_direto'), ('cliente_visivel'), ('custo_recolha_por_km'),
    ('destinatarios_email'), ('e_admin_plataforma'), ('enfileirar_emails'), ('meu_papel'), ('mfa_ok'),
    ('minha_empresa'), ('norm'), ('notificar_plataforma'), ('papel_em'), ('permissoes_validas'),
    ('preco_com_tarifa'), ('proposta_marca_respondida'), ('proteger_preco_encomenda'),
    ('proteger_tarifa_usada'), ('proximo_codigo'), ('regras_manifesto'), ('set_updated_at'),
    ('tarifa_aplicavel'), ('tem_permissao'), ('tipo_envia_email'), ('validar_alteracao_acesso'),
    ('ve_ticket'), ('verificar_empresa')), rpc_autenticados(nome) as (values ('calcular_propostas'),
    ('enviar_simulacao'), ('cancelar_simulacao'), ('aceitar_simulacao'), ('recusar_simulacao'),
    ('transitar_encomenda'), ('aceitar_proposta'), ('decidir_empresa'), ('confirmar_pagamento_subscricao'),
    ('sou_admin_plataforma'), ('abrir_sessao_empresa'), ('terminar_sessao_empresa'), ('painel_administracao'),
    ('sessao_empresa_ativa'), ('validar_empresa')),
sem_politicas_esperado(nome) as (values ('empresa_segredos'), ('sessoes_empresa'), ('tentativas_gate'), ('emails_fila')),
r as ( -- 1. tabelas
  select 'tabelas' as area, 'todas as tabelas existem' as verificacao,
         case when count(*) = 0 then 'OK' else 'FALHA' end as resultado,
         coalesce(string_agg(e.nome, ', '), '') as detalhe from esperadas_tabelas e
   where not exists (select 1 from pg_tables t where t.schemaname = 'public' and t.tablename = e.nome)
  union all select 'tabelas', 'RLS ligado em TODAS as tabelas de public',
         case when count(*) = 0 then 'OK' else 'FALHA' end, coalesce(string_agg(c.relname, ', '), '')
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity union all
  select 'tabelas', 'tabelas internas com RLS e SEM políticas (só funções definer lhes acedem)',
         case when count(*) = 0 then 'OK' else 'FALHA' end, coalesce(string_agg(s.nome, ', '), '')
    from sem_politicas_esperado s
   where not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = s.nome and c.relrowsecurity)
      or exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = s.nome) union all
  select 'tabelas', 'outras tabelas sem nenhuma política (ninguém acede, exceto funções)',
         case when count(*) = 0 then 'OK' else 'AVISO' end, coalesce(string_agg(c.relname, ', '), '')
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and c.relname not in (select nome from sem_politicas_esperado)
     and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname)
  union all -- 2. funções
  select 'funções', 'funções públicas esperadas existem',
         case when count(*) = 0 then 'OK' else 'FALHA' end, coalesce(string_agg(e.nome, ', '), '')
    from esperadas_publicas e
   where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = e.nome)
  union all select 'funções', 'funções do schema private esperadas existem',
         case when count(*) = 0 then 'OK' else 'FALHA' end, coalesce(string_agg(e.nome, ', '), '')
    from esperadas_privadas e
   where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = e.nome)
  union all -- 3. permissões de execução
  select 'permissões', 'funções servico_* NÃO executáveis por anon nem authenticated',
         case when count(*) = 0 then 'OK' else 'FALHA' end, coalesce(string_agg(p.proname, ', '), '')
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'servico\_%'
     and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
  union all select 'permissões', 'funções servico_* executáveis pelo service_role',
         case when count(*) = 0 then 'OK' else 'FALHA' end, coalesce(string_agg(p.proname, ', '), '')
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like 'servico\_%' and not has_function_privilege('service_role', p.oid, 'execute')
  union all select 'permissões', 'RPC da aplicação executáveis por authenticated',
         case when count(*) = 0 then 'OK' else 'FALHA' end, coalesce(string_agg(x.nome, ', '), '')
    from rpc_autenticados x
   where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public' and p.proname = x.nome and has_function_privilege('authenticated', p.oid, 'execute'))
  union all select 'permissões', 'anon só executa validar_empresa',
         case when count(*) = 0 then 'OK' else 'FALHA' end, coalesce(string_agg(p.proname, ', '), '')
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname <> 'validar_empresa' and has_function_privilege('anon', p.oid, 'execute')
  union all select 'permissões', 'authenticated não executa funções public fora da lista da aplicação',
         case when count(*) = 0 then 'OK' else 'AVISO' end, coalesce(string_agg(distinct p.proname, ', '), '')
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname not in (select nome from rpc_autenticados)
     and p.proname not like 'servico\_%' and p.prokind = 'f' and has_function_privilege('authenticated', p.oid, 'execute')
  union all
  select 'permissões', 'anon sem acesso direto a tabelas (o RLS já bloqueia; 0009_endurecer.sql revoga)',
         case when count(*) = 0 then 'OK' else 'AVISO' end, coalesce(string_agg(c.relname, ', '), '')
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'v') and has_table_privilege('anon', c.oid, 'select')
  union all select 'permissões', 'segredos/filas não legíveis por authenticated (privilégio de tabela)',
         case when count(*) = 0 then 'OK' else 'AVISO' end, coalesce(string_agg(c.relname, ', '), '')
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname in ('empresa_segredos', 'sessoes_empresa', 'tentativas_gate', 'emails_fila')
     and has_table_privilege('authenticated', c.oid, 'select') union all -- 4. gatilhos
  select 'gatilhos', 'gatilho da fila de e-mails em notificacoes',
         case when count(*) = 1 then 'OK' else 'FALHA' end, ''
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where c.relname = 'notificacoes' and t.tgname = 'trg_notificacoes_emails' and not t.tgisinternal union all
  select 'gatilhos', 'gatilhos de notificação à administração (empresas, subscricoes, pedidos_cliente, tickets)',
         case when count(*) = 4 then 'OK' else 'FALHA' end, 'encontrados: ' || count(*)
    from pg_trigger t where t.tgname in ('trg_notif_empresas', 'trg_notif_subscricoes', 'trg_notif_pedidos', 'trg_notif_tickets') and not t.tgisinternal
  union all select 'gatilhos', 'estado da encomenda só muda por transitar_encomenda()',
         case when count(*) = 1 then 'OK' else 'FALHA' end, ''
    from pg_trigger t where t.tgname = 'trg_encomenda_estado_direto' and not t.tgisinternal union all
  -- 5. dados de base
  select 'dados', 'os 3 planos existem (Básico, Profissional, Empresarial)',
         case when count(*) = 3 then 'OK' else 'FALHA' end, 'encontrados: ' || count(*)
    from planos where nome in ('Básico', 'Profissional', 'Empresarial') union all
  select 'dados', 'transições de encomenda carregadas (11)',
         case when count(*) >= 11 then 'OK' else 'FALHA' end, 'encontradas: ' || count(*)
    from encomenda_transicoes union all select 'dados', 'existe pelo menos 1 administrador da plataforma',
         case when count(*) >= 1 then 'OK' else 'AVISO' end, 'encontrados: ' || count(*)
    from administradores_plataforma union all
  select 'dados', 'o administrador da plataforma tem e-mail confirmado (senão não recebe avisos)',
         case when count(*) = 0 then 'OK' else 'AVISO' end, coalesce(string_agg(u.email, ', '), '')
    from administradores_plataforma a join auth.users u on u.id = a.user_id where u.email_confirmed_at is null
  union all -- 6. extensões e infraestrutura
  select 'infraestrutura', 'extensões pgcrypto e unaccent instaladas',
         case when count(*) = 2 then 'OK' else 'FALHA' end, 'encontradas: ' || coalesce(string_agg(extname, ', '), 'nenhuma')
    from pg_extension where extname in ('pgcrypto', 'unaccent') union all
  select 'infraestrutura', 'extensões pg_cron e pg_net (necessárias para o envio de e-mails)',
         case when count(*) = 2 then 'OK' else 'AVISO' end, 'encontradas: ' || coalesce(string_agg(extname, ', '), 'nenhuma')
    from pg_extension where extname in ('pg_cron', 'pg_net') union all
  select 'infraestrutura', 'bucket privado "documentos" existe',
         case when count(*) = 1 then 'OK' else 'FALHA' end, ''
    from storage.buckets where id = 'documentos' and not public )
select area, verificacao, resultado, detalhe from r
order by case resultado when 'FALHA' then 0 when 'AVISO' then 1 else 2 end, area, verificacao;
-- Agendamento dos e-mails (só se o pg_cron existir; corra à parte se a linha acima falhou):
--   select jobname, schedule, active from cron.job where jobname = 'elolog-enviar-emails';

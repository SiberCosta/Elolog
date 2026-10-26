-- Elolog · TESTE 2 — Comportamento. Instruções e cuidados: testes/LEIA-ME.md (secção «Teste 2»).
-- Termina com um ERRO de propósito: a mensagem é o relatório e o PostgreSQL desfaz tudo o que o teste criou.
do $teste$ declare -- utilizadores
  pa   constant uuid := 'a0000000-0000-4000-8000-0000000000a1';   -- administrador da plataforma (e-mail confirmado)
  pa2  constant uuid := 'a0000000-0000-4000-8000-0000000000a2';   -- administrador da plataforma NÃO confirmado
  aa   constant uuid := 'a0000000-0000-4000-8000-000000000001';   -- administrador da empresa A (com sessão de empresa)
  oa   constant uuid := 'a0000000-0000-4000-8000-000000000002';   -- operador da empresa A (com sessão)
  ns   constant uuid := 'a0000000-0000-4000-8000-000000000003';   -- administrador da empresa A SEM sessão de empresa
  ab   constant uuid := 'a0000000-0000-4000-8000-000000000004';   -- administrador da empresa B (com sessão)
  ac   constant uuid := 'a0000000-0000-4000-8000-000000000005';   -- administrador da empresa C (com sessão de empresa)
  ac2  constant uuid := 'a0000000-0000-4000-8000-000000000007';   -- operador da empresa C
  cl   constant uuid := 'a0000000-0000-4000-8000-000000000006';   -- cliente
  -- empresas e dados
  ea   constant uuid := 'b0000000-0000-4000-8000-000000000001'; eb   constant uuid := 'b0000000-0000-4000-8000-000000000002';
  ec   constant uuid := 'b0000000-0000-4000-8000-000000000003';   -- pendente, pagamento por confirmar
  sc   constant uuid := 'c0000000-0000-4000-8000-000000000003';   -- subscrição da empresa C
  sim  constant uuid := 'd0000000-0000-4000-8000-000000000001'; v_enc uuid; v_plano uuid; v_rel text := ''; v_ok int := 0; v_total int := 0; r record; begin
  create temp table resultados (n serial, nome text, ok boolean, detalhe text, esperado text); -- Executa um teste com o papel e o utilizador indicados. p_esperado:
  --   'ok'          o SQL tem de correr sem erro
  --   'erro'        o SQL tem de falhar (permissão negada, regra violada...)
  --   'nada'        o SQL tem de falhar OU devolver 0 linhas (acesso bloqueado)
  --   'linhas=N'    o SQL tem de devolver exatamente N linhas
  --   'verdadeiro'  o SQL é uma expressão que tem de dar true
  execute $f$ create function pg_temp.t(p_nome text, p_user uuid, p_sql text, p_esperado text, p_papel text default 'authenticated', p_aal text default 'aal1')
  returns void language plpgsql as $b$ declare v_n bigint; v_ok boolean := false; v_det text := ''; begin perform set_config('request.jwt.claims',
      case when p_user is null then '{}' else json_build_object('sub', p_user, 'role', p_papel, 'aal', p_aal)::text end, true);
    execute format('set local role %I', p_papel); begin if p_esperado = 'erro' then execute p_sql; v_ok := false; v_det := 'devia ter falhado, mas passou';
      elsif p_esperado = 'nada' then execute 'select count(*) from (' || p_sql || ') q' into v_n; v_ok := v_n = 0; v_det := 'linhas=' || v_n;
      elsif p_esperado like 'linhas=%' then execute 'select count(*) from (' || p_sql || ') q' into v_n;
        v_ok := v_n = substr(p_esperado, 8)::bigint; v_det := 'linhas=' || v_n || ' (esperado ' || substr(p_esperado, 8) || ')'; elsif p_esperado = 'verdadeiro' then
        execute 'select coalesce((' || p_sql || ')::boolean, false)' into v_ok; v_det := coalesce(v_ok::text, 'null'); else execute p_sql; v_ok := true; end if;
    exception when others then if p_esperado = 'erro' then v_ok := true; v_det := left(sqlerrm, 90);
      elsif p_esperado = 'nada' then v_ok := true; v_det := 'bloqueado: ' || left(sqlerrm, 70); else v_ok := false; v_det := left(sqlerrm, 220); end if; end;
    reset role; insert into resultados (nome, ok, detalhe, esperado) values (p_nome, v_ok, v_det, p_esperado); end $b$ $f$;
  -- ------------------------------------------------------------------ preparação (como administrador da base de dados)
  insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
  select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email,
         case when confirmado then now() end, now(), now(), '{}'::jsonb, '{}'::jsonb from (values (pa,  'plataforma@teste.elolog.invalid',  true),
      (pa2, 'plataforma2@teste.elolog.invalid', false), (aa,  'admin-a@teste.elolog.invalid',     true), (oa,  'operador-a@teste.elolog.invalid',  true),
      (ns,  'semsessao-a@teste.elolog.invalid', true), (ab,  'admin-b@teste.elolog.invalid',     true), (ac,  'admin-c@teste.elolog.invalid',     true),
      (ac2, 'operador-c@teste.elolog.invalid',  true), (cl,  'cliente@teste.elolog.invalid',     true)) v(id, email, confirmado);
  -- administradores da plataforma ANTES das empresas: os gatilhos de aviso encontram-nos
  insert into administradores_plataforma (user_id, nome) values (pa, 'Administração (teste)'), (pa2, 'Administração não confirmada (teste)');
  select id into v_plano from planos where nome = 'Básico';
  if v_plano is null then raise exception 'Preparação: o plano "Básico" não existe (a migração 0002 não foi aplicada?).'; end if;
  insert into empresas (id, nome, nif, email, estado, aprovada_em) values (ea, 'Empresa A (teste)', 'TESTE-A', 'a@teste.elolog.invalid', 'aprovada', now()),
    (eb, 'Empresa B (teste)', 'TESTE-B', 'b@teste.elolog.invalid', 'aprovada', now()),
    (ec, 'Empresa C (teste)', 'TESTE-C', 'c@teste.elolog.invalid', 'pendente', null);
  insert into subscricoes (empresa_id, plano_id, estado, valor, pago_em) values (ea, v_plano, 'ativa', 29, now()), (eb, v_plano, 'ativa', 29, now());
  insert into subscricoes (id, empresa_id, plano_id, estado, valor, metodo_pagamento, referencia) values (sc, ec, v_plano, 'pendente', 29, 'teste', 'REF-TESTE-C');
  insert into funcionarios (id, empresa_id, nome, email, papel) values (aa, ea, 'Admin A',        'admin-a@teste.elolog.invalid',     'admin_empresa'),
    (oa, ea, 'Operador A',     'operador-a@teste.elolog.invalid',  'operador'),
    (ns, ea, 'Admin A (sem sessão)', 'semsessao-a@teste.elolog.invalid', 'admin_empresa'),
    (ab, eb, 'Admin B',        'admin-b@teste.elolog.invalid',     'admin_empresa'), (ac, ec, 'Admin C',        'admin-c@teste.elolog.invalid',     'admin_empresa'),
    (ac2, ec, 'Operador C',    'operador-c@teste.elolog.invalid',  'operador'); insert into sessoes_empresa (user_id, empresa_id, valida_ate) values
    (aa, ea, now() + interval '1 hour'), (oa, ea, now() + interval '1 hour'), (ab, eb, now() + interval '1 hour'), (ac, ec, now() + interval '1 hour');
  insert into clientes (id, nome, email) values (cl, 'Cliente (teste)', 'cliente@teste.elolog.invalid');
  insert into tarifas (empresa_id, nome, aplicacao, tipo_carga, metodo, valor, preco_minimo, origem, destino, regras)
    values (ea, 'Lisboa → Luanda (comercial, por peso)', 'carga', 'Comercial', 'peso'::metodo_cobranca, 1.20, 60, 'Lisboa', 'Luanda', '{"volumetricFactor":167}'::jsonb);
  insert into simulacoes (id, cliente_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3)
    values (sim, cl, 'Lisboa', 'Luanda', 'Comercial', 'Caixas de teste', 2, 20, 0.4);
  -- ------------------------------------------------------------------ 1. isolamento entre empresas e segredos
  perform pg_temp.t('1.1 admin A vê os 3 funcionários da SUA empresa', aa, 'select * from funcionarios', 'linhas=3');
  perform pg_temp.t('1.2 admin A não vê funcionários da empresa B', aa, format('select * from funcionarios where empresa_id = %L', eb), 'nada');
  perform pg_temp.t('1.3 admin B só vê o seu funcionário', ab, 'select * from funcionarios', 'linhas=1');
  perform pg_temp.t('1.4 admin SEM sessão de empresa só vê a própria linha (o 2.º nível funciona)', ns, 'select * from funcionarios', 'linhas=1');
  perform pg_temp.t('1.5 admin A não altera funcionários diretamente (só pela Edge Function)', aa, format('update funcionarios set ativo = false where id = %L', oa), 'erro');
  perform pg_temp.t('1.6 admin A não lê a senha da empresa', aa, 'select * from empresa_segredos', 'nada');
  perform pg_temp.t('1.7 admin A não lê as sessões de empresa', aa, 'select * from sessoes_empresa', 'nada');
  perform pg_temp.t('1.8 admin A não lê a fila de e-mails', aa, 'select * from emails_fila', 'nada');
  perform pg_temp.t('1.9 anónimo não lê empresas', null, 'select * from empresas', 'nada', 'anon');
  perform pg_temp.t('1.10 cliente não lê tarifas', cl, 'select * from tarifas', 'nada');
  perform pg_temp.t('1.11 utilizador autenticado não executa funções de serviço', aa, $$select public.servico_limite('x', 1, 1)$$, 'erro');
  perform pg_temp.t('1.12 admin A não vê dados de pagamento da subscrição da empresa B', aa, format('select * from subscricoes where empresa_id = %L', eb), 'nada');
  -- ------------------------------------------------------------------ 2. preços calculados no servidor
  perform pg_temp.t('2.1 calcular_propostas: empresa A cobra 80,16 €', cl,
    format($$select (select preco_total from public.calcular_propostas('Lisboa', 'Luanda', 'Comercial', 2, 20, 0.4, 0) where prestador_id = %L) = 80.16$$, ea), 'verdadeiro');
  perform pg_temp.t('2.2 calcular_propostas: empresa B (sem tarifa) aparece como indisponível', cl,
    format($$select (select disponivel from public.calcular_propostas('Lisboa', 'Luanda', 'Comercial', 2, 20, 0.4, 0) where prestador_id = %L) = false$$, eb), 'verdadeiro');
  perform pg_temp.t('2.3 um prestador não usa calcular_propostas (não é cliente)', aa, $$select * from public.calcular_propostas('Lisboa', 'Luanda', 'Comercial', 2, 20, 0.4, 0)$$, 'erro');
  -- ------------------------------------------------------------------ 3. simulação → encomenda
  perform pg_temp.t('3.1 cliente cria uma simulação (rascunho) com as colunas permitidas', cl,
    format($$insert into simulacoes (cliente_id, origem, destino, tipo_carga, quantidade, peso_kg, volume_m3, remetente, destinatario, data_prevista)
             values (%L, 'Porto', 'Luanda', 'Comercial', 1, 5, 0.1, '{}', '{}', current_date)$$, cl), 'ok');
  perform pg_temp.t('3.2 cliente NÃO cria uma simulação já "enviada"', cl,
    format($$insert into simulacoes (cliente_id, origem, destino, estado) values (%L, 'Porto', 'Luanda', 'enviada')$$, cl), 'erro');
  perform pg_temp.t('3.3 cliente NÃO define o preço estimado', cl,
    format($$insert into simulacoes (cliente_id, origem, destino, preco_estimado) values (%L, 'Porto', 'Luanda', 1)$$, cl), 'erro');
  perform pg_temp.t('3.4 cliente envia a simulação ao prestador (enviar_simulacao)', cl, format('select public.enviar_simulacao(%L, %L)', sim, ea), 'ok');
  perform pg_temp.t('3.5 o preço guardado é o do servidor (80,16) e o estado é "enviada"', cl,
    format($$select (select preco_estimado = 80.16 and estado::text = 'enviada' from simulacoes where id = %L)$$, sim), 'verdadeiro');
  perform pg_temp.t('3.6 admin B não vê a simulação enviada à empresa A', ab, format('select * from simulacoes where id = %L', sim), 'nada');
  perform pg_temp.t('3.7 admin A vê a simulação', aa, format('select * from simulacoes where id = %L', sim), 'linhas=1');
  perform pg_temp.t('3.8 admin A aceita a simulação (aceitar_simulacao)', aa, format('select public.aceitar_simulacao(%L)', sim), 'ok');
  select id into v_enc from encomendas where simulacao_id = sim;
  perform pg_temp.t('3.9 a encomenda nasce em "aprovacao"', aa, format($$select (select estado::text from encomendas where id = %L) = 'aprovacao'$$, v_enc), 'verdadeiro');
  perform pg_temp.t('3.10 salto de estado recusado (aprovacao → recolha)', aa, format($$select public.transitar_encomenda(%L, 'recolha'::estado_encomenda, 'x')$$, v_enc), 'erro');
  perform pg_temp.t('3.11 transição válida (aprovacao → agendamento)', aa, format($$select public.transitar_encomenda(%L, 'agendamento'::estado_encomenda, 'x')$$, v_enc), 'ok');
  perform pg_temp.t('3.12 o estado não se altera diretamente', aa, format($$update encomendas set estado = 'cancelada' where id = %L$$, v_enc), 'erro');
  perform pg_temp.t('3.13 admin B não vê a encomenda da empresa A', ab, 'select * from encomendas', 'nada');
  perform pg_temp.t('3.14 cliente vê a notificação "simulacao_aceite"', cl, $$select count(*) >= 1 from notificacoes where tipo = 'simulacao_aceite'$$, 'verdadeiro');
  -- ------------------------------------------------------------------ 4. administração: pagamento, autorização, suspensão
  perform pg_temp.t('4.0 enquanto a empresa C está PENDENTE o seu administrador só vê a própria linha', ac, 'select * from funcionarios', 'linhas=1');
  perform pg_temp.t('4.1 autorizar a empresa C SEM pagamento confirmado é recusado', pa, format('select public.decidir_empresa(%L, true, null)', ec), 'erro');
  perform pg_temp.t('4.2 um admin de empresa não decide sobre empresas', aa, format('select public.decidir_empresa(%L, true, null)', ec), 'erro');
  perform pg_temp.t('4.3 um cliente não confirma pagamentos', cl, format('select public.confirmar_pagamento_subscricao(%L, null)', sc), 'erro');
  perform pg_temp.t('4.4 a administração confirma o pagamento', pa, format($$select public.confirmar_pagamento_subscricao(%L, 'nota de teste')$$, sc), 'ok');
  perform pg_temp.t('4.5 o pagamento não se confirma duas vezes', pa, format('select public.confirmar_pagamento_subscricao(%L, null)', sc), 'erro');
  perform pg_temp.t('4.6 foi criado 1 recibo interno', pa, format($$select count(*) = 1 from faturas_plataforma where empresa_id = %L and tipo = 'recibo'$$, ec), 'verdadeiro');
  perform pg_temp.t('4.7 a administração autoriza a empresa C', pa, format('select public.decidir_empresa(%L, true, null)', ec), 'ok');
  perform pg_temp.t('4.8 empresa C aprovada e subscrição ativa', pa,
    format($$select (select estado::text from empresas where id = %L) = 'aprovada' and (select estado::text from subscricoes where id = %L) = 'ativa'$$, ec, sc), 'verdadeiro');
  perform pg_temp.t('4.8b depois de aprovada, o administrador de C vê os 2 funcionários da empresa', ac, 'select * from funcionarios', 'linhas=2');
  perform pg_temp.t('4.9 suspender SEM motivo é recusado', pa, format($$select public.decidir_empresa(%L, false, '')$$, ec), 'erro');
  perform pg_temp.t('4.10 suspender com motivo', pa, format($$select public.decidir_empresa(%L, false, 'Teste de suspensão')$$, ec), 'ok');
  perform pg_temp.t('4.11 empresa suspensa: o acesso aos dados da empresa é cortado de imediato (volta a ver só a própria linha)', ac, 'select * from funcionarios', 'linhas=1');
  perform pg_temp.t('4.12 reativar a empresa', pa, format('select public.decidir_empresa(%L, true, null)', ec), 'ok');
  perform pg_temp.t('4.13 reativar retoma a subscrição (correção da 0007)', pa, format($$select (select estado::text from subscricoes where id = %L) = 'ativa'$$, sc), 'verdadeiro');
  perform pg_temp.t('4.14 sou_admin_plataforma: o administrador da plataforma é reconhecido', pa,
    $$select (select count(*) from public.sou_admin_plataforma()) = 1$$, 'verdadeiro');
  perform pg_temp.t('4.15 sou_admin_plataforma: cliente não é administrador', cl, $$select (select count(*) from public.sou_admin_plataforma()) = 0$$, 'verdadeiro');
  -- ------------------------------------------------------------------ 4b. indicadores do painel da administração
  -- Estado neste ponto: A, B e C aprovadas (3 ativas); 1 cliente; 1 simulação enviada→convertida em 1 encomenda,
  -- agora em "agendamento"; 1 recibo de 29 € (empresa C); 1 subscrição por confirmar: nenhuma.
  perform pg_temp.t('4b.1 painel: só a administração da plataforma o pode pedir', aa, 'select public.painel_administracao(30)', 'erro');
  perform pg_temp.t('4b.2 painel: um cliente também não', cl, 'select public.painel_administracao(30)', 'erro');
  perform pg_temp.t('4b.3 painel: período inválido (15 dias) é recusado', pa, 'select public.painel_administracao(15)', 'erro');
  perform pg_temp.t('4b.4 painel: 3 prestadores ativos e nenhum pendente', pa,
    $$select (public.painel_administracao(30) -> 'prestadores' ->> 'ativos')::int = 3 and (public.painel_administracao(30) -> 'prestadores' ->> 'pendentes')::int = 0$$, 'verdadeiro');
  perform pg_temp.t('4b.5 painel: 1 encomenda em "agendamento" e todos os 9 estados presentes no pipeline', pa,
    $$select (public.painel_administracao(30) -> 'pipeline' ->> 'agendamento')::int = 1
          and (select count(*) from jsonb_object_keys(public.painel_administracao(30) -> 'pipeline')) = 9$$, 'verdadeiro');
  perform pg_temp.t('4b.6 painel: funil com 1 simulação, 1 aceite e 1 encomenda', pa, $$select (public.painel_administracao(30) -> 'funil' ->> 'simulacoes')::int = 1
          and (public.painel_administracao(30) -> 'funil' ->> 'aceites')::int = 1
          and (public.painel_administracao(30) -> 'funil' ->> 'encomendas')::int = 1$$, 'verdadeiro');
  perform pg_temp.t('4b.7 painel: receita do período = 29 € (o recibo da empresa C) e 0 pagamentos por confirmar', pa,
    $$select (public.painel_administracao(30) -> 'receita' ->> 'periodo')::numeric = 29
          and (public.painel_administracao(30) -> 'subscricoes' ->> 'pagamentos_por_confirmar')::int = 0$$, 'verdadeiro');
  perform pg_temp.t('4b.8 painel: a rota Lisboa → Luanda aparece com 1 pedido e preço médio 80,16', pa,
    $$select (public.painel_administracao(30) -> 'rotas' -> 0 ->> 'origem') = 'Lisboa' and (public.painel_administracao(30) -> 'rotas' -> 0 ->> 'pedidos')::int = 1
          and (public.painel_administracao(30) -> 'rotas' -> 0 ->> 'preco_medio')::numeric = 80.16$$, 'verdadeiro');
  perform pg_temp.t('4b.9 painel: série semanal com 8 semanas e 1 cliente', pa, $$select jsonb_array_length(public.painel_administracao(30) -> 'serie_semanal') = 8
          and (public.painel_administracao(30) -> 'clientes' ->> 'total')::int = 1$$, 'verdadeiro');
  perform pg_temp.t('4b.10 painel: a atividade recente não traz motivos nem dados pessoais (só 4 campos)', pa,
    $$select not exists (select 1 from jsonb_array_elements(public.painel_administracao(30) -> 'atividade') a
                          where (select array_agg(k order by k) from jsonb_object_keys(a) k) <> array['acao', 'created_at', 'empresa', 'papel'])$$, 'verdadeiro');
  -- ------------------------------------------------------------------ 4c. verificação em dois passos da administração (0011)
  perform pg_temp.t('4c.1 por omissão a regra está desligada: a administração entra só com a palavra-passe (aal1)', pa, 'select * from public.sou_admin_plataforma()', 'linhas=1');
  update private.plataforma_config set valor = 'true' where chave = 'exigir_mfa_admin';
  perform pg_temp.t('4c.2 regra LIGADA: sem o 2.º passo (aal1) já não é administradora', pa, 'select * from public.sou_admin_plataforma()', 'nada');
  perform pg_temp.t('4c.3 regra LIGADA: sem o 2.º passo as funções de administração recusam', pa, 'select public.painel_administracao(30)', 'erro');
  perform pg_temp.t('4c.4 regra LIGADA: sem o 2.º passo não lê as tabelas de administração', pa, 'select * from empresas', 'nada');
  perform pg_temp.t('4c.5 regra LIGADA: com o 2.º passo (aal2) é administradora', pa, 'select * from public.sou_admin_plataforma()', 'linhas=1', 'authenticated', 'aal2');
  perform pg_temp.t('4c.6 regra LIGADA: com o 2.º passo as funções de administração funcionam', pa, 'select public.painel_administracao(30)', 'ok', 'authenticated', 'aal2');
  perform pg_temp.t('4c.7 regra LIGADA: com o 2.º passo lê as empresas', pa, 'select * from empresas', 'linhas=3', 'authenticated', 'aal2');
  perform pg_temp.t('4c.8 o aal2 de quem não é administrador não dá poderes', cl, 'select * from public.sou_admin_plataforma()', 'nada', 'authenticated', 'aal2');
  perform pg_temp.t('4c.9 a configuração não é legível nem alterável pela API', pa, 'select * from private.plataforma_config', 'erro', 'authenticated', 'aal2');
  perform pg_temp.t('4c.10 nem a administração altera a regra pela API', pa, $$update private.plataforma_config set valor = 'false'$$, 'erro', 'authenticated', 'aal2');
  update private.plataforma_config set valor = 'false' where chave = 'exigir_mfa_admin';   -- os grupos seguintes correm com a regra desligada, como por omissão
  -- ------------------------------------------------------------------ 5. fila de e-mails
  perform pg_temp.t('5.1 o administrador confirmado da plataforma recebe o aviso de novo prestador', null,
    $$select count(*) >= 1 from emails_fila where destinatario = 'plataforma@teste.elolog.invalid' and tipo = 'novo_prestador'$$, 'verdadeiro', 'postgres');
  perform pg_temp.t('5.2 o administrador NÃO confirmado não recebe nada', null,
    $$select count(*) = 0 from emails_fila where destinatario = 'plataforma2@teste.elolog.invalid'$$, 'verdadeiro', 'postgres');
  perform pg_temp.t('5.3 a empresa C recebe o aviso de pagamento confirmado', null,
    $$select count(*) >= 1 from emails_fila where destinatario = 'admin-c@teste.elolog.invalid' and tipo = 'pagamento_confirmado'$$, 'verdadeiro', 'postgres');
  perform pg_temp.t('5.4 o cliente recebe o aviso de simulação aceite', null,
    $$select count(*) >= 1 from emails_fila where destinatario = 'cliente@teste.elolog.invalid' and tipo = 'simulacao_aceite'$$, 'verdadeiro', 'postgres');
  perform pg_temp.t('5.5 o operador da empresa A recebe o aviso de nova simulação (e a empresa B não)', null,
    $$select (select count(*) from emails_fila where destinatario = 'operador-a@teste.elolog.invalid' and tipo = 'nova_simulacao') >= 1
          and (select count(*) from emails_fila where destinatario = 'admin-b@teste.elolog.invalid') = 0$$, 'verdadeiro', 'postgres');
  insert into notificacoes (empresa_id, tipo, titulo) select ea, 'empresa_aprovada', 'Teste ' || g from generate_series(1, 40) g;
  perform pg_temp.t('5.6 anti-inundação: no máximo 30 e-mails por pessoa em 24 h', null,
    $$select count(*) between 1 and 30 from emails_fila where destinatario = 'admin-a@teste.elolog.invalid'$$, 'verdadeiro', 'postgres');
  perform pg_temp.t('5.7 servico_reservar_emails reserva e marca "a_enviar"', null,
    $$select count(*) >= 1 from public.servico_reservar_emails(5, 5)$$, 'verdadeiro', 'postgres');
  perform pg_temp.t('5.8 um utilizador autenticado não reserva e-mails', aa, 'select * from public.servico_reservar_emails(5, 5)', 'erro');
  perform pg_temp.t('5.9 "repetir" devolve o e-mail à fila com espera', null,
    $$select public.servico_marcar_email((select id from emails_fila where estado = 'a_enviar' limit 1), 'repetir', null, 'erro de teste')$$, 'ok', 'postgres');
  perform pg_temp.t('5.10 …e fica pendente com a próxima tentativa no futuro', null,
    $$select exists (select 1 from emails_fila where estado = 'pendente' and erro = 'erro de teste' and proxima_tentativa > now())$$, 'verdadeiro', 'postgres');
  perform pg_temp.t('5.11 "enviado" regista a hora e conta para o limite diário', null,
    $$select public.servico_marcar_email((select id from emails_fila where estado = 'a_enviar' limit 1), 'enviado', 'msg-teste', null)$$, 'ok', 'postgres');
  perform pg_temp.t('5.12 …enviados hoje ≥ 1', null, $$select public.servico_emails_enviados_hoje() >= 1$$, 'verdadeiro', 'postgres');
  -- ------------------------------------------------------------------ relatório (o erro final desfaz tudo)
  for r in select * from resultados order by n loop v_total := v_total + 1; if r.ok then v_ok := v_ok + 1; end if;
    v_rel := v_rel || case when r.ok then '✔ ' else '✘ ' end || r.nome || case when not r.ok then '   →  ' || coalesce(r.detalhe, '')
                     when r.esperado in ('erro', 'nada') then '   [motivo: ' || coalesce(r.detalhe, '') || ']' else '' end || E'\n'; end loop;
  raise exception E'\n===== RELATÓRIO Elolog (o erro é propositado: desfaz tudo) =====\n%\n===== % de % verificações passaram =====', v_rel, v_ok, v_total; end
$teste$;

-- Elolog · TESTE 5 — Produção: faturas certificadas, pagamentos ifthenpay, navios e documentos.
-- Executar no SQL Editor do projeto de TESTE depois das migrações 00131–00133.
-- Termina com um ERRO de propósito: a mensagem é o relatório e o PostgreSQL desfaz tudo o que o teste criou.
do $teste$ declare
  aa constant uuid := 'a5000000-0000-4000-8000-000000000001';  -- administrador da empresa A
  oa constant uuid := 'a5000000-0000-4000-8000-000000000002';  -- operador da empresa A
  ab constant uuid := 'a5000000-0000-4000-8000-000000000003';  -- administrador da empresa B
  cl constant uuid := 'a5000000-0000-4000-8000-000000000004';  -- cliente
  c2 constant uuid := 'a5000000-0000-4000-8000-000000000005';  -- outro cliente
  ea constant uuid := 'b5000000-0000-4000-8000-000000000001'; eb constant uuid := 'b5000000-0000-4000-8000-000000000002';
  en constant uuid := 'e5000000-0000-4000-8000-000000000001'; dc constant uuid := 'd5000000-0000-4000-8000-000000000001';
  qr text := 'A:500000000*B:123456789*C:PT*D:FT*E:N*F:' || to_char(current_date, 'YYYYMMDD') || '*G:FT A/1*H:ABCD1234-1*I1:PT*N:23.00*O:123.00*Q:ab12*R:1234';
  v_rel text := ''; v_ok int := 0; v_total int := 0; r record; v jsonb; begin
  create temp table resultados (n serial, nome text, ok boolean, detalhe text);
  execute $f$ create function pg_temp.t(p_nome text, p_user uuid, p_sql text, p_esperado text, p_papel text default 'authenticated')
  returns void language plpgsql as $b$ declare v_n bigint; v_ok boolean := false; v_det text := ''; begin
    perform set_config('request.jwt.claims', case when p_user is null then '{}' else json_build_object('sub', p_user, 'role', p_papel, 'aal', 'aal2')::text end, true);
    execute format('set local role %I', p_papel);
    begin
      if p_esperado = 'erro' then execute p_sql; v_det := 'devia ter falhado';
      elsif p_esperado = 'nada' then execute 'select count(*) from (' || p_sql || ') q' into v_n; v_ok := v_n = 0; v_det := 'linhas=' || v_n;
      elsif p_esperado like 'linhas=%' then execute 'select count(*) from (' || p_sql || ') q' into v_n; v_ok := v_n = substr(p_esperado, 8)::bigint; v_det := 'linhas=' || v_n;
      elsif p_esperado like '=%' then execute 'select (' || p_sql || ')::text' into v_det; v_ok := v_det = substr(p_esperado, 2);
      else execute p_sql; v_ok := true; end if;
    exception when others then v_ok := p_esperado in ('erro', 'nada'); v_det := left(sqlerrm, 120); end;
    reset role; insert into resultados (nome, ok, detalhe) values (p_nome, v_ok, v_det); end $b$ $f$;

  insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
  select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', email, now(), now(), now(), '{}', '{}' from (values
    (aa, 'p5-aa@teste.elolog.invalid'), (oa, 'p5-oa@teste.elolog.invalid'), (ab, 'p5-ab@teste.elolog.invalid'),
    (cl, 'p5-cl@teste.elolog.invalid'), (c2, 'p5-c2@teste.elolog.invalid')) u(id, email);
  insert into empresas (id, nome, nif, email, estado, aprovada_em) values (ea, 'Empresa A p5', '500000000', 'p5a@teste.elolog.invalid', 'aprovada', now()),
    (eb, 'Empresa B p5', '500000001', 'p5b@teste.elolog.invalid', 'aprovada', now());
  insert into funcionarios (id, empresa_id, nome, email, papel) values (aa, ea, 'Admin A', 'p5-aa@teste.elolog.invalid', 'admin_empresa'),
    (oa, ea, 'Operador A', 'p5-oa@teste.elolog.invalid', 'operador'), (ab, eb, 'Admin B', 'p5-ab@teste.elolog.invalid', 'admin_empresa');
  insert into sessoes_empresa (user_id, empresa_id, valida_ate) values (aa, ea, now() + interval '1 hour'), (oa, ea, now() + interval '1 hour'), (ab, eb, now() + interval '1 hour');
  insert into clientes (id, nome, email) values (cl, 'Cliente p5', 'p5-cl@teste.elolog.invalid'), (c2, 'Cliente 2 p5', 'p5-c2@teste.elolog.invalid');
  insert into encomendas (id, codigo, empresa_id, cliente_id, cliente_nif, origem, destino, tipo_carga, preco_total)
    values (en, 'TR-P5-0001', ea, cl, '123456789', 'Lisboa', 'São Tomé', 'Comercial', 150);
  insert into documentos (id, empresa_id, categoria, nome, visibilidade, storage_path, enviado_por)
    values (dc, ea, 'outro', 'fatura.pdf', 'interna', ea || '/faturas/fatura.pdf', aa);

  -- ---------- faturas
  perform pg_temp.t('F1 operador não regista faturas', oa, format('select registar_fatura(%L, %L, %L)', dc, qr, en), 'erro');
  perform pg_temp.t('F2 empresa B não usa documento da A', ab, format('select registar_fatura(%L, %L, %L)', dc, qr, en), 'erro');
  perform pg_temp.t('F3 NIF do emitente diferente recusado', aa, format('select registar_fatura(%L, %L, %L)', dc, replace(qr, 'A:500000000', 'A:500000001'), en), 'erro');
  perform pg_temp.t('F4 ATCUD inválido recusado', aa, format('select registar_fatura(%L, %L, %L)', dc, replace(qr, 'H:ABCD1234-1', 'H:12'), en), 'erro');
  perform pg_temp.t('F5 NIF do cliente diferente do da encomenda', aa, format('select registar_fatura(%L, %L, %L)', dc, replace(qr, 'B:123456789', 'B:500000000'), en), 'erro');
  perform pg_temp.t('F6 fatura válida registada', aa, format('select registar_fatura(%L, %L, %L)', dc, qr, en), 'ok');
  perform pg_temp.t('F7 a mesma fatura não entra duas vezes', aa, format('select registar_fatura(%L, %L, %L)', dc, qr, en), 'erro');
  perform pg_temp.t('F8 faturar acima do preço recusado', aa, format('select registar_fatura(%L, %L, %L)', dc, replace(replace(replace(qr, 'G:FT A/1', 'G:FT A/2'), 'H:ABCD1234-1', 'H:ABCD1234-2'), 'O:123.00', 'O:40.00'), en), 'erro');
  perform pg_temp.t('F9 cliente vê a sua fatura', cl, 'select * from faturas', 'linhas=1');
  perform pg_temp.t('F10 cliente vê o PDF da fatura', cl, format('select * from documentos where id = %L', dc), 'linhas=1');
  perform pg_temp.t('F11 empresa B não vê a fatura', ab, 'select * from faturas', 'nada');
  perform pg_temp.t('F12 ninguém altera faturas diretamente', aa, 'update faturas set total = 1', 'erro');
  perform pg_temp.t('F13 cliente foi avisado (email em fila)', cl, $q$select * from notificacoes where tipo = 'fatura_emitida'$q$, 'linhas=1');

  -- ---------- configuração de pagamentos
  perform pg_temp.t('P1 operador não grava chaves', oa, $q$select guardar_config_pagamentos('MBK-123456','MBW-123456','antiphishing-segredo-1',true,true)$q$, 'erro');
  perform pg_temp.t('P2 chave com formato inválido recusada', aa, $q$select guardar_config_pagamentos('chave inválida!','','antiphishing-segredo-1',false,true)$q$, 'erro');
  perform pg_temp.t('P3 ativar sem anti-phishing recusado', aa, $q$select guardar_config_pagamentos('MBK-123456','','',true,true)$q$, 'erro');
  perform pg_temp.t('P4 administrador grava e ativa', aa, $q$select guardar_config_pagamentos('MBK-123456','MBW-123456','antiphishing-segredo-1',true,true)$q$, 'ok');
  perform pg_temp.t('P5 a chave volta mascarada', aa, $q$select ver_config_pagamentos()->>'multibanco'$q$, '=••••456');
  perform pg_temp.t('P6 ninguém lê a tabela das chaves', aa, 'select * from empresa_pagamentos_config', 'nada');
  perform pg_temp.t('P7 cliente não chama funções de serviço', cl, $q$select servico_preparar_pedido(auth.uid(), 'TR-P5-0001', 'multibanco', '')$q$, 'erro');

  -- ---------- pedido, aviso e pagamento (como a função de servidor)
  perform pg_temp.t('P8 outro cliente não paga a encomenda', null, format($q$select servico_preparar_pedido(%L, 'TR-P5-0001', 'multibanco', '')$q$, c2), 'erro', 'service_role');
  perform pg_temp.t('P9 MB WAY com telemóvel inválido', null, format($q$select servico_preparar_pedido(%L, 'TR-P5-0001', 'mbway', '812')$q$, cl), 'erro', 'service_role');
  perform pg_temp.t('P10 pedido Multibanco criado pelo valor em falta', null, format($q$select (servico_preparar_pedido(%L, 'TR-P5-0001', 'multibanco', '')->'pedido'->>'valor')$q$, cl), '=150.00', 'service_role');
  select order_id into r from pedidos_pagamento where encomenda_id = en;
  perform pg_temp.t('P11 aviso com chave errada não paga', null, format($q$select servico_confirmar_pedido(%L, 'errada', 150, 'aviso')$q$, r.order_id), '=chave_invalida', 'service_role');
  perform pg_temp.t('P12 aviso com valor diferente não paga', null, format($q$select servico_confirmar_pedido(%L, 'antiphishing-segredo-1', 15, 'aviso')$q$, r.order_id), '=valor_diferente', 'service_role');
  perform pg_temp.t('P13 aviso certo paga', null, format($q$select servico_confirmar_pedido(%L, 'antiphishing-segredo-1', 150, 'aviso')$q$, r.order_id), '=pago', 'service_role');
  perform pg_temp.t('P14 aviso repetido não paga duas vezes', null, format($q$select servico_confirmar_pedido(%L, 'antiphishing-segredo-1', 150, 'aviso')$q$, r.order_id), '=ja_pago', 'service_role');
  perform pg_temp.t('P15 um só pagamento de 150 €', cl, $q$select * from pagamentos where estado = 'pago' and valor = 150$q$, 'linhas=1');
  perform pg_temp.t('P16 encomenda paga não gera novo pedido', null, format($q$select servico_preparar_pedido(%L, 'TR-P5-0001', 'multibanco', '')$q$, cl), 'erro', 'service_role');
  perform pg_temp.t('P17 empresa B não vê o pedido', ab, 'select * from pedidos_pagamento', 'nada');
  perform pg_temp.t('P18 cliente não cria pedidos à mão', cl, format($q$insert into pedidos_pagamento (order_id, empresa_id, encomenda_id, cliente_id, metodo, valor) values ('ELX', %L, %L, %L, 'multibanco', 1)$q$, ea, en, cl), 'erro');

  -- ---------- navios e documentos do cliente
  perform pg_temp.t('N1 empresa segue um navio', aa, format($q$insert into navios_seguidos (empresa_id, mmsi, nome) values (%L, '255806000', 'SAO TOME')$q$, ea), 'ok');
  perform pg_temp.t('N2 MMSI inválido recusado', aa, format($q$insert into navios_seguidos (empresa_id, mmsi, nome) values (%L, '12', 'X')$q$, ea), 'erro');
  perform pg_temp.t('N3 empresa B não vê os navios da A', ab, 'select * from navios_seguidos', 'nada');
  perform pg_temp.t('N4 ninguém escreve posições à mão', aa, $q$insert into navios_posicoes (mmsi) values ('255806000')$q$, 'erro');
  perform pg_temp.t('D1 cliente não junta documentos à encomenda de outro', c2, format($q$insert into documentos (cliente_id, encomenda_id, categoria, nome, visibilidade, storage_path, enviado_por) values (auth.uid(), %L, 'outro', 'x.pdf', 'cliente', auth.uid() || '/x.pdf', auth.uid())$q$, en), 'erro');
  perform pg_temp.t('D2 cliente junta documento à sua encomenda', cl, format($q$insert into documentos (cliente_id, encomenda_id, categoria, nome, visibilidade, storage_path, enviado_por) values (auth.uid(), %L, 'outro', 'y.pdf', 'cliente', auth.uid() || '/y.pdf', auth.uid())$q$, en), 'ok');
  perform pg_temp.t('D3 a empresa vê o documento do cliente', aa, $q$select * from documentos where nome = 'y.pdf'$q$, 'linhas=1');
  perform pg_temp.t('T1 tarefas agendadas existem', null, $q$select count(*) from cron.job where jobname like 'elolog-%'$q$, '=4', 'postgres');

  for r in select * from resultados order by n loop
    v_total := v_total + 1; if r.ok then v_ok := v_ok + 1; end if;
    v_rel := v_rel || case when r.ok then 'OK    ' else 'FALHA ' end || r.nome || ' · ' || r.detalhe || E'\n';
  end loop;
  raise exception E'\n===== TESTE 5 Elolog (o erro é propositado: desfaz tudo) =====\n%\n===== % de % verificações passaram =====', v_rel, v_ok, v_total;
end $teste$;

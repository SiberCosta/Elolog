-- Teste 41: pagamento em prestações (00212). Corre numa transação que termina com raise exception: nada fica gravado.
-- Usa uma encomenda real sem pagamentos, liga dentro da transação uma configuração de pagamentos fictícia (sandbox)
-- e confirma os pedidos diretamente na base de dados. Não chama a ifthenpay.
-- Resultado em 2026-11-25 (encomenda de 39,58 €): ok=9 falhas=0.
begin;
do $$
declare en encomendas; r jsonb; o text := ''; ord text; msg text; ok int := 0; falhas int := 0; lst text; t numeric; mn numeric; resto numeric;
begin
  select e.* into en from encomendas e where e.cliente_id is not null and e.preco_total > 20 and e.estado not in ('cancelada','entregue')
    and not exists (select 1 from pagamentos p where p.encomenda_id = e.id) limit 1;
  if en.id is null then raise exception 'RELATORIO sem encomenda de teste'; end if;
  t := en.preco_total; mn := greatest(10, round(t*0.25,2)); resto := t - mn;
  insert into empresa_pagamentos_config (empresa_id, mb_key, mbway_key, chave_antiphishing, ativo, sandbox)
  values (en.empresa_id, 'TESTE-MB', 'TESTE-MBW', 'chave-de-teste-123', true, true)
  on conflict (empresa_id) do update set mb_key = 'TESTE-MB', mbway_key = 'TESTE-MBW', chave_antiphishing = 'chave-de-teste-123', ativo = true, sandbox = true;
  perform set_config('request.jwt.claims', json_build_object('sub', en.cliente_id, 'role', 'authenticated')::text, true);
  -- 1. resumo
  r := pagamento_resumo(en.codigo);
  o := o || format(E'\n1 resumo: total=%s falta=%s minimo=%s', r->>'total', r->>'falta', r->>'minimo');
  if (r->>'minimo')::numeric = mn and (r->>'falta')::numeric = t then ok := ok + 1; else falhas := falhas + 1; end if;
  -- 2 e 3. abaixo do mínimo e acima do que falta
  begin perform servico_preparar_pedido(en.cliente_id, en.codigo, 'multibanco', '', mn - 1); falhas := falhas + 1; o := o || E'\n2 FALHA: aceitou abaixo do minimo';
  exception when others then ok := ok + 1; o := o || E'\n2 recusa abaixo do minimo: ' || sqlerrm; end;
  begin perform servico_preparar_pedido(en.cliente_id, en.codigo, 'multibanco', '', t + 1); falhas := falhas + 1; o := o || E'\n3 FALHA: aceitou acima';
  exception when others then ok := ok + 1; o := o || E'\n3 recusa acima: ' || sqlerrm; end;
  -- 4. 1.ª prestação
  r := servico_preparar_pedido(en.cliente_id, en.codigo, 'multibanco', '', mn);
  ord := r->'pedido'->>'order_id';
  o := o || format(E'\n4 pedido valor=%s descricao=%s', r->'pedido'->>'valor', r->>'descricao');
  msg := servico_confirmar_pedido(ord, null, mn, 'verificacao');
  select string_agg(tipo::text || ':' || valor, ',') into lst from pagamentos where encomenda_id = en.id;
  o := o || format(E'\n  confirmar=%s pagamentos=%s', msg, lst);
  if msg = 'pago' and lst like 'prestacao:%' then ok := ok + 1; else falhas := falhas + 1; end if;
  -- 5. expedição bloqueada com pagamento parcial (regra de 00210)
  select string_agg(x, ' | ') into msg from unnest(private.encomenda_falta(en, 'expedicao', null)) x;
  o := o || E'\n5 falta para expedir: ' || coalesce(msg, '(nada)');
  if msg ilike '%pag%' then ok := ok + 1; else falhas := falhas + 1; end if;
  -- 6. resumo depois
  r := pagamento_resumo(en.codigo);
  o := o || format(E'\n6 resumo: pago=%s falta=%s minimo=%s', r->>'pago', r->>'falta', r->>'minimo');
  if (r->>'falta')::numeric = resto then ok := ok + 1; else falhas := falhas + 1; end if;
  -- 7. sem valor = paga o resto
  r := servico_preparar_pedido(en.cliente_id, en.codigo, 'mbway', '912345678');
  ord := r->'pedido'->>'order_id';
  msg := servico_confirmar_pedido(ord, null, resto, 'verificacao');
  select string_agg(tipo::text || ':' || valor, ',') into lst from pagamentos where encomenda_id = en.id;
  o := o || format(E'\n7 resto: valor=%s confirmar=%s pagamentos=%s', r->'pedido'->>'valor', msg, lst);
  if msg = 'pago' and lst like '%total:%' then ok := ok + 1; else falhas := falhas + 1; end if;
  select string_agg(x, ' | ') into msg from unnest(private.encomenda_falta(en, 'expedicao', null)) x;
  o := o || E'\n  falta para expedir depois: ' || coalesce(msg, '(nada)');
  -- 8. já paga
  begin perform servico_preparar_pedido(en.cliente_id, en.codigo, 'multibanco', '', 10); falhas := falhas + 1; o := o || E'\n8 FALHA';
  exception when others then ok := ok + 1; o := o || E'\n8 ' || sqlerrm; end;
  -- 9. outro utilizador
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  begin perform pagamento_resumo(en.codigo); falhas := falhas + 1; o := o || E'\n9 FALHA: estranho viu';
  exception when others then ok := ok + 1; o := o || E'\n9 estranho: ' || sqlerrm; end;
  raise exception 'RELATORIO ok=% falhas=% %', ok, falhas, o;
end $$;
rollback;

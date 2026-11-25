-- 00212: pagamento em prestações pelo cliente (Multibanco / MB WAY).
-- · O cliente pode pagar só uma parte do que falta. Cada prestação tem um mínimo: 25 % do total ou 10 €
--   (o que for maior); a última prestação é sempre o que falta, mesmo que seja menor.
-- · A regra de 00210 mantém-se: a encomenda só segue para expedição com o valor total pago.
-- · Cada pagamento online fica com tipo «prestacao» quando não salda a encomenda, «total» quando salda.

create or replace function private.prestacao_minima(p_total numeric, p_falta numeric)
returns numeric language sql immutable set search_path = '' as $$
  select least(round(coalesce(p_falta, 0), 2), greatest(10::numeric, round(coalesce(p_total, 0) * 0.25, 2)));
$$;

-- Resumo do que está pago e do que falta, para o cliente dono da encomenda.
create or replace function public.pagamento_resumo(p_encomenda text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare en encomendas; v_pago numeric; v_falta numeric; v_n int;
begin
  select * into en from encomendas where codigo = p_encomenda and cliente_id = auth.uid();
  if en.id is null then raise exception 'Encomenda não encontrada.'; end if;
  select coalesce(sum(valor), 0), count(*) into v_pago, v_n from pagamentos
   where encomenda_id = en.id and estado = 'pago' and tipo <> 'reembolso';
  v_falta := greatest(0, round(coalesce(en.preco_total, 0) - v_pago, 2));
  return jsonb_build_object('total', coalesce(en.preco_total, 0), 'pago', v_pago, 'falta', v_falta, 'pagamentos', v_n,
    'minimo', private.prestacao_minima(en.preco_total, v_falta),
    'online', exists (select 1 from empresa_pagamentos_config where empresa_id = en.empresa_id and ativo));
end $$;
revoke all on function public.pagamento_resumo(text) from public, anon;
grant execute on function public.pagamento_resumo(text) to authenticated;

drop function if exists public.servico_preparar_pedido(uuid, text, text, text);
create function public.servico_preparar_pedido(p_cliente uuid, p_encomenda text, p_metodo text, p_telemovel text, p_valor numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare en encomendas; c empresa_pagamentos_config; v_pago numeric; v_falta numeric; v_min numeric; v_valor numeric; p pedidos_pagamento;
begin
  select * into en from encomendas where codigo = p_encomenda and cliente_id = p_cliente;
  if en.id is null then raise exception 'Encomenda não encontrada.'; end if;
  select * into c from empresa_pagamentos_config where empresa_id = en.empresa_id and ativo;
  if c.empresa_id is null then raise exception 'Esta empresa ainda não aceita pagamentos online.'; end if;
  if p_metodo = 'multibanco' and c.mb_key is null or p_metodo = 'mbway' and c.mbway_key is null then
    raise exception 'Método não disponível para esta empresa.'; end if;
  if p_metodo = 'mbway' and coalesce(p_telemovel, '') !~ '^9[1236][0-9]{7}$' then
    raise exception 'Indique um telemóvel português válido (9 dígitos).'; end if;
  if (select count(*) from pedidos_pagamento where encomenda_id = en.id and created_at > now() - interval '1 hour') >= 6 then
    raise exception 'Demasiados pedidos de pagamento seguidos. Tente daqui a pouco.'; end if;
  select coalesce(sum(valor), 0) into v_pago from pagamentos where encomenda_id = en.id and estado = 'pago' and tipo <> 'reembolso';
  v_falta := round(coalesce(en.preco_total, 0) - v_pago, 2);
  if v_falta <= 0 then raise exception 'Esta encomenda já está paga.'; end if;
  if p_valor is null then v_valor := v_falta;
  else
    v_valor := round(p_valor, 2);
    v_min := private.prestacao_minima(en.preco_total, v_falta);
    if v_valor > v_falta then raise exception 'O valor não pode passar o que falta pagar (% €).', private.valor_pt(v_falta); end if;
    if v_valor < v_min then raise exception 'Cada prestação tem de ser de pelo menos % €.', private.valor_pt(v_min); end if;
  end if;
  -- Reaproveita uma referência Multibanco ainda válida com o mesmo valor.
  select * into p from pedidos_pagamento where encomenda_id = en.id and metodo = 'multibanco' and p_metodo = 'multibanco'
    and estado = 'pendente' and valor = v_valor and referencia is not null and (expira_em is null or expira_em > now()) limit 1;
  if p.id is not null then return jsonb_build_object('reutilizar', true, 'pedido', to_jsonb(p)); end if;
  update pedidos_pagamento set estado = 'expirado', updated_at = now() where encomenda_id = en.id and estado = 'pendente' and metodo = p_metodo;
  insert into pedidos_pagamento (order_id, empresa_id, encomenda_id, cliente_id, metodo, valor, telemovel)
  values ('EL' || upper(substr(md5(gen_random_uuid()::text), 1, 12)), en.empresa_id, en.id, p_cliente, p_metodo, v_valor, nullif(p_telemovel, ''))
  returning * into p;
  return jsonb_build_object('reutilizar', false, 'pedido', to_jsonb(p), 'sandbox', c.sandbox,
    'chave', case when p_metodo = 'multibanco' then c.mb_key else c.mbway_key end,
    'descricao', 'Encomenda ' || en.codigo || case when v_valor < v_falta then ' (prestação)' else '' end);
end $function$;
revoke all on function public.servico_preparar_pedido(uuid, text, text, text, numeric) from public, anon, authenticated;
grant execute on function public.servico_preparar_pedido(uuid, text, text, text, numeric) to service_role;

create or replace function public.servico_confirmar_pedido(p_order_id text, p_chave text, p_valor numeric, p_origem text)
returns text language plpgsql security definer set search_path = public as $function$
declare p pedidos_pagamento; c empresa_pagamentos_config; v_pag uuid; en encomendas; v_pago numeric; v_resta numeric;
begin
  select * into p from pedidos_pagamento where order_id = p_order_id for update;
  if p.id is null then return 'desconhecido'; end if;
  select * into c from empresa_pagamentos_config where empresa_id = p.empresa_id;
  if p_origem = 'aviso' and (c.chave_antiphishing is null or p_chave is distinct from c.chave_antiphishing) then return 'chave_invalida'; end if;
  if p.estado = 'pago' then return 'ja_pago'; end if;
  if abs(coalesce(p_valor, -1) - p.valor) > 0.009 then return 'valor_diferente'; end if;
  select * into en from encomendas where id = p.encomenda_id;
  select coalesce(sum(valor), 0) into v_pago from pagamentos where encomenda_id = p.encomenda_id and estado = 'pago' and tipo <> 'reembolso';
  v_resta := greatest(0, round(coalesce(en.preco_total, 0) - v_pago - p.valor, 2));
  insert into pagamentos (empresa_id, encomenda_id, cliente_id, tipo, valor, estado, metodo, referencia, pago_em)
  values (p.empresa_id, p.encomenda_id, p.cliente_id, case when v_resta > 0 then 'prestacao' else 'total' end::tipo_pagamento, p.valor, 'pago',
    case when p.metodo = 'mbway' then 'MB WAY' else 'Multibanco' end, coalesce(p.referencia, p.request_id, p.order_id), now())
  returning id into v_pag;
  update pedidos_pagamento set estado = 'pago', pago_em = now(), pagamento_id = v_pag, updated_at = now() where id = p.id;
  insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  values (p.cliente_id, 'pagamento_recebido', case when v_resta > 0 then 'Prestação recebida' else 'Pagamento recebido' end,
    'Recebemos ' || private.valor_pt(p.valor) || ' € da encomenda ' || en.codigo || '.'
      || case when v_resta > 0 then ' Falta pagar ' || private.valor_pt(v_resta) || ' € antes da expedição.' else ' A encomenda está paga.' end,
    'pagamentos', v_pag);
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  values (p.empresa_id, 'pagamento_recebido', case when v_resta > 0 then 'Prestação recebida · ' else 'Pagamento recebido · ' end || en.codigo,
    private.valor_pt(p.valor) || ' € por ' || case when p.metodo = 'mbway' then 'MB WAY' else 'Multibanco' end || '.'
      || case when v_resta > 0 then ' Em dívida: ' || private.valor_pt(v_resta) || ' €.' else '' end,
    'pagamentos', v_pag);
  insert into auditoria (empresa_id, acao, entidade, entidade_id, depois)
  values (p.empresa_id, 'pagamento_online', 'pagamentos', v_pag::text,
    jsonb_build_object('metodo', p.metodo, 'valor', p.valor, 'origem', p_origem, 'resta', v_resta));
  return 'pago';
end $function$;
revoke all on function public.servico_confirmar_pedido(text, text, numeric, text) from public, anon, authenticated;
grant execute on function public.servico_confirmar_pedido(text, text, numeric, text) to service_role;

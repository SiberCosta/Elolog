-- 00209 (auditoria fase 2, A-14): o cliente tem de aceitar um preço que ainda não viu.
-- Antes: num pedido de cotação (sem preço calculado) ou quando o prestador indicava um preço ACIMA do calculado,
-- aceitar_simulacao criava logo a encomenda com esse valor, sem o cliente concordar.
-- Agora, para simulações de clientes com conta: preço igual ou abaixo do calculado → encomenda criada como antes;
-- pedido de cotação ou preço acima → fica uma proposta «enviada» (válida 7 dias) que o cliente aceita (aceitar_proposta)
-- ou recusa (recusar_proposta, nova). Pedidos registados pela administração em nome de um cliente sem conta não mudam.
create or replace function public.aceitar_simulacao(p_simulacao uuid, p_preco numeric default null::numeric)
 returns encomendas language plpgsql security definer set search_path to 'public' as $function$
declare v_sim simulacoes; v_enc encomendas; v_prop uuid; v_preco numeric; v_det jsonb; c regras_comissao; com numeric;
begin
  if private.minha_empresa() is null or not private.papel_em(array['admin_empresa','operador']) then raise exception 'Sem permissão para aceitar simulações.'; end if;
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.empresa_destinatario_id is distinct from private.minha_empresa() then raise exception 'Simulação inexistente.'; end if;
  if v_sim.estado not in ('enviada', 'respondida') then raise exception 'A simulação já não está disponível (%).', v_sim.estado; end if;
  v_preco := coalesce(p_preco, v_sim.preco_estimado);
  if v_preco is null or v_preco <= 0 then raise exception 'Indique o preço para este pedido de cotação.'; end if;
  if v_preco > 10000000 then raise exception 'Preço inválido.'; end if;
  v_preco := round(v_preco, 2);
  if p_preco is null or v_sim.preco_estimado is not distinct from v_preco then v_det := v_sim.preco_detalhe;
  else
    c := private.comissao_escolhida(v_sim.empresa_destinatario_id, null, v_sim.origem, v_sim.destino); com := private.comissao_valor(c, v_preco);
    v_det := jsonb_build_object('disponivel', true, 'origem_tarifa', 'cotacao', 'moeda', coalesce(v_sim.moeda_estimada, 'EUR'), 'preco_prestador', v_preco, 'suplementos', '[]'::jsonb,
      'suplementos_total', 0, 'comissao', com, 'apresentacao', coalesce(c.apresentacao, 'incluida'),
      'comissao_regra', case when c.id is null then null else jsonb_build_object('id', c.id, 'nome', c.nome, 'tipo_valor', c.tipo_valor, 'valor', c.valor) end,
      'preco_final', v_preco + case when c.apresentacao = 'separada' then com else 0 end,
      'liquido_prestador', v_preco - case when coalesce(c.apresentacao, 'incluida') = 'incluida' then com else 0 end);
    v_preco := (v_det ->> 'preco_final')::numeric;
  end if;
  v_det := private.preco_congelado(v_det, v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), v_sim.tarifa_estimada_id);
  update propostas set estado = 'cancelada', respondida_em = now() where simulacao_id = v_sim.id and empresa_id = v_sim.empresa_destinatario_id and estado = 'enviada';

  /* consentimento do cliente: cotação ou preço acima do que o cliente viu */
  if v_sim.cliente_id is not null and (v_sim.preco_estimado is null or v_preco > v_sim.preco_estimado) then
    insert into propostas (simulacao_id, empresa_id, tarifa_id, preco, moeda, estado, mensagem, criado_por, validade, preco_detalhe)
    values (v_sim.id, v_sim.empresa_destinatario_id, v_sim.tarifa_estimada_id, v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), 'enviada',
            case when v_sim.preco_estimado is null then 'Preço indicado pelo prestador para o seu pedido de cotação.' else 'O prestador indicou um preço diferente do calculado.' end,
            auth.uid(), current_date + 7, v_det) returning id into v_prop;
    update simulacoes set estado = 'respondida' where id = v_sim.id;
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (v_sim.cliente_id, 'proposta_recebida', 'Tem um preço para aceitar', coalesce(v_sim.codigo || ' · ', '') || v_sim.origem || ' → ' || v_sim.destino || ': ' ||
              to_char(v_preco, 'FM999G999G990D00') || ' ' || coalesce(v_sim.moeda_estimada, 'EUR') || '. Aceite ou recuse na sua área, em Propostas.', 'propostas', v_prop);
    insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
      values (v_sim.empresa_destinatario_id, auth.uid(), private.meu_papel()::text, 'propor_preco', 'simulacoes', v_sim.id::text,
              jsonb_build_object('proposta', v_prop, 'preco', v_preco, 'preco_calculado', v_sim.preco_estimado));
    return null;
  end if;

  insert into propostas (simulacao_id, empresa_id, tarifa_id, preco, moeda, estado, mensagem, criado_por, respondida_em, preco_detalhe)
  values (v_sim.id, v_sim.empresa_destinatario_id, v_sim.tarifa_estimada_id, v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), 'aceite',
          case when p_preco is not null and v_sim.preco_estimado is distinct from round(p_preco, 2) then 'Aceite com preço indicado pelo prestador.' else 'Aceite ao preço calculado pelas tarifas do prestador.' end,
          auth.uid(), now(), v_det) returning id into v_prop;
  update simulacoes set estado = 'convertida', preco_estimado = v_preco where id = v_sim.id;
  insert into encomendas (empresa_id, cliente_id, simulacao_id, proposta_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes, preco_total, moeda, estado,
                          data_prevista, morada_recolha, remetente, destinatario, valor_declarado, observacoes, criado_por, preco_detalhe)
  values (v_sim.empresa_destinatario_id, v_sim.cliente_id, v_sim.id, v_prop, v_sim.origem, v_sim.destino, v_sim.tipo_carga, v_sim.descricao, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3,
          v_sim.volumes, v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), 'aprovacao', v_sim.data_prevista, v_sim.morada_recolha, v_sim.remetente, v_sim.destinatario, v_sim.valor_declarado,
          v_sim.observacoes, auth.uid(), v_det) returning * into v_enc;
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id) values (v_enc.id, v_enc.empresa_id, null, 'aprovacao', 'Simulação aceite pelo prestador', auth.uid());
  insert into notificacoes (user_id, para_plataforma, tipo, titulo, corpo, referencia_tabela, referencia_id)
  values (v_sim.cliente_id, v_sim.cliente_id is null, 'simulacao_aceite',
          case when v_sim.cliente_id is null then 'Prestador aceitou um pedido registado pela Elolog' else 'O prestador aceitou o seu pedido' end,
          'Encomenda ' || v_enc.codigo || ' criada' || case when v_sim.cliente_id is null then '. Informe o cliente: ' || coalesce(v_sim.remetente->>'nome','') || ' ' || coalesce(v_sim.remetente->>'telefone','') else ' e a aguardar aprovação operacional.' end,
          'encomendas', v_enc.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
  values (v_enc.empresa_id, auth.uid(), private.meu_papel()::text, 'aceitar_simulacao', 'simulacoes', v_sim.id::text, jsonb_build_object('encomenda', v_enc.codigo, 'preco', v_preco));
  return v_enc;
end $function$;

create or replace function public.recusar_proposta(p_proposta uuid, p_motivo text default null)
 returns propostas language plpgsql security definer set search_path to 'public' as $function$
declare v_prop propostas; v_sim simulacoes;
begin
  select * into v_prop from propostas where id = p_proposta for update;
  if not found then raise exception 'Proposta inexistente.'; end if;
  select * into v_sim from simulacoes where id = v_prop.simulacao_id for update;
  if v_sim.cliente_id is distinct from auth.uid() then raise exception 'Sem permissão.'; end if;
  if v_prop.estado <> 'enviada' then raise exception 'A proposta já não está disponível (%).', v_prop.estado; end if;
  update propostas set estado = 'recusada', respondida_em = now(), mensagem = coalesce(mensagem || ' · ', '') || 'Recusada pelo cliente' || coalesce(': ' || nullif(left(trim(p_motivo), 300), ''), '')
   where id = v_prop.id returning * into v_prop;
  update simulacoes set estado = 'enviada' where id = v_sim.id and estado = 'respondida';
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v_prop.empresa_id, 'proposta_recusada', 'O cliente recusou o preço proposto', coalesce(v_sim.codigo || ' · ', '') || v_sim.origem || ' → ' || v_sim.destino ||
            coalesce(' · ' || nullif(left(trim(p_motivo), 200), ''), '') || '. Pode indicar outro preço.', 'simulacoes', v_sim.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, motivo)
    values (v_prop.empresa_id, auth.uid(), 'cliente', 'recusar_proposta', 'propostas', v_prop.id::text, nullif(trim(p_motivo), ''));
  return v_prop;
end $function$;
revoke all on function public.recusar_proposta(uuid, text) from public, anon;
grant execute on function public.recusar_proposta(uuid, text) to authenticated;

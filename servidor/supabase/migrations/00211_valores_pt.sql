-- 00211: valores em formato português nas mensagens do servidor («2 200,00» em vez de «2,200.00»).
-- O servidor não tem a localização pt_PT, por isso a conversão é feita por private.valor_pt. Só muda o texto das mensagens.
create or replace function private.valor_pt(p numeric) returns text language sql immutable set search_path to 'public' as $$
  select replace(replace(replace(to_char(coalesce(p, 0), 'FM999G999G990D00'), ',', '#'), '.', ','), '#', ' ') $$;
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
              private.valor_pt(v_preco) || ' ' || coalesce(v_sim.moeda_estimada, 'EUR') || '. Aceite ou recuse na sua área, em Propostas.', 'propostas', v_prop);
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
create or replace function private.encomenda_falta(e encomendas, p_para estado_encomenda, p_excecao text default null::text)
 returns text[] language plpgsql stable security definer set search_path to 'public' as $function$
declare f text[] := '{}'; r recibos_armazem; v_pago numeric;
begin
  if e.estado = 'aprovacao' and p_para = 'armazenamento' then
    if not (e.criada_no_terreno or private.meu_papel() = 'admin_empresa') then f := f || text 'fluxo autorizado direto para armazém (registo no terreno ou administrador da empresa)'; end if;
    if length(trim(coalesce(p_excecao, ''))) < 5 then f := f || text 'motivo de exceção para dispensar a aprovação'; end if;
  end if;
  if p_para = 'armazenamento' then
    if e.criada_no_terreno then
      if e.cliente_id is null and coalesce(e.cliente_nome, '') = '' then f := f || text 'cliente'; end if;
      if coalesce(e.origem, '') = '' or coalesce(e.destino, '') = '' then f := f || text 'rota'; end if;
      if not exists (select 1 from pagamentos pg where pg.encomenda_id = e.id and pg.tipo <> 'reembolso' and pg.estado in ('pendente','parcial','pago')) then f := f || text 'primeiro pagamento'; end if;
      if e.assinatura_documento_id is null and e.pin_validacao_hash is null then f := f || text 'assinatura ou PIN do cliente'; end if;
    end if;
    select * into r from recibos_armazem where encomenda_id = e.id;
    if r.encomenda_id is null or not r.confirmado or r.quantidade_recebida is null then f := f || text 'receção no armazém com quantidade confirmada';
    elsif e.quantidade is not null and r.quantidade_recebida <> e.quantidade and coalesce(trim(r.ocorrencias), '') = '' then
      f := f || ('ocorrência a explicar a diferença de quantidade (' || r.quantidade_recebida || ' de ' || e.quantidade || ')'); end if;
  end if;
  if p_para = 'expedicao' and not exists (select 1 from recibos_armazem ra where ra.encomenda_id = e.id and ra.confirmado and ra.carga_conferida) then
    f := f || text 'receção confirmada e carga conferida pelo armazém'; end if;
  if p_para = 'expedicao' and coalesce(e.preco_total, 0) > 0 then
    select coalesce(sum(pg.valor), 0) into v_pago from pagamentos pg where pg.encomenda_id = e.id and pg.tipo <> 'reembolso' and pg.estado = 'pago';
    if v_pago < e.preco_total - 0.01 and not (private.meu_papel() = 'admin_empresa' and length(trim(coalesce(p_excecao, ''))) >= 5) then
      f := f || ('pagamento total do cliente (pago ' || private.valor_pt(v_pago) || ' de ' || private.valor_pt(e.preco_total) || ' ' || coalesce(e.moeda, 'EUR') ||
                 '; só o administrador da empresa pode expedir sem pagamento, indicando o motivo)'); end if;
  end if;
  if p_para = 'em_transito' and not (coalesce(e.navio, '') <> '' and coalesce(e.viagem, '') <> '' and e.partida_prevista is not null)
     and not exists (select 1 from manifesto_encomendas me join manifestos m on m.id = me.manifesto_id where me.encomenda_id = e.id
                      and coalesce(m.transportador, '') <> '' and coalesce(m.numero_viagem, '') <> '' and m.partida is not null) then
    f := f || text 'navio, viagem e data prevista de partida'; end if;
  if p_para = 'disponivel' and not exists (select 1 from trabalhos_terreno t where t.encomenda_id = e.id and t.tipo = 'processamento_destino' and t.estado = 'concluida') then
    f := f || text 'processamento no destino concluído'; end if;
  if p_para = 'entregue' then
    if e.estado <> 'disponivel' then f := f || text 'passar por Destino e Disponível (chegada e aviso ao cliente)'; end if;
    if not private.entrega_confirmada(e.id) then f := f || text 'confirmação do levantamento (identificação e assinatura/PIN)'; end if;
  end if;
  return f;
end $function$;
create or replace function public.aceitar_proposta(p_proposta uuid)
 returns encomendas language plpgsql security definer set search_path to 'public' as $function$
declare v_prop propostas; v_sim simulacoes; v_enc encomendas; v_det jsonb;
begin
  select * into v_prop from propostas where id = p_proposta for update;
  if not found then raise exception 'Proposta inexistente.'; end if;
  select * into v_sim from simulacoes where id = v_prop.simulacao_id for update;
  if v_sim.cliente_id is distinct from auth.uid() then raise exception 'Sem permissão.'; end if;
  if v_prop.estado <> 'enviada' then raise exception 'A proposta já não está disponível (%).', v_prop.estado; end if;
  if v_prop.validade is not null and v_prop.validade < current_date then raise exception 'A proposta expirou.'; end if;
  v_det := private.preco_congelado(coalesce(v_prop.preco_detalhe, case when v_sim.preco_estimado = v_prop.preco then v_sim.preco_detalhe end), v_prop.preco, v_prop.moeda, v_prop.tarifa_id);
  update propostas set estado = 'aceite', respondida_em = now(), preco_detalhe = v_det where id = v_prop.id;
  update propostas set estado = 'recusada', respondida_em = now() where simulacao_id = v_prop.simulacao_id and id <> v_prop.id and estado = 'enviada';
  update simulacoes set estado = 'convertida' where id = v_sim.id;
  insert into encomendas (empresa_id, cliente_id, simulacao_id, proposta_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes, preco_total, moeda, estado, criado_por, preco_detalhe)
  values (v_prop.empresa_id, v_sim.cliente_id, v_sim.id, v_prop.id, v_sim.origem, v_sim.destino, v_sim.tipo_carga, v_sim.descricao, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3, v_sim.volumes,
          v_prop.preco, v_prop.moeda, 'aprovacao', auth.uid(), v_det) returning * into v_enc;
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id) values (v_enc.id, v_enc.empresa_id, null, 'aprovacao', 'Proposta aceite pelo cliente', auth.uid());
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v_enc.empresa_id, 'proposta_aceite', 'O cliente aceitou o preço: nova encomenda ' || v_enc.codigo,
            v_enc.origem || ' → ' || v_enc.destino || ' · ' || private.valor_pt(v_prop.preco) || ' ' || coalesce(v_prop.moeda, 'EUR') || '. Aprove em «Aprovar pedidos».', 'encomendas', v_enc.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_enc.empresa_id, auth.uid(), 'cliente', 'aceitar_proposta', 'propostas', v_prop.id::text, jsonb_build_object('encomenda', v_enc.codigo));
  return v_enc;
end $function$;

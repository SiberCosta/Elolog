-- v114 — A aceitação guarda a cópia dos valores e condições em vigor (preco_detalhe), e a ficha lê a comissão dessa cópia.
-- aceitar_simulacao e aceitar_proposta ficam iguais em tudo o resto (mesmas verificações, histórico, notificações e auditoria).

create or replace function public.aceitar_proposta(p_proposta uuid)
returns encomendas language plpgsql security definer set search_path = public as $$
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
  insert into encomendas (empresa_id, cliente_id, simulacao_id, proposta_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes,
                          preco_total, moeda, estado, criado_por, preco_detalhe)
  values (v_prop.empresa_id, v_sim.cliente_id, v_sim.id, v_prop.id, v_sim.origem, v_sim.destino, v_sim.tipo_carga, v_sim.descricao, v_sim.quantidade, v_sim.peso_kg,
          v_sim.volume_m3, v_sim.volumes, v_prop.preco, v_prop.moeda, 'aprovacao', auth.uid(), v_det) returning * into v_enc;
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id)
    values (v_enc.id, v_enc.empresa_id, null, 'aprovacao', 'Proposta aceite pelo cliente', auth.uid());
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_enc.empresa_id, auth.uid(), 'cliente', 'aceitar_proposta', 'propostas', v_prop.id::text, jsonb_build_object('encomenda', v_enc.codigo));
  return v_enc;
end $$;

create or replace function public.aceitar_simulacao(p_simulacao uuid, p_preco numeric default null)
returns encomendas language plpgsql security definer set search_path = public as $$
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
  if p_preco is null or v_sim.preco_estimado is not distinct from v_preco then
    v_det := v_sim.preco_detalhe;
  else  -- cotação personalizada: o preço indicado é o do prestador; a comissão Elolog aplica-se pelas mesmas regras do motor
    c := private.comissao_escolhida(v_sim.empresa_destinatario_id, null, v_sim.origem, v_sim.destino); com := private.comissao_valor(c, v_preco);
    v_det := jsonb_build_object('disponivel', true, 'origem_tarifa', 'cotacao', 'moeda', coalesce(v_sim.moeda_estimada, 'EUR'), 'preco_prestador', v_preco, 'suplementos', '[]'::jsonb,
      'suplementos_total', 0, 'comissao', com, 'apresentacao', coalesce(c.apresentacao, 'incluida'),
      'comissao_regra', case when c.id is null then null else jsonb_build_object('id', c.id, 'nome', c.nome, 'tipo_valor', c.tipo_valor, 'valor', c.valor) end,
      'preco_final', v_preco + case when c.apresentacao = 'separada' then com else 0 end,
      'liquido_prestador', v_preco - case when coalesce(c.apresentacao, 'incluida') = 'incluida' then com else 0 end);
    v_preco := (v_det ->> 'preco_final')::numeric;
  end if;
  v_det := private.preco_congelado(v_det, v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), v_sim.tarifa_estimada_id);

  update propostas set estado = 'cancelada', respondida_em = now()
   where simulacao_id = v_sim.id and empresa_id = v_sim.empresa_destinatario_id and estado = 'enviada';
  insert into propostas (simulacao_id, empresa_id, tarifa_id, preco, moeda, estado, mensagem, criado_por, respondida_em, preco_detalhe)
  values (v_sim.id, v_sim.empresa_destinatario_id, v_sim.tarifa_estimada_id, v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), 'aceite',
          case when p_preco is not null and v_sim.preco_estimado is distinct from round(p_preco, 2) then 'Aceite com preço indicado pelo prestador.'
               else 'Aceite ao preço calculado pelas tarifas do prestador.' end, auth.uid(), now(), v_det)
  returning id into v_prop;
  update simulacoes set estado = 'convertida', preco_estimado = v_preco where id = v_sim.id;

  insert into encomendas (empresa_id, cliente_id, simulacao_id, proposta_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes, preco_total, moeda,
                          estado, data_prevista, morada_recolha, remetente, destinatario, valor_declarado, observacoes, criado_por, preco_detalhe)
  values (v_sim.empresa_destinatario_id, v_sim.cliente_id, v_sim.id, v_prop, v_sim.origem, v_sim.destino, v_sim.tipo_carga, v_sim.descricao, v_sim.quantidade, v_sim.peso_kg,
          v_sim.volume_m3, v_sim.volumes, v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), 'aprovacao', v_sim.data_prevista, v_sim.morada_recolha, v_sim.remetente,
          v_sim.destinatario, v_sim.valor_declarado, v_sim.observacoes, auth.uid(), v_det)
  returning * into v_enc;

  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id)
    values (v_enc.id, v_enc.empresa_id, null, 'aprovacao', 'Simulação aceite pelo prestador', auth.uid());
  insert into notificacoes (user_id, para_plataforma, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v_sim.cliente_id, v_sim.cliente_id is null, 'simulacao_aceite',
            case when v_sim.cliente_id is null then 'Prestador aceitou um pedido registado pela Elolog' else 'O prestador aceitou o seu pedido' end,
            'Encomenda ' || v_enc.codigo || ' criada' || case when v_sim.cliente_id is null then '. Informe o cliente: ' || coalesce(v_sim.remetente->>'nome','') || ' ' || coalesce(v_sim.remetente->>'telefone','') else ' e a aguardar aprovação operacional.' end,
            'encomendas', v_enc.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_enc.empresa_id, auth.uid(), private.meu_papel()::text, 'aceitar_simulacao', 'simulacoes', v_sim.id::text, jsonb_build_object('encomenda', v_enc.codigo, 'preco', v_preco));
  return v_enc;
end $$;

-- a cópia congelada não se altera depois (nem pelo prestador, nem por engano): só a administração da plataforma
create or replace function private.proteger_preco_detalhe() returns trigger language plpgsql set search_path = public as $$
begin
  if old.preco_detalhe is not null and new.preco_detalhe is distinct from old.preco_detalhe and not private.e_admin_plataforma() then
    raise exception 'O preço acordado não muda depois de aprovado.'; end if;
  return new;
end $$;
create or replace trigger encomendas_preco_detalhe before update of preco_detalhe on public.encomendas for each row execute function private.proteger_preco_detalhe();

-- a ficha da operação passa a usar a comissão guardada na aprovação (quando existe), em vez de a recalcular
do $$ declare d text := pg_get_functiondef('public.encomenda_ficha(text)'::regprocedure); n text; begin
  n := replace(d, 'comissao := case when regra.id is null then null', 'comissao := case when (e.preco_detalhe ->> ''comissao'') is not null then (e.preco_detalhe ->> ''comissao'')::numeric when regra.id is null then null');
  if n <> d then execute n; end if;
end $$;

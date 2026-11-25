-- 00210 (regras aprovadas em 25/11/2026):
-- 1) Pagar antes de expedir: para passar a «Expedição», os pagamentos «pago» (sem reembolsos) têm de cobrir o preço total.
--    Exceção só do administrador da empresa, com motivo (≥ 5 caracteres) no campo de exceção — por exemplo, cliente com
--    crédito acordado ou pagamento no destino. A exceção fica no histórico e na auditoria (motivo_excecao).
-- 2) Quando o cliente aceita uma proposta de preço, o prestador recebe uma notificação.
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
      f := f || ('pagamento total do cliente (pago ' || to_char(v_pago, 'FM999G999G990D00') || ' de ' || to_char(e.preco_total, 'FM999G999G990D00') || ' ' || coalesce(e.moeda, 'EUR') ||
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
            v_enc.origem || ' → ' || v_enc.destino || ' · ' || to_char(v_prop.preco, 'FM999G999G990D00') || ' ' || coalesce(v_prop.moeda, 'EUR') || '. Aprove em «Aprovar pedidos».', 'encomendas', v_enc.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_enc.empresa_id, auth.uid(), 'cliente', 'aceitar_proposta', 'propostas', v_prop.id::text, jsonb_build_object('encomenda', v_enc.codigo));
  return v_enc;
end $function$;

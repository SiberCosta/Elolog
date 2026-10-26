create function public.recusar_simulacao(p_simulacao uuid, p_motivo text) returns simulacoes
language plpgsql security definer set search_path = public as $$
declare v_sim simulacoes;
begin
  if private.minha_empresa() is null or not private.papel_em(array['admin_empresa','operador']) then
    raise exception 'Sem permissão para recusar simulações.';
  end if;
  if length(trim(coalesce(p_motivo, ''))) < 3 then
    raise exception 'Indique o motivo da recusa.';
  end if;
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.empresa_destinatario_id is distinct from private.minha_empresa() then
    raise exception 'Simulação inexistente.';
  end if;
  if v_sim.estado not in ('enviada', 'respondida') then
    raise exception 'A simulação já não está disponível (%).', v_sim.estado;
  end if;

  update propostas set estado = 'cancelada', respondida_em = now()
   where simulacao_id = v_sim.id and estado = 'enviada';
  update simulacoes set estado = 'cancelada' where id = v_sim.id returning * into v_sim;

  insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v_sim.cliente_id, 'simulacao_recusada', 'O prestador não pôde aceitar o seu pedido',
            trim(p_motivo), 'simulacoes', v_sim.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, motivo)
    values (v_sim.empresa_destinatario_id, auth.uid(), private.meu_papel()::text, 'recusar_simulacao',
            'simulacoes', v_sim.id::text, trim(p_motivo));
  return v_sim;
end $$;

revoke execute on function public.aceitar_simulacao(uuid), public.recusar_simulacao(uuid, text) from public, anon;
grant  execute on function public.aceitar_simulacao(uuid), public.recusar_simulacao(uuid, text) to authenticated;

-- ---------- 5. transitar_encomenda exige a sessão de empresa -----------
-- Mesma função da 0002, com uma alteração: o papel e a empresa vêm de meu_papel()/minha_empresa(),
-- que só devolvem valores com sessão de empresa válida.
create or replace function public.transitar_encomenda(
  p_encomenda uuid, p_para estado_encomenda, p_nota text default null
) returns encomendas
language plpgsql security definer set search_path = public as $$
declare
  v_enc   encomendas;
  v_papel papel_funcionario;
  v_falta text[] := '{}';
begin
  select * into v_enc from encomendas where id = p_encomenda for update;
  if not found then raise exception 'Encomenda inexistente.'; end if;

  if private.minha_empresa() is distinct from v_enc.empresa_id then
    raise exception 'Sem permissão para esta encomenda (inicie a sessão da empresa).';
  end if;
  v_papel := private.meu_papel();
  if v_papel is null then raise exception 'Sem permissão para esta encomenda.'; end if;

  if not exists (select 1 from encomenda_transicoes t
                  where t.de = v_enc.estado and t.para = p_para and v_papel = any (t.papeis)) then
    raise exception 'Transição % → % não permitida para o papel %.', v_enc.estado, p_para, v_papel;
  end if;

  if v_papel = 'operador_terreno' and not (
       coalesce(v_enc.criado_por = auth.uid(), false)
       or exists (select 1 from trabalhos_terreno tt
                   where tt.encomenda_id = v_enc.id and tt.operador_id = auth.uid())) then
    raise exception 'Este serviço não está atribuído ao operador.';
  end if;

  if p_para = 'armazenamento' and v_enc.criada_no_terreno then
    if v_enc.cliente_id is null and coalesce(v_enc.cliente_nome, '') = '' then v_falta := v_falta || 'cliente'; end if;
    if coalesce(v_enc.origem, '') = '' or coalesce(v_enc.destino, '') = '' then v_falta := v_falta || 'rota'; end if;
    if not exists (select 1 from pagamentos pg
                    where pg.encomenda_id = v_enc.id and pg.tipo <> 'reembolso'
                      and pg.estado in ('pendente','parcial','pago')) then
      v_falta := v_falta || 'primeiro pagamento';
    end if;
    if v_enc.assinatura_documento_id is null and v_enc.pin_validacao_hash is null then
      v_falta := v_falta || 'assinatura ou PIN do cliente';
    end if;
  end if;

  if p_para = 'expedicao' and not exists (
       select 1 from recibos_armazem ra
        where ra.encomenda_id = v_enc.id and ra.confirmado and ra.carga_conferida) then
    v_falta := v_falta || 'receção confirmada e carga conferida pelo armazém';
  end if;

  if p_para = 'em_transito' and not exists (
       select 1 from manifesto_encomendas me
         join manifestos m on m.id = me.manifesto_id
        where me.encomenda_id = v_enc.id and m.estado in ('confirmado','em_transito')) then
    v_falta := v_falta || 'manifesto confirmado';
  end if;

  if p_para = 'entregue' and not exists (
       select 1 from entregas en
        where en.encomenda_id = v_enc.id
          and coalesce(en.identificacao, '') <> ''
          and (en.assinatura_documento_id is not null or en.pin_validado)) then
    v_falta := v_falta || 'identificação e assinatura/PIN de entrega';
  end if;

  if cardinality(v_falta) > 0 then
    raise exception 'Não é possível avançar. Complete: %.', array_to_string(v_falta, ', ');
  end if;

  perform set_config('elolog.transicao', 'on', true);
  update encomendas set estado = p_para where id = v_enc.id;
  perform set_config('elolog.transicao', 'off', true);

  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id)
    values (v_enc.id, v_enc.empresa_id, v_enc.estado, p_para, p_nota, auth.uid());
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, antes, depois, motivo)
    values (v_enc.empresa_id, auth.uid(), v_papel::text, 'transicao_encomenda', 'encomendas', v_enc.id::text,
            jsonb_build_object('estado', v_enc.estado), jsonb_build_object('estado', p_para), p_nota);

  -- o cliente é avisado de cada mudança de estado
  if v_enc.cliente_id is not null then
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (v_enc.cliente_id, 'estado_encomenda', 'A sua encomenda ' || v_enc.codigo || ' mudou de estado',
              p_para::text, 'encomendas', v_enc.id);
  end if;

  select * into v_enc from encomendas where id = p_encomenda;
  return v_enc;
end $$;
revoke execute on function public.transitar_encomenda(uuid, estado_encomenda, text) from public, anon;
grant  execute on function public.transitar_encomenda(uuid, estado_encomenda, text) to authenticated;

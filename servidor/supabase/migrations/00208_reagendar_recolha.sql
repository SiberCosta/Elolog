-- 00208 (auditoria A-05 e A-12):
-- 1) Uma recolha que falhou pode voltar a «Agendamento» (reagendar). Só administrador da empresa e operador; o motivo é
--    obrigatório (o cliente vê-o) e os serviços de recolha ainda abertos no terreno ficam cancelados com essa nota.
-- 2) A transição destino → entregue estava na tabela mas era sempre recusada por encomenda_falta (é obrigatório passar
--    por «Disponível»). Sai da tabela para a lista de passos não mostrar uma opção que nunca funciona.
insert into public.encomenda_transicoes (de, para, papeis) values ('recolha', 'agendamento', '{admin_empresa,operador}')
on conflict do nothing;
delete from public.encomenda_transicoes where de = 'destino' and para = 'entregue';

create or replace function public.avancar_encomenda(p_encomenda uuid, p_para estado_encomenda, p_nota text default null::text, p_documentos uuid[] default null::uuid[], p_excecao text default null::text)
 returns encomendas language plpgsql security definer set search_path to 'public' as $function$
declare v_enc encomendas; v_papel papel_funcionario; v_falta text[]; v_resp text; v_prest text;
begin
  select * into v_enc from encomendas where id = p_encomenda for update;
  if not found then raise exception 'Encomenda inexistente.'; end if;
  if private.minha_empresa() is distinct from v_enc.empresa_id then raise exception 'Sem permissão para esta encomenda (inicie a sessão da empresa).'; end if;
  v_papel := private.meu_papel();
  if v_papel is null then raise exception 'Sem permissão para esta encomenda.'; end if;
  if v_enc.suspensa and p_para <> 'cancelada' then raise exception 'A encomenda está suspensa (%). Retome-a antes de mudar o estado.', coalesce(v_enc.suspensa_motivo, 'ocorrência'); end if;
  if not exists (select 1 from encomenda_transicoes t where t.de = v_enc.estado and t.para = p_para and v_papel = any (t.papeis)) then
    raise exception 'Transição % → % não permitida para o papel %.', v_enc.estado, p_para, v_papel; end if;
  if v_enc.estado = 'recolha' and p_para = 'agendamento' and length(trim(coalesce(p_nota, ''))) < 5 then
    raise exception 'Indique porque falhou a recolha e o que fica combinado (o cliente vê esta observação).'; end if;
  if v_papel = 'operador_terreno' and not (coalesce(v_enc.criado_por = auth.uid(), false)
       or exists (select 1 from trabalhos_terreno tt where tt.encomenda_id = v_enc.id and tt.operador_id = auth.uid())) then
    raise exception 'Este serviço não está atribuído ao operador.'; end if;
  if p_documentos is not null and exists (select 1 from unnest(p_documentos) d where not exists (select 1 from documentos x where x.id = d and (x.empresa_id = v_enc.empresa_id or x.encomenda_id = v_enc.id))) then
    raise exception 'Documento inválido para esta encomenda.'; end if;
  v_falta := private.encomenda_falta(v_enc, p_para, p_excecao);
  if cardinality(v_falta) > 0 then raise exception 'Não é possível avançar. Complete: %.', array_to_string(v_falta, ', '); end if;
  perform set_config('elolog.transicao', 'on', true);
  update encomendas set estado = p_para where id = v_enc.id;
  perform set_config('elolog.transicao', 'off', true);
  if v_enc.estado = 'recolha' and p_para = 'agendamento' then
    update trabalhos_terreno set estado = 'cancelada', notas = coalesce(notas || ' · ', '') || 'Recolha reagendada: ' || left(trim(p_nota), 200), updated_at = now()
     where encomenda_id = v_enc.id and tipo = 'recolha' and estado in ('planeada', 'em_curso');
  end if;
  select nome into v_resp from funcionarios where id = auth.uid();
  select coalesce(nome_comercial, nome) into v_prest from empresas where id = v_enc.empresa_id;
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id, codigo, responsavel, prestador, documentos, motivo_excecao)
    values (v_enc.id, v_enc.empresa_id, v_enc.estado, p_para, nullif(trim(p_nota), ''), auth.uid(), v_enc.codigo, v_resp, v_prest, p_documentos, nullif(trim(p_excecao), ''));
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, antes, depois, motivo)
    values (v_enc.empresa_id, auth.uid(), v_papel::text, 'transicao_encomenda', 'encomendas', v_enc.id::text,
            jsonb_build_object('estado', v_enc.estado), jsonb_build_object('estado', p_para), coalesce(nullif(trim(p_excecao), ''), p_nota));
  if v_enc.cliente_id is not null then
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (v_enc.cliente_id, 'estado_encomenda', case when p_para = 'disponivel' then 'A sua encomenda ' || v_enc.codigo || ' está disponível para levantamento'
              when v_enc.estado = 'recolha' and p_para = 'agendamento' then 'A recolha da encomenda ' || v_enc.codigo || ' vai ser reagendada'
              else 'A sua encomenda ' || v_enc.codigo || ' mudou de estado' end,
              case when v_enc.estado = 'recolha' and p_para = 'agendamento' then left(trim(p_nota), 300) else p_para::text end, 'encomendas', v_enc.id); end if;
  if p_para = 'destino' then
    insert into trabalhos_terreno (empresa_id, encomenda_id, tipo, data, notas) values (v_enc.empresa_id, v_enc.id, 'processamento_destino', current_date, 'Processar a chegada: conferir carga e preparar a disponibilização.');
    insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (v_enc.empresa_id, 'tarefa_destino', 'Chegada de ' || v_enc.codigo || ': processar no destino', v_enc.destino, 'encomendas', v_enc.id); end if;
  select * into v_enc from encomendas where id = p_encomenda;
  return v_enc;
end $function$;

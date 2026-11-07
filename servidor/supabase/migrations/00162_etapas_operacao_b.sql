-- v100 (parte B) — Regras automáticas de movimentação das encomendas, histórico obrigatório e ficha da operação.
-- Só ACRESCENTA colunas, transições e funções; transitar_encomenda() continua a existir (passa a usar as novas regras).
-- Regras: só avança com os requisitos da etapa; aprovação dispensada só no fluxo autorizado direto para armazém (com motivo de exceção);
-- pagamento pendente gera alerta financeiro; receção no armazém exige quantidade (e ocorrências se não bater certo); expedição exige navio,
-- viagem e data prevista; chegada cria tarefa de processamento no destino; Disponível exige essa tarefa concluída; Levantado só a partir de
-- Disponível e com confirmação do levantamento. Nunca «Em trânsito» → «Levantado» diretamente.

alter table encomendas add column if not exists navio text;
alter table encomendas add column if not exists viagem text;
alter table encomendas add column if not exists partida_prevista date;
alter table encomendas add column if not exists chegada_prevista date;
alter table recibos_armazem add column if not exists quantidade_recebida int check (quantidade_recebida is null or quantidade_recebida >= 0);
alter table encomenda_historico add column if not exists codigo text;
alter table encomenda_historico add column if not exists responsavel text;
alter table encomenda_historico add column if not exists prestador text;
alter table encomenda_historico add column if not exists documentos uuid[];
alter table encomenda_historico add column if not exists motivo_excecao text;

insert into encomenda_transicoes (de, para, papeis) select * from (values
  ('destino'::estado_encomenda, 'disponivel'::estado_encomenda, '{admin_empresa,operador}'::papel_funcionario[]),
  ('disponivel', 'entregue', '{admin_empresa,operador,operador_terreno}'),
  ('aprovacao', 'armazenamento', '{admin_empresa,operador,armazem}')) v(de, para, papeis)
 where not exists (select 1 from encomenda_transicoes t where t.de = v.de and t.para = v.para);

-- Requisitos de cada etapa (usado ao avançar e na ficha)
create or replace function private.encomenda_falta(e encomendas, p_para estado_encomenda, p_excecao text default null) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare f text[] := '{}'; r recibos_armazem;
begin
  if e.estado = 'aprovacao' and p_para = 'armazenamento' then          -- aprovação dispensada (fluxo autorizado)
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
  if p_para = 'em_transito' and not (coalesce(e.navio, '') <> '' and coalesce(e.viagem, '') <> '' and e.partida_prevista is not null)
     and not exists (select 1 from manifesto_encomendas me join manifestos m on m.id = me.manifesto_id where me.encomenda_id = e.id
                      and coalesce(m.transportador, '') <> '' and coalesce(m.numero_viagem, '') <> '' and m.partida is not null) then
    f := f || text 'navio, viagem e data prevista de partida'; end if;
  if p_para = 'disponivel' and not exists (select 1 from trabalhos_terreno t where t.encomenda_id = e.id and t.tipo = 'processamento_destino' and t.estado = 'concluida') then
    f := f || text 'processamento no destino concluído'; end if;
  if p_para = 'entregue' then
    if e.estado <> 'disponivel' then f := f || text 'passar por Destino e Disponível (chegada e aviso ao cliente)'; end if;
    if not exists (select 1 from entregas en where en.encomenda_id = e.id and coalesce(en.identificacao, '') <> '' and (en.assinatura_documento_id is not null or en.pin_validado)) then
      f := f || text 'confirmação do levantamento (identificação e assinatura/PIN)'; end if;
  end if;
  return f;
end $$;

-- Avançar uma encomenda (com histórico obrigatório)
create or replace function public.avancar_encomenda(p_encomenda uuid, p_para estado_encomenda, p_nota text default null,
  p_documentos uuid[] default null, p_excecao text default null) returns encomendas
language plpgsql security definer set search_path = public as $$
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
              else 'A sua encomenda ' || v_enc.codigo || ' mudou de estado' end, p_para::text, 'encomendas', v_enc.id); end if;
  if p_para = 'destino' then                                             -- chegada: tarefa de processamento no destino
    insert into trabalhos_terreno (empresa_id, encomenda_id, tipo, data, notas) values (v_enc.empresa_id, v_enc.id, 'processamento_destino', current_date, 'Processar a chegada: conferir carga e preparar a disponibilização.');
    insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (v_enc.empresa_id, 'tarefa_destino', 'Chegada de ' || v_enc.codigo || ': processar no destino', v_enc.destino, 'encomendas', v_enc.id); end if;
  select * into v_enc from encomendas where id = p_encomenda;
  return v_enc;
end $$;

-- A função antiga mantém o nome e passa a usar as novas regras
create or replace function public.transitar_encomenda(p_encomenda uuid, p_para estado_encomenda, p_nota text default null) returns encomendas
language sql security definer set search_path = public as $$ select public.avancar_encomenda(p_encomenda, p_para, p_nota, null, null) $$;

-- Ações de etapa (não mudam o estado; ficam no histórico)
create or replace function private.encomenda_da_empresa(p_encomenda uuid, p_papeis text[]) returns encomendas language plpgsql security definer set search_path = public as $$
declare e encomendas; begin
  select * into e from encomendas where id = p_encomenda;
  if not found or private.minha_empresa() is distinct from e.empresa_id then raise exception 'Sem permissão para esta encomenda.'; end if;
  if not private.papel_em(p_papeis) then raise exception 'A sua função não permite esta ação.'; end if;
  return e; end $$;
create or replace function private.encomenda_nota(e encomendas, p_nota text) returns void language sql security definer set search_path = public as $$
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id, codigo, responsavel, prestador)
  select e.id, e.empresa_id, e.estado, e.estado, p_nota, auth.uid(), e.codigo, (select nome from funcionarios where id = auth.uid()),
         (select coalesce(nome_comercial, nome) from empresas where id = e.empresa_id) $$;

create or replace function public.encomenda_rececao_armazem(p_encomenda uuid, p_quantidade int, p_conferida boolean, p_ocorrencias text default null,
  p_localizacao text default null, p_armazem uuid default null) returns void language plpgsql security definer set search_path = public as $$
declare e encomendas;
begin
  e := private.encomenda_da_empresa(p_encomenda, array['admin_empresa','operador','armazem']);
  if p_quantidade is null or p_quantidade < 0 then raise exception 'Indique a quantidade recebida.'; end if;
  if e.quantidade is not null and p_quantidade <> e.quantidade and length(trim(coalesce(p_ocorrencias, ''))) < 5 then
    raise exception 'A quantidade recebida (%) é diferente da prevista (%). Descreva a ocorrência.', p_quantidade, e.quantidade; end if;
  insert into recibos_armazem (encomenda_id, armazem_id, confirmado, carga_conferida, localizacao, ocorrencias, confirmado_por, confirmado_em, quantidade_recebida)
    values (e.id, p_armazem, true, coalesce(p_conferida, false), nullif(trim(p_localizacao), ''), nullif(trim(p_ocorrencias), ''), auth.uid(), now(), p_quantidade)
  on conflict (encomenda_id) do update set armazem_id = coalesce(excluded.armazem_id, recibos_armazem.armazem_id), confirmado = true, carga_conferida = excluded.carga_conferida,
    localizacao = coalesce(excluded.localizacao, recibos_armazem.localizacao), ocorrencias = excluded.ocorrencias, confirmado_por = auth.uid(), confirmado_em = now(),
    quantidade_recebida = excluded.quantidade_recebida, updated_at = now();
  perform private.encomenda_nota(e, 'Receção no armazém: ' || p_quantidade || ' volume(s)' || case when p_conferida then ', carga conferida' else '' end ||
    coalesce('. Ocorrências: ' || nullif(trim(p_ocorrencias), ''), ''));
end $$;

create or replace function public.encomenda_expedicao(p_encomenda uuid, p_navio text, p_viagem text, p_partida date, p_chegada date default null) returns void
language plpgsql security definer set search_path = public as $$
declare e encomendas;
begin
  e := private.encomenda_da_empresa(p_encomenda, array['admin_empresa','operador','armazem']);
  if length(trim(coalesce(p_navio, ''))) < 2 or length(trim(coalesce(p_viagem, ''))) < 1 or p_partida is null then raise exception 'Indique o navio, a viagem e a data prevista de partida.'; end if;
  if p_chegada is not null and p_chegada < p_partida then raise exception 'A chegada prevista não pode ser antes da partida.'; end if;
  update encomendas set navio = trim(p_navio), viagem = trim(p_viagem), partida_prevista = p_partida, chegada_prevista = p_chegada where id = e.id;
  perform private.encomenda_nota(e, 'Expedição: navio ' || trim(p_navio) || ', viagem ' || trim(p_viagem) || ', partida ' || to_char(p_partida, 'DD/MM/YYYY') ||
    coalesce(', chegada ' || to_char(p_chegada, 'DD/MM/YYYY'), ''));
end $$;

create or replace function public.encomenda_processamento_destino(p_encomenda uuid, p_nota text default null) returns void
language plpgsql security definer set search_path = public as $$
declare e encomendas;
begin
  e := private.encomenda_da_empresa(p_encomenda, array['admin_empresa','operador','armazem']);
  if e.estado <> 'destino' then raise exception 'O processamento no destino faz-se depois de confirmar a chegada.'; end if;
  update trabalhos_terreno set estado = 'concluida', notas = coalesce(nullif(trim(p_nota), ''), notas) where encomenda_id = e.id and tipo = 'processamento_destino' and estado <> 'concluida';
  if not found then raise exception 'Não há tarefa de processamento por concluir.'; end if;
  perform private.encomenda_nota(e, 'Processamento no destino concluído' || coalesce(': ' || nullif(trim(p_nota), ''), '.'));
end $$;

create or replace function public.encomenda_levantamento(p_encomenda uuid, p_identificacao text, p_documento uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e encomendas;
begin
  e := private.encomenda_da_empresa(p_encomenda, array['admin_empresa','operador','operador_terreno']);
  if e.estado <> 'disponivel' then raise exception 'O levantamento só se confirma com a encomenda Disponível.'; end if;
  if length(trim(coalesce(p_identificacao, ''))) < 3 then raise exception 'Indique a identificação de quem levanta.'; end if;
  if p_documento is null or not exists (select 1 from documentos d where d.id = p_documento and d.empresa_id = e.empresa_id) then raise exception 'Anexe o comprovativo de entrega assinado.'; end if;
  insert into entregas (encomenda_id, identificacao, assinatura_documento_id, entregue_por, entregue_em) values (e.id, trim(p_identificacao), p_documento, auth.uid(), now())
  on conflict (encomenda_id) do update set identificacao = excluded.identificacao, assinatura_documento_id = excluded.assinatura_documento_id, entregue_por = auth.uid(), entregue_em = now(), updated_at = now();
  perform private.encomenda_nota(e, 'Levantamento confirmado: ' || trim(p_identificacao));
end $$;

-- Pagamento pendente → alerta financeiro (uma vez por pagamento a cada 24 h)
create or replace function private.alerta_pagamento_pendente() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.tipo <> 'reembolso' and new.estado in ('pendente', 'parcial') and (tg_op = 'INSERT' or old.estado is distinct from new.estado)
     and not exists (select 1 from notificacoes n where n.referencia_id = new.id and n.tipo = 'alerta_financeiro' and n.created_at > now() - interval '24 hours') then
    insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      select new.empresa_id, 'alerta_financeiro', 'Pagamento ' || new.estado || ' — ' || coalesce(e.codigo, ''), new.valor || ' ' || new.moeda, 'pagamentos', new.id
        from encomendas e where e.id = new.encomenda_id;
  end if;
  return new;
end $$;
create or replace trigger alerta_pagamento_pendente after insert or update on pagamentos for each row execute function private.alerta_pagamento_pendente();

revoke all on function public.avancar_encomenda(uuid, estado_encomenda, text, uuid[], text), public.encomenda_rececao_armazem(uuid, int, boolean, text, text, uuid),
  public.encomenda_expedicao(uuid, text, text, date, date), public.encomenda_processamento_destino(uuid, text), public.encomenda_levantamento(uuid, text, uuid) from public, anon;
grant execute on function public.avancar_encomenda(uuid, estado_encomenda, text, uuid[], text), public.encomenda_rececao_armazem(uuid, int, boolean, text, text, uuid),
  public.encomenda_expedicao(uuid, text, text, date, date), public.encomenda_processamento_destino(uuid, text), public.encomenda_levantamento(uuid, text, uuid) to authenticated;
revoke all on function private.encomenda_falta(encomendas, estado_encomenda, text), private.encomenda_da_empresa(uuid, text[]), private.encomenda_nota(encomendas, text) from public, anon, authenticated;

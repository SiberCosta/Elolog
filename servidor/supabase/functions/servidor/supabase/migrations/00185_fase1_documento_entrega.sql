-- v127 — Fase 1: o comprovativo de entrega assinado no terreno conta para concluir a encomenda e passa a documento do Centro Documental (EL-ENT).
-- Substitui (create or replace) as funções do Centro Documental e a verificação de etapas, acrescentando só o caso «entrega»; o resto fica igual.

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
    if not private.entrega_confirmada(e.id) then
      f := f || text 'confirmação do levantamento (identificação e assinatura/PIN)'; end if;
  end if;
  return f;
end $$;

create or replace function private.documento_dados(p_tipo text, p_encomenda uuid, p_pagamento uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e encomendas; r jsonb; pago numeric; pg pagamentos;
begin
  select * into e from encomendas where id = p_encomenda;
  r := jsonb_build_object(
    'empresa', (select jsonb_build_object('id', m.id, 'nome', coalesce(m.nome_comercial, m.nome), 'nif', m.nif, 'morada', concat_ws(', ', m.morada, nullif(concat_ws(' ', m.codigo_postal, m.cidade), ''), m.pais),
                  'telefone', m.telefone, 'email', m.email) from empresas m where m.id = e.empresa_id),
    'cliente', (select jsonb_build_object('nome', coalesce(c.nome, e.cliente_nome), 'nif', coalesce(c.nif, e.cliente_nif)) from (select 1) x left join clientes c on c.id = e.cliente_id),
    'remetente', coalesce(e.remetente, '{}'::jsonb) - 'nif', 'destinatario', coalesce(e.destinatario, '{}'::jsonb) - 'nif',
    'encomenda', jsonb_build_object('codigo', e.codigo, 'simulacao', (select s.codigo from simulacoes s where s.id = e.simulacao_id), 'origem', e.origem, 'destino', e.destino,
      'modalidade', case when e.navio is not null then 'Marítimo' else 'A confirmar pelo prestador' end, 'tipo_carga', e.tipo_carga, 'descricao', e.descricao,
      'quantidade', e.quantidade, 'peso_kg', e.peso_kg, 'volume_m3', e.volume_m3, 'volumes', coalesce(e.volumes, '[]'::jsonb), 'valor_declarado', e.valor_declarado,
      'data_prevista', e.data_prevista, 'morada_recolha', e.morada_recolha, 'navio', e.navio, 'viagem', e.viagem, 'partida_prevista', e.partida_prevista,
      'chegada_prevista', e.chegada_prevista, 'observacoes', e.observacoes),
    'ocorrencias', (select coalesce(jsonb_agg(jsonb_build_object('codigo', o.codigo, 'tipo', o.tipo, 'descricao', o.descricao, 'em', o.created_at) order by o.created_at), '[]'::jsonb)
                      from ocorrencias o where o.encomenda_id = e.id));
  if p_tipo = 'rececao' then
    r := r || jsonb_build_object('rececao', (select jsonb_build_object('em', ra.confirmado_em, 'por', f.nome, 'armazem', a.nome, 'quantidade_esperada', e.quantidade,
            'quantidade_recebida', ra.quantidade_recebida, 'conferida', ra.carga_conferida, 'localizacao', ra.localizacao, 'ocorrencias', ra.ocorrencias)
          from recibos_armazem ra left join armazens a on a.id = ra.armazem_id left join funcionarios f on f.id = ra.confirmado_por where ra.encomenda_id = e.id));
  elsif p_tipo = 'pagamento' then
    select * into pg from pagamentos where id = p_pagamento;
    select coalesce(sum(case when tipo = 'reembolso' then -valor else valor end), 0) into pago from pagamentos
     where encomenda_id = e.id and estado = 'pago' and coalesce(pago_em, created_at) <= coalesce(pg.pago_em, pg.created_at);
    r := r || jsonb_build_object('pagamento', jsonb_build_object('codigo', pg.codigo, 'valor', pg.valor, 'moeda', pg.moeda, 'metodo', pg.metodo, 'referencia', pg.referencia,
            'em', coalesce(pg.pago_em, pg.created_at), 'total_encomenda', e.preco_total, 'total_pago', pago, 'saldo', greatest(coalesce(e.preco_total, 0) - pago, 0),
            'estado', case when coalesce(e.preco_total, 0) - pago <= 0 then 'integral' else 'parcial' end));
  elsif p_tipo = 'entrega' then
    r := r || jsonb_build_object('entrega', (select jsonb_build_object('recebido_por', c.recebido_por, 'identificacao', c.identificacao, 'feito_em', c.feito_em, 'lat', c.lat, 'lon', c.lon,
            'precisao_m', c.precisao_m, 'volumes_conferidos', c.volumes_conferidos, 'notas', c.notas, 'assinatura', c.assinatura, 'motorista', f.nome,
            'fotos', (select count(*) from comprovativos_terreno_fotos x where x.comprovativo_id = c.id))
          from comprovativos_terreno c left join funcionarios f on f.id = c.criado_por where c.encomenda_id = e.id and c.resultado = 'entregue' order by c.recebido_em desc limit 1));
  end if;
  return r;
end $$;

create or replace function private.documento_emitir(p_tipo text, p_encomenda uuid, p_pagamento uuid, p_motivo text, p_reemitir boolean)
returns public.documentos_emitidos language plpgsql security definer set search_path = public as $$
declare e encomendas; atual documentos_emitidos; novo documentos_emitidos; d jsonb; n int; v_ano int := extract(year from now())::int;
begin
  select * into e from encomendas where id = p_encomenda;
  if not found then raise exception 'Encomenda não encontrada.'; end if;
  select * into atual from documentos_emitidos where empresa_id = e.empresa_id and tipo = p_tipo and coalesce(pagamento_id, encomenda_id) = coalesce(p_pagamento, p_encomenda)
     and estado = 'valido' for update;
  if found and not p_reemitir then return atual; end if;
  d := private.documento_dados(p_tipo, p_encomenda, p_pagamento);
  if atual.id is not null then
    if atual.dados = d then raise exception 'Os dados não mudaram desde a versão %: não é preciso emitir nova versão.', atual.versao; end if;
    update documentos_emitidos set estado = 'substituido' where id = atual.id;
    insert into documentos_emitidos (empresa_id, tipo, numero, versao, encomenda_id, pagamento_id, cliente_id, referencia, dados, sha256, motivo, substitui_id, emitido_por)
    values (e.empresa_id, p_tipo, atual.numero, atual.versao + 1, p_encomenda, p_pagamento, e.cliente_id, e.codigo, d, encode(extensions.digest(d::text, 'sha256'), 'hex'),
            p_motivo, atual.id, auth.uid()) returning * into novo;
    insert into documentos_eventos (documento_id, acao, user_id, detalhe) values (novo.id, 'reemitido', auth.uid(), p_motivo);
  else
    insert into documentos_numeracao (empresa_id, tipo, ano, ultimo) values (e.empresa_id, p_tipo, v_ano, 1)
      on conflict (empresa_id, tipo, ano) do update set ultimo = documentos_numeracao.ultimo + 1 returning ultimo into n;
    insert into documentos_emitidos (empresa_id, tipo, numero, encomenda_id, pagamento_id, cliente_id, referencia, dados, sha256, emitido_por)
    values (e.empresa_id, p_tipo, 'EL-' || case p_tipo when 'guia' then 'GUI' when 'rececao' then 'REC' when 'entrega' then 'ENT' else 'RCP' end || '-' || v_ano || '-' || lpad(n::text, 6, '0'),
            p_encomenda, p_pagamento, e.cliente_id, e.codigo, d, encode(extensions.digest(d::text, 'sha256'), 'hex'), auth.uid()) returning * into novo;
    insert into documentos_eventos (documento_id, acao, user_id) values (novo.id, 'emitido', auth.uid());
  end if;
  if e.cliente_id is not null then
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (e.cliente_id, 'documento_emitido', case p_tipo when 'guia' then 'Guia da encomenda' when 'rececao' then 'Carga recebida no armazém' when 'entrega' then 'Comprovativo de entrega' else 'Comprovativo de pagamento' end
            || ' · ' || e.codigo, 'O documento ' || novo.numero || case when novo.versao > 1 then ' (versão ' || novo.versao || ')' else '' end || ' está disponível nos seus documentos.',
            'documentos_emitidos', novo.id);
  end if;
  return novo;
end $$;

create or replace function private.documento_pode(p_tipo text, p_encomenda uuid, p_pagamento uuid) returns text language sql stable security definer set search_path = public as $$
  select case p_tipo
    when 'guia' then case when (select estado from encomendas where id = p_encomenda) in ('aprovacao', 'cancelada') then 'A guia só é emitida depois de a encomenda ser aprovada.' end
    when 'rececao' then case when not exists (select 1 from recibos_armazem where encomenda_id = p_encomenda and confirmado) then 'A receção ainda não foi confirmada pelo armazém.' end
    when 'pagamento' then case when not exists (select 1 from pagamentos where id = p_pagamento and encomenda_id = p_encomenda and estado = 'pago' and tipo <> 'reembolso')
                               then 'O pagamento ainda não está confirmado.' end
    when 'entrega' then case when not exists (select 1 from comprovativos_terreno c where c.encomenda_id = p_encomenda and c.resultado = 'entregue')
                             then 'Ainda não há comprovativo de entrega assinado no terreno.' end
    else 'Tipo de documento inválido.' end $$;

create or replace function private.documento_papeis(p_tipo text) returns text[] language sql immutable as $$
  select case p_tipo when 'guia' then array['admin_empresa', 'operador'] when 'rececao' then array['admin_empresa', 'operador', 'armazem']
                     when 'entrega' then array['admin_empresa', 'operador', 'operador_terreno'] else array['admin_empresa', 'financeiro'] end $$;

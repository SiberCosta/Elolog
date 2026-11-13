-- v123: Centro Documental — emissão automática, reemissão com nova versão, histórico e validação pública pelo QR.
-- Um documento só é emitido quando a operação foi confirmada: guia quando a encomenda sai da aprovação; guia de receção quando o armazém
-- confirma a receção; comprovativo quando um pagamento fica «pago». O comprovativo operacional NÃO é recibo fiscal.

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
    values (e.empresa_id, p_tipo, 'EL-' || case p_tipo when 'guia' then 'GUI' when 'rececao' then 'REC' else 'RCP' end || '-' || v_ano || '-' || lpad(n::text, 6, '0'),
            p_encomenda, p_pagamento, e.cliente_id, e.codigo, d, encode(extensions.digest(d::text, 'sha256'), 'hex'), auth.uid()) returning * into novo;
    insert into documentos_eventos (documento_id, acao, user_id) values (novo.id, 'emitido', auth.uid());
  end if;
  if e.cliente_id is not null then
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (e.cliente_id, 'documento_emitido', case p_tipo when 'guia' then 'Guia da encomenda' when 'rececao' then 'Carga recebida no armazém' else 'Comprovativo de pagamento' end
            || ' · ' || e.codigo, 'O documento ' || novo.numero || case when novo.versao > 1 then ' (versão ' || novo.versao || ')' else '' end || ' está disponível nos seus documentos.',
            'documentos_emitidos', novo.id);
  end if;
  return novo;
end $$;

-- condições: nenhum documento declara uma operação que não foi confirmada
create or replace function private.documento_pode(p_tipo text, p_encomenda uuid, p_pagamento uuid) returns text language sql stable security definer set search_path = public as $$
  select case p_tipo
    when 'guia' then case when (select estado from encomendas where id = p_encomenda) in ('aprovacao', 'cancelada') then 'A guia só é emitida depois de a encomenda ser aprovada.' end
    when 'rececao' then case when not exists (select 1 from recibos_armazem where encomenda_id = p_encomenda and confirmado) then 'A receção ainda não foi confirmada pelo armazém.' end
    when 'pagamento' then case when not exists (select 1 from pagamentos where id = p_pagamento and encomenda_id = p_encomenda and estado = 'pago' and tipo <> 'reembolso')
                               then 'O pagamento ainda não está confirmado.' end
    else 'Tipo de documento inválido.' end $$;

-- emissão automática (nunca bloqueia a operação principal: um erro no documento fica só registado como aviso)
create or replace function private.documentos_automaticos() returns trigger language plpgsql security definer set search_path = public as $$
declare t text; enc uuid; pag uuid;
begin
  if tg_table_name = 'encomendas' then t := 'guia'; enc := new.id;
  elsif tg_table_name = 'recibos_armazem' then t := 'rececao'; enc := new.encomenda_id;
  else t := 'pagamento'; enc := new.encomenda_id; pag := new.id; end if;
  if enc is null or private.documento_pode(t, enc, pag) is not null then return new; end if;
  begin perform private.documento_emitir(t, enc, pag, null, false);
  exception when others then raise warning 'Centro documental: % não emitido para %: %', t, enc, sqlerrm; end;
  return new;
end $$;
create or replace trigger documentos_guia after insert or update of estado on public.encomendas for each row execute function private.documentos_automaticos();
create or replace trigger documentos_rececao after insert or update of confirmado on public.recibos_armazem for each row execute function private.documentos_automaticos();
create or replace trigger documentos_pagamento after insert or update of estado on public.pagamentos for each row execute function private.documentos_automaticos();

-- quem pode emitir/reemitir cada tipo
create or replace function private.documento_papeis(p_tipo text) returns text[] language sql immutable as $$
  select case p_tipo when 'guia' then array['admin_empresa', 'operador'] when 'rececao' then array['admin_empresa', 'operador', 'armazem'] else array['admin_empresa', 'financeiro'] end $$;

-- emitir manualmente um documento em falta (ex.: encomendas anteriores ao Centro Documental)
create or replace function public.emitir_documento(p_encomenda text, p_tipo text, p_pagamento text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e encomendas; pg uuid; falta text; d documentos_emitidos;
begin
  select * into e from encomendas where codigo = upper(trim(p_encomenda));
  if not found or e.empresa_id is distinct from private.minha_empresa() then raise exception 'Encomenda não encontrada nesta empresa.'; end if;
  if not private.papel_em(private.documento_papeis(p_tipo)) then raise exception 'A sua função não pode emitir este documento.' using errcode = '42501'; end if;
  if p_tipo = 'pagamento' then select id into pg from pagamentos where codigo = p_pagamento and encomenda_id = e.id; end if;
  falta := private.documento_pode(p_tipo, e.id, pg);
  if falta is not null then raise exception '%', falta; end if;
  d := private.documento_emitir(p_tipo, e.id, pg, null, false);
  return jsonb_build_object('id', d.id, 'numero', d.numero, 'versao', d.versao);
end $$;

-- corrigir: nova versão com o mesmo número; a anterior fica «substituída» e continua consultável
create or replace function public.reemitir_documento(p_documento uuid, p_motivo text) returns jsonb language plpgsql security definer set search_path = public as $$
declare d documentos_emitidos; n documentos_emitidos;
begin
  select * into d from documentos_emitidos where id = p_documento;
  if not found or d.empresa_id is distinct from private.minha_empresa() then raise exception 'Documento não encontrado nesta empresa.'; end if;
  if d.estado <> 'valido' then raise exception 'Só a versão em vigor pode ser corrigida.'; end if;
  if not private.papel_em(private.documento_papeis(d.tipo)) then raise exception 'A sua função não pode emitir este documento.' using errcode = '42501'; end if;
  if length(trim(coalesce(p_motivo, ''))) < 5 then raise exception 'Indique o motivo da nova versão.'; end if;
  n := private.documento_emitir(d.tipo, d.encomenda_id, d.pagamento_id, trim(p_motivo), true);
  return jsonb_build_object('id', n.id, 'numero', n.numero, 'versao', n.versao);
end $$;

-- histórico de consulta, impressão e descarga
create or replace function public.registar_evento_documento(p_documento uuid, p_acao text) returns void language plpgsql security definer set search_path = public as $$
declare d documentos_emitidos;
begin
  if p_acao not in ('consultado', 'impresso', 'descarregado') then raise exception 'Ação inválida.'; end if;
  select * into d from documentos_emitidos where id = p_documento;
  if not found or not private.documento_visivel(d) then raise exception 'Documento não encontrado.'; end if;
  insert into documentos_eventos (documento_id, acao, user_id) values (d.id, p_acao, auth.uid());
end $$;

-- validação pública pelo QR: só o que não é confidencial (sem nomes, moradas, valores ou contactos).
-- Só a função do servidor «validar-documento» a chama (chave de serviço, com limite de pedidos por IP): o público continua a executar só validar_empresa.
create or replace function public.servico_validar_documento(p_codigo text) returns jsonb language plpgsql security definer set search_path = public as $$
declare d documentos_emitidos; ultima int;
begin
  if p_codigo !~ '^[0-9a-f]{24}$' then return jsonb_build_object('encontrado', false); end if;
  select * into d from documentos_emitidos where codigo_validacao = p_codigo;
  if not found then return jsonb_build_object('encontrado', false); end if;
  select max(versao) into ultima from documentos_emitidos where empresa_id = d.empresa_id and numero = d.numero;
  insert into documentos_eventos (documento_id, acao, user_id) values (d.id, 'validado', auth.uid());
  return jsonb_build_object('encontrado', true, 'tipo', d.tipo, 'numero', d.numero, 'versao', d.versao, 'versao_atual', ultima, 'estado', d.estado,
    'emitido_em', d.emitido_em, 'referencia', d.referencia, 'empresa', d.dados -> 'empresa' ->> 'nome', 'sha256', d.sha256,
    'logotipo', (select logotipo from empresas_marca where empresa_id = d.empresa_id));
end $$;

-- marca do prestador
create or replace function public.definir_logotipo(p_logotipo text) returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid := private.minha_empresa();
begin
  if v_emp is null or not private.papel_em(array['admin_empresa']) then raise exception 'Só o administrador da empresa altera o logótipo.' using errcode = '42501'; end if;
  if coalesce(p_logotipo, '') = '' then raise exception 'Escolha uma imagem PNG, JPEG ou WebP.'; end if;
  insert into empresas_marca (empresa_id, logotipo) values (v_emp, p_logotipo)
    on conflict (empresa_id) do update set logotipo = excluded.logotipo, atualizado_em = now();
end $$;
create or replace function public.logotipo_empresa(p_empresa uuid) returns text language sql stable security definer set search_path = public as $$
  select logotipo from empresas_marca where empresa_id = p_empresa $$;

revoke all on function public.emitir_documento(text, text, text), public.reemitir_documento(uuid, text), public.registar_evento_documento(uuid, text),
  public.servico_validar_documento(text), public.definir_logotipo(text), public.logotipo_empresa(uuid) from public, anon, authenticated;
grant execute on function public.emitir_documento(text, text, text), public.reemitir_documento(uuid, text), public.registar_evento_documento(uuid, text),
  public.definir_logotipo(text), public.logotipo_empresa(uuid) to authenticated;
grant execute on function public.servico_validar_documento(text) to service_role;
revoke all on function private.documento_emitir(text, uuid, uuid, text, boolean), private.documento_dados(text, uuid, uuid), private.documento_pode(text, uuid, uuid)
  from public, anon, authenticated;

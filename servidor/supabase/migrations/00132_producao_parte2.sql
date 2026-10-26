-- Elolog — produção, parte 2: registo de faturas certificadas e pagamentos ifthenpay (Multibanco e MB WAY).

-- ---------- 1. Registar uma fatura a partir do QR da AT ---------------------------
create or replace function public.registar_fatura(p_documento uuid, p_qr text, p_encomenda uuid default null)
returns faturas language plpgsql security definer set search_path = public as $$
declare m jsonb := '{}'; parte text; k text; v text; e empresas; en encomendas; d documentos; f faturas;
        v_total numeric; v_data date; v_faturado numeric;
begin
  if not private.papel_em(array['admin_empresa','financeiro']) then raise exception 'Só o administrador ou o financeiro registam faturas.'; end if;
  select * into e from empresas where id = private.minha_empresa();
  select * into d from documentos where id = p_documento and empresa_id = e.id;
  if d.id is null then raise exception 'Documento não encontrado nesta empresa.'; end if;
  if length(coalesce(p_qr, '')) not between 20 and 1000 then raise exception 'Código QR da fatura em falta ou inválido.'; end if;
  foreach parte in array string_to_array(p_qr, '*') loop
    k := split_part(parte, ':', 1); v := substr(parte, length(k) + 2);
    if k <> '' then m := m || jsonb_build_object(k, v); end if;
  end loop;
  if not (m ? 'A' and m ? 'B' and m ? 'D' and m ? 'F' and m ? 'G' and m ? 'H' and m ? 'O') then
    raise exception 'O QR não tem os campos obrigatórios da AT (A, B, D, F, G, H, O).'; end if;
  if regexp_replace(m->>'A', '^PT', '') <> regexp_replace(coalesce(e.nif, ''), '^PT', '') then
    raise exception 'O NIF do emitente (%) não é o NIF da empresa.', m->>'A'; end if;
  if not private.nif_valido(m->>'B') then raise exception 'NIF do cliente inválido: %', m->>'B'; end if;
  if m->>'D' not in ('FT','FR','FS','NC','ND') then raise exception 'Tipo de documento não aceite: %', m->>'D'; end if;
  if coalesce(m->>'E', 'N') = 'A' then raise exception 'Esta fatura está anulada.'; end if;
  if m->>'H' !~ '^[A-Z0-9]{8,}-[0-9]+$' then raise exception 'ATCUD inválido: %', m->>'H'; end if;
  begin v_data := to_date(m->>'F', 'YYYYMMDD'); v_total := (m->>'O')::numeric;
  exception when others then raise exception 'Data ou total ilegíveis no QR.'; end;
  if v_data > current_date or v_data < current_date - 400 then raise exception 'Data da fatura fora do intervalo aceite.'; end if;
  if p_encomenda is not null then
    select * into en from encomendas where id = p_encomenda and empresa_id = e.id;
    if en.id is null then raise exception 'Encomenda não encontrada nesta empresa.'; end if;
    if en.cliente_nif is not null and m->>'B' <> '999999990' and m->>'B' <> en.cliente_nif then
      raise exception 'O NIF do cliente na fatura (%) não corresponde ao da encomenda.', m->>'B'; end if;
    select coalesce(sum(case when tipo_documento = 'NC' then -total else total end), 0) into v_faturado
      from faturas where encomenda_id = en.id and estado = 'valida';
    if m->>'D' <> 'NC' and en.preco_total is not null and v_faturado + v_total > en.preco_total + 0.01 then
      raise exception 'O total faturado (% €) passaria o preço da encomenda (% €).', v_faturado + v_total, en.preco_total; end if;
  end if;
  insert into faturas (empresa_id, encomenda_id, cliente_id, documento_id, tipo_documento, numero, atcud, data_emissao,
    nif_emitente, nif_adquirente, total, total_iva, hash4, certificado, qr_texto)
  values (e.id, en.id, en.cliente_id, d.id, m->>'D', m->>'G', m->>'H', v_data, m->>'A', m->>'B', v_total,
    coalesce(nullif(m->>'N', '')::numeric, 0), m->>'Q', m->>'R', p_qr)
  returning * into f;
  update documentos set categoria = 'fatura', visibilidade = case when en.id is null then visibilidade else 'cliente' end,
    encomenda_id = coalesce(en.id, encomenda_id) where id = d.id;
  if en.cliente_id is not null then
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (en.cliente_id, 'fatura_emitida', 'Fatura ' || f.numero, 'A fatura da encomenda ' || en.codigo || ' já está nos seus documentos.', 'faturas', f.id);
  end if;
  insert into auditoria (empresa_id, user_id, acao, entidade, entidade_id, depois)
  values (e.id, auth.uid(), 'registar_fatura', 'faturas', f.id::text, jsonb_build_object('numero', f.numero, 'total', f.total));
  return f;
exception when unique_violation then raise exception 'Esta fatura (número ou ATCUD) já foi registada.';
end $$;
revoke all on function public.registar_fatura(uuid, text, uuid) from public, anon;
grant execute on function public.registar_fatura(uuid, text, uuid) to authenticated;

create or replace function private.tipo_envia_email(p_tipo text) returns boolean language sql immutable set search_path = public as $$
  select p_tipo in ('novo_prestador', 'pedido_subscricao', 'pedido_cliente', 'apoio', 'nova_simulacao', 'empresa_aprovada',
    'empresa_recusada', 'pagamento_confirmado', 'simulacao_aceite', 'simulacao_recusada', 'estado_encomenda', 'fatura_emitida', 'pagamento_recebido') $$;

-- ---------- 2. Configuração de pagamentos da empresa ---------------------------
-- As chaves da ifthenpay ficam numa tabela sem acesso pela aplicação; só funções de servidor as leem.
create table if not exists empresa_pagamentos_config (
  empresa_id uuid primary key references empresas(id) on delete cascade,
  mb_key text, mbway_key text, chave_antiphishing text,
  ativo boolean not null default false, sandbox boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table empresa_pagamentos_config enable row level security;
revoke all on empresa_pagamentos_config from anon, authenticated;

create or replace function public.ver_config_pagamentos() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c empresa_pagamentos_config; mascara text := '••••';
begin
  if not private.papel_em(array['admin_empresa','financeiro']) then raise exception 'Sem permissão.'; end if;
  select * into c from empresa_pagamentos_config where empresa_id = private.minha_empresa();
  return jsonb_build_object('multibanco', case when c.mb_key is null then null else mascara || right(c.mb_key, 3) end,
    'mbway', case when c.mbway_key is null then null else mascara || right(c.mbway_key, 3) end,
    'antiphishing', c.chave_antiphishing is not null, 'ativo', coalesce(c.ativo, false), 'sandbox', coalesce(c.sandbox, true));
end $$;

create or replace function public.guardar_config_pagamentos(p_mb_key text, p_mbway_key text, p_antiphishing text, p_ativo boolean, p_sandbox boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid := private.minha_empresa(); limpa text;
begin
  if not private.papel_em(array['admin_empresa']) then raise exception 'Só o administrador da empresa altera os pagamentos.'; end if;
  foreach limpa in array array[p_mb_key, p_mbway_key] loop
    if nullif(trim(limpa), '') is not null and trim(limpa) !~ '^[A-Za-z0-9-]{6,40}$' then raise exception 'Chave ifthenpay com formato inválido.'; end if;
  end loop;
  if nullif(trim(p_antiphishing), '') is not null and length(trim(p_antiphishing)) < 12 then raise exception 'A chave anti-phishing deve ter pelo menos 12 caracteres.'; end if;
  insert into empresa_pagamentos_config (empresa_id) values (v_emp) on conflict (empresa_id) do nothing;
  update empresa_pagamentos_config set
    mb_key = coalesce(nullif(trim(p_mb_key), ''), mb_key), mbway_key = coalesce(nullif(trim(p_mbway_key), ''), mbway_key),
    chave_antiphishing = coalesce(nullif(trim(p_antiphishing), ''), chave_antiphishing),
    ativo = coalesce(p_ativo, ativo), sandbox = coalesce(p_sandbox, sandbox), updated_at = now()
  where empresa_id = v_emp;
  if p_ativo and exists (select 1 from empresa_pagamentos_config where empresa_id = v_emp
                         and (chave_antiphishing is null or (mb_key is null and mbway_key is null))) then
    raise exception 'Para ativar indique a chave anti-phishing e pelo menos uma chave (Multibanco ou MB WAY).'; end if;
  insert into auditoria (empresa_id, user_id, acao, entidade, entidade_id) values (v_emp, auth.uid(), 'config_pagamentos', 'empresas', v_emp::text);
  return public.ver_config_pagamentos();
end $$;
revoke all on function public.ver_config_pagamentos(), public.guardar_config_pagamentos(text, text, text, boolean, boolean) from public, anon;
grant execute on function public.ver_config_pagamentos(), public.guardar_config_pagamentos(text, text, text, boolean, boolean) to authenticated;

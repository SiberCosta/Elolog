-- Elolog — produção, parte 3: pedidos de pagamento (ifthenpay) e posições reais dos navios (AIS).

-- ---------- 1. Pedidos de pagamento ---------------------------------------------
create table if not exists pedidos_pagamento (
  id uuid primary key default gen_random_uuid(),
  order_id text not null unique check (length(order_id) <= 15),
  empresa_id uuid not null references empresas(id) on delete cascade,
  encomenda_id uuid not null references encomendas(id) on delete cascade,
  cliente_id uuid not null,
  metodo text not null check (metodo in ('multibanco','mbway')),
  valor numeric(12,2) not null check (valor > 0),
  estado text not null default 'pendente' check (estado in ('pendente','pago','expirado','recusado','erro')),
  request_id text, entidade text, referencia text, telemovel text, mensagem text,
  expira_em timestamptz, pago_em timestamptz, pagamento_id uuid references pagamentos(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists pedidos_pagamento_encomenda on pedidos_pagamento (encomenda_id, estado);
alter table pedidos_pagamento enable row level security;
create policy pedidos_cliente_ver on pedidos_pagamento for select to authenticated using (cliente_id = auth.uid());
create policy pedidos_empresa_ver on pedidos_pagamento for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro','operador']));
create policy pedidos_admin_ver on pedidos_pagamento for select to authenticated using (private.e_admin_plataforma());
revoke insert, update, delete on pedidos_pagamento from anon, authenticated;

-- Só a função de servidor «pagamentos» (chave de serviço) usa as três funções abaixo.
create or replace function public.servico_preparar_pedido(p_cliente uuid, p_encomenda text, p_metodo text, p_telemovel text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare en encomendas; c empresa_pagamentos_config; v_pago numeric; v_valor numeric; p pedidos_pagamento;
begin
  select * into en from encomendas where codigo = p_encomenda and cliente_id = p_cliente;
  if en.id is null then raise exception 'Encomenda não encontrada.'; end if;
  select * into c from empresa_pagamentos_config where empresa_id = en.empresa_id and ativo;
  if c.empresa_id is null then raise exception 'Esta empresa ainda não aceita pagamentos online.'; end if;
  if p_metodo = 'multibanco' and c.mb_key is null or p_metodo = 'mbway' and c.mbway_key is null then raise exception 'Método não disponível para esta empresa.'; end if;
  if p_metodo = 'mbway' and coalesce(p_telemovel, '') !~ '^9[1236][0-9]{7}$' then raise exception 'Indique um telemóvel português válido (9 dígitos).'; end if;
  if (select count(*) from pedidos_pagamento where encomenda_id = en.id and created_at > now() - interval '1 hour') >= 6 then
    raise exception 'Demasiados pedidos de pagamento seguidos. Tente daqui a pouco.'; end if;
  select coalesce(sum(valor), 0) into v_pago from pagamentos where encomenda_id = en.id and estado = 'pago';
  v_valor := round(coalesce(en.preco_total, 0) - v_pago, 2);
  if v_valor <= 0 then raise exception 'Esta encomenda já está paga.'; end if;
  -- Reaproveita uma referência Multibanco ainda válida com o mesmo valor.
  select * into p from pedidos_pagamento where encomenda_id = en.id and metodo = 'multibanco' and p_metodo = 'multibanco'
    and estado = 'pendente' and valor = v_valor and referencia is not null and (expira_em is null or expira_em > now()) limit 1;
  if p.id is not null then return jsonb_build_object('reutilizar', true, 'pedido', to_jsonb(p)); end if;
  update pedidos_pagamento set estado = 'expirado', updated_at = now() where encomenda_id = en.id and estado = 'pendente' and metodo = p_metodo;
  insert into pedidos_pagamento (order_id, empresa_id, encomenda_id, cliente_id, metodo, valor, telemovel)
  values ('EL' || upper(substr(md5(gen_random_uuid()::text), 1, 12)), en.empresa_id, en.id, p_cliente, p_metodo, v_valor, nullif(p_telemovel, ''))
  returning * into p;
  return jsonb_build_object('reutilizar', false, 'pedido', to_jsonb(p), 'sandbox', c.sandbox,
    'chave', case when p_metodo = 'multibanco' then c.mb_key else c.mbway_key end, 'descricao', 'Encomenda ' || en.codigo);
end $$;

create or replace function public.servico_atualizar_pedido(p_id uuid, p_estado text, p_dados jsonb)
returns void language sql security definer set search_path = public as $$
  update pedidos_pagamento set estado = coalesce(p_estado, estado), request_id = coalesce(p_dados->>'request_id', request_id),
    entidade = coalesce(p_dados->>'entidade', entidade), referencia = coalesce(p_dados->>'referencia', referencia),
    expira_em = coalesce((p_dados->>'expira_em')::timestamptz, expira_em), mensagem = left(coalesce(p_dados->>'mensagem', mensagem), 300),
    updated_at = now()
  where id = p_id and estado = 'pendente' $$;

-- Confirma um pagamento (aviso da ifthenpay ou verificação do MB WAY). Repetir não paga duas vezes.
create or replace function public.servico_confirmar_pedido(p_order_id text, p_chave text, p_valor numeric, p_origem text)
returns text language plpgsql security definer set search_path = public as $$
declare p pedidos_pagamento; c empresa_pagamentos_config; v_pag uuid; en encomendas;
begin
  select * into p from pedidos_pagamento where order_id = p_order_id for update;
  if p.id is null then return 'desconhecido'; end if;
  select * into c from empresa_pagamentos_config where empresa_id = p.empresa_id;
  if p_origem = 'aviso' and (c.chave_antiphishing is null or p_chave is distinct from c.chave_antiphishing) then return 'chave_invalida'; end if;
  if p.estado = 'pago' then return 'ja_pago'; end if;
  if abs(coalesce(p_valor, -1) - p.valor) > 0.009 then return 'valor_diferente'; end if;
  insert into pagamentos (empresa_id, encomenda_id, cliente_id, tipo, valor, estado, metodo, referencia, pago_em)
  values (p.empresa_id, p.encomenda_id, p.cliente_id, 'total', p.valor, 'pago',
    case when p.metodo = 'mbway' then 'MB WAY' else 'Multibanco' end, coalesce(p.referencia, p.request_id, p.order_id), now())
  returning id into v_pag;
  update pedidos_pagamento set estado = 'pago', pago_em = now(), pagamento_id = v_pag, updated_at = now() where id = p.id;
  select * into en from encomendas where id = p.encomenda_id;
  insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  values (p.cliente_id, 'pagamento_recebido', 'Pagamento recebido', 'Recebemos ' || p.valor || ' € da encomenda ' || en.codigo || '.', 'pagamentos', v_pag);
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  values (p.empresa_id, 'pagamento_recebido', 'Pagamento recebido · ' || en.codigo, p.valor || ' € por ' || p.metodo || '.', 'pagamentos', v_pag);
  insert into auditoria (empresa_id, acao, entidade, entidade_id, depois)
  values (p.empresa_id, 'pagamento_online', 'pagamentos', v_pag::text, jsonb_build_object('metodo', p.metodo, 'valor', p.valor, 'origem', p_origem));
  return 'pago';
end $$;

-- Pedidos MB WAY à espera, para a verificação periódica (caso o aviso não chegue).
create or replace function public.servico_pedidos_mbway_pendentes() returns table (id uuid, order_id text, request_id text, valor numeric, chave text, sandbox boolean)
language plpgsql security definer set search_path = public as $$
begin
  update pedidos_pagamento pp set estado = 'expirado', updated_at = now()
    where pp.estado = 'pendente' and (pp.metodo = 'mbway' and pp.created_at < now() - interval '30 minutes' or pp.expira_em < now());
  return query select pp.id, pp.order_id, pp.request_id, pp.valor, c.mbway_key, c.sandbox from pedidos_pagamento pp
    join empresa_pagamentos_config c on c.empresa_id = pp.empresa_id
    where pp.metodo = 'mbway' and pp.estado = 'pendente' and pp.request_id is not null limit 50;
end $$;

revoke all on function public.servico_preparar_pedido(uuid, text, text, text), public.servico_atualizar_pedido(uuid, text, jsonb),
  public.servico_confirmar_pedido(text, text, numeric, text), public.servico_pedidos_mbway_pendentes() from public, anon, authenticated;
grant execute on function public.servico_preparar_pedido(uuid, text, text, text), public.servico_atualizar_pedido(uuid, text, jsonb),
  public.servico_confirmar_pedido(text, text, numeric, text), public.servico_pedidos_mbway_pendentes() to service_role;

-- ---------- 2. Navios seguidos e posições AIS -----------------------------------
create table if not exists navios_seguidos (
  empresa_id uuid not null references empresas(id) on delete cascade,
  mmsi text not null check (mmsi ~ '^[0-9]{9}$'),
  nome text not null check (length(nome) between 2 and 80),
  viagem text, created_at timestamptz not null default now(),
  primary key (empresa_id, mmsi)
);
create table if not exists navios_posicoes (
  mmsi text primary key, nome text, imo text, latitude double precision, longitude double precision,
  velocidade_nos numeric, rumo numeric, destino text, eta timestamptz, posicao_em timestamptz, atualizado_em timestamptz not null default now()
);
alter table navios_seguidos enable row level security;
alter table navios_posicoes enable row level security;
create policy navios_seguidos_empresa on navios_seguidos for all to authenticated
  using (empresa_id = private.minha_empresa()) with check (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','armazem']));
create policy navios_posicoes_ver on navios_posicoes for select to authenticated
  using (private.e_admin_plataforma() or exists (select 1 from navios_seguidos s where s.mmsi = navios_posicoes.mmsi and s.empresa_id = private.minha_empresa()));
revoke insert, update, delete on navios_posicoes from anon, authenticated;

create or replace function public.servico_navios_seguidos() returns table (mmsi text) language sql stable security definer set search_path = public as $$
  select distinct mmsi from navios_seguidos order by 1 limit 50 $$;
revoke all on function public.servico_navios_seguidos() from public, anon, authenticated;
grant execute on function public.servico_navios_seguidos() to service_role;

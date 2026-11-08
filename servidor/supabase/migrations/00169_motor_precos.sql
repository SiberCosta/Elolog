-- v114 — Centro de Gestão de Tarifários (3/4): o motor de preços, fonte única de preços da Elolog.
-- Ordem: 1 serviço · 2 modalidade · 3 origem e destino · 4 prestador · 5 tarifas ativas e válidas · 6 tarifa específica
--        · 7 suplementos autorizados · 8 comissão Elolog · 9 preço final.
-- Comissão «incluida» (o modelo de sempre): o cliente paga o preço do prestador + suplementos e a comissão é retida a esse valor.
-- Comissão «separada»: o cliente vê e paga a taxa de serviço Elolog à parte, em cima do preço do prestador.

alter table public.simulacoes add column if not exists preco_detalhe jsonb;
alter table public.propostas  add column if not exists preco_detalhe jsonb;
alter table public.encomendas add column if not exists preco_detalhe jsonb;

-- quanto «mede» o pedido na modalidade da tarifa (mesma fórmula de sempre: peso usa o volumétrico; o resto, volume)
create or replace function private.tarifa_medida(p_metodo metodo_cobranca, p_regras jsonb, q int, peso numeric, vol numeric)
returns numeric language sql immutable set search_path = public as $$
  select case p_metodo when 'fixo' then 1
    when 'peso' then greatest(coalesce(peso, 0), coalesce(vol, 0) * coalesce(nullif((p_regras ->> 'volumetricFactor')::numeric, 0), 167))
    when 'unidade' then coalesce(q, 0)::numeric else coalesce(vol, 0) end $$;

-- compatível: o pedido tem a medida que a modalidade precisa e está dentro dos limites da tarifa
create or replace function private.tarifa_compativel(p_metodo metodo_cobranca, p_regras jsonb, p_min numeric, p_max numeric, q int, peso numeric, vol numeric)
returns boolean language sql immutable set search_path = public as $$
  select m > 0 and (p_min is null or m >= p_min) and (p_max is null or m <= p_max)
    from (select private.tarifa_medida(p_metodo, p_regras, q, peso, vol) m) x $$;

create or replace function private.tarifa_preco(p_metodo metodo_cobranca, p_valor numeric, p_min numeric, p_max numeric, p_regras jsonb, q int, peso numeric, vol numeric)
returns numeric language sql immutable set search_path = public as $$
  select round(least(greatest(case p_metodo when 'fixo' then p_valor else private.tarifa_medida(p_metodo, p_regras, q, peso, vol) * p_valor end, coalesce(p_min, 0)),
                     coalesce(p_max, 'infinity'::numeric)), 2) $$;

create or replace function private.rota_bate(p_regra text, p_pedido text) returns boolean language sql stable set search_path = public, extensions as $$
  select coalesce(p_regra, '') = '' or strpos(private.norm(p_pedido), private.norm(p_regra)) > 0 or strpos(private.norm(p_regra), private.norm(p_pedido)) > 0 $$;

-- 5 e 6: a tarifa APROVADA, válida e compatível mais específica do prestador
create or replace function private.tarifa_escolhida(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric)
returns public.tarifas language sql stable security definer set search_path = public, extensions as $$
  select t.* from tarifas t
   where t.empresa_id = p_empresa and t.estado = 'aprovada' and t.aplicacao = 'carga'
     and (t.validade_inicio is null or t.validade_inicio <= current_date) and (t.validade_fim is null or t.validade_fim >= current_date)
     and private.rota_bate(t.origem, p_origem) and private.rota_bate(t.destino, p_destino)
     and (coalesce(t.transporte, '') = '' or coalesce(p_servico, '') = '' or private.norm(t.transporte) = private.norm(p_servico))
     and (coalesce(t.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = '' or strpos(private.norm(p_tipo_carga), private.norm(t.tipo_carga)) > 0)
     and private.tarifa_compativel(t.metodo, t.regras, t.limite_min, t.limite_max, q, peso, vol)
   order by ((coalesce(t.origem, '') <> '')::int + (coalesce(t.destino, '') <> '')::int + (coalesce(t.tipo_carga, '') <> '')::int + (coalesce(t.transporte, '') <> '')::int) desc,
            t.versao desc, t.created_at desc limit 1 $$;

-- 5 e 6 (alternativa): tarifário comercial geral da Elolog associado a este prestador
create or replace function private.tarifa_geral_escolhida(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric)
returns public.tarifas_gerais language sql stable security definer set search_path = public, extensions as $$
  select g.* from tarifas_gerais g
   where g.uso = 'comercial' and g.estado = 'ativa' and p_empresa = any (g.prestadores)
     and (g.validade_inicio is null or g.validade_inicio <= current_date) and (g.validade_fim is null or g.validade_fim >= current_date)
     and private.rota_bate(g.origem, p_origem) and private.rota_bate(g.destino, p_destino)
     and (coalesce(g.servico, '') = '' or coalesce(p_servico, '') = '' or private.norm(g.servico) = private.norm(p_servico))
     and (coalesce(g.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = '' or strpos(private.norm(p_tipo_carga), private.norm(g.tipo_carga)) > 0)
     and private.tarifa_compativel(g.metodo, g.regras, g.limite_min, g.limite_max, q, peso, vol)
   order by ((coalesce(g.origem, '') <> '')::int + (coalesce(g.destino, '') <> '')::int + (coalesce(g.tipo_carga, '') <> '')::int) desc, g.versao desc limit 1 $$;

-- 7: suplementos aprovados e válidos (o do prestador vale mais do que o geral da mesma chave); recolha: por km pedido
create or replace function private.suplementos_calc(p_empresa uuid, p_servico text, p_tipo_carga text, p_km numeric, p_base numeric)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare r record; itens jsonb := '[]'; total numeric := 0; m numeric; tem_recolha boolean := false;
begin
  for r in select distinct on (s.chave, case when s.chave = 'outro' then s.id end) s.* from tarifa_suplementos s
            where s.estado = 'aprovado' and (s.empresa_id = p_empresa or s.empresa_id is null)
              and (s.validade_inicio is null or s.validade_inicio <= current_date) and (s.validade_fim is null or s.validade_fim >= current_date)
              and (coalesce(s.servico, '') = '' or coalesce(p_servico, '') = '' or private.norm(s.servico) = private.norm(p_servico))
              and (coalesce(s.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = '' or strpos(private.norm(p_tipo_carga), private.norm(s.tipo_carga)) > 0)
            order by s.chave, case when s.chave = 'outro' then s.id end, (s.empresa_id is null), s.updated_at desc loop
    if r.chave = 'recolha_km' then
      if coalesce(p_km, 0) <= 0 then continue; end if; tem_recolha := true;
    elsif not r.automatico then continue; end if;
    m := round(case r.tipo when 'fixo' then r.valor when 'percentual' then p_base * r.valor / 100 else coalesce(p_km, 0) * r.valor end, 2);
    total := total + m;
    itens := itens || jsonb_build_object('id', r.id, 'nome', r.nome, 'chave', r.chave, 'tipo', r.tipo, 'valor', r.valor, 'montante', m, 'origem', case when r.empresa_id is null then 'elolog' else 'prestador' end);
  end loop;
  if coalesce(p_km, 0) > 0 and not tem_recolha then   -- sem suplemento configurado: o custo por km de sempre
    m := round(p_km * private.custo_recolha_por_km(), 2); total := total + m;
    itens := itens || jsonb_build_object('nome', 'Recolha na morada', 'chave', 'recolha_km', 'tipo', 'por_km', 'valor', private.custo_recolha_por_km(), 'montante', m, 'origem', 'elolog');
  end if;
  return jsonb_build_object('total', total, 'itens', itens);
end $$;

-- 8: a regra de comissão ativa mais específica (prestador, modalidade, rota), dentro do período
create or replace function private.comissao_escolhida(p_empresa uuid, p_metodo metodo_cobranca, p_origem text, p_destino text)
returns public.regras_comissao language sql stable security definer set search_path = public, extensions as $$
  select c.* from regras_comissao c
   where c.ativa and (c.inicio is null or c.inicio <= current_date) and (c.fim is null or c.fim >= current_date)
     and (c.empresa_id is null or c.empresa_id = p_empresa) and (c.metodo is null or p_metodo is null or c.metodo = p_metodo)
     and private.rota_bate(c.rota_origem, p_origem) and private.rota_bate(c.rota_destino, p_destino)
   order by ((c.empresa_id is not null)::int + (c.metodo is not null)::int + (coalesce(c.rota_origem, '') <> '')::int + (coalesce(c.rota_destino, '') <> '')::int) desc,
            c.promocional desc, c.prioridade desc, c.updated_at desc limit 1 $$;

create or replace function private.comissao_valor(c public.regras_comissao, p_base numeric) returns numeric language sql immutable as $$
  select case when c.id is null then 0 when c.tipo_valor = 'percentagem' then round(p_base * c.valor / 100, 2) else round(c.valor, 2) end $$;

-- o motor: devolve o preço e o caminho que fez (para a administração) e a cópia a guardar quando for aprovado
create or replace function private.motor_preco(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric, km numeric)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare t tarifas; g tarifas_gerais; c regras_comissao; base numeric; sup jsonb; com numeric; ap text; met metodo_cobranca; tj jsonb; orig text; moeda text;
begin
  t := private.tarifa_escolhida(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol);
  if t.id is not null then
    met := t.metodo; orig := 'prestador'; moeda := t.moeda;
    base := private.tarifa_preco(t.metodo, t.valor, t.preco_minimo, t.preco_maximo, t.regras, q, peso, vol);
    tj := jsonb_build_object('id', t.id, 'nome', t.nome, 'versao', t.versao, 'metodo', t.metodo, 'valor', t.valor, 'moeda', t.moeda, 'preco_minimo', t.preco_minimo,
          'preco_maximo', t.preco_maximo, 'limite_min', t.limite_min, 'limite_max', t.limite_max, 'regras', t.regras, 'validade_inicio', t.validade_inicio, 'validade_fim', t.validade_fim, 'notas', t.notas);
  else
    g := private.tarifa_geral_escolhida(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol);
    if g.id is null then
      return jsonb_build_object('disponivel', false, 'mensagem', 'Não existe uma tarifa automática disponível. Solicite uma cotação personalizada.');
    end if;
    met := g.metodo; orig := 'geral'; moeda := g.moeda;
    base := private.tarifa_preco(g.metodo, g.valor, g.preco_minimo, g.preco_maximo, g.regras, q, peso, vol);
    tj := jsonb_build_object('id', g.id, 'codigo', g.codigo, 'nome', g.nome, 'versao', g.versao, 'metodo', g.metodo, 'valor', g.valor, 'moeda', g.moeda, 'preco_minimo', g.preco_minimo,
          'preco_maximo', g.preco_maximo, 'limite_min', g.limite_min, 'limite_max', g.limite_max, 'regras', g.regras, 'validade_inicio', g.validade_inicio, 'validade_fim', g.validade_fim, 'condicoes', g.condicoes);
  end if;
  sup := private.suplementos_calc(p_empresa, p_servico, p_tipo_carga, km, base);
  c := private.comissao_escolhida(p_empresa, met, p_origem, p_destino);
  com := private.comissao_valor(c, base + (sup ->> 'total')::numeric); ap := coalesce(c.apresentacao, 'incluida');
  return jsonb_build_object('disponivel', true, 'origem_tarifa', orig, 'tarifa_id', case when orig = 'prestador' then t.id end, 'tarifa', tj, 'moeda', moeda,
    'pedido', jsonb_build_object('servico', p_servico, 'origem', p_origem, 'destino', p_destino, 'tipo_carga', p_tipo_carga, 'quantidade', q, 'peso_kg', peso, 'volume_m3', vol, 'recolha_km', km,
                                 'medida', private.tarifa_medida(met, tj -> 'regras', q, peso, vol)),
    'preco_prestador', base, 'suplementos', sup -> 'itens', 'suplementos_total', (sup ->> 'total')::numeric,
    'comissao', com, 'apresentacao', ap,
    'comissao_regra', case when c.id is null then null else jsonb_build_object('id', c.id, 'nome', c.nome, 'tipo_valor', c.tipo_valor, 'valor', c.valor, 'promocional', c.promocional) end,
    'preco_final', base + (sup ->> 'total')::numeric + case when ap = 'separada' then com else 0 end,
    'liquido_prestador', base + (sup ->> 'total')::numeric - case when ap = 'incluida' then com else 0 end, 'calculado_em', now());
end $$;
revoke all on function private.motor_preco(uuid, text, text, text, text, int, numeric, numeric, numeric) from public, anon, authenticated;

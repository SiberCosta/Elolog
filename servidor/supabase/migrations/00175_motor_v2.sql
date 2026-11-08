-- v115 — o motor de preços com a descrição da carga e os veículos (continua a ser a fonte única de preços).
-- private.motor_preco (assinatura antiga) passa a chamar private.motor_preco_d sem descrição: o resultado não muda.

create or replace function private.motor_preco_d(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric, km numeric, p_descricao text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare t tarifas; g tarifas_gerais; c regras_comissao; base numeric; sup jsonb; com numeric; ap text; met metodo_cobranca; tj jsonb; orig text; moeda text; achou boolean := false;
begin
  t := private.tarifa_escolhida_d(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol, p_descricao);
  if t.id is not null then
    met := t.metodo; orig := 'prestador'; moeda := t.moeda; achou := private.descricao_bate(p_descricao, t.nome, t.regras);
    base := private.tarifa_preco(t.metodo, t.valor, t.preco_minimo, t.preco_maximo, t.regras, q, peso, vol);
    tj := jsonb_build_object('id', t.id, 'nome', t.nome, 'versao', t.versao, 'metodo', t.metodo, 'valor', t.valor, 'moeda', t.moeda, 'preco_minimo', t.preco_minimo,
          'preco_maximo', t.preco_maximo, 'limite_min', t.limite_min, 'limite_max', t.limite_max, 'regras', t.regras, 'validade_inicio', t.validade_inicio, 'validade_fim', t.validade_fim, 'notas', t.notas);
  else
    g := private.tarifa_geral_escolhida_d(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol, p_descricao);
    if g.id is null then
      return jsonb_build_object('disponivel', false, 'mensagem', 'Não existe uma tarifa automática disponível. Solicite uma cotação personalizada.');
    end if;
    met := g.metodo; orig := 'geral'; moeda := g.moeda; achou := private.descricao_bate(p_descricao, g.nome, g.regras);
    base := private.tarifa_preco(g.metodo, g.valor, g.preco_minimo, g.preco_maximo, g.regras, q, peso, vol);
    tj := jsonb_build_object('id', g.id, 'codigo', g.codigo, 'nome', g.nome, 'versao', g.versao, 'metodo', g.metodo, 'valor', g.valor, 'moeda', g.moeda, 'preco_minimo', g.preco_minimo,
          'preco_maximo', g.preco_maximo, 'limite_min', g.limite_min, 'limite_max', g.limite_max, 'regras', g.regras, 'validade_inicio', g.validade_inicio, 'validade_fim', g.validade_fim, 'condicoes', g.condicoes);
  end if;
  sup := private.suplementos_calc_d(p_empresa, p_servico, p_tipo_carga, km, base, peso, vol);
  c := private.comissao_escolhida(p_empresa, met, p_origem, p_destino);
  com := private.comissao_valor(c, base + (sup ->> 'total')::numeric); ap := coalesce(c.apresentacao, 'incluida');
  return jsonb_build_object('disponivel', true, 'origem_tarifa', orig, 'tarifa_id', case when orig = 'prestador' then t.id end, 'tarifa', tj, 'moeda', moeda,
    'pela_descricao', achou,
    'pedido', jsonb_build_object('servico', p_servico, 'origem', p_origem, 'destino', p_destino, 'tipo_carga', p_tipo_carga, 'descricao', p_descricao, 'quantidade', q, 'peso_kg', peso,
                                 'volume_m3', vol, 'recolha_km', km, 'medida', private.tarifa_medida(met, tj -> 'regras', q, peso, vol)),
    'preco_prestador', base, 'suplementos', sup -> 'itens', 'suplementos_total', (sup ->> 'total')::numeric,
    'comissao', com, 'apresentacao', ap,
    'comissao_regra', case when c.id is null then null else jsonb_build_object('id', c.id, 'nome', c.nome, 'tipo_valor', c.tipo_valor, 'valor', c.valor, 'promocional', c.promocional) end,
    'preco_final', base + (sup ->> 'total')::numeric + case when ap = 'separada' then com else 0 end,
    'liquido_prestador', base + (sup ->> 'total')::numeric - case when ap = 'incluida' then com else 0 end, 'calculado_em', now());
end $$;
revoke all on function private.motor_preco_d(uuid, text, text, text, text, int, numeric, numeric, numeric, text) from public, anon, authenticated;

create or replace function private.motor_preco(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric, km numeric)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select private.motor_preco_d(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol, km, null) $$;

-- simulador do cliente: igual a calcular_precos, com a descrição da carga (o cliente só recebe o preço final)
create or replace function public.precos_automaticos(p_origem text, p_destino text, p_tipo_carga text default null, p_quantidade int default 0, p_peso_kg numeric default 0,
  p_volume_m3 numeric default 0, p_recolha_km numeric default 0, p_servico text default null, p_descricao text default null)
returns table (prestador_id uuid, prestador_nome text, disponivel boolean, preco_final numeric, taxa_servico numeric, moeda char(3), mensagem text)
language plpgsql stable security definer set search_path = public as $$
declare r record; m jsonb;
begin
  if not exists (select 1 from clientes c where c.id = auth.uid()) and not private.e_admin_plataforma() then raise exception 'Apenas clientes autenticados.'; end if;
  if coalesce(trim(p_origem), '') = '' or coalesce(trim(p_destino), '') = '' then raise exception 'Indique origem e destino.'; end if;
  if least(coalesce(p_quantidade, 0), coalesce(p_peso_kg, 0), coalesce(p_volume_m3, 0), coalesce(p_recolha_km, 0)) < 0 then raise exception 'Valores negativos não são permitidos.'; end if;
  if length(coalesce(p_descricao, '')) > 1000 then raise exception 'A descrição é demasiado longa.'; end if;
  for r in select e.id, e.nome from empresas_disponiveis e order by e.nome loop
    m := private.motor_preco_d(r.id, p_servico, p_origem, p_destino, p_tipo_carga, p_quantidade, p_peso_kg, p_volume_m3, p_recolha_km, p_descricao);
    prestador_id := r.id; prestador_nome := r.nome; disponivel := (m ->> 'disponivel')::boolean;
    preco_final := (m ->> 'preco_final')::numeric; moeda := m ->> 'moeda'; mensagem := m ->> 'mensagem';
    taxa_servico := case when m ->> 'apresentacao' = 'separada' then (m ->> 'comissao')::numeric end;
    return next;
  end loop;
end $$;
revoke all on function public.precos_automaticos(text, text, text, int, numeric, numeric, numeric, text, text) from public, anon;
grant execute on function public.precos_automaticos(text, text, text, int, numeric, numeric, numeric, text, text) to authenticated;

-- simulador de preços do centro: a administração testa qualquer prestador; o prestador (administrador ou financeiro) só a sua empresa
create or replace function public.simular_preco(p_empresa uuid, p_origem text, p_destino text, p_tipo_carga text default null, p_quantidade int default 0, p_peso_kg numeric default 0,
  p_volume_m3 numeric default 0, p_recolha_km numeric default 0, p_servico text default null, p_descricao text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid := p_empresa;
begin
  if not private.e_admin_plataforma() then
    if private.minha_empresa() is null or not private.papel_em(array['admin_empresa','financeiro']) then
      raise exception 'Só a administração Elolog ou o financeiro da empresa podem simular preços.' using errcode = '42501'; end if;
    v_emp := private.minha_empresa();
  end if;
  if v_emp is null then raise exception 'Escolha o prestador.'; end if;
  if least(coalesce(p_quantidade, 0), coalesce(p_peso_kg, 0), coalesce(p_volume_m3, 0), coalesce(p_recolha_km, 0)) < 0 then raise exception 'Valores negativos não são permitidos.'; end if;
  return private.motor_preco_d(v_emp, p_servico, p_origem, p_destino, p_tipo_carga, p_quantidade, p_peso_kg, p_volume_m3, p_recolha_km, p_descricao);
end $$;
revoke all on function public.simular_preco(uuid, text, text, text, int, numeric, numeric, numeric, text, text) from public, anon;
grant execute on function public.simular_preco(uuid, text, text, text, int, numeric, numeric, numeric, text, text) to authenticated;

-- o envio ao prestador usa a descrição guardada na simulação (mesmo preço que o cliente viu)
do $$ declare d text := pg_get_functiondef('public.enviar_simulacao(uuid, uuid)'::regprocedure); n text; begin
  n := replace(d, 'm := private.motor_preco(p_empresa, null, v_sim.origem, v_sim.destino, v_sim.tipo_carga, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3,
                           case when v_sim.recolha_na_morada then coalesce(v_sim.recolha_distancia_km, 0) else 0 end);',
                  'm := private.motor_preco_d(p_empresa, null, v_sim.origem, v_sim.destino, v_sim.tipo_carga, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3,
                           case when v_sim.recolha_na_morada then coalesce(v_sim.recolha_distancia_km, 0) else 0 end, v_sim.descricao);');
  if n = d then raise exception 'enviar_simulacao: não encontrei a chamada ao motor para atualizar.'; end if;
  execute n;
end $$;

-- v115 — Regras de cobrança (2/2): o motor de preços passa a procurar pela DESCRIÇÃO da carga e a usar as tarifas de veículos.
-- Motor de busca: quando a descrição do pedido contém o nome de uma tarifa (ou uma das suas palavras-chave), essa tarifa ganha.
--   Ex.: tarifa «Frigorífico» (por unidade) e descrição «2 frigoríficos combinados» → usa a tarifa «Frigorífico».
--   Uma tarifa marcada «só pela descrição» (regras.so_descricao) só entra quando a descrição coincide.
-- Recolha: com km pedidos, usa a tarifa de veículo aprovada mais barata que leva o peso e o volume (do prestador; senão, a geral da Elolog);
--   sem tarifa de veículo, fica tudo como antes (suplemento de recolha ou 1 € por km).
-- As funções antigas continuam (mesmas assinaturas) e passam pelo motor novo, sem descrição: o resultado é o de sempre.

-- palavras da descrição comparadas por início de palavra, sem acentos nem maiúsculas (aceita plurais: «frigorífico» ↔ «frigoríficos»)
create or replace function private.descricao_bate(p_desc text, p_nome text, p_regras jsonb) returns boolean
language sql stable set search_path = public, extensions as $$
  select coalesce(trim(p_desc), '') <> '' and exists (
    select 1 from (select p_nome as w union all
                   select jsonb_array_elements_text(case when jsonb_typeof(p_regras -> 'palavras') = 'array' then p_regras -> 'palavras' else '[]'::jsonb end)) x,
                  lateral (select trim(regexp_replace(private.norm(x.w), '[^a-z0-9]+', ' ', 'g')) as p) n
     where length(n.p) >= 3
       and strpos(' ' || regexp_replace(private.norm(p_desc), '[^a-z0-9]+', ' ', 'g') || ' ', ' ' || n.p) > 0) $$;

create or replace function private.tarifa_escolhida_d(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric, p_descricao text)
returns public.tarifas language sql stable security definer set search_path = public, extensions as $$
  select t.* from tarifas t
   where t.empresa_id = p_empresa and t.estado = 'aprovada' and t.aplicacao = 'carga'
     and (t.validade_inicio is null or t.validade_inicio <= current_date) and (t.validade_fim is null or t.validade_fim >= current_date)
     and private.rota_bate(t.origem, p_origem) and private.rota_bate(t.destino, p_destino)
     and (coalesce(t.transporte, '') = '' or coalesce(p_servico, '') = '' or private.norm(t.transporte) = private.norm(p_servico))
     and (coalesce(t.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = '' or strpos(private.norm(p_tipo_carga), private.norm(t.tipo_carga)) > 0)
     and (coalesce(t.regras ->> 'so_descricao', '') <> 'true' or private.descricao_bate(p_descricao, t.nome, t.regras))
     and private.tarifa_compativel(t.metodo, t.regras, t.limite_min, t.limite_max, q, peso, vol)
   order by private.descricao_bate(p_descricao, t.nome, t.regras) desc,
            ((coalesce(t.origem, '') <> '')::int + (coalesce(t.destino, '') <> '')::int + (coalesce(t.tipo_carga, '') <> '')::int + (coalesce(t.transporte, '') <> '')::int) desc,
            t.versao desc, t.created_at desc limit 1 $$;
create or replace function private.tarifa_escolhida(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric)
returns public.tarifas language sql stable security definer set search_path = public, extensions as $$
  select * from private.tarifa_escolhida_d(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol, null) $$;

create or replace function private.tarifa_geral_escolhida_d(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric, p_descricao text)
returns public.tarifas_gerais language sql stable security definer set search_path = public, extensions as $$
  select g.* from tarifas_gerais g
   where g.uso = 'comercial' and g.estado = 'ativa' and p_empresa = any (g.prestadores)
     and (g.validade_inicio is null or g.validade_inicio <= current_date) and (g.validade_fim is null or g.validade_fim >= current_date)
     and private.rota_bate(g.origem, p_origem) and private.rota_bate(g.destino, p_destino)
     and (coalesce(g.servico, '') = '' or coalesce(p_servico, '') = '' or private.norm(g.servico) = private.norm(p_servico))
     and (coalesce(g.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = '' or strpos(private.norm(p_tipo_carga), private.norm(g.tipo_carga)) > 0)
     and (coalesce(g.regras ->> 'so_descricao', '') <> 'true' or private.descricao_bate(p_descricao, g.nome, g.regras))
     and private.tarifa_compativel(g.metodo, g.regras, g.limite_min, g.limite_max, q, peso, vol)
   order by private.descricao_bate(p_descricao, g.nome, g.regras) desc,
            ((coalesce(g.origem, '') <> '')::int + (coalesce(g.destino, '') <> '')::int + (coalesce(g.tipo_carga, '') <> '')::int) desc, g.versao desc limit 1 $$;
create or replace function private.tarifa_geral_escolhida(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric)
returns public.tarifas_gerais language sql stable security definer set search_path = public, extensions as $$
  select * from private.tarifa_geral_escolhida_d(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol, null) $$;

-- o veículo aprovado mais barato que leva a carga (primeiro os do prestador, depois os gerais da Elolog)
create or replace function private.veiculo_escolhido(p_empresa uuid, p_servico text, peso numeric, vol numeric, km numeric) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('id', v.id, 'nome', v.nome, 'chave', 'recolha_km', 'tipo', 'veiculo', 'veiculo', v.veiculo, 'valor', v.preco_km,
           'montante', round(greatest(v.preco_minimo, v.preco_saida + coalesce(km, 0) * v.preco_km), 2), 'origem', case when v.empresa_id is null then 'elolog' else 'prestador' end, 'versao', v.versao)
    from tarifas_veiculos v
   where v.estado = 'aprovado' and (v.empresa_id = p_empresa or v.empresa_id is null)
     and (v.validade_inicio is null or v.validade_inicio <= current_date) and (v.validade_fim is null or v.validade_fim >= current_date)
     and (coalesce(v.servico, '') = '' or coalesce(p_servico, '') = '' or private.norm(v.servico) = private.norm(p_servico))
     and (v.capacidade_kg is null or coalesce(peso, 0) <= v.capacidade_kg) and (v.capacidade_m3 is null or coalesce(vol, 0) <= v.capacidade_m3)
   order by (v.empresa_id is null), greatest(v.preco_minimo, v.preco_saida + coalesce(km, 0) * v.preco_km), v.updated_at desc limit 1 $$;

create or replace function private.suplementos_calc_d(p_empresa uuid, p_servico text, p_tipo_carga text, p_km numeric, p_base numeric, peso numeric, vol numeric)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare r record; itens jsonb := '[]'; total numeric := 0; m numeric; tem_recolha boolean := false; vei jsonb;
begin
  if coalesce(p_km, 0) > 0 then
    vei := private.veiculo_escolhido(p_empresa, p_servico, peso, vol, p_km);
    if vei is not null then tem_recolha := true; total := (vei ->> 'montante')::numeric; itens := jsonb_build_array(vei); end if;
  end if;
  for r in select distinct on (s.chave, case when s.chave = 'outro' then s.id end) s.* from tarifa_suplementos s
            where s.estado = 'aprovado' and (s.empresa_id = p_empresa or s.empresa_id is null)
              and (s.validade_inicio is null or s.validade_inicio <= current_date) and (s.validade_fim is null or s.validade_fim >= current_date)
              and (coalesce(s.servico, '') = '' or coalesce(p_servico, '') = '' or private.norm(s.servico) = private.norm(p_servico))
              and (coalesce(s.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = '' or strpos(private.norm(p_tipo_carga), private.norm(s.tipo_carga)) > 0)
            order by s.chave, case when s.chave = 'outro' then s.id end, (s.empresa_id is null), s.updated_at desc loop
    if r.chave = 'recolha_km' then
      if coalesce(p_km, 0) <= 0 or vei is not null then continue; end if; tem_recolha := true;
    elsif not r.automatico then continue; end if;
    m := round(case r.tipo when 'fixo' then r.valor when 'percentual' then p_base * r.valor / 100 else coalesce(p_km, 0) * r.valor end, 2);
    total := total + m;
    itens := itens || jsonb_build_object('id', r.id, 'nome', r.nome, 'chave', r.chave, 'tipo', r.tipo, 'valor', r.valor, 'montante', m, 'origem', case when r.empresa_id is null then 'elolog' else 'prestador' end);
  end loop;
  if coalesce(p_km, 0) > 0 and not tem_recolha then
    m := round(p_km * private.custo_recolha_por_km(), 2); total := total + m;
    itens := itens || jsonb_build_object('nome', 'Recolha na morada', 'chave', 'recolha_km', 'tipo', 'por_km', 'valor', private.custo_recolha_por_km(), 'montante', m, 'origem', 'elolog');
  end if;
  return jsonb_build_object('total', total, 'itens', itens);
end $$;
create or replace function private.suplementos_calc(p_empresa uuid, p_servico text, p_tipo_carga text, p_km numeric, p_base numeric)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select private.suplementos_calc_d(p_empresa, p_servico, p_tipo_carga, p_km, p_base, null, null) $$;

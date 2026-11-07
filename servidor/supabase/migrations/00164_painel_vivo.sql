-- v101 — «Painel ao vivo» do Centro de Controlo (administração). Só ACRESCENTA uma função de leitura:
-- não altera tabelas, dados, autenticação, permissões, fluxos de encomendas, comissões nem planos.
-- Tudo vem dos dados reais: comissões pela regra ativa (da empresa ou global) sobre pagamentos confirmados hoje,
-- planos pelos recibos pagos hoje, navios pelas encomendas expedidas (navio/viagem) e pela posição AIS quando existe.

create or replace function public.painel_vivo() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_hoje date := current_date; r jsonb;
  k_com numeric; k_planos numeric; k_media numeric; k_curso int; k_novas int; k_novas_ant int;
  k_prazo_n int; k_prazo_ok int; k_prazo_ant_n int; k_prazo_ant_ok int; k_risco numeric; k_risco_n int; k_atras int;
begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;

  -- receita da Elolog hoje: comissões (regra ativa da empresa, senão a global) sobre o recebido hoje + planos pagos hoje
  with pg as (select p.empresa_id, p.pago_em::date d, sum(case when p.tipo = 'reembolso' then -p.valor else p.valor end) v
                from pagamentos p where p.estado = 'pago' and p.pago_em >= v_hoje - 14 group by 1, 2),
       c as (select pg.d, case when rc.tipo_valor = 'percentagem' then pg.v * rc.valor / 100 when rc.tipo_valor = 'fixo' then rc.valor else 0 end com
               from pg left join lateral (select * from regras_comissao x where x.ativa and (x.empresa_id = pg.empresa_id or x.empresa_id is null)
                                          order by (x.empresa_id is null), x.updated_at desc limit 1) rc on true)
  select coalesce(sum(com) filter (where d = v_hoje), 0), coalesce(sum(com) filter (where d < v_hoje), 0) / 14 into k_com, k_media from c;
  select coalesce(sum(valor), 0) into k_planos from faturas_plataforma where tipo = 'recibo' and estado = 'paga' and emitida_em::date = v_hoje;
  k_media := k_media + coalesce((select sum(valor) from faturas_plataforma where tipo = 'recibo' and estado = 'paga'
                                  and emitida_em::date >= v_hoje - 14 and emitida_em::date < v_hoje), 0) / 14;

  select count(*) filter (where estado not in ('entregue', 'cancelada')),
         count(*) filter (where created_at >= now() - interval '30 days'),
         count(*) filter (where created_at >= now() - interval '60 days' and created_at < now() - interval '30 days'),
         count(*) filter (where estado not in ('entregue', 'cancelada') and coalesce(chegada_prevista, data_prevista) < v_hoje)
    into k_curso, k_novas, k_novas_ant, k_atras from encomendas;
  select count(*) filter (where en.entregue_em >= now() - interval '30 days'),
         count(*) filter (where en.entregue_em >= now() - interval '30 days' and en.entregue_em::date <= coalesce(e.chegada_prevista, e.data_prevista, en.entregue_em::date)),
         count(*) filter (where en.entregue_em >= now() - interval '60 days' and en.entregue_em < now() - interval '30 days'),
         count(*) filter (where en.entregue_em >= now() - interval '60 days' and en.entregue_em < now() - interval '30 days'
                          and en.entregue_em::date <= coalesce(e.chegada_prevista, e.data_prevista, en.entregue_em::date))
    into k_prazo_n, k_prazo_ok, k_prazo_ant_n, k_prazo_ant_ok
    from entregas en join encomendas e on e.id = en.encomenda_id and e.estado = 'entregue';
  select coalesce(sum(valor), 0), count(*) into k_risco, k_risco_n from pagamentos where estado in ('pendente', 'parcial') and tipo <> 'reembolso';

  r := jsonb_build_object('gerado_em', now(),
    'kpis', jsonb_build_object(
      'receita_hoje', round(k_com + k_planos, 2), 'comissoes_hoje', round(k_com, 2), 'planos_hoje', k_planos, 'receita_media_14d', round(k_media, 2),
      'em_curso', k_curso, 'novas_30d', k_novas, 'novas_30d_anteriores', k_novas_ant,
      'prazo_pct', case when k_prazo_n > 0 then round(k_prazo_ok * 100.0 / k_prazo_n, 1) end,
      'prazo_pct_anterior', case when k_prazo_ant_n > 0 then round(k_prazo_ant_ok * 100.0 / k_prazo_ant_n, 1) end,
      'risco_valor', k_risco, 'risco_pagamentos', k_risco_n, 'atrasadas', k_atras),

    -- viagens: encomendas expedidas ou em trânsito agrupadas por navio e viagem; posição AIS se o navio é seguido
    'viagens', coalesce((select jsonb_agg(v order by v->>'partida') from (
      select jsonb_build_object('navio', e.navio, 'viagem', e.viagem, 'origem', mode() within group (order by e.origem), 'destino', mode() within group (order by e.destino),
        'encomendas', count(*), 'codigos', jsonb_agg(e.codigo order by e.codigo), 'partida', min(e.partida_prevista), 'chegada', max(e.chegada_prevista),
        'em_transito', bool_or(e.estado = 'em_transito'), 'atrasada', bool_or(e.estado <> 'destino' and e.chegada_prevista < v_hoje),
        'prestadores', (select jsonb_agg(distinct coalesce(em.nome_comercial, em.nome)) from encomendas e2 join empresas em on em.id = e2.empresa_id
                         where e2.navio = e.navio and coalesce(e2.viagem, '') = coalesce(e.viagem, '') and e2.estado in ('expedicao', 'em_transito')),
        'ais', (select jsonb_build_object('lat', p.latitude, 'lon', p.longitude, 'nos', p.velocidade_nos, 'eta', p.eta, 'em', p.posicao_em)
                  from navios_posicoes p where lower(p.nome) = lower(e.navio) and p.latitude is not null order by p.posicao_em desc nulls last limit 1)) v
        from encomendas e where e.estado in ('expedicao', 'em_transito') and coalesce(e.navio, '') <> ''
       group by e.navio, e.viagem) x), '[]'::jsonb),

    -- encomendas por porto: antes de embarcar contam na origem, depois na chegada
    'portos', coalesce((select jsonb_agg(jsonb_build_object('cidade', cidade, 'n', n) order by n desc) from (
      select case when estado in ('em_transito', 'destino', 'disponivel') then destino else origem end cidade, count(*) n
        from encomendas where estado not in ('entregue', 'cancelada') group by 1) p where cidade is not null), '[]'::jsonb),

    'veiculos', coalesce((select jsonb_agg(jsonb_build_object('matricula', v.matricula, 'descricao', v.descricao, 'empresa', coalesce(em.nome_comercial, em.nome),
        'servicos_hoje', (select count(*) from trabalhos_terreno t where t.veiculo_id = v.id and t.data = v_hoje),
        'por_fazer', (select count(*) from trabalhos_terreno t where t.veiculo_id = v.id and t.data = v_hoje and t.estado::text <> 'concluida'))
        order by em.nome, v.matricula) from veiculos v join empresas em on em.id = v.empresa_id where v.ativo), '[]'::jsonb),

    'armazens', coalesce((select jsonb_agg(jsonb_build_object('nome', a.nome, 'morada', a.morada, 'empresa', coalesce(em.nome_comercial, em.nome),
        'encomendas', (select count(*) from recibos_armazem ra join encomendas e on e.id = ra.encomenda_id where ra.armazem_id = a.id and e.estado = 'armazenamento'),
        'volumes', (select coalesce(sum(ra.quantidade_recebida), 0) from recibos_armazem ra join encomendas e on e.id = ra.encomenda_id where ra.armazem_id = a.id and e.estado = 'armazenamento'))
        order by a.nome) from armazens a join empresas em on em.id = a.empresa_id where a.ativo), '[]'::jsonb),

    'recentes', coalesce((select jsonb_agg(x order by x->>'atualizada' desc) from (
      select jsonb_build_object('codigo', e.codigo, 'origem', e.origem, 'destino', e.destino, 'chegada', coalesce(e.chegada_prevista, e.data_prevista),
        'transporte', case when coalesce(e.navio, '') <> '' then e.navio || coalesce(' ' || e.viagem, '') end, 'prestador', coalesce(em.nome_comercial, em.nome),
        'cliente', coalesce(e.cliente_nome, c.nome), 'estado', e.estado, 'suspensa', e.suspensa,
        'atrasada', e.estado not in ('entregue', 'cancelada') and coalesce(e.chegada_prevista, e.data_prevista) < v_hoje,
        'pagamento_pendente', exists (select 1 from pagamentos p where p.encomenda_id = e.id and p.estado in ('pendente', 'parcial')), 'atualizada', e.updated_at) x
        from encomendas e join empresas em on em.id = e.empresa_id left join clientes c on c.id = e.cliente_id
       order by e.updated_at desc limit 20) t), '[]'::jsonb));
  return r;
end $$;
revoke all on function public.painel_vivo() from public, anon;
grant execute on function public.painel_vivo() to authenticated;

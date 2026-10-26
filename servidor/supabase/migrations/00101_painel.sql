-- =====================================================================
-- Elolog · 0010 · Indicadores reais do painel da administração (logística transitária)
-- Depende de 0001–0009.
-- Uma só chamada devolve tudo o que o painel mostra, calculado na base de dados (só leitura):
--   prestadores, subscrições e receita, clientes, funil comercial (simulação → proposta → encomenda → entrega),
--   pipeline logístico por estado da encomenda, alertas, rotas mais pedidas, prestadores mais ativos,
--   evolução semanal e atividade recente.
-- Só a administração da plataforma a pode executar. Não devolve dados pessoais (nomes de clientes, moradas, e-mails).
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- =====================================================================
create function public.painel_administracao(p_dias int default 30)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini timestamptz;
  v_res jsonb;
begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;
  if p_dias is null or p_dias not in (7, 14, 30, 60, 90, 180) then raise exception 'Período inválido: use 7, 30 ou 90 dias (ou o dobro, para comparar com o período anterior).'; end if;
  v_ini := now() - make_interval(days => p_dias);

  select jsonb_build_object(
    'gerado_em', now(),
    'periodo_dias', p_dias,

    'prestadores', (select jsonb_build_object(
        'ativos',              count(*) filter (where estado = 'aprovada'),
        'pendentes',           count(*) filter (where estado = 'pendente'),
        'suspensos',           count(*) filter (where estado = 'suspensa'),
        'recusados',           count(*) filter (where estado = 'rejeitada'),
        'pendentes_mais_48h',  count(*) filter (where estado = 'pendente' and created_at < now() - interval '48 hours'),
        'novos_periodo',       count(*) filter (where created_at >= v_ini))
      from empresas),

    -- receita recorrente mensal: subscrições ativas (as anuais a 1/12)
    'subscricoes', (select jsonb_build_object(
        'mrr',                     coalesce(sum(case when periodicidade = 'anual' then valor / 12 else valor end) filter (where estado = 'ativa'), 0),
        'ativas',                  count(*) filter (where estado = 'ativa'),
        'pagamentos_por_confirmar', count(*) filter (where estado = 'pendente' and pago_em is null),
        'valor_por_confirmar',     coalesce(sum(valor) filter (where estado = 'pendente' and pago_em is null), 0))
      from subscricoes),

    -- recibos internos emitidos ao confirmar pagamentos
    'receita', (select jsonb_build_object(
        'periodo', coalesce(sum(valor) filter (where tipo = 'recibo' and estado = 'paga' and emitida_em >= v_ini), 0),
        'mes',     coalesce(sum(valor) filter (where tipo = 'recibo' and estado = 'paga' and emitida_em >= date_trunc('month', now())), 0))
      from faturas_plataforma),

    'clientes', (select jsonb_build_object('total', count(*), 'novos_periodo', count(*) filter (where created_at >= v_ini)) from clientes),

    'funil', jsonb_build_object(
        'simulacoes', (select count(*) from simulacoes where estado <> 'rascunho' and enviada_em >= v_ini),
        'propostas',  (select count(*) from propostas where created_at >= v_ini),
        'aceites',    (select count(*) from propostas where estado = 'aceite' and created_at >= v_ini),
        'encomendas', (select count(*) from encomendas where created_at >= v_ini),
        'entregues',  (select count(*) from encomendas where estado = 'entregue' and created_at >= v_ini)),

    -- todos os estados aparecem, mesmo a zero (a ordem do fluxo é a do enum)
    'pipeline', (select jsonb_object_agg(e::text, coalesce(c.n, 0))
                   from unnest(enum_range(null::estado_encomenda)) e
                   left join (select estado, count(*) as n from encomendas group by estado) c on c.estado = e),

    'encomendas', (select jsonb_build_object(
        'em_curso',            count(*) filter (where estado not in ('entregue', 'cancelada')),
        'valor_em_curso',      coalesce(sum(preco_total) filter (where estado not in ('entregue', 'cancelada')), 0),
        'valor_periodo',       coalesce(sum(preco_total) filter (where created_at >= v_ini and estado <> 'cancelada'), 0),
        'paradas_mais_7d',     count(*) filter (where estado not in ('entregue', 'cancelada') and updated_at < now() - interval '7 days'),
        'canceladas_periodo',  count(*) filter (where estado = 'cancelada' and created_at >= v_ini))
      from encomendas),

    'rotas', coalesce((select jsonb_agg(r) from (
        select origem, destino, count(*) as pedidos, round(avg(preco_estimado), 2) as preco_medio
          from simulacoes where estado <> 'rascunho' and enviada_em >= v_ini
         group by origem, destino order by count(*) desc, origem, destino limit 5) r), '[]'::jsonb),

    'top_prestadores', coalesce((select jsonb_agg(t) from (
        select e.nome, count(*) as encomendas, coalesce(sum(o.preco_total), 0) as valor
          from encomendas o join empresas e on e.id = o.empresa_id
         where o.created_at >= v_ini and o.estado <> 'cancelada'
         group by e.nome order by count(*) desc, e.nome limit 5) t), '[]'::jsonb),

    -- últimas 8 semanas (segunda a domingo), incluindo a corrente
    'serie_semanal', (select jsonb_agg(s order by s.semana) from (
        select to_char(w, 'YYYY-MM-DD') as semana,
               (select count(*) from encomendas o where o.created_at >= w and o.created_at < w + interval '7 days') as encomendas,
               (select coalesce(sum(o.preco_total), 0) from encomendas o
                 where o.created_at >= w and o.created_at < w + interval '7 days' and o.estado <> 'cancelada') as valor
          from generate_series(date_trunc('week', now()) - interval '7 weeks', date_trunc('week', now()), interval '1 week') w) s),

    'apoio', (select jsonb_build_object('abertos', count(*) filter (where estado <> 'resolvido'),
                                        'escalados', count(*) filter (where estado = 'escalado')) from tickets),

    -- sem motivos nem dados pessoais: só o tipo de ação, quem agiu (papel), a empresa e quando
    'atividade', coalesce((select jsonb_agg(a) from (
        select au.acao, au.papel, e.nome as empresa, au.created_at
          from auditoria au left join empresas e on e.id = au.empresa_id
         order by au.created_at desc limit 8) a), '[]'::jsonb)
  ) into v_res;

  return v_res;
end $$;

revoke execute on function public.painel_administracao(int) from public, anon;
grant  execute on function public.painel_administracao(int) to authenticated;

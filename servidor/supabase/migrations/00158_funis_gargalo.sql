-- v94 — Três funis (clientes, prestadores, financeiro) e o indicador «Gargalo principal» no Centro de comando.
-- Só ACRESCENTA uma função de leitura (só administração). Não altera tabelas, dados nem ligações Supabase.
-- Regras obrigatórias (só se conta o que existe de facto na base de dados):
--  1. Só contam propostas de prestadores APROVADOS — nunca se mostram propostas fictícias.
--  2. Só há aceite se houver proposta válida (enviada/aceite, de prestador aprovado).
--  3. Só há valor contratado com proposta ACEITE (encomendas sem proposta aceite ficam fora do funil).
--  4. Só há valor faturado com fatura VÁLIDA registada.
--  5. Só há valor recebido com pagamento CONFIRMADO (estado «pago», menos reembolsos).
--  6. Planos (subscrições) e comissões das encomendas são contabilizados em separado.

create or replace function public.painel_funis(p_dias integer default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini timestamptz; r jsonb; a_sim uuid[]; a_prop uuid[]; a_aceite uuid[]; a_enc uuid[];
  -- clientes
  c_sim int; c_prop int; c_aceite int; c_enc int; c_entregue int; c_sem_prop int; c_expiradas int; c_recusadas int;
  -- prestadores
  p_registos int; p_pagos int; p_aprovados int; p_disponiveis int; p_com_prop int; p_com_enc int; p_pend48 int; p_pend int;
  -- financeiro
  f_sim numeric; f_prop numeric; f_aceite numeric; f_fat numeric; f_rec numeric; f_com numeric; f_sem_regra int;
  pl_recebido numeric; pl_por_confirmar numeric; pl_ativos int; pl_mrr numeric;
  g jsonb; taxa numeric; melhor numeric := 2; e record;
begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;
  if p_dias is null or p_dias not in (7, 14, 30, 60, 90, 180, 365) then raise exception 'Período inválido.'; end if;
  v_ini := now() - make_interval(days => p_dias);

  -- ---------- coorte: simulações enviadas no período, propostas válidas/aceites e encomendas com proposta aceite
  select coalesce(array_agg(s.id), '{}') into a_sim from simulacoes s
   where s.estado <> 'rascunho' and coalesce(s.enviada_em, s.created_at) >= v_ini;
  select coalesce(array_agg(p.id), '{}') into a_prop
    from propostas p join empresas em on em.id = p.empresa_id and em.estado = 'aprovada'            -- regra 1
   where p.simulacao_id = any(a_sim)
     and (p.estado = 'aceite' or (p.estado = 'enviada' and (p.validade is null or p.validade >= current_date)));   -- regra 2
  select coalesce(array_agg(p.id), '{}') into a_aceite from propostas p where p.id = any(a_prop) and p.estado = 'aceite';
  select coalesce(array_agg(o.id), '{}') into a_enc from encomendas o
   where o.proposta_id = any(a_aceite) and o.estado <> 'cancelada';                                                   -- regra 3

  select count(*) into c_sim from simulacoes where id = any(a_sim);
  select count(distinct simulacao_id) into c_prop from propostas where id = any(a_prop);
  select count(distinct simulacao_id) into c_aceite from propostas where id = any(a_aceite);
  select count(*) into c_enc from encomendas where id = any(a_enc);
  select count(*) into c_entregue from encomendas where id = any(a_enc) and estado = 'entregue';
  select count(*) into c_sem_prop from encomendas o where o.created_at >= v_ini and o.estado <> 'cancelada'
     and not exists (select 1 from propostas p where p.id = o.proposta_id and p.estado = 'aceite');
  select count(*) filter (where p.estado = 'enviada' and p.validade < current_date), count(*) filter (where p.estado = 'recusada')
    into c_expiradas, c_recusadas from propostas p where p.simulacao_id = any(a_sim);

  -- ---------- prestadores (estado atual + atividade no período)
  select count(*), count(*) filter (where estado = 'aprovada'), count(*) filter (where estado = 'pendente' and created_at < now() - interval '48 hours'),
         count(*) filter (where estado = 'pendente')
    into p_registos, p_aprovados, p_pend48, p_pend from empresas;
  select count(distinct empresa_id) into p_pagos from subscricoes where pago_em is not null or estado = 'ativa';
  select count(*) into p_disponiveis from empresas em where em.estado = 'aprovada'
     and exists (select 1 from subscricoes s where s.empresa_id = em.id and s.estado = 'ativa');
  select count(distinct empresa_id) into p_com_prop from propostas where id = any(a_prop);
  select count(distinct empresa_id) into p_com_enc from encomendas where id = any(a_enc);

  -- ---------- financeiro (coorte do período)
  select coalesce(sum(preco_estimado), 0) into f_sim from simulacoes where id = any(a_sim);
  select coalesce(sum(preco), 0) into f_prop from propostas where id = any(a_prop);
  select coalesce(sum(preco), 0) into f_aceite from propostas where id = any(a_aceite);
  select coalesce(sum(f.total), 0) into f_fat from faturas f where f.estado = 'valida' and f.encomenda_id = any(a_enc);   -- regra 4
  select coalesce(sum(case when pg.tipo = 'reembolso' then -pg.valor else pg.valor end), 0) into f_rec
    from pagamentos pg where pg.estado = 'pago' and pg.encomenda_id = any(a_enc);                                          -- regra 5
  -- comissões: regra ativa da empresa (ou a global) sobre o valor RECEBIDO de cada encomenda
  select coalesce(sum(case when rc.tipo_valor = 'percentagem' then x.recebido * rc.valor / 100 when rc.tipo_valor = 'fixo' then rc.valor else 0 end), 0),
         count(*) filter (where rc.id is null)
    into f_com, f_sem_regra
    from (select o.id, o.empresa_id, sum(case when pg.tipo = 'reembolso' then -pg.valor else pg.valor end) as recebido
            from encomendas o join pagamentos pg on pg.encomenda_id = o.id and pg.estado = 'pago' where o.id = any(a_enc) group by o.id, o.empresa_id having sum(pg.valor) > 0) x
    left join lateral (select * from regras_comissao c where c.ativa and (c.empresa_id = x.empresa_id or c.empresa_id is null)
                        order by (c.empresa_id is null), c.updated_at desc limit 1) rc on true;
  -- planos (regra 6: separados das comissões)
  select coalesce(sum(valor) filter (where tipo = 'recibo' and estado = 'paga' and emitida_em >= v_ini), 0) into pl_recebido from faturas_plataforma;
  select coalesce(sum(valor) filter (where estado = 'pendente' and pago_em is null), 0), count(*) filter (where estado = 'ativa'),
         coalesce(sum(case when periodicidade = 'anual' then valor / 12 else valor end) filter (where estado = 'ativa'), 0)
    into pl_por_confirmar, pl_ativos, pl_mrr from subscricoes;

  -- ---------- gargalo principal: a primeira condição que trava tudo; senão, a etapa com pior passagem
  if p_disponiveis = 0 then
    g := jsonb_build_object('funil', 'prestadores', 'etapa', 'disponiveis', 'titulo', 'Sem prestadores disponíveis',
      'mensagem', case when p_pend > 0 then p_pend || ' pedido(s) de inscrição à espera de validação. Sem prestadores aprovados com subscrição ativa não há propostas.'
                       else 'Não há prestadores aprovados com subscrição ativa: os clientes não recebem propostas.' end,
      'acao', 'Validar pedidos de inscrição', 'pagina', 'adminProviderRequests');
  elsif c_sim = 0 then
    g := jsonb_build_object('funil', 'clientes', 'etapa', 'simulacoes', 'titulo', 'Sem procura', 'mensagem', 'Não houve simulações no período.',
      'acao', 'Divulgar o simulador e a pesquisa marítima', 'pagina', 'dashboard');
  else
    for e in select * from (values
        ('clientes', 'propostas', 'Simulações sem proposta', c_prop::numeric, c_sim::numeric, 'Pedir aos prestadores que respondam às simulações', 'adminOperations'),
        ('clientes', 'aceites', 'Propostas não aceites', c_aceite::numeric, c_prop::numeric, 'Rever preços e prazos das propostas', 'adminOperations'),
        ('clientes', 'encomendas', 'Aceites sem encomenda', c_enc::numeric, c_aceite::numeric, 'Acompanhar a criação das encomendas', 'adminOperations'),
        ('financeiro', 'faturado', 'Valor contratado por faturar', f_fat, f_aceite, 'Pedir aos prestadores que registem as faturas', 'adminBilling'),
        ('financeiro', 'recebido', 'Faturado por receber', f_rec, f_fat, 'Confirmar pagamentos em falta', 'adminBilling')) t(funil, etapa, titulo, num, den, acao, pagina)
    loop
      if e.den > 0 then
        taxa := least(e.num / e.den, 1);
        if taxa < melhor then melhor := taxa;
          g := jsonb_build_object('funil', e.funil, 'etapa', e.etapa, 'titulo', e.titulo, 'taxa', round(taxa * 100),
            'mensagem', 'Só ' || round(taxa * 100) || ' % passam esta etapa.', 'acao', e.acao, 'pagina', e.pagina);
        end if;
      end if;
    end loop;
    if g is null then g := jsonb_build_object('funil', 'clientes', 'etapa', 'aceites', 'titulo', 'Sem gargalo', 'mensagem', 'O funil está a avançar sem bloqueios.', 'acao', '', 'pagina', 'dashboard'); end if;
  end if;

  r := jsonb_build_object('gerado_em', now(), 'periodo_dias', p_dias, 'gargalo', g,
    'clientes', jsonb_build_object('etapas', jsonb_build_array(
        jsonb_build_object('id', 'simulacoes', 'nome', 'Simulações', 'n', c_sim, 'pagina', 'adminOperations'),
        jsonb_build_object('id', 'propostas', 'nome', 'Com proposta válida', 'n', c_prop, 'pagina', 'adminOperations', 'extra', jsonb_build_object('expiradas', c_expiradas, 'recusadas', c_recusadas)),
        jsonb_build_object('id', 'aceites', 'nome', 'Aceites', 'n', c_aceite, 'pagina', 'adminOperations'),
        jsonb_build_object('id', 'encomendas', 'nome', 'Encomendas', 'n', c_enc, 'pagina', 'adminOperations', 'extra', jsonb_build_object('sem_proposta_aceite', c_sem_prop)),
        jsonb_build_object('id', 'entregues', 'nome', 'Entregues', 'n', c_entregue, 'pagina', 'adminOperations'))),
    'prestadores', jsonb_build_object('etapas', jsonb_build_array(
        jsonb_build_object('id', 'registos', 'nome', 'Registados', 'n', p_registos, 'pagina', 'adminProviderRequests', 'extra', jsonb_build_object('pendentes', p_pend, 'pendentes_48h', p_pend48)),
        jsonb_build_object('id', 'pagos', 'nome', 'Subscrição paga', 'n', p_pagos, 'pagina', 'adminPlans'),
        jsonb_build_object('id', 'aprovados', 'nome', 'Aprovados', 'n', p_aprovados, 'pagina', 'adminActiveProviders'),
        jsonb_build_object('id', 'disponiveis', 'nome', 'Disponíveis', 'n', p_disponiveis, 'pagina', 'adminActiveProviders'),
        jsonb_build_object('id', 'com_proposta', 'nome', 'Com propostas', 'n', p_com_prop, 'pagina', 'adminActiveProviders'),
        jsonb_build_object('id', 'com_encomenda', 'nome', 'Com encomendas', 'n', p_com_enc, 'pagina', 'adminActiveProviders'))),
    'financeiro', jsonb_build_object('etapas', jsonb_build_array(
        jsonb_build_object('id', 'simulado', 'nome', 'Valor simulado', 'v', f_sim, 'pagina', 'adminOperations'),
        jsonb_build_object('id', 'proposto', 'nome', 'Valor proposto', 'v', f_prop, 'pagina', 'adminOperations'),
        jsonb_build_object('id', 'contratado', 'nome', 'Valor contratado', 'v', f_aceite, 'pagina', 'adminOperations'),
        jsonb_build_object('id', 'faturado', 'nome', 'Valor faturado', 'v', f_fat, 'pagina', 'adminBilling'),
        jsonb_build_object('id', 'recebido', 'nome', 'Valor recebido', 'v', f_rec, 'pagina', 'adminBilling'),
        jsonb_build_object('id', 'comissoes', 'nome', 'Comissões Elolog', 'v', round(f_com, 2), 'pagina', 'adminCommissions', 'extra', jsonb_build_object('sem_regra', f_sem_regra))),
      'planos', jsonb_build_object('recebido', pl_recebido, 'por_confirmar', pl_por_confirmar, 'ativos', pl_ativos, 'mrr', round(pl_mrr, 2))),
    'resumo', jsonb_build_object('prestadores_disponiveis', p_disponiveis, 'simulacoes', c_sim,
      'conversao', case when c_sim > 0 then round(c_enc * 100.0 / c_sim) end, 'valor_contratado', f_aceite,
      'receita_comissoes', round(f_com, 2), 'receita_planos', pl_recebido));
  return r;
end $$;
revoke all on function public.painel_funis(integer) from public, anon;
grant execute on function public.painel_funis(integer) to authenticated;

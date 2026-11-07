-- v100 — Ficha da operação: tudo o que é preciso para trabalhar uma encomenda (resumo, percurso de 11 etapas, carga, financeiro,
-- histórico) e as próximas ações com os requisitos em falta. Só leitura; administração da plataforma ou a empresa da encomenda.

create or replace function public.encomenda_ficha(p_codigo text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e encomendas; adm boolean := private.e_admin_plataforma(); papel papel_funcionario := private.meu_papel(); r jsonb;
  pago numeric; comissao numeric; regra regras_comissao; ordem text[] := array['aprovacao','agendamento','recolha','armazenamento','expedicao','em_transito','destino','disponivel','entregue'];
begin
  select * into e from encomendas where codigo = upper(trim(p_codigo)) or id::text = trim(p_codigo);
  if not found then raise exception 'Encomenda não encontrada.'; end if;
  if not adm and private.minha_empresa() is distinct from e.empresa_id then raise exception 'Sem permissão para esta encomenda.'; end if;
  select coalesce(sum(case when tipo = 'reembolso' then -valor else valor end), 0) into pago from pagamentos where encomenda_id = e.id and estado = 'pago';
  select * into regra from regras_comissao c where c.ativa and (c.empresa_id = e.empresa_id or c.empresa_id is null) order by (c.empresa_id is null), c.updated_at desc limit 1;
  comissao := case when regra.id is null then null when regra.tipo_valor = 'percentagem' then round(e.preco_total * regra.valor / 100, 2) else regra.valor end;
  r := jsonb_build_object(
    'encomenda', to_jsonb(e) - 'pin_validacao_hash',
    'prestador', (select coalesce(nome_comercial, nome) from empresas where id = e.empresa_id),
    'cliente', (select jsonb_build_object('nome', coalesce(c.nome, e.cliente_nome), 'email', c.email, 'telefone', coalesce(c.telefone, e.cliente_telefone), 'nif', coalesce(c.nif, e.cliente_nif))
                  from (select 1) x left join clientes c on c.id = e.cliente_id),
    'simulacao', (select jsonb_build_object('codigo', s.codigo, 'em', s.created_at) from simulacoes s where s.id = e.simulacao_id),
    'proposta', (select jsonb_build_object('preco', p.preco, 'estado', p.estado, 'em', p.respondida_em) from propostas p where p.id = e.proposta_id),
    'chegou_em', (select jsonb_object_agg(para, em) from (select h.para::text para, min(h.created_at) em from encomenda_historico h where h.encomenda_id = e.id group by h.para) t),
    'armazem', (select to_jsonb(ra) || jsonb_build_object('armazem', a.nome) from recibos_armazem ra left join armazens a on a.id = ra.armazem_id where ra.encomenda_id = e.id),
    'entrega', (select to_jsonb(en) from entregas en where en.encomenda_id = e.id),
    'tarefa_destino', (select jsonb_build_object('estado', t.estado, 'notas', t.notas, 'data', t.data) from trabalhos_terreno t where t.encomenda_id = e.id and t.tipo = 'processamento_destino' order by t.created_at desc limit 1),
    'documentos', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'nome', d.nome, 'categoria', d.categoria, 'mime', d.mime, 'caminho', d.storage_path, 'em', d.created_at) order by d.created_at), '[]'::jsonb)
                     from documentos d where d.encomenda_id = e.id and d.verificado),
    'pagamentos', (select coalesce(jsonb_agg(jsonb_build_object('codigo', pg.codigo, 'tipo', pg.tipo, 'valor', pg.valor, 'estado', pg.estado, 'metodo', pg.metodo, 'pago_em', pg.pago_em, 'em', pg.created_at) order by pg.created_at), '[]'::jsonb)
                     from pagamentos pg where pg.encomenda_id = e.id),
    'financeiro', jsonb_build_object('preco', e.preco_total, 'pago', pago, 'em_divida', greatest(e.preco_total - pago, 0), 'comissao', comissao,
                     'comissao_regra', case when regra.id is null then null when regra.tipo_valor = 'percentagem' then regra.valor || ' %' else regra.valor || ' € fixo' end,
                     'pendentes', (select count(*) from pagamentos pg where pg.encomenda_id = e.id and pg.estado in ('pendente','parcial'))),
    'historico', (select coalesce(jsonb_agg(jsonb_build_object('de', h.de, 'para', h.para, 'em', h.created_at, 'responsavel', coalesce(h.responsavel, f.nome), 'prestador', h.prestador,
                     'nota', h.nota, 'motivo_excecao', h.motivo_excecao, 'documentos', (select jsonb_agg(d.nome) from documentos d where d.id = any (h.documentos))) order by h.id), '[]'::jsonb)
                     from encomenda_historico h left join funcionarios f on f.id = h.user_id where h.encomenda_id = e.id),
    'ocorrencias', (select coalesce(jsonb_agg(jsonb_build_object('codigo', o.codigo, 'tipo', o.tipo, 'gravidade', o.gravidade, 'estado', o.estado, 'descricao', o.descricao, 'resolucao', o.resolucao, 'em', o.created_at) order by o.created_at), '[]'::jsonb)
                     from ocorrencias o where o.encomenda_id = e.id),
    'proximos', (select coalesce(jsonb_agg(jsonb_build_object('para', t.para, 'permitido', papel is not null and papel = any (t.papeis) and not adm,
                     'excecao', t.de = 'aprovacao' and t.para = 'armazenamento', 'falta', to_jsonb(private.encomenda_falta(e, t.para, case when t.de = 'aprovacao' and t.para = 'armazenamento' then 'motivo a indicar' end)))
                     order by array_position(ordem, t.para::text) nulls last), '[]'::jsonb)
                     from encomenda_transicoes t where t.de = e.estado and t.para <> 'cancelada' and not (t.de = 'destino' and t.para = 'entregue')),
    'pode_cancelar', exists (select 1 from encomenda_transicoes t where t.de = e.estado and t.para = 'cancelada' and papel = any (t.papeis)),
    'papel', coalesce(papel::text, case when adm then 'administracao' end));
  return r;
end $$;
revoke all on function public.encomenda_ficha(text) from public, anon;
grant execute on function public.encomenda_ficha(text) to authenticated;

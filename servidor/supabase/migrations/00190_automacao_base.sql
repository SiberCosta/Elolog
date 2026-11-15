-- v135: a plataforma automatiza-se na base de dados (antes dependia de alguém abrir a página «Automação» no navegador).
-- De 15 em 15 minutos, private.automacao_plataforma() avisa a empresa (uma única vez por caso) quando:
--   1) uma encomenda está em «Aprovação» há mais de 24 horas;
--   2) um pedido de cotação dirigido à empresa está sem resposta há mais de 24 horas;
--   3) um pagamento está pendente há mais de 3 dias;
--   4) uma carga em trânsito passou a data de chegada prevista.
-- Só cria avisos (notificações); não muda estados, valores nem permissões. Só acrescenta uma função e uma tarefa agendada.
create or replace function private.automacao_plataforma() returns int language plpgsql security definer set search_path = public as $$
declare n int := 0; k int;
begin
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  select e.empresa_id, 'auto_aprovacao', 'Encomenda à espera de aprovação: ' || e.codigo,
         'A encomenda ' || e.codigo || ' (' || e.origem || ' → ' || e.destino || ') está em «Aprovação» há mais de 24 horas.', 'encomendas', e.id
  from encomendas e where e.estado = 'aprovacao' and e.created_at < now() - interval '24 hours' and not coalesce(e.suspensa, false)
    and not exists (select 1 from notificacoes x where x.tipo = 'auto_aprovacao' and x.referencia_id = e.id);
  get diagnostics k = row_count; n := n + k;

  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  select s.empresa_destinatario_id, 'auto_pedido', 'Pedido sem resposta: ' || s.codigo,
         'O pedido ' || s.codigo || ' (' || s.origem || ' → ' || s.destino || ') espera pela sua proposta há mais de 24 horas.', 'simulacoes', s.id
  from simulacoes s where s.estado = 'enviada' and s.empresa_destinatario_id is not null and coalesce(s.enviada_em, s.created_at) < now() - interval '24 hours'
    and not exists (select 1 from propostas p where p.simulacao_id = s.id and p.empresa_id = s.empresa_destinatario_id)
    and not exists (select 1 from notificacoes x where x.tipo = 'auto_pedido' and x.referencia_id = s.id);
  get diagnostics k = row_count; n := n + k;

  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  select p.empresa_id, 'auto_pagamento', 'Pagamento pendente: ' || coalesce(p.codigo, ''),
         'O pagamento ' || coalesce(p.codigo, '') || ' de ' || to_char(p.valor, 'FM999G999G990D00') || ' ' || p.moeda || ' está pendente há mais de 3 dias.', 'pagamentos', p.id
  from pagamentos p where p.estado = 'pendente' and p.empresa_id is not null and p.created_at < now() - interval '3 days'
    and not exists (select 1 from notificacoes x where x.tipo = 'auto_pagamento' and x.referencia_id = p.id);
  get diagnostics k = row_count; n := n + k;

  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  select e.empresa_id, 'auto_atraso', 'Chegada prevista ultrapassada: ' || e.codigo,
         'A carga ' || e.codigo || coalesce(' (navio ' || e.navio || ')', '') || ' devia ter chegado a ' || to_char(e.chegada_prevista, 'DD/MM/YYYY') || '. Atualize o estado ou a nova data.', 'encomendas', e.id
  from encomendas e where e.estado = 'em_transito' and e.chegada_prevista < current_date
    and not exists (select 1 from notificacoes x where x.tipo = 'auto_atraso' and x.referencia_id = e.id);
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function private.automacao_plataforma() from public, anon, authenticated;

do $$ begin if exists (select 1 from pg_extension where extname = 'pg_cron') then
  perform cron.schedule('elolog-automacao', '*/15 * * * *', $c$select private.automacao_plataforma()$c$); end if; end $$;

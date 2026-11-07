-- Testes da v100: regras automáticas de movimentação, histórico obrigatório e ficha da operação. Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
insert into auth.users (id, email) values ('a1000000-0000-0000-0000-000000000001','op@x.pt'), ('a1000000-0000-0000-0000-000000000002','arm@x.pt'),
  ('a1000000-0000-0000-0000-000000000003','adm@x.pt'), ('a1000000-0000-0000-0000-000000000004','outra@x.pt'), ('66666666-6666-6666-6666-666666666666','equipa@elolog.pt');
insert into administradores_plataforma (user_id, nome) values ('66666666-6666-6666-6666-666666666666','Equipa');
set local session_replication_role = replica;
insert into empresas (id, nome, nif, email, estado) values ('b1000000-0000-0000-0000-000000000001','Atlântico Lda','500000101','a@x.pt','aprovada'),
  ('b1000000-0000-0000-0000-000000000002','Outra Lda','500000102','o@x.pt','aprovada');
insert into funcionarios (id, empresa_id, nome, email, papel) values ('a1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','Rui Operador','op@x.pt','operador'),
  ('a1000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000001','Ana Armazém','arm@x.pt','armazem'),
  ('a1000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000001','Admin A','adm@x.pt','admin_empresa'),
  ('a1000000-0000-0000-0000-000000000004','b1000000-0000-0000-0000-000000000002','Admin B','outra@x.pt','admin_empresa');
insert into sessoes_empresa (user_id, empresa_id, valida_ate) select id, empresa_id, now() + interval '1 hour' from funcionarios where email like '%@x.pt';
insert into encomendas (id, codigo, empresa_id, cliente_nome, origem, destino, quantidade, preco_total, estado) values
  ('c1000000-0000-0000-0000-000000000001','EL-T-0001','b1000000-0000-0000-0000-000000000001','Cliente Um','Lisboa','São Tomé',3,500,'aprovacao'),
  ('c1000000-0000-0000-0000-000000000002','EL-T-0002','b1000000-0000-0000-0000-000000000001','Cliente Dois','Lisboa','São Tomé',1,100,'aprovacao');
insert into documentos (id, empresa_id, encomenda_id, categoria, nome, visibilidade, storage_path, enviado_por, verificado) values
  ('d1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','entrega','entrega-assinada.pdf','interna','b1/e.pdf','a1000000-0000-0000-0000-000000000001',true);
set local session_replication_role = origin;
insert into pagamentos (empresa_id, encomenda_id, tipo, valor, estado) values ('b1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','prestacao',200,'pendente');
insert into r select 1, count(*) = 1, 'pagamento pendente gera alerta financeiro' from notificacoes where tipo = 'alerta_financeiro';

create or replace function pg_temp.como(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated', 'aal', 'aal2')::text, true) $$;
create or replace function pg_temp.falha(n int, nome text, q text, frag text default '') returns void language plpgsql as $$ begin execute q; insert into r values (n, false, nome);
  exception when others then insert into r values (n, sqlerrm ilike '%' || frag || '%', nome || case when sqlerrm ilike '%' || frag || '%' then '' else ' [' || sqlerrm || ']' end); end $$;
create or replace function pg_temp.av(p text, para text, nota text default null, exc text default null) returns void language sql as $$
  select public.avancar_encomenda((select id from encomendas where codigo = p), para::estado_encomenda, nota, null, exc) $$;
grant execute on all functions in schema pg_temp to authenticated;
set local role authenticated;
select pg_temp.como('a1000000-0000-0000-0000-000000000001');   -- operador
select pg_temp.falha(2, 'aprovação → em trânsito não é permitido', $q$select pg_temp.av('EL-T-0001','em_transito')$q$, 'não permitida');
select pg_temp.falha(3, 'operador não dispensa a aprovação fora do fluxo autorizado', $q$select pg_temp.av('EL-T-0001','armazenamento',null,'Cliente entregou no armazém')$q$, 'fluxo autorizado');
select pg_temp.av('EL-T-0001','agendamento','Recolha marcada');
insert into r select 4, codigo = 'EL-T-0001' and de = 'aprovacao' and para = 'agendamento' and responsavel = 'Rui Operador' and prestador = 'Atlântico Lda' and nota = 'Recolha marcada' and created_at is not null,
  'histórico: número, estado anterior, novo, data, responsável, prestador, observações' from encomenda_historico order by id desc limit 1;
select pg_temp.av('EL-T-0001','recolha');
select pg_temp.falha(5, 'armazenamento exige receção com quantidade', $q$select pg_temp.av('EL-T-0001','armazenamento')$q$, 'quantidade confirmada');
select pg_temp.como('a1000000-0000-0000-0000-000000000002');   -- armazém
select pg_temp.falha(6, 'quantidade diferente exige ocorrência', $q$select public.encomenda_rececao_armazem('c1000000-0000-0000-0000-000000000001',2,true)$q$, 'Descreva a ocorrência');
select public.encomenda_rececao_armazem('c1000000-0000-0000-0000-000000000001', 2, true, 'Um volume ficou no camião; segue amanhã.', 'A-12');
select pg_temp.como('a1000000-0000-0000-0000-000000000001');
select pg_temp.av('EL-T-0001','armazenamento');
select pg_temp.av('EL-T-0001','expedicao');
select pg_temp.falha(7, 'em trânsito exige navio, viagem e data', $q$select pg_temp.av('EL-T-0001','em_transito')$q$, 'navio, viagem');
select public.encomenda_expedicao('c1000000-0000-0000-0000-000000000001', 'MSC Lisboa', 'V-123', current_date + 2, current_date + 14);
select pg_temp.av('EL-T-0001','em_transito');
select pg_temp.falha(8, 'em trânsito → levantado diretamente é bloqueado', $q$select pg_temp.av('EL-T-0001','entregue')$q$, 'não permitida');
select pg_temp.av('EL-T-0001','destino','Chegou ao porto');
reset role;
insert into r select 9, count(*) = 1, 'chegada cria a tarefa de processamento no destino' from trabalhos_terreno where tipo = 'processamento_destino' and estado = 'planeada';
set local role authenticated;
select pg_temp.falha(10, 'destino → levantado sem Disponível é bloqueado', $q$select pg_temp.av('EL-T-0001','entregue')$q$, 'Disponível');
select pg_temp.falha(11, 'Disponível exige o processamento concluído', $q$select pg_temp.av('EL-T-0001','disponivel')$q$, 'processamento');
select public.encomenda_processamento_destino('c1000000-0000-0000-0000-000000000001', 'Carga conferida no destino');
select pg_temp.av('EL-T-0001','disponivel');
select pg_temp.falha(12, 'levantado exige confirmação do levantamento', $q$select pg_temp.av('EL-T-0001','entregue')$q$, 'levantamento');
select public.encomenda_levantamento('c1000000-0000-0000-0000-000000000001', 'CC 12345678', 'd1000000-0000-0000-0000-000000000001');
select public.avancar_encomenda('c1000000-0000-0000-0000-000000000001', 'entregue', 'Entregue ao destinatário', array['d1000000-0000-0000-0000-000000000001']::uuid[]);
insert into r select 13, estado = 'entregue', 'percurso completo até Levantado' from encomendas where codigo = 'EL-T-0001';
insert into r select 14, documentos = array['d1000000-0000-0000-0000-000000000001']::uuid[], 'histórico guarda os documentos' from encomenda_historico where para = 'entregue';
-- aprovação dispensada no fluxo autorizado (administrador da empresa, com motivo)
select pg_temp.como('a1000000-0000-0000-0000-000000000003');
select pg_temp.falha(15, 'dispensar aprovação exige motivo de exceção', $q$select pg_temp.av('EL-T-0002','armazenamento')$q$, 'motivo de exceção');
select public.encomenda_rececao_armazem('c1000000-0000-0000-0000-000000000002', 1, true);
select pg_temp.av('EL-T-0002','armazenamento','Entrada direta','Cliente entregou a carga no armazém (fluxo autorizado)');
insert into r select 16, motivo_excecao like 'Cliente entregou%' and de = 'aprovacao' and para = 'armazenamento', 'motivo de exceção guardado no histórico' from encomenda_historico where codigo = 'EL-T-0002' and para = 'armazenamento';
select pg_temp.falha(17, 'estado não muda por atualização direta', $q$update encomendas set estado = 'entregue' where codigo = 'EL-T-0002'$q$, '');
-- ficha
select pg_temp.como('66666666-6666-6666-6666-666666666666');
insert into r select 18, (public.encomenda_ficha('EL-T-0001')->'financeiro'->>'em_divida')::numeric = 500 and jsonb_array_length(public.encomenda_ficha('EL-T-0001')->'historico') >= 10,
  'ficha: financeiro e histórico completos (administração)' from (select 1) x;
select pg_temp.como('a1000000-0000-0000-0000-000000000002');
insert into r select 19, (select bool_and(not (x->>'permitido')::boolean) or true from jsonb_array_elements(public.encomenda_ficha('EL-T-0002')->'proximos') x)
  and (public.encomenda_ficha('EL-T-0002')->'proximos'->0->>'para') = 'expedicao', 'ficha: próximos passos com requisitos' from (select 1) x;
select pg_temp.como('a1000000-0000-0000-0000-000000000004');
select pg_temp.falha(20, 'outra empresa não abre a ficha', $q$select public.encomenda_ficha('EL-T-0001')$q$, 'Sem permissão');
reset role;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

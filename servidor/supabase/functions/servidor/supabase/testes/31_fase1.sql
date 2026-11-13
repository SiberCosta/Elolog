-- Testes da v127 (Fase 1): seguimento ao vivo, alertas, comprovativo no terreno (sem rede/idempotente), entrega concluída, documento EL-ENT e webhooks.
-- Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated, anon, service_role;
insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111','cli@x.pt'),('12121212-1212-1212-1212-121212121212','outro@x.pt'),
  ('22222222-2222-2222-2222-222222222222','adm-a@x.pt'),('33333333-3333-3333-3333-333333333333','adm-b@x.pt'),('66666666-6666-6666-6666-666666666666','mot-a@x.pt'),('77777777-7777-7777-7777-777777777777','mot2-a@x.pt');
set local session_replication_role = replica;
insert into clientes (id, nome, email, nif) values ('11111111-1111-1111-1111-111111111111','Ana Cliente','cli@x.pt','123456789'),('12121212-1212-1212-1212-121212121212','Outro','outro@x.pt','987654321');
insert into empresas (id, nome, nif, email, estado) values ('a0000000-0000-0000-0000-00000000000a','Prest A','500000010','a@x.pt','aprovada'),('b0000000-0000-0000-0000-00000000000b','Prest B','500000020','b@x.pt','aprovada');
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-00000000000a','Rita Admin','adm-a@x.pt','admin_empresa'),
  ('33333333-3333-3333-3333-333333333333','b0000000-0000-0000-0000-00000000000b','Nuno B','adm-b@x.pt','admin_empresa'),('66666666-6666-6666-6666-666666666666','a0000000-0000-0000-0000-00000000000a','Mário Motorista','mot-a@x.pt','operador_terreno'),
  ('77777777-7777-7777-7777-777777777777','a0000000-0000-0000-0000-00000000000a','Outro Motorista','mot2-a@x.pt','operador_terreno');
insert into sessoes_empresa (user_id, empresa_id, valida_ate) select id, empresa_id, now() + interval '1 hour' from funcionarios where email like '%-a@x.pt' or email like '%-b@x.pt';
insert into encomendas (id, codigo, empresa_id, cliente_id, origem, destino, quantidade, preco_total, estado, destinatario)
values ('e0000000-0000-0000-0000-00000000000e','ELO-F1-1','a0000000-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111','Almada','São Tomé',4,300,'disponivel','{"nome":"Rui","morada":"Riboque"}');
insert into trabalhos_terreno (id, empresa_id, encomenda_id, tipo, operador_id, data, estado) values
  ('f0000000-0000-0000-0000-00000000000f','a0000000-0000-0000-0000-00000000000a','e0000000-0000-0000-0000-00000000000e','entrega','66666666-6666-6666-6666-666666666666',current_date,'planeada');
set local session_replication_role = origin;
create or replace function pg_temp.como(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated', 'aal', 'aal2')::text, true) $$;
create or replace function pg_temp.falha(n int, nome text, q text) returns void language plpgsql as $$ begin execute q; insert into r values (n, false, nome);
  exception when others then insert into r values (n, true, nome); end $$;
grant execute on all functions in schema pg_temp to authenticated, anon, service_role;
\set T '''f0000000-0000-0000-0000-00000000000f'''
\set PNG '''data:image/png;base64,iVBORw0KGgo='''

-- 1-4) percurso e posição
set local role authenticated; select pg_temp.como('77777777-7777-7777-7777-777777777777');
select pg_temp.falha(1, 'outro motorista não inicia um serviço que não é seu', $q$select iniciar_percurso('f0000000-0000-0000-0000-00000000000f', 38.67, -9.16)$q$);
select pg_temp.como('33333333-3333-3333-3333-333333333333');
select pg_temp.falha(2, 'outra empresa não inicia o serviço', $q$select iniciar_percurso('f0000000-0000-0000-0000-00000000000f', 38.67, -9.16)$q$);
select pg_temp.como('66666666-6666-6666-6666-666666666666');
select iniciar_percurso(:T, 38.67, -9.16, 20, now() + interval '30 minutes');
insert into r select 3, (select estado::text from trabalhos_terreno where id = :T) = 'em_curso', 'iniciar: serviço em curso e posição guardada';
insert into r select 4, registar_posicao(:T, 38.68, -9.15, 15, 40, now() + interval '20 minutes', 3.2) = false, 'posição repetida em menos de 15 s é ignorada';
reset role; update trabalhos_seguimento set atualizado_em = now() - interval '1 minute' where trabalho_id = :T; set local role authenticated; select pg_temp.como('66666666-6666-6666-6666-666666666666');
create temp table p5 as select registar_posicao(:T, 38.68, -9.15, 15, 40, now() + interval '20 minutes', 3.2) v;
insert into r select 5, (select v from p5) and (select lat from trabalhos_seguimento where trabalho_id = :T) = 38.68, 'posição nova gravada (só a última)';
-- 6-8) quem vê
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 6, count(*) = 1 and min(codigo) = 'ELO-F1-1', 'o cliente vê a sua entrega a caminho' from servicos_a_caminho();
select pg_temp.como('12121212-1212-1212-1212-121212121212');
insert into r select 7, count(*) = 0, 'outro cliente não vê nada' from servicos_a_caminho();
reset role; update trabalhos_seguimento set atualizado_em = now() - interval '40 minutes' where trabalho_id = :T; set local role authenticated;
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 8, count(*) = 0, 'sinal com mais de 30 min: o cliente deixa de ver a posição' from servicos_a_caminho();
-- 9-11) alertas
reset role; update trabalhos_seguimento set eta = now() + interval '2 hours' where trabalho_id = :T;
select private.alertas_terreno();
insert into r select 9, count(*) = 1, 'atraso previsto: aviso à empresa' from notificacoes where tipo = 'atraso_previsto' and empresa_id = 'a0000000-0000-0000-0000-00000000000a';
insert into r select 10, count(*) = 1, 'atraso previsto: aviso ao cliente' from notificacoes where tipo = 'atraso_previsto' and user_id = '11111111-1111-1111-1111-111111111111';
select private.alertas_terreno();
insert into r select 11, (select count(*) from notificacoes where tipo = 'atraso_previsto') = 2 and (select count(*) from notificacoes where tipo = 'sem_sinal') = 1, 'cada alerta só uma vez; sem sinal avisado';

-- 12-21) comprovativo de entrega
set local role authenticated; select pg_temp.como('66666666-6666-6666-6666-666666666666');
select pg_temp.falha(12, 'entrega sem assinatura é recusada', $q$select registar_comprovativo('{"id_local":"aaaaaaaa-0000-4000-8000-000000000001","trabalho":"f0000000-0000-0000-0000-00000000000f","resultado":"entregue","recebido_por":"Rui"}')$q$);
reset role; update empresas set limite_fotos = 1 where id = 'a0000000-0000-0000-0000-00000000000a'; set local role authenticated; select pg_temp.como('66666666-6666-6666-6666-666666666666');
select pg_temp.falha(13, 'fotografias acima do limite da empresa', format($q$select registar_comprovativo('{"id_local":"aaaaaaaa-0000-4000-8000-000000000002","trabalho":"f0000000-0000-0000-0000-00000000000f","resultado":"entregue","recebido_por":"Rui","assinatura":%s,"fotos":["data:image/jpeg;base64,AAAA","data:image/jpeg;base64,BBBB"]}')$q$, to_json(:PNG::text)));
create temp table x as select registar_comprovativo(jsonb_build_object('id_local','aaaaaaaa-0000-4000-8000-000000000003','trabalho',:T,'resultado','entregue','recebido_por','Rui Mendes','identificacao','CC 1234',
  'assinatura',:PNG,'volumes',4,'lat',0.33,'lon',6.73,'feito_em',now(),'fotos',jsonb_build_array('data:image/jpeg;base64,AAAA'))) v;
insert into r select 14, (select v ->> 'id' from x) is not null and (select estado::text from trabalhos_terreno where id = :T) = 'concluida', 'entrega registada: serviço concluído';
insert into r select 15, (select estado::text from encomendas where codigo = 'ELO-F1-1') = 'entregue', 'encomenda passa a «Entregue» com a assinatura do terreno';
insert into r select 16, (select terminado_em from trabalhos_seguimento where trabalho_id = :T) is not null, 'a partilha da posição termina com a entrega';
insert into r select 17, (registar_comprovativo(jsonb_build_object('id_local','aaaaaaaa-0000-4000-8000-000000000003','trabalho',:T,'resultado','entregue')) ->> 'repetido')::boolean
  and (select count(*) from comprovativos_terreno) = 1, 'reenvio sem rede: não grava duas vezes';
reset role;
insert into r select 18, numero like 'EL-ENT-%' and dados -> 'entrega' ->> 'recebido_por' = 'Rui Mendes' and (dados -> 'entrega' ->> 'fotos')::int = 1, 'documento EL-ENT emitido com quem recebeu e as fotos'
  from documentos_emitidos where tipo = 'entrega';
select pg_temp.falha(19, 'comprovativo não se altera', $q$update comprovativos_terreno set recebido_por = 'X'$q$);
set local role authenticated; select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 20, count(*) = 1, 'o cliente vê o comprovativo da sua entrega' from comprovativos_terreno;
select pg_temp.como('33333333-3333-3333-3333-333333333333');
insert into r select 21, count(*) = 0, 'outra empresa não vê o comprovativo' from comprovativos_terreno;

-- 22-30) webhooks
reset role; insert into r select 22, count(*) = 0, 'sem integração não há eventos na fila' from eventos_saida;
set local role authenticated; select pg_temp.como('22222222-2222-2222-2222-222222222222');
select pg_temp.falha(23, 'webhook só em https público (http recusado)', $q$select configurar_webhook('http://exemplo.pt/h', array['encomenda.estado'], true)$q$);
select pg_temp.falha(24, 'endereços internos recusados', $q$select configurar_webhook('https://10.0.0.5/h', array['encomenda.estado'], true)$q$);
select configurar_webhook('https://erp.exemplo.pt/elolog', array['encomenda.estado','documento.emitido','terreno.comprovativo'], true);
create temp table s as select gerar_segredo_webhook() v; grant select on s to authenticated, service_role;
insert into r select 25, (select v from s) like 'whsec_%' and not (ver_webhook() ? 'segredo') and (ver_webhook() ->> 'tem_segredo')::boolean, 'segredo mostrado uma vez e nunca devolvido depois';
select pg_temp.como('66666666-6666-6666-6666-666666666666');
select pg_temp.falha(26, 'o motorista não configura integrações', $q$select configurar_webhook('https://x.pt/h', array['encomenda.estado'], true)$q$);
select pg_temp.falha(27, 'a fila de envio não é acessível à aplicação', $q$select * from servico_webhooks_pendentes(5)$q$);
reset role; set local session_replication_role = replica; update encomendas set estado = 'destino' where codigo = 'ELO-F1-1'; set local session_replication_role = origin;
select set_config('elolog.transicao', 'on', true); update encomendas set estado = 'disponivel' where codigo = 'ELO-F1-1'; select set_config('elolog.transicao', 'off', true);
set local role service_role; select set_config('request.jwt.claims', '{"role":"service_role"}', true);
insert into r select 28, count(*) = 1 and min(segredo) = (select v from s) and min(tipo) = 'encomenda.estado', 'mudança de estado vai para a fila com o segredo do cofre' from servico_webhooks_pendentes(10);
select servico_webhook_resultado((select min(id) from eventos_saida), false, 'HTTP 500');
reset role;
insert into r select 29, estado = 'pendente' and tentativas = 1 and proxima_em > now(), 'falha: volta a tentar mais tarde' from eventos_saida order by id limit 1;
update eventos_saida set tentativas = 7; set local role service_role;
select servico_webhook_resultado((select min(id) from eventos_saida), false, 'HTTP 500'); reset role;
insert into r select 30, estado = 'falhou', 'à 8.ª tentativa falhada desiste' from eventos_saida order by id limit 1;
insert into r select 31, not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname <> 'validar_empresa'
  and has_function_privilege('anon', p.oid, 'execute')), 'o público continua a executar só validar_empresa';

reset role;
select n, case when ok then 'ok' else 'FALHOU' end, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as resultado from r;
rollback;

-- Testes da v98: encomendas diretas (cliente → validação da administração → decisão do prestador). Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
create temp table v (k text primary key, id uuid); grant all on v to authenticated;
insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111','cliente@x.pt'), ('66666666-6666-6666-6666-666666666666','equipa@elolog.pt'),
  ('22222222-2222-2222-2222-222222222222','op-a@x.pt'), ('33333333-3333-3333-3333-333333333333','op-d@x.pt');
insert into administradores_plataforma (user_id, nome) values ('66666666-6666-6666-6666-666666666666','Equipa');
set local session_replication_role = replica;
insert into empresas (id, nome, nif, email, estado) values ('a0000000-0000-0000-0000-00000000000a','Prest A','500000010','a@x.pt','aprovada'),
  ('b0000000-0000-0000-0000-00000000000b','Prest B','500000020','b@x.pt','aprovada'), ('c0000000-0000-0000-0000-00000000000c','Prest C','500000030','c@x.pt','pendente'),
  ('d0000000-0000-0000-0000-00000000000d','Prest D','500000040','d@x.pt','aprovada');
insert into planos (id, nome) values ('f0000000-0000-0000-0000-00000000000f','Base');
insert into subscricoes (empresa_id, plano_id, valor, estado, periodicidade) select e, 'f0000000-0000-0000-0000-00000000000f', 10, 'ativa', 'mensal'
  from unnest(array['a0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b','c0000000-0000-0000-0000-00000000000c','d0000000-0000-0000-0000-00000000000d']::uuid[]) e;
insert into tarifas (empresa_id, nome, metodo, valor, origem, destino) values ('a0000000-0000-0000-0000-00000000000a','LIS-STP','peso',2,'Lisboa','São Tomé'),
  ('b0000000-0000-0000-0000-00000000000b','POR-LAD','peso',2,'Porto','Luanda');
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-00000000000a','Op A','op-a@x.pt','operador'),
  ('33333333-3333-3333-3333-333333333333','d0000000-0000-0000-0000-00000000000d','Op D','op-d@x.pt','operador');
insert into sessoes_empresa (user_id, empresa_id, valida_ate) values ('22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-00000000000a', now() + interval '1 hour'),
  ('33333333-3333-3333-3333-333333333333','d0000000-0000-0000-0000-00000000000d', now() + interval '1 hour');
insert into documentos (id, cliente_id, categoria, nome, visibilidade, storage_path, enviado_por, verificado) values
  ('e0000000-0000-0000-0000-00000000000e','11111111-1111-1111-1111-111111111111','comprovativo','orcamento.pdf','cliente','11111111-1111-1111-1111-111111111111/orc.pdf','11111111-1111-1111-1111-111111111111',true);
set local session_replication_role = origin;

create or replace function pg_temp.como(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated', 'aal', 'aal2')::text, true) $$;
create or replace function pg_temp.falha(n int, nome text, q text) returns void language plpgsql as $$ begin execute q; insert into r values (n, false, nome);
  exception when others then insert into r values (n, true, nome); end $$;
grant execute on all functions in schema pg_temp to authenticated;
set local role authenticated;

-- cliente
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 1, array_agg(nome order by nome) = array['Prest A','Prest D'], 'lista: só ativos e elegíveis para a rota (A tem a rota, D serve todas; B noutra rota; C pendente)' from public.prestadores_encomenda_direta('Lisboa','São Tomé');
select pg_temp.falha(2, 'recusa prestador que não serve a rota', $q$select public.criar_encomenda_direta('b0000000-0000-0000-0000-00000000000b','Lisboa','São Tomé','Roupa',3,50,null,300,current_date+5,'e0000000-0000-0000-0000-00000000000e',null)$q$);
select pg_temp.falha(3, 'comprovativo obrigatório', $q$select public.criar_encomenda_direta('a0000000-0000-0000-0000-00000000000a','Lisboa','São Tomé','Roupa',3,50,null,300,current_date+5,null,null)$q$);
insert into v select 'ed', (public.criar_encomenda_direta('a0000000-0000-0000-0000-00000000000a','Lisboa','São Tomé','Roupa e calçado',3,50,0.4,300,current_date+5,'e0000000-0000-0000-0000-00000000000e','Frágil')->>'id')::uuid;
insert into r select 4, estado = 'pendente_validacao' and codigo like 'ED-%', 'cliente regista: pendente de validação' from encomendas_diretas;
-- prestador ainda não vê
select pg_temp.como('22222222-2222-2222-2222-222222222222');
insert into r select 5, count(*) = 0, 'prestador não vê antes do encaminhamento' from encomendas_diretas;
-- administração
select pg_temp.como('66666666-6666-6666-6666-666666666666');
select pg_temp.falha(6, 'não encaminha sem validar', format($q$select public.admin_encomenda_direta(%L,'enviar')$q$, (select id from v)));
select public.admin_encomenda_direta((select id from v), 'analisar');
select public.admin_comprovativo_visto((select id from v));
select public.admin_encomenda_direta((select id from v), 'validar', 'Orçamento confere.');
select public.admin_encomenda_direta((select id from v), 'enviar');
insert into r select 7, estado = 'enviada_prestador', 'administração: em análise → validada → enviada ao prestador' from encomendas_diretas;
-- prestador decide
select pg_temp.como('22222222-2222-2222-2222-222222222222');
insert into r select 8, count(*) = 1, 'prestador vê depois do encaminhamento' from encomendas_diretas;
insert into r select 9, count(*) = 1, 'prestador abre o comprovativo' from documentos where id = 'e0000000-0000-0000-0000-00000000000e';
insert into r select 22, (public.encomendas_diretas_lista()->0->>'cliente_email') is null, 'prestador não vê contactos do cliente antes de aceitar';
select public.prestador_encomenda_direta((select id from v), 'analisar');
select pg_temp.falha(10, 'recusa sem motivo não é aceite', format($q$select public.prestador_encomenda_direta(%L,'recusar')$q$, (select id from v)));
select pg_temp.falha(11, '«outro motivo» exige descrição', format($q$select public.prestador_encomenda_direta(%L,'recusar','outro','')$q$, (select id from v)));
select public.prestador_encomenda_direta((select id from v), 'recusar', 'espaco', 'Navio cheio nesta data.');
insert into r select 12, estado = 'recusada' and motivo_tipo = 'espaco', 'recusa com motivo' from encomendas_diretas;
-- a recusa não desaparece nem é reencaminhada sem o cliente
select pg_temp.como('66666666-6666-6666-6666-666666666666');
select pg_temp.falha(13, 'administração não reencaminha uma recusa', format($q$select public.admin_encomenda_direta(%L,'enviar')$q$, (select id from v)));
select pg_temp.como('11111111-1111-1111-1111-111111111111');
select pg_temp.falha(14, 'cliente não elimina', format($q$delete from encomendas_diretas where id = %L$q$, (select id from v)));
insert into r select 21, (public.encomendas_diretas_lista()->0->>'prestador') = 'Prest A' and jsonb_array_length(public.encomendas_diretas_lista()->0->'historico') = 6, 'lista do cliente com prestador e histórico';
insert into r select 15, motivo = 'Navio cheio nesta data.' , 'cliente vê o motivo da recusa' from encomendas_diretas;
select public.cliente_encomenda_direta((select id from v), 'trocar_prestador', 'd0000000-0000-0000-0000-00000000000d');
insert into r select 16, estado = 'pendente_validacao' and empresa_id = 'd0000000-0000-0000-0000-00000000000d', 'só o cliente escolhe outro prestador (volta à validação)' from encomendas_diretas;
insert into r select 17, count(*) = 7, 'histórico completo visível ao cliente' from encomendas_diretas_historico;
select pg_temp.como('33333333-3333-3333-3333-333333333333');
insert into r select 20, jsonb_array_length(public.encomendas_diretas_lista()) = 0, 'lista vazia para o novo prestador antes da validação';
insert into r select 18, count(*) = 0, 'novo prestador só vê depois de nova validação' from encomendas_diretas;
reset role;
insert into r select 19, count(*) >= 3, 'avisos criados (cliente, administração, prestador)' from notificacoes where referencia_tabela = 'encomendas_diretas';
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

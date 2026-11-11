-- Testes da v128: o prestador cria encomendas no servidor; os colegas veem-nas; reenvio sem duplicar; outras empresas não veem.
\set ON_ERROR_STOP 1
begin;
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated, anon;
insert into auth.users (id, email) values ('22222222-2222-2222-2222-222222222222','adm-a@x.pt'),('44444444-4444-4444-4444-444444444444','op-a@x.pt'),
  ('33333333-3333-3333-3333-333333333333','adm-b@x.pt'),('55555555-5555-5555-5555-555555555555','fin-a@x.pt');
set local session_replication_role = replica;
insert into empresas (id, nome, nif, email, estado) values ('a0000000-0000-0000-0000-00000000000a','Prest A','500000010','a@x.pt','aprovada'),('b0000000-0000-0000-0000-00000000000b','Prest B','500000020','b@x.pt','aprovada');
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-00000000000a','Rita Admin','adm-a@x.pt','admin_empresa'),
  ('44444444-4444-4444-4444-444444444444','a0000000-0000-0000-0000-00000000000a','Óscar Operador','op-a@x.pt','operador'),
  ('33333333-3333-3333-3333-333333333333','b0000000-0000-0000-0000-00000000000b','Nuno B','adm-b@x.pt','admin_empresa'),('55555555-5555-5555-5555-555555555555','a0000000-0000-0000-0000-00000000000a','Fi','fin-a@x.pt','financeiro');
insert into sessoes_empresa (user_id, empresa_id, valida_ate) select id, empresa_id, now() + interval '1 hour' from funcionarios;
set local session_replication_role = origin;
create or replace function pg_temp.como(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated', 'aal', 'aal2')::text, true) $$;
create or replace function pg_temp.falha(n int, nome text, q text) returns void language plpgsql as $$ begin execute q; insert into r values (n, false, nome);
  exception when others then insert into r values (n, true, nome); end $$;
grant execute on all functions in schema pg_temp to authenticated, anon;
\set P '''{"id_local":"ELO-LOCAL-0001","cliente_nome":"Puro Broto","origem":"Almada, Portugal","destino":"São Tomé","tipo_carga":"Veículo","descricao":"Carro","quantidade":1,"peso_kg":1200,"volume_m3":9.5,"preco_total":1912.3,"recolha":true,"morada_recolha":"Rua X 15, Almada","km_recolha":12.3,"recolha_valor":12.3,"recolha_tarifa":"Recolha","remetente":{"nome":"Puro Broto","telefone":"+351933893964"},"destinatario":{"nome":"Rui","morada":"Riboque"},"volumes":[{"descricao":"Carro","quantidade":1,"peso":1200}],"data_prevista":"2026-11-14"}'''

set local role authenticated; select pg_temp.como('22222222-2222-2222-2222-222222222222');
create temp table x as select criar_encomenda_prestador(:P::jsonb) v; grant select on x to authenticated;
insert into r select 1, (select v ->> 'codigo' from x) is not null and not (select (v ->> 'repetido')::boolean from x), 'o administrador cria a encomenda no servidor';
insert into r select 2, (criar_encomenda_prestador(:P::jsonb) ->> 'repetido')::boolean and (select count(*) from encomendas) = 1, 'reenvio do mesmo navegador não duplica';
select pg_temp.como('44444444-4444-4444-4444-444444444444');
insert into r select 3, count(*) = 1 and min(estado::text) = 'aprovacao' and min(cliente_nome) = 'Puro Broto', 'o colega (operador) vê a encomenda em Aprovação' from encomendas;
insert into r select 4, (preco_detalhe ->> 'recolha_km')::numeric = 12.3 and preco_total = 1912.3 and morada_recolha = 'Rua X 15, Almada', 'preço e km da recolha guardados' from encomendas;
select pg_temp.como('33333333-3333-3333-3333-333333333333');
insert into r select 5, count(*) = 0, 'outra empresa não vê a encomenda' from encomendas;
select pg_temp.como('55555555-5555-5555-5555-555555555555');
select pg_temp.falha(6, 'o financeiro não cria encomendas', $q$select criar_encomenda_prestador('{"id_local":"ELO-LOCAL-0002","cliente_nome":"X","origem":"A","destino":"B"}')$q$);
select pg_temp.como('22222222-2222-2222-2222-222222222222');
select pg_temp.falha(7, 'sem origem/destino é recusada', $q$select criar_encomenda_prestador('{"id_local":"ELO-LOCAL-0003","cliente_nome":"X","origem":"","destino":"B"}')$q$);
select pg_temp.falha(8, 'distância impossível é recusada', $q$select criar_encomenda_prestador('{"id_local":"ELO-LOCAL-0004","cliente_nome":"X","origem":"A","destino":"B","km_recolha":99999}')$q$);
reset role;
insert into r select 9, count(*) = 1, 'histórico e aviso à empresa registados' from encomenda_historico where nota = 'Encomenda criada pelo prestador';
insert into r select 10, count(*) = 1, 'aviso «nova encomenda para aprovar»' from notificacoes where tipo = 'encomenda_nova';
select n, case when ok then 'ok' else 'FALHOU' end, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as resultado from r;
rollback;

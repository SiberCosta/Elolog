-- Testes da v115: regras de cobrança — motor de busca pela descrição, tarifas de veículos, referência visível, comissões e simulador do prestador.
-- Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
create temp table v (k text primary key, id uuid, x jsonb); grant all on v to authenticated;
insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111','cliente@x.pt'), ('66666666-6666-6666-6666-666666666666','equipa@elolog.pt'),
  ('22222222-2222-2222-2222-222222222222','admin-a@x.pt'), ('33333333-3333-3333-3333-333333333333','admin-b@x.pt');
insert into administradores_plataforma (user_id, nome) values ('66666666-6666-6666-6666-666666666666','Equipa Elolog');
set local session_replication_role = replica;
insert into clientes (id, nome, email) values ('11111111-1111-1111-1111-111111111111','Ana','cliente@x.pt');
insert into empresas (id, nome, nif, email, estado) values ('a0000000-0000-0000-0000-00000000000a','Prest A','500000010','a@x.pt','aprovada'),
  ('b0000000-0000-0000-0000-00000000000b','Prest B','500000020','b@x.pt','aprovada');
insert into planos (id, nome) values ('f0000000-0000-0000-0000-00000000000f','Base');
insert into subscricoes (empresa_id, plano_id, valor, estado, periodicidade) select e, 'f0000000-0000-0000-0000-00000000000f', 10, 'ativa', 'mensal'
  from unnest(array['a0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b']::uuid[]) e;
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-00000000000a','Rita (A)','admin-a@x.pt','admin_empresa'),
  ('33333333-3333-3333-3333-333333333333','b0000000-0000-0000-0000-00000000000b','Nuno (B)','admin-b@x.pt','admin_empresa');
insert into sessoes_empresa (user_id, empresa_id, valida_ate) values ('22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-00000000000a', now() + interval '1 hour'),
  ('33333333-3333-3333-3333-333333333333','b0000000-0000-0000-0000-00000000000b', now() + interval '1 hour');
set local session_replication_role = origin;
create or replace function pg_temp.como(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated', 'aal', 'aal2')::text, true) $$;
create or replace function pg_temp.falha(n int, nome text, q text) returns void language plpgsql as $$ begin execute q; insert into r values (n, false, nome);
  exception when others then insert into r values (n, true, nome); end $$;
create or replace function pg_temp.preco(e text, d text default null, km numeric default 0, peso numeric default 100) returns jsonb language sql as $$ select to_jsonb(x) from public.precos_automaticos('Lisboa','São Tomé',null,2,peso,0.5,km,null,d) x where x.prestador_id = e::uuid $$;
grant execute on all functions in schema pg_temp to authenticated;
grant execute on all functions in schema pg_temp to authenticated;
set local role authenticated;
\set A '''a0000000-0000-0000-0000-00000000000a'''
\set B '''b0000000-0000-0000-0000-00000000000b'''
-- A: tarifa geral por peso e tarifa «Frigorífico» por unidade (só pela descrição), ambas aprovadas
select pg_temp.como('22222222-2222-2222-2222-222222222222');
insert into v select 'peso', (public.tarifa_guardar('{"nome":"Carga geral","metodo":"peso","valor":2,"origem":"Lisboa","destino":"São Tomé"}'::jsonb)).id;
insert into v select 'frigo', (public.tarifa_guardar('{"nome":"Frigorífico","metodo":"unidade","valor":75,"regras":{"so_descricao":true,"palavras":["arca congeladora"]}}'::jsonb)).id;
select pg_temp.como('66666666-6666-6666-6666-666666666666');
select public.tarifa_decidir(id, 'aprovar') from v where k in ('peso','frigo');
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 1, (pg_temp.preco(:A) ->> 'preco_final')::numeric = 200, 'sem descrição: tarifa de sempre (100 kg × 2 €)';
insert into r select 2, (pg_temp.preco(:A, 'Roupa e calçado') ->> 'preco_final')::numeric = 200, 'descrição sem nome de tarifa: igual';
insert into r select 3, (pg_temp.preco(:A, '2 FRIGORIFICOS combinados') ->> 'preco_final')::numeric = 150, 'descrição «frigoríficos» encontra a tarifa «Frigorífico» (2 × 75 €)';
insert into r select 4, (pg_temp.preco(:A, 'Uma arca congeladora') ->> 'preco_final')::numeric = 150, 'palavra-chave da tarifa também encontra';
insert into r select 5, (pg_temp.preco(:A, 'frigideiras') ->> 'preco_final')::numeric = 200, 'palavra parecida não engana (frigideiras ≠ frigorífico)';
-- veículos: A submete; geral da Elolog; escolha pela capacidade e preço
select pg_temp.como('22222222-2222-2222-2222-222222222222');
insert into tarifas_veiculos (empresa_id, nome, veiculo, capacidade_kg, preco_saida, preco_km, preco_minimo, estado) values (:A, 'Carrinha A', 'carrinha', 1000, 10, 0.5, 15, 'aprovado');
insert into r select 6, estado = 'pendente', 'veículo submetido pelo prestador fica pendente' from tarifas_veiculos where empresa_id = :A;
select pg_temp.falha(7, 'o prestador não cria tarifas gerais de veículos', $q$insert into tarifas_veiculos (nome, preco_km) values ('Geral', 1)$q$);
select pg_temp.falha(8, 'o prestador não se aprova a si próprio', $q$update tarifas_veiculos set estado = 'aprovado' where empresa_id = 'a0000000-0000-0000-0000-00000000000a'$q$);
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 9, (pg_temp.preco(:A, null, 40) ->> 'preco_final')::numeric = 240, 'veículo pendente não conta: recolha a 1 €/km (200 + 40)';
select pg_temp.como('66666666-6666-6666-6666-666666666666');
select public.veiculo_decidir(id, 'aprovar') from tarifas_veiculos where empresa_id = :A;
insert into tarifas_veiculos (nome, veiculo, capacidade_kg, preco_saida, preco_km, estado) values ('Camião Elolog', 'camiao', 10000, 40, 1, 'aprovado');
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 10, (pg_temp.preco(:A, null, 40) ->> 'preco_final')::numeric = 230, 'veículo do prestador: 10 + 40 km × 0,5 = 30 € (200 + 30)';
insert into r select 11, (pg_temp.preco(:A, null, 2) ->> 'preco_final')::numeric = 215, 'mínimo do veículo: 15 € (200 + 15)';
insert into r select 12, (pg_temp.preco(:A, null, 20, 3000) ->> 'preco_final')::numeric = 6060, 'carga acima da capacidade: usa o camião geral (6000 + 40 + 20)';
insert into r select 13, (pg_temp.preco(:A, null, 0) ->> 'preco_final')::numeric = 200, 'sem recolha: nenhum veículo';
-- prestador B: vê as gerais em vigor e a referência; não vê os veículos de A
select pg_temp.como('66666666-6666-6666-6666-666666666666');
insert into tarifas_gerais (nome, uso, metodo, valor, estado) values ('Referência peso', 'referencia', 'peso', 2.2, 'ativa'), ('Comercial reservada', 'comercial', 'peso', 1.9, 'ativa');
insert into regras_comissao (nome, empresa_id, tipo_valor, valor, ativa, escopo, evento) values ('Só para A', :A, 'percentagem', 5, true, 'encomenda', 'aprovacao'), ('Geral', null, 'percentagem', 8, true, 'encomenda', 'aprovacao');
select pg_temp.como('33333333-3333-3333-3333-333333333333');
insert into r select 14, count(*) filter (where nome = 'Referência peso') = 1 and count(*) filter (where nome = 'Comercial reservada') = 0, 'B vê a referência, não a comercial a que não está associado' from tarifas_gerais;
insert into r select 15, count(*) filter (where empresa_id is not null) = 0 and count(*) filter (where empresa_id is null) = 1, 'B vê o veículo geral, não o de A' from tarifas_veiculos;
insert into r select 16, count(*) = 1 and bool_and(geral), 'B só vê a comissão geral (não a de A)' from public.minhas_comissoes();
insert into r select 17, (public.simular_preco(:A, 'Lisboa', 'São Tomé', null, 2, 100, 0.5, 0) ->> 'disponivel')::boolean = false, 'B simula só a sua empresa (sem tarifas: sem preço)';
select pg_temp.como('22222222-2222-2222-2222-222222222222');
insert into r select 18, (public.simular_preco(null, 'Lisboa', 'São Tomé', null, 2, 100, 0.5, 0, null, 'frigorífico') ->> 'pela_descricao')::boolean, 'A simula com descrição e vê que a tarifa veio pela descrição';
select pg_temp.como('11111111-1111-1111-1111-111111111111');
select pg_temp.falha(19, 'o cliente não usa o simulador interno', $q$select public.simular_preco('a0000000-0000-0000-0000-00000000000a','Lisboa','São Tomé')$q$);
reset role;
insert into r select 20, exists (select 1 from tarifas_historico where entidade = 'tarifas_veiculos' and estado_anterior = 'pendente' and estado_novo = 'aprovado' and user_nome = 'Equipa Elolog'), 'histórico das tarifas de veículos';
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

-- Testes da v114/v116: Centro de Gestão de Tarifários (publicação pelo prestador, suspensão pela Elolog, versões, limites, gerais, suplementos, comissões, motor, cópia na aprovação,
-- histórico e privacidade). Só em base de TESTES; tudo é desfeito.
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
create or replace function pg_temp.preco(e text) returns jsonb language sql as $$ select to_jsonb(x) from public.calcular_precos('Lisboa','São Tomé','Roupa',3,100,0.5,0) x where x.prestador_id = e::uuid $$;
grant execute on all functions in schema pg_temp to authenticated;
set local role authenticated;
\set A '''a0000000-0000-0000-0000-00000000000a'''
\set B '''b0000000-0000-0000-0000-00000000000b'''

-- prestador A publica: a tarifa entra logo em vigor, sem esperar pela Elolog
select pg_temp.como('22222222-2222-2222-2222-222222222222');
insert into v select 't1', (public.tarifa_guardar('{"nome":"LIS-STP peso","metodo":"peso","valor":2,"origem":"Lisboa","destino":"São Tomé","preco_minimo":50,"limite_max":500}'::jsonb)).id;
insert into r select 1, estado = 'aprovada' and ativa, 'publicada pelo prestador: em vigor de imediato' from tarifas where id = (select id from v where k = 't1');
select pg_temp.falha(2, 'o prestador não se suspende nem se rejeita (é poder da Elolog)', $q$update tarifas set estado = 'suspensa' where id = (select id from v where k = 't1')$q$);
insert into tarifas (empresa_id, nome, metodo, valor, estado) values (:A, 'Atalho', 'fixo', 10, 'rascunho');
insert into r select 3, estado = 'rascunho' and not ativa, 'rascunho fica fora das simulações' from tarifas where nome = 'Atalho';
-- cliente: B não tem tarifas; A já tem
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 4, not (pg_temp.preco(:B) ->> 'disponivel')::boolean and pg_temp.preco(:B) ->> 'mensagem' = 'Não existe uma tarifa automática disponível. Solicite uma cotação personalizada.', 'sem tarifa aprovada: mensagem de cotação personalizada';
insert into r select 5, count(*) = 0, 'o cliente não lê tarifas internas' from tarifas;
select pg_temp.falha(6, 'o cliente não testa o motor (margens)', $q$select public.testar_preco('a0000000-0000-0000-0000-00000000000a','Lisboa','São Tomé')$q$);
-- a Elolog pode suspender (com motivo); só ela reativa
select pg_temp.como('66666666-6666-6666-6666-666666666666');
select pg_temp.falha(7, 'suspender exige motivo', $q$select public.tarifa_decidir((select id from v where k = 't1'), 'suspender', '')$q$);
select public.tarifa_decidir((select id from v where k = 't1'), 'suspender', 'Verificação de preços');
insert into r select 8, estado = 'suspensa' and not ativa, 'suspensa pela Elolog: fora das simulações' from tarifas where id = (select id from v where k = 't1');
select pg_temp.como('22222222-2222-2222-2222-222222222222');
select pg_temp.falha(30, 'o prestador não levanta a suspensão', $q$update tarifas set estado = 'aprovada' where id = (select id from v where k = 't1')$q$);
select pg_temp.como('66666666-6666-6666-6666-666666666666');
select public.tarifa_decidir((select id from v where k = 't1'), 'reativar');
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 9, (pg_temp.preco(:A) ->> 'preco_final')::numeric = 200 and pg_temp.preco(:A) ->> 'taxa_servico' is null, 'preço: 100 kg × 2 € = 200 €' ;
insert into r select 10, (select (x ->> 'disponivel')::boolean = false from (select to_jsonb(y) x from public.calcular_precos('Lisboa','São Tomé','Roupa',3,900,0.5,0) y where y.prestador_id = :A) z), 'fora do limite (900 kg > 500): incompatível';
-- prestador: tarifa aprovada não muda; nova versão
select pg_temp.como('22222222-2222-2222-2222-222222222222');
select pg_temp.falha(11, 'mudar o valor de uma aprovada é recusado', $q$update tarifas set valor = 3 where id = (select id from v where k = 't1')$q$);
-- simulação enviada e aceite ao preço de então (cópia congelada)
select pg_temp.como('11111111-1111-1111-1111-111111111111');
reset role;
insert into simulacoes (id, cliente_id, origem, destino, tipo_carga, quantidade, peso_kg, volume_m3) values ('c0000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','Lisboa','São Tomé','Roupa',3,100,0.5);
set local role authenticated;
select pg_temp.como('11111111-1111-1111-1111-111111111111');
select public.enviar_simulacao('c0000000-0000-0000-0000-000000000001', :A);
select pg_temp.como('22222222-2222-2222-2222-222222222222');
insert into v select 'enc', (public.aceitar_simulacao('c0000000-0000-0000-0000-000000000001')).id;
reset role;
insert into r select 13, e.preco_total = 200 and (e.preco_detalhe ->> 'preco_prestador')::numeric = 200 and e.preco_detalhe -> 'tarifa' ->> 'versao' = '1' and e.preco_detalhe ? 'congelado_em',
  'a encomenda guarda a cópia (tarifa versão 1, 200 €)' from encomendas e where id = (select id from v where k = 'enc');
set local role authenticated;
select pg_temp.como('22222222-2222-2222-2222-222222222222');
insert into v select 't2', (public.tarifa_guardar('{"nome":"LIS-STP peso","metodo":"peso","valor":3,"origem":"Lisboa","destino":"São Tomé","preco_minimo":50,"limite_max":500}'::jsonb, (select id from v where k = 't1'), true, 'Subida do combustível')).id;
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 12, (pg_temp.preco(:A) ->> 'preco_final')::numeric = 300, 'a nova versão entra logo em vigor (100 × 3 = 300)';
select pg_temp.como('22222222-2222-2222-2222-222222222222');
insert into r select 14, (select estado from tarifas where id = (select id from v where k = 't1')) = 'substituida' and (select estado from tarifas where id = (select id from v where k = 't2')) = 'aprovada', 'a v2 substitui a v1';
reset role;
insert into r select 15, preco_total = 200 and (preco_detalhe ->> 'preco_prestador')::numeric = 200, 'a nova versão não muda o preço já acordado' from encomendas where id = (select id from v where k = 'enc');
set local role authenticated;
select pg_temp.como('22222222-2222-2222-2222-222222222222');
select pg_temp.falha(16, 'o prestador não altera a cópia congelada', $q$update encomendas set preco_detalhe = '{}' where id = (select id from v where k = 'enc')$q$);
-- suplementos do prestador: entram logo
insert into tarifa_suplementos (empresa_id, nome, chave, tipo, valor) values (:A, 'Seguro', 'seguro', 'percentual', 10);
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 17, (pg_temp.preco(:A) ->> 'preco_final')::numeric = 330, 'suplemento do prestador entra logo (300 + 10 %)';
select pg_temp.como('66666666-6666-6666-6666-666666666666');
-- comissões: global 10 % incluída; Lisboa→São Tomé 5 % separada (mais específica)
insert into regras_comissao (escopo, evento, tipo_valor, valor, nome) values ('encomenda','aprovacao','percentagem',10,'Geral');
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 18, (pg_temp.preco(:A) ->> 'preco_final')::numeric = 330, 'suplemento aprovado (+10 %) e comissão incluída: o cliente paga 330';
select pg_temp.como('66666666-6666-6666-6666-666666666666');
insert into r select 19, (x ->> 'comissao')::numeric = 33 and (x ->> 'liquido_prestador')::numeric = 297 and x ->> 'origem_tarifa' = 'prestador',
  'motor: comissão 33 € retida, prestador recebe 297' from (select public.testar_preco(:A,'Lisboa','São Tomé','Roupa',3,100,0.5,0) x) z;
insert into regras_comissao (escopo, evento, tipo_valor, valor, nome, rota_origem, rota_destino, apresentacao) values ('encomenda','aprovacao','percentagem',5,'Rota STP','Lisboa','São Tomé','separada');
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 20, (pg_temp.preco(:A) ->> 'preco_final')::numeric = 346.5 and (pg_temp.preco(:A) ->> 'taxa_servico')::numeric = 16.5, 'comissão da rota (5 %, separada): taxa de 16,50 € à parte';
-- tarifário geral comercial associado a B (B não tem tarifas próprias)
select pg_temp.como('66666666-6666-6666-6666-666666666666');
insert into tarifas_gerais (nome, uso, metodo, valor, origem, destino, prestadores, estado) values ('Geral STP', 'comercial', 'fixo', 120, 'Lisboa', 'São Tomé', array[:B]::uuid[], 'ativa');
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 21, (pg_temp.preco(:B) ->> 'disponivel')::boolean and (pg_temp.preco(:B) ->> 'preco_final')::numeric > 120, 'B usa o tarifário geral associado (120 € + comissão separada)';
select pg_temp.como('22222222-2222-2222-2222-222222222222');
insert into r select 22, count(*) = 0, 'A não vê o tarifário geral associado só a B' from tarifas_gerais;
select pg_temp.falha(23, 'um prestador não cria tarifários gerais', $q$insert into tarifas_gerais (nome, metodo, valor) values ('X','fixo',1)$q$);
select pg_temp.como('33333333-3333-3333-3333-333333333333');
insert into r select 24, count(*) = 0, 'B não vê as tarifas de A' from tarifas;
-- administração altera o geral em vigor: exige motivo e cria versão
select pg_temp.como('66666666-6666-6666-6666-666666666666');
select pg_temp.falha(25, 'mudar o preço de um geral em vigor exige motivo', $q$update tarifas_gerais set valor = 130 where nome = 'Geral STP'$q$);
update tarifas_gerais set valor = 130, motivo_alteracao = 'Atualização anual' where nome = 'Geral STP';
insert into r select 26, versao = 2, 'o geral passa à versão 2' from tarifas_gerais where nome = 'Geral STP';
-- expirada não entra
reset role;
update tarifas set validade_fim = current_date - 1 where id = (select id from v where k = 't2');
set local role authenticated;
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 27, not (pg_temp.preco(:A) ->> 'disponivel')::boolean, 'tarifa expirada não é usada';
-- histórico
reset role;
insert into r select 28, exists (select 1 from tarifas_historico where entidade = 'tarifas' and motivo = 'Subida do combustível' and estado_novo = 'aprovada' and user_nome = 'Rita (A)')
  and exists (select 1 from tarifas_historico where entidade = 'tarifas' and estado_anterior = 'aprovada' and estado_novo = 'suspensa' and motivo = 'Verificação de preços' and user_nome = 'Equipa Elolog')
  and exists (select 1 from tarifas_historico where entidade = 'tarifas_gerais' and motivo = 'Atualização anual' and (antes ->> 'valor')::numeric = 120 and (depois ->> 'valor')::numeric = 130),
  'histórico: quem, quando, motivo, estado e valor anterior/novo';
set local role authenticated;
select pg_temp.como('33333333-3333-3333-3333-333333333333');
insert into r select 29, count(*) = 0, 'B não lê o histórico das tarifas de A' from tarifas_historico where entidade = 'tarifas';
reset role;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

-- Testes da v87: EloLog Maritime Search. Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('22222222-2222-2222-2222-222222222222','dono@luso.pt'), ('33333333-3333-3333-3333-333333333333','op@outra.pt'),
  ('55555555-5555-5555-5555-555555555555','cliente@x.pt');
insert into empresas (id, nome, nif, email, estado) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Luso','509999990','g@luso.pt','aprovada'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Outra','509999991','g@outra.pt','aprovada');
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Dono','dono@luso.pt','operador'),
  ('33333333-3333-3333-3333-333333333333','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Op','op@outra.pt','operador');
insert into sessoes_empresa (user_id, empresa_id, valida_ate) values ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', now() + interval '1 hour'),
  ('33333333-3333-3333-3333-333333333333','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', now() + interval '1 hour');
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
insert into viagens_maritimas (empresa_id, navio, mmsi, linha, viagem, sentido, porto_origem, porto_destino, partida, chegada, fecho_carga, cont20_livres, grupagem_m3)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Navio Teste Um','123456789','Linha A','V01','PT-STP','Lisboa','São Tomé', current_date + 10, current_date + 24, current_date + 7, 4, 20);
insert into viagens_maritimas (empresa_id, navio, sentido, porto_origem, porto_destino, partida, estado, cont20_livres, publicada)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Navio Rascunho','STP-PT','São Tomé','Leixões', current_date + 30, 'planeada', 0, false);
insert into r select 1, true, 'prestador publica viagens da própria empresa';
do $$ begin insert into viagens_maritimas (empresa_id, navio, sentido, porto_origem, porto_destino, partida)
  values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Intruso','PT-STP','Lisboa','São Tomé', current_date + 5); insert into r values (2, false, 'não publica em nome de outra empresa');
exception when others then insert into r values (2, true, 'não publica em nome de outra empresa'); end $$;
do $$ begin insert into viagens_maritimas (empresa_id, navio, sentido, porto_origem, porto_destino, partida, chegada)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Datas','PT-STP','Lisboa','São Tomé', current_date + 5, current_date + 1); insert into r values (3, false, 'chegada antes da partida recusada');
exception when check_violation then insert into r values (3, true, 'chegada antes da partida recusada'); end $$;
insert into r select 4, count(*) = 2, 'a empresa vê as suas viagens (incluindo rascunho)' from public.pesquisa_maritima();
-- Outro prestador
select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', true);
insert into r select 5, count(*) = 1, 'outra empresa só vê as publicadas' from public.pesquisa_maritima();
update viagens_maritimas set cont20_livres = 99 where navio = 'Navio Teste Um';
insert into r select 6, (select cont20_livres from viagens_maritimas where navio = 'Navio Teste Um') = 4, 'não altera viagens de outra empresa';
-- Cliente
select set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}', true);
insert into r select 7, count(*) = 1, 'cliente pesquisa as viagens publicadas' from public.pesquisa_maritima();
insert into r select 8, count(*) = 1, 'filtro por sentido PT-STP' from public.pesquisa_maritima(p_sentido => 'PT-STP');
insert into r select 9, count(*) = 0, 'filtro por sentido STP-PT (rascunho não aparece)' from public.pesquisa_maritima(p_sentido => 'STP-PT');
insert into r select 10, count(*) = 1, 'pesquisa por nome do navio' from public.pesquisa_maritima(p_texto => 'teste um');
insert into r select 11, count(*) = 1, 'só com espaço disponível' from public.pesquisa_maritima(p_so_disponivel => true);
insert into r select 12, count(*) = 1, 'pesquisa por porto' from public.pesquisa_maritima(p_porto => 'são tomé');
insert into r select 13, count(*) = 1, 'chegadas por intervalo de datas' from public.pesquisa_maritima(p_de => current_date + 20, p_ate => current_date + 30, p_por => 'chegada');
do $$ begin insert into viagens_maritimas (empresa_id, navio, sentido, porto_origem, porto_destino, partida)
  values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Cliente','PT-STP','Lisboa','São Tomé', current_date + 5); insert into r values (14, false, 'cliente não publica viagens');
exception when others then insert into r values (14, true, 'cliente não publica viagens'); end $$;
reset role;
insert into r select 15, exists (select 1 from navios_seguidos where mmsi = '123456789'), 'navio com MMSI passa a ser seguido pelo AIS';
insert into r select 16, exists (select 1 from auditoria where entidade = 'viagens_maritimas'), 'alterações registadas na auditoria';
select set_config('request.jwt.claims', '', true);
do $$ begin perform public.pesquisa_maritima(); insert into r values (17, false, 'sem sessão: recusado');
exception when others then insert into r values (17, true, 'sem sessão: recusado'); end $$;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

-- Testes da v91: a equipa Elolog publica viagens na Pesquisa marítima. Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('66666666-6666-6666-6666-666666666666','equipa@elolog.pt'), ('55555555-5555-5555-5555-555555555555','cliente@x.pt');
insert into administradores_plataforma (user_id, nome) values ('66666666-6666-6666-6666-666666666666','Equipa');
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated","aal":"aal2"}', true);
insert into viagens_elolog (navio, linha, sentido, porto_origem, porto_destino, partida, chegada, fecho_carga, cont20_livres, grupagem_m3)
  values ('Navio Elolog', 'Linha X', 'PT-STP', 'Lisboa', 'São Tomé', current_date + 12, current_date + 24, current_date + 9, 2, 10);
insert into viagens_elolog (navio, sentido, porto_origem, porto_destino, partida, publicada) values ('Rascunho Elolog', 'STP-PT', 'São Tomé', 'Lisboa', current_date + 30, false);
insert into r select 1, count(*) = 2, 'administração vê as suas viagens (incluindo rascunho)' from public.pesquisa_maritima();
insert into r select 2, bool_and(minha and prestador = 'Elolog'), 'aparecem como Elolog e editáveis pela administração' from public.pesquisa_maritima();
select set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}', true);
insert into r select 3, count(*) = 1, 'cliente vê só a publicada' from public.pesquisa_maritima();
insert into r select 4, count(*) = 1, 'aparece em «só com espaço»' from public.pesquisa_maritima(p_so_disponivel => true);
insert into r select 5, count(*) = 1, 'pesquisa por «elolog»' from public.pesquisa_maritima(p_texto => 'elolog');
do $$ begin insert into viagens_elolog (navio, sentido, porto_origem, porto_destino, partida) values ('Intruso','PT-STP','Lisboa','São Tomé', current_date + 3);
  insert into r values (6, false, 'cliente não publica como Elolog');
exception when others then insert into r values (6, true, 'cliente não publica como Elolog'); end $$;
update viagens_elolog set cont20_livres = 99;
reset role;
insert into r select 7, (select cont20_livres from viagens_elolog where navio = 'Navio Elolog') = 2, 'cliente não altera viagens da Elolog';
insert into r select 8, exists (select 1 from auditoria where entidade = 'viagens_elolog'), 'registado na auditoria';
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

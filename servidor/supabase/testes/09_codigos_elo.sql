-- Testes da v72: referências ELO_<REF>-NNNNNN (encomendas) e ELO_SM-NNNNNN (simulações). Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('55555555-5555-5555-5555-555555555555','cli@x.pt');
insert into clientes (id, nome, email) values ('55555555-5555-5555-5555-555555555555','Cliente','cli@x.pt');
insert into empresas (id, nome, nome_comercial, nif, email) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Transatlântico Demo, Lda.',null,'500000000','g@t.pt'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Transportes Rápidos SA',null,'500000001','g@r.pt'), ('cccccccc-cccc-cccc-cccc-cccccccccccc','Ab, Lda',null,'500000002','g@a.pt'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd','Luso Freight Unipessoal','Luso Freight','500000003','g@l.pt');
create temp table r (n int, ok boolean, nome text);
insert into r select 1, (select referencia from empresas where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') = 'TRAN', 'referência a partir do nome (sem acentos)';
insert into r select 2, (select referencia from empresas where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') = 'TRAN2', 'referência repetida ganha número';
insert into r select 3, (select referencia from empresas where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc') = 'ABX' and (select referencia from empresas where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd') = 'LUSO', 'nomes curtos e nome comercial';
insert into encomendas (empresa_id, cliente_id, origem, destino) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','55555555-5555-5555-5555-555555555555','Lisboa','Luanda'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','55555555-5555-5555-5555-555555555555','Porto','Praia'), ('dddddddd-dddd-dddd-dddd-dddddddddddd','55555555-5555-5555-5555-555555555555','Lisboa','Bissau');
insert into r select 4, (select array_agg(codigo order by codigo) from encomendas where origem in ('Lisboa','Porto')) = array['ELO_LUSO-000001','ELO_TRAN-000001','ELO_TRAN-000002'], 'encomendas ELO_<REF>-NNNNNN por prestador';
insert into simulacoes (cliente_id, origem, destino) values ('55555555-5555-5555-5555-555555555555','Lisboa','Luanda');
insert into r select 5, (select codigo from simulacoes where cliente_id = '55555555-5555-5555-5555-555555555555') ~ '^ELO_SM-\d{6}$', 'simulações ELO_SM-NNNNNN';
insert into encomendas (empresa_id, cliente_id, origem, destino, codigo) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','55555555-5555-5555-5555-555555555555','A','B','MANUAL-1');
insert into r select 6, exists (select 1 from encomendas where codigo = 'MANUAL-1'), 'código indicado à mão mantém-se';
do $$ begin update empresas set referencia = 'luso' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; insert into r values (7, false, 'referência única');
  exception when unique_violation then insert into r values (7, true, 'referência única'); end $$;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

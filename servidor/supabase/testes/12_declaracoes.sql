-- Testes da v75: declarações da encomenda (quem lê, quem grava, o embarque é do prestador). Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('22222222-2222-2222-2222-222222222222','dono@luso.pt'), ('55555555-5555-5555-5555-555555555555','cli@x.pt'), ('66666666-6666-6666-6666-666666666666','outro@x.pt'), ('77777777-7777-7777-7777-777777777777','dono@tejo.pt');
insert into clientes (id, nome, email, nif) values ('55555555-5555-5555-5555-555555555555','Maria Silva','cli@x.pt','123456789'), ('66666666-6666-6666-6666-666666666666','Outro','outro@x.pt',null);
insert into empresas (id, nome, nif, email, estado) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Luso','500000000','g@luso.pt','aprovada'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Tejo','500000001','g@tejo.pt','aprovada');
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Dono','dono@luso.pt','admin_empresa'),
  ('77777777-7777-7777-7777-777777777777','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Dono T','dono@tejo.pt','admin_empresa');
insert into sessoes_empresa (user_id, empresa_id, valida_ate) values ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', now() + interval '1 hour'),
  ('77777777-7777-7777-7777-777777777777','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', now() + interval '1 hour');
insert into encomendas (empresa_id, cliente_id, origem, destino, codigo) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','55555555-5555-5555-5555-555555555555','Lisboa','São Tomé','ELO_LUSO-000001');
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
set local role authenticated;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"55555555-5555-5555-5555-555555555555"}', true);
insert into r select 1, x->>'papel' = 'cliente' and x->'cliente'->>'nome' = 'Maria Silva' and x->'empresa'->>'nome' = 'Luso' and x->'dados' = '{}'::jsonb, 'cliente lê a sua encomenda com dados de base' from (select public.declaracoes_ler('ELO_LUSO-000001') x) t;
select public.declaracoes_gravar('ELO_LUSO-000001', '{"proprietario":{"nome":"Maria Silva"},"viatura":{"inclui":true,"matricula":"AA-00-BB"},"bens":[{"descricao":"Frigorífico","quantidade":1,"valor":300}],"embarque":{"contentor":"FALSO"}}');
reset role;
insert into r select 2, dados->'viatura'->>'matricula' = 'AA-00-BB' and dados->'embarque' = '{}'::jsonb, 'cliente grava; o embarque do cliente é ignorado' from encomenda_declaracoes;
set local role authenticated;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"22222222-2222-2222-2222-222222222222"}', true);
insert into r select 3, x->>'papel' = 'empresa' and x->'dados'->'proprietario'->>'nome' = 'Maria Silva', 'prestador da encomenda lê o que o cliente preencheu' from (select public.declaracoes_ler('ELO_LUSO-000001') x) t;
select public.declaracoes_gravar('ELO_LUSO-000001', (select public.declaracoes_ler('ELO_LUSO-000001')->'dados') || '{"embarque":{"contentor":"MSCU1234567","bl":"BL-9"}}');
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"55555555-5555-5555-5555-555555555555"}', true);
select public.declaracoes_gravar('ELO_LUSO-000001', '{"proprietario":{"nome":"Maria S. Silva"},"bens":[]}');
reset role;
insert into r select 4, dados->'embarque'->>'contentor' = 'MSCU1234567' and dados->'proprietario'->>'nome' = 'Maria S. Silva', 'o embarque do prestador mantém-se quando o cliente grava' from encomenda_declaracoes;
set local role authenticated;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"66666666-6666-6666-6666-666666666666"}', true);
do $$ begin perform public.declaracoes_ler('ELO_LUSO-000001'); insert into r values (5, false, 'outro cliente não vê');
  exception when others then insert into r values (5, true, 'outro cliente não vê'); end $$;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"77777777-7777-7777-7777-777777777777"}', true);
do $$ begin perform public.declaracoes_gravar('ELO_LUSO-000001', '{}'); insert into r values (6, false, 'outra empresa não grava');
  exception when others then insert into r values (6, true, 'outra empresa não grava'); end $$;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"55555555-5555-5555-5555-555555555555"}', true);
do $$ begin perform public.declaracoes_gravar('ELO_LUSO-000001', '{"bens":"x"}'); insert into r values (7, false, 'lista de bens inválida recusada');
  exception when others then insert into r values (7, true, 'lista de bens inválida recusada'); end $$;
do $$ begin perform 1 from encomenda_declaracoes; insert into r values (8, false, 'tabela fechada ao acesso direto');
  exception when insufficient_privilege then insert into r values (8, true, 'tabela fechada ao acesso direto'); end $$;
reset role;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

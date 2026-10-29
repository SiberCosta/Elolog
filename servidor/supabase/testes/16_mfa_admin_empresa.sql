-- Testes da v81: o administrador da empresa precisa do 2.º passo (aal2); os funcionários não. Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('22222222-2222-2222-2222-222222222222','dono@luso.pt'), ('33333333-3333-3333-3333-333333333333','op@luso.pt');
insert into empresas (id, nome, nif, email, estado) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Luso','509999990','g@luso.pt','aprovada');
insert into empresa_segredos (empresa_id, segredo_hash) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', extensions.crypt('EmpresaLuso2026', extensions.gen_salt('bf')));
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Dono','dono@luso.pt','admin_empresa'),
  ('33333333-3333-3333-3333-333333333333','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Op','op@luso.pt','operador');
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","aal":"aal1"}', true);
insert into r select 1, not (x).ok and (x).mensagem = 'MFA_NECESSARIO', 'administrador sem 2.º passo: pede o código' from (select public.abrir_sessao_empresa('Luso','509999990','EmpresaLuso2026') x) t;
insert into r select 2, not (x).ok and (x).mensagem <> 'MFA_NECESSARIO', 'palavra-passe da empresa errada não chega ao 2.º passo' from (select public.abrir_sessao_empresa('Luso','509999990','errada') x) t;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","aal":"aal2"}', true);
insert into r select 3, (x).ok, 'com o 2.º passo abre a sessão' from (select public.abrir_sessao_empresa('Luso','509999990','EmpresaLuso2026') x) t;
insert into r select 4, private.minha_empresa() = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 'aal2 vê a empresa';
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","aal":"aal1"}', true);
insert into r select 5, private.minha_empresa() is null and private.meu_papel() is null, 'sessão da empresa já aberta, mas token sem 2.º passo não vê nada';
select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","aal":"aal1"}', true);
insert into r select 6, (x).ok, 'operador entra sem o 2.º passo' from (select public.abrir_sessao_empresa('Luso','509999990','EmpresaLuso2026') x) t;
insert into r select 7, private.minha_empresa() is not null, 'operador vê a empresa';
reset role;
insert into r select 8, public.servico_admin_empresa_aal('22222222-2222-2222-2222-222222222222','aal2') is not null and public.servico_admin_empresa_aal('22222222-2222-2222-2222-222222222222','aal1') is null, 'Edge Functions exigem aal2 ao administrador';
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

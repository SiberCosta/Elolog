-- Testes da v80: n.º de funcionário automático e único; login por NIF + n.º (só o serviço). Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('22222222-2222-2222-2222-222222222222','dono@luso.pt'), ('33333333-3333-3333-3333-333333333333','op@luso.pt'), ('34343434-3434-3434-3434-343434343434','ter@luso.pt'), ('44444444-4444-4444-4444-444444444444','op@tejo.pt');
insert into empresas (id, nome, nif, email, estado) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Luso','509999990','g@luso.pt','aprovada'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Tejo','500000001','g@tejo.pt','aprovada');
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Dono','dono@luso.pt','admin_empresa'),
  ('33333333-3333-3333-3333-333333333333','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Op','op@luso.pt','operador'), ('44444444-4444-4444-4444-444444444444','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','OpT','op@tejo.pt','operador');
insert into funcionarios (id, empresa_id, nome, email, papel, numero_interno) values ('34343434-3434-3434-3434-343434343434','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Ter','ter@luso.pt','operador_terreno','0003');
create temp table r (n int, ok boolean, nome text);
insert into r select 1, (select array_agg(numero_interno order by email) from funcionarios where empresa_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') = array['0001','0002','0003'] and (select numero_interno from funcionarios where email='op@tejo.pt') = '0001', 'números automáticos por empresa (0001, 0002…)';
do $$ begin insert into auth.users (id, email) values ('35353535-3535-3535-3535-353535353535','x@luso.pt');
  insert into funcionarios (id, empresa_id, nome, email, papel, numero_interno) values ('35353535-3535-3535-3535-353535353535','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','X','x@luso.pt','operador','2'); insert into r values (2,false,'número repetido recusado');
  exception when unique_violation then insert into r values (2,true,'número repetido recusado'); end $$;
insert into auth.users (id, email) values ('36363636-3636-3636-3636-363636363636','y@luso.pt');
insert into funcionarios (id, empresa_id, nome, email, papel) values ('36363636-3636-3636-3636-363636363636','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Y','y@luso.pt','armazem');
insert into r select 3, (select numero_interno from funcionarios where email='y@luso.pt') = '0004', 'automático salta o número usado à mão';
insert into r select 4, (select email from public.servico_funcionario_por_numero('509 999 990','2')) = 'op@luso.pt' and (select email from public.servico_funcionario_por_numero('509999990','0002')) = 'op@luso.pt', 'encontra por NIF + n.º (com ou sem zeros)';
insert into r select 5, not exists (select 1 from public.servico_funcionario_por_numero('500000001','0002')), 'n.º de outra empresa não serve';
select public.servico_abrir_sessao_funcionario('33333333-3333-3333-3333-333333333333');
insert into r select 6, exists (select 1 from sessoes_empresa where user_id='33333333-3333-3333-3333-333333333333'), 'abre a sessão da empresa sem a senha da empresa';
do $$ begin perform public.servico_abrir_sessao_funcionario('22222222-2222-2222-2222-222222222222'); insert into r values (7,false,'administrador não entra sem a senha da empresa');
  exception when others then insert into r values (7,true,'administrador não entra sem a senha da empresa'); end $$;
insert into r select 8, not has_function_privilege('anon','public.servico_funcionario_por_numero(text,text)','execute') and not has_function_privilege('authenticated','public.servico_funcionario_por_numero(text,text)','execute'), 'pesquisa só para a chave de serviço';
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

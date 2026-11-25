-- Elolog · TESTE 33 — Entrada por email para todos (migração 00200, v163).
-- Executar no SQL Editor depois da migração 00200. Termina com um ERRO de propósito: a mensagem é o relatório e o
-- PostgreSQL desfaz tudo o que o teste criou. Resultado esperado: RELATORIO 9/9 :: tudo OK
begin;
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111','cli@x.pt'),('22222222-2222-2222-2222-222222222222','adm-a@x.pt'),('66666666-6666-6666-6666-666666666666','mot-a@x.pt'),('77777777-7777-7777-7777-777777777777','ina@x.pt'),('88888888-8888-8888-8888-888888888888','p@x.pt');
set local session_replication_role = replica;
insert into clientes (id, nome, email) values ('11111111-1111-1111-1111-111111111111','Ana','cli@x.pt');
insert into empresas (id, nome, nome_comercial, nif, email, estado) values ('a0000000-0000-0000-0000-00000000000a','Prest A Lda','Prest A','500000010','a@x.pt','aprovada'),('b0000000-0000-0000-0000-00000000000b','Prest B','Prest B','500000020','b@x.pt','pendente');
insert into funcionarios (id, empresa_id, nome, email, papel, ativo) values ('22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-00000000000a','Rita','adm-a@x.pt','admin_empresa',true),
 ('66666666-6666-6666-6666-666666666666','a0000000-0000-0000-0000-00000000000a','Mário','mot-a@x.pt','operador_terreno',true),('77777777-7777-7777-7777-777777777777','a0000000-0000-0000-0000-00000000000a','Ina','ina@x.pt','operador',false),
 ('88888888-8888-8888-8888-888888888888','b0000000-0000-0000-0000-00000000000b','P','p@x.pt','operador',true);
set local session_replication_role = origin;
create or replace function pg_temp.como(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true) $$;
grant execute on all functions in schema pg_temp to authenticated, anon;
set local role authenticated;
select pg_temp.como('11111111-1111-1111-1111-111111111111'); insert into r select 1, tipo='cliente', 'cliente' from entrar_por_email();
select pg_temp.como('66666666-6666-6666-6666-666666666666'); insert into r select 2, tipo='funcionario' and empresa_nome='Prest A' and empresa_nif='500000010' and papel='operador_terreno', 'funcionario abre sessão' from entrar_por_email();
select pg_temp.como('22222222-2222-2222-2222-222222222222'); insert into r select 4, tipo='admin_empresa' and empresa_nome_registo='Prest A Lda' and valida_ate is null, 'admin precisa da senha da empresa' from entrar_por_email();
select pg_temp.como('77777777-7777-7777-7777-777777777777'); insert into r select 5, tipo='recusado' and mensagem like '%desativada%', 'inativo recusado' from entrar_por_email();
select pg_temp.como('88888888-8888-8888-8888-888888888888'); insert into r select 6, tipo='recusado' and mensagem like '%aguarda%', 'empresa pendente recusada' from entrar_por_email();
reset role;
insert into r select 3, (select count(*) from sessoes_empresa where user_id='66666666-6666-6666-6666-666666666666' and valida_ate>now())=1, 'sessão da empresa ficou ativa';
insert into r select 7, (select count(*) from sessoes_empresa where user_id in ('22222222-2222-2222-2222-222222222222','77777777-7777-7777-7777-777777777777','88888888-8888-8888-8888-888888888888'))=0, 'admin/inativo/pendente sem sessão';
insert into r select 8, (select count(*) from auditoria where acao='abrir_sessao_funcionario_email' and user_id='66666666-6666-6666-6666-666666666666')=1, 'auditoria registada';
insert into r select 9, not has_function_privilege('anon','public.entrar_por_email()','execute'), 'anónimo não chama';
do $rel$ declare t text; begin select count(*) filter (where ok)||'/'||count(*)||' :: '||coalesce(string_agg(case when not ok then n||' '||nome end,' | ' order by n),'tudo OK') into t from r; raise exception 'RELATORIO %', t; end $rel$;

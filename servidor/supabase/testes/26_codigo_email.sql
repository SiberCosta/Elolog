-- Testes da v107: código por email no 2.º passo do administrador da empresa; notificações marcadas como lidas; sem TRUNCATE.
-- Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111','admin@empresa.pt'), ('22222222-2222-2222-2222-222222222222','outro@empresa.pt'),
  ('66666666-6666-6666-6666-666666666666','equipa@elolog.pt');
insert into administradores_plataforma (user_id, nome) values ('66666666-6666-6666-6666-666666666666','Equipa');
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
create temp table c (codigo text); grant all on c to authenticated;
set local session_replication_role = replica;
insert into empresas (id, nome, nif, email, estado) values ('a0000000-0000-0000-0000-000000000001','Atlântico Cargo','500000001','a@x.pt','aprovada');
insert into funcionarios (id, empresa_id, nome, email, papel) values ('11111111-1111-1111-1111-111111111111','a0000000-0000-0000-0000-000000000001','Ana','admin@empresa.pt','admin_empresa');
insert into notificacoes (id, para_plataforma, tipo, titulo) values ('b0000000-0000-0000-0000-000000000001', true, 'sistema', 'Teste');
set local session_replication_role = origin;

-- o serviço cria o código (sessão A)
insert into c select codigo from public.servico_codigo_email_criar('11111111-1111-1111-1111-111111111111','aaaaaaaa-0000-0000-0000-00000000000a');
insert into r select 1, (select codigo ~ '^\d{6}$' from c), 'o serviço recebe um código de 6 dígitos';
insert into r select 2, (select hash <> (select codigo from c) from codigos_email), 'o código fica guardado cifrado';
insert into r select 3, not exists (select 1 from public.servico_codigo_email_criar('22222222-2222-2222-2222-222222222222','aaaaaaaa-0000-0000-0000-00000000000a')), 'quem não é funcionário não recebe código';

set local role authenticated;
-- sessão B (outra) não pode usar o código da sessão A
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"bbbbbbbb-0000-0000-0000-00000000000b"}', true);
insert into r select 4, not public.confirmar_codigo_email((select codigo from c)), 'o código não serve noutra sessão';
-- sessão A
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-0000-0000-0000-00000000000a"}', true);
insert into r select 5, not private.sessao_reforcada(), 'antes do código a sessão não está reforçada';
insert into r select 6, not public.confirmar_codigo_email('000000') or (select codigo from c) = '000000', 'código errado é recusado';
insert into r select 7, public.confirmar_codigo_email((select codigo from c)), 'código certo é aceite';
insert into r select 8, private.sessao_reforcada(), 'a sessão fica reforçada (abre a sessão da empresa)';
insert into r select 9, not public.confirmar_codigo_email((select codigo from c)), 'o código só se usa uma vez';
do $$ begin perform public.servico_codigo_email_criar('11111111-1111-1111-1111-111111111111','aaaaaaaa-0000-0000-0000-00000000000a'); insert into r values (10, false, 'utilizador não cria códigos');
exception when insufficient_privilege then insert into r values (10, true, 'utilizador não cria códigos'); end $$;
reset role;

-- 5 tentativas erradas bloqueiam o código
delete from c; insert into c select codigo from public.servico_codigo_email_criar('11111111-1111-1111-1111-111111111111','aaaaaaaa-0000-0000-0000-00000000000a');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","session_id":"aaaaaaaa-0000-0000-0000-00000000000a"}', true);
do $$ begin for i in 1..5 loop perform public.confirmar_codigo_email(case when (select codigo from c) = '111111' then '222222' else '111111' end); end loop; end $$;
insert into r select 11, not public.confirmar_codigo_email((select codigo from c)), 'depois de 5 tentativas erradas o código deixa de valer';

-- notificações: a administração marca como lida; ninguém faz TRUNCATE
select set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated","aal":"aal2"}', true);
update notificacoes set lida_em = now() where id = 'b0000000-0000-0000-0000-000000000001';
insert into r select 12, (select lida_em is not null from notificacoes where id = 'b0000000-0000-0000-0000-000000000001'), 'a administração marca a notificação como lida';
do $$ begin execute 'truncate notificacoes'; insert into r values (13, false, 'utilizador não pode esvaziar tabelas');
exception when insufficient_privilege then insert into r values (13, true, 'utilizador não pode esvaziar tabelas'); end $$;
reset role;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

-- Testes da v85: código de reserva para quando não há acesso ao telemóvel. Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('22222222-2222-2222-2222-222222222222','dono@luso.pt'), ('44444444-4444-4444-4444-444444444444','outro@luso.pt');
insert into empresas (id, nome, nif, email, estado) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Luso','509999990','g@luso.pt','aprovada');
insert into empresa_segredos (empresa_id, segredo_hash) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', extensions.crypt('EmpresaLuso2026', extensions.gen_salt('bf')));
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Dono','dono@luso.pt','admin_empresa');
create temp table r (n int, ok boolean, nome text); create temp table c (v text); grant all on r, c to authenticated;
set local role authenticated;
-- 1. Sem telemóvel confirmado não se gera código
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","aal":"aal1","session_id":"11111111-0000-0000-0000-000000000001"}', true);
do $$ begin perform public.gerar_codigo_reserva(); insert into r values (1, false, 'gerar exige aal2');
exception when others then insert into r values (1, sqlerrm like 'MFA_NECESSARIO%', 'gerar exige aal2'); end $$;
-- 2. Com o telemóvel confirmado gera um código XXXX-XXXX-XXXX-XXXX
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","aal":"aal2","session_id":"11111111-0000-0000-0000-000000000000"}', true);
insert into c select public.gerar_codigo_reserva();
insert into r select 2, v ~ '^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$', 'código gerado no formato certo' from c;
insert into r select 3, (select tem from public.estado_codigo_reserva()), 'estado mostra que existe código';
-- Nova sessão só com palavra-passe (aal1)
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","aal":"aal1","session_id":"11111111-0000-0000-0000-000000000001"}', true);
insert into r select 4, (x).mensagem = 'MFA_NECESSARIO', 'sem código: a empresa pede o 2.º passo' from (select public.abrir_sessao_empresa('Luso','509999990','EmpresaLuso2026') x) t;
insert into r select 5, not public.usar_codigo_reserva('AAAA-BBBB-CCCC-DDDD'), 'código errado recusado';
insert into r select 6, not private.aal2(), 'código errado não reforça a sessão';
insert into r select 7, public.usar_codigo_reserva(lower(replace(v, '-', ' '))), 'código certo aceite (minúsculas/espaços)' from c;
insert into r select 8, (x).ok, 'com o código de reserva abre a sessão da empresa' from (select public.abrir_sessao_empresa('Luso','509999990','EmpresaLuso2026') x) t;
insert into r select 9, private.minha_empresa() is not null, 'vê os dados da empresa';
do $$ begin perform public.gerar_codigo_reserva(); insert into r values (10, false, 'com código de reserva não se troca o código');
exception when others then insert into r values (10, true, 'com código de reserva não se troca o código'); end $$;
-- 11. O reforço é só desta sessão
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","aal":"aal1","session_id":"11111111-0000-0000-0000-000000000002"}', true);
insert into r select 11, not private.aal2(), 'outra sessão não fica reforçada';
-- 12. Outro utilizador não usa o código de outra pessoa
select set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","aal":"aal1","session_id":"11111111-0000-0000-0000-000000000003"}', true);
insert into r select 12, not public.usar_codigo_reserva(v), 'código não serve a outro utilizador' from c;
-- 13. Limite de tentativas
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","aal":"aal1","session_id":"11111111-0000-0000-0000-000000000004"}', true);
select public.usar_codigo_reserva('ERRADO') from generate_series(1, 6);
insert into r select 13, not public.usar_codigo_reserva(v), 'após várias tentativas até o código certo é bloqueado' from c;
reset role;
insert into r select 14, (select count(*) from codigos_reserva where hash like '$2%') = 1 and not exists (select 1 from codigos_reserva cr, c where cr.hash = c.v), 'guardado só como hash';
insert into r select 15, exists (select 1 from auditoria where acao = 'codigo_reserva_usado') and exists (select 1 from auditoria where acao = 'codigo_reserva_errado')
  and exists (select 1 from auditoria where acao = 'bloqueio_seguranca' and entidade = 'codigos_reserva'), 'usos, erros e bloqueios registados';
insert into r select 16, exists (select 1 from notificacoes where tipo = 'alerta_seguranca' and user_id = '22222222-2222-2222-2222-222222222222'), 'aviso ao dono da conta';
insert into r select 17, public.servico_sessao_reforcada('22222222-2222-2222-2222-222222222222', '11111111-0000-0000-0000-000000000001')
  and not public.servico_sessao_reforcada('22222222-2222-2222-2222-222222222222', '11111111-0000-0000-0000-000000000002'), 'Edge Functions reconhecem a sessão reforçada';
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

-- Testes da v76: prestador criado pela Elolog com código temporário; sem trocar as palavras-passe não acede a nada. Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111','admin@elolog.pt'), ('22222222-2222-2222-2222-222222222222','dono@novo.pt'), ('33333333-3333-3333-3333-333333333333','op@elolog.pt');
insert into administradores_plataforma (user_id, nome, email, papel, ativo) values ('11111111-1111-1111-1111-111111111111','Admin','admin@elolog.pt','admin',true), ('33333333-3333-3333-3333-333333333333','Op','op@elolog.pt','operador',true);
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
do $$ begin perform public.servico_criar_prestador_admin('33333333-3333-3333-3333-333333333333','22222222-2222-2222-2222-222222222222','{"nome":"Novo Lda","nif":"509999990","email":"g@novo.pt"}','Dono','dono@novo.pt','Profissional',true,'ELO-AB12-CD34',now()+interval '72 hours');
  insert into r values (1, false, 'operador da Elolog não cria prestadores'); exception when others then insert into r values (1, true, 'operador da Elolog não cria prestadores'); end $$;
select public.servico_criar_prestador_admin('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222','{"nome":"Novo Lda","nif":"509999990","email":"G@Novo.pt","cidade":"Lisboa"}','Dono','dono@novo.pt','Profissional',true,'ELO-AB12-CD34',now()+interval '72 hours') as emp \gset
insert into r select 2, (select estado = 'aprovada' and email = 'g@novo.pt' from empresas where id = :'emp') and exists (select 1 from subscricoes where empresa_id = :'emp' and estado = 'pendente')
  and exists (select 1 from funcionarios where id = '22222222-2222-2222-2222-222222222222' and papel = 'admin_empresa'), 'empresa aprovada, plano pendente e administrador criados';
insert into r select 3, (select p_empresa from private.verificar_empresa('Novo Lda','509999990','ELO-AB12-CD34')) = :'emp'::uuid, 'o código temporário serve de palavra-passe da empresa';
set local role authenticated;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"22222222-2222-2222-2222-222222222222"}', true);
insert into r select 4, (x).ok, 'abre a sessão da empresa com o código' from (select public.abrir_sessao_empresa('Novo Lda','509999990','ELO-AB12-CD34') x) t;
insert into r select 5, private.minha_empresa() is null and private.meu_papel() is null, 'com acesso temporário não vê nada da empresa';
insert into r select 6, (public.primeiro_acesso()->>'pendente')::boolean and not (public.primeiro_acesso()->>'expirado')::boolean, 'primeiro_acesso indica pendente';
reset role;
do $$ begin perform public.servico_concluir_primeiro_acesso('22222222-2222-2222-2222-222222222222','curta'); insert into r values (7, false, 'palavra-passe da empresa curta recusada');
  exception when others then insert into r values (7, true, 'palavra-passe da empresa curta recusada'); end $$;
select public.servico_renovar_acesso_temporario('11111111-1111-1111-1111-111111111111', :'emp', 'ELO-ZZ99-YY88', now()+interval '72 hours');
insert into r select 8, (select segredo_hash = extensions.crypt('ELO-ZZ99-YY88', segredo_hash) from empresa_segredos where empresa_id = :'emp'), 'reenviar troca o código da empresa';
select public.servico_concluir_primeiro_acesso('22222222-2222-2222-2222-222222222222','EmpresaNova2026');
insert into r select 9, not exists (select 1 from acessos_temporarios) and (select segredo_hash = extensions.crypt('EmpresaNova2026', segredo_hash) from empresa_segredos where empresa_id = :'emp'), 'concluir troca a palavra-passe da empresa e termina o acesso temporário';
set local role authenticated;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"22222222-2222-2222-2222-222222222222"}', true);
insert into r select 10, private.minha_empresa() = :'emp'::uuid and not (public.primeiro_acesso()->>'pendente')::boolean, 'depois de concluir já acede à empresa';
do $$ begin perform public.acessos_temporarios_pendentes(); insert into r values (11, false, 'só a equipa Elolog lista os pendentes');
  exception when others then insert into r values (11, true, 'só a equipa Elolog lista os pendentes'); end $$;
reset role;
insert into acessos_temporarios (user_id, empresa_id, expira_em) values ('22222222-2222-2222-2222-222222222222', :'emp', now() - interval '1 minute');
do $$ begin perform public.servico_concluir_primeiro_acesso('22222222-2222-2222-2222-222222222222','EmpresaNova2027'); insert into r values (12, false, 'código expirado não conclui');
  exception when others then insert into r values (12, true, 'código expirado não conclui'); end $$;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

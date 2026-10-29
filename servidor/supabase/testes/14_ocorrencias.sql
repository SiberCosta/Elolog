-- Testes da v77: ocorrências, suspensão e manifesto opcional. Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('22222222-2222-2222-2222-222222222222','dono@luso.pt'), ('33333333-3333-3333-3333-333333333333','fin@luso.pt'), ('55555555-5555-5555-5555-555555555555','cli@x.pt'), ('66666666-6666-6666-6666-666666666666','outro@x.pt');
insert into clientes (id, nome, email) values ('55555555-5555-5555-5555-555555555555','Maria','cli@x.pt'), ('66666666-6666-6666-6666-666666666666','Outro','outro@x.pt');
insert into empresas (id, nome, nif, email, estado) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Luso','500000000','g@luso.pt','aprovada');
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Dono','dono@luso.pt','admin_empresa'),
  ('33333333-3333-3333-3333-333333333333','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Fin','fin@luso.pt','financeiro');
insert into sessoes_empresa (user_id, empresa_id, valida_ate) values ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', now()+interval '1 hour'), ('33333333-3333-3333-3333-333333333333','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', now()+interval '1 hour');
insert into encomendas (empresa_id, cliente_id, origem, destino, codigo) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','55555555-5555-5555-5555-555555555555','Lisboa','São Tomé','ELO_LUSO-000001');
select set_config('elolog.transicao','on',false); update encomendas set estado = 'expedicao'; select set_config('elolog.transicao','off',false);
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
set local role authenticated;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"55555555-5555-5555-5555-555555555555"}', true);
select public.ocorrencia_criar('ELO_LUSO-000001', 'Caixa chegou amolgada', 'perda', 'critica', true, false);
insert into r select 1, (x->'lista'->0->>'do_cliente')::boolean and x->'lista'->0->>'tipo' = 'outro' and not (x->>'suspensa')::boolean, 'cliente comunica (sem classificar nem suspender)' from (select public.ocorrencias_da_encomenda('ELO_LUSO-000001') x) t;
do $$ begin perform public.encomenda_suspender('ELO_LUSO-000001','x x x'); insert into r values (2,false,'cliente não suspende'); exception when others then insert into r values (2,true,'cliente não suspende'); end $$;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"22222222-2222-2222-2222-222222222222"}', true);
select public.ocorrencia_criar('ELO_LUSO-000001', 'Falta a fatura comercial', 'documentacao', 'alta', true, false) as oc \gset
insert into r select 3, (x->>'suspensa')::boolean and jsonb_array_length(x->'lista') = 2 and (x->>'pode_gerir')::boolean, 'empresa regista e suspende' from (select public.ocorrencias_da_encomenda('ELO_LUSO-000001') x) t;
do $$ begin perform public.transitar_encomenda((select id from encomendas), 'em_transito'); insert into r values (4,false,'suspensa não avança'); exception when others then insert into r values (4, sqlerrm like '%suspensa%','suspensa não avança'); end $$;
do $$ begin perform public.ocorrencia_atualizar((public.ocorrencias_da_encomenda('ELO_LUSO-000001')->'lista'->0->>'id')::uuid, 'resolvida'); insert into r values (5,false,'resolver exige resolução'); exception when others then insert into r values (5,true,'resolver exige resolução'); end $$;
select public.ocorrencia_atualizar((public.ocorrencias_da_encomenda('ELO_LUSO-000001')->'lista'->0->>'id')::uuid, 'resolvida', null, null, '22222222-2222-2222-2222-222222222222', 'Cliente enviou a fatura', true, 'ok');
select public.encomenda_retomar('ELO_LUSO-000001', 'Documentação completa');
insert into r select 6, e = 'em_transito', 'retomada avança para trânsito sem manifesto' from (select (public.transitar_encomenda((select id from encomendas), 'em_transito')).estado e) t;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"55555555-5555-5555-5555-555555555555"}', true);
insert into r select 7, jsonb_array_length(x->'lista') = 2 and x->'lista'->0->'registos' = '[]'::jsonb, 'cliente vê as comunicadas, sem notas internas' from (select public.ocorrencias_da_encomenda('ELO_LUSO-000001') x) t;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"66666666-6666-6666-6666-666666666666"}', true);
do $$ begin perform public.ocorrencias_da_encomenda('ELO_LUSO-000001'); insert into r values (8,false,'outro cliente não vê'); exception when others then insert into r values (8,true,'outro cliente não vê'); end $$;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"33333333-3333-3333-3333-333333333333"}', true);
do $$ begin perform public.ocorrencia_criar('ELO_LUSO-000001','teste de fin'); insert into r values (9,false,'financeiro só consulta'); exception when others then insert into r values (9,true,'financeiro só consulta'); end $$;
reset role;
insert into r select 10, (select count(*) from encomenda_historico where nota like 'Suspensa%' or nota like 'Retomada%') = 2 and (select count(*) from notificacoes where user_id = '55555555-5555-5555-5555-555555555555') >= 3
  and (select codigo from ocorrencias order by created_at limit 1) ~ '^ELO_OC-\d{6}$', 'histórico, avisos ao cliente e código ELO_OC';
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

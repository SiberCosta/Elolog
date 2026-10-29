-- Testes da v74: espaço de ficheiros por plano (medição, limite, bloqueio de envios e avisos). Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
grant select, insert on storage.objects to authenticated;   -- no Supabase real já existe
insert into auth.users (id, email) values ('22222222-2222-2222-2222-222222222222','dono@luso.pt'), ('55555555-5555-5555-5555-555555555555','cli@x.pt'), ('99999999-9999-9999-9999-999999999999','adm@elolog.pt');
insert into clientes (id, nome, email) values ('55555555-5555-5555-5555-555555555555','Cliente','cli@x.pt');
insert into empresas (id, nome, nif, email, estado) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Luso','500000000','g@luso.pt','aprovada'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Tejo','500000001','g@tejo.pt','aprovada');
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Dono','dono@luso.pt','admin_empresa');
insert into sessoes_empresa (user_id, empresa_id, valida_ate) values ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', now() + interval '1 hour');
insert into subscricoes (empresa_id, plano_id, estado, valor) select 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', id, 'ativa', 79 from planos where nome = 'Profissional';
insert into subscricoes (empresa_id, plano_id, estado, valor) select 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', id, 'ativa', 0 from planos where nome = 'Empresarial';
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
insert into r select 1, private.espaco_limite_empresa('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') = 20::bigint * 1073741824, 'Profissional = 20 GB';
insert into r select 2, private.espaco_limite_empresa('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') = 50::bigint * 1073741824, 'Empresarial sem valor acordado = 50 GB';
update empresas set armazenamento_gb_acordado = 200 where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
insert into r select 3, private.espaco_limite_empresa('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb') = 200::bigint * 1073741824, 'valor acordado manda';
insert into storage.objects (bucket_id, name, metadata) values ('documentos','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/a.pdf','{"size": 15000000000}'),
  ('documentos','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/b.pdf','{"size": 2000000000}'), ('documentos','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/c.pdf','{"size": 5}');
insert into r select 4, private.espaco_usado('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') = 17000000000, 'soma só a pasta da empresa';
set local role authenticated;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"22222222-2222-2222-2222-222222222222"}', true);
insert into r select 5, (x->>'percentagem')::int = 79 and x->>'tipo' = 'empresa', 'espaço da empresa (79 %)' from (select public.espaco_ficheiros() x) t;
insert into storage.objects (bucket_id, name, metadata) values ('documentos','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/d.pdf','{"size": 3000000000}');
insert into r select 6, true, 'abaixo do limite: envio aceite';
insert into r select 7, (x->>'percentagem')::int = 93, 'agora 93 %' from (select public.espaco_ficheiros() x) t;
select public.espaco_ficheiros();
reset role;
insert into r select 8, (select count(*) from notificacoes where empresa_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and tipo = 'espaco') = 1, 'aviso dos 80 % só uma vez';
update storage.objects set metadata = '{"size": 19000000000}' where name like '%/d.pdf';
set local role authenticated;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"22222222-2222-2222-2222-222222222222"}', true);
do $$ begin insert into storage.objects (bucket_id, name, metadata) values ('documentos','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/e.pdf','{"size": 10}'); insert into r values (9, false, 'no limite: envio bloqueado');
  exception when insufficient_privilege then insert into r values (9, true, 'no limite: envio bloqueado'); end $$;
select public.espaco_ficheiros();
reset role;
insert into r select 10, exists (select 1 from notificacoes where para_plataforma and tipo = 'espaco') and exists (select 1 from notificacoes where empresa_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and titulo = 'Espaço de ficheiros esgotado'), 'aviso dos 100 % à empresa e à Elolog';
set local role authenticated;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"55555555-5555-5555-5555-555555555555"}', true);
insert into storage.objects (bucket_id, name, metadata) values ('documentos','55555555-5555-5555-5555-555555555555/f.pdf','{"size": 100}');
insert into r select 11, (x->>'tipo') = 'cliente' and (x->>'limite')::bigint = 1073741824 and (x->>'usado')::bigint = 100, 'cliente: 1 GB' from (select public.espaco_ficheiros() x) t;
do $$ begin perform public.espaco_empresas(); insert into r values (12, false, 'só a equipa Elolog vê todas as empresas');
  exception when others then insert into r values (12, true, 'só a equipa Elolog vê todas as empresas'); end $$;
reset role;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

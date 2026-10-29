-- Testes da v71: grupos no chat da equipa. Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111','admin@elolog.pt'), ('12121212-1212-1212-1212-121212121212','ana@elolog.pt'),
 ('22222222-2222-2222-2222-222222222222','dono@luso.pt'), ('33333333-3333-3333-3333-333333333333','op@luso.pt'), ('35353535-3535-3535-3535-353535353535','fin@luso.pt'),
 ('44444444-4444-4444-4444-444444444444','dono@tejo.pt');
insert into administradores_plataforma (user_id, nome, email, papel, ativo) values ('11111111-1111-1111-1111-111111111111','Admin','admin@elolog.pt','admin',true),
 ('12121212-1212-1212-1212-121212121212','Ana','ana@elolog.pt','operador',true);
insert into empresas (id, nome, nif, email) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Luso','500000000','g@luso.pt'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Tejo','500000001','g@tejo.pt');
insert into funcionarios (id, empresa_id, nome, email, papel) values
 ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Dono','dono@luso.pt','admin_empresa'),
 ('33333333-3333-3333-3333-333333333333','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Op','op@luso.pt','operador'),
 ('35353535-3535-3535-3535-353535353535','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Fin','fin@luso.pt','financeiro'),
 ('44444444-4444-4444-4444-444444444444','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Dono T','dono@tejo.pt','admin_empresa');
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated; create temp table g (id uuid); grant all on g to authenticated;
set local role authenticated;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"33333333-3333-3333-3333-333333333333"}', true);
insert into g select chat_grupo_criar('Recolhas Leixões', array['35353535-3535-3535-3535-353535353535','44444444-4444-4444-4444-444444444444','11111111-1111-1111-1111-111111111111']::uuid[]);
insert into r select 1, (select membros from chat_grupos() where id = (select id from g)) = 2, 'grupo só com colegas da mesma empresa';
select chat_grupo_enviar((select id from g), 'Bom dia equipa') is not null;
reset role; update chat_grupo_membros set lido_ate = lido_ate - interval '1 second' where user_id <> '33333333-3333-3333-3333-333333333333'; set local role authenticated;   -- na mesma transação now() não avança
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"35353535-3535-3535-3535-353535353535"}', true);
insert into r select 2, chat_por_ler() = 1 and (select por_ler from chat_grupos()) = 1, 'mensagem do grupo chega por ler';
create temp table c2 as select * from chat_grupo_conversa((select id from g));
insert into r select 3, (select count(*) from c2) = 1 and (select nome_de from c2) = 'Op' and chat_por_ler() = 0, 'abrir o grupo marca como lido';
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"44444444-4444-4444-4444-444444444444"}', true);
do $$ begin perform chat_grupo_conversa((select id from g)); insert into r values (4, false, 'outra empresa não lê o grupo');
  exception when others then insert into r values (4, true, 'outra empresa não lê o grupo'); end $$;
insert into r select 5, (select count(*) from chat_grupos()) = 0, 'outra empresa não vê o grupo';
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"11111111-1111-1111-1111-111111111111"}', true);
insert into r select 6, (select count(*) from chat_grupos()) = 0 and (select count(*) from chat_contactos()) = 1, 'administração da plataforma não vê o chat do prestador';
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"35353535-3535-3535-3535-353535353535"}', true);
select chat_grupo_adicionar((select id from g), array['22222222-2222-2222-2222-222222222222']::uuid[]);
insert into r select 7, (select membros from chat_grupos()) = 3, 'qualquer membro adiciona colegas';
select chat_grupo_sair((select id from g));
insert into r select 8, (select count(*) from chat_grupos()) = 0, 'sair do grupo';
do $$ begin perform chat_grupo_enviar((select id from g), 'x'); insert into r values (9, false, 'quem saiu já não escreve');
  exception when others then insert into r values (9, true, 'quem saiu já não escreve'); end $$;
reset role;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

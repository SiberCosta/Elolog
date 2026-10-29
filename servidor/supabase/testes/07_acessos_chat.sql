-- Testes da v70: acessos às caixas de email por funcionário e chat interno com hierarquia (precisa de 00138 a 00141). Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values
 ('11111111-1111-1111-1111-111111111111','admin@elolog.pt'), ('12121212-1212-1212-1212-121212121212','ana@elolog.pt'),
 ('22222222-2222-2222-2222-222222222222','dono@luso.pt'), ('33333333-3333-3333-3333-333333333333','op@luso.pt'),
 ('34343434-3434-3434-3434-343434343434','terreno@luso.pt'), ('35353535-3535-3535-3535-353535353535','fin@luso.pt'),
 ('36363636-3636-3636-3636-363636363636','arm@luso.pt'), ('44444444-4444-4444-4444-444444444444','dono@tejo.pt');
insert into administradores_plataforma (user_id, nome, email, papel, ativo) values ('11111111-1111-1111-1111-111111111111','Admin','admin@elolog.pt','admin',true),
 ('12121212-1212-1212-1212-121212121212','Ana','ana@elolog.pt','operador',true);
insert into empresas (id, nome, nif, email) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Luso','500000000','g@luso.pt'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Tejo','500000001','g@tejo.pt');
insert into funcionarios (id, empresa_id, nome, email, papel) values
 ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Dono','dono@luso.pt','admin_empresa'),
 ('33333333-3333-3333-3333-333333333333','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Op','op@luso.pt','operador'),
 ('34343434-3434-3434-3434-343434343434','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Ter','terreno@luso.pt','operador_terreno'),
 ('35353535-3535-3535-3535-353535353535','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Fin','fin@luso.pt','financeiro'),
 ('36363636-3636-3636-3636-363636363636','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Arm','arm@luso.pt','armazem'),
 ('44444444-4444-4444-4444-444444444444','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Dono T','dono@tejo.pt','admin_empresa');
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
do $$ declare ce uuid; cl uuid; ok boolean;
  ad uuid := '11111111-1111-1111-1111-111111111111'; ana uuid := '12121212-1212-1212-1212-121212121212'; dono uuid := '22222222-2222-2222-2222-222222222222';
  op uuid := '33333333-3333-3333-3333-333333333333'; ter uuid := '34343434-3434-3434-3434-343434343434'; fin uuid := '35353535-3535-3535-3535-353535353535';
  arm uuid := '36363636-3636-3636-3636-363636363636'; tejo uuid := '44444444-4444-4444-4444-444444444444';
begin
  ce := (servico_email_gravar(ad, null, '{"email":"contacto@elolog.pt","imap_host":"imap.correio.pt","smtp_host":"smtp.correio.pt","utilizador":"contacto@elolog.pt"}', 's1')->>'id')::uuid;
  cl := (servico_email_gravar(dono, null, '{"email":"ops@luso.pt","imap_host":"imap.luso.pt","smtp_host":"smtp.luso.pt","utilizador":"ops@luso.pt"}', 's2')->>'id')::uuid;
  insert into r values (1, jsonb_array_length(servico_email_caixas(ana)) = 0 and not (servico_email_acesso(ana)->>'delegado')::boolean, 'sem acesso antes de conceder');
  begin perform servico_email_conceder(ana, ce, ana, true); ok := false; exception when others then ok := true; end; insert into r values (2, ok, 'operador não concede acessos');
  perform servico_email_conceder(ad, ce, ana, true);
  insert into r values (3, (servico_email_acesso(ana)->>'delegado')::boolean and servico_email_caixas(ana)->0->>'email' = 'contacto@elolog.pt'
    and not (servico_email_caixas(ana)->0->>'gerir')::boolean and servico_email_credenciais(ana, ce)->>'senha' = 's1', 'acesso concedido: vê e usa, não gere');
  begin perform servico_email_gravar(ana, ce, '{"email":"contacto@elolog.pt","imap_host":"x.pt","smtp_host":"x.pt","utilizador":"u"}', null); ok := false; exception when others then ok := true; end;
  insert into r values (4, ok, 'funcionário com acesso não altera a caixa');
  begin perform servico_email_remover(ana, ce); ok := false; exception when others then ok := true; end; insert into r values (5, ok, 'nem a remove');
  insert into r values (6, (select count(*) from jsonb_array_elements(servico_email_acessos(ad, ce)) x where (x->>'acesso')::boolean) = 1, 'lista de acessos');
  perform servico_email_conceder(ad, ce, ana, false); insert into r values (7, jsonb_array_length(servico_email_caixas(ana)) = 0, 'retirar acesso');
  begin perform servico_email_conceder(dono, cl, tejo, true); ok := false; exception when others then ok := sqlerrm like '%não pertence%'; end; insert into r values (8, ok, 'não concede a outra empresa');
  perform servico_email_conceder(dono, cl, op, true); insert into r values (9, servico_email_credenciais(op, cl)->>'email' = 'ops@luso.pt', 'prestador: operador com acesso');
  begin perform servico_email_credenciais(ter, cl); ok := false; exception when others then ok := true; end; insert into r values (10, ok, 'colega sem acesso não lê');
  update funcionarios set ativo = false where id = op; insert into r values (11, jsonb_array_length(servico_email_caixas(op)) = 0, 'inativo perde acesso');
  update funcionarios set ativo = true where id = op;
  insert into r values (12, private.chat_pode(ad, ana) and not private.chat_pode(ad, dono) and not private.chat_pode(ana, dono) and not private.chat_pode(ana, op), 'Elolog só fala entre si (não com prestadores)');
  insert into r values (13, private.chat_pode(op, ter) and private.chat_pode(arm, ter) and private.chat_pode(fin, dono) and private.chat_pode(fin, ter) and private.chat_pode(ter, ter) = false, 'no prestador todos falam com todos');
  insert into r values (14, not private.chat_pode(dono, tejo) and not private.chat_pode(op, op), 'empresas diferentes e o próprio não');
end $$;
do $$ declare ce uuid := (select id from caixas_email where email = 'contacto@elolog.pt'); cl uuid := (select id from caixas_email where email = 'ops@luso.pt'); ok boolean;
  ad uuid := '11111111-1111-1111-1111-111111111111'; ana uuid := '12121212-1212-1212-1212-121212121212'; op uuid := '33333333-3333-3333-3333-333333333333';
  ter uuid := '34343434-3434-3434-3434-343434343434'; tejo uuid := '44444444-4444-4444-4444-444444444444';
begin
  perform servico_email_atribuir(ad, ce, 42, ana, 'Cliente <c@x.pt>', 'Pedido de cotação', 'Responde tu, por favor');
  insert into r values (21, (servico_email_credenciais2(ana, ce, 42)->>'restrito')::boolean and (servico_email_acesso(ana)->>'delegado')::boolean, 'atribuído: abre só esse email');
  begin perform servico_email_credenciais2(ana, ce, 43); ok := false; exception when others then ok := true; end; insert into r values (22, ok, 'outro email da caixa continua fechado');
  insert into r values (23, servico_email_atribuidos(ana)->0->>'assunto' = 'Pedido de cotação' and exists (select 1 from chat_mensagens where de = ad and para = ana and texto like '%Pedido de cotação%'), 'lista de atribuídos e aviso no chat');
  perform servico_email_respondido(ana, ce, 42); insert into r values (24, servico_email_atribuidos(ana)->0->>'estado' = 'respondido', 'marcado como respondido');
  begin perform servico_email_atribuir(op, cl, 7, tejo, '', '', ''); ok := false; exception when others then ok := true; end; insert into r values (25, ok, 'não encaminha para outra empresa');
  perform servico_email_atribuir(op, cl, 7, ter, 'x', 'Entrega', null); insert into r values (26, (servico_email_credenciais2(ter, cl, 7)->>'restrito')::boolean
    and jsonb_array_length(servico_email_equipa(op, cl)) = 4, 'prestador: operador encaminha ao terreno');
end $$;
-- como utilizadores reais (papel authenticated)
set local role authenticated;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"33333333-3333-3333-3333-333333333333"}', true);
select chat_enviar('34343434-3434-3434-3434-343434343434', 'Recolha às 10h em Leixões') is not null;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"34343434-3434-3434-3434-343434343434"}', true);
insert into r select 15, chat_por_ler() = 2, 'mensagem chega por ler';
create temp table c16 as select count(*) n from chat_conversa('33333333-3333-3333-3333-333333333333');
insert into r select 16, (select n from c16) = 2 and chat_por_ler() = 0, 'abrir conversa marca como lida';
insert into r select 17, (select count(*) from chat_contactos() where user_id = '35353535-3535-3535-3535-353535353535') = 1
  and (select por_ler from chat_contactos() where user_id = '33333333-3333-3333-3333-333333333333') = 0, 'contactos: toda a empresa';
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"35353535-3535-3535-3535-353535353535"}', true);
do $$ begin perform chat_enviar('34343434-3434-3434-3434-343434343434', 'olá'); insert into r values (18, true, 'financeiro fala com o terreno');
  exception when others then insert into r values (18, false, 'financeiro fala com o terreno'); end $$;
do $$ begin perform 1 from chat_mensagens; insert into r values (19, false, 'tabela fechada à API');
  exception when insufficient_privilege then insert into r values (19, true, 'tabela fechada à API'); end $$;
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"22222222-2222-2222-2222-222222222222"}', true);
insert into r select 20, (select count(*) from chat_contactos() where organizacao = 'Elolog') = 0 and (select count(*) from chat_contactos()) = 4, 'admin do prestador vê só a sua equipa';
reset role;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

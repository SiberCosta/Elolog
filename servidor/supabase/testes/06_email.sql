-- Testes da v67 (painel de email): permissões e cofre das caixas. Só numa base de TESTES já instalada (não em produção); tudo é desfeito no fim.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111','admin@elolog.pt'), ('22222222-2222-2222-2222-222222222222','dono@luso.pt'),
  ('33333333-3333-3333-3333-333333333333','op@luso.pt'), ('44444444-4444-4444-4444-444444444444','dono@tejo.pt');
insert into administradores_plataforma (user_id, nome, email, papel, ativo) values ('11111111-1111-1111-1111-111111111111','Admin','admin@elolog.pt','admin',true);
insert into empresas (id, nome, nif, email) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Luso','500000000','geral@luso.pt'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Tejo','500000001','geral@tejo.pt');
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Dono','dono@luso.pt','admin_empresa'),
  ('33333333-3333-3333-3333-333333333333','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Op','op@luso.pt','operador'), ('44444444-4444-4444-4444-444444444444','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Dono T','dono@tejo.pt','admin_empresa');
create temp table r (n int, ok boolean, nome text); create temp table v (k text, val text);
do $$ declare j jsonb; c1 uuid; c2 uuid; ok boolean; s uuid;
begin
  j := servico_email_acesso('11111111-1111-1111-1111-111111111111'); insert into r values (1, (j->>'plataforma')::boolean and j->'empresa' = 'null'::jsonb, 'admin da plataforma');
  j := servico_email_acesso('22222222-2222-2222-2222-222222222222'); insert into r values (2, not (j->>'plataforma')::boolean and j->>'empresa' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'admin do prestador');
  j := servico_email_acesso('33333333-3333-3333-3333-333333333333'); insert into r values (3, not (j->>'plataforma')::boolean and j->'empresa' = 'null'::jsonb, 'operador sem acesso');
  c1 := (servico_email_gravar('11111111-1111-1111-1111-111111111111', null, '{"email":"Contacto@Elolog.pt","nome":"Elolog","imap_host":"imap.correio.pt","smtp_host":"smtp.correio.pt","utilizador":"contacto@elolog.pt"}', 'S3nha!')->>'id')::uuid;
  c2 := (servico_email_gravar('22222222-2222-2222-2222-222222222222', null, '{"email":"ops@luso.pt","imap_host":"imap.luso.pt","smtp_host":"smtp.luso.pt","utilizador":"ops@luso.pt","ambito":"elolog"}', 'luso-1')->>'id')::uuid;
  insert into r select 4, empresa_id is null and email = 'contacto@elolog.pt' and segredo_id is not null, 'caixa Elolog gravada' from caixas_email where id = c1;
  insert into r select 5, empresa_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'prestador não escolhe o âmbito Elolog' from caixas_email where id = c2;
  insert into r values (6, servico_email_credenciais('11111111-1111-1111-1111-111111111111', c1)->>'senha' = 'S3nha!' and (servico_email_credenciais('11111111-1111-1111-1111-111111111111', c1)->>'elolog')::boolean, 'credenciais do cofre');
  insert into r values (7, jsonb_array_length(servico_email_caixas('22222222-2222-2222-2222-222222222222')) = 1 and servico_email_caixas('22222222-2222-2222-2222-222222222222')->0->>'email' = 'ops@luso.pt'
    and not (servico_email_caixas('22222222-2222-2222-2222-222222222222')->0 ? 'senha'), 'lista só da empresa, sem senha');
  insert into r values (8, jsonb_array_length(servico_email_caixas('44444444-4444-4444-4444-444444444444')) = 0 and jsonb_array_length(servico_email_caixas('33333333-3333-3333-3333-333333333333')) = 0, 'outros não veem');
  begin perform servico_email_credenciais('44444444-4444-4444-4444-444444444444', c2); ok := false; exception when others then ok := sqlerrm = 'Caixa de email inexistente.'; end; insert into r values (9, ok, 'outra empresa não lê credenciais');
  begin perform servico_email_credenciais('22222222-2222-2222-2222-222222222222', c1); ok := false; exception when others then ok := true; end; insert into r values (10, ok, 'prestador não lê caixa Elolog');
  begin perform servico_email_gravar('33333333-3333-3333-3333-333333333333', null, '{"email":"x@luso.pt","imap_host":"imap.luso.pt","smtp_host":"smtp.luso.pt","utilizador":"x"}', 'x'); ok := false;
    exception when others then ok := sqlerrm like 'Sem permissão%'; end; insert into r values (11, ok, 'operador não grava');
  begin perform servico_email_gravar('22222222-2222-2222-2222-222222222222', null, '{"email":"OPS@luso.pt","imap_host":"imap.luso.pt","smtp_host":"smtp.luso.pt","utilizador":"ops"}', 'x'); ok := false;
    exception when others then ok := sqlerrm like '%já está configurada%'; end; insert into r values (12, ok, 'duplicada recusada');
  begin perform servico_email_gravar('22222222-2222-2222-2222-222222222222', null, '{"email":"novo@luso.pt","imap_host":"imap.luso.pt","smtp_host":"smtp.luso.pt","utilizador":"n"}', null); ok := false;
    exception when others then ok := sqlerrm like '%palavra-passe%'; end; insert into r values (13, ok, 'nova sem senha recusada');
  perform servico_email_gravar('22222222-2222-2222-2222-222222222222', c2, '{"email":"ops@luso.pt","nome":"Operações","imap_host":"mail.luso.pt","smtp_host":"mail.luso.pt","utilizador":"ops@luso.pt"}', null);
  insert into r values (14, servico_email_credenciais('22222222-2222-2222-2222-222222222222', c2)->>'senha' = 'luso-1' and servico_email_credenciais('22222222-2222-2222-2222-222222222222', c2)->>'imap_host' = 'mail.luso.pt', 'editar mantém senha');
  perform servico_email_gravar('22222222-2222-2222-2222-222222222222', c2, '{"email":"ops@luso.pt","imap_host":"mail.luso.pt","smtp_host":"mail.luso.pt","utilizador":"ops@luso.pt"}', 'nova-2');
  insert into r values (15, servico_email_credenciais('22222222-2222-2222-2222-222222222222', c2)->>'senha' = 'nova-2' and (select count(*) from vault.secrets where name like 'email_caixa_%') = 2, 'trocar senha sem duplicar segredo');
  begin perform servico_email_gravar('22222222-2222-2222-2222-222222222222', null, '{"email":"a@luso.pt","imap_host":"imap luso","smtp_host":"smtp.luso.pt","utilizador":"a"}', 'x'); ok := false;
    exception when others then ok := true; end; insert into r values (16, ok, 'servidor inválido recusado');
  select segredo_id into s from caixas_email where id = c2;
  begin perform servico_email_remover('44444444-4444-4444-4444-444444444444', c2); ok := false; exception when others then ok := true; end; insert into r values (17, ok, 'outra empresa não remove');
  perform servico_email_remover('22222222-2222-2222-2222-222222222222', c2);
  insert into r values (18, not exists (select 1 from caixas_email where id = c2) and not exists (select 1 from vault.secrets where id = s), 'remover apaga o segredo');
  delete from empresas where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  update funcionarios set ativo = false where id = '22222222-2222-2222-2222-222222222222';
  insert into r values (19, (servico_email_acesso('22222222-2222-2222-2222-222222222222')->'empresa') = 'null'::jsonb, 'funcionário inativo perde acesso');
end $$;
insert into r select 20, not has_function_privilege('authenticated', 'public.servico_email_credenciais(uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.servico_email_gravar(uuid,uuid,jsonb,text)', 'execute')
  and not has_table_privilege('authenticated', 'caixas_email', 'select') and has_function_privilege('service_role', 'public.servico_email_credenciais(uuid,uuid)', 'execute'), 'só a chave de serviço';
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

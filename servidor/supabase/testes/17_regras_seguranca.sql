-- Testes da v84: regras de segurança obrigatórias (auditoria, ficheiros, limites). Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('44444444-4444-4444-4444-444444444444','cli@x.pt'), ('55555555-5555-5555-5555-555555555555','outro@x.pt');
insert into clientes (id, nome, email) values ('44444444-4444-4444-4444-444444444444','Cli','cli@x.pt'), ('55555555-5555-5555-5555-555555555555','Outro','outro@x.pt');
insert into storage.objects (bucket_id, name, owner, metadata) values
  ('documentos','44444444-4444-4444-4444-444444444444/1-fatura.pdf','44444444-4444-4444-4444-444444444444','{"mimetype":"application/pdf","size":1000}'),
  ('documentos','44444444-4444-4444-4444-444444444444/2-foto.pdf','44444444-4444-4444-4444-444444444444','{"mimetype":"application/pdf","size":10}'),
  ('documentos','44444444-4444-4444-4444-444444444444/3-virus.exe','44444444-4444-4444-4444-444444444444','{"mimetype":"application/x-msdownload","size":10}');
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
create function pg_temp.falha(q text, padrao text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return sqlerrm like padrao; end $$;
grant execute on function pg_temp.falha(text, text) to authenticated;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}', true);
insert into r select 1, pg_temp.falha($q$insert into documentos (cliente_id, categoria, nome, storage_path, mime, tamanho_bytes) values
  ('44444444-4444-4444-4444-444444444444','cliente','v','44444444-4444-4444-4444-444444444444/3-virus.exe','application/x-msdownload',10)$q$, 'FICHEIRO_RECUSADO: tipo%'), 'ficheiro .exe recusado';
insert into r select 2, pg_temp.falha($q$insert into documentos (cliente_id, categoria, nome, storage_path, mime, tamanho_bytes) values
  ('44444444-4444-4444-4444-444444444444','cliente','f','44444444-4444-4444-4444-444444444444/1-fatura.pdf','image/png',1000)$q$, 'FICHEIRO_RECUSADO: a extensão%'), 'extensão diferente do tipo recusada';
insert into r select 3, pg_temp.falha($q$insert into documentos (cliente_id, categoria, nome, storage_path, mime, tamanho_bytes) values
  ('44444444-4444-4444-4444-444444444444','cliente','f','44444444-4444-4444-4444-444444444444/2-foto.pdf','application/pdf',999)$q$, 'FICHEIRO_RECUSADO: o ficheiro guardado%'), 'tamanho declarado diferente do guardado recusado';
insert into r select 4, pg_temp.falha($q$insert into documentos (cliente_id, categoria, nome, storage_path, mime, tamanho_bytes) values
  ('44444444-4444-4444-4444-444444444444','cliente','f','44444444-4444-4444-4444-444444444444/9-nao-existe.pdf','application/pdf',10)$q$, 'FICHEIRO_RECUSADO: o ficheiro não está%'), 'ficheiro inexistente recusado';
insert into documentos (id, cliente_id, categoria, nome, storage_path, mime, tamanho_bytes, verificado) values
  ('dddddddd-dddd-dddd-dddd-dddddddddddd','44444444-4444-4444-4444-444444444444','cliente','f','44444444-4444-4444-4444-444444444444/1-fatura.pdf','application/pdf',1000, true);
insert into r select 5, not verificado, 'cliente não consegue marcar o ficheiro como verificado' from documentos where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
insert into r select 6, (pg_temp.falha($q$update documentos set verificado = true where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'$q$, '%') or true)
  and not (select verificado from documentos where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'), 'cliente não altera a verificação';
reset role;
insert into r select 7, pg_temp.falha($q$update auditoria set acao = 'x'$q$, 'AUDITORIA_IMUTAVEL%') and pg_temp.falha($q$delete from auditoria$q$, 'AUDITORIA_IMUTAVEL%'), 'auditoria não se altera nem se apaga';
insert into r select 8, exists (select 1 from auditoria where entidade = 'documentos' and acao = 'insert' and entidade_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'), 'envio de documento ficou registado';
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.servico_documento_verificado('dddddddd-dddd-dddd-dddd-dddddddddddd', true, 'assinatura PDF');
insert into r select 9, verificado, 'servidor marca como verificado' from documentos where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
update empresas set nome = nome where false;
insert into r select 10, not exists (select 1 from auditoria where antes ? 'segredo_hash' or depois ? 'segredo_hash' or depois ? 'mb_key'), 'segredos nunca vão para a auditoria';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}', true);
reset role;
create temp table esc (x int); grant all on esc to authenticated;
create trigger limitar_escritas before insert on esc for each row execute function private.limitar_escritas('2');
set local role authenticated;
insert into esc values (1); insert into esc values (2);
insert into r select 11, pg_temp.falha('insert into esc values (3)', 'LIMITE_EXCEDIDO%'), 'acima do limite de escritas: bloqueado';
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.servico_registar_bloqueio('teste', 'limite', null);
insert into r select 12, exists (select 1 from auditoria where acao = 'bloqueio_seguranca' and entidade = 'teste'), 'bloqueio fica registado';
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

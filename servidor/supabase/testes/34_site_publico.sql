-- Elolog · TESTE 34 — Site público (migração 00202, v169): saídas, prestadores, novidades e avisos.
-- Executar depois da migração 00202. Termina com um ERRO de propósito (desfaz tudo). Esperado: RELATORIO 9/9 :: tudo OK
begin;
create temp table r (n int, ok boolean, nome text); grant all on r to anon, authenticated;
set local session_replication_role = replica;
insert into empresas (id, nome, nome_comercial, nif, email, estado, cidade, aprovada_em) values ('a0000000-0000-0000-0000-00000000000a','Prest A Lda','Prest A','500000010','segredo@a.pt','aprovada','Lisboa',now()-interval '5 days'),('b0000000-0000-0000-0000-00000000000b','Prest B','Prest B','500000020','b@x.pt','pendente','Porto',null);
insert into subscricoes (empresa_id, estado, plano_id, valor) select 'a0000000-0000-0000-0000-00000000000a','ativa',(select id from planos limit 1),0;
insert into viagens_maritimas (id, empresa_id, navio, sentido, porto_origem, porto_destino, partida, chegada, fecho_carga, publicada, estado, created_at) values
 ('d0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-00000000000a','Navio Teste','PT-STP','Lisboa','São Tomé',current_date+10,current_date+25,current_date+7,true,'aberta',now()),
 ('d0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-00000000000a','Navio Oculto','PT-STP','Lisboa','Luanda',current_date+12,current_date+30,null,true,'planeada',now()),
 ('d0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-00000000000a','Navio Privado','PT-STP','Lisboa','Praia',current_date+5,null,null,false,'planeada',now()),
 ('d0000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-00000000000b','Navio Pendente','PT-STP','Porto','Bissau',current_date+5,null,null,true,'planeada',now());
set local session_replication_role = origin;
update site_definicoes set valor = jsonb_set(valor,'{ocultas}','["d0000000-0000-0000-0000-000000000002"]') where chave='saidas';
insert into site_publicacoes (tipo, titulo, texto, ativo) values ('aviso','Feriado de Natal','Atendimento fechado a 25/12.',true),('novidade','Nova rota para Cabo Verde','Já disponível.',true),('novidade','Antiga','x',false);
insert into site_publicacoes (tipo, titulo, texto, empresa_id) values ('destaque','Destaque','Especialistas em São Tomé.','a0000000-0000-0000-0000-00000000000a');
create temp table c (j jsonb); grant all on c to anon;
set local role anon;
insert into c select site_conteudo();
reset role;
insert into r select 1, jsonb_array_length(j->'saidas') >= 1 and (j->'saidas') @> '[{"navio":"Navio Teste"}]', 'saída publicada aparece' from c;
insert into r select 2, not ((j->'saidas')::text like '%Navio Oculto%'), 'saída escondida pela administração não aparece' from c;
insert into r select 3, not ((j->'saidas')::text like '%Navio Privado%'), 'saída não publicada pelo prestador não aparece' from c;
insert into r select 4, not (j::text like '%Navio Pendente%') and not (j::text like '%Prest B%'), 'prestador não aprovado nunca aparece' from c;
insert into r select 5, (j->'prestadores') @> '[{"nome":"Prest A","texto":"Especialistas em São Tomé."}]', 'prestador aprovado com destaque' from c;
insert into r select 6, not (j::text like '%segredo@a.pt%') and not (j::text like '%500000010%'), 'sem email nem NIF no conteúdo público' from c;
insert into r select 7, (j->'feed')::text like '%juntou-se à Elolog%' and (j->'feed')::text like '%Nova saída%' and (j->'feed')::text like '%Cabo Verde%' and not ((j->'feed')::text like '%Antiga%'), 'feed automático + manual ativo' from c;
insert into r select 8, (j->'avisos') @> '[{"titulo":"Feriado de Natal"}]', 'aviso ativo' from c;
insert into r select 9, not has_table_privilege('anon','public.site_publicacoes','select') or not exists (select 1 from pg_policies where tablename='site_publicacoes' and 'anon' = any(roles)), 'anónimo não lê a tabela diretamente';
do $rel$ declare t text; begin select count(*) filter (where ok)||'/'||count(*)||' :: '||coalesce(string_agg(case when not ok then n||' '||nome end,' | ' order by n),'tudo OK') into t from r; raise exception 'RELATORIO %', t; end $rel$;

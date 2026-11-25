-- 37: cor do título e logótipos (migrações 00206 e 00207). Corre em rollback.
begin;
do $rel$ declare ok1 boolean; ok2 boolean; c jsonb; begin
 insert into site_publicacoes(tipo,titulo,cor_titulo) values ('novidade','Teste título','#A3271C');
 c := public.site_conteudo();
 begin insert into site_publicacoes(tipo,titulo,cor_titulo) values ('novidade','x x','vermelho'); ok1:=false; exception when check_violation then ok1:=true; end;
 begin insert into prestador_classificacao(empresa_id,logo) select id,'https://exemplo.com/a.png' from empresas limit 1; ok2:=false; exception when check_violation then ok2:=true; end;
 raise exception 'RELATORIO cor_titulo_no_site=% cor_invalida_recusada=% logo_fora_recusado=%', (select x->>'cor_titulo' from jsonb_array_elements(c->'feed') x where x->>'titulo'='Teste título'), ok1, ok2; end $rel$;
-- Resultado na base real (25/11/2026): cor_titulo_no_site=#A3271C cor_invalida_recusada=t logo_fora_recusado=t.
-- Armazenamento «site-publico»: público, 1 MB, PNG/JPEG/WebP; o administrador carrega; outro utilizador é recusado.

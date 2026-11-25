-- 36: anúncios com fundo/público, atualizações da plataforma e classificações (migração 00205). Corre em rollback.
begin;
do $rel$ declare r text := ''; ok boolean; c jsonb;
begin
  begin insert into site_publicacoes(tipo,titulo,fundo) values ('aviso','Fundo inválido','vermelho'); ok := false; exception when check_violation then ok := true; end;
  r := r || ' fundo_inválido_recusado=' || ok;
  insert into site_publicacoes(tipo,titulo,fundo,publico) values ('aviso','Só plataforma','#A3271C','plataforma'),('aviso','No site','#13293D','site');
  c := public.site_conteudo();
  r := r || ' site_vê_só_site=' || (select count(*) = 1 from jsonb_array_elements(c->'avisos') x where x->>'titulo' in ('Só plataforma','No site') and x->>'titulo' = 'No site')
          || ' fundo=' || coalesce((select x->>'fundo' from jsonb_array_elements(c->'avisos') x where x->>'titulo'='No site'), 'nulo');
  r := r || ' sem_sessão_plataforma=' || jsonb_array_length(public.plataforma_avisos());
  begin perform public.avaliar_prestador(gen_random_uuid(), 5); ok := false; exception when others then ok := sqlerrm like 'Inicie sessão%'; end;
  r := r || ' avaliar_sem_sessão_recusado=' || ok;
  begin insert into prestador_classificacao(empresa_id,nivel) values ((select id from empresas limit 1),'diamante'); ok := false; exception when check_violation then ok := true; end;
  r := r || ' nível_inválido_recusado=' || ok;
  r := r || ' prestadores_com_media=' || (select count(*) from jsonb_array_elements(c->'prestadores') x where x ? 'media' and x ? 'nivel');
  raise exception 'RELATORIO%', r;
end $rel$;

-- 35: cores dos anúncios e calendário de saídas (migração 00204). Corre em rollback; não deixa dados.
begin;
insert into site_publicacoes(tipo,titulo,texto,cor) values ('aviso','Teste alerta','x','vermelho'),('aviso','Teste info',null,'azul');
update site_definicoes set valor = valor || '{"calendario":true}' where chave='saidas';
do $rel$ declare c jsonb := public.site_conteudo(); ok boolean := false; begin
  begin insert into site_publicacoes(tipo,titulo,cor) values ('aviso','Cor inválida','roxo'); exception when check_violation then ok := true; end;
  raise exception 'RELATORIO calendario_ativo=% calendario=% 1.º aviso=% (vermelho primeiro) cor inválida recusada=%',
    c->'calendario_ativo', jsonb_array_length(c->'calendario'), c->'avisos'->0->>'cor', ok; end $rel$;
-- Resultado na base real (25/11/2026): calendario_ativo=true calendario=1 1.º aviso=vermelho

-- v120 — Segurança (autorizado em 08/11/2026): caminho de pesquisa fixo nas funções que ainda não o tinham
-- (impede que um objeto com o mesmo nome noutro esquema seja usado em vez do verdadeiro) e fim da integração AIS de navios
-- (a tarefa agendada chamava a função sem chave AISSTREAM_API_KEY e falhava 48 vezes por dia).
alter function private.auditoria_imutavel() set search_path = public;
alter function private.comissao_valor(public.regras_comissao, numeric) set search_path = public;
alter function private.km_linha(numeric, numeric, numeric, numeric) set search_path = public;
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'tipos_ficheiro' loop
    execute format('alter function %s set search_path = public', f);
  end loop;
end $$;
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and exists (select 1 from cron.job where jobname = 'elolog-navios') then
    perform cron.unschedule('elolog-navios');
  end if;
end $$;

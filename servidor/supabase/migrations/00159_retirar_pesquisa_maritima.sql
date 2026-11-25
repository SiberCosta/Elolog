-- v97 — Retirar a Pesquisa marítima e tudo o que lhe pertence (pedido do utilizador).
-- Não toca nas outras tabelas, nos dados da Elolog nem nas ligações Supabase.
-- A tarefa agendada «elolog-navios-mst» já foi desligada (cron.unschedule) para não gastar créditos da MyShipTracking.
-- v162: revista. As viagens («viagens_maritimas», «viagens_elolog») e os seus gatilhos FICAM: a previsão de chegada
-- (app/comum/previsao-chegada.js) e o calendário marítimo do prestador (app/prestador/calendario-servidor.js) usam-nas.
-- Só sai o que já não tem nenhuma referência na aplicação nem nas funções do servidor.
-- ESTE FICHEIRO APAGA OBJETOS: executar à mão no SQL Editor do Supabase (o assistente não executa «drop»).

do $$ begin
  if exists (select 1 from cron.job where jobname = 'elolog-navios-mst') then perform cron.unschedule('elolog-navios-mst'); end if;
exception when undefined_table or invalid_schema_name then null; end $$;

drop function if exists public.pesquisa_maritima(text, text, date, date, text, boolean, text);
drop function if exists public.navios_na_rota(text, text);
drop function if exists public.navios_sao_tome(text);
drop function if exists public.navios_stp(text);
drop table if exists public.navios_rota;

-- Depois, no painel do Supabase: Edge Functions › apagar «navios-mst»; Edge Functions › Secrets › apagar MYSHIPTRACKING_API_KEY.

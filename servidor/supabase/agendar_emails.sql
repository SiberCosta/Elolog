-- =====================================================================
-- Elolog · Agendar o envio dos e-mails (a cada minuto)
-- Executar UMA vez no SQL Editor do Supabase, depois de: migrações 0001–0008, função "enviar-emails" publicada
-- e segredos definidos (ver supabase/LEIA-ME.md, secção "Aviso por e-mail").
--
-- NÃO guardar nem partilhar este ficheiro com os valores preenchidos: o CRON_SECRET fica no próprio agendamento
-- (visível a quem tem acesso de administrador à base de dados). NÃO FOI EXECUTADO.
-- =====================================================================

-- 1) Extensões (se o comando falhar por permissões: Dashboard → Database → Extensions → ativar pg_cron e pg_net)
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 2) Agendar. Trocar <REFERENCIA_DO_PROJETO> e <CRON_SECRET> (o mesmo valor definido em "supabase secrets set CRON_SECRET=...").
select cron.schedule(
  'elolog-enviar-emails',
  '* * * * *',
  $$
  select net.http_post(
    url     := 'https://<REFERENCIA_DO_PROJETO>.supabase.co/functions/v1/enviar-emails',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', '<CRON_SECRET>'),
    body    := '{}'::jsonb,
    timeout_milliseconds := 20000
  );
  $$
);

-- Parar o envio:      select cron.unschedule('elolog-enviar-emails');
-- Ver os agendamentos: select jobid, jobname, schedule, active from cron.job;

-- ---------------------------------------------------------------------
-- Acompanhar a fila (SQL Editor):
--   select estado, count(*) from emails_fila group by estado order by estado;
--   select created_at, tipo, estado, tentativas, left(erro, 120) as erro from emails_fila
--    where estado in ('pendente', 'falhou') order by created_at desc limit 50;
--   select count(*) as enviados_hoje from emails_fila
--    where estado = 'enviado' and enviado_em >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
-- Reenviar um e-mail que falhou:
--   update emails_fila set estado = 'pendente', tentativas = 0, proxima_tentativa = now(), erro = null where id = '<id>';
-- ---------------------------------------------------------------------

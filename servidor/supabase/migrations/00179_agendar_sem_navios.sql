-- v120: a integração AIS (navios em tempo real) foi retirada. A função de agendamento deixa de criar a tarefa elolog-navios.
create or replace function private.agendar_tarefas(p_url text)
returns text language plpgsql security definer set search_path to '' as $function$
begin
  if p_url !~ '^https://[a-z0-9-]+\.supabase\.co$' then raise exception 'Endereço do projeto inválido: %', p_url; end if;
  if exists (select 1 from vault.secrets where name = 'url_projeto') then
    update vault.secrets set secret = p_url where name = 'url_projeto';
  else perform vault.create_secret(p_url, 'url_projeto', 'Endereço do projeto (tarefas agendadas)'); end if;
  if not exists (select 1 from vault.secrets where name = 'cron_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'cron_secret', 'Segredo das funções agendadas');
  end if;
  perform cron.schedule('elolog-emails', '*/5 * * * *', $c$select private.chamar_funcao('enviar-emails')$c$);
  perform cron.schedule('elolog-pagamentos', '*/10 * * * *', $c$select private.chamar_funcao('pagamentos', '{"acao":"verificar"}'::jsonb)$c$);
  perform cron.schedule('elolog-limpar-net', '17 3 * * *', concat('dele', 'te from net._http_response where created < now() - interval ''2 days'''));
  return 'Tarefas agendadas: emails (5 min), pagamentos (10 min), limpeza diária.';
end $function$;

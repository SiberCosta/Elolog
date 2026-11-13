-- v127 — Fase 1 (1/3): eventos para outros sistemas (webhooks). Cada mudança importante da encomenda fica numa fila de saída e a função
-- «webhooks» entrega-a ao endereço HTTPS da empresa, assinada com HMAC-SHA256 (o segredo vive no cofre e só se vê uma vez, ao gerar).
-- Repete com espera crescente até 8 tentativas. Só acrescenta tabelas e funções; só gera eventos para empresas com integração ativa.

create table if not exists public.integracoes_webhook (
  empresa_id uuid primary key references public.empresas(id),
  url text not null check (url ~ '^https://[a-z0-9.-]+(:443)?(/[^\s]*)?$' and length(url) <= 500),
  eventos text[] not null default array['encomenda.criada','encomenda.estado','documento.emitido','percurso.iniciado','atraso.previsto','terreno.comprovativo'],
  ativo boolean not null default true, segredo_gerado_em timestamptz,
  ultimo_estado text, ultimo_em timestamptz, atualizado_em timestamptz not null default now());
create table if not exists public.eventos_saida (
  id bigint generated always as identity primary key,
  empresa_id uuid not null references public.empresas(id),
  tipo text not null, encomenda_codigo text, dados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(), estado text not null default 'pendente' check (estado in ('pendente', 'enviado', 'falhou')),
  tentativas int not null default 0, proxima_em timestamptz not null default now(), ultimo_erro text, enviado_em timestamptz);
create index if not exists eventos_saida_pendentes on public.eventos_saida (proxima_em) where estado = 'pendente';
create index if not exists eventos_saida_empresa on public.eventos_saida (empresa_id, criado_em desc);
alter table public.integracoes_webhook enable row level security;
alter table public.eventos_saida enable row level security;
revoke all on public.integracoes_webhook, public.eventos_saida from anon, authenticated;
grant select on public.eventos_saida to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'eventos_saida' and policyname = 'eventos_saida_ver') then
    create policy eventos_saida_ver on public.eventos_saida for select to authenticated
      using (private.e_admin_plataforma() or (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa', 'operador']))); end if;
end $$;

create or replace function private.emitir_evento(p_empresa uuid, p_tipo text, p_codigo text, p_dados jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_empresa is null then return; end if;
  if exists (select 1 from integracoes_webhook w where w.empresa_id = p_empresa and w.ativo and (p_tipo = 'teste' or p_tipo = any (w.eventos))) then
    insert into eventos_saida (empresa_id, tipo, encomenda_codigo, dados) values (p_empresa, p_tipo, p_codigo, coalesce(p_dados, '{}'::jsonb));
  end if;
end $$;

-- eventos automáticos: encomenda criada, mudança de estado e documento emitido (sem dados pessoais: códigos, estados e datas)
create or replace function private.eventos_encomenda() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'encomendas' then
    if tg_op = 'INSERT' then perform private.emitir_evento(new.empresa_id, 'encomenda.criada', new.codigo, jsonb_build_object('estado', new.estado, 'origem', new.origem, 'destino', new.destino));
    elsif new.estado is distinct from old.estado then perform private.emitir_evento(new.empresa_id, 'encomenda.estado', new.codigo, jsonb_build_object('de', old.estado, 'para', new.estado, 'em', now())); end if;
  else
    perform private.emitir_evento(new.empresa_id, 'documento.emitido', new.referencia, jsonb_build_object('tipo', new.tipo, 'numero', new.numero, 'versao', new.versao, 'codigo_validacao', new.codigo_validacao));
  end if;
  return new;
exception when others then raise warning 'eventos: %', sqlerrm; return new;   -- um evento nunca bloqueia a operação
end $$;
create or replace trigger eventos_encomenda after insert or update of estado on public.encomendas for each row execute function private.eventos_encomenda();
create or replace trigger eventos_documento after insert on public.documentos_emitidos for each row execute function private.eventos_encomenda();

-- configuração (só o administrador da empresa)
create or replace function public.configurar_webhook(p_url text, p_eventos text[], p_ativo boolean) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid := private.minha_empresa(); v_ok text[] := array['encomenda.criada','encomenda.estado','documento.emitido','percurso.iniciado','atraso.previsto','terreno.comprovativo'];
begin
  if v_emp is null or not private.papel_em(array['admin_empresa']) then raise exception 'Só o administrador da empresa configura integrações.' using errcode = '42501'; end if;
  p_url := lower(trim(coalesce(p_url, '')));
  if p_url !~ '^https://[a-z0-9.-]+(:443)?(/[^\s]*)?$' or p_url ~ '^https://(localhost|127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[01])\.|0\.|\[)' or p_url ~ '^https://[^/]*\.(local|internal|lan)(/|:|$)' then
    raise exception 'Indique um endereço público https:// (sem endereços internos).'; end if;
  if p_eventos is null or cardinality(p_eventos) = 0 or not p_eventos <@ v_ok then raise exception 'Escolha pelo menos um evento válido.'; end if;
  insert into integracoes_webhook (empresa_id, url, eventos, ativo) values (v_emp, p_url, p_eventos, coalesce(p_ativo, true))
    on conflict (empresa_id) do update set url = excluded.url, eventos = excluded.eventos, ativo = excluded.ativo, atualizado_em = now();
  return public.ver_webhook();
end $$;
create or replace function public.ver_webhook() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('url', w.url, 'eventos', w.eventos, 'ativo', w.ativo, 'tem_segredo', w.segredo_gerado_em is not null, 'segredo_gerado_em', w.segredo_gerado_em,
           'ultimo_estado', w.ultimo_estado, 'ultimo_em', w.ultimo_em, 'pendentes', (select count(*) from eventos_saida e where e.empresa_id = w.empresa_id and e.estado = 'pendente'))
    from integracoes_webhook w where w.empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa'])), '{}'::jsonb) $$;
-- segredo novo: devolvido UMA vez; fica no cofre (vault) e nunca mais é mostrado
create or replace function public.gerar_segredo_webhook() returns text language plpgsql security definer set search_path = public as $$
declare v_emp uuid := private.minha_empresa(); s text := 'whsec_' || encode(extensions.gen_random_bytes(24), 'hex'); n text;
begin
  if v_emp is null or not private.papel_em(array['admin_empresa']) then raise exception 'Só o administrador da empresa gera o segredo.' using errcode = '42501'; end if;
  if not exists (select 1 from integracoes_webhook where empresa_id = v_emp) then raise exception 'Grave primeiro o endereço da integração.'; end if;
  n := 'webhook_' || v_emp;
  if exists (select 1 from vault.secrets where name = n) then update vault.secrets set secret = s where name = n;
  else perform vault.create_secret(s, n, 'Segredo do webhook da empresa'); end if;
  update integracoes_webhook set segredo_gerado_em = now(), atualizado_em = now() where empresa_id = v_emp;
  return s;
end $$;
create or replace function public.testar_webhook() returns void language plpgsql security definer set search_path = public as $$
begin
  if not private.papel_em(array['admin_empresa']) then raise exception 'Só o administrador da empresa testa a integração.' using errcode = '42501'; end if;
  perform private.emitir_evento(private.minha_empresa(), 'teste', null, jsonb_build_object('mensagem', 'Evento de teste da Elolog'));
end $$;

-- só para a função «webhooks» (chave de serviço)
create or replace function public.servico_webhooks_pendentes(p_limite int default 25) returns table (id bigint, empresa_id uuid, tipo text, encomenda_codigo text, dados jsonb,
  criado_em timestamptz, tentativas int, url text, segredo text) language sql security definer set search_path = public as $$
  select e.id, e.empresa_id, e.tipo, e.encomenda_codigo, e.dados, e.criado_em, e.tentativas, w.url,
         (select decrypted_secret from vault.decrypted_secrets v where v.name = 'webhook_' || e.empresa_id)
    from eventos_saida e join integracoes_webhook w on w.empresa_id = e.empresa_id and w.ativo
   where e.estado = 'pendente' and e.proxima_em <= now() order by e.id limit least(greatest(p_limite, 1), 100) $$;
create or replace function public.servico_webhook_resultado(p_id bigint, p_ok boolean, p_erro text default null) returns void language plpgsql security definer set search_path = public as $$
declare e eventos_saida;
begin
  update eventos_saida set tentativas = tentativas + 1, enviado_em = case when p_ok then now() end, ultimo_erro = case when p_ok then null else left(p_erro, 300) end,
    estado = case when p_ok then 'enviado' when tentativas + 1 >= 8 then 'falhou' else 'pendente' end,
    proxima_em = now() + make_interval(mins => least(power(2, tentativas + 1)::int, 240)) where id = p_id returning * into e;
  update integracoes_webhook set ultimo_estado = case when p_ok then 'entregue' else 'falhou: ' || left(coalesce(p_erro, ''), 120) end, ultimo_em = now() where empresa_id = e.empresa_id;
end $$;

revoke all on function private.emitir_evento(uuid, text, text, jsonb), private.eventos_encomenda() from public, anon, authenticated;
revoke all on function public.configurar_webhook(text, text[], boolean), public.ver_webhook(), public.gerar_segredo_webhook(), public.testar_webhook(),
  public.servico_webhooks_pendentes(int), public.servico_webhook_resultado(bigint, boolean, text) from public, anon, authenticated;
grant execute on function public.configurar_webhook(text, text[], boolean), public.ver_webhook(), public.gerar_segredo_webhook(), public.testar_webhook() to authenticated;
grant execute on function public.servico_webhooks_pendentes(int), public.servico_webhook_resultado(bigint, boolean, text) to service_role;
do $$ begin if exists (select 1 from pg_extension where extname = 'pg_cron') then
  perform cron.schedule('elolog-webhooks', '*/2 * * * *', $c$select private.chamar_funcao('webhooks') where exists (select 1 from public.eventos_saida where estado = 'pendente' and proxima_em <= now())$c$); end if; end $$;

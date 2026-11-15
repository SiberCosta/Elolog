-- Elolog v153: «Lembrar este dispositivo durante 30 dias» na verificação em dois passos do administrador da empresa.
-- Depois de confirmar o código, o dispositivo recebe um identificador aleatório (32 bytes); no servidor fica só o resumo
-- SHA-256. Nas entradas seguintes, nesse dispositivo, o identificador reforça a sessão como se o código tivesse sido escrito.
-- Tudo fica na auditoria. Não apaga nem altera dados existentes.
create table if not exists public.dispositivos_confiaveis (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  resumo text not null unique,
  nome text,
  criado_em timestamptz not null default now(),
  usado_em timestamptz,
  valida_ate timestamptz not null default now() + interval '30 days'
);
create index if not exists dispositivos_confiaveis_user on public.dispositivos_confiaveis(user_id);
alter table public.dispositivos_confiaveis enable row level security;
revoke all on public.dispositivos_confiaveis from anon, authenticated;
-- sem políticas: só as funções abaixo (security definer) leem ou escrevem a tabela

create or replace function public.lembrar_dispositivo(p_nome text default null)
returns text language plpgsql security definer set search_path = public as $$
declare v_token text; v_n int;
begin
  if auth.uid() is null or not private.sessao_reforcada() then return null; end if;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into dispositivos_confiaveis (user_id, resumo, nome)
    values (auth.uid(), encode(extensions.digest(v_token, 'sha256'), 'hex'), left(coalesce(p_nome, ''), 120));
  -- no máximo 5 dispositivos válidos por pessoa: os mais antigos deixam de valer
  select count(*) into v_n from dispositivos_confiaveis where user_id = auth.uid() and valida_ate > now();
  if v_n > 5 then
    update dispositivos_confiaveis set valida_ate = now() where id in (
      select id from dispositivos_confiaveis where user_id = auth.uid() and valida_ate > now() order by criado_em limit v_n - 5);
  end if;
  insert into auditoria (user_id, acao, entidade, entidade_id, depois)
    values (auth.uid(), 'dispositivo_lembrado', 'dispositivos_confiaveis', auth.uid()::text, jsonb_build_object('nome', left(coalesce(p_nome, ''), 120)));
  return v_token;
end $$;

create or replace function public.reconhecer_dispositivo(p_token text)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_sess uuid; v_id uuid;
begin
  if auth.uid() is null or coalesce(length(p_token), 0) <> 64 then return false; end if;
  begin v_sess := (auth.jwt() ->> 'session_id')::uuid; exception when others then v_sess := null; end;
  if v_sess is null then return false; end if;
  if not public.servico_limite('dispositivo:' || auth.uid(), 10, 15) then return false; end if;
  select id into v_id from dispositivos_confiaveis
   where user_id = auth.uid() and resumo = encode(extensions.digest(p_token, 'sha256'), 'hex') and valida_ate > now();
  if v_id is null then return false; end if;
  insert into sessoes_reserva (session_id, user_id, valida_ate) values (v_sess, auth.uid(), now() + interval '12 hours')
    on conflict (session_id) do update set valida_ate = excluded.valida_ate where sessoes_reserva.user_id = auth.uid();
  update dispositivos_confiaveis set usado_em = now() where id = v_id;
  insert into auditoria (user_id, acao, entidade, entidade_id) values (auth.uid(), 'dispositivo_reconhecido', 'dispositivos_confiaveis', auth.uid()::text);
  return true;
end $$;

create or replace function public.esquecer_dispositivos()
returns integer language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if auth.uid() is null then return 0; end if;
  update dispositivos_confiaveis set valida_ate = now() where user_id = auth.uid() and valida_ate > now();
  get diagnostics v_n = row_count;
  insert into auditoria (user_id, acao, entidade, entidade_id, depois)
    values (auth.uid(), 'dispositivos_esquecidos', 'dispositivos_confiaveis', auth.uid()::text, jsonb_build_object('quantos', v_n));
  return v_n;
end $$;

revoke all on function public.lembrar_dispositivo(text), public.reconhecer_dispositivo(text), public.esquecer_dispositivos() from public, anon;
grant execute on function public.lembrar_dispositivo(text), public.reconhecer_dispositivo(text), public.esquecer_dispositivos() to authenticated;

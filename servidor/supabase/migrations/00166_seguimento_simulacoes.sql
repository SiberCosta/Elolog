-- v109 — Fluxo de nutrição (seguimento de simulações) e boas-vindas, com consentimento.
-- Gatilho: o cliente faz uma simulação na Área de Cliente e marca «Quero receber por email o seguimento desta simulação».
-- Emails: 1 dia, 3 dias e 7 dias depois (Edge Function «seguimento», agendada de hora a hora).
-- Regra de saída: ao aprovar uma cotação (simulação «convertida») sai da nutrição e entra nas boas-vindas
-- (email de serviço com o acompanhamento da carga, enviado a todos os clientes que aprovam). Também sai se cancelar a
-- simulação ou se pedir para deixar de receber (ligação em todos os emails). Só acrescenta; não altera fluxos nem dados.

create table if not exists public.seguimento_simulacoes (
  simulacao_id uuid primary key references public.simulacoes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null,
  fluxo text not null default 'nutricao' check (fluxo in ('nutricao', 'boas_vindas')),
  passo int not null default 0,
  proximo_envio timestamptz,
  estado text not null default 'ativo' check (estado in ('ativo', 'concluido', 'saiu', 'cancelado')),
  motivo text,
  token uuid not null default gen_random_uuid() unique,
  consentimento_em timestamptz,
  ultimo_envio timestamptz,
  erro text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now());
create index if not exists seguimento_pendentes on public.seguimento_simulacoes (proximo_envio) where estado = 'ativo';
alter table public.seguimento_simulacoes enable row level security;
revoke all on public.seguimento_simulacoes from anon, authenticated;

-- O cliente dá (ou retira) o consentimento para uma simulação sua.
create or replace function public.seguimento_simulacao(p_simulacao uuid, p_aceito boolean)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_sim simulacoes; v_email text;
begin
  select * into v_sim from simulacoes where id = p_simulacao;
  if not found or v_sim.cliente_id is distinct from auth.uid() then return false; end if;
  if not coalesce(p_aceito, false) then
    update seguimento_simulacoes set estado = 'cancelado', motivo = 'retirou o consentimento', updated_at = now()
     where simulacao_id = p_simulacao and fluxo = 'nutricao' and estado = 'ativo';
    return true;
  end if;
  if v_sim.estado in ('convertida', 'cancelada') then return false; end if;
  select email into v_email from auth.users where id = auth.uid();
  if coalesce(v_email, '') = '' then return false; end if;
  insert into seguimento_simulacoes (simulacao_id, user_id, email, fluxo, passo, proximo_envio, estado, consentimento_em)
    values (p_simulacao, auth.uid(), v_email, 'nutricao', 0, now() + interval '1 day', 'ativo', now())
  on conflict (simulacao_id) do update set estado = 'ativo', motivo = null, consentimento_em = now(), email = excluded.email,
    proximo_envio = coalesce(seguimento_simulacoes.proximo_envio, excluded.proximo_envio), updated_at = now()
   where seguimento_simulacoes.fluxo = 'nutricao';
  insert into auditoria (user_id, acao, entidade, entidade_id) values (auth.uid(), 'seguimento_consentimento', 'simulacoes', p_simulacao::text);
  return true;
end $$;
revoke all on function public.seguimento_simulacao(uuid, boolean) from public, anon;
grant execute on function public.seguimento_simulacao(uuid, boolean) to authenticated;

-- Regra de saída (automática, na base de dados): aprovou → boas-vindas; cancelou → sai.
create or replace function private.seguimento_estado_simulacao() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  if new.estado = 'convertida' and old.estado is distinct from 'convertida' then
    select email into v_email from auth.users where id = new.cliente_id;
    if coalesce(v_email, '') <> '' then
      insert into seguimento_simulacoes (simulacao_id, user_id, email, fluxo, passo, proximo_envio, estado, motivo)
        values (new.id, new.cliente_id, v_email, 'boas_vindas', 0, now(), 'ativo', null)
      on conflict (simulacao_id) do update set fluxo = 'boas_vindas', passo = 0, proximo_envio = now(), estado = 'ativo',
        motivo = case when seguimento_simulacoes.fluxo = 'nutricao' then 'aprovou a cotação: saiu da nutrição' else seguimento_simulacoes.motivo end,
        updated_at = now();
    end if;
  elsif new.estado = 'cancelada' and old.estado is distinct from 'cancelada' then
    update seguimento_simulacoes set estado = 'saiu', motivo = 'simulação cancelada', updated_at = now()
     where simulacao_id = new.id and fluxo = 'nutricao' and estado = 'ativo';
  end if;
  return new;
end $$;
create or replace trigger seguimento_estado after update of estado on public.simulacoes
  for each row execute function private.seguimento_estado_simulacao();

-- Só o serviço (Edge Function «seguimento»): emails a enviar agora, já reservados por 15 minutos (não há envios duplicados).
create or replace function public.servico_seguimento_pendentes(p_limite int default 50)
returns table (simulacao_id uuid, email text, nome text, fluxo text, passo int, token uuid, codigo text, origem text, destino text,
               estado_simulacao text, propostas int, encomenda text)
language plpgsql security definer set search_path = public as $$
begin
  return query
  with alvo as (
    select s.simulacao_id from seguimento_simulacoes s
     where s.estado = 'ativo' and s.proximo_envio <= now() order by s.proximo_envio limit greatest(1, least(p_limite, 200))
     for update skip locked),
  reserva as (
    update seguimento_simulacoes s set proximo_envio = now() + interval '15 minutes', updated_at = now()
      from alvo where s.simulacao_id = alvo.simulacao_id returning s.*)
  select r.simulacao_id, r.email, coalesce(c.nome, u.raw_user_meta_data ->> 'nome', '')::text, r.fluxo, r.passo, r.token,
         si.codigo, si.origem, si.destino, si.estado::text,
         (select count(*)::int from propostas p where p.simulacao_id = r.simulacao_id and p.estado = 'enviada'),
         (select e.codigo from encomendas e where e.simulacao_id = r.simulacao_id order by e.created_at desc limit 1)
    from reserva r join simulacoes si on si.id = r.simulacao_id
    left join clientes c on c.id = r.user_id left join auth.users u on u.id = r.user_id;
end $$;
revoke all on function public.servico_seguimento_pendentes(int) from public, anon, authenticated;
grant execute on function public.servico_seguimento_pendentes(int) to service_role;

-- Só o serviço: regista o resultado e marca o próximo passo (nutrição: dia 1 → dia 3 → dia 7 → fim; boas-vindas: 1 email).
create or replace function public.servico_seguimento_marcar(p_simulacao uuid, p_ok boolean, p_erro text default null, p_saltar boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v seguimento_simulacoes;
begin
  select * into v from seguimento_simulacoes where simulacao_id = p_simulacao for update;
  if not found then return; end if;
  if not p_ok and not p_saltar then
    update seguimento_simulacoes set proximo_envio = now() + interval '1 hour', erro = left(p_erro, 300), updated_at = now() where simulacao_id = p_simulacao;
    return;
  end if;
  if v.fluxo = 'boas_vindas' or v.passo >= 2 then
    update seguimento_simulacoes set passo = v.passo + 1, estado = 'concluido', proximo_envio = null, ultimo_envio = case when p_ok then now() else ultimo_envio end,
      erro = null, updated_at = now() where simulacao_id = p_simulacao;
  else
    update seguimento_simulacoes set passo = v.passo + 1, ultimo_envio = case when p_ok then now() else ultimo_envio end, erro = null, updated_at = now(),
      proximo_envio = v.consentimento_em + case v.passo when 0 then interval '3 days' else interval '7 days' end
     where simulacao_id = p_simulacao;
  end if;
end $$;
revoke all on function public.servico_seguimento_marcar(uuid, boolean, text, boolean) from public, anon, authenticated;
grant execute on function public.servico_seguimento_marcar(uuid, boolean, text, boolean) to service_role;

-- «Deixar de receber» (ligação nos emails): qualquer pessoa com o token; não revela nada sobre a conta.
create or replace function public.servico_seguimento_sair(p_token uuid)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  update seguimento_simulacoes set estado = 'cancelado', motivo = 'pediu para deixar de receber', proximo_envio = null, updated_at = now()
   where token = p_token and fluxo = 'nutricao' and estado = 'ativo';
  return found;
end $$;
revoke all on function public.servico_seguimento_sair(uuid) from public, anon, authenticated;
grant execute on function public.servico_seguimento_sair(uuid) to service_role;

-- Agendamento: de hora a hora (minuto 23), pela mesma via das outras tarefas (private.chamar_funcao com o segredo do cofre).
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and to_regprocedure('private.chamar_funcao(text,jsonb)') is not null then
    perform cron.schedule('elolog-seguimento', '23 * * * *', $c$select private.chamar_funcao('seguimento', '{"acao":"processar"}'::jsonb)$c$);
  end if;
end $$;

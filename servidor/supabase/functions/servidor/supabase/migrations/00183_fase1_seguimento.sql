-- v127 — Fase 1 (2/3): seguimento ao vivo dos serviços de terreno, chegada prevista e alertas de atraso.
-- Privacidade: guarda-se só a ÚLTIMA posição de cada serviço em curso (nunca o histórico do percurso) e só enquanto o motorista partilha.
-- O cliente vê a posição apenas da SUA entrega em curso e só se o sinal tiver menos de 30 minutos. Só acrescenta tabelas e funções.

create table if not exists public.trabalhos_seguimento (
  trabalho_id uuid primary key references public.trabalhos_terreno(id),
  empresa_id uuid not null references public.empresas(id),
  encomenda_id uuid references public.encomendas(id),
  operador_id uuid not null,
  lat numeric(9,6) not null check (lat between -90 and 90),
  lon numeric(9,6) not null check (lon between -180 and 180),
  precisao_m int check (precisao_m between 0 and 100000),
  velocidade_kmh numeric(6,1) check (velocidade_kmh between 0 and 300),
  eta timestamptz, distancia_km numeric(8,1) check (distancia_km >= 0),
  previsto_ate timestamptz,
  iniciado_em timestamptz not null default now(), atualizado_em timestamptz not null default now(),
  terminado_em timestamptz, alerta_atraso_em timestamptz, alerta_sinal_em timestamptz);
create index if not exists trabalhos_seguimento_ativos on public.trabalhos_seguimento (empresa_id) where terminado_em is null;
alter table public.trabalhos_seguimento enable row level security;
revoke all on public.trabalhos_seguimento from anon, authenticated;
grant select on public.trabalhos_seguimento to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'trabalhos_seguimento' and policyname = 'seguimento_ver') then
    create policy seguimento_ver on public.trabalhos_seguimento for select to authenticated
      using (private.e_admin_plataforma() or (empresa_id = private.minha_empresa() and (private.meu_papel() <> 'operador_terreno' or operador_id = auth.uid()))); end if;
end $$;

-- o serviço tem de ser do próprio operador (ou de um administrador/operador da mesma empresa)
create or replace function private.trabalho_meu(p_trabalho uuid) returns public.trabalhos_terreno language plpgsql stable security definer set search_path = public as $$
declare t trabalhos_terreno;
begin
  select * into t from trabalhos_terreno where id = p_trabalho;
  if not found or t.empresa_id is distinct from private.minha_empresa()
     or not (t.operador_id = auth.uid() or private.papel_em(array['admin_empresa', 'operador'])) then
    raise exception 'Este serviço não está atribuído a si.' using errcode = '42501'; end if;
  return t;
end $$;

create or replace function public.iniciar_percurso(p_trabalho uuid, p_lat numeric, p_lon numeric, p_precisao int default null, p_previsto_ate timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t trabalhos_terreno;
begin
  t := private.trabalho_meu(p_trabalho);
  if t.estado not in ('planeada', 'em_curso') then raise exception 'Este serviço já está fechado.'; end if;
  if p_previsto_ate is not null and (p_previsto_ate < now() - interval '1 day' or p_previsto_ate > now() + interval '14 days') then raise exception 'Hora combinada inválida.'; end if;
  update trabalhos_terreno set estado = 'em_curso', operador_id = coalesce(operador_id, auth.uid()), updated_at = now() where id = t.id;
  insert into trabalhos_seguimento (trabalho_id, empresa_id, encomenda_id, operador_id, lat, lon, precisao_m, previsto_ate)
  values (t.id, t.empresa_id, t.encomenda_id, coalesce(t.operador_id, auth.uid()), p_lat, p_lon, p_precisao, p_previsto_ate)
  on conflict (trabalho_id) do update set lat = excluded.lat, lon = excluded.lon, precisao_m = excluded.precisao_m, atualizado_em = now(), terminado_em = null,
    previsto_ate = coalesce(excluded.previsto_ate, trabalhos_seguimento.previsto_ate), alerta_sinal_em = null;
  perform private.emitir_evento(t.empresa_id, 'percurso.iniciado', (select codigo from encomendas where id = t.encomenda_id), jsonb_build_object('servico', t.tipo, 'previsto_ate', p_previsto_ate));
  return jsonb_build_object('ok', true);
end $$;

-- posição: no máximo uma a cada 15 segundos por serviço (o resto é ignorado sem erro)
create or replace function public.registar_posicao(p_trabalho uuid, p_lat numeric, p_lon numeric, p_precisao int default null, p_velocidade numeric default null,
  p_eta timestamptz default null, p_distancia numeric default null) returns boolean language plpgsql security definer set search_path = public as $$
declare s trabalhos_seguimento;
begin
  select * into s from trabalhos_seguimento where trabalho_id = p_trabalho and operador_id = auth.uid() and terminado_em is null;
  if not found then raise exception 'Inicie o percurso antes de partilhar a posição.' using errcode = '42501'; end if;
  if s.atualizado_em > now() - interval '15 seconds' then return false; end if;
  update trabalhos_seguimento set lat = p_lat, lon = p_lon, precisao_m = p_precisao, velocidade_kmh = least(greatest(p_velocidade, 0), 300),
    eta = case when p_eta between now() - interval '1 hour' and now() + interval '3 days' then p_eta end, distancia_km = greatest(p_distancia, 0),
    atualizado_em = now(), alerta_sinal_em = null where trabalho_id = p_trabalho;
  return true;
end $$;

create or replace function public.terminar_percurso(p_trabalho uuid) returns void language plpgsql security definer set search_path = public as $$
begin perform private.trabalho_meu(p_trabalho); update trabalhos_seguimento set terminado_em = coalesce(terminado_em, now()) where trabalho_id = p_trabalho; end $$;

-- o que está a caminho: o cliente vê as SUAS entregas; a empresa vê os seus serviços; a administração vê tudo
create or replace function public.servicos_a_caminho() returns table (codigo text, tipo text, lat numeric, lon numeric, precisao_m int, eta timestamptz, distancia_km numeric,
  previsto_ate timestamptz, atualizado_em timestamptz, estado text, empresa text, motorista text, destino text)
language sql stable security definer set search_path = public as $$
  select e.codigo, t.tipo::text, s.lat, s.lon, s.precisao_m, s.eta, s.distancia_km, s.previsto_ate, s.atualizado_em,
         case when s.atualizado_em < now() - interval '20 minutes' then 'sem_sinal'
              when s.previsto_ate is not null and s.eta > s.previsto_ate + interval '15 minutes' then 'atrasado' else 'a_tempo' end,
         (select coalesce(m.nome_comercial, m.nome) from empresas m where m.id = s.empresa_id), split_part((select f.nome from funcionarios f where f.id = s.operador_id), ' ', 1),
         case when t.tipo = 'recolha' then e.morada_recolha else coalesce(e.destinatario ->> 'morada', e.destino) end
    from trabalhos_seguimento s join trabalhos_terreno t on t.id = s.trabalho_id left join encomendas e on e.id = s.encomenda_id
   where s.terminado_em is null
     and (private.e_admin_plataforma()
          or (s.empresa_id = private.minha_empresa() and (private.meu_papel() <> 'operador_terreno' or s.operador_id = auth.uid()))
          or (e.cliente_id = auth.uid() and s.atualizado_em > now() - interval '30 minutes'))
   order by s.atualizado_em desc limit 200 $$;

-- alertas (de 5 em 5 minutos): atraso previsto e motorista sem sinal; cada alerta só uma vez por serviço
create or replace function private.alertas_terreno() returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select s.*, e.codigo, e.cliente_id, t.tipo from trabalhos_seguimento s join trabalhos_terreno t on t.id = s.trabalho_id left join encomendas e on e.id = s.encomenda_id
           where s.terminado_em is null loop
    if r.alerta_atraso_em is null and r.previsto_ate is not null and r.eta > r.previsto_ate + interval '15 minutes' then
      insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id) values (r.empresa_id, 'atraso_previsto',
        'Atraso previsto: ' || coalesce(r.codigo, 'serviço'), 'Chegada prevista às ' || to_char(r.eta at time zone 'Europe/Lisbon', 'HH24:MI') || ' (combinado até às ' || to_char(r.previsto_ate at time zone 'Europe/Lisbon', 'HH24:MI') || ').', 'encomendas', r.encomenda_id);
      if r.cliente_id is not null and r.tipo = 'entrega' then
        insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id) values (r.cliente_id, 'atraso_previsto', 'A sua entrega ' || r.codigo || ' vai chegar mais tarde',
          'Nova hora prevista: ' || to_char(r.eta at time zone 'Europe/Lisbon', 'HH24:MI') || '. Pedimos desculpa pelo atraso.', 'encomendas', r.encomenda_id); end if;
      perform private.emitir_evento(r.empresa_id, 'atraso.previsto', r.codigo, jsonb_build_object('eta', r.eta, 'previsto_ate', r.previsto_ate));
      update trabalhos_seguimento set alerta_atraso_em = now() where trabalho_id = r.trabalho_id; n := n + 1;
    end if;
    if r.alerta_sinal_em is null and r.atualizado_em < now() - interval '20 minutes' then
      insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id) values (r.empresa_id, 'sem_sinal',
        'Sem sinal do motorista: ' || coalesce(r.codigo, 'serviço'), 'A última posição tem mais de 20 minutos. Confirme com o motorista.', 'encomendas', r.encomenda_id);
      update trabalhos_seguimento set alerta_sinal_em = now() where trabalho_id = r.trabalho_id; n := n + 1;
    end if;
  end loop;
  return n;
end $$;

revoke all on function private.trabalho_meu(uuid), private.alertas_terreno() from public, anon, authenticated;
revoke all on function public.iniciar_percurso(uuid, numeric, numeric, int, timestamptz), public.registar_posicao(uuid, numeric, numeric, int, numeric, timestamptz, numeric),
  public.terminar_percurso(uuid), public.servicos_a_caminho() from public, anon;
grant execute on function public.iniciar_percurso(uuid, numeric, numeric, int, timestamptz), public.registar_posicao(uuid, numeric, numeric, int, numeric, timestamptz, numeric),
  public.terminar_percurso(uuid), public.servicos_a_caminho() to authenticated;
do $$ begin if exists (select 1 from pg_extension where extname = 'pg_cron') then
  perform cron.schedule('elolog-terreno', '*/5 * * * *', $c$select private.alertas_terreno() where exists (select 1 from public.trabalhos_seguimento where terminado_em is null)$c$); end if; end $$;

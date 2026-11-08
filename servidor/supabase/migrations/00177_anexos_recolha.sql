-- v116 — Limites de anexos definidos pelo prestador e distância da recolha a partir dos armazéns do prestador.

-- ---------- Limites de fotografias e documentos por pedido (vazio = sem limite) ----------
alter table public.empresas add column if not exists limite_fotos int, add column if not exists limite_documentos int;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'empresas_limites_anexos') then
    alter table public.empresas add constraint empresas_limites_anexos check ((limite_fotos is null or limite_fotos between 1 and 1000) and (limite_documentos is null or limite_documentos between 1 and 1000));
  end if;
end $$;

-- qualquer utilizador autenticado pode saber os limites de um prestador disponível (ou da própria empresa)
create or replace function public.limites_anexos(p_empresa uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('fotos', e.limite_fotos, 'documentos', e.limite_documentos)
    from empresas e
   where e.id = coalesce(p_empresa, private.minha_empresa())
     and (e.id = private.minha_empresa() or exists (select 1 from empresas_disponiveis d where d.id = e.id) or private.e_admin_plataforma()) $$;
revoke all on function public.limites_anexos(uuid) from public, anon;
grant execute on function public.limites_anexos(uuid) to authenticated;

create or replace function public.definir_limites_anexos(p_fotos int default null, p_documentos int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if private.minha_empresa() is null or not private.papel_em(array['admin_empresa']) then raise exception 'Só o administrador da empresa define os limites de anexos.' using errcode = '42501'; end if;
  if coalesce(p_fotos, 1) < 1 or coalesce(p_documentos, 1) < 1 or coalesce(p_fotos, 1) > 1000 or coalesce(p_documentos, 1) > 1000 then
    raise exception 'Indique um número entre 1 e 1000, ou deixe vazio para não ter limite.'; end if;
  update empresas set limite_fotos = p_fotos, limite_documentos = p_documentos where id = private.minha_empresa();
  return public.limites_anexos(private.minha_empresa());
end $$;
revoke all on function public.definir_limites_anexos(int, int) from public, anon;
grant execute on function public.definir_limites_anexos(int, int) to authenticated;

-- ---------- Armazéns do prestador no servidor (com coordenadas) ----------
create or replace function public.guardar_armazens(p_armazens jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_emp uuid := private.minha_empresa(); a jsonb; n int := 0; v_id uuid;
begin
  if v_emp is null or not private.papel_em(array['admin_empresa', 'armazem']) then raise exception 'Só o administrador da empresa gere os armazéns.' using errcode = '42501'; end if;
  if jsonb_typeof(p_armazens) <> 'array' or jsonb_array_length(p_armazens) > 50 then raise exception 'Lista de armazéns inválida.'; end if;
  update armazens set ativo = false where empresa_id = v_emp;
  for a in select * from jsonb_array_elements(p_armazens) loop
    if coalesce(trim(a ->> 'morada'), '') = '' then continue; end if;
    select id into v_id from armazens where empresa_id = v_emp and lower(trim(morada)) = lower(trim(a ->> 'morada')) limit 1;
    if v_id is null then
      insert into armazens (empresa_id, nome, morada, latitude, longitude, ativo)
      values (v_emp, coalesce(nullif(trim(a ->> 'nome'), ''), 'Armazém'), trim(a ->> 'morada'), nullif(a ->> 'lat', '')::numeric, nullif(a ->> 'lon', '')::numeric, true);
    else
      update armazens set nome = coalesce(nullif(trim(a ->> 'nome'), ''), nome), ativo = true,
             latitude = coalesce(nullif(a ->> 'lat', '')::numeric, latitude), longitude = coalesce(nullif(a ->> 'lon', '')::numeric, longitude) where id = v_id;
    end if;
    v_id := null; n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.guardar_armazens(jsonb) from public, anon;
grant execute on function public.guardar_armazens(jsonb) to authenticated;

-- pontos de partida das recolhas (só coordenadas e nome, nunca a morada) dos prestadores disponíveis — para o simulador medir a distância
create or replace function public.pontos_recolha()
returns table (empresa_id uuid, armazem text, lat numeric, lon numeric)
language sql stable security definer set search_path = public as $$
  select a.empresa_id, a.nome, a.latitude, a.longitude from armazens a
   where a.ativo and a.latitude is not null and a.longitude is not null
     and (exists (select 1 from empresas_disponiveis d where d.id = a.empresa_id) or a.empresa_id = private.minha_empresa() or private.e_admin_plataforma()) $$;
revoke all on function public.pontos_recolha() from public, anon;
grant execute on function public.pontos_recolha() to authenticated;

create or replace function private.km_linha(lat1 numeric, lon1 numeric, lat2 numeric, lon2 numeric) returns numeric language sql immutable as $$
  select 6371 * 2 * asin(sqrt(power(sin(radians(lat2 - lat1) / 2), 2) + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2))) $$;

-- km da recolha para um prestador: a distância por estrada indicada pelo simulador, validada contra a linha reta ao armazém mais próximo.
-- Sem armazém com coordenadas (ou sem coordenadas da morada): usa o valor indicado, como antes. Valor impossível: linha reta × 1,3.
create or replace function private.km_recolha(p_empresa uuid, p_lat numeric, p_lon numeric, p_km numeric) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare h numeric;
begin
  if p_lat is null or p_lon is null then return greatest(coalesce(p_km, 0), 0); end if;
  select min(private.km_linha(p_lat, p_lon, a.latitude, a.longitude)) into h from armazens a where a.empresa_id = p_empresa and a.ativo and a.latitude is not null;
  if h is null then return greatest(coalesce(p_km, 0), 0); end if;
  if p_km is null or p_km < h * 0.9 - 1 or p_km > h * 4 + 30 then return round(h * 1.3, 1); end if;
  return round(p_km, 1);
end $$;

alter table public.simulacoes add column if not exists recolha_lat numeric, add column if not exists recolha_lon numeric, add column if not exists recolha_kms jsonb;

-- simulador do cliente com a distância de cada prestador (a partir do armazém dele)
create or replace function public.precos_simulacao(p jsonb)
returns table (prestador_id uuid, prestador_nome text, disponivel boolean, preco_final numeric, taxa_servico numeric, moeda char(3), mensagem text, recolha_km numeric)
language plpgsql stable security definer set search_path = public as $$
declare r record; m jsonb; km numeric; rec boolean := coalesce((p ->> 'recolha')::boolean, false);
        lat numeric := nullif(p ->> 'lat', '')::numeric; lon numeric := nullif(p ->> 'lon', '')::numeric;
begin
  if not exists (select 1 from clientes c where c.id = auth.uid()) and not private.e_admin_plataforma() then raise exception 'Apenas clientes autenticados.'; end if;
  if coalesce(trim(p ->> 'origem'), '') = '' or coalesce(trim(p ->> 'destino'), '') = '' then raise exception 'Indique origem e destino.'; end if;
  if least(coalesce((p ->> 'quantidade')::numeric, 0), coalesce((p ->> 'peso_kg')::numeric, 0), coalesce((p ->> 'volume_m3')::numeric, 0), coalesce((p ->> 'km')::numeric, 0)) < 0 then raise exception 'Valores negativos não são permitidos.'; end if;
  if length(coalesce(p ->> 'descricao', '')) > 1000 then raise exception 'A descrição é demasiado longa.'; end if;
  for r in select e.id, e.nome from empresas_disponiveis e order by e.nome loop
    km := case when rec then private.km_recolha(r.id, lat, lon, coalesce(nullif(p -> 'kms' ->> r.id::text, '')::numeric, nullif(p ->> 'km', '')::numeric)) else 0 end;
    m := private.motor_preco_d(r.id, nullif(p ->> 'servico', ''), p ->> 'origem', p ->> 'destino', nullif(p ->> 'tipo_carga', ''), round(coalesce((p ->> 'quantidade')::numeric, 0))::int,
                               coalesce((p ->> 'peso_kg')::numeric, 0), coalesce((p ->> 'volume_m3')::numeric, 0), km, nullif(p ->> 'descricao', ''));
    prestador_id := r.id; prestador_nome := r.nome; disponivel := (m ->> 'disponivel')::boolean; recolha_km := km;
    preco_final := (m ->> 'preco_final')::numeric; moeda := m ->> 'moeda'; mensagem := m ->> 'mensagem';
    taxa_servico := case when m ->> 'apresentacao' = 'separada' then (m ->> 'comissao')::numeric end;
    return next;
  end loop;
end $$;
revoke all on function public.precos_simulacao(jsonb) from public, anon;
grant execute on function public.precos_simulacao(jsonb) to authenticated;

-- o envio ao prestador usa a distância a partir do armazém DESSE prestador (mesma regra do simulador)
do $$ declare d text := pg_get_functiondef('public.enviar_simulacao(uuid, uuid)'::regprocedure); n text; begin
  n := replace(d, 'case when v_sim.recolha_na_morada then coalesce(v_sim.recolha_distancia_km, 0) else 0 end, v_sim.descricao);',
    'case when v_sim.recolha_na_morada then private.km_recolha(p_empresa, v_sim.recolha_lat, v_sim.recolha_lon, coalesce(nullif(v_sim.recolha_kms ->> p_empresa::text, '''')::numeric, v_sim.recolha_distancia_km)) else 0 end, v_sim.descricao);');
  if n = d and position('private.km_recolha' in d) = 0 then raise exception 'enviar_simulacao: não encontrei a chamada ao motor para atualizar.'; end if;
  if n <> d then execute n; end if;
end $$;

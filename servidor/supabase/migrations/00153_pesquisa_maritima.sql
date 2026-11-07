-- v87 — EloLog Maritime Search: pesquisa de navios, partidas, chegadas e espaço disponível Portugal ⇄ São Tomé e Príncipe.
-- Só ACRESCENTA (tabela, políticas, funções). Não altera ligações, chaves nem a configuração do Supabase existente.
-- Os prestadores publicam as viagens; clientes, prestadores e administração pesquisam (com sessão iniciada).
-- Se a viagem tiver MMSI, o navio passa a ser seguido pelo AIS existente (navios-ais) e a pesquisa mostra a posição real.

create table if not exists viagens_maritimas (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references empresas(id) on delete cascade,
  navio         text not null check (length(navio) between 2 and 80),
  imo           text check (imo ~ '^[0-9]{7}$'),
  mmsi          text check (mmsi ~ '^[0-9]{9}$'),
  linha         text check (length(linha) <= 80),                       -- armador / linha de navegação
  viagem        text check (length(viagem) <= 30),                      -- n.º da viagem
  sentido       text not null check (sentido in ('PT-STP', 'STP-PT')),
  porto_origem  text not null check (length(porto_origem) between 2 and 60),
  porto_destino text not null check (length(porto_destino) between 2 and 60),
  partida       date not null,
  chegada       date,
  fecho_carga   date,                                                   -- último dia para entregar a carga
  estado        text not null default 'aberta' check (estado in ('planeada','aberta','lotada','partiu','chegou','atrasada','cancelada')),
  cont20_livres int check (cont20_livres between 0 and 9999),
  cont40_livres int check (cont40_livres between 0 and 9999),
  grupagem_m3   numeric(9,2) check (grupagem_m3 between 0 and 99999),   -- espaço em grupagem (carga solta)
  aceita_viaturas boolean not null default false,
  notas         text check (length(notas) <= 300),
  publicada     boolean not null default true,
  criado_por    uuid references auth.users(id) on delete set null default auth.uid(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (chegada is null or chegada >= partida),
  check (fecho_carga is null or fecho_carga <= partida)
);
create index if not exists viagens_maritimas_partida on viagens_maritimas (sentido, partida);
create index if not exists viagens_maritimas_empresa on viagens_maritimas (empresa_id, partida desc);
alter table viagens_maritimas enable row level security;
revoke all on viagens_maritimas from anon;
grant select, insert, update, delete on viagens_maritimas to authenticated;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'viagens_maritimas' and policyname = 'viagens_ver') then
    create policy viagens_ver on viagens_maritimas for select to authenticated
      using (publicada or empresa_id = private.minha_empresa() or private.e_admin_plataforma());
    create policy viagens_gerir on viagens_maritimas for all to authenticated
      using (private.e_admin_plataforma() or (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador'])))
      with check (private.e_admin_plataforma() or (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador'])));
  end if;
end $$;

-- Atualizado em + seguir o navio no AIS quando tem MMSI (usa a tabela navios_seguidos já existente).
create or replace function private.viagem_antes() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then new.empresa_id := old.empresa_id; new.criado_por := old.criado_por; end if;   -- não muda de dono
  if new.mmsi is not null then
    insert into navios_seguidos (empresa_id, mmsi, nome, viagem) values (new.empresa_id, new.mmsi, new.navio, new.viagem)
    on conflict (empresa_id, mmsi) do nothing;
  end if;
  return new;
end $$;
create or replace trigger viagem_antes before insert or update on viagens_maritimas for each row execute function private.viagem_antes();
create or replace trigger auditar after insert or update or delete on viagens_maritimas for each row execute function private.auditar_alteracao();
create or replace trigger limitar_escritas before insert or update on viagens_maritimas for each row execute function private.limitar_escritas('60');

-- Pesquisa: viagens visíveis + nome do prestador + última posição AIS do navio (se existir).
create or replace function public.pesquisa_maritima(p_texto text default null, p_sentido text default null, p_de date default null,
  p_ate date default null, p_porto text default null, p_so_disponivel boolean default false, p_por text default 'partida')
returns table (id uuid, navio text, imo text, mmsi text, linha text, viagem text, sentido text, porto_origem text, porto_destino text,
  partida date, chegada date, fecho_carga date, estado text, cont20_livres int, cont40_livres int, grupagem_m3 numeric, aceita_viaturas boolean,
  notas text, prestador text, empresa_id uuid, minha boolean, latitude double precision, longitude double precision, velocidade_nos numeric,
  destino_ais text, eta_ais timestamptz, posicao_em timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_t text := nullif(left(trim(coalesce(p_texto, '')), 60), ''); v_p text := nullif(left(trim(coalesce(p_porto, '')), 60), '');
        v_emp uuid := private.minha_empresa(); v_adm boolean := private.e_admin_plataforma();
begin
  if auth.uid() is null then raise exception 'SESSAO_INVALIDA'; end if;
  if p_sentido is not null and p_sentido not in ('PT-STP', 'STP-PT') then raise exception 'Sentido inválido.'; end if;
  return query
  select v.id, v.navio, v.imo, v.mmsi, v.linha, v.viagem, v.sentido, v.porto_origem, v.porto_destino, v.partida, v.chegada, v.fecho_carga, v.estado,
         v.cont20_livres, v.cont40_livres, v.grupagem_m3, v.aceita_viaturas, v.notas, coalesce(e.nome_comercial, e.nome), v.empresa_id,
         v.empresa_id = v_emp, p.latitude, p.longitude, p.velocidade_nos, p.destino, p.eta, p.posicao_em
    from viagens_maritimas v
    join empresas e on e.id = v.empresa_id and e.estado = 'aprovada'
    left join navios_posicoes p on p.mmsi = v.mmsi
   where (v.publicada or v.empresa_id = v_emp or v_adm)
     and (p_sentido is null or v.sentido = p_sentido)
     and (p_de is null or (case when p_por = 'chegada' then coalesce(v.chegada, v.partida) else v.partida end) >= p_de)
     and (p_ate is null or (case when p_por = 'chegada' then coalesce(v.chegada, v.partida) else v.partida end) <= p_ate)
     and (v_p is null or v.porto_origem ilike '%' || v_p || '%' or v.porto_destino ilike '%' || v_p || '%')
     and (v_t is null or concat_ws(' ', v.navio, v.imo, v.mmsi, v.linha, v.viagem, e.nome, e.nome_comercial) ilike '%' || v_t || '%')
     and (not p_so_disponivel or (v.estado in ('aberta', 'planeada', 'atrasada') and (v.fecho_carga is null or v.fecho_carga >= current_date)
          and (coalesce(v.cont20_livres, 0) + coalesce(v.cont40_livres, 0) > 0 or coalesce(v.grupagem_m3, 0) > 0 or v.aceita_viaturas)))
   order by case when p_por = 'chegada' then coalesce(v.chegada, v.partida) else v.partida end, v.navio
   limit 200;
end $$;
revoke all on function public.pesquisa_maritima(text, text, date, date, text, boolean, text) from public, anon;
grant execute on function public.pesquisa_maritima(text, text, date, date, text, boolean, text) to authenticated;

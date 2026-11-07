-- v91 — A equipa Elolog (administração da plataforma) também publica viagens na Pesquisa marítima, sem depender
-- de prestadores nem de fontes AIS externas. Só ACRESCENTA uma tabela e substitui a função de pesquisa (mesma assinatura),
-- que passa a juntar as viagens dos prestadores e as da Elolog. Não altera ligações nem configuração do Supabase.

create table if not exists viagens_elolog (
  id            uuid primary key default gen_random_uuid(),
  navio         text not null check (length(navio) between 2 and 80),
  imo           text check (imo ~ '^[0-9]{7}$'),
  mmsi          text check (mmsi ~ '^[0-9]{9}$'),
  linha         text check (length(linha) <= 80),
  viagem        text check (length(viagem) <= 30),
  sentido       text not null check (sentido in ('PT-STP', 'STP-PT')),
  porto_origem  text not null check (length(porto_origem) between 2 and 60),
  porto_destino text not null check (length(porto_destino) between 2 and 60),
  partida       date not null,
  chegada       date,
  fecho_carga   date,
  estado        text not null default 'aberta' check (estado in ('planeada','aberta','lotada','partiu','chegou','atrasada','cancelada')),
  cont20_livres int check (cont20_livres between 0 and 9999),
  cont40_livres int check (cont40_livres between 0 and 9999),
  grupagem_m3   numeric(9,2) check (grupagem_m3 between 0 and 99999),
  aceita_viaturas boolean not null default false,
  notas         text check (length(notas) <= 300),
  publicada     boolean not null default true,
  criado_por    uuid references auth.users(id) on delete set null default auth.uid(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (chegada is null or chegada >= partida),
  check (fecho_carga is null or fecho_carga <= partida)
);
create index if not exists viagens_elolog_partida on viagens_elolog (sentido, partida);
alter table viagens_elolog enable row level security;
revoke all on viagens_elolog from anon;
grant select, insert, update, delete on viagens_elolog to authenticated;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'viagens_elolog' and policyname = 'viagens_elolog_ver') then
    create policy viagens_elolog_ver on viagens_elolog for select to authenticated using (publicada or private.e_admin_plataforma());
    create policy viagens_elolog_gerir on viagens_elolog for all to authenticated
      using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
  end if;
end $$;

create or replace function private.viagem_elolog_antes() returns trigger language plpgsql set search_path = public as $$
begin new.updated_at := now(); if tg_op = 'UPDATE' then new.criado_por := old.criado_por; end if; return new; end $$;
create or replace trigger viagem_elolog_antes before insert or update on viagens_elolog for each row execute function private.viagem_elolog_antes();
create or replace trigger auditar after insert or update or delete on viagens_elolog for each row execute function private.auditar_alteracao();
create or replace trigger limitar_escritas before insert or update on viagens_elolog for each row execute function private.limitar_escritas('60');

-- Pesquisa: viagens dos prestadores + viagens publicadas pela Elolog (mesma assinatura da 00153).
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
  with todas as (
    select v.id, v.navio, v.imo, v.mmsi, v.linha, v.viagem, v.sentido, v.porto_origem, v.porto_destino, v.partida, v.chegada, v.fecho_carga, v.estado,
           v.cont20_livres, v.cont40_livres, v.grupagem_m3, v.aceita_viaturas, v.notas, coalesce(e.nome_comercial, e.nome) as prestador, v.empresa_id,
           v.empresa_id = v_emp as minha, concat_ws(' ', e.nome, e.nome_comercial) as pesquisa_extra
      from viagens_maritimas v join empresas e on e.id = v.empresa_id and e.estado = 'aprovada'
     where v.publicada or v.empresa_id = v_emp or v_adm
    union all
    select g.id, g.navio, g.imo, g.mmsi, g.linha, g.viagem, g.sentido, g.porto_origem, g.porto_destino, g.partida, g.chegada, g.fecho_carga, g.estado,
           g.cont20_livres, g.cont40_livres, g.grupagem_m3, g.aceita_viaturas, g.notas, 'Elolog', null::uuid, v_adm, 'Elolog'
      from viagens_elolog g
     where g.publicada or v_adm)
  select t.id, t.navio, t.imo, t.mmsi, t.linha, t.viagem, t.sentido, t.porto_origem, t.porto_destino, t.partida, t.chegada, t.fecho_carga, t.estado,
         t.cont20_livres, t.cont40_livres, t.grupagem_m3, t.aceita_viaturas, t.notas, t.prestador, t.empresa_id, t.minha,
         p.latitude, p.longitude, p.velocidade_nos, p.destino, p.eta, p.posicao_em
    from todas t left join navios_posicoes p on p.mmsi = t.mmsi
   where (p_sentido is null or t.sentido = p_sentido)
     and (p_de is null or (case when p_por = 'chegada' then coalesce(t.chegada, t.partida) else t.partida end) >= p_de)
     and (p_ate is null or (case when p_por = 'chegada' then coalesce(t.chegada, t.partida) else t.partida end) <= p_ate)
     and (v_p is null or t.porto_origem ilike '%' || v_p || '%' or t.porto_destino ilike '%' || v_p || '%')
     and (v_t is null or concat_ws(' ', t.navio, t.imo, t.mmsi, t.linha, t.viagem, t.pesquisa_extra) ilike '%' || v_t || '%')
     and (not p_so_disponivel or (t.estado in ('aberta', 'planeada', 'atrasada') and (t.fecho_carga is null or t.fecho_carga >= current_date)
          and (coalesce(t.cont20_livres, 0) + coalesce(t.cont40_livres, 0) > 0 or coalesce(t.grupagem_m3, 0) > 0 or t.aceita_viaturas)))
   order by case when p_por = 'chegada' then coalesce(t.chegada, t.partida) else t.partida end, t.navio
   limit 200;
end $$;
revoke all on function public.pesquisa_maritima(text, text, date, date, text, boolean, text) from public, anon;
grant execute on function public.pesquisa_maritima(text, text, date, date, text, boolean, text) to authenticated;

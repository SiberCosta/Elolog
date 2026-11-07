-- v89 — Navios REAIS na rota Portugal ⇄ São Tomé e Príncipe, descobertos pelo AIS (navios-ais, a cada 30 min).
-- Só ACRESCENTA uma tabela e uma função de leitura; não altera ligações nem configuração do Supabase.
-- Precisa do segredo AISSTREAM_API_KEY (conta gratuita em aisstream.io) definido nas Edge Functions.

create table if not exists navios_rota (
  mmsi         text primary key check (mmsi ~ '^[0-9]{9}$'),
  nome         text,
  imo          text,
  tipo         int,
  destino      text not null,
  eta          timestamptz,
  sentido      text not null check (sentido in ('PT-STP', 'STP-PT')),
  latitude     double precision,
  longitude    double precision,
  visto_em     timestamptz not null,
  atualizado_em timestamptz not null default now()
);
create index if not exists navios_rota_sentido on navios_rota (sentido, visto_em desc);
alter table navios_rota enable row level security;
revoke all on navios_rota from anon, authenticated;            -- só o servidor escreve; a leitura é pela função abaixo

-- Navios vistos nos últimos 21 dias com destino na rota (com a última posição conhecida, se for seguido).
create or replace function public.navios_na_rota(p_sentido text default null, p_texto text default null)
returns table (mmsi text, nome text, imo text, destino text, eta timestamptz, sentido text, latitude double precision,
  longitude double precision, visto_em timestamptz, velocidade_nos numeric, posicao_em timestamptz)
language sql stable security definer set search_path = public as $$
  select r.mmsi, r.nome, r.imo, r.destino, r.eta, r.sentido,
         coalesce(p.latitude, r.latitude), coalesce(p.longitude, r.longitude), r.visto_em, p.velocidade_nos, p.posicao_em
    from navios_rota r left join navios_posicoes p on p.mmsi = r.mmsi
   where auth.uid() is not null
     and r.visto_em > now() - interval '21 days'
     and (p_sentido is null or r.sentido = p_sentido)
     and (nullif(trim(coalesce(p_texto, '')), '') is null
          or concat_ws(' ', r.nome, r.imo, r.mmsi, r.destino) ilike '%' || left(trim(p_texto), 60) || '%')
   order by coalesce(r.eta, r.visto_em + interval '30 days'), r.nome
   limit 100 $$;
revoke all on function public.navios_na_rota(text, text) from public, anon;
grant execute on function public.navios_na_rota(text, text) to authenticated;

-- v92 — Navios reais em São Tomé pela API MyShipTracking (função navios-mst, 3 vezes por dia).
-- Só ACRESCENTA colunas, uma função de leitura e uma tarefa agendada. Não altera ligações nem configuração do Supabase.
-- Precisa do segredo MYSHIPTRACKING_API_KEY nas Edge Functions (o utilizador define-o no painel do Supabase).

alter table navios_rota add column if not exists estado    text check (estado in ('a_caminho', 'no_porto', 'partiu'));
alter table navios_rota add column if not exists fonte     text not null default 'ais';
alter table navios_rota add column if not exists evento_em timestamptz;      -- chegada ao porto ou saída
alter table navios_rota add column if not exists tipo_txt  text;
alter table navios_rota add column if not exists bandeira  text;
alter table navios_rota add column if not exists gt        int;

-- Navios em São Tomé: a caminho e no porto (atualizados nas últimas 24 h) e saídas dos últimos 10 dias.
create or replace function public.navios_sao_tome(p_texto text default null)
returns table (mmsi text, nome text, imo text, estado text, sentido text, destino text, eta timestamptz, evento_em timestamptz,
  tipo_txt text, bandeira text, gt int, latitude double precision, longitude double precision, visto_em timestamptz, fonte text)
language sql stable security definer set search_path = public as $$
  select r.mmsi, r.nome, r.imo, coalesce(r.estado, 'a_caminho'), r.sentido, r.destino, r.eta, r.evento_em, r.tipo_txt, r.bandeira, r.gt,
         coalesce(p.latitude, r.latitude), coalesce(p.longitude, r.longitude), r.visto_em, r.fonte
    from navios_rota r left join navios_posicoes p on p.mmsi = r.mmsi
   where auth.uid() is not null
     and ((r.fonte = 'myshiptracking' and ((r.estado in ('a_caminho', 'no_porto') and r.visto_em > now() - interval '24 hours')
                                          or (r.estado = 'partiu' and r.evento_em > now() - interval '10 days')))
          or (r.fonte <> 'myshiptracking' and r.visto_em > now() - interval '21 days'))
     and (nullif(trim(coalesce(p_texto, '')), '') is null
          or concat_ws(' ', r.nome, r.imo, r.mmsi, r.tipo_txt, r.bandeira) ilike '%' || left(trim(p_texto), 60) || '%')
   order by case coalesce(r.estado, 'a_caminho') when 'no_porto' then 0 when 'a_caminho' then 1 else 2 end,
            coalesce(r.eta, r.evento_em), r.nome
   limit 150 $$;
revoke all on function public.navios_sao_tome(text) from public, anon;
grant execute on function public.navios_sao_tome(text) to authenticated;

-- Tarefa agendada: 3 vezes por dia (cerca de 50 créditos por execução com poucos navios).
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('elolog-navios-mst', '23 5,13,21 * * *', $c$select private.chamar_funcao('navios-mst')$c$);
  end if;
end $$;

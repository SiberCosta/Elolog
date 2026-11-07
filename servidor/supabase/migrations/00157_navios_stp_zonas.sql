-- v93 — Todos os navios com destino São Tomé (ST TMS) e partidas de São Tomé (MyShipTracking, 1 vez por dia).
-- Só ACRESCENTA uma coluna e uma função de leitura e muda o horário da tarefa já existente. Ligações Supabase inalteradas.

alter table navios_rota add column if not exists local text;     -- onde o navio foi visto (Lisboa, Leixões, Setúbal, Sines, São Tomé)

create or replace function public.navios_stp(p_texto text default null)
returns table (mmsi text, nome text, imo text, estado text, sentido text, destino text, eta timestamptz, evento_em timestamptz,
  tipo_txt text, bandeira text, gt int, latitude double precision, longitude double precision, visto_em timestamptz, local text)
language sql stable security definer set search_path = public as $$
  select r.mmsi, r.nome, r.imo, coalesce(r.estado, 'a_caminho'), r.sentido, r.destino, r.eta, r.evento_em, r.tipo_txt, r.bandeira, r.gt,
         coalesce(p.latitude, r.latitude), coalesce(p.longitude, r.longitude), r.visto_em, r.local
    from navios_rota r left join navios_posicoes p on p.mmsi = r.mmsi
   where auth.uid() is not null and r.fonte = 'myshiptracking'
     and ((r.estado in ('a_caminho', 'no_porto') and r.visto_em > now() - interval '36 hours')
          or (r.estado = 'partiu' and coalesce(r.evento_em, r.visto_em) > now() - interval '30 days'))
     and (nullif(trim(coalesce(p_texto, '')), '') is null
          or concat_ws(' ', r.nome, r.imo, r.mmsi, r.destino, r.local, r.tipo_txt, r.bandeira) ilike '%' || left(trim(p_texto), 60) || '%')
   order by case coalesce(r.estado, 'a_caminho') when 'no_porto' then 0 when 'a_caminho' then 1 else 2 end,
            case when r.estado = 'partiu' then null else coalesce(r.eta, r.visto_em) end, r.evento_em desc nulls last, r.nome
   limit 200 $$;
revoke all on function public.navios_stp(text) from public, anon;
grant execute on function public.navios_stp(text) to authenticated;

-- 1 vez por dia (06:23 UTC), como escolhido pelo utilizador (custo).
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('elolog-navios-mst', '23 6 * * *', $c$select private.chamar_funcao('navios-mst')$c$);
  end if;
end $$;

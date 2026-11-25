-- v169 — Site público gerido pela administração: saídas previstas, prestadores, novidades e avisos.
-- A administração decide o que aparece no site (área «Site público»); o site e o ELO leem tudo por uma só função pública
-- (site_conteudo), que devolve apenas dados que podem ser públicos: nunca NIF, emails, telefones, moradas nem preços.
-- Automático: com «auto» ligado, as saídas que os prestadores publicam no calendário, os prestadores aprovados e as novidades
-- (empresa nova, saída nova) aparecem sozinhos; a administração só esconde o que não quer mostrar.

create table if not exists public.site_publicacoes (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('novidade', 'aviso', 'destaque')),
  titulo text not null check (length(trim(titulo)) between 3 and 120),
  texto text check (texto is null or length(texto) <= 600),
  empresa_id uuid references public.empresas(id) on delete set null,
  ligacao text check (ligacao is null or ligacao ~ '^(https://(www\.)?elolog\.pt(/|$)|/|#|\.\./)'),
  ativo boolean not null default true,
  inicio date,
  fim date,
  criado_por uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (fim is null or inicio is null or fim >= inicio));
alter table public.site_publicacoes enable row level security;
drop policy if exists site_pub_admin on public.site_publicacoes;
create policy site_pub_admin on public.site_publicacoes for all to authenticated
  using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());

create table if not exists public.site_definicoes (
  chave text primary key check (chave in ('saidas', 'prestadores', 'feed')),
  valor jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now());
alter table public.site_definicoes enable row level security;
drop policy if exists site_def_admin on public.site_definicoes;
create policy site_def_admin on public.site_definicoes for all to authenticated
  using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
insert into public.site_definicoes (chave, valor) values
  ('saidas', '{"mostrar": true, "max": 6, "ocultas": []}'),
  ('prestadores', '{"mostrar": true, "auto": true, "max": 8, "escolhidos": [], "ocultos": []}'),
  ('feed', '{"mostrar": true, "auto": true, "max": 6}')
on conflict (chave) do nothing;

create or replace function public.site_conteudo()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare s jsonb; p jsonb; f jsonb; v_saidas jsonb := '[]'; v_prest jsonb := '[]'; v_feed jsonb := '[]'; v_avisos jsonb := '[]';
begin
  select valor into s from site_definicoes where chave = 'saidas';
  select valor into p from site_definicoes where chave = 'prestadores';
  select valor into f from site_definicoes where chave = 'feed';
  s := coalesce(s, '{}'); p := coalesce(p, '{}'); f := coalesce(f, '{}');

  if coalesce((s ->> 'mostrar')::boolean, true) then
    select coalesce(jsonb_agg(x order by x ->> 'partida'), '[]') into v_saidas from (
      select jsonb_build_object('id', v.id, 'navio', v.navio, 'viagem', v.viagem, 'origem', v.porto_origem, 'destino', v.porto_destino,
             'partida', v.partida, 'chegada', v.chegada, 'fecho_carga', v.fecho_carga, 'prestador', e.nome,
             'estado', v.estado, 'viaturas', coalesce(v.aceita_viaturas, false), 'grupagem', coalesce(v.grupagem_m3, 0) > 0) x
        from viagens_maritimas v join empresas_disponiveis e on e.id = v.empresa_id
       where v.publicada and v.partida >= current_date and coalesce(v.estado, 'planeada') not in ('cancelada', 'partiu', 'chegou')
         and not (coalesce(s -> 'ocultas', '[]') ? v.id::text)
       order by v.partida limit least(greatest(coalesce((s ->> 'max')::int, 6), 1), 24)) q;
  end if;

  if coalesce((p ->> 'mostrar')::boolean, true) then
    select coalesce(jsonb_agg(x order by o, n), '[]') into v_prest from (
      select jsonb_build_object('id', e.id, 'nome', e.nome, 'cidade', e.cidade, 'pais', e.pais,
             'saidas', (select count(*) from viagens_maritimas v where v.empresa_id = e.id and v.publicada and v.partida >= current_date),
             'texto', (select d.texto from site_publicacoes d where d.tipo = 'destaque' and d.empresa_id = e.id and d.ativo order by d.updated_at desc limit 1)) x,
             coalesce(array_position(array(select jsonb_array_elements_text(coalesce(p -> 'escolhidos', '[]'))), e.id::text), 999) o, e.nome n
        from empresas_disponiveis e
       where not (coalesce(p -> 'ocultos', '[]') ? e.id::text)
         and (coalesce((p ->> 'auto')::boolean, true) or coalesce(p -> 'escolhidos', '[]') ? e.id::text)
       order by o, n limit least(greatest(coalesce((p ->> 'max')::int, 8), 1), 48)) q;
  end if;

  if coalesce((f ->> 'mostrar')::boolean, true) then
    select coalesce(jsonb_agg(x order by x ->> 'data' desc), '[]') into v_feed from (
      select * from (
        select jsonb_build_object('tipo', 'novidade', 'titulo', d.titulo, 'texto', d.texto, 'ligacao', d.ligacao,
               'prestador', (select nome from empresas_disponiveis where id = d.empresa_id), 'data', coalesce(d.inicio::timestamptz, d.created_at)) x
          from site_publicacoes d
         where d.tipo = 'novidade' and d.ativo and (d.inicio is null or d.inicio <= current_date) and (d.fim is null or d.fim >= current_date)
        union all
        select jsonb_build_object('tipo', 'prestador', 'titulo', e.nome || ' juntou-se à Elolog', 'texto', 'Novo prestador verificado' ||
               coalesce(' em ' || nullif(e.cidade, ''), '') || '. Já pode pedir-lhe preço no simulador.', 'prestador', e.nome, 'data', em.aprovada_em) x
          from empresas_disponiveis e join empresas em on em.id = e.id
         where coalesce((f ->> 'auto')::boolean, true) and em.aprovada_em >= now() - interval '90 days'
           and not (coalesce(p -> 'ocultos', '[]') ? e.id::text)
        union all
        select jsonb_build_object('tipo', 'saida', 'titulo', 'Nova saída: ' || coalesce(v.porto_origem, '—') || ' → ' || coalesce(v.porto_destino, '—'),
               'texto', coalesce(v.navio || ' · ', '') || 'parte a ' || to_char(v.partida, 'DD/MM/YYYY') ||
               coalesce(', fecho de carga a ' || to_char(v.fecho_carga, 'DD/MM'), '') || '.', 'prestador', e.nome, 'data', v.created_at) x
          from viagens_maritimas v join empresas_disponiveis e on e.id = v.empresa_id
         where coalesce((f ->> 'auto')::boolean, true) and v.publicada and v.partida >= current_date and v.created_at >= now() - interval '30 days'
           and coalesce(v.estado, 'planeada') not in ('cancelada', 'partiu', 'chegou') and not (coalesce(s -> 'ocultas', '[]') ? v.id::text)
      ) t order by x ->> 'data' desc limit least(greatest(coalesce((f ->> 'max')::int, 6), 1), 24)) q;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('titulo', d.titulo, 'texto', d.texto, 'ligacao', d.ligacao) order by d.created_at desc), '[]') into v_avisos
    from site_publicacoes d where d.tipo = 'aviso' and d.ativo and (d.inicio is null or d.inicio <= current_date) and (d.fim is null or d.fim >= current_date);

  return jsonb_build_object('saidas', v_saidas, 'prestadores', v_prest, 'feed', v_feed, 'avisos', v_avisos, 'gerado', now());
end $$;
revoke all on function public.site_conteudo() from public;
grant execute on function public.site_conteudo() to anon, authenticated;

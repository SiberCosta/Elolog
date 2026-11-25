-- 00205: anúncios com fundo e público (site / plataforma), classificações dos prestadores.
-- 1) site_publicacoes: fundo (#rrggbb), publico (site, plataforma, ambos) e para (todos, clientes, prestadores).
--    public.plataforma_avisos(): avisos e novidades para quem tem sessão na plataforma, segundo o perfil.
-- 2) avaliacoes_prestador: o cliente avalia (1 a 5) o prestador de uma encomenda sua já entregue, uma vez por encomenda
--    (pode corrigir durante 30 dias). A administração pode ocultar. A empresa lê as suas avaliações.
--    public.avaliar_prestador(): único caminho de escrita do cliente (valida dono, estado e notas).
-- 3) prestador_classificacao: nível atribuído pela administração (recomendado, ouro, prata, bronze) e nota interna.
-- 4) site_conteudo(): fundo nos anúncios, só os do site; prestadores com nível, média e n.º de avaliações publicadas.
alter table public.site_publicacoes add column if not exists fundo text;
alter table public.site_publicacoes add column if not exists publico text not null default 'site';
alter table public.site_publicacoes add column if not exists para text not null default 'todos';
alter table public.site_publicacoes drop constraint if exists site_publicacoes_fundo_check;
alter table public.site_publicacoes add constraint site_publicacoes_fundo_check check (fundo is null or fundo ~ '^#[0-9a-fA-F]{6}$');
alter table public.site_publicacoes drop constraint if exists site_publicacoes_publico_check;
alter table public.site_publicacoes add constraint site_publicacoes_publico_check check (publico in ('site', 'plataforma', 'ambos'));
alter table public.site_publicacoes drop constraint if exists site_publicacoes_para_check;
alter table public.site_publicacoes add constraint site_publicacoes_para_check check (para in ('todos', 'clientes', 'prestadores'));

create or replace function public.plataforma_avisos()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'tipo', d.tipo, 'titulo', d.titulo, 'texto', d.texto, 'ligacao', d.ligacao,
         'cor', d.cor, 'fundo', d.fundo, 'data', coalesce(d.inicio::timestamptz, d.created_at))
         order by (d.cor = 'vermelho') desc nulls last, d.created_at desc), '[]')
    from site_publicacoes d
   where auth.uid() is not null and d.tipo in ('aviso', 'novidade') and d.ativo and d.publico in ('plataforma', 'ambos')
     and (d.inicio is null or d.inicio <= current_date) and (d.fim is null or d.fim >= current_date)
     and (d.para = 'todos' or (d.para = 'prestadores' and private.minha_empresa() is not null)
          or (d.para = 'clientes' and private.minha_empresa() is null and not private.e_admin_plataforma()));
$$;
revoke all on function public.plataforma_avisos() from public;
grant execute on function public.plataforma_avisos() to authenticated;

create table if not exists public.avaliacoes_prestador (
  id uuid primary key default gen_random_uuid(),
  encomenda_id uuid not null unique references public.encomendas(id) on delete cascade,
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  cliente_id uuid not null default auth.uid(),
  nota smallint not null check (nota between 1 and 5),
  pontualidade smallint check (pontualidade between 1 and 5),
  comunicacao smallint check (comunicacao between 1 and 5),
  cuidado smallint check (cuidado between 1 and 5),
  comentario text check (comentario is null or length(comentario) <= 500),
  estado text not null default 'publicada' check (estado in ('publicada', 'oculta')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create index if not exists avaliacoes_prestador_empresa on public.avaliacoes_prestador (empresa_id, estado);
alter table public.avaliacoes_prestador enable row level security;
drop policy if exists aval_ver on public.avaliacoes_prestador;
create policy aval_ver on public.avaliacoes_prestador for select to authenticated
  using (cliente_id = (select auth.uid()) or empresa_id = private.minha_empresa() or private.e_admin_plataforma());
drop policy if exists aval_admin on public.avaliacoes_prestador;
create policy aval_admin on public.avaliacoes_prestador for update to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
revoke insert, delete on public.avaliacoes_prestador from authenticated, anon;

create or replace function public.avaliar_prestador(p_encomenda uuid, p_nota int, p_pontualidade int default null,
  p_comunicacao int default null, p_cuidado int default null, p_comentario text default null)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $$
declare e record; a record;
begin
  if auth.uid() is null then raise exception 'Inicie sessão para avaliar.'; end if;
  if p_nota is null or p_nota not between 1 and 5 then raise exception 'Escolha de 1 a 5 estrelas.'; end if;
  if coalesce(p_pontualidade, 3) not between 1 and 5 or coalesce(p_comunicacao, 3) not between 1 and 5 or coalesce(p_cuidado, 3) not between 1 and 5 then
    raise exception 'Cada critério vai de 1 a 5.'; end if;
  select id, empresa_id, cliente_id, estado into e from encomendas where id = p_encomenda;
  if e.id is null or e.cliente_id is distinct from auth.uid() then raise exception 'Só pode avaliar encomendas suas.'; end if;
  if e.estado <> 'entregue' then raise exception 'Pode avaliar depois de a encomenda ser entregue.'; end if;
  select * into a from avaliacoes_prestador where encomenda_id = p_encomenda;
  if a.id is not null and a.created_at < now() - interval '30 days' then raise exception 'A avaliação só pode ser corrigida nos primeiros 30 dias.'; end if;
  insert into avaliacoes_prestador (encomenda_id, empresa_id, cliente_id, nota, pontualidade, comunicacao, cuidado, comentario)
  values (p_encomenda, e.empresa_id, auth.uid(), p_nota, p_pontualidade, p_comunicacao, p_cuidado, nullif(left(trim(coalesce(p_comentario, '')), 500), ''))
  on conflict (encomenda_id) do update set nota = excluded.nota, pontualidade = excluded.pontualidade, comunicacao = excluded.comunicacao,
    cuidado = excluded.cuidado, comentario = excluded.comentario, updated_at = now();
  return jsonb_build_object('ok', true, 'nota', p_nota);
end $$;
revoke all on function public.avaliar_prestador(uuid, int, int, int, int, text) from public;
grant execute on function public.avaliar_prestador(uuid, int, int, int, int, text) to authenticated;

-- Encomendas entregues do próprio cliente (últimos 120 dias), com o nome do prestador e a avaliação já dada, se houver.
create or replace function public.avaliacoes_minhas()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(jsonb_build_object('encomenda_id', e.id, 'codigo', e.codigo, 'origem', e.origem, 'destino', e.destino,
         'prestador', coalesce(em.nome_comercial, em.nome), 'entregue_em', e.updated_at, 'nota', a.nota, 'comentario', a.comentario,
         'pode_corrigir', a.id is null or a.created_at >= now() - interval '30 days') order by e.updated_at desc), '[]')
    from encomendas e join empresas em on em.id = e.empresa_id
    left join avaliacoes_prestador a on a.encomenda_id = e.id
   where auth.uid() is not null and e.cliente_id = auth.uid() and e.estado = 'entregue' and e.updated_at >= now() - interval '120 days';
$$;
revoke all on function public.avaliacoes_minhas() from public;
grant execute on function public.avaliacoes_minhas() to authenticated;

create table if not exists public.prestador_classificacao (
  empresa_id uuid primary key references public.empresas(id) on delete cascade,
  nivel text check (nivel is null or nivel in ('recomendado', 'ouro', 'prata', 'bronze')),
  nota_interna text check (nota_interna is null or length(nota_interna) <= 500),
  atualizado_por uuid default auth.uid(), updated_at timestamptz not null default now());
alter table public.prestador_classificacao enable row level security;
drop policy if exists class_admin on public.prestador_classificacao;
create policy class_admin on public.prestador_classificacao for all to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());

create or replace function public.site_conteudo()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare s jsonb; p jsonb; f jsonb; v_cal jsonb := '[]'; v_saidas jsonb := '[]'; v_prest jsonb := '[]'; v_feed jsonb := '[]'; v_avisos jsonb := '[]';
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

  if coalesce((s ->> 'calendario')::boolean, false) then
    select coalesce(jsonb_agg(x order by x ->> 'partida'), '[]') into v_cal from (
      select jsonb_build_object('partida', v.partida, 'fecho_carga', v.fecho_carga, 'origem', v.porto_origem, 'destino', v.porto_destino,
             'navio', v.navio, 'prestador', e.nome, 'estado', v.estado) x
        from viagens_maritimas v join empresas_disponiveis e on e.id = v.empresa_id
       where v.publicada and v.partida >= current_date and v.partida < current_date + 180
         and coalesce(v.estado, 'planeada') not in ('cancelada', 'partiu', 'chegou') and not (coalesce(s -> 'ocultas', '[]') ? v.id::text)
       order by v.partida limit 80) q;
  end if;

  if coalesce((p ->> 'mostrar')::boolean, true) then
    select coalesce(jsonb_agg(x order by o, r, m desc nulls last, n), '[]') into v_prest from (
      select jsonb_build_object('id', e.id, 'nome', e.nome, 'cidade', e.cidade, 'pais', e.pais,
             'saidas', (select count(*) from viagens_maritimas v where v.empresa_id = e.id and v.publicada and v.partida >= current_date),
             'texto', (select d.texto from site_publicacoes d where d.tipo = 'destaque' and d.empresa_id = e.id and d.ativo order by d.updated_at desc limit 1),
             'nivel', c.nivel, 'media', a.media, 'avaliacoes', coalesce(a.total, 0)) x,
             coalesce(array_position(array(select jsonb_array_elements_text(coalesce(p -> 'escolhidos', '[]'))), e.id::text), 999) o,
             coalesce(array_position(array['recomendado', 'ouro', 'prata', 'bronze'], c.nivel), 9) r, a.media m, e.nome n
        from empresas_disponiveis e
        left join prestador_classificacao c on c.empresa_id = e.id
        left join lateral (select round(avg(r.nota)::numeric, 1) media, count(*) total from avaliacoes_prestador r where r.empresa_id = e.id and r.estado = 'publicada') a on true
       where not (coalesce(p -> 'ocultos', '[]') ? e.id::text)
         and (coalesce((p ->> 'auto')::boolean, true) or coalesce(p -> 'escolhidos', '[]') ? e.id::text)
       order by o, r, m desc nulls last, n limit least(greatest(coalesce((p ->> 'max')::int, 8), 1), 48)) q;
  end if;

  if coalesce((f ->> 'mostrar')::boolean, true) then
    select coalesce(jsonb_agg(x order by x ->> 'data' desc), '[]') into v_feed from (
      select * from (
        select jsonb_build_object('tipo', 'novidade', 'cor', d.cor, 'fundo', d.fundo, 'titulo', d.titulo, 'texto', d.texto, 'ligacao', d.ligacao,
               'prestador', (select nome from empresas_disponiveis where id = d.empresa_id), 'data', coalesce(d.inicio::timestamptz, d.created_at)) x
          from site_publicacoes d
         where d.tipo = 'novidade' and d.ativo and d.publico in ('site', 'ambos') and (d.inicio is null or d.inicio <= current_date) and (d.fim is null or d.fim >= current_date)
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

  select coalesce(jsonb_agg(jsonb_build_object('titulo', d.titulo, 'texto', d.texto, 'ligacao', d.ligacao, 'cor', coalesce(d.cor, 'amarelo'), 'fundo', d.fundo) order by (d.cor = 'vermelho') desc nulls last, d.created_at desc), '[]') into v_avisos
    from site_publicacoes d where d.tipo = 'aviso' and d.ativo and d.publico in ('site', 'ambos') and (d.inicio is null or d.inicio <= current_date) and (d.fim is null or d.fim >= current_date);

  return jsonb_build_object('faixa', coalesce((f ->> 'faixa')::boolean, true), 'calendario', v_cal, 'calendario_ativo', coalesce((s ->> 'calendario')::boolean, false), 'saidas', v_saidas, 'prestadores', v_prest, 'feed', v_feed, 'avisos', v_avisos, 'gerado', now());
end $$;
revoke all on function public.site_conteudo() from public;
grant execute on function public.site_conteudo() to anon, authenticated;

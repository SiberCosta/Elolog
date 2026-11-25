-- 00206: cor do título nos avisos e novidades; logótipo dos prestadores nas classificações.
-- site_publicacoes.cor_titulo (#rrggbb). prestador_classificacao.logo: endereço público de uma imagem guardada no
-- armazenamento «site-publico» (PNG, JPEG ou WebP até 1 MB; só a administração carrega, altera ou apaga; todos podem ver).
-- site_conteudo() passa a devolver cor_titulo e logo.
alter table public.site_publicacoes add column if not exists cor_titulo text;
alter table public.site_publicacoes drop constraint if exists site_publicacoes_cor_titulo_check;
alter table public.site_publicacoes add constraint site_publicacoes_cor_titulo_check check (cor_titulo is null or cor_titulo ~ '^#[0-9a-fA-F]{6}$');
alter table public.prestador_classificacao add column if not exists logo text;
alter table public.prestador_classificacao drop constraint if exists prestador_classificacao_logo_check;
alter table public.prestador_classificacao add constraint prestador_classificacao_logo_check check (logo is null or logo ~ '^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/site-publico/');

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('site-publico', 'site-publico', true, 1048576, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp'];
drop policy if exists site_publico_admin_inserir on storage.objects;
create policy site_publico_admin_inserir on storage.objects for insert to authenticated with check (bucket_id = 'site-publico' and private.e_admin_plataforma());
drop policy if exists site_publico_admin_alterar on storage.objects;
create policy site_publico_admin_alterar on storage.objects for update to authenticated using (bucket_id = 'site-publico' and private.e_admin_plataforma()) with check (bucket_id = 'site-publico' and private.e_admin_plataforma());
drop policy if exists site_publico_admin_apagar on storage.objects;
create policy site_publico_admin_apagar on storage.objects for delete to authenticated using (bucket_id = 'site-publico' and private.e_admin_plataforma());

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
             'nivel', c.nivel, 'logo', c.logo, 'media', a.media, 'avaliacoes', coalesce(a.total, 0)) x,
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
        select jsonb_build_object('tipo', 'novidade', 'cor', d.cor, 'fundo', d.fundo, 'cor_titulo', d.cor_titulo, 'titulo', d.titulo, 'texto', d.texto, 'ligacao', d.ligacao,
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

  select coalesce(jsonb_agg(jsonb_build_object('titulo', d.titulo, 'texto', d.texto, 'ligacao', d.ligacao, 'cor', coalesce(d.cor, 'amarelo'), 'fundo', d.fundo, 'cor_titulo', d.cor_titulo) order by (d.cor = 'vermelho') desc nulls last, d.created_at desc), '[]') into v_avisos
    from site_publicacoes d where d.tipo = 'aviso' and d.ativo and d.publico in ('site', 'ambos') and (d.inicio is null or d.inicio <= current_date) and (d.fim is null or d.fim >= current_date);

  return jsonb_build_object('faixa', coalesce((f ->> 'faixa')::boolean, true), 'calendario', v_cal, 'calendario_ativo', coalesce((s ->> 'calendario')::boolean, false), 'saidas', v_saidas, 'prestadores', v_prest, 'feed', v_feed, 'avisos', v_avisos, 'gerado', now());
end $$;
revoke all on function public.site_conteudo() from public;
grant execute on function public.site_conteudo() to anon, authenticated;

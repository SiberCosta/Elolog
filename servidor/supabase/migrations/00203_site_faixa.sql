-- 00203: faixa de informação a correr no site (definição feed.faixa, ligada por omissão).
-- Só acrescenta o campo «faixa» ao resultado de site_conteudo(); nada mais muda.
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

  return jsonb_build_object('faixa', coalesce((f ->> 'faixa')::boolean, true), 'saidas', v_saidas, 'prestadores', v_prest, 'feed', v_feed, 'avisos', v_avisos, 'gerado', now());
end $$;
revoke all on function public.site_conteudo() from public;
grant execute on function public.site_conteudo() to anon, authenticated;

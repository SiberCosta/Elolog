-- 00207: plataforma_avisos() devolve também a cor do título (cor_titulo, migração 00206).
create or replace function public.plataforma_avisos()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'tipo', d.tipo, 'titulo', d.titulo, 'texto', d.texto, 'ligacao', d.ligacao,
         'cor', d.cor, 'fundo', d.fundo, 'cor_titulo', d.cor_titulo, 'data', coalesce(d.inicio::timestamptz, d.created_at))
         order by (d.cor = 'vermelho') desc nulls last, d.created_at desc), '[]')
    from site_publicacoes d
   where auth.uid() is not null and d.tipo in ('aviso', 'novidade') and d.ativo and d.publico in ('plataforma', 'ambos')
     and (d.inicio is null or d.inicio <= current_date) and (d.fim is null or d.fim >= current_date)
     and (d.para = 'todos' or (d.para = 'prestadores' and private.minha_empresa() is not null)
          or (d.para = 'clientes' and private.minha_empresa() is null and not private.e_admin_plataforma()));
$$;
revoke all on function public.plataforma_avisos() from public;
grant execute on function public.plataforma_avisos() to authenticated;

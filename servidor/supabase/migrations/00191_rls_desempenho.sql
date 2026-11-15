-- v136 (auditoria, desempenho): regras de acesso que chamavam auth.uid() em cada linha passam a usar (select auth.uid()),
-- calculado uma só vez por pedido (aviso «auth_rls_initplan» do Supabase). A regra é exatamente a mesma: muda só a forma de cálculo.
-- Antes de alterar, guarda a definição original de cada regra em private.politicas_copia_v136 (para repor, se for preciso).
-- Índices para as chaves estrangeiras sem índice (aviso «unindexed_foreign_keys»): só acrescenta índices.
create table if not exists private.politicas_copia_v136 (tabela text, politica text, original text, guardado_em timestamptz default now(), primary key (tabela, politica));
alter table private.politicas_copia_v136 enable row level security;

do $$ declare r record; q text; w text;
begin
  for r in select * from pg_policies where schemaname = 'public'
            and ((qual ~ 'auth\.uid\(\)' and qual !~* '\(\s*select\s+auth\.') or (with_check ~ 'auth\.uid\(\)' and with_check !~* '\(\s*select\s+auth\.')) loop
    insert into private.politicas_copia_v136 (tabela, politica, original)
    values (r.tablename, r.policyname, format('alter policy %I on public.%I%s%s;', r.policyname, r.tablename,
            case when r.qual is not null then ' using (' || r.qual || ')' else '' end, case when r.with_check is not null then ' with check (' || r.with_check || ')' else '' end))
    on conflict do nothing;
    q := case when r.qual is not null then ' using (' || regexp_replace(r.qual, 'auth\.uid\(\)', '(select auth.uid())', 'g') || ')' else '' end;
    w := case when r.with_check is not null then ' with check (' || regexp_replace(r.with_check, 'auth\.uid\(\)', '(select auth.uid())', 'g') || ')' else '' end;
    execute format('alter policy %I on public.%I', r.policyname, r.tablename) || q || w;
  end loop;
end $$;

-- índices das chaves estrangeiras (esquema public) que ainda não têm um índice a começar por essas colunas
do $$ declare r record; nome text;
begin
  for r in
    select c.conrelid::regclass as tabela, cl.relname, c.conname, array_agg(a.attname order by k.ord) cols
    from pg_constraint c join pg_class cl on cl.oid = c.conrelid join pg_namespace n on n.oid = cl.relnamespace
    cross join lateral unnest(c.conkey) with ordinality k(attnum, ord) join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
    where c.contype = 'f' and n.nspname = 'public'
      and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and (i.indkey::int2[])[0:cardinality(c.conkey)-1] = c.conkey)
    group by c.conrelid, cl.relname, c.conname
  loop
    nome := left('idx_' || r.relname || '_' || array_to_string(r.cols, '_'), 63);
    execute format('create index if not exists %I on %s (%s)', nome, r.tabela, (select string_agg(quote_ident(x), ', ') from unnest(r.cols) x));
  end loop;
end $$;

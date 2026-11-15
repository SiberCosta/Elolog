-- v140: segunda cópia de segurança (Cloudflare R2). Exporta os DADOS de todas as tabelas dos esquemas public e private num só
-- documento JSON. Só o service_role a executa (pela Edge Function «copia-dados», que cifra o resultado antes de o entregar ao
-- Worker do Cloudflare). A estrutura (tabelas, regras, funções) vem dos instaladores; esta cópia guarda os registos.
-- Só acrescenta uma função; não altera dados nem permissões existentes.
create or replace function public.servico_exportar_dados() returns jsonb language plpgsql security definer set search_path = '' as $$
declare r record; j jsonb; res jsonb := '{}'::jsonb; n int := 0;
begin
  for r in select ns.nspname as esquema, c.relname as tabela from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
           where c.relkind = 'r' and ns.nspname in ('public', 'private') order by 1, 2 loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from %I.%I x', r.esquema, r.tabela) into j;
    res := res || jsonb_build_object(r.esquema || '.' || r.tabela, j); n := n + jsonb_array_length(j);
  end loop;
  return jsonb_build_object('formato', 'elolog-dados-1', 'gerado_em', now(), 'registos', n, 'tabelas', res);
end $$;
revoke all on function public.servico_exportar_dados() from public, anon, authenticated;
grant execute on function public.servico_exportar_dados() to service_role;

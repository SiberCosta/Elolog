-- v78 — A Área de Cliente é só para clientes: uma conta da equipa Elolog ou de um funcionário de prestador
-- já não consegue entrar como cliente (nem criar um perfil de cliente por engano).

-- Tipo de conta da sessão: 'equipa' (Elolog), 'funcionario' (prestador), 'cliente' ou null.
create or replace function public.tipo_conta() returns text
language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from administradores_plataforma where user_id = auth.uid()) then 'equipa'
              when exists (select 1 from funcionarios where id = auth.uid()) then 'funcionario'
              when exists (select 1 from clientes where id = auth.uid()) then 'cliente' end
$$;
revoke all on function public.tipo_conta() from public, anon;
grant execute on function public.tipo_conta() to authenticated;

-- A base de dados recusa criar um perfil de cliente para contas da equipa ou de prestadores.
do $$ begin
  create policy clientes_so_clientes on clientes as restrictive for insert to authenticated
    with check (not exists (select 1 from administradores_plataforma a where a.user_id = auth.uid())
            and not exists (select 1 from funcionarios f where f.id = auth.uid()));
exception when duplicate_object then null; end $$;

-- Limpar perfis de cliente criados por engano para contas da equipa/prestadores (só os que não têm simulações nem encomendas).
delete from clientes c
 where (exists (select 1 from administradores_plataforma a where a.user_id = c.id) or exists (select 1 from funcionarios f where f.id = c.id))
   and not exists (select 1 from encomendas e where e.cliente_id = c.id) and not exists (select 1 from simulacoes s where s.cliente_id = c.id);

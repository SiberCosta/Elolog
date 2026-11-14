-- v132: contador mensal de pedidos ao HERE (mapas pagos acima de uma quota gratuita). A Edge Function «mapas-here» pára de pedir
-- ao HERE quando o mês chega ao limite definido (por omissão 90 % da quota gratuita) e a aplicação usa os serviços gratuitos.
-- Só acrescenta uma tabela e uma função; acesso só do service_role.
create table if not exists public.here_uso (
  mes text not null check (mes ~ '^\d{4}-\d{2}$'), tipo text not null check (tipo in ('rota', 'morada')),
  total int not null default 0, atualizado_em timestamptz not null default now(), primary key (mes, tipo));
alter table public.here_uso enable row level security;
revoke all on public.here_uso from anon, authenticated;

create or replace function public.servico_here_contar(p_tipo text, p_max int) returns boolean language plpgsql security definer set search_path = public as $$
declare v int; m text := to_char(now() at time zone 'Europe/Lisbon', 'YYYY-MM');
begin
  if p_tipo not in ('rota', 'morada') or p_max < 0 then raise exception 'Parâmetros inválidos.'; end if;
  insert into here_uso (mes, tipo, total) values (m, p_tipo, 1)
  on conflict (mes, tipo) do update set total = here_uso.total + 1, atualizado_em = now() where here_uso.total < p_max
  returning total into v;
  return v is not null and v <= p_max;
end $$;
revoke all on function public.servico_here_contar(text, int) from public, anon, authenticated;
grant execute on function public.servico_here_contar(text, int) to service_role;

-- quanto já se gastou este mês (para a administração da plataforma ver no painel, sem mostrar a chave)
create or replace function public.here_uso_mes() returns table (tipo text, total int) language sql stable security definer set search_path = public as $$
  select tipo, total from here_uso where mes = to_char(now() at time zone 'Europe/Lisbon', 'YYYY-MM') and private.e_admin_plataforma() $$;
revoke all on function public.here_uso_mes() from public, anon;
grant execute on function public.here_uso_mes() to authenticated;

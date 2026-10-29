-- v75 — Declarações da encomenda (6 modelos internos de apoio): os dados preenchem-se uma vez e servem a todos os modelos.
-- O cliente preenche proprietário, destinatário, viatura e bens; o prestador da encomenda completa o embarque e pode corrigir tudo.

create table if not exists encomenda_declaracoes (
  encomenda_id   uuid primary key references encomendas(id) on delete cascade,
  dados          jsonb not null default '{}'::jsonb check (jsonb_typeof(dados) = 'object' and pg_column_size(dados) < 200000),
  atualizado_por uuid references auth.users(id) on delete set null,
  updated_at     timestamptz not null default now()
);
alter table encomenda_declaracoes enable row level security;
revoke all on encomenda_declaracoes from anon, authenticated;

-- Encomenda pelo código, só para o cliente dela ou para a empresa prestadora. Devolve também quem está a pedir.
create or replace function private.declaracao_acesso(p_codigo text, out v_id uuid, out v_papel text)
language sql stable security definer set search_path = public as $$
  select e.id, case when e.cliente_id = auth.uid() then 'cliente' else 'empresa' end
  from encomendas e where e.codigo = p_codigo
    and (e.cliente_id = auth.uid() or (private.minha_empresa() is not null and e.empresa_id = private.minha_empresa()))
$$;

create or replace function public.declaracoes_ler(p_codigo text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a record; r jsonb;
begin
  select * into a from private.declaracao_acesso(p_codigo);
  if a.v_id is null then raise exception 'Encomenda não encontrada.'; end if;
  select jsonb_build_object('codigo', e.codigo, 'origem', e.origem, 'destino', e.destino, 'papel', a.v_papel,
      'cliente', jsonb_build_object('nome', c.nome, 'nif', c.nif, 'telefone', c.telefone, 'morada', c.morada, 'email', c.email),
      'empresa', jsonb_build_object('nome', coalesce(m.nome_comercial, m.nome), 'nif', m.nif, 'email', m.email, 'telefone', m.telefone),
      'dados', coalesce(d.dados, '{}'::jsonb), 'atualizado_em', d.updated_at)
    into r
  from encomendas e left join clientes c on c.id = e.cliente_id left join empresas m on m.id = e.empresa_id
    left join encomenda_declaracoes d on d.encomenda_id = e.id
  where e.id = a.v_id;
  return r;
end $$;

create or replace function public.declaracoes_gravar(p_codigo text, p_dados jsonb) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare a record; v_antes jsonb; v_novo jsonb; v_quando timestamptz := now();
begin
  select * into a from private.declaracao_acesso(p_codigo);
  if a.v_id is null then raise exception 'Encomenda não encontrada.'; end if;
  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then raise exception 'Dados inválidos.'; end if;
  if jsonb_typeof(coalesce(p_dados->'bens', '[]')) <> 'array' or jsonb_array_length(coalesce(p_dados->'bens', '[]')) > 300 then raise exception 'A lista de bens é inválida (máximo 300 linhas).'; end if;
  select dados into v_antes from encomenda_declaracoes where encomenda_id = a.v_id;
  v_novo := p_dados;
  if a.v_papel = 'cliente' then   -- o embarque é do prestador
    v_novo := (v_novo - 'embarque') || jsonb_build_object('embarque', coalesce(v_antes->'embarque', '{}'::jsonb));
  end if;
  insert into encomenda_declaracoes (encomenda_id, dados, atualizado_por, updated_at) values (a.v_id, v_novo, auth.uid(), v_quando)
  on conflict (encomenda_id) do update set dados = excluded.dados, atualizado_por = excluded.atualizado_por, updated_at = excluded.updated_at;
  return v_quando;
end $$;

revoke all on function private.declaracao_acesso(text), public.declaracoes_ler(text), public.declaracoes_gravar(text, jsonb) from public, anon;
grant execute on function public.declaracoes_ler(text), public.declaracoes_gravar(text, jsonb) to authenticated;

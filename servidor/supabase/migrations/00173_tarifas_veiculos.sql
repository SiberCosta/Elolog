-- v115 — Regras de cobrança (1/2): tarifários de veículos, referência visível aos prestadores e acessos do prestador ao centro.
-- Tarifa de veículo: custo da recolha/entrega por tipo de veículo (saída + km, com mínimo), escolhida pela capacidade que o pedido precisa.
-- Mesmo circuito das outras tarifas: o prestador submete, a administração aprova; tudo fica no histórico.

create table if not exists public.tarifas_veiculos (
  id uuid primary key default gen_random_uuid(), empresa_id uuid references public.empresas(id) on delete cascade,   -- null = tarifa geral da Elolog
  nome text not null check (length(trim(nome)) between 1 and 120), veiculo text not null default 'carrinha'
    check (veiculo in ('mota','ligeiro','carrinha','camiao_pequeno','camiao','pesado','outro')),
  capacidade_kg numeric check (capacidade_kg is null or capacidade_kg > 0), capacidade_m3 numeric check (capacidade_m3 is null or capacidade_m3 > 0),
  preco_saida numeric not null default 0 check (preco_saida >= 0 and preco_saida <= 1000000),
  preco_km numeric not null default 0 check (preco_km >= 0 and preco_km <= 100000),
  preco_minimo numeric not null default 0 check (preco_minimo >= 0 and preco_minimo <= 1000000),
  moeda text not null default 'EUR', servico text, versao int not null default 1,
  estado text not null default 'pendente' check (estado in ('pendente','aprovado','rejeitado','suspenso','inativo')),
  validade_inicio date, validade_fim date, motivo_decisao text, motivo_alteracao text, criado_por uuid references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint tarifas_veiculos_validade check (validade_fim is null or validade_inicio is null or validade_fim >= validade_inicio));
create index if not exists tarifas_veiculos_empresa on public.tarifas_veiculos (empresa_id, estado);
alter table public.tarifas_veiculos enable row level security;
revoke all on public.tarifas_veiculos from anon;
grant select, insert, update on public.tarifas_veiculos to authenticated;
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas_veiculos' and policyname = 'tv_admin') then
  create policy tv_admin on public.tarifas_veiculos for all to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
end if; end $$;
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas_veiculos' and policyname = 'tv_empresa') then
  create policy tv_empresa on public.tarifas_veiculos for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']))
  with check (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']));
end if; end $$;
-- os prestadores veem as tarifas gerais de veículos em vigor (para comparar), sem as poder mudar
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas_veiculos' and policyname = 'tv_geral_ve') then
  create policy tv_geral_ve on public.tarifas_veiculos for select to authenticated
  using (empresa_id is null and estado = 'aprovado' and private.minha_empresa() is not null);
end if; end $$;

-- guarda: o prestador só cria «pendente»; mudar preço ou capacidade de uma tarifa aprovada volta a «pendente» e sobe a versão
create or replace function private.veiculo_guarda() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if auth.uid() is not null and not private.e_admin_plataforma() then
    if new.empresa_id is null then raise exception 'As tarifas gerais de veículos são da administração Elolog.' using errcode = '42501'; end if;
    if tg_op = 'INSERT' then new.estado := 'pendente'; new.motivo_decisao := null; new.versao := 1;
    else
      new.motivo_decisao := old.motivo_decisao; new.empresa_id := old.empresa_id;
      if (new.veiculo, new.capacidade_kg, new.capacidade_m3, new.preco_saida, new.preco_km, new.preco_minimo, new.moeda, new.servico, new.validade_inicio, new.validade_fim)
         is distinct from (old.veiculo, old.capacidade_kg, old.capacidade_m3, old.preco_saida, old.preco_km, old.preco_minimo, old.moeda, old.servico, old.validade_inicio, old.validade_fim) then
        new.estado := 'pendente'; new.versao := old.versao + 1;
      elsif new.estado not in ('pendente', 'inativo') and new.estado is distinct from old.estado then
        raise exception 'Só a administração Elolog pode aprovar ou suspender tarifas de veículos.' using errcode = '42501';
      end if;
    end if;
  elsif tg_op = 'UPDATE' and (new.preco_saida, new.preco_km, new.preco_minimo, new.capacidade_kg, new.capacidade_m3)
        is distinct from (old.preco_saida, old.preco_km, old.preco_minimo, old.capacidade_kg, old.capacidade_m3) then
    new.versao := old.versao + 1;
  end if;
  return new;
end $$;
create or replace trigger tarifas_veiculos_guarda before insert or update on public.tarifas_veiculos for each row execute function private.veiculo_guarda();
create or replace trigger tarifas_veiculos_registo after insert or update on public.tarifas_veiculos for each row execute function private.tarifa_registo();

create or replace function public.veiculo_decidir(p_veiculo uuid, p_decisao text, p_motivo text default null)
returns public.tarifas_veiculos language plpgsql security definer set search_path = public as $$
declare v tarifas_veiculos; v_para text := case p_decisao when 'aprovar' then 'aprovado' when 'rejeitar' then 'rejeitado' when 'suspender' then 'suspenso' when 'reativar' then 'aprovado' end;
begin
  if not private.e_admin_plataforma() then raise exception 'Só a administração Elolog decide sobre tarifas de veículos.' using errcode = '42501'; end if;
  if v_para is null then raise exception 'Decisão desconhecida.'; end if;
  if p_decisao in ('rejeitar', 'suspender') and coalesce(trim(p_motivo), '') = '' then raise exception 'Indique o motivo: o prestador vai lê-lo.'; end if;
  perform set_config('elolog.motivo', coalesce(nullif(trim(p_motivo), ''), initcap(p_decisao)), true);
  update tarifas_veiculos set estado = v_para, motivo_decisao = nullif(trim(p_motivo), '') where id = p_veiculo returning * into v;
  if not found then raise exception 'Tarifa de veículo inexistente.'; end if;
  if v.empresa_id is not null then
    insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v.empresa_id, 'veiculo_decisao', 'Tarifa de veículo ' || v_para, '«' || v.nome || '»' || coalesce('. ' || nullif(trim(p_motivo), ''), '.'), 'tarifas_veiculos', v.id);
  end if;
  perform set_config('elolog.motivo', '', true);
  return v;
end $$;
revoke all on function public.veiculo_decidir(uuid, text, text) from public, anon;
grant execute on function public.veiculo_decidir(uuid, text, text) to authenticated;

-- avisar a Elolog quando um prestador submete uma tarifa de veículo
create or replace function private.veiculo_aviso() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.empresa_id is not null and new.estado = 'pendente' and (tg_op = 'INSERT' or old.estado is distinct from 'pendente') then
    insert into notificacoes (para_plataforma, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (true, 'veiculo_submetido', 'Uma tarifa de veículo espera aprovação',
            coalesce((select nome from empresas where id = new.empresa_id), 'Um prestador') || ' submeteu «' || new.nome || '».', 'tarifas_veiculos', new.id);
  end if;
  return new;
end $$;
create or replace trigger tarifas_veiculos_aviso after insert or update of estado on public.tarifas_veiculos for each row execute function private.veiculo_aviso();

-- os prestadores aprovados veem os tarifários gerais de REFERÊNCIA em vigor (para alinharem os preços); os comerciais só se estiverem associados
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas_gerais' and policyname = 'tg_prestador_ref') then
  create policy tg_prestador_ref on public.tarifas_gerais for select to authenticated
  using (uso = 'referencia' and estado = 'ativa' and private.minha_empresa() is not null);
end if; end $$;

-- comissões que se aplicam à empresa do prestador (só leitura, só as ativas, sem as regras de outros prestadores)
create or replace function public.minhas_comissoes()
returns table (nome text, tipo_valor text, valor numeric, metodo text, rota_origem text, rota_destino text, inicio date, fim date, promocional boolean, apresentacao text, geral boolean)
language sql stable security definer set search_path = public as $$
  select c.nome, c.tipo_valor::text, c.valor, c.metodo::text, c.rota_origem, c.rota_destino, c.inicio, c.fim, c.promocional, c.apresentacao, c.empresa_id is null
    from regras_comissao c
   where private.minha_empresa() is not null and private.papel_em(array['admin_empresa','financeiro'])
     and c.ativa and (c.fim is null or c.fim >= current_date) and (c.empresa_id is null or c.empresa_id = private.minha_empresa())
   order by (c.empresa_id is not null) desc, c.prioridade desc $$;
revoke all on function public.minhas_comissoes() from public, anon;
grant execute on function public.minhas_comissoes() to authenticated;

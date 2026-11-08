-- v114 — Centro de Gestão de Tarifários (1/3): estados, versões e limites das tarifas; tarifários gerais da Elolog;
-- suplementos; comissões por prestador, modalidade, rota e período; histórico de todas as alterações.
-- Só acrescenta: as tarifas, comissões, planos e fluxos existentes continuam a funcionar.

-- ---------- 1. Tarifas dos prestadores: estado (aprovação pela administração), limites e decisão ----------
alter table public.tarifas add column if not exists estado text not null default 'rascunho',
  add column if not exists limite_min numeric, add column if not exists limite_max numeric, add column if not exists preco_maximo numeric,
  add column if not exists submetida_em timestamptz, add column if not exists decidida_em timestamptz, add column if not exists decidida_por uuid,
  add column if not exists motivo_decisao text, add column if not exists updated_at timestamptz not null default now();
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'tarifas_estado_valido') then
    alter table public.tarifas add constraint tarifas_estado_valido check (estado in ('rascunho','pendente','alteracoes_pedidas','aprovada','rejeitada','suspensa','inativa','substituida'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'tarifas_limites_validos') then
    alter table public.tarifas add constraint tarifas_limites_validos check ((limite_min is null or limite_min >= 0) and (limite_max is null or limite_min is null or limite_max >= limite_min)
      and (preco_maximo is null or preco_maximo >= coalesce(preco_minimo, 0)) and valor <= 10000000);
  end if;
end $$;
-- as tarifas que já existiam continuam como estavam: ativas = aprovadas
update public.tarifas set estado = case when ativa then 'aprovada' else 'inativa' end where estado = 'rascunho' and decidida_em is null and submetida_em is null;
create index if not exists tarifas_estado on public.tarifas (estado, empresa_id);

-- ---------- 2. Tarifários gerais (Elolog): referência e comerciais, associáveis a prestadores ----------
create sequence if not exists public.tarifas_gerais_seq;
create table if not exists public.tarifas_gerais (
  id uuid primary key default gen_random_uuid(), codigo text unique, nome text not null,
  uso text not null default 'referencia' check (uso in ('referencia', 'comercial')),
  servico text, tipo_carga text, metodo metodo_cobranca not null, valor numeric not null check (valor >= 0 and valor <= 10000000), moeda char(3) not null default 'EUR',
  preco_minimo numeric not null default 0, preco_maximo numeric, limite_min numeric, limite_max numeric, regras jsonb not null default '{}',
  origem text, destino text, condicoes text, prestadores uuid[] not null default '{}',
  validade_inicio date, validade_fim date, estado text not null default 'rascunho' check (estado in ('rascunho','ativa','suspensa','inativa','substituida')),
  versao int not null default 1, tarifa_pai_id uuid references public.tarifas_gerais(id), motivo_alteracao text, criado_por uuid references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (validade_fim is null or validade_inicio is null or validade_fim >= validade_inicio),
  check ((limite_max is null or limite_min is null or limite_max >= limite_min) and (preco_maximo is null or preco_maximo >= preco_minimo)));
alter table public.tarifas_gerais enable row level security;
revoke all on public.tarifas_gerais from anon;
grant select, insert, update on public.tarifas_gerais to authenticated;
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas_gerais' and policyname = 'tg_admin') then
  create policy tg_admin on public.tarifas_gerais for all to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
end if; end $$;
-- um prestador só vê as tarifas comerciais ativas que a Elolog lhe associou (nunca as de referência nem as de outros)
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas_gerais' and policyname = 'tg_prestador_ve') then
  create policy tg_prestador_ve on public.tarifas_gerais for select to authenticated
  using (uso = 'comercial' and estado = 'ativa' and private.minha_empresa() = any (prestadores));
end if; end $$;

-- ---------- 3. Suplementos (recolha por km, combustível, seguro, urgência…) ----------
create table if not exists public.tarifa_suplementos (
  id uuid primary key default gen_random_uuid(), empresa_id uuid references public.empresas(id) on delete cascade,   -- null = suplemento geral da Elolog
  nome text not null, chave text not null default 'outro' check (chave in ('recolha_km','combustivel','seguro','manuseamento','urgente','outro')),
  tipo text not null check (tipo in ('fixo','percentual','por_km')), valor numeric not null check (valor >= 0 and valor <= 1000000),
  servico text, tipo_carga text, automatico boolean not null default true,
  estado text not null default 'pendente' check (estado in ('pendente','aprovado','rejeitado','suspenso','inativo')),
  validade_inicio date, validade_fim date, motivo_decisao text, motivo_alteracao text, criado_por uuid references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
alter table public.tarifa_suplementos enable row level security;
revoke all on public.tarifa_suplementos from anon;
grant select, insert, update on public.tarifa_suplementos to authenticated;
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifa_suplementos' and policyname = 'sup_admin') then
  create policy sup_admin on public.tarifa_suplementos for all to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
end if; end $$;
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifa_suplementos' and policyname = 'sup_empresa') then
  create policy sup_empresa on public.tarifa_suplementos for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']))
  with check (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']));
end if; end $$;

-- ---------- 4. Comissões: por prestador (já existia), modalidade, rota, período, promoção e forma de apresentação ----------
alter table public.regras_comissao add column if not exists nome text, add column if not exists metodo metodo_cobranca,
  add column if not exists rota_origem text, add column if not exists rota_destino text, add column if not exists promocional boolean not null default false,
  add column if not exists inicio date, add column if not exists fim date, add column if not exists prioridade int not null default 0,
  add column if not exists apresentacao text not null default 'incluida', add column if not exists motivo_alteracao text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'regras_comissao_apresentacao') then
    alter table public.regras_comissao add constraint regras_comissao_apresentacao check (apresentacao in ('incluida','separada') and (fim is null or inicio is null or fim >= inicio));
  end if;
end $$;

-- ---------- 5. Histórico de alterações (tarifas, tarifários gerais, suplementos e comissões) ----------
create table if not exists public.tarifas_historico (
  id bigint generated always as identity primary key, entidade text not null, registo_id uuid not null, empresa_id uuid,
  versao int, estado_anterior text, estado_novo text, antes jsonb, depois jsonb, motivo text,
  user_id uuid, user_nome text, created_at timestamptz not null default now());
create index if not exists tarifas_historico_registo on public.tarifas_historico (entidade, registo_id, created_at desc);
alter table public.tarifas_historico enable row level security;
revoke all on public.tarifas_historico from anon, authenticated;
grant select on public.tarifas_historico to authenticated;
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas_historico' and policyname = 'th_admin') then
  create policy th_admin on public.tarifas_historico for select to authenticated using (private.e_admin_plataforma());
end if; end $$;
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas_historico' and policyname = 'th_empresa') then
  create policy th_empresa on public.tarifas_historico for select to authenticated
  using (empresa_id is not null and empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']));
end if; end $$;

create or replace function private.tarifa_registo() returns trigger language plpgsql security definer set search_path = public as $$
declare a jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) - 'updated_at' else null end; d jsonb := to_jsonb(new) - 'updated_at';
        so text; sn text; nome text;
begin
  if a is not null and a = d then return new; end if;
  so := coalesce(a ->> 'estado', case when a ? 'ativa' then case when (a ->> 'ativa')::boolean then 'ativa' else 'inativa' end end);
  sn := coalesce(d ->> 'estado', case when d ? 'ativa' then case when (d ->> 'ativa')::boolean then 'ativa' else 'inativa' end end);
  select coalesce((select f.nome from funcionarios f where f.id = auth.uid()), (select ap.nome from administradores_plataforma ap where ap.user_id = auth.uid()),
                  (select u.email from auth.users u where u.id = auth.uid()), 'Sistema') into nome;
  insert into tarifas_historico (entidade, registo_id, empresa_id, versao, estado_anterior, estado_novo, antes, depois, motivo, user_id, user_nome)
  values (tg_table_name, new.id, nullif(d ->> 'empresa_id', '')::uuid, nullif(d ->> 'versao', '')::int, so, sn, a, d,
          coalesce(case when a is null or a ->> 'motivo_alteracao' is distinct from d ->> 'motivo_alteracao' then d ->> 'motivo_alteracao' end, nullif(current_setting('elolog.motivo', true), '')), auth.uid(), nome);
  return new;
end $$;
create or replace trigger tarifas_registo after insert or update on public.tarifas for each row execute function private.tarifa_registo();
create or replace trigger tarifas_gerais_registo after insert or update on public.tarifas_gerais for each row execute function private.tarifa_registo();
create or replace trigger tarifa_suplementos_registo after insert or update on public.tarifa_suplementos for each row execute function private.tarifa_registo();
create or replace trigger regras_comissao_registo after insert or update on public.regras_comissao for each row execute function private.tarifa_registo();

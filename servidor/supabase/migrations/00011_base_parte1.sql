-- =====================================================================
-- Elolog · 0001 · Esquema base (Supabase / PostgreSQL 15+)
-- Multiempresa: cada prestador (empresa) só vê os seus dados (ver 0003_rls.sql).
-- Gerado a partir de DOCUMENTACAO/ARQUITETURA_E_FLUXOS.md e PLANO_DE_PRODUCAO.md.
-- =====================================================================
create schema if not exists private;          -- funções internas (não expostas pela API)
grant usage on schema private to authenticated, service_role;
-- ---------- Tipos enumerados -----------------------------------------
create type estado_empresa      as enum ('pendente','aprovada','suspensa','rejeitada');
create type papel_funcionario   as enum ('admin_empresa','operador','operador_terreno','armazem','financeiro');
create type estado_subscricao   as enum ('pendente','ativa','suspensa','cancelada');
create type estado_simulacao    as enum ('rascunho','enviada','respondida','convertida','cancelada');
create type estado_proposta     as enum ('enviada','aceite','recusada','cancelada');
-- Fluxo principal: aprovação → agendamento → recolha → armazenamento → expedição → trânsito → destino → entregue
create type estado_encomenda    as enum ('aprovacao','agendamento','recolha','armazenamento','expedicao','em_transito','destino','entregue','cancelada');
create type metodo_cobranca     as enum ('unidade','volume','peso','wm','contentor','fixo');
create type aplicacao_tarifa    as enum ('carga','recolha','adicional');
create type tipo_pagamento      as enum ('total','prestacao','reembolso');
create type estado_pagamento    as enum ('pendente','parcial','pago','reembolsado','anulado');
create type estado_manifesto    as enum ('rascunho','confirmado','em_transito','concluido','cancelado');
create type tipo_trabalho       as enum ('recolha','entrega');
create type estado_trabalho     as enum ('planeada','em_curso','concluida','cliente_ausente','cancelada');
create type origem_ticket       as enum ('cliente','prestador','terreno','reclamacao');
create type estado_ticket       as enum ('aberto','em_tratamento','escalado','resolvido');
-- ---------- Códigos legíveis (TR-2026-000001, SIM-..., PROP-...) ------
create table contadores ( prefixo text not null, ano     int  not null, valor   int  not null default 0,
  primary key (prefixo, ano) ); create function private.proximo_codigo(p_prefixo text) returns text
language plpgsql security definer set search_path = public as $$
declare v int; a int := extract(year from now())::int; begin
  insert into contadores(prefixo, ano, valor) values (p_prefixo, a, 1)
  on conflict (prefixo, ano) do update set valor = contadores.valor + 1 returning valor into v;
  return p_prefixo || '-' || a || '-' || lpad(v::text, 6, '0'); end $$;
grant execute on function private.proximo_codigo(text) to authenticated, service_role;
create function private.set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
-- ---------- Plataforma e empresas -------------------------------------
create table administradores_plataforma (
  user_id    uuid primary key references auth.users(id) on delete cascade, nome       text not null,
  created_at timestamptz not null default now() ); create table empresas (
  id                 uuid primary key default gen_random_uuid(), nome               text not null,
  nome_comercial     text, nif                text not null, email              text not null,
  telefone           text, morada             text, codigo_postal      text, cidade             text,
  pais               text not null default 'Portugal',
  estado             estado_empresa not null default 'pendente',
  segredo_acesso_hash text,                       -- palavra-passe da empresa (1.º passo do login), bcrypt
  aprovada_por       uuid references auth.users(id), aprovada_em        timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(), constraint empresas_nif_unico unique (nif),
  constraint empresas_nome_nif_nao_vazio check (length(trim(nome)) > 0 and length(trim(nif)) > 0) );
create table planos ( id               uuid primary key default gen_random_uuid(),
  nome             text not null unique,
  preco_mensal     numeric(12,2) not null default 0 check (preco_mensal >= 0),
  personalizado    boolean not null default false, trial_dias       int not null default 0,
  max_funcionarios int,                           -- null = ilimitado / a definir
  max_operacoes    int, armazenamento_gb int, suporte          text,
  ativo            boolean not null default true, created_at       timestamptz not null default now() );
create table subscricoes ( id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references empresas(id) on delete cascade,
  plano_id         uuid not null references planos(id),
  estado           estado_subscricao not null default 'pendente',
  periodicidade    text not null default 'mensal' check (periodicidade in ('mensal','anual')),
  valor            numeric(12,2) not null check (valor >= 0), metodo_pagamento text, referencia       text,
  pago_em          timestamptz, confirmado_por   uuid references auth.users(id),
  created_at       timestamptz not null default now(), updated_at       timestamptz not null default now() );
create unique index subscricoes_uma_ativa on subscricoes(empresa_id) where estado = 'ativa';
create table funcionarios ( id               uuid primary key references auth.users(id) on delete cascade,
  empresa_id       uuid not null references empresas(id) on delete cascade, nome             text not null,
  email            text not null, papel            papel_funcionario not null,
  ativo            boolean not null default true, numero_interno   text, veiculo_habitual text,
  permissoes       text[] not null default '{}',  -- ex.: receive_cash, register_signature, capture_load
  created_at       timestamptz not null default now(), updated_at       timestamptz not null default now(),
  unique (empresa_id, email) ); create index funcionarios_empresa on funcionarios(empresa_id);
create table clientes ( id         uuid primary key references auth.users(id) on delete cascade,
  nome       text not null, nif        text, telefone   text, email      text not null, morada     text,
  estado     text not null default 'ativo' check (estado in ('ativo','bloqueado','eliminado')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now() );
create index clientes_nif on clientes(nif); create table cliente_notas (
  id         uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  cliente_id uuid not null references clientes(id) on delete cascade, nota       text not null,
  autor_id   uuid references auth.users(id), created_at timestamptz not null default now(),
  updated_at timestamptz not null default now() ); create table armazens (
  id         uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade, nome       text not null,
  morada     text, latitude   numeric(9,6), longitude  numeric(9,6), ativo      boolean not null default true,
  created_at timestamptz not null default now() ); create table veiculos (
  id         uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade, matricula  text not null,
  descricao  text, ativo      boolean not null default true, created_at timestamptz not null default now(),
  unique (empresa_id, matricula) ); -- ---------- Simulações, tarifas e propostas ---------------------------
create table simulacoes ( id                    uuid primary key default gen_random_uuid(),
  codigo                text not null unique default private.proximo_codigo('SIM'),
  cliente_id            uuid not null references clientes(id),
  empresa_destinatario_id uuid references empresas(id), origem                text not null,
  destino               text not null, tipo_carga            text, descricao             text,
  quantidade            int, peso_kg               numeric(12,3), volume_m3             numeric(12,4),
  volumes               jsonb not null default '[]' check (jsonb_typeof(volumes) = 'array'),
  recolha_na_morada     boolean not null default false, recolha_distancia_km  numeric(10,2),
  estado                estado_simulacao not null default 'rascunho', enviada_em            timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  -- Rascunho é privado; só sai do rascunho com prestador destinatário e registo de envio.
  constraint simulacao_envio_explicito check (
    estado in ('rascunho','cancelada') or (empresa_destinatario_id is not null and enviada_em is not null) )
); create index simulacoes_cliente on simulacoes(cliente_id);
create index simulacoes_empresa on simulacoes(empresa_destinatario_id) where estado <> 'rascunho';
-- Tarifas versionadas: uma tarifa já utilizada nunca é alterada; cria-se nova versão.
create table tarifas ( id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references empresas(id) on delete cascade,
  tarifa_pai_id     uuid references tarifas(id), versao            int not null default 1,
  nome              text not null, aplicacao         aplicacao_tarifa not null default 'carga',
  tipo_carga        text, metodo            metodo_cobranca not null,
  valor             numeric(14,4) not null check (valor >= 0),
  moeda             char(3) not null default 'EUR', quantidade_minima numeric(14,3) not null default 0,
  preco_minimo      numeric(14,2) not null default 0, transporte        text, origem            text,
  destino           text, validade_inicio   date, validade_fim      date,
  ativa             boolean not null default true,
  regras            jsonb not null default '{}',   -- fator volumétrico, unidade, regras avançadas
  notas             text, criado_por        uuid references auth.users(id),
  created_at        timestamptz not null default now(),
  check (validade_fim is null or validade_inicio is null or validade_fim >= validade_inicio) );
create index tarifas_pesquisa on tarifas(empresa_id, ativa, aplicacao, origem, destino);
-- Serviços adicionais, armazenagem, impostos/taxas e descontos (módulo Financeiro)
create table regras_financeiras ( id         uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  tipo       text not null check (tipo in ('servico_adicional','armazenagem','imposto','desconto')),
  nome       text not null, valor      numeric(14,4) not null default 0,
  regras     jsonb not null default '{}', ativa      boolean not null default true,
  criado_por uuid references auth.users(id), created_at timestamptz not null default now(),
  updated_at timestamptz not null default now() );

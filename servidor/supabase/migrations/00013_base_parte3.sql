create table notificacoes (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid references auth.users(id) on delete cascade,
  empresa_id        uuid references empresas(id) on delete cascade,
  para_plataforma   boolean not null default false,
  tipo              text not null,
  titulo            text not null,
  corpo             text,
  referencia_tabela text,
  referencia_id     uuid,
  lida_em           timestamptz,                    -- só muda quando o utilizador a marca como lida
  created_at        timestamptz not null default now(),
  check (user_id is not null or empresa_id is not null or para_plataforma)
);
create index notificacoes_user on notificacoes(user_id, created_at desc);
create index notificacoes_empresa on notificacoes(empresa_id, created_at desc);

create table auditoria (
  id          bigint generated always as identity primary key,
  empresa_id  uuid,
  user_id     uuid,
  papel       text,
  acao        text not null,
  entidade    text not null,
  entidade_id text,
  antes       jsonb,
  depois      jsonb,
  motivo      text,
  created_at  timestamptz not null default now()
);
create index auditoria_empresa on auditoria(empresa_id, created_at desc);
create index auditoria_entidade on auditoria(entidade, entidade_id);

-- ---------- Administração da plataforma -------------------------------
create table regras_comissao (
  id         uuid primary key default gen_random_uuid(),
  empresa_id uuid references empresas(id) on delete cascade,   -- null = regra global
  escopo     text not null,
  evento     text not null,
  tipo_valor text not null default 'percentagem' check (tipo_valor in ('percentagem','fixo')),
  valor      numeric(12,4) not null check (valor >= 0),
  regras     jsonb not null default '{}',
  ativa      boolean not null default true,
  criado_por uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table regras_conformidade (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid references empresas(id) on delete cascade,   -- null = regra global
  escopo          text not null,
  nome            text not null,                                    -- ex.: documento exigido ao prestador
  obrigatorio     boolean not null default true,
  exige_validade  boolean not null default false,
  validade_dias   int,
  ativa           boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table faturas_plataforma (                              -- faturas, recibos e notas de crédito Elolog → prestador
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references empresas(id),
  tipo             text not null check (tipo in ('fatura','recibo','nota_credito')),
  numero_fiscal    text,                                        -- do software de faturação certificado
  fatura_origem_id uuid references faturas_plataforma(id),
  valor            numeric(14,2) not null,
  moeda            char(3) not null default 'EUR',
  estado           text not null default 'emitida' check (estado in ('emitida','paga','anulada')),
  documento_id     uuid references documentos(id),
  emitida_em       timestamptz not null default now(),
  criado_por       uuid references auth.users(id),
  updated_at       timestamptz not null default now()
);
create unique index faturas_numero_fiscal_unico on faturas_plataforma(numero_fiscal) where numero_fiscal is not null;

create table pedidos_cliente (                                  -- alteração de dados / eliminação de conta
  id         uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id) on delete cascade,
  tipo       text not null check (tipo in ('alteracao_dados','eliminacao_conta')),
  estado     text not null default 'pendente' check (estado in ('pendente','aprovado','recusado')),
  dados      jsonb not null default '{}',
  tratado_por uuid references auth.users(id),
  tratado_em timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Limitação de tentativas no passo "empresa" do login (nome + NIF + palavra-passe)
create table tentativas_gate (
  chave         text primary key,
  falhas        int not null default 0,
  bloqueado_ate timestamptz
);

-- ---------- updated_at automático -------------------------------------
do $$
declare r record;
begin
  for r in select table_name from information_schema.columns
           where table_schema = 'public' and column_name = 'updated_at' loop
    execute format('create trigger trg_updated_at before update on public.%I for each row execute function private.set_updated_at()', r.table_name);
  end loop;
end $$;

-- ---------- RLS ligada em TODAS as tabelas (políticas em 0003) --------
do $$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', r.tablename);
  end loop;
end $$;

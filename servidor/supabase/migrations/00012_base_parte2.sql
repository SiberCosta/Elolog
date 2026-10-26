create table propostas ( id           uuid primary key default gen_random_uuid(),
  codigo       text not null unique default private.proximo_codigo('PROP'),
  simulacao_id uuid not null references simulacoes(id) on delete cascade,
  empresa_id   uuid not null references empresas(id), tarifa_id    uuid references tarifas(id),
  preco        numeric(14,2) not null check (preco >= 0), moeda        char(3) not null default 'EUR',
  prazo_dias   int check (prazo_dias > 0), mensagem     text, validade     date,
  estado       estado_proposta not null default 'enviada', versao       int not null default 1,
  criado_por   uuid references auth.users(id), respondida_em timestamptz,
  created_at   timestamptz not null default now(), updated_at   timestamptz not null default now() );
create unique index propostas_ativa_unica on propostas(simulacao_id, empresa_id) where estado in ('enviada','aceite');
-- ---------- Encomendas ------------------------------------------------
create table encomendas ( id                      uuid primary key default gen_random_uuid(),
  codigo                  text not null unique default private.proximo_codigo('TR'),
  empresa_id              uuid not null references empresas(id),
  cliente_id              uuid references clientes(id),
  cliente_nome            text,                      -- cliente sem conta (criado no terreno)
  cliente_nif             text, cliente_telefone        text,
  simulacao_id            uuid references simulacoes(id),
  proposta_id             uuid references propostas(id), origem                  text not null,
  destino                 text not null, tipo_carga              text, descricao               text,
  quantidade              int, peso_kg                 numeric(12,3), volume_m3               numeric(12,4),
  volumes                 jsonb not null default '[]' check (jsonb_typeof(volumes) = 'array'),
  estado                  estado_encomenda not null default 'aprovacao',
  criada_no_terreno       boolean not null default false,
  preco_total             numeric(14,2) not null default 0 check (preco_total >= 0),
  moeda                   char(3) not null default 'EUR', data_prevista           date,
  assinatura_documento_id uuid,                      -- FK adicionada abaixo (documentos)
  pin_validacao_hash      text,                      -- PIN do cliente (hash), nunca em claro
  criado_por              uuid references auth.users(id),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now() );
create index encomendas_empresa_estado on encomendas(empresa_id, estado);
create index encomendas_cliente on encomendas(cliente_id); create table documentos (
  id            uuid primary key default gen_random_uuid(), empresa_id    uuid references empresas(id),
  encomenda_id  uuid references encomendas(id), cliente_id    uuid references clientes(id),
  categoria     text not null,                       -- ex.: fatura, comprovativo, manifesto, dossier_prestador
  nome          text not null,
  visibilidade  text not null default 'interna' check (visibilidade in ('interna','cliente')),
  storage_path  text not null unique,                -- caminho no bucket privado "documentos"
  mime          text, tamanho_bytes bigint, sha256        text, versao        int not null default 1,
  substitui_id  uuid references documentos(id),      -- versionamento: nunca se substitui em silêncio
  valido_ate    date, enviado_por   uuid references auth.users(id),
  created_at    timestamptz not null default now(), check (empresa_id is not null or cliente_id is not null)
); create index documentos_encomenda on documentos(encomenda_id); alter table encomendas
  add constraint encomendas_assinatura_fk foreign key (assinatura_documento_id) references documentos(id);
create table recibos_armazem ( encomenda_id   uuid primary key references encomendas(id) on delete cascade,
  armazem_id     uuid references armazens(id), confirmado     boolean not null default false,
  carga_conferida boolean not null default false, localizacao    text, ocorrencias    text,
  confirmado_por uuid references auth.users(id), confirmado_em  timestamptz,
  updated_at     timestamptz not null default now() ); create table entregas (
  encomenda_id            uuid primary key references encomendas(id) on delete cascade,
  identificacao           text,                      -- quem levantou/recebeu
  assinatura_documento_id uuid references documentos(id),
  pin_validado            boolean not null default false,
  entregue_por            uuid references auth.users(id), entregue_em             timestamptz,
  updated_at              timestamptz not null default now() ); create table encomenda_historico (
  id           bigint generated always as identity primary key,
  encomenda_id uuid not null references encomendas(id) on delete cascade,
  empresa_id   uuid not null references empresas(id), de           estado_encomenda,
  para         estado_encomenda not null, nota         text, user_id      uuid references auth.users(id),
  created_at   timestamptz not null default now() );
create index encomenda_historico_enc on encomenda_historico(encomenda_id, created_at);
-- Transições permitidas e quem as pode executar (regras do fluxo principal)
create table encomenda_transicoes ( de     estado_encomenda not null, para   estado_encomenda not null,
  papeis papel_funcionario[] not null, primary key (de, para) );
-- ---------- Pagamentos ------------------------------------------------
create table pagamentos ( id                uuid primary key default gen_random_uuid(),
  codigo            text not null unique default private.proximo_codigo('PAY'),
  empresa_id        uuid not null references empresas(id),
  encomenda_id      uuid not null references encomendas(id), cliente_id        uuid references clientes(id),
  tipo              tipo_pagamento not null default 'total',
  valor             numeric(14,2) not null check (valor > 0),
  moeda             char(3) not null default 'EUR',
  estado            estado_pagamento not null default 'pendente', metodo            text,
  referencia        text, numerario_terreno boolean not null default false,
  registado_por     uuid references auth.users(id), pago_em           timestamptz,
  reconciliado      boolean not null default false, reconciliado_por  uuid references auth.users(id),
  reconciliado_em   timestamptz, motivo_anulacao   text, created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  -- Sem DELETE: um recebimento errado é anulado com motivo, ficando no histórico.
  constraint pagamento_anulacao_com_motivo check (estado <> 'anulado' or coalesce(motivo_anulacao,'') <> '')
); create index pagamentos_encomenda on pagamentos(encomenda_id);
create index pagamentos_empresa on pagamentos(empresa_id, estado);
-- ---------- Manifestos e declarações de carga -------------------------
create table manifestos ( id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references empresas(id) on delete cascade, numero           text not null,
  versao           int not null default 1, estado           estado_manifesto not null default 'rascunho',
  origem           text, destino          text, numero_viagem    text, partida          date,
  chegada          date, transportador    text, total_unidades   int not null default 0,
  total_peso_kg    numeric(12,3) not null default 0, total_volume_m3  numeric(12,4) not null default 0,
  criado_por       uuid references auth.users(id), confirmado_por   uuid references auth.users(id),
  confirmado_em    timestamptz, created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(), unique (empresa_id, numero, versao) );
create table manifesto_encomendas ( manifesto_id uuid not null references manifestos(id) on delete cascade,
  encomenda_id uuid not null references encomendas(id), primary key (manifesto_id, encomenda_id) );
create table declaracoes_carga ( id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references empresas(id) on delete cascade,
  encomenda_id  uuid not null references encomendas(id) on delete cascade,
  versao        int not null default 1,
  estado        text not null default 'rascunho' check (estado in ('rascunho','confirmada','assinada','enviada','arquivada')),
  itens         jsonb not null default '[]' check (jsonb_typeof(itens) = 'array'),
  assinatura_declarante_documento_id uuid references documentos(id),
  criado_por    uuid references auth.users(id), created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(), unique (encomenda_id, versao) );
-- ---------- Terreno ---------------------------------------------------
create table trabalhos_terreno ( id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references empresas(id) on delete cascade,
  encomenda_id uuid not null references encomendas(id) on delete cascade, tipo         tipo_trabalho not null,
  operador_id  uuid references funcionarios(id), veiculo_id   uuid references veiculos(id), data         date,
  estado       estado_trabalho not null default 'planeada', notas        text,
  created_at   timestamptz not null default now(), updated_at   timestamptz not null default now() );
create index trabalhos_operador on trabalhos_terreno(operador_id, data);
-- ---------- Suporte, notificações, auditoria --------------------------
create table tickets ( id           uuid primary key default gen_random_uuid(),
  codigo       text not null unique default private.proximo_codigo('TKT'),
  empresa_id   uuid references empresas(id), cliente_id   uuid references clientes(id),
  encomenda_id uuid references encomendas(id), origem       origem_ticket not null,
  assunto      text not null, estado       estado_ticket not null default 'aberto',
  escalado     boolean not null default false, criado_por   uuid references auth.users(id),
  resolvido_em timestamptz, created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now() ); create table ticket_mensagens (
  id         bigint generated always as identity primary key,
  ticket_id  uuid not null references tickets(id) on delete cascade,
  autor_id   uuid not null references auth.users(id), corpo      text not null,
  created_at timestamptz not null default now() );

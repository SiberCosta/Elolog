-- v123: Centro Documental — documentos emitidos por encomenda (guia, guia de receção, comprovativo de pagamento).
-- Regras: numeração própria de cada empresa; um documento nunca é alterado nem apagado (uma correção cria nova versão com o mesmo número);
-- cada documento tem um código aleatório para validação pelo QR; o conteúdo é uma fotografia dos dados no momento da emissão (construída no servidor).
-- Só acrescenta tabelas e funções: as tabelas existentes não mudam.

create table if not exists public.documentos_emitidos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  tipo text not null check (tipo in ('guia', 'rececao', 'pagamento')),
  numero text not null,
  versao int not null default 1 check (versao >= 1),
  estado text not null default 'valido' check (estado in ('valido', 'substituido', 'anulado')),
  encomenda_id uuid not null references public.encomendas(id),
  pagamento_id uuid references public.pagamentos(id),
  cliente_id uuid,
  referencia text not null,
  dados jsonb not null,
  sha256 text not null,
  codigo_validacao text not null unique default encode(extensions.gen_random_bytes(12), 'hex'),
  motivo text,
  substitui_id uuid references public.documentos_emitidos(id),
  emitido_por uuid,
  emitido_em timestamptz not null default now(),
  unique (empresa_id, numero, versao));
create index if not exists documentos_emitidos_encomenda on public.documentos_emitidos (encomenda_id);
create index if not exists documentos_emitidos_empresa on public.documentos_emitidos (empresa_id, tipo, emitido_em desc);
create unique index if not exists documentos_emitidos_um_valido on public.documentos_emitidos (empresa_id, tipo, coalesce(pagamento_id, encomenda_id)) where estado = 'valido';

create table if not exists public.documentos_numeracao (
  empresa_id uuid not null references public.empresas(id), tipo text not null, ano int not null, ultimo int not null default 0,
  primary key (empresa_id, tipo, ano));

create table if not exists public.documentos_eventos (
  id bigint generated always as identity primary key,
  documento_id uuid not null references public.documentos_emitidos(id),
  acao text not null check (acao in ('emitido', 'reemitido', 'consultado', 'impresso', 'descarregado', 'validado')),
  user_id uuid, detalhe text, em timestamptz not null default now());
create index if not exists documentos_eventos_doc on public.documentos_eventos (documento_id, em desc);

-- logótipo do prestador, para os documentos terem as duas marcas (Elolog + prestador)
create table if not exists public.empresas_marca (
  empresa_id uuid primary key references public.empresas(id),
  logotipo text not null check (logotipo ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$' and length(logotipo) <= 400000),
  atualizado_em timestamptz not null default now());

alter table public.documentos_emitidos enable row level security;
alter table public.documentos_numeracao enable row level security;
alter table public.documentos_eventos enable row level security;
alter table public.empresas_marca enable row level security;
revoke all on public.documentos_emitidos, public.documentos_numeracao, public.documentos_eventos, public.empresas_marca from anon, authenticated;
grant select on public.documentos_emitidos, public.documentos_eventos to authenticated;

-- quem vê: a empresa emissora (os comprovativos de pagamento só administração, financeiro e operador), o cliente da encomenda e a administração Elolog
create or replace function private.documento_visivel(d public.documentos_emitidos) returns boolean language sql stable security definer set search_path = public as $$
  select private.e_admin_plataforma()
      or (d.cliente_id is not null and d.cliente_id = auth.uid())
      or (d.empresa_id = private.minha_empresa() and (d.tipo <> 'pagamento' or private.papel_em(array['admin_empresa', 'financeiro', 'operador']))) $$;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'documentos_emitidos' and policyname = 'documentos_emitidos_ver') then
    create policy documentos_emitidos_ver on public.documentos_emitidos for select to authenticated using (private.documento_visivel(documentos_emitidos)); end if;
  if not exists (select 1 from pg_policies where tablename = 'documentos_eventos' and policyname = 'documentos_eventos_ver') then
    create policy documentos_eventos_ver on public.documentos_eventos for select to authenticated
      using (exists (select 1 from public.documentos_emitidos d where d.id = documento_id and private.documento_visivel(d))); end if;
end $$;

-- imutabilidade: só o estado pode passar de válido a substituído/anulado; nunca se apaga
create or replace function private.documento_imutavel() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'Os documentos emitidos não podem ser apagados.'; end if;
  if new.dados is distinct from old.dados or new.numero <> old.numero or new.versao <> old.versao or new.codigo_validacao <> old.codigo_validacao
     or new.sha256 <> old.sha256 or new.tipo <> old.tipo or new.empresa_id <> old.empresa_id or new.emitido_em <> old.emitido_em
     or not (old.estado = 'valido' and new.estado in ('valido', 'substituido', 'anulado')) then
    raise exception 'Um documento emitido não pode ser alterado: emita uma nova versão.';
  end if;
  return new;
end $$;
create or replace trigger documentos_emitidos_imutavel before update or delete on public.documentos_emitidos for each row execute function private.documento_imutavel();
create or replace function private.evento_imutavel() returns trigger language plpgsql as $$ begin raise exception 'O histórico dos documentos não pode ser alterado.'; end $$;
create or replace trigger documentos_eventos_imutavel before update or delete on public.documentos_eventos for each row execute function private.evento_imutavel();

-- fotografia dos dados no momento da emissão (o mesmo formato que a aplicação usa em demonstração)
create or replace function private.documento_dados(p_tipo text, p_encomenda uuid, p_pagamento uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e encomendas; r jsonb; pago numeric; pg pagamentos;
begin
  select * into e from encomendas where id = p_encomenda;
  r := jsonb_build_object(
    'empresa', (select jsonb_build_object('id', m.id, 'nome', coalesce(m.nome_comercial, m.nome), 'nif', m.nif, 'morada', concat_ws(', ', m.morada, nullif(concat_ws(' ', m.codigo_postal, m.cidade), ''), m.pais),
                  'telefone', m.telefone, 'email', m.email) from empresas m where m.id = e.empresa_id),
    'cliente', (select jsonb_build_object('nome', coalesce(c.nome, e.cliente_nome), 'nif', coalesce(c.nif, e.cliente_nif)) from (select 1) x left join clientes c on c.id = e.cliente_id),
    'remetente', coalesce(e.remetente, '{}'::jsonb) - 'nif', 'destinatario', coalesce(e.destinatario, '{}'::jsonb) - 'nif',
    'encomenda', jsonb_build_object('codigo', e.codigo, 'simulacao', (select s.codigo from simulacoes s where s.id = e.simulacao_id), 'origem', e.origem, 'destino', e.destino,
      'modalidade', case when e.navio is not null then 'Marítimo' else 'A confirmar pelo prestador' end, 'tipo_carga', e.tipo_carga, 'descricao', e.descricao,
      'quantidade', e.quantidade, 'peso_kg', e.peso_kg, 'volume_m3', e.volume_m3, 'volumes', coalesce(e.volumes, '[]'::jsonb), 'valor_declarado', e.valor_declarado,
      'data_prevista', e.data_prevista, 'morada_recolha', e.morada_recolha, 'navio', e.navio, 'viagem', e.viagem, 'partida_prevista', e.partida_prevista,
      'chegada_prevista', e.chegada_prevista, 'observacoes', e.observacoes),
    'ocorrencias', (select coalesce(jsonb_agg(jsonb_build_object('codigo', o.codigo, 'tipo', o.tipo, 'descricao', o.descricao, 'em', o.created_at) order by o.created_at), '[]'::jsonb)
                      from ocorrencias o where o.encomenda_id = e.id));
  if p_tipo = 'rececao' then
    r := r || jsonb_build_object('rececao', (select jsonb_build_object('em', ra.confirmado_em, 'por', f.nome, 'armazem', a.nome, 'quantidade_esperada', e.quantidade,
            'quantidade_recebida', ra.quantidade_recebida, 'conferida', ra.carga_conferida, 'localizacao', ra.localizacao, 'ocorrencias', ra.ocorrencias)
          from recibos_armazem ra left join armazens a on a.id = ra.armazem_id left join funcionarios f on f.id = ra.confirmado_por where ra.encomenda_id = e.id));
  elsif p_tipo = 'pagamento' then
    select * into pg from pagamentos where id = p_pagamento;
    select coalesce(sum(case when tipo = 'reembolso' then -valor else valor end), 0) into pago from pagamentos
     where encomenda_id = e.id and estado = 'pago' and coalesce(pago_em, created_at) <= coalesce(pg.pago_em, pg.created_at);
    r := r || jsonb_build_object('pagamento', jsonb_build_object('codigo', pg.codigo, 'valor', pg.valor, 'moeda', pg.moeda, 'metodo', pg.metodo, 'referencia', pg.referencia,
            'em', coalesce(pg.pago_em, pg.created_at), 'total_encomenda', e.preco_total, 'total_pago', pago, 'saldo', greatest(coalesce(e.preco_total, 0) - pago, 0),
            'estado', case when coalesce(e.preco_total, 0) - pago <= 0 then 'integral' else 'parcial' end));
  end if;
  return r;
end $$;

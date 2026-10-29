-- v77 — Ocorrências e suspensão da encomenda; o manifesto deixa de ser obrigatório para passar a «em trânsito»
-- (o despacho pode ser feito por um despachante à parte e carregado na plataforma como documento «despacho»).
-- Fluxo da ocorrência: registo → classificação → responsável → resolução → comunicação ao cliente → encerramento.
-- Uma ocorrência pode suspender a encomenda: o estado logístico mantém-se, mas não avança até ser retomada.

alter table encomendas add column if not exists suspensa boolean not null default false;
alter table encomendas add column if not exists suspensa_motivo text;
alter table encomendas add column if not exists suspensa_em timestamptz;

create table if not exists ocorrencias (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null unique default private.codigo_elo('ELO_OC'),
  encomenda_id   uuid not null references encomendas(id) on delete cascade,
  empresa_id     uuid not null references empresas(id),
  tipo           text not null default 'outro' check (tipo in ('atraso','dano','perda','documentacao','alfandega','pagamento','endereco','outro')),
  gravidade      text not null default 'media' check (gravidade in ('baixa','media','alta','critica')),
  estado         text not null default 'aberta' check (estado in ('aberta','em_resolucao','resolvida','encerrada')),
  descricao      text not null check (length(descricao) between 3 and 2000),
  resolucao      text check (length(resolucao) <= 2000),
  responsavel_id uuid references auth.users(id) on delete set null,
  visivel_cliente boolean not null default false,
  suspendeu      boolean not null default false,
  aberta_por     uuid references auth.users(id) on delete set null,
  aberta_por_cliente boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  encerrada_em   timestamptz
);
create index if not exists ocorrencias_encomenda on ocorrencias (encomenda_id, created_at desc);
create index if not exists ocorrencias_empresa on ocorrencias (empresa_id, estado);
create table if not exists ocorrencia_registos (
  id            bigint generated always as identity primary key,
  ocorrencia_id uuid not null references ocorrencias(id) on delete cascade,
  user_id       uuid references auth.users(id) on delete set null,
  acao          text not null,
  nota          text,
  created_at    timestamptz not null default now()
);
alter table ocorrencias enable row level security; alter table ocorrencia_registos enable row level security;
revoke all on ocorrencias, ocorrencia_registos from anon, authenticated;

-- Quem pode tratar ocorrências na empresa: administrador, operador, armazém e terreno (o financeiro só vê).
create or replace function private.ocorrencia_gestor() returns boolean
language sql stable security definer set search_path = public as $$ select private.papel_em(array['admin_empresa','operador','armazem','operador_terreno']) $$;

/** Encomenda pelo código, para a empresa prestadora (gestão) ou para o cliente dela. */
create or replace function private.ocorrencia_encomenda(p_codigo text, out v_enc encomendas, out v_cliente boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  select * into v_enc from encomendas e where e.codigo = p_codigo
    and (e.cliente_id = auth.uid() or (private.minha_empresa() is not null and e.empresa_id = private.minha_empresa()));
  if v_enc.id is null then raise exception 'Encomenda não encontrada.'; end if;
  v_cliente := v_enc.cliente_id = auth.uid() and private.minha_empresa() is distinct from v_enc.empresa_id;
end $$;

create or replace function private.ocorrencia_avisar_cliente(o ocorrencias, p_titulo text, p_corpo text) returns void
language sql security definer set search_path = public as $$
  insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  select e.cliente_id, 'ocorrencia', p_titulo, left(p_corpo, 400), 'encomendas', e.id from encomendas e where e.id = o.encomenda_id and e.cliente_id is not null
$$;

-- Suspender / retomar (o estado logístico não muda; fica registado no histórico).
create or replace function public.encomenda_suspender(p_codigo text, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare a record;
begin
  select * into a from private.ocorrencia_encomenda(p_codigo);
  if a.v_cliente or not private.ocorrencia_gestor() then raise exception 'Sem permissão para suspender a encomenda.'; end if;
  if length(trim(coalesce(p_motivo, ''))) < 3 then raise exception 'Indique o motivo da suspensão.'; end if;
  if (a.v_enc).estado in ('entregue','cancelada') then raise exception 'Não é possível suspender uma encomenda %.', (a.v_enc).estado; end if;
  update encomendas set suspensa = true, suspensa_motivo = left(trim(p_motivo), 300), suspensa_em = now() where id = (a.v_enc).id;
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id) values ((a.v_enc).id, (a.v_enc).empresa_id, (a.v_enc).estado, (a.v_enc).estado, 'Suspensa: ' || left(trim(p_motivo), 300), auth.uid());
  if (a.v_enc).cliente_id is not null then insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values ((a.v_enc).cliente_id, 'ocorrencia', 'A encomenda ' || p_codigo || ' está suspensa', left(trim(p_motivo), 300), 'encomendas', (a.v_enc).id); end if;
end $$;

create or replace function public.encomenda_retomar(p_codigo text, p_nota text default null) returns void
language plpgsql security definer set search_path = public as $$
declare a record;
begin
  select * into a from private.ocorrencia_encomenda(p_codigo);
  if a.v_cliente or not private.ocorrencia_gestor() then raise exception 'Sem permissão para retomar a encomenda.'; end if;
  if not (a.v_enc).suspensa then raise exception 'A encomenda não está suspensa.'; end if;
  update encomendas set suspensa = false, suspensa_motivo = null, suspensa_em = null where id = (a.v_enc).id;
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id) values ((a.v_enc).id, (a.v_enc).empresa_id, (a.v_enc).estado, (a.v_enc).estado, 'Retomada' || coalesce(': ' || nullif(trim(p_nota), ''), ''), auth.uid());
  if (a.v_enc).cliente_id is not null then insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values ((a.v_enc).cliente_id, 'ocorrencia', 'A encomenda ' || p_codigo || ' foi retomada', coalesce(nullif(trim(p_nota), ''), 'O processo continua.'), 'encomendas', (a.v_enc).id); end if;
end $$;

-- Registar: a empresa (com classificação, gravidade, responsável e opção de suspender) ou o cliente (fica «aberta», visível para ele).
create or replace function public.ocorrencia_criar(p_codigo text, p_descricao text, p_tipo text default 'outro', p_gravidade text default 'media',
  p_suspender boolean default false, p_visivel_cliente boolean default false) returns ocorrencias
language plpgsql security definer set search_path = public as $$
declare a record; o ocorrencias;
begin
  select * into a from private.ocorrencia_encomenda(p_codigo);
  if not a.v_cliente and not private.ocorrencia_gestor() then raise exception 'Sem permissão para registar ocorrências.'; end if;
  if (select count(*) from ocorrencias where aberta_por = auth.uid() and created_at > now() - interval '1 hour') >= 20 then raise exception 'Demasiadas ocorrências seguidas. Aguarde.'; end if;
  insert into ocorrencias (encomenda_id, empresa_id, tipo, gravidade, descricao, visivel_cliente, suspendeu, aberta_por, aberta_por_cliente)
  values ((a.v_enc).id, (a.v_enc).empresa_id, case when a.v_cliente then 'outro' else coalesce(p_tipo, 'outro') end, case when a.v_cliente then 'media' else coalesce(p_gravidade, 'media') end,
    trim(p_descricao), a.v_cliente or coalesce(p_visivel_cliente, false), not a.v_cliente and coalesce(p_suspender, false), auth.uid(), a.v_cliente)
  returning * into o;
  insert into ocorrencia_registos (ocorrencia_id, user_id, acao, nota) values (o.id, auth.uid(), case when a.v_cliente then 'Comunicada pelo cliente' else 'Registada' end, left(trim(p_descricao), 300));
  if a.v_cliente then
    insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (o.empresa_id, 'ocorrencia', 'Ocorrência comunicada pelo cliente — ' || p_codigo, left(trim(p_descricao), 300), 'encomendas', o.encomenda_id);
  else
    if o.visivel_cliente then perform private.ocorrencia_avisar_cliente(o, 'Ocorrência na encomenda ' || p_codigo, trim(p_descricao)); end if;
    if o.suspendeu and not (a.v_enc).suspensa then perform public.encomenda_suspender(p_codigo, 'Ocorrência ' || o.codigo || ': ' || left(trim(p_descricao), 200)); end if;
  end if;
  return o;
end $$;

-- Tratar: classificar, atribuir responsável, mudar estado, registar resolução, comunicar ao cliente.
create or replace function public.ocorrencia_atualizar(p_id uuid, p_estado text default null, p_tipo text default null, p_gravidade text default null,
  p_responsavel uuid default null, p_resolucao text default null, p_comunicar boolean default null, p_nota text default null) returns ocorrencias
language plpgsql security definer set search_path = public as $$
declare o ocorrencias; v_nota text[] := '{}';
begin
  select * into o from ocorrencias where id = p_id for update;
  if o.id is null or o.empresa_id is distinct from private.minha_empresa() or not private.ocorrencia_gestor() then raise exception 'Sem permissão para esta ocorrência.'; end if;
  if o.estado = 'encerrada' then raise exception 'A ocorrência já está encerrada.'; end if;
  if p_responsavel is not null and not exists (select 1 from funcionarios where id = p_responsavel and empresa_id = o.empresa_id and ativo) then raise exception 'O responsável tem de ser um funcionário ativo da empresa.'; end if;
  if p_estado in ('resolvida','encerrada') and length(trim(coalesce(p_resolucao, o.resolucao, ''))) < 3 then raise exception 'Descreva a resolução antes de resolver ou encerrar.'; end if;
  if p_estado is not null and p_estado <> o.estado then v_nota := v_nota || ('Estado: ' || p_estado); end if;
  if p_tipo is not null and p_tipo <> o.tipo then v_nota := v_nota || ('Tipo: ' || p_tipo); end if;
  if p_gravidade is not null and p_gravidade <> o.gravidade then v_nota := v_nota || ('Gravidade: ' || p_gravidade); end if;
  if p_responsavel is not null and p_responsavel is distinct from o.responsavel_id then v_nota := v_nota || ('Responsável: ' || coalesce((select nome from funcionarios where id = p_responsavel), '?')); end if;
  if nullif(trim(p_resolucao), '') is not null then v_nota := v_nota || 'Resolução registada'::text; end if;
  if p_comunicar and not o.visivel_cliente then v_nota := v_nota || 'Comunicada ao cliente'::text; end if;
  update ocorrencias set estado = coalesce(p_estado, estado), tipo = coalesce(p_tipo, tipo), gravidade = coalesce(p_gravidade, gravidade),
    responsavel_id = coalesce(p_responsavel, responsavel_id), resolucao = coalesce(nullif(trim(p_resolucao), ''), resolucao),
    visivel_cliente = visivel_cliente or coalesce(p_comunicar, false), updated_at = now(),
    encerrada_em = case when coalesce(p_estado, estado) = 'encerrada' then now() else encerrada_em end
  where id = p_id returning * into o;
  insert into ocorrencia_registos (ocorrencia_id, user_id, acao, nota) values (o.id, auth.uid(), coalesce(nullif(array_to_string(v_nota, ' · '), ''), 'Nota'), nullif(left(trim(coalesce(p_nota, '')), 500), ''));
  if o.visivel_cliente and (p_comunicar or p_estado in ('resolvida','encerrada')) then
    perform private.ocorrencia_avisar_cliente(o, 'Ocorrência ' || o.codigo || ' — ' || case o.estado when 'resolvida' then 'resolvida' when 'encerrada' then 'encerrada' else 'atualização' end,
      coalesce(o.resolucao, o.descricao));
  end if;
  return o;
end $$;

-- Ocorrências de uma encomenda (o cliente só vê as que lhe foram comunicadas, sem notas internas).
create or replace function public.ocorrencias_da_encomenda(p_codigo text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a record;
begin
  select * into a from private.ocorrencia_encomenda(p_codigo);
  return jsonb_build_object('suspensa', (a.v_enc).suspensa, 'motivo', (a.v_enc).suspensa_motivo, 'cliente', a.v_cliente,
    'pode_gerir', not a.v_cliente and private.ocorrencia_gestor(),
    'equipa', case when a.v_cliente then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome) order by f.nome) from funcionarios f where f.empresa_id = (a.v_enc).empresa_id and f.ativo), '[]') end,
    'lista', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'codigo', o.codigo, 'tipo', o.tipo, 'gravidade', o.gravidade, 'estado', o.estado, 'descricao', o.descricao,
        'resolucao', o.resolucao, 'responsavel', (select nome from funcionarios where id = o.responsavel_id), 'responsavel_id', o.responsavel_id, 'visivel_cliente', o.visivel_cliente,
        'suspendeu', o.suspendeu, 'do_cliente', o.aberta_por_cliente, 'criada', o.created_at,
        'registos', case when a.v_cliente then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('acao', r.acao, 'nota', r.nota, 'quando', r.created_at,
            'quem', coalesce((select nome from funcionarios where id = r.user_id), (select nome from clientes where id = r.user_id), 'Sistema')) order by r.created_at) from ocorrencia_registos r where r.ocorrencia_id = o.id), '[]') end)
      order by o.created_at desc, o.codigo desc) from ocorrencias o where o.encomenda_id = (a.v_enc).id and (not a.v_cliente or o.visivel_cliente)), '[]'));
end $$;

-- Transições: suspensa não avança; manifesto já não é obrigatório para «em trânsito».
create or replace function public.transitar_encomenda(p_encomenda uuid, p_para estado_encomenda, p_nota text default null) returns encomendas
language plpgsql security definer set search_path = public as $$
declare
  v_enc   encomendas;
  v_papel papel_funcionario;
  v_falta text[] := '{}';
begin
  select * into v_enc from encomendas where id = p_encomenda for update;
  if not found then raise exception 'Encomenda inexistente.'; end if;
  if private.minha_empresa() is distinct from v_enc.empresa_id then
    raise exception 'Sem permissão para esta encomenda (inicie a sessão da empresa).';
  end if;
  v_papel := private.meu_papel();
  if v_papel is null then raise exception 'Sem permissão para esta encomenda.'; end if;
  if v_enc.suspensa and p_para <> 'cancelada' then
    raise exception 'A encomenda está suspensa (%). Retome-a antes de mudar o estado.', coalesce(v_enc.suspensa_motivo, 'ocorrência');
  end if;
  if not exists (select 1 from encomenda_transicoes t
                  where t.de = v_enc.estado and t.para = p_para and v_papel = any (t.papeis)) then
    raise exception 'Transição % → % não permitida para o papel %.', v_enc.estado, p_para, v_papel;
  end if;
  if v_papel = 'operador_terreno' and not (
       coalesce(v_enc.criado_por = auth.uid(), false)
       or exists (select 1 from trabalhos_terreno tt
                   where tt.encomenda_id = v_enc.id and tt.operador_id = auth.uid())) then
    raise exception 'Este serviço não está atribuído ao operador.';
  end if;
  if p_para = 'armazenamento' and v_enc.criada_no_terreno then
    if v_enc.cliente_id is null and coalesce(v_enc.cliente_nome, '') = '' then v_falta := v_falta || 'cliente'; end if;
    if coalesce(v_enc.origem, '') = '' or coalesce(v_enc.destino, '') = '' then v_falta := v_falta || 'rota'; end if;
    if not exists (select 1 from pagamentos pg
                    where pg.encomenda_id = v_enc.id and pg.tipo <> 'reembolso'
                      and pg.estado in ('pendente','parcial','pago')) then
      v_falta := v_falta || 'primeiro pagamento';
    end if;
    if v_enc.assinatura_documento_id is null and v_enc.pin_validacao_hash is null then
      v_falta := v_falta || 'assinatura ou PIN do cliente';
    end if;
  end if;
  if p_para = 'expedicao' and not exists (
       select 1 from recibos_armazem ra
        where ra.encomenda_id = v_enc.id and ra.confirmado and ra.carga_conferida) then
    v_falta := v_falta || 'receção confirmada e carga conferida pelo armazém';
  end if;
  if p_para = 'entregue' and not exists (
       select 1 from entregas en
        where en.encomenda_id = v_enc.id
          and coalesce(en.identificacao, '') <> ''
          and (en.assinatura_documento_id is not null or en.pin_validado)) then
    v_falta := v_falta || 'identificação e assinatura/PIN de entrega';
  end if;
  if cardinality(v_falta) > 0 then
    raise exception 'Não é possível avançar. Complete: %.', array_to_string(v_falta, ', ');
  end if;
  perform set_config('elolog.transicao', 'on', true);
  update encomendas set estado = p_para where id = v_enc.id;
  perform set_config('elolog.transicao', 'off', true);
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id)
    values (v_enc.id, v_enc.empresa_id, v_enc.estado, p_para, p_nota, auth.uid());
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, antes, depois, motivo)
    values (v_enc.empresa_id, auth.uid(), v_papel::text, 'transicao_encomenda', 'encomendas', v_enc.id::text,
            jsonb_build_object('estado', v_enc.estado), jsonb_build_object('estado', p_para), p_nota);
  if v_enc.cliente_id is not null then
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (v_enc.cliente_id, 'estado_encomenda', 'A sua encomenda ' || v_enc.codigo || ' mudou de estado',
              p_para::text, 'encomendas', v_enc.id);
  end if;
  select * into v_enc from encomendas where id = p_encomenda;
  return v_enc;
end $$;

revoke all on function private.ocorrencia_gestor(), private.ocorrencia_encomenda(text), private.ocorrencia_avisar_cliente(ocorrencias, text, text),
  public.encomenda_suspender(text, text), public.encomenda_retomar(text, text), public.ocorrencia_criar(text, text, text, text, boolean, boolean),
  public.ocorrencia_atualizar(uuid, text, text, text, uuid, text, boolean, text), public.ocorrencias_da_encomenda(text) from public, anon;
grant execute on function public.encomenda_suspender(text, text), public.encomenda_retomar(text, text), public.ocorrencia_criar(text, text, text, text, boolean, boolean),
  public.ocorrencia_atualizar(uuid, text, text, text, uuid, text, boolean, text), public.ocorrencias_da_encomenda(text) to authenticated;

-- v99 — Encomendas diretas: revisão administrativa.
-- A administração vê o comprovativo antes de validar, corrige dados administrativos, pede documentos adicionais ao cliente
-- e valida/encaminha ao prestador. Só ACRESCENTA colunas, uma tabela e funções; nada é apagado.

alter table encomendas_diretas add column if not exists pedido_documentos    text check (pedido_documentos is null or length(pedido_documentos) <= 500);
alter table encomendas_diretas add column if not exists pedido_documentos_em timestamptz;
alter table encomendas_diretas add column if not exists comprovativo_visto_em timestamptz;      -- quando a administração abriu o comprovativo

create table if not exists encomendas_diretas_anexos (
  id           bigint generated always as identity primary key,
  encomenda_id uuid not null references encomendas_diretas(id),
  documento_id uuid not null references documentos(id),
  nota         text check (nota is null or length(nota) <= 300),
  enviado_por  uuid,
  created_at   timestamptz not null default now());
create index if not exists encomendas_diretas_anexos_enc on encomendas_diretas_anexos (encomenda_id, id);
alter table encomendas_diretas_anexos enable row level security;
revoke all on encomendas_diretas_anexos from anon, authenticated;
grant select on encomendas_diretas_anexos to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'encomendas_diretas_anexos' and policyname = 'eda_ver') then
    create policy eda_ver on encomendas_diretas_anexos for select to authenticated
      using (exists (select 1 from encomendas_diretas e where e.id = encomenda_id and private.ed_visivel(e))); end if;
  if not exists (select 1 from pg_policies where tablename = 'documentos' and policyname = 'docs_encomenda_direta_anexos_prestador') then
    create policy docs_encomenda_direta_anexos_prestador on documentos for select to authenticated using (exists (select 1 from encomendas_diretas_anexos a
      join encomendas_diretas e on e.id = a.encomenda_id where a.documento_id = documentos.id and e.empresa_id = private.minha_empresa()
      and e.estado in ('enviada_prestador','em_analise_prestador','aceite','recusada'))); end if;
end $$;

-- Administração: o comprovativo foi aberto (fica registado; validar exige que tenha sido visto)
create or replace function public.admin_comprovativo_visto(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;
  update encomendas_diretas set comprovativo_visto_em = coalesce(comprovativo_visto_em, now()) where id = p_id;
end $$;

-- Administração: analisar, pedir documentos, validar (só depois de ver o comprovativo), validar e encaminhar, não validar, encaminhar
create or replace function public.admin_encomenda_direta(p_id uuid, p_acao text, p_nota text default null) returns void
language plpgsql security definer set search_path = public as $$
declare e encomendas_diretas; novo text;
begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;
  select * into e from encomendas_diretas where id = p_id for update;
  if not found then raise exception 'Encomenda direta não encontrada.'; end if;
  novo := case
    when p_acao = 'analisar'         and e.estado = 'pendente_validacao' then 'em_analise_admin'
    when p_acao = 'pedir_documentos' and e.estado in ('pendente_validacao', 'em_analise_admin', 'validada') then 'em_analise_admin'
    when p_acao in ('validar', 'validar_enviar') and e.estado in ('pendente_validacao', 'em_analise_admin') then 'validada'
    when p_acao = 'nao_validar'      and e.estado in ('pendente_validacao', 'em_analise_admin') then 'nao_validada'
    when p_acao = 'enviar'           and e.estado = 'validada' then 'enviada_prestador' end;
  if novo is null then raise exception 'Esta ação não é possível no estado atual (%).', e.estado; end if;
  if p_acao = 'pedir_documentos' then
    if length(trim(coalesce(p_nota, ''))) < 5 then raise exception 'Indique ao cliente que documentos são precisos.'; end if;
    update encomendas_diretas set pedido_documentos = trim(p_nota), pedido_documentos_em = now() where id = p_id;
    perform private.ed_registar(p_id, novo, 'administracao', 'Documentos pedidos: ' || trim(p_nota)); return; end if;
  if p_acao in ('validar', 'validar_enviar') then
    if e.comprovativo_visto_em is null then raise exception 'Abra e analise o comprovativo antes de validar.'; end if;
    if e.pedido_documentos is not null then raise exception 'Há documentos pedidos ao cliente ainda por receber.'; end if; end if;
  if novo = 'nao_validada' then
    if length(trim(coalesce(p_nota, ''))) < 5 then raise exception 'Indique ao cliente o motivo da não validação.'; end if;
    update encomendas_diretas set motivo = trim(p_nota), motivo_tipo = null, pedido_documentos = null where id = p_id; end if;
  if (novo = 'enviada_prestador' or p_acao = 'validar_enviar') and not exists (select 1 from empresas_disponiveis d where d.id = e.empresa_id) then
    raise exception 'O prestador escolhido já não está ativo. Contacte o cliente para escolher outro.'; end if;
  perform private.ed_registar(p_id, novo, 'administracao', p_nota);
  if p_acao = 'validar_enviar' then perform private.ed_registar(p_id, 'enviada_prestador', 'administracao', null); end if;
end $$;

-- Administração: corrigir dados administrativos antes de encaminhar (o prestador continua a ser o escolhido pelo cliente)
create or replace function public.admin_corrigir_encomenda_direta(p_id uuid, p_dados jsonb, p_nota text default null) returns void
language plpgsql security definer set search_path = public as $$
declare e encomendas_diretas; n encomendas_diretas; dif text := '';
begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;
  select * into e from encomendas_diretas where id = p_id for update;
  if not found then raise exception 'Encomenda direta não encontrada.'; end if;
  if e.estado not in ('pendente_validacao', 'em_analise_admin', 'validada') then raise exception 'Só pode corrigir antes de encaminhar ao prestador.'; end if;
  update encomendas_diretas set
    origem = coalesce(nullif(trim(p_dados->>'origem'), ''), origem), destino = coalesce(nullif(trim(p_dados->>'destino'), ''), destino),
    mercadoria = coalesce(nullif(trim(p_dados->>'mercadoria'), ''), mercadoria), volumes = coalesce((p_dados->>'volumes')::int, volumes),
    peso_kg = case when p_dados ? 'peso_kg' then (p_dados->>'peso_kg')::numeric else peso_kg end,
    volume_m3 = case when p_dados ? 'volume_m3' then (p_dados->>'volume_m3')::numeric else volume_m3 end,
    valor_acordado = coalesce((p_dados->>'valor_acordado')::numeric, valor_acordado),
    data_prevista = case when p_dados ? 'data_prevista' then (p_dados->>'data_prevista')::date else data_prevista end,
    observacoes = case when p_dados ? 'observacoes' then nullif(trim(p_dados->>'observacoes'), '') else observacoes end
   where id = p_id returning * into n;
  if not exists (select 1 from public.prestadores_encomenda_direta(n.origem, n.destino) x where x.id = n.empresa_id) then
    raise exception 'Com esta rota, o prestador escolhido pelo cliente deixa de ser elegível. Contacte o cliente.'; end if;
  if n.data_prevista is distinct from e.data_prevista and n.data_prevista < current_date then raise exception 'A data prevista não pode ser no passado.'; end if;
  dif := concat_ws('; ',
    case when n.origem is distinct from e.origem then 'origem: ' || e.origem || ' → ' || n.origem end,
    case when n.destino is distinct from e.destino then 'destino: ' || e.destino || ' → ' || n.destino end,
    case when n.mercadoria is distinct from e.mercadoria then 'mercadoria: ' || n.mercadoria end,
    case when n.volumes is distinct from e.volumes then 'volumes: ' || e.volumes || ' → ' || n.volumes end,
    case when n.peso_kg is distinct from e.peso_kg then 'peso: ' || coalesce(e.peso_kg::text, '—') || ' → ' || coalesce(n.peso_kg::text, '—') || ' kg' end,
    case when n.volume_m3 is distinct from e.volume_m3 then 'volume: ' || coalesce(e.volume_m3::text, '—') || ' → ' || coalesce(n.volume_m3::text, '—') || ' m³' end,
    case when n.valor_acordado is distinct from e.valor_acordado then 'valor: ' || e.valor_acordado || ' → ' || n.valor_acordado || ' €' end,
    case when n.data_prevista is distinct from e.data_prevista then 'data: ' || coalesce(to_char(e.data_prevista, 'DD/MM/YYYY'), '—') || ' → ' || coalesce(to_char(n.data_prevista, 'DD/MM/YYYY'), '—') end,
    case when n.observacoes is distinct from e.observacoes then 'observações atualizadas' end);
  if dif = '' then raise exception 'Não há alterações.'; end if;
  perform private.ed_registar(p_id, n.estado, 'administracao', 'Dados corrigidos — ' || dif || coalesce('. ' || nullif(trim(p_nota), ''), ''));
end $$;

-- Cliente: enviar documentos adicionais pedidos pela administração
create or replace function public.cliente_anexo_encomenda_direta(p_id uuid, p_documento uuid, p_nota text default null) returns void
language plpgsql security definer set search_path = public as $$
declare e encomendas_diretas;
begin
  select * into e from encomendas_diretas where id = p_id and cliente_id = auth.uid() for update;
  if not found then raise exception 'Encomenda direta não encontrada.'; end if;
  if e.estado not in ('pendente_validacao', 'em_analise_admin', 'validada', 'nao_validada') then raise exception 'Já não é possível juntar documentos a esta encomenda.'; end if;
  if not exists (select 1 from documentos d where d.id = p_documento and d.cliente_id = auth.uid()) then raise exception 'Documento inválido.'; end if;
  insert into encomendas_diretas_anexos (encomenda_id, documento_id, nota, enviado_por) values (p_id, p_documento, nullif(trim(p_nota), ''), auth.uid());
  update encomendas_diretas set pedido_documentos = null, pedido_documentos_em = null where id = p_id;
  perform private.ed_registar(p_id, case when e.estado = 'nao_validada' then 'em_analise_admin' else e.estado end, 'cliente',
    'Documento adicional enviado' || coalesce(': ' || nullif(trim(p_nota), ''), '.'));
end $$;

-- Lista com anexos (mesma visibilidade)
create or replace function public.encomendas_diretas_lista() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb) from (
    select to_jsonb(e) || jsonb_build_object(
      'prestador', coalesce(em.nome_comercial, em.nome),
      'cliente_nome', coalesce(c.nome, u.email),
      'cliente_email', case when private.e_admin_plataforma() or e.cliente_id = auth.uid() or e.estado = 'aceite' then coalesce(c.email, u.email) end,
      'cliente_telefone', case when private.e_admin_plataforma() or e.cliente_id = auth.uid() or e.estado = 'aceite' then c.telefone end,
      'documento', (select jsonb_build_object('nome', d.nome, 'caminho', d.storage_path, 'mime', d.mime, 'verificado', d.verificado) from documentos d where d.id = e.documento_id),
      'anexos', (select coalesce(jsonb_agg(jsonb_build_object('nome', d.nome, 'caminho', d.storage_path, 'mime', d.mime, 'nota', a.nota, 'em', a.created_at) order by a.id), '[]'::jsonb)
                   from encomendas_diretas_anexos a join documentos d on d.id = a.documento_id where a.encomenda_id = e.id),
      'historico', (select coalesce(jsonb_agg(jsonb_build_object('estado', h.estado, 'papel', h.papel, 'nota', h.nota, 'em', h.created_at) order by h.id), '[]'::jsonb)
                      from encomendas_diretas_historico h where h.encomenda_id = e.id)) as x
      from encomendas_diretas e join empresas em on em.id = e.empresa_id
      left join clientes c on c.id = e.cliente_id left join auth.users u on u.id = e.cliente_id
     where private.ed_visivel(e)) t $$;

revoke all on function public.admin_comprovativo_visto(uuid), public.admin_corrigir_encomenda_direta(uuid, jsonb, text), public.cliente_anexo_encomenda_direta(uuid, uuid, text) from public, anon;
grant execute on function public.admin_comprovativo_visto(uuid), public.admin_corrigir_encomenda_direta(uuid, jsonb, text), public.cliente_anexo_encomenda_direta(uuid, uuid, text) to authenticated;

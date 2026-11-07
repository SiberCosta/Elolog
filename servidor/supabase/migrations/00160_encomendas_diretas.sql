-- v98 — Encomendas diretas com validação da administração e decisão do prestador.
-- Só ACRESCENTA tabelas, funções e uma política de leitura de documentos. Tabelas, dados e ligações existentes ficam iguais.
-- Fluxo: cliente submete (pendente_validacao) → administração: em_analise_admin → validada | nao_validada (motivo) → enviada_prestador
--        → prestador: em_analise_prestador → aceite | recusada (motivo obrigatório). O cliente vê tudo; nunca há eliminação.
-- Regra: uma recusa não é eliminada nem reencaminhada a outro prestador sem o cliente — só o cliente troca de prestador.

create table if not exists encomendas_diretas (
  id               uuid primary key default gen_random_uuid(),
  codigo           text not null unique default private.proximo_codigo('ED'),
  cliente_id       uuid not null references auth.users(id),
  empresa_id       uuid not null references empresas(id),
  origem           text not null check (length(origem) between 2 and 120),
  destino          text not null check (length(destino) between 2 and 120),
  mercadoria       text not null check (length(mercadoria) between 2 and 300),
  volumes          int  not null check (volumes between 1 and 10000),
  peso_kg          numeric(12,2) check (peso_kg is null or peso_kg >= 0),
  volume_m3        numeric(12,3) check (volume_m3 is null or volume_m3 >= 0),
  valor_acordado   numeric(12,2) not null check (valor_acordado >= 0),
  data_prevista    date,
  observacoes      text check (observacoes is null or length(observacoes) <= 1000),
  documento_id     uuid references documentos(id),
  estado           text not null default 'pendente_validacao' check (estado in ('pendente_validacao','em_analise_admin','validada',
                     'nao_validada','enviada_prestador','em_analise_prestador','aceite','recusada','cancelada')),
  motivo_tipo      text check (motivo_tipo is null or motivo_tipo in ('rota','espaco','preco','documentacao','mercadoria','outro')),
  motivo           text check (motivo is null or length(motivo) <= 500),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now());
create index if not exists encomendas_diretas_cliente on encomendas_diretas (cliente_id, created_at desc);
create index if not exists encomendas_diretas_empresa on encomendas_diretas (empresa_id, estado);

create table if not exists encomendas_diretas_historico (
  id          bigint generated always as identity primary key,
  encomenda_id uuid not null references encomendas_diretas(id),
  estado      text not null,
  papel       text not null check (papel in ('cliente','administracao','prestador')),
  por         uuid,
  nota        text,
  created_at  timestamptz not null default now());
create index if not exists encomendas_diretas_historico_enc on encomendas_diretas_historico (encomenda_id, id);

alter table encomendas_diretas enable row level security;
alter table encomendas_diretas_historico enable row level security;
revoke all on encomendas_diretas, encomendas_diretas_historico from anon, authenticated;
grant select on encomendas_diretas, encomendas_diretas_historico to authenticated;   -- escritas só pelas funções abaixo

-- O prestador só vê o pedido depois de a administração o encaminhar.
create or replace function private.ed_visivel(e encomendas_diretas) returns boolean language sql stable security definer set search_path = public as $$
  select e.cliente_id = auth.uid() or private.e_admin_plataforma()
      or (e.empresa_id = private.minha_empresa() and e.estado in ('enviada_prestador','em_analise_prestador','aceite','recusada')) $$;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'encomendas_diretas' and policyname = 'ed_ver') then
    create policy ed_ver on encomendas_diretas for select to authenticated using (private.ed_visivel(encomendas_diretas)); end if;
  if not exists (select 1 from pg_policies where tablename = 'encomendas_diretas_historico' and policyname = 'edh_ver') then
    create policy edh_ver on encomendas_diretas_historico for select to authenticated
      using (exists (select 1 from encomendas_diretas e where e.id = encomenda_id and private.ed_visivel(e))); end if;
  -- comprovativo: a administração já lê todos os documentos; o prestador lê o comprovativo do pedido que lhe foi encaminhado
  if not exists (select 1 from pg_policies where tablename = 'documentos' and policyname = 'docs_encomenda_direta_prestador') then
    create policy docs_encomenda_direta_prestador on documentos for select to authenticated using (exists (select 1 from encomendas_diretas e
      where e.documento_id = documentos.id and e.empresa_id = private.minha_empresa() and e.estado in ('enviada_prestador','em_analise_prestador','aceite','recusada'))); end if;
end $$;
create or replace trigger auditar after insert or update on encomendas_diretas for each row execute function private.auditar_alteracao('updated_at');
create or replace trigger limitar_escritas before insert on encomendas_diretas for each row execute function private.limitar_escritas('20');

-- Prestadores ativos (aprovados e com subscrição ativa) e elegíveis para a rota:
-- se o prestador tem tarifas ativas com origem/destino, a rota tem de coincidir com uma delas; sem tarifas de rota, serve todas.
create or replace function public.prestadores_encomenda_direta(p_origem text default null, p_destino text default null)
returns table (id uuid, nome text, cidade text, pais text) language sql stable security definer set search_path = public as $$
  select d.id, d.nome, d.cidade, d.pais from empresas_disponiveis d
   where auth.uid() is not null
     and (nullif(trim(coalesce(p_origem,'')),'') is null or nullif(trim(coalesce(p_destino,'')),'') is null
          or not exists (select 1 from tarifas t where t.empresa_id = d.id and t.ativa and (t.origem is not null or t.destino is not null)
                           and (t.validade_fim is null or t.validade_fim >= current_date))
          or exists (select 1 from tarifas t where t.empresa_id = d.id and t.ativa and (t.validade_fim is null or t.validade_fim >= current_date)
                       and (t.origem is null or p_origem ilike '%' || t.origem || '%' or t.origem ilike '%' || p_origem || '%')
                       and (t.destino is null or p_destino ilike '%' || t.destino || '%' or t.destino ilike '%' || p_destino || '%')))
   order by d.nome $$;

create or replace function private.ed_registar(p_id uuid, p_estado text, p_papel text, p_nota text) returns void
language plpgsql security definer set search_path = public as $$
declare e encomendas_diretas;
begin
  update encomendas_diretas set estado = p_estado, updated_at = now() where id = p_id returning * into e;
  insert into encomendas_diretas_historico (encomenda_id, estado, papel, por, nota) values (p_id, p_estado, p_papel, auth.uid(), nullif(trim(p_nota), ''));
  -- avisos: cliente sempre; administração nas decisões do cliente e do prestador; prestador quando recebe o pedido
  insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (e.cliente_id, 'encomenda_direta', 'Encomenda direta ' || e.codigo, 'Estado: ' || replace(p_estado, '_', ' '), 'encomendas_diretas', e.id);
  if p_papel <> 'administracao' then
    insert into notificacoes (para_plataforma, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (true, 'encomenda_direta', 'Encomenda direta ' || e.codigo || ' — ' || replace(p_estado, '_', ' '), nullif(trim(p_nota), ''), 'encomendas_diretas', e.id); end if;
  if p_estado = 'enviada_prestador' then
    insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (e.empresa_id, 'encomenda_direta', 'Nova encomenda direta ' || e.codigo, e.origem || ' → ' || e.destino, 'encomendas_diretas', e.id); end if;
end $$;

-- Cliente: registar a encomenda direta
create or replace function public.criar_encomenda_direta(p_empresa uuid, p_origem text, p_destino text, p_mercadoria text, p_volumes int,
  p_peso_kg numeric, p_volume_m3 numeric, p_valor numeric, p_data date, p_documento uuid, p_observacoes text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_cod text;
begin
  if auth.uid() is null or private.minha_empresa() is not null or private.e_admin_plataforma() then raise exception 'Só um cliente com sessão iniciada pode registar encomendas diretas.'; end if;
  if not exists (select 1 from public.prestadores_encomenda_direta(p_origem, p_destino) x where x.id = p_empresa) then
    raise exception 'O prestador escolhido não está ativo ou não serve esta rota.'; end if;
  if p_documento is null or not exists (select 1 from documentos d where d.id = p_documento and d.cliente_id = auth.uid()) then
    raise exception 'Anexe o comprovativo da negociação (proposta, orçamento, recibo ou documento de transporte).'; end if;
  if p_data is not null and p_data < current_date then raise exception 'A data prevista não pode ser no passado.'; end if;
  insert into encomendas_diretas (cliente_id, empresa_id, origem, destino, mercadoria, volumes, peso_kg, volume_m3, valor_acordado, data_prevista, documento_id, observacoes)
    values (auth.uid(), p_empresa, trim(p_origem), trim(p_destino), trim(p_mercadoria), p_volumes, p_peso_kg, p_volume_m3, p_valor, p_data, p_documento, nullif(trim(p_observacoes), ''))
    returning id, codigo into v_id, v_cod;
  perform private.ed_registar(v_id, 'pendente_validacao', 'cliente', null);
  return jsonb_build_object('id', v_id, 'codigo', v_cod);
end $$;

-- Cliente: depois de uma recusa ou de não validação, escolher outro prestador (volta à validação) ou cancelar
create or replace function public.cliente_encomenda_direta(p_id uuid, p_acao text, p_empresa uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare e encomendas_diretas;
begin
  select * into e from encomendas_diretas where id = p_id and cliente_id = auth.uid() for update;
  if not found then raise exception 'Encomenda direta não encontrada.'; end if;
  if p_acao = 'trocar_prestador' then
    if e.estado not in ('recusada', 'nao_validada') then raise exception 'Só pode trocar de prestador depois de uma recusa ou de uma não validação.'; end if;
    if not exists (select 1 from public.prestadores_encomenda_direta(e.origem, e.destino) x where x.id = p_empresa) then raise exception 'O prestador escolhido não está ativo ou não serve esta rota.'; end if;
    update encomendas_diretas set empresa_id = p_empresa, motivo = null, motivo_tipo = null where id = p_id;
    perform private.ed_registar(p_id, 'pendente_validacao', 'cliente', 'Novo prestador escolhido pelo cliente.');
  elsif p_acao = 'cancelar' then
    if e.estado not in ('pendente_validacao', 'em_analise_admin', 'nao_validada', 'recusada') then raise exception 'Esta encomenda já não pode ser cancelada pelo cliente.'; end if;
    perform private.ed_registar(p_id, 'cancelada', 'cliente', null);
  else raise exception 'Ação inválida.'; end if;
end $$;

-- Administração: analisar, validar, não validar (motivo) e encaminhar ao prestador escolhido pelo cliente
create or replace function public.admin_encomenda_direta(p_id uuid, p_acao text, p_nota text default null) returns void
language plpgsql security definer set search_path = public as $$
declare e encomendas_diretas; novo text;
begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;
  select * into e from encomendas_diretas where id = p_id for update;
  if not found then raise exception 'Encomenda direta não encontrada.'; end if;
  novo := case
    when p_acao = 'analisar'    and e.estado = 'pendente_validacao' then 'em_analise_admin'
    when p_acao = 'validar'     and e.estado in ('pendente_validacao', 'em_analise_admin') then 'validada'
    when p_acao = 'nao_validar' and e.estado in ('pendente_validacao', 'em_analise_admin') then 'nao_validada'
    when p_acao = 'enviar'      and e.estado = 'validada' then 'enviada_prestador' end;
  if novo is null then raise exception 'Esta ação não é possível no estado atual (%).', e.estado; end if;
  if novo = 'nao_validada' then
    if length(trim(coalesce(p_nota, ''))) < 5 then raise exception 'Indique ao cliente o motivo da não validação.'; end if;
    update encomendas_diretas set motivo = trim(p_nota), motivo_tipo = null where id = p_id; end if;
  if novo = 'enviada_prestador' and not exists (select 1 from empresas_disponiveis d where d.id = e.empresa_id) then
    raise exception 'O prestador escolhido já não está ativo. Contacte o cliente para escolher outro.'; end if;
  perform private.ed_registar(p_id, novo, 'administracao', p_nota);
end $$;

-- Prestador: colocar em análise, aceitar ou recusar (motivo obrigatório)
create or replace function public.prestador_encomenda_direta(p_id uuid, p_acao text, p_motivo_tipo text default null, p_motivo text default null) returns void
language plpgsql security definer set search_path = public as $$
declare e encomendas_diretas; novo text;
begin
  if not private.papel_em(array['admin_empresa', 'operador']) then raise exception 'Sem permissão para decidir encomendas diretas.'; end if;
  select * into e from encomendas_diretas where id = p_id and empresa_id = private.minha_empresa() for update;
  if not found then raise exception 'Encomenda direta não encontrada.'; end if;
  novo := case
    when p_acao = 'analisar' and e.estado = 'enviada_prestador' then 'em_analise_prestador'
    when p_acao = 'aceitar'  and e.estado in ('enviada_prestador', 'em_analise_prestador') then 'aceite'
    when p_acao = 'recusar'  and e.estado in ('enviada_prestador', 'em_analise_prestador') then 'recusada' end;
  if novo is null then raise exception 'Esta ação não é possível no estado atual (%).', e.estado; end if;
  if novo = 'recusada' then
    if p_motivo_tipo is null or p_motivo_tipo not in ('rota','espaco','preco','documentacao','mercadoria','outro') then raise exception 'Escolha o motivo da recusa.'; end if;
    if p_motivo_tipo = 'outro' and length(trim(coalesce(p_motivo, ''))) < 5 then raise exception 'Descreva o motivo da recusa.'; end if;
    update encomendas_diretas set motivo_tipo = p_motivo_tipo, motivo = nullif(trim(p_motivo), '') where id = p_id; end if;
  perform private.ed_registar(p_id, novo, 'prestador', case when novo = 'recusada' then p_motivo_tipo || coalesce(': ' || nullif(trim(p_motivo), ''), '') end);
end $$;

revoke all on function public.prestadores_encomenda_direta(text, text), public.criar_encomenda_direta(uuid, text, text, text, int, numeric, numeric, numeric, date, uuid, text),
  public.cliente_encomenda_direta(uuid, text, uuid), public.admin_encomenda_direta(uuid, text, text), public.prestador_encomenda_direta(uuid, text, text, text) from public, anon;
grant execute on function public.prestadores_encomenda_direta(text, text), public.criar_encomenda_direta(uuid, text, text, text, int, numeric, numeric, numeric, date, uuid, text),
  public.cliente_encomenda_direta(uuid, text, uuid), public.admin_encomenda_direta(uuid, text, text), public.prestador_encomenda_direta(uuid, text, text, text) to authenticated;
revoke all on function private.ed_registar(uuid, text, text, text) from public, anon, authenticated;

-- Lista para cada perfil (cliente: as suas; administração: todas; prestador: as encaminhadas), com nomes, comprovativo e histórico.
-- Os contactos do cliente só chegam ao prestador depois de aceitar.
create or replace function public.encomendas_diretas_lista() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb) from (
    select to_jsonb(e) || jsonb_build_object(
      'prestador', coalesce(em.nome_comercial, em.nome),
      'cliente_nome', coalesce(c.nome, u.email),
      'cliente_email', case when private.e_admin_plataforma() or e.cliente_id = auth.uid() or e.estado = 'aceite' then coalesce(c.email, u.email) end,
      'cliente_telefone', case when private.e_admin_plataforma() or e.cliente_id = auth.uid() or e.estado = 'aceite' then c.telefone end,
      'documento', (select jsonb_build_object('nome', d.nome, 'caminho', d.storage_path, 'verificado', d.verificado) from documentos d where d.id = e.documento_id),
      'historico', (select coalesce(jsonb_agg(jsonb_build_object('estado', h.estado, 'papel', h.papel, 'nota', h.nota, 'em', h.created_at) order by h.id), '[]'::jsonb)
                      from encomendas_diretas_historico h where h.encomenda_id = e.id)) as x
      from encomendas_diretas e join empresas em on em.id = e.empresa_id
      left join clientes c on c.id = e.cliente_id left join auth.users u on u.id = e.cliente_id
     where private.ed_visivel(e)) t $$;
revoke all on function public.encomendas_diretas_lista() from public, anon;
grant execute on function public.encomendas_diretas_lista() to authenticated;

-- =====================================================================
-- Elolog · 0002 · Regras do fluxo como funções e gatilhos (Supabase / PostgreSQL 15+)
-- Depende de 0001_base.sql. As regras vêm de DOCUMENTACAO/ARQUITETURA_E_FLUXOS.md
-- e de PROVIDER_PERMISSIONS (js/nucleo/permissoes.js).
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- =====================================================================
-- ---------- 1. Segredo da empresa fora da tabela "empresas" -----------
-- A palavra-passe da empresa (1.º passo do login) nunca deve ser legível pela API.
-- Tabela com RLS ligada e SEM políticas: só o service_role (Edge Function) lhe acede.
create table empresa_segredos ( empresa_id uuid primary key references empresas(id) on delete cascade,
  segredo_hash text not null,                         -- hash (bcrypt/argon2), nunca em claro
  updated_at timestamptz not null default now() ); alter table empresa_segredos enable row level security;
create trigger trg_updated_at before update on empresa_segredos
  for each row execute function private.set_updated_at();
insert into empresa_segredos (empresa_id, segredo_hash)
  select id, segredo_acesso_hash from empresas where segredo_acesso_hash is not null;
alter table empresas drop column segredo_acesso_hash;
-- ---------- 2. Planos por omissão (valores do código: adminPlans()) ---
insert into planos (nome, preco_mensal, personalizado, trial_dias, max_funcionarios, max_operacoes, armazenamento_gb, suporte) values
  ('Básico',       29, false, 14, 3,    100,  2,    'Suporte normal'),
  ('Profissional', 79, false, 30, 15,   1000, 20,   'Suporte prioritário'),
  ('Empresarial',   0, true,  30, null, null, null, 'Gestor dedicado') on conflict (nome) do nothing;
-- ---------- 3. Transições permitidas e quem as executa ----------------
-- Fluxo: aprovação → agendamento → recolha → armazenamento → expedição → trânsito → destino → entregue
insert into encomenda_transicoes (de, para, papeis) values
  ('aprovacao',     'agendamento',   '{admin_empresa,operador}'),
  ('agendamento',   'recolha',       '{admin_empresa,operador,operador_terreno}'),
  ('recolha',       'armazenamento', '{admin_empresa,operador,operador_terreno}'),
  ('armazenamento', 'expedicao',     '{admin_empresa,operador,armazem}'),
  ('expedicao',     'em_transito',   '{admin_empresa,operador,armazem}'),
  ('em_transito',   'destino',       '{admin_empresa,operador,armazem}'),
  ('destino',       'entregue',      '{admin_empresa,operador,operador_terreno}'),
  ('aprovacao',     'cancelada',     '{admin_empresa,operador}'),
  ('agendamento',   'cancelada',     '{admin_empresa,operador}'),
  ('recolha',       'cancelada',     '{admin_empresa,operador}'),
  ('armazenamento', 'cancelada',     '{admin_empresa}') on conflict do nothing;
-- ---------- 4. O estado da encomenda só muda por transitar_encomenda() -
create function private.bloquear_estado_direto() returns trigger language plpgsql as $$ begin
  if new.estado is distinct from old.estado
     and coalesce(current_setting('elolog.transicao', true), '') <> 'on' then
    raise exception 'O estado da encomenda só pode mudar através de transitar_encomenda().'; end if;
  return new; end $$; create trigger trg_encomenda_estado_direto before update on encomendas
  for each row execute function private.bloquear_estado_direto(); create function public.transitar_encomenda(
  p_encomenda uuid, p_para estado_encomenda, p_nota text default null ) returns encomendas
language plpgsql security definer set search_path = public as $$ declare v_enc   encomendas;
  v_papel papel_funcionario; v_falta text[] := '{}'; begin
  select * into v_enc from encomendas where id = p_encomenda for update;
  if not found then raise exception 'Encomenda inexistente.'; end if; select f.papel into v_papel
    from funcionarios f join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
   where f.id = auth.uid() and f.empresa_id = v_enc.empresa_id and f.ativo;
  if v_papel is null then raise exception 'Sem permissão para esta encomenda.'; end if;
  if not exists (select 1 from encomenda_transicoes t
                  where t.de = v_enc.estado and t.para = p_para and v_papel = any (t.papeis)) then
    raise exception 'Transição % → % não permitida para o papel %.', v_enc.estado, p_para, v_papel; end if;
  -- Operador de terreno: só serviços atribuídos a si ou criados por si.
  if v_papel = 'operador_terreno' and not ( coalesce(v_enc.criado_por = auth.uid(), false)
       or exists (select 1 from trabalhos_terreno tt
                   where tt.encomenda_id = v_enc.id and tt.operador_id = auth.uid())) then
    raise exception 'Este serviço não está atribuído ao operador.'; end if;
  -- Condições mínimas (tabela "Regras obrigatórias" da documentação)
  if p_para = 'armazenamento' and v_enc.criada_no_terreno then
    if v_enc.cliente_id is null and coalesce(v_enc.cliente_nome, '') = '' then v_falta := v_falta || 'cliente'; end if;
    if coalesce(v_enc.origem, '') = '' or coalesce(v_enc.destino, '') = '' then v_falta := v_falta || 'rota'; end if;
    if not exists (select 1 from pagamentos pg where pg.encomenda_id = v_enc.id and pg.tipo <> 'reembolso'
                      and pg.estado in ('pendente','parcial','pago')) then
      v_falta := v_falta || 'primeiro pagamento'; end if;
    if v_enc.assinatura_documento_id is null and v_enc.pin_validacao_hash is null then
      v_falta := v_falta || 'assinatura ou PIN do cliente'; end if; end if;
  if p_para = 'expedicao' and not exists ( select 1 from recibos_armazem ra
        where ra.encomenda_id = v_enc.id and ra.confirmado and ra.carga_conferida) then
    v_falta := v_falta || 'receção confirmada e carga conferida pelo armazém'; end if;
  if p_para = 'em_transito' and not exists ( select 1 from manifesto_encomendas me
         join manifestos m on m.id = me.manifesto_id
        where me.encomenda_id = v_enc.id and m.estado in ('confirmado','em_transito')) then
    v_falta := v_falta || 'manifesto confirmado'; end if; if p_para = 'entregue' and not exists (
       select 1 from entregas en where en.encomenda_id = v_enc.id and coalesce(en.identificacao, '') <> ''
          and (en.assinatura_documento_id is not null or en.pin_validado)) then
    v_falta := v_falta || 'identificação e assinatura/PIN de entrega'; end if;
  if cardinality(v_falta) > 0 then
    raise exception 'Não é possível avançar. Complete: %.', array_to_string(v_falta, ', '); end if;
  perform set_config('elolog.transicao', 'on', true);
  update encomendas set estado = p_para where id = v_enc.id;
  perform set_config('elolog.transicao', 'off', true);
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id)
    values (v_enc.id, v_enc.empresa_id, v_enc.estado, p_para, p_nota, auth.uid());
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, antes, depois, motivo)
    values (v_enc.empresa_id, auth.uid(), v_papel::text, 'transicao_encomenda', 'encomendas', v_enc.id::text,
            jsonb_build_object('estado', v_enc.estado), jsonb_build_object('estado', p_para), p_nota);
  select * into v_enc from encomendas where id = p_encomenda; return v_enc; end $$;
-- ---------- 5. Cliente aceita proposta → nasce a encomenda ------------
-- "Proposta aceite gera encomenda para aprovação operacional."
create function public.aceitar_proposta(p_proposta uuid) returns encomendas
language plpgsql security definer set search_path = public as $$ declare v_prop propostas; v_sim  simulacoes;
  v_enc  encomendas; begin select * into v_prop from propostas where id = p_proposta for update;
  if not found then raise exception 'Proposta inexistente.'; end if;
  select * into v_sim from simulacoes where id = v_prop.simulacao_id for update;
  if v_sim.cliente_id is distinct from auth.uid() then raise exception 'Sem permissão.'; end if;
  if v_prop.estado <> 'enviada' then raise exception 'A proposta já não está disponível (%).', v_prop.estado; end if;
  if v_prop.validade is not null and v_prop.validade < current_date then raise exception 'A proposta expirou.'; end if;
  update propostas set estado = 'aceite', respondida_em = now() where id = v_prop.id;
  update propostas set estado = 'recusada', respondida_em = now()
   where simulacao_id = v_prop.simulacao_id and id <> v_prop.id and estado = 'enviada';
  update simulacoes set estado = 'convertida' where id = v_sim.id;
  insert into encomendas (empresa_id, cliente_id, simulacao_id, proposta_id, origem, destino, tipo_carga,
                          descricao, quantidade, peso_kg, volume_m3, volumes, preco_total, moeda, estado, criado_por)
  values (v_prop.empresa_id, v_sim.cliente_id, v_sim.id, v_prop.id, v_sim.origem, v_sim.destino, v_sim.tipo_carga,
          v_sim.descricao, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3, v_sim.volumes, v_prop.preco,
          v_prop.moeda, 'aprovacao', auth.uid()) returning * into v_enc;
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id)
    values (v_enc.id, v_enc.empresa_id, null, 'aprovacao', 'Proposta aceite pelo cliente', auth.uid());
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_enc.empresa_id, auth.uid(), 'cliente', 'aceitar_proposta', 'propostas', v_prop.id::text,
            jsonb_build_object('encomenda', v_enc.codigo)); return v_enc; end $$;
-- Ao criar uma proposta, a simulação passa a "respondida" (deixa de contar como nova).
create function private.proposta_marca_respondida() returns trigger
language plpgsql security definer set search_path = public as $$ begin
  update simulacoes set estado = 'respondida' where id = new.simulacao_id and estado = 'enviada'; return new;
end $$; create trigger trg_proposta_respondida after insert on propostas
  for each row execute function private.proposta_marca_respondida();
-- ---------- 6. Aprovação / recusa de empresas (plataforma) ------------
-- "A autorização ativa a subscrição; a recusa suspende-a."
create function public.decidir_empresa(p_empresa uuid, p_aprovar boolean, p_motivo text default null)
returns empresas language plpgsql security definer set search_path = public as $$ declare v_emp   empresas;
  v_antes estado_empresa; begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;
  select estado into v_antes from empresas where id = p_empresa for update;
  if not found then raise exception 'Empresa inexistente.'; end if; if p_aprovar then
    if exists (select 1 from subscricoes s join planos pl on pl.id = s.plano_id
                where s.empresa_id = p_empresa and s.estado = 'pendente'
                  and pl.preco_mensal > 0 and s.pago_em is null) then
      raise exception 'O pagamento da subscrição ainda não foi confirmado.'; end if;
    update empresas set estado = 'aprovada', aprovada_por = auth.uid(), aprovada_em = now()
     where id = p_empresa returning * into v_emp;
    update subscricoes set estado = 'ativa', confirmado_por = coalesce(confirmado_por, auth.uid())
     where empresa_id = p_empresa and estado = 'pendente'; else
    update empresas set estado = case when v_antes = 'pendente' then 'rejeitada'::estado_empresa
                                      else 'suspensa'::estado_empresa end
     where id = p_empresa returning * into v_emp;
    update subscricoes set estado = 'suspensa' where empresa_id = p_empresa and estado in ('pendente','ativa');
  end if;
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, antes, depois, motivo)
    values (p_empresa, auth.uid(), 'admin_plataforma',
            case when p_aprovar then 'aprovar_empresa' else 'recusar_empresa' end,
            'empresas', p_empresa::text,
            jsonb_build_object('estado', v_antes), jsonb_build_object('estado', v_emp.estado), p_motivo);
  return v_emp; end $$;
-- A 1.ª conta de administrador da empresa (auth.users + funcionarios) é criada por uma
-- Edge Function com service_role, depois desta aprovação.
-- ---------- 7. Tarifas usadas nunca são alteradas retroativamente ------
create function private.proteger_tarifa_usada() returns trigger
language plpgsql security definer set search_path = public as $$ begin
  if exists (select 1 from propostas p where p.tarifa_id = old.id) and (
       (new.aplicacao, new.metodo, new.valor, new.moeda, new.quantidade_minima, new.preco_minimo,
        new.origem, new.destino, new.tipo_carga, new.transporte, new.regras::text) is distinct from
       (old.aplicacao, old.metodo, old.valor, old.moeda, old.quantidade_minima, old.preco_minimo,
        old.origem, old.destino, old.tipo_carga, old.transporte, old.regras::text)) then
    raise exception 'Tarifa já utilizada: crie uma nova versão (a anterior fica inativa).'; end if;
  return new; end $$;

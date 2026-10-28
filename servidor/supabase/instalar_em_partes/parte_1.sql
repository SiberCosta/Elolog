-- Elolog — instalação, parte 1 de 4 (00021_regras_fluxo_parte1.sql a 00041_calculo_tarifas.sql). Correr pela ordem: 1, 2, 3, 4.
begin;
-- ===== 00021_regras_fluxo_parte1.sql =====
-- =====================================================================
-- Elolog · 0002 · Regras do fluxo como funções e gatilhos (Supabase / PostgreSQL 15+)
-- Depende de 0001_base.sql. As regras vêm de DOCUMENTACAO/ARQUITETURA_E_FLUXOS.md
-- e de PROVIDER_PERMISSIONS (js/nucleo/permissoes.js).
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- =====================================================================
-- ---------- 1. Segredo da empresa fora da tabela "empresas" -----------
-- A palavra-passe da empresa (1.º passo do login) nunca deve ser legível pela API.
-- Tabela com RLS ligada e SEM políticas: só o service_role (Edge Function) lhe acede.
create table if not exists empresa_segredos ( empresa_id uuid primary key references empresas(id) on delete cascade,
  segredo_hash text not null,                         -- hash (bcrypt/argon2), nunca em claro
  updated_at timestamptz not null default now() ); alter table empresa_segredos enable row level security;
drop trigger if exists trg_updated_at on empresa_segredos;
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


-- ===== 00022_regras_fluxo_parte2.sql =====
create trigger trg_tarifa_usada before update on tarifas
  for each row execute function private.proteger_tarifa_usada();

-- ---------- 8. Manifestos: só o admin confirma/cancela; confirmados não se alteram
create function private.regras_manifesto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.estado in ('confirmado','cancelado') and new.estado is distinct from old.estado
     and not (private.meu_papel() = 'admin_empresa' or private.e_admin_plataforma()) then
    raise exception 'Só o administrador da empresa pode confirmar ou cancelar manifestos.';
  end if;
  if old.estado in ('confirmado','em_transito','concluido') and (
       (new.numero, new.versao, new.origem, new.destino, new.numero_viagem, new.partida, new.chegada,
        new.transportador, new.total_unidades, new.total_peso_kg, new.total_volume_m3)
       is distinct from
       (old.numero, old.versao, old.origem, old.destino, old.numero_viagem, old.partida, old.chegada,
        old.transportador, old.total_unidades, old.total_peso_kg, old.total_volume_m3)) then
    raise exception 'Manifesto confirmado não se altera: crie uma nova versão.';
  end if;
  return new;
end $$;
create trigger trg_manifesto_regras before update on manifestos
  for each row execute function private.regras_manifesto();

-- ---------- 9. Notificações persistentes para a administração ---------
create function private.notificar_plataforma() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_tipo text; v_titulo text;
begin
  if tg_table_name = 'empresas' then
    v_tipo := 'novo_prestador';      v_titulo := 'Novo pedido de inscrição de prestador';
  elsif tg_table_name = 'subscricoes' then
    v_tipo := 'pedido_subscricao';   v_titulo := 'Novo pedido de subscrição';
  elsif tg_table_name = 'pedidos_cliente' then
    v_tipo := 'pedido_cliente';      v_titulo := 'Pedido do cliente: ' || new.tipo;
  else
    v_tipo := 'apoio';               v_titulo := 'Novo pedido de apoio ou reclamação';
  end if;
  insert into notificacoes (para_plataforma, tipo, titulo, referencia_tabela, referencia_id)
    values (true, v_tipo, v_titulo, tg_table_name, new.id);
  return new;
end $$;

create trigger trg_notif_empresas  after insert on empresas
  for each row execute function private.notificar_plataforma();
create trigger trg_notif_subscricoes after insert on subscricoes
  for each row execute function private.notificar_plataforma();
create trigger trg_notif_pedidos after insert on pedidos_cliente
  for each row execute function private.notificar_plataforma();
create trigger trg_notif_tickets after insert on tickets
  for each row when (new.origem in ('cliente','reclamacao') or new.escalado)
  execute function private.notificar_plataforma();

-- ---------- 10. Execução das funções públicas -------------------------
revoke execute on function public.transitar_encomenda(uuid, estado_encomenda, text) from public, anon;
revoke execute on function public.aceitar_proposta(uuid) from public, anon;
revoke execute on function public.decidir_empresa(uuid, boolean, text) from public, anon;
grant  execute on function public.transitar_encomenda(uuid, estado_encomenda, text) to authenticated;
grant  execute on function public.aceitar_proposta(uuid) to authenticated;
grant  execute on function public.decidir_empresa(uuid, boolean, text) to authenticated;


-- ===== 00031_rls_parte1.sql =====
-- =====================================================================
-- Elolog · 0003 · Segurança ao nível da linha (RLS) e permissões
-- Depende de 0001 e 0002. A empresa do utilizador vem SEMPRE da sessão (auth.uid()),
-- nunca de um valor enviado pelo navegador.
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- Aplicar 0003 logo a seguir a 0002 (as funções de 0002 usam os auxiliares daqui).
-- =====================================================================
-- ---------- 1. Funções auxiliares (security definer: evitam recursão de RLS)
create function private.e_admin_plataforma() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from administradores_plataforma where user_id = auth.uid()) $$;
-- Empresa do utilizador autenticado (apenas se funcionário ativo de empresa aprovada)
create function private.minha_empresa() returns uuid
language sql stable security definer set search_path = public as $$ select f.empresa_id from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada' where f.id = auth.uid() and f.ativo
$$; create function private.meu_papel() returns papel_funcionario
language sql stable security definer set search_path = public as $$ select f.papel from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada' where f.id = auth.uid() and f.ativo
$$; create function private.papel_em(p text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(private.meu_papel()::text = any (p), false) $$;
create function private.tem_permissao(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p = any (f.permissoes) from funcionarios f
                    where f.id = auth.uid() and f.ativo), false) $$;
-- O prestador só vê clientes com quem tem simulação enviada ou encomenda.
create function private.cliente_visivel(p_cliente uuid) returns boolean
language sql stable security definer set search_path = public as $$ select exists (select 1 from simulacoes s
                  where s.cliente_id = p_cliente and s.estado <> 'rascunho'
                    and s.empresa_destinatario_id = private.minha_empresa())
      or exists (select 1 from encomendas en
                  where en.cliente_id = p_cliente and en.empresa_id = private.minha_empresa()) $$;
create function private.ve_ticket(p_ticket uuid) returns boolean
language sql stable security definer set search_path = public as $$ select exists (select 1 from tickets t
                  where t.id = p_ticket and (t.cliente_id = auth.uid()
                         or (t.empresa_id is not null and t.empresa_id = private.minha_empresa())
                         or private.e_admin_plataforma())) $$;
grant execute on function private.e_admin_plataforma(), private.minha_empresa(), private.meu_papel(),
  private.papel_em(text[]), private.tem_permissao(text), private.cliente_visivel(uuid),
  private.ve_ticket(uuid) to authenticated, service_role;
-- ---------- 2. Privilégios base ---------------------------------------
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
-- Tabelas só escritas por funções/gatilhos (definer) ou pelo service_role
revoke insert, update, delete on auditoria, encomenda_historico, encomenda_transicoes from authenticated;
-- Colunas que cada utilizador pode alterar diretamente (o resto é identidade ou fluxo)
revoke update on empresas from authenticated;
grant  update (nome_comercial, telefone, morada, codigo_postal, cidade) on empresas to authenticated;
revoke update on funcionarios from authenticated;
grant  update (nome, papel, ativo, numero_interno, veiculo_habitual, permissoes) on funcionarios to authenticated;
revoke update on encomendas from authenticated;      -- o estado só muda por transitar_encomenda()
grant  update (cliente_nome, cliente_nif, cliente_telefone, origem, destino, tipo_carga, descricao,
               quantidade, peso_kg, volume_m3, volumes, preco_total, data_prevista,
               assinatura_documento_id, pin_validacao_hash) on encomendas to authenticated;
revoke update on notificacoes from authenticated; grant  update (lida_em) on notificacoes to authenticated;
-- ---------- 3. Administração da plataforma lê tudo (exceto segredos) --
do $$ declare r record; begin for r in select tablename from pg_tables where schemaname = 'public'
              and tablename not in ('empresa_segredos','tentativas_gate','contadores') loop
    execute format('create policy admin_plataforma_le on public.%I for select to authenticated
                    using (private.e_admin_plataforma())', r.tablename); end loop; end $$;
create policy planos_admin         on planos              for all to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
create policy subscricoes_admin    on subscricoes         for all to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
create policy comissoes_admin      on regras_comissao     for all to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
create policy conformidade_admin   on regras_conformidade for all to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
create policy faturas_admin        on faturas_plataforma  for all to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
create policy clientes_admin_upd   on clientes            for update to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
create policy pedidos_admin_upd    on pedidos_cliente     for update to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
create policy tickets_admin_upd    on tickets             for update to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
create policy notif_admin_upd      on notificacoes        for update to authenticated using (para_plataforma and private.e_admin_plataforma()) with check (para_plataforma and private.e_admin_plataforma());
-- ---------- 4. Empresas, planos, subscrições, equipa ------------------
create policy empresas_propria     on empresas for select to authenticated using (id = private.minha_empresa());
create policy empresas_editar      on empresas for update to authenticated
  using (id = private.minha_empresa() and private.papel_em(array['admin_empresa']))
  with check (id = private.minha_empresa());
-- Lista pública (para clientes) de prestadores autorizados, ativos e com subscrição paga.
-- Vista sem dados sensíveis; corre com os direitos do dono de propósito.
create view empresas_disponiveis as select e.id, coalesce(e.nome_comercial, e.nome) as nome, e.cidade, e.pais
    from empresas e where e.estado = 'aprovada'
     and exists (select 1 from subscricoes s where s.empresa_id = e.id and s.estado = 'ativa');
revoke all on empresas_disponiveis from anon; grant select on empresas_disponiveis to authenticated;
create policy planos_ativos        on planos for select to authenticated using (ativo);
create policy subscricoes_propria  on subscricoes for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']));
create policy funcionarios_ver     on funcionarios for select to authenticated using (id = auth.uid()
         or (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador'])));
create policy funcionarios_gerir   on funcionarios for update to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa']))
  with check (empresa_id = private.minha_empresa());
-- Criar/eliminar funcionários exige criar utilizadores em auth.users → Edge Function (service_role).
-- ---------- 5. Clientes e notas ---------------------------------------
create policy clientes_ver         on clientes for select to authenticated using (id = auth.uid()
         or (private.papel_em(array['admin_empresa','operador','armazem','financeiro']) and private.cliente_visivel(id)));
create policy clientes_criar       on clientes for insert to authenticated with check (id = auth.uid());
-- Alterações de dados do cliente passam por "pedidos_cliente" (aprovação da administração).
create policy cliente_notas_empresa on cliente_notas for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','financeiro']))
  with check (empresa_id = private.minha_empresa() and autor_id = auth.uid()
              and private.papel_em(array['admin_empresa','operador','financeiro']));
create policy pedidos_cliente_ver  on pedidos_cliente for select to authenticated using (cliente_id = auth.uid());
create policy pedidos_cliente_criar on pedidos_cliente for insert to authenticated
  with check (cliente_id = auth.uid() and estado = 'pendente');
-- ---------- 6. Armazéns e veículos ------------------------------------
create policy armazens_ver         on armazens for select to authenticated using (empresa_id = private.minha_empresa());
create policy armazens_gerir       on armazens for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','armazem']))
  with check (empresa_id = private.minha_empresa());
create policy veiculos_ver         on veiculos for select to authenticated using (empresa_id = private.minha_empresa());
create policy veiculos_gerir       on veiculos for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador']))
  with check (empresa_id = private.minha_empresa());
-- ---------- 7. Simulações (rascunho é privado do cliente) -------------
create policy sim_cliente_ver      on simulacoes for select to authenticated using (cliente_id = auth.uid());
create policy sim_cliente_criar    on simulacoes for insert to authenticated
  with check (cliente_id = auth.uid() and estado = 'rascunho');
create policy sim_cliente_editar   on simulacoes for update to authenticated
  using (cliente_id = auth.uid() and estado in ('rascunho','enviada'))
  with check (cliente_id = auth.uid() and estado in ('rascunho','enviada','cancelada'));
create policy sim_cliente_apagar   on simulacoes for delete to authenticated
  using (cliente_id = auth.uid() and estado = 'rascunho');
create policy sim_prestador_ver    on simulacoes for select to authenticated
  using (empresa_destinatario_id = private.minha_empresa() and estado <> 'rascunho'
         and private.papel_em(array['admin_empresa','operador','financeiro']));
-- ---------- 8. Financeiro: tarifas e regras ---------------------------
create policy tarifas_ver          on tarifas for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro','operador']));
create policy tarifas_gerir        on tarifas for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']))
  with check (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']));
-- Os clientes NÃO leem tarifas: o preço é calculado no servidor (0004: calcular_propostas /
-- enviar_simulacao), que devolve apenas o total. A regra comercial fica interna ao prestador.
create policy regras_fin_empresa   on regras_financeiras for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']))
  with check (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']));
-- ---------- 9. Propostas ----------------------------------------------
create policy prop_prestador_ver   on propostas for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','financeiro']));
create policy prop_prestador_criar on propostas for insert to authenticated
  with check (empresa_id = private.minha_empresa()
              and private.papel_em(array['admin_empresa','operador','financeiro'])
              and exists (select 1 from simulacoes s
                           where s.id = simulacao_id and s.empresa_destinatario_id = empresa_id
                             and s.estado in ('enviada','respondida')));
create policy prop_prestador_editar on propostas for update to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','financeiro']))
  with check (empresa_id = private.minha_empresa());
create policy prop_cliente_ver     on propostas for select to authenticated
  using (exists (select 1 from simulacoes s where s.id = simulacao_id and s.cliente_id = auth.uid()));
-- O cliente aceita através de aceitar_proposta() (cria a encomenda de forma atómica).
-- ---------- 10. Encomendas --------------------------------------------
create policy enc_cliente_ver      on encomendas for select to authenticated using (cliente_id = auth.uid());
create policy enc_empresa_ver      on encomendas for select to authenticated
  using (empresa_id = private.minha_empresa() and (private.meu_papel() <> 'operador_terreno'
              or criado_por = auth.uid() or exists (select 1 from trabalhos_terreno tt
                          where tt.encomenda_id = encomendas.id and tt.operador_id = auth.uid())));
create policy enc_empresa_criar    on encomendas for insert to authenticated
  with check (empresa_id = private.minha_empresa() and criado_por = auth.uid() and (
      (private.papel_em(array['admin_empresa','operador']) and estado = 'aprovacao' and not criada_no_terreno)
      -- Encomenda criada no terreno não passa pela aprovação: nasce em "recolha".
      or (private.papel_em(array['operador_terreno','operador','admin_empresa'])
          and criada_no_terreno and estado = 'recolha')));
create policy enc_empresa_editar   on encomendas for update to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','operador_terreno']))
  with check (empresa_id = private.minha_empresa());
create function private.proteger_preco_encomenda() returns trigger language plpgsql as $$ begin
  if new.preco_total is distinct from old.preco_total
     and not (private.papel_em(array['admin_empresa','financeiro']) or private.e_admin_plataforma()) then
    raise exception 'Só o administrador ou o financeiro podem alterar o preço.'; end if; return new; end $$;
create trigger trg_enc_preco before update on encomendas
  for each row execute function private.proteger_preco_encomenda();
create policy enc_historico_ver    on encomenda_historico for select to authenticated
  using (exists (select 1 from encomendas en where en.id = encomenda_id));  -- herda a visibilidade da encomenda
create policy transicoes_ver       on encomenda_transicoes for select to authenticated using (true);
-- ---------- 11. Armazém e entrega -------------------------------------
create policy recibos_ver          on recibos_armazem for select to authenticated
  using (exists (select 1 from encomendas en where en.id = encomenda_id and en.empresa_id = private.minha_empresa()));
create policy recibos_gerir        on recibos_armazem for all to authenticated
  using (private.papel_em(array['admin_empresa','operador','armazem'])
         and exists (select 1 from encomendas en where en.id = encomenda_id and en.empresa_id = private.minha_empresa()))
  with check (private.papel_em(array['admin_empresa','operador','armazem'])
         and exists (select 1 from encomendas en where en.id = encomenda_id and en.empresa_id = private.minha_empresa()));


-- ===== 00032_rls_parte2.sql =====
create policy entregas_ver         on entregas for select to authenticated
  using (exists (select 1 from encomendas en where en.id = encomenda_id));      -- empresa ou cliente da encomenda
create policy entregas_gerir       on entregas for all to authenticated
  using (private.papel_em(array['admin_empresa','operador','operador_terreno'])
         and exists (select 1 from encomendas en where en.id = encomenda_id and en.empresa_id = private.minha_empresa()))
  with check (private.papel_em(array['admin_empresa','operador','operador_terreno'])
         and exists (select 1 from encomendas en where en.id = encomenda_id and en.empresa_id = private.minha_empresa()));

-- ---------- 12. Documentos (versionados: sem UPDATE nem DELETE) -------
create policy docs_empresa_ver     on documentos for select to authenticated using (empresa_id = private.minha_empresa());
create policy docs_cliente_ver     on documentos for select to authenticated
  using (cliente_id = auth.uid()
         or (visibilidade = 'cliente'
             and exists (select 1 from encomendas en where en.id = encomenda_id and en.cliente_id = auth.uid())));
create policy docs_empresa_criar   on documentos for insert to authenticated
  with check (empresa_id = private.minha_empresa() and enviado_por = auth.uid());
create policy docs_cliente_criar   on documentos for insert to authenticated
  with check (cliente_id = auth.uid() and empresa_id is null and enviado_por = auth.uid());

-- ---------- 13. Pagamentos (sem DELETE; erros anulam-se com motivo) ---
create policy pag_empresa_ver      on pagamentos for select to authenticated
  using (empresa_id = private.minha_empresa()
         and (private.papel_em(array['admin_empresa','financeiro','operador']) or registado_por = auth.uid()));
create policy pag_cliente_ver      on pagamentos for select to authenticated using (cliente_id = auth.uid());
create policy pag_financeiro_criar on pagamentos for insert to authenticated
  with check (empresa_id = private.minha_empresa() and registado_por = auth.uid()
              and private.papel_em(array['admin_empresa','financeiro']));
-- Numerário no terreno: exige a permissão "receive_cash", fica pendente de reconciliação.
create policy pag_terreno_criar    on pagamentos for insert to authenticated
  with check (empresa_id = private.minha_empresa() and registado_por = auth.uid()
              and private.papel_em(array['operador_terreno'])
              and numerario_terreno and private.tem_permissao('receive_cash')
              and estado = 'pendente' and not reconciliado
              and exists (select 1 from encomendas en where en.id = encomenda_id));
create policy pag_financeiro_editar on pagamentos for update to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']))
  with check (empresa_id = private.minha_empresa());

-- ---------- 14. Manifestos e declarações de carga ---------------------
create policy manif_ver            on manifestos for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','armazem','financeiro']));
create policy manif_gerir          on manifestos for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','armazem']))
  with check (empresa_id = private.minha_empresa());
create policy manif_enc_ver        on manifesto_encomendas for select to authenticated
  using (exists (select 1 from manifestos m where m.id = manifesto_id and m.empresa_id = private.minha_empresa())
         and private.papel_em(array['admin_empresa','operador','armazem','financeiro']));
create policy manif_enc_gerir      on manifesto_encomendas for all to authenticated
  using (private.papel_em(array['admin_empresa','operador','armazem'])
         and exists (select 1 from manifestos m where m.id = manifesto_id and m.empresa_id = private.minha_empresa()))
  with check (private.papel_em(array['admin_empresa','operador','armazem'])
         and exists (select 1 from manifestos m where m.id = manifesto_id and m.empresa_id = private.minha_empresa()));
create policy decl_ver             on declaracoes_carga for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','armazem','financeiro']));
create policy decl_gerir           on declaracoes_carga for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','armazem']))
  with check (empresa_id = private.minha_empresa());

-- ---------- 15. Terreno -----------------------------------------------
create policy terreno_ver          on trabalhos_terreno for select to authenticated
  using (empresa_id = private.minha_empresa()
         and (private.meu_papel() <> 'operador_terreno' or operador_id = auth.uid()));
create policy terreno_gerir        on trabalhos_terreno for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador']))
  with check (empresa_id = private.minha_empresa());
create policy terreno_atribuido    on trabalhos_terreno for update to authenticated
  using (empresa_id = private.minha_empresa() and operador_id = auth.uid())
  with check (empresa_id = private.minha_empresa() and operador_id = auth.uid());

-- ---------- 16. Suporte, notificações, auditoria ----------------------
create policy tickets_ver          on tickets for select to authenticated
  using (cliente_id = auth.uid() or (empresa_id is not null and empresa_id = private.minha_empresa()));
create policy tickets_cliente_criar on tickets for insert to authenticated
  with check (cliente_id = auth.uid() and criado_por = auth.uid() and origem in ('cliente','reclamacao'));
create policy tickets_empresa_criar on tickets for insert to authenticated
  with check (empresa_id = private.minha_empresa() and criado_por = auth.uid() and origem in ('prestador','terreno'));
create policy tickets_empresa_editar on tickets for update to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador']))
  with check (empresa_id = private.minha_empresa());

create policy ticket_msg_ver       on ticket_mensagens for select to authenticated using (private.ve_ticket(ticket_id));
create policy ticket_msg_criar     on ticket_mensagens for insert to authenticated
  with check (autor_id = auth.uid() and private.ve_ticket(ticket_id));

create policy notif_ver            on notificacoes for select to authenticated
  using (user_id = auth.uid()
         or (empresa_id is not null and empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa'])));
create policy notif_marcar_lida    on notificacoes for update to authenticated
  using (user_id = auth.uid()
         or (empresa_id is not null and empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa'])))
  with check (user_id = auth.uid()
         or (empresa_id is not null and empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa'])));

create policy auditoria_empresa    on auditoria for select to authenticated
  using (empresa_id is not null and empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa']));

-- ---------- 17. Regras da plataforma visíveis ao prestador ------------
create policy comissoes_empresa    on regras_comissao for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']));
create policy conformidade_ver     on regras_conformidade for select to authenticated
  using (private.minha_empresa() is not null and (empresa_id is null or empresa_id = private.minha_empresa()));
create policy faturas_empresa      on faturas_plataforma for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']));

-- ---------- 18. Armazenamento privado de documentos -------------------
-- Convenção de caminho: <empresa_id>/... (prestador) ou <cliente_id>/... (cliente).
-- A leitura reaproveita a RLS da tabela "documentos". Requer o schema "storage" do Supabase.
insert into storage.buckets (id, name, public) values ('documentos', 'documentos', false)
  on conflict (id) do nothing;

create policy storage_documentos_ler on storage.objects for select to authenticated
  using (bucket_id = 'documentos'
         and exists (select 1 from public.documentos d where d.storage_path = storage.objects.name));
create policy storage_documentos_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'documentos'
              and (storage.foldername(name))[1] in (coalesce(private.minha_empresa()::text, ''), auth.uid()::text));
-- Sem políticas de UPDATE/DELETE: os ficheiros não se substituem em silêncio (nova versão = novo ficheiro).


-- ===== 00041_calculo_tarifas.sql =====
-- =====================================================================
-- Elolog · 0004 · Cálculo de preços NO SERVIDOR
-- Depende de 0001, 0002 e 0003. Replica a lógica do front-end
-- (window.elologFindActiveTariff em js/prestador/financeiro.js e atualizarPrestadoresCliente()
--  em js/cliente/simulacao.js), mas o cliente nunca lê as tarifas:
-- recebe apenas o total por prestador.
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- =====================================================================
create extension if not exists unaccent with schema extensions;
-- Idempotente: se uma versão anterior da 0003 já foi aplicada, remove o acesso direto a tarifas.
drop policy if exists tarifas_clientes on tarifas;
-- ---------- 1. Estimativa guardada na simulação -----------------------
alter table simulacoes add column preco_estimado     numeric(14,2) check (preco_estimado >= 0),
  add column moeda_estimada     char(3), add column tarifa_estimada_id uuid references tarifas(id);
-- Uma tarifa usada numa proposta OU numa estimativa não é alterada retroativamente.
create or replace function private.proteger_tarifa_usada() returns trigger
language plpgsql security definer set search_path = public as $$ begin
  if (exists (select 1 from propostas p where p.tarifa_id = old.id)
      or exists (select 1 from simulacoes s where s.tarifa_estimada_id = old.id)) and (
       (new.aplicacao, new.metodo, new.valor, new.moeda, new.quantidade_minima, new.preco_minimo,
        new.origem, new.destino, new.tipo_carga, new.transporte, new.regras::text) is distinct from
       (old.aplicacao, old.metodo, old.valor, old.moeda, old.quantidade_minima, old.preco_minimo,
        old.origem, old.destino, old.tipo_carga, old.transporte, old.regras::text)) then
    raise exception 'Tarifa já utilizada: crie uma nova versão (a anterior fica inativa).'; end if;
  return new; end $$; -- ---------- 2. Funções internas (não expostas pela API) ---------------
-- Mesma normalização do front-end: aparar, minúsculas, sem acentos.
create function private.norm(p text) returns text
language sql stable set search_path = public, extensions as $$
  select lower(trim(extensions.unaccent(coalesce(p, '')))) $$;
-- No front-end o custo de recolha do cliente é 1 € por km (custoKm = km). Ajustar aqui se mudar.
create function private.custo_recolha_por_km() returns numeric
language sql immutable as $$ select 1.00::numeric $$;
-- Tarifa ativa MAIS ESPECÍFICA para prestador, rota e carga.
-- Critérios iguais a elologFindActiveTariff: estado ativo, datas de validade, origem/destino
-- por correspondência parcial nos dois sentidos, transporte igual (se ambos existirem) e
-- tipo de carga contido no pedido. Ordena por nº de campos preenchidos (origem, destino, carga);
-- desempate (que o front-end deixava à ordem de gravação): versão mais recente.
-- DIFERENÇA: só considera tarifas de aplicação 'carga' (o front-end também podia apanhar 'recolha').
create function private.tarifa_aplicavel(
  p_empresa uuid, p_origem text, p_destino text, p_tipo_carga text, p_transporte text default null
) returns tarifas language sql stable security definer set search_path = public, extensions as $$ select t.*
    from tarifas t where t.empresa_id = p_empresa and t.ativa and t.aplicacao = 'carga'
     and (t.validade_inicio is null or t.validade_inicio <= current_date)
     and (t.validade_fim    is null or t.validade_fim    >= current_date) and (coalesce(t.origem, '') = ''
          or strpos(private.norm(p_origem), private.norm(t.origem)) > 0
          or strpos(private.norm(t.origem), private.norm(p_origem)) > 0) and (coalesce(t.destino, '') = ''
          or strpos(private.norm(p_destino), private.norm(t.destino)) > 0
          or strpos(private.norm(t.destino), private.norm(p_destino)) > 0)
     and (coalesce(t.transporte, '') = '' or coalesce(p_transporte, '') = ''
          or private.norm(t.transporte) = private.norm(p_transporte))
     and (coalesce(t.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = ''
          or strpos(private.norm(p_tipo_carga), private.norm(t.tipo_carga)) > 0)
   order by ((coalesce(t.origem, '')     <> '')::int + (coalesce(t.destino, '')    <> '')::int
           + (coalesce(t.tipo_carga, '') <> '')::int) desc, t.versao desc, t.created_at desc limit 1 $$;
-- Preço da carga com uma tarifa. Fórmulas do front-end:
--   fixo     → valor
--   peso     → maior(peso real, volume × fator volumétrico) × valor   (fator em regras->>'volumetricFactor', por omissão 167)
--   unidade  → quantidade × valor
--   restantes (volume, wm, contentor) → volume m³ × valor
-- e depois aplica o preço mínimo. p_peso_kg é o PESO TOTAL da carga.
create function private.preco_com_tarifa(t tarifas, p_quantidade int, p_peso_kg numeric, p_volume_m3 numeric)
returns numeric language sql immutable as $$ select round(greatest( case t.metodo when 'fixo'    then t.valor
      when 'peso'    then greatest(coalesce(p_peso_kg, 0), coalesce(p_volume_m3, 0)
                                   * coalesce(nullif((t.regras ->> 'volumetricFactor')::numeric, 0), 167)) * t.valor
      when 'unidade' then coalesce(p_quantidade, 0) * t.valor
      else                coalesce(p_volume_m3, 0) * t.valor end, t.preco_minimo), 2) $$;
revoke execute on function private.norm(text), private.custo_recolha_por_km(),
  private.tarifa_aplicavel(uuid, text, text, text, text),
  private.preco_com_tarifa(tarifas, int, numeric, numeric) from public;
-- ---------- 3. Colunas que o cliente pode escrever na simulação -------
-- O preço estimado, o estado e o destinatário só mudam por funções do servidor.
revoke insert, update on simulacoes from authenticated;
grant  insert (cliente_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3,
               volumes, recolha_na_morada, recolha_distancia_km) on simulacoes to authenticated;
grant  update (origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3,
               volumes, recolha_na_morada, recolha_distancia_km) on simulacoes to authenticated;
-- Depois de enviada, os dados já não se editam (invalidariam a estimativa): cancela-se e cria-se outra.
drop policy sim_cliente_editar on simulacoes;
create policy sim_cliente_editar on simulacoes for update to authenticated
  using (cliente_id = auth.uid() and estado = 'rascunho')
  with check (cliente_id = auth.uid() and estado = 'rascunho');
-- ---------- 4. Pré-visualização: um total por prestador disponível ----
-- Não devolve tarifas nem fórmulas, só o total (já com recolha).
create function public.calcular_propostas( p_origem text, p_destino text, p_tipo_carga text default null,
  p_quantidade int default 0, p_peso_kg numeric default 0, p_volume_m3 numeric default 0,
  p_recolha_km numeric default 0, p_transporte text default null
) returns table (prestador_id uuid, prestador_nome text, disponivel boolean, preco_total numeric, moeda char(3))
language plpgsql stable security definer set search_path = public as $$ declare r   record; v_t tarifas; begin
  if not exists (select 1 from clientes c where c.id = auth.uid()) then
    raise exception 'Apenas clientes autenticados.'; end if;
  if coalesce(trim(p_origem), '') = '' or coalesce(trim(p_destino), '') = '' then
    raise exception 'Indique origem e destino.'; end if;
  if coalesce(p_quantidade, 0) < 0 or coalesce(p_peso_kg, 0) < 0
     or coalesce(p_volume_m3, 0) < 0 or coalesce(p_recolha_km, 0) < 0 then
    raise exception 'Valores negativos não são permitidos.'; end if;
  for r in select e.id, e.nome from empresas_disponiveis e order by e.nome loop
    v_t := private.tarifa_aplicavel(r.id, p_origem, p_destino, p_tipo_carga, p_transporte);
    prestador_id   := r.id; prestador_nome := r.nome; if v_t.id is null then
      disponivel := false;  preco_total := null;  moeda := null;      -- "A aguardar tarifa"
    else disponivel  := true;
      preco_total := private.preco_com_tarifa(v_t, p_quantidade, p_peso_kg, p_volume_m3)
                     + round(coalesce(p_recolha_km, 0) * private.custo_recolha_por_km(), 2);
      moeda       := v_t.moeda; end if; return next; end loop; end $$;
-- ---------- 5. Envio explícito ao prestador (fixa a estimativa) -------
create function public.enviar_simulacao(p_simulacao uuid, p_empresa uuid) returns simulacoes
language plpgsql security definer set search_path = public as $$ declare v_sim   simulacoes; v_t     tarifas;
  v_preco numeric; begin select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.cliente_id is distinct from auth.uid() then raise exception 'Simulação inexistente.';
  end if; if v_sim.estado <> 'rascunho' then raise exception 'A simulação já foi enviada (%).', v_sim.estado;
  end if; if not exists (select 1 from empresas_disponiveis e where e.id = p_empresa) then
    raise exception 'Este prestador não está disponível.'; end if;
  v_t := private.tarifa_aplicavel(p_empresa, v_sim.origem, v_sim.destino, v_sim.tipo_carga);
  if v_t.id is null then raise exception 'O prestador ainda não configurou tarifa para esta rota.'; end if;
  v_preco := private.preco_com_tarifa(v_t, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3)
             + case when v_sim.recolha_na_morada
                    then round(coalesce(v_sim.recolha_distancia_km, 0) * private.custo_recolha_por_km(), 2)
                    else 0 end; update simulacoes
     set estado = 'enviada', empresa_destinatario_id = p_empresa, enviada_em = now(),
         preco_estimado = v_preco, moeda_estimada = v_t.moeda, tarifa_estimada_id = v_t.id where id = v_sim.id
   returning * into v_sim;
  insert into notificacoes (empresa_id, tipo, titulo, referencia_tabela, referencia_id)
    values (p_empresa, 'nova_simulacao', 'Nova simulação recebida', 'simulacoes', v_sim.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (p_empresa, auth.uid(), 'cliente', 'enviar_simulacao', 'simulacoes', v_sim.id::text,
            jsonb_build_object('preco_estimado', v_preco, 'tarifa', v_t.id)); return v_sim; end $$;
-- ---------- 6. Cancelar (rascunho, enviada ou respondida) -------------
create function public.cancelar_simulacao(p_simulacao uuid) returns simulacoes
language plpgsql security definer set search_path = public as $$ declare v_sim simulacoes; begin
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.cliente_id is distinct from auth.uid() then raise exception 'Simulação inexistente.';
  end if; if v_sim.estado not in ('rascunho', 'enviada', 'respondida') then
    raise exception 'Não é possível cancelar uma simulação (%).', v_sim.estado; end if;
  update propostas set estado = 'cancelada', respondida_em = now()
   where simulacao_id = v_sim.id and estado = 'enviada';
  update simulacoes set estado = 'cancelada' where id = v_sim.id returning * into v_sim; return v_sim; end $$;
-- ---------- 7. Execução -----------------------------------------------
revoke execute on function public.calcular_propostas(text, text, text, int, numeric, numeric, numeric, text) from public, anon;
revoke execute on function public.enviar_simulacao(uuid, uuid) from public, anon;
revoke execute on function public.cancelar_simulacao(uuid) from public, anon;
grant  execute on function public.calcular_propostas(text, text, text, int, numeric, numeric, numeric, text) to authenticated;
grant  execute on function public.enviar_simulacao(uuid, uuid) to authenticated;
grant  execute on function public.cancelar_simulacao(uuid) to authenticated;
commit;

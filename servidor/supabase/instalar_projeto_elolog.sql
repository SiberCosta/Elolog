-- Elolog — instalação completa no projeto «Elolog» (wcggcpdiswbzrdpwgdpb).
-- Cole TUDO no Supabase › SQL Editor › New query e carregue em Run. Corre numa só transação: ou fica tudo instalado, ou nada muda.
-- As partes 00011–00013 (tabelas base) já foram instaladas. Este ficheiro instala de 00021 em diante e agenda as tarefas automáticas.
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


-- ===== 00051_prestador_parte1.sql =====
-- =====================================================================
-- Elolog · 0005 · Ligação do prestador
-- Depende de 0001–0004.
--   1. Dados de envio/entrega (remetente, destinatário, morada de recolha, data prevista)
--   2. Login em dois níveis NO SERVIDOR: validar_empresa() + abrir_sessao_empresa()
--   3. Sessão de empresa exigida pelas políticas RLS (minha_empresa / meu_papel)
--   4. aceitar_simulacao() e recusar_simulacao() do prestador
--   5. transitar_encomenda() atualizada para exigir a sessão de empresa
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- =====================================================================
create extension if not exists pgcrypto with schema extensions;
-- ---------- 1. Dados necessários para o prestador operar ---------------
-- O prestador precisa de saber onde recolher, a quem entregar e quando.
alter table simulacoes add column data_prevista   date, add column morada_recolha  text,
  add column remetente       jsonb not null default '{}' check (jsonb_typeof(remetente) = 'object'),
  add column destinatario    jsonb not null default '{}' check (jsonb_typeof(destinatario) = 'object'),
  add column valor_declarado numeric(14,2) check (valor_declarado >= 0), add column observacoes     text;
alter table encomendas add column morada_recolha  text,
  add column remetente       jsonb not null default '{}' check (jsonb_typeof(remetente) = 'object'),
  add column destinatario    jsonb not null default '{}' check (jsonb_typeof(destinatario) = 'object'),
  add column valor_declarado numeric(14,2) check (valor_declarado >= 0), add column observacoes     text;
-- O cliente pode escrever estes campos na simulação (rascunho). O resto continua protegido (0004).
grant insert (data_prevista, morada_recolha, remetente, destinatario, valor_declarado, observacoes)
  on simulacoes to authenticated;
grant update (data_prevista, morada_recolha, remetente, destinatario, valor_declarado, observacoes)
  on simulacoes to authenticated; -- O prestador pode corrigir estes campos na encomenda.
grant update (morada_recolha, destinatario, valor_declarado, observacoes) on encomendas to authenticated;
-- ---------- 2. Limitação de tentativas do 1.º nível (empresa) ----------
alter table tentativas_gate add column ultima_falha timestamptz;
-- Valida nome + NIF + palavra-passe da empresa. Devolve o id da empresa ou NULL.
-- Conta as falhas (por empresa) e bloqueia 15 min após 5 falhas seguidas.
-- IMPORTANTE: nunca lança exceção por credenciais erradas, porque a exceção desfaria o contador.
-- Quem chama devolve o resultado como valor ("ok = false"). Uma empresa inexistente não gera linhas.
create function private.verificar_empresa(p_nome text, p_nif text, p_senha text, out p_empresa uuid, out p_mensagem text)
language plpgsql security definer set search_path = public, extensions as $$ declare v_emp  empresas;
  v_hash text; v_t    tentativas_gate; begin p_empresa := null;
  p_mensagem := 'Os dados de autenticação da empresa estão incorretos.';
  if coalesce(trim(p_nome), '') = '' or coalesce(trim(p_nif), '') = '' or coalesce(p_senha, '') = '' then
    return; end if; select e.* into v_emp from empresas e
   where private.norm(e.nif) = private.norm(p_nif) and private.norm(e.nome) = private.norm(p_nome);
  if not found then return; end if;       -- mesma mensagem para empresa inexistente
  select * into v_t from tentativas_gate where chave = v_emp.id::text;
  if found and v_t.bloqueado_ate is not null and v_t.bloqueado_ate > now() then
    p_mensagem := 'Demasiadas tentativas. Tente novamente dentro de alguns minutos.'; return; end if;
  select s.segredo_hash into v_hash from empresa_segredos s where s.empresa_id = v_emp.id;
  if v_hash is null or extensions.crypt(p_senha, v_hash) <> v_hash then
    insert into tentativas_gate (chave, falhas, ultima_falha) values (v_emp.id::text, 1, now())
    on conflict (chave) do update
      set falhas = case when tentativas_gate.ultima_falha < now() - interval '15 minutes'
                        then 1 else tentativas_gate.falhas + 1 end, ultima_falha = now(), bloqueado_ate = case
            when (case when tentativas_gate.ultima_falha < now() - interval '15 minutes'
                       then 1 else tentativas_gate.falhas + 1 end) >= 5
            then now() + interval '15 minutes' else null end; return; end if;
  if v_emp.estado = 'pendente'  then p_mensagem := 'O registo da empresa aguarda validação da administração.'; return; end if;
  if v_emp.estado <> 'aprovada' then p_mensagem := 'A empresa não está autorizada a aceder à plataforma.'; return; end if;
  delete from tentativas_gate where chave = v_emp.id::text; p_empresa := v_emp.id; p_mensagem := null; end $$;
revoke execute on function private.verificar_empresa(text, text, text) from public;
-- Passo 1 do login (antes de existir sessão): confirma a empresa. Chamável sem autenticação.
create function public.validar_empresa(p_nome text, p_nif text, p_senha text)
returns table (ok boolean, empresa_id uuid, empresa_nome text, mensagem text)
language plpgsql security definer set search_path = public as $$ declare r record; begin
  select * into r from private.verificar_empresa(p_nome, p_nif, p_senha); if r.p_empresa is null then
    return query select false, null::uuid, null::text, r.p_mensagem; else
    return query select true, e.id, e.nome, null::text from empresas e where e.id = r.p_empresa; end if;
end $$; revoke execute on function public.validar_empresa(text, text, text) from public;
grant  execute on function public.validar_empresa(text, text, text) to anon, authenticated;
-- ---------- 3. Sessão de empresa (2.º nível, aplicado pelo servidor) ---
-- Sem esta sessão válida, minha_empresa() e meu_papel() devolvem NULL e as políticas RLS
-- do prestador não deixam passar nada, mesmo com e-mail e palavra-passe de funcionário corretos.
create table sessoes_empresa ( user_id    uuid primary key references auth.users(id) on delete cascade,
  empresa_id uuid not null references empresas(id) on delete cascade, valida_ate timestamptz not null,
  created_at timestamptz not null default now() );
alter table sessoes_empresa enable row level security;   -- sem políticas: só funções definer
create or replace function private.minha_empresa() returns uuid
language sql stable security definer set search_path = public as $$ select f.empresa_id from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = auth.uid() and f.ativo $$;
create or replace function private.meu_papel() returns papel_funcionario
language sql stable security definer set search_path = public as $$ select f.papel from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = auth.uid() and f.ativo $$;
-- Passo 2: depois do login do funcionário (Supabase Auth), repete a empresa e abre a sessão (12 h).
create function public.abrir_sessao_empresa(p_nome text, p_nif text, p_senha text)
returns table (ok boolean, mensagem text, empresa_id uuid, empresa_nome text, papel papel_funcionario,
               funcionario_nome text, email text, valida_ate timestamptz)
language plpgsql security definer set search_path = public as $$ declare r   record; v_f funcionarios;
  v_validade timestamptz := now() + interval '12 hours'; begin
  select * into v_f from funcionarios where id = auth.uid() and ativo; if not found then
    return query select false, 'Esta conta não é de um funcionário ativo de uma empresa.', null::uuid, null::text,
                        null::papel_funcionario, null::text, null::text, null::timestamptz; return; end if;
  select * into r from private.verificar_empresa(p_nome, p_nif, p_senha); if r.p_empresa is null then
    return query select false, r.p_mensagem, null::uuid, null::text, null::papel_funcionario,
                        null::text, null::text, null::timestamptz; return; end if;
  if r.p_empresa <> v_f.empresa_id then
    return query select false, 'Esta conta de funcionário não pertence à empresa indicada.', null::uuid, null::text,
                        null::papel_funcionario, null::text, null::text, null::timestamptz; return; end if;
  insert into sessoes_empresa (user_id, empresa_id, valida_ate) values (auth.uid(), v_f.empresa_id, v_validade)
  on conflict (user_id) do update set empresa_id = excluded.empresa_id, valida_ate = excluded.valida_ate;
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id)
    values (v_f.empresa_id, auth.uid(), v_f.papel::text, 'abrir_sessao_empresa', 'funcionarios', auth.uid()::text);
  return query select true, null::text, e.id, e.nome, v_f.papel, v_f.nome, v_f.email, v_validade
                 from empresas e where e.id = v_f.empresa_id; end $$;
revoke execute on function public.abrir_sessao_empresa(text, text, text) from public, anon;
grant  execute on function public.abrir_sessao_empresa(text, text, text) to authenticated;
create function public.terminar_sessao_empresa() returns void
language sql security definer set search_path = public as $$
  delete from sessoes_empresa where user_id = auth.uid() $$;
revoke execute on function public.terminar_sessao_empresa() from public, anon;
grant  execute on function public.terminar_sessao_empresa() to authenticated;
-- A interface pergunta isto de tempos a tempos: se a sessão de empresa expirou, pede novo login.
create function public.sessao_empresa_ativa() returns boolean
language sql stable security definer set search_path = public as $$ select private.minha_empresa() is not null
$$; revoke execute on function public.sessao_empresa_ativa() from public, anon;
grant  execute on function public.sessao_empresa_ativa() to authenticated;
-- ---------- 4. Prestador aceita ou recusa a simulação ------------------
-- Aceitar = criar a proposta (aceite, ao preço estimado pelo servidor) e a encomenda em "aprovação".
create function public.aceitar_simulacao(p_simulacao uuid) returns encomendas
language plpgsql security definer set search_path = public as $$ declare v_sim simulacoes; v_enc encomendas;
  v_prop uuid; begin
  if private.minha_empresa() is null or not private.papel_em(array['admin_empresa','operador']) then
    raise exception 'Sem permissão para aceitar simulações.'; end if;
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.empresa_destinatario_id is distinct from private.minha_empresa() then
    raise exception 'Simulação inexistente.'; end if; if v_sim.estado not in ('enviada', 'respondida') then
    raise exception 'A simulação já não está disponível (%).', v_sim.estado; end if;
  if v_sim.preco_estimado is null then raise exception 'A simulação não tem preço calculado.'; end if;
  -- propostas ainda pendentes deste prestador para esta simulação deixam de valer
  update propostas set estado = 'cancelada', respondida_em = now()
   where simulacao_id = v_sim.id and empresa_id = v_sim.empresa_destinatario_id and estado = 'enviada';
  insert into propostas (simulacao_id, empresa_id, tarifa_id, preco, moeda, estado, mensagem, criado_por, respondida_em)
  values (v_sim.id, v_sim.empresa_destinatario_id, v_sim.tarifa_estimada_id, v_sim.preco_estimado,
          coalesce(v_sim.moeda_estimada, 'EUR'), 'aceite', 'Aceite ao preço calculado pelas tarifas do prestador.',
          auth.uid(), now()) returning id into v_prop;
  update simulacoes set estado = 'convertida' where id = v_sim.id;
  insert into encomendas (empresa_id, cliente_id, simulacao_id, proposta_id, origem, destino, tipo_carga, descricao,
                          quantidade, peso_kg, volume_m3, volumes, preco_total, moeda, estado, data_prevista,
                          morada_recolha, remetente, destinatario, valor_declarado, observacoes, criado_por)
  values (v_sim.empresa_destinatario_id, v_sim.cliente_id, v_sim.id, v_prop, v_sim.origem, v_sim.destino,
          v_sim.tipo_carga, v_sim.descricao, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3, v_sim.volumes,
          v_sim.preco_estimado, coalesce(v_sim.moeda_estimada, 'EUR'), 'aprovacao', v_sim.data_prevista,
          v_sim.morada_recolha, v_sim.remetente, v_sim.destinatario, v_sim.valor_declarado, v_sim.observacoes,
          auth.uid()) returning * into v_enc;
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id)
    values (v_enc.id, v_enc.empresa_id, null, 'aprovacao', 'Simulação aceite pelo prestador', auth.uid());
  insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v_sim.cliente_id, 'simulacao_aceite', 'O prestador aceitou o seu pedido',
            'Encomenda ' || v_enc.codigo || ' criada e a aguardar aprovação operacional.', 'encomendas', v_enc.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_enc.empresa_id, auth.uid(), private.meu_papel()::text, 'aceitar_simulacao', 'simulacoes', v_sim.id::text,
            jsonb_build_object('encomenda', v_enc.codigo, 'preco', v_sim.preco_estimado)); return v_enc;
end $$;


-- ===== 00052_prestador_parte2.sql =====
create function public.recusar_simulacao(p_simulacao uuid, p_motivo text) returns simulacoes
language plpgsql security definer set search_path = public as $$
declare v_sim simulacoes;
begin
  if private.minha_empresa() is null or not private.papel_em(array['admin_empresa','operador']) then
    raise exception 'Sem permissão para recusar simulações.';
  end if;
  if length(trim(coalesce(p_motivo, ''))) < 3 then
    raise exception 'Indique o motivo da recusa.';
  end if;
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.empresa_destinatario_id is distinct from private.minha_empresa() then
    raise exception 'Simulação inexistente.';
  end if;
  if v_sim.estado not in ('enviada', 'respondida') then
    raise exception 'A simulação já não está disponível (%).', v_sim.estado;
  end if;

  update propostas set estado = 'cancelada', respondida_em = now()
   where simulacao_id = v_sim.id and estado = 'enviada';
  update simulacoes set estado = 'cancelada' where id = v_sim.id returning * into v_sim;

  insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v_sim.cliente_id, 'simulacao_recusada', 'O prestador não pôde aceitar o seu pedido',
            trim(p_motivo), 'simulacoes', v_sim.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, motivo)
    values (v_sim.empresa_destinatario_id, auth.uid(), private.meu_papel()::text, 'recusar_simulacao',
            'simulacoes', v_sim.id::text, trim(p_motivo));
  return v_sim;
end $$;

revoke execute on function public.aceitar_simulacao(uuid), public.recusar_simulacao(uuid, text) from public, anon;
grant  execute on function public.aceitar_simulacao(uuid), public.recusar_simulacao(uuid, text) to authenticated;

-- ---------- 5. transitar_encomenda exige a sessão de empresa -----------
-- Mesma função da 0002, com uma alteração: o papel e a empresa vêm de meu_papel()/minha_empresa(),
-- que só devolvem valores com sessão de empresa válida.
create or replace function public.transitar_encomenda(
  p_encomenda uuid, p_para estado_encomenda, p_nota text default null
) returns encomendas
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

  if p_para = 'em_transito' and not exists (
       select 1 from manifesto_encomendas me
         join manifestos m on m.id = me.manifesto_id
        where me.encomenda_id = v_enc.id and m.estado in ('confirmado','em_transito')) then
    v_falta := v_falta || 'manifesto confirmado';
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

  -- o cliente é avisado de cada mudança de estado
  if v_enc.cliente_id is not null then
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (v_enc.cliente_id, 'estado_encomenda', 'A sua encomenda ' || v_enc.codigo || ' mudou de estado',
              p_para::text, 'encomendas', v_enc.id);
  end if;

  select * into v_enc from encomendas where id = p_encomenda;
  return v_enc;
end $$;
revoke execute on function public.transitar_encomenda(uuid, estado_encomenda, text) from public, anon;
grant  execute on function public.transitar_encomenda(uuid, estado_encomenda, text) to authenticated;


-- ===== 00061_funcoes_servico_parte1.sql =====
-- =====================================================================
-- Elolog · 0006 · Apoio às Edge Functions (registar-prestador, gerir-funcionarios)
-- Depende de 0001–0005.
--   1. Colunas do funcionário que a interface já recolhe (telefone, carta de condução)
--   2. Funções "servico_*": só o service_role as executa (as Edge Functions); a API pública não
--   3. Fecha atalhos: o administrador deixa de editar "funcionarios" diretamente pela API
--      (tudo passa pela Edge Function, que também bane/desbane o utilizador de autenticação)
--   4. Alinha o nome da permissão de pré-pagamento no terreno com o da interface
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- =====================================================================
-- ---------- 1. Colunas ------------------------------------------------
alter table funcionarios add column telefone         text, add column licenca_conducao text;
-- ---------- 2. Permissões: nomes usados pela interface ----------------
-- A interface usa "confirm_field_prepayment" (e não "receive_cash") para autorizar o operador
-- de terreno a registar numerário. A política passa a usar o nome real.
drop policy if exists pag_terreno_criar on pagamentos;
create policy pag_terreno_criar on pagamentos for insert to authenticated
  with check (empresa_id = private.minha_empresa() and registado_por = auth.uid()
              and private.papel_em(array['operador_terreno'])
              and numerario_terreno and private.tem_permissao('confirm_field_prepayment')
              and estado = 'pendente' and not reconciliado
              and exists (select 1 from encomendas en where en.id = encomenda_id));
-- Lista fechada de permissões que um funcionário pode ter (a Edge Function e esta função validam).
create function private.permissoes_validas(p text[]) returns boolean language sql immutable as $$
  select p <@ array['view_assigned_jobs','update_assigned_jobs','capture_load','register_signature',
                    'create_incident','confirm_field_prepayment','delete_order_history']::text[] $$;
-- ---------- 3. Atalho fechado: edição direta de funcionários ----------
-- Sem isto, um administrador podia mudar "ativo" ou "papel" pela API e contornar as regras
-- (último administrador, ban no utilizador de autenticação, fecho das sessões de empresa).
revoke update on funcionarios from authenticated;
-- ---------- 4. Funções de serviço -------------------------------------
-- Todas: security definer, só service_role. (A API pública não consegue chamá-las.)
-- 4.1 Limite de pedidos por chave (janela deslizante). Devolve false quando excedido.
-- A chave deve chegar já "hasheada" pela Edge Function (sem e-mails nem IPs em claro).
create function public.servico_limite(p_chave text, p_max int, p_janela_min int) returns boolean
language plpgsql security definer set search_path = public as $$ declare v_falhas int; begin
  if coalesce(p_chave, '') = '' or p_max < 1 or p_janela_min < 1 then
    raise exception 'Parâmetros de limite inválidos.'; end if;
  delete from tentativas_gate where ultima_falha < now() - interval '2 days';
  insert into tentativas_gate (chave, falhas, ultima_falha) values (p_chave, 1, now())
  on conflict (chave) do update
    set falhas = case when tentativas_gate.ultima_falha < now() - make_interval(mins => p_janela_min)
                      then 1 else tentativas_gate.falhas + 1 end, ultima_falha = now()
  returning falhas into v_falhas; return v_falhas <= p_max; end $$;
-- 4.2 Já existe um utilizador de autenticação com este e-mail?
create function public.servico_utilizador_existe(p_email text) returns boolean
language sql stable security definer set search_path = public, auth as $$
  select exists (select 1 from auth.users u where lower(u.email) = lower(trim(p_email))) $$;
-- 4.3 Registo de prestador (atómico): empresa pendente + segredo + subscrição pendente + 1.º administrador.
-- O utilizador de autenticação já foi criado pela Edge Function (p_user).
-- A palavra-passe da empresa é cifrada AQUI (pgcrypto), com o mesmo algoritmo que validar_empresa() verifica.
create function public.servico_registar_prestador(
  p_user uuid, p_nome text, p_nif text, p_email text, p_telefone text, p_senha_empresa text,
  p_admin_nome text, p_admin_email text, p_plano text, p_metodo text, p_referencia text ) returns uuid
language plpgsql security definer set search_path = public, extensions as $$ declare v_plano planos;
  v_emp   uuid; begin
  if length(coalesce(p_senha_empresa, '')) < 8 then raise exception 'A palavra-passe da empresa é demasiado curta.'; end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'Utilizador de autenticação inexistente.'; end if;
  select * into v_plano from planos
   where lower(nome) = lower(trim(p_plano)) and ativo and not personalizado and preco_mensal > 0;
  if not found then raise exception 'O plano escolhido não está disponível.'; end if;
  if exists (select 1 from empresas where private.norm(nif) = private.norm(p_nif)) then
    raise exception 'Já existe uma empresa registada com este NIF.' using errcode = 'unique_violation';
  end if; insert into empresas (nome, nif, email, telefone, estado)
    values (trim(p_nome), trim(p_nif), lower(trim(p_email)), nullif(trim(p_telefone), ''), 'pendente')
    returning id into v_emp; insert into empresa_segredos (empresa_id, segredo_hash)
    values (v_emp, extensions.crypt(p_senha_empresa, extensions.gen_salt('bf')));
  -- O pagamento só é DECLARADO aqui (método e referência). pago_em fica nulo até a administração o confirmar;
  -- decidir_empresa() recusa aprovar uma subscrição paga sem confirmação.
  insert into subscricoes (empresa_id, plano_id, estado, periodicidade, valor, metodo_pagamento, referencia)
    values (v_emp, v_plano.id, 'pendente', 'mensal', v_plano.preco_mensal,
            nullif(trim(p_metodo), ''), nullif(trim(p_referencia), ''));
  insert into funcionarios (id, empresa_id, nome, email, papel)
    values (p_user, v_emp, trim(p_admin_nome), lower(trim(p_admin_email)), 'admin_empresa');
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_emp, p_user, 'admin_empresa', 'registo_prestador', 'empresas', v_emp::text,
            jsonb_build_object('plano', v_plano.nome, 'termos_aceites', true, 'aceites_em', now()));
  return v_emp; end $$;
-- 4.4 Empresa do utilizador, se for ADMINISTRADOR ativo de empresa aprovada com sessão de empresa válida.
-- É a mesma regra do RLS (minha_empresa/meu_papel), avaliada para um utilizador concreto.
create function public.servico_admin_empresa(p_user uuid) returns uuid
language sql stable security definer set search_path = public as $$ select f.empresa_id from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = p_user and f.ativo and f.papel = 'admin_empresa' $$;
-- 4.5 Limite de funcionários ativos do plano (null = ilimitado). Levanta exceção se estiver cheio.
create function public.servico_verificar_limite_funcionarios(p_empresa uuid) returns void
language plpgsql security definer set search_path = public as $$ declare v_max int; v_ativos int; begin
  select pl.max_funcionarios into v_max from subscricoes s join planos pl on pl.id = s.plano_id
   where s.empresa_id = p_empresa and s.estado = 'ativa';
  select count(*) into v_ativos from funcionarios where empresa_id = p_empresa and ativo;
  if v_max is not null and v_ativos >= v_max then
    raise exception 'O plano da empresa permite % funcionários ativos e já estão todos em uso.', v_max;
  end if; end $$; -- 4.6 Criar o registo de funcionário (o utilizador de autenticação já existe: p_user).
create function public.servico_criar_funcionario(
  p_empresa uuid, p_user uuid, p_autor uuid, p_nome text, p_email text, p_papel papel_funcionario,
  p_numero text, p_veiculo text, p_telefone text, p_licenca text, p_permissoes text[], p_ativo boolean
) returns funcionarios language plpgsql security definer set search_path = public as $$
declare v_f funcionarios; begin
  perform 1 from empresas where id = p_empresa for update;      -- serializa criações simultâneas
  if not found then raise exception 'Empresa inexistente.'; end if;
  if p_ativo then perform public.servico_verificar_limite_funcionarios(p_empresa); end if;
  if not private.permissoes_validas(coalesce(p_permissoes, '{}')) then raise exception 'Permissão desconhecida.'; end if;
  insert into funcionarios (id, empresa_id, nome, email, papel, ativo, numero_interno, veiculo_habitual,
                            telefone, licenca_conducao, permissoes)
  values (p_user, p_empresa, trim(p_nome), lower(trim(p_email)), p_papel, p_ativo, nullif(trim(p_numero), ''),
          nullif(trim(p_veiculo), ''), nullif(trim(p_telefone), ''), nullif(trim(p_licenca), ''),
          coalesce(p_permissoes, '{}')) returning * into v_f;
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (p_empresa, p_autor, 'admin_empresa', 'criar_funcionario', 'funcionarios', p_user::text,
            jsonb_build_object('email', v_f.email, 'papel', p_papel, 'ativo', p_ativo)); return v_f; end $$;
-- 4.7 Ler um funcionário DA empresa (nunca de outra).
create function public.servico_obter_funcionario(p_empresa uuid, p_alvo uuid) returns funcionarios
language sql stable security definer set search_path = public as $$
  select * from funcionarios where id = p_alvo and empresa_id = p_empresa $$;
-- 4.8 Regras comuns a desativar/rebaixar/eliminar: o alvo é da empresa, não é o próprio, e não é o último
-- administrador ativo. Devolve o registo do alvo.
create function private.validar_alteracao_acesso(p_empresa uuid, p_alvo uuid, p_autor uuid, p_remove_admin boolean)
returns funcionarios language plpgsql security definer set search_path = public as $$
declare v_f funcionarios; begin
  select * into v_f from funcionarios where id = p_alvo and empresa_id = p_empresa for update;
  if not found then raise exception 'Funcionário não encontrado nesta empresa.'; end if;
  if p_remove_admin then
    if p_alvo = p_autor then raise exception 'Não pode retirar o seu próprio acesso de administrador.'; end if;
    if v_f.papel = 'admin_empresa' and v_f.ativo and not exists ( select 1 from funcionarios o
          where o.empresa_id = p_empresa and o.id <> p_alvo and o.papel = 'admin_empresa' and o.ativo) then
      raise exception 'A empresa tem de manter pelo menos um administrador ativo.'; end if; end if;
  return v_f; end $$;
-- 4.9 Atualizar um funcionário. p_alt é um objeto JSON; só as chaves presentes são alteradas.
-- Chaves: nome, papel, ativo, numero_interno, veiculo_habitual, telefone, licenca_conducao, permissoes.
create function public.servico_atualizar_funcionario(p_empresa uuid, p_alvo uuid, p_autor uuid, p_alt jsonb)
returns funcionarios language plpgsql security definer set search_path = public as $$ declare
  v_old funcionarios; v_new funcionarios; v_papel papel_funcionario; v_ativo boolean; v_perm text[];
  v_tira_acesso boolean; begin
  if jsonb_typeof(p_alt) is distinct from 'object' then raise exception 'Alterações inválidas.'; end if;
  v_old := (select f from funcionarios f where f.id = p_alvo and f.empresa_id = p_empresa);
  if v_old.id is null then raise exception 'Funcionário não encontrado nesta empresa.'; end if;
  v_papel := coalesce((p_alt ->> 'papel')::papel_funcionario, v_old.papel);
  v_ativo := coalesce((p_alt ->> 'ativo')::boolean, v_old.ativo); v_perm  := case when p_alt ? 'permissoes'
                  then array(select jsonb_array_elements_text(p_alt -> 'permissoes')) else v_old.permissoes end;
  if not private.permissoes_validas(coalesce(v_perm, '{}')) then raise exception 'Permissão desconhecida.'; end if;
  v_tira_acesso := (v_old.ativo and not v_ativo) or (v_old.papel = 'admin_empresa' and v_papel <> 'admin_empresa');
  if v_tira_acesso then perform private.validar_alteracao_acesso(p_empresa, p_alvo, p_autor, true); end if;
  if v_ativo and not v_old.ativo then perform public.servico_verificar_limite_funcionarios(p_empresa); end if;
  update funcionarios set nome             = coalesce(nullif(trim(p_alt ->> 'nome'), ''), nome),
      papel            = v_papel, ativo            = v_ativo,
      numero_interno   = case when p_alt ? 'numero_interno'   then nullif(trim(p_alt ->> 'numero_interno'), '')   else numero_interno end,
      veiculo_habitual = case when p_alt ? 'veiculo_habitual' then nullif(trim(p_alt ->> 'veiculo_habitual'), '') else veiculo_habitual end,
      telefone         = case when p_alt ? 'telefone'         then nullif(trim(p_alt ->> 'telefone'), '')         else telefone end,
      licenca_conducao = case when p_alt ? 'licenca_conducao' then nullif(trim(p_alt ->> 'licenca_conducao'), '') else licenca_conducao end,
      permissoes       = coalesce(v_perm, '{}') where id = p_alvo and empresa_id = p_empresa
   returning * into v_new;
  -- perder acesso ou mudar de função fecha logo a sessão de empresa (obriga a novo login)
  if v_tira_acesso or v_new.papel is distinct from v_old.papel then
    delete from sessoes_empresa where user_id = p_alvo; end if;
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, antes, depois)
    values (p_empresa, p_autor, 'admin_empresa', 'atualizar_funcionario', 'funcionarios', p_alvo::text,
            jsonb_build_object('papel', v_old.papel, 'ativo', v_old.ativo, 'permissoes', v_old.permissoes),
            jsonb_build_object('papel', v_new.papel, 'ativo', v_new.ativo, 'permissoes', v_new.permissoes));
  return v_new; end $$;


-- ===== 00062_funcoes_servico_parte2.sql =====
-- 4.10 Antes de eliminar o utilizador de autenticação: valida as regras e fecha as sessões de empresa.
create function public.servico_preparar_remocao(p_empresa uuid, p_alvo uuid, p_autor uuid) returns funcionarios
language plpgsql security definer set search_path = public as $$
declare v_f funcionarios;
begin
  v_f := private.validar_alteracao_acesso(p_empresa, p_alvo, p_autor, true);
  delete from sessoes_empresa where user_id = p_alvo;
  return v_f;
end $$;

-- 4.11 Registo de auditoria feito pela Edge Function (repor palavra-passe, eliminar, arquivar...).
create function public.servico_auditar(p_empresa uuid, p_user uuid, p_acao text, p_entidade_id text, p_depois jsonb)
returns void
language sql security definer set search_path = public as $$
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
  values (p_empresa, p_user, 'admin_empresa', p_acao, 'funcionarios', p_entidade_id, coalesce(p_depois, '{}'::jsonb))
$$;

-- 4.12 Fechar as sessões de empresa de um funcionário (ex.: depois de repor a palavra-passe).
create function public.servico_encerrar_sessoes(p_alvo uuid) returns void
language sql security definer set search_path = public as $$
  delete from sessoes_empresa where user_id = p_alvo
$$;

-- ---------- 5. Execução: só o service_role ---------------------------
revoke execute on function
  public.servico_limite(text, int, int),
  public.servico_utilizador_existe(text),
  public.servico_registar_prestador(uuid, text, text, text, text, text, text, text, text, text, text),
  public.servico_admin_empresa(uuid),
  public.servico_verificar_limite_funcionarios(uuid),
  public.servico_criar_funcionario(uuid, uuid, uuid, text, text, papel_funcionario, text, text, text, text, text[], boolean),
  public.servico_obter_funcionario(uuid, uuid),
  public.servico_atualizar_funcionario(uuid, uuid, uuid, jsonb),
  public.servico_preparar_remocao(uuid, uuid, uuid),
  public.servico_auditar(uuid, uuid, text, text, jsonb),
  public.servico_encerrar_sessoes(uuid)
  from public, anon, authenticated;
grant execute on function
  public.servico_limite(text, int, int),
  public.servico_utilizador_existe(text),
  public.servico_registar_prestador(uuid, text, text, text, text, text, text, text, text, text, text),
  public.servico_admin_empresa(uuid),
  public.servico_verificar_limite_funcionarios(uuid),
  public.servico_criar_funcionario(uuid, uuid, uuid, text, text, papel_funcionario, text, text, text, text, text[], boolean),
  public.servico_obter_funcionario(uuid, uuid),
  public.servico_atualizar_funcionario(uuid, uuid, uuid, jsonb),
  public.servico_preparar_remocao(uuid, uuid, uuid),
  public.servico_auditar(uuid, uuid, text, text, jsonb),
  public.servico_encerrar_sessoes(uuid)
  to service_role;
revoke execute on function private.permissoes_validas(text[]), private.validar_alteracao_acesso(uuid, uuid, uuid, boolean) from public;


-- ===== 00071_admin.sql =====
-- =====================================================================
-- Elolog · 0007 · Painel da administração (aprovar empresas e confirmar pagamentos)
-- Depende de 0001–0006.
--   1. sou_admin_plataforma(): a interface confirma que a conta autenticada é administradora
--   2. decidir_empresa() corrigida: reativar uma empresa suspensa também retoma a subscrição
--      (na 0002 a subscrição ficava "suspensa" para sempre e a empresa nunca voltava a ser listada aos clientes)
--   3. confirmar_pagamento_subscricao(): a administração confirma o pagamento declarado no registo
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- =====================================================================

-- ---------- 1. Quem é administrador da plataforma ----------------------
-- Sem linhas = não é administrador. Só devolve dados do próprio utilizador autenticado.
create function public.sou_admin_plataforma()
returns table (ok boolean, nome text)
language sql stable security definer set search_path = public as $$
  select true, a.nome from administradores_plataforma a where a.user_id = auth.uid()
$$;
revoke execute on function public.sou_admin_plataforma() from public, anon;
grant  execute on function public.sou_admin_plataforma() to authenticated;

-- ---------- 2. Aprovar / recusar / suspender / reativar ----------------
-- Mesma assinatura da 0002 (as permissões de execução mantêm-se). Alterações:
--  * aprovar uma empresa já aprovada, ou recusar/suspender uma que já o está, dá erro claro
--  * recusar ou suspender exige motivo (fica na auditoria e na notificação à empresa)
--  * aprovar ativa a subscrição pendente (já paga) OU retoma a suspensa que tinha sido paga
--    (uma só, a mais recente: há um índice que só permite uma subscrição ativa por empresa)
--  * suspender/recusar fecha de imediato as sessões de empresa (o RLS já corta o acesso, isto é higiene)
--  * a empresa recebe uma notificação com a decisão
create or replace function public.decidir_empresa(p_empresa uuid, p_aprovar boolean, p_motivo text default null)
returns empresas
language plpgsql security definer set search_path = public as $$
declare
  v_emp   empresas;
  v_antes estado_empresa;
  v_sub   uuid;
begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;
  select estado into v_antes from empresas where id = p_empresa for update;
  if not found then raise exception 'Empresa inexistente.'; end if;

  if p_aprovar then
    if v_antes = 'aprovada' then raise exception 'A empresa já está aprovada.'; end if;
    if exists (select 1 from subscricoes s join planos pl on pl.id = s.plano_id
                where s.empresa_id = p_empresa and s.estado = 'pendente'
                  and pl.preco_mensal > 0 and s.pago_em is null) then
      raise exception 'O pagamento da subscrição ainda não foi confirmado.';
    end if;

    update empresas set estado = 'aprovada', aprovada_por = auth.uid(), aprovada_em = now()
     where id = p_empresa returning * into v_emp;

    select s.id into v_sub from subscricoes s
     where s.empresa_id = p_empresa and (s.estado = 'pendente' or (s.estado = 'suspensa' and s.pago_em is not null))
     order by (s.estado = 'pendente') desc, s.created_at desc limit 1;
    if v_sub is not null then
      update subscricoes set estado = 'ativa', confirmado_por = coalesce(confirmado_por, auth.uid()) where id = v_sub;
    end if;
  else
    if v_antes in ('rejeitada', 'suspensa') then raise exception 'A empresa já está %.', v_antes; end if;
    if length(trim(coalesce(p_motivo, ''))) < 3 then raise exception 'Indique o motivo da decisão.'; end if;

    update empresas set estado = case when v_antes = 'pendente' then 'rejeitada'::estado_empresa
                                      else 'suspensa'::estado_empresa end
     where id = p_empresa returning * into v_emp;
    update subscricoes set estado = 'suspensa' where empresa_id = p_empresa and estado in ('pendente', 'ativa');
    delete from sessoes_empresa where empresa_id = p_empresa;
  end if;

  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (p_empresa, case when p_aprovar then 'empresa_aprovada' else 'empresa_recusada' end,
            case when p_aprovar then 'A sua empresa foi autorizada na plataforma'
                 when v_antes = 'pendente' then 'O pedido de registo da empresa foi recusado'
                 else 'A empresa foi suspensa na plataforma' end,
            nullif(trim(coalesce(p_motivo, '')), ''), 'empresas', p_empresa);

  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, antes, depois, motivo)
    values (p_empresa, auth.uid(), 'admin_plataforma',
            case when p_aprovar then 'aprovar_empresa'
                 when v_antes = 'pendente' then 'recusar_empresa' else 'suspender_empresa' end,
            'empresas', p_empresa::text,
            jsonb_build_object('estado', v_antes), jsonb_build_object('estado', v_emp.estado), p_motivo);
  return v_emp;
end $$;

-- ---------- 3. Confirmar o pagamento de uma subscrição ------------------
-- O prestador só DECLARA o pagamento (método e referência) ao registar-se. Aqui a administração confirma que
-- o dinheiro chegou. Efeitos: pago_em e confirmado_por; recibo interno em faturas_plataforma (sem número fiscal:
-- a fatura fiscal sai do software de faturação certificado); se a empresa já está aprovada, a subscrição fica
-- ativa (reativação ou mudança de plano). Para uma empresa ainda pendente, a subscrição ativa-se quando
-- a empresa for aprovada (decidir_empresa).
create function public.confirmar_pagamento_subscricao(p_subscricao uuid, p_nota text default null)
returns subscricoes
language plpgsql security definer set search_path = public as $$
declare
  v_sub  subscricoes;
  v_emp  empresas;
begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;

  select * into v_sub from subscricoes where id = p_subscricao for update;
  if not found then raise exception 'Subscrição inexistente.'; end if;
  if v_sub.pago_em is not null then raise exception 'O pagamento desta subscrição já foi confirmado.'; end if;
  if v_sub.estado = 'cancelada' then raise exception 'A subscrição está cancelada.'; end if;

  select * into v_emp from empresas where id = v_sub.empresa_id for update;

  if v_emp.estado = 'aprovada' and v_sub.estado in ('pendente', 'suspensa') then
    -- só pode haver uma ativa: a anterior (mudança de plano) é encerrada
    update subscricoes set estado = 'cancelada' where empresa_id = v_sub.empresa_id and estado = 'ativa' and id <> v_sub.id;
    update subscricoes set pago_em = now(), confirmado_por = auth.uid(), estado = 'ativa'
     where id = v_sub.id returning * into v_sub;
  else
    update subscricoes set pago_em = now(), confirmado_por = auth.uid()
     where id = v_sub.id returning * into v_sub;
  end if;

  insert into faturas_plataforma (empresa_id, tipo, valor, moeda, estado, criado_por)
    values (v_sub.empresa_id, 'recibo', v_sub.valor, 'EUR', 'paga', auth.uid());

  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v_sub.empresa_id, 'pagamento_confirmado', 'O pagamento da subscrição foi confirmado',
            nullif(trim(coalesce(p_nota, '')), ''), 'subscricoes', v_sub.id);

  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois, motivo)
    values (v_sub.empresa_id, auth.uid(), 'admin_plataforma', 'confirmar_pagamento_subscricao', 'subscricoes',
            v_sub.id::text,
            jsonb_build_object('valor', v_sub.valor, 'metodo', v_sub.metodo_pagamento, 'referencia', v_sub.referencia,
                               'estado', v_sub.estado),
            nullif(trim(coalesce(p_nota, '')), ''));
  return v_sub;
end $$;
revoke execute on function public.confirmar_pagamento_subscricao(uuid, text) from public, anon;
grant  execute on function public.confirmar_pagamento_subscricao(uuid, text) to authenticated;


-- ===== 00081_emails.sql =====
-- =====================================================================
-- Elolog · 0008 · Aviso por e-mail das decisões e das notificações
-- Depende de 0001–0007.
-- Cada notificação (tabela "notificacoes") passa a gerar linhas numa fila ("emails_fila"), uma por destinatário.
-- A Edge Function "enviar-emails" (chamada por agendamento) envia-as através do Brevo.
--
--  * A fila nunca bloqueia o negócio: se a criação da fila falhar, a notificação e a decisão continuam.
--  * Só recebem e-mail endereços CONFIRMADOS no serviço de contas (auth.users.email_confirmed_at). Isto impede que
--    alguém registe uma empresa com o e-mail de outra pessoa e lhe envie avisos.
--    ATENÇÃO: com "Confirm email" DESLIGADO no Supabase todos os endereços contam como confirmados e esta proteção
--    deixa de existir. Manter ligado.
--  * O conteúdo do e-mail é montado na Edge Function (modelos testáveis); aqui só se guardam os dados da notificação.
--  * Ninguém além do service_role lê ou escreve a fila (RLS ligado, sem políticas).
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- =====================================================================

create table emails_fila (
  id                uuid primary key default gen_random_uuid(),
  notificacao_id    uuid not null references notificacoes(id) on delete cascade,
  destinatario      text not null check (length(destinatario) <= 254 and destinatario ~* '^[^\s@]+@[^\s@]+\.[^\s@]+$'),
  destino           text not null check (destino in ('plataforma', 'empresa', 'utilizador')),
  tipo              text not null,
  titulo            text not null,
  corpo             text,
  estado            text not null default 'pendente' check (estado in ('pendente', 'a_enviar', 'enviado', 'falhou')),
  tentativas        int  not null default 0,
  proxima_tentativa timestamptz not null default now(),
  reservado_ate     timestamptz,
  fornecedor_id     text,                         -- identificador devolvido pelo Brevo
  erro              text,                         -- resumo curto (nunca a chave nem o corpo do e-mail)
  enviado_em        timestamptz,
  created_at        timestamptz not null default now(),
  unique (notificacao_id, destinatario)           -- uma notificação nunca gera dois e-mails para o mesmo endereço
);
create index emails_fila_pendentes on emails_fila (proxima_tentativa) where estado in ('pendente', 'a_enviar');
create index emails_fila_enviados  on emails_fila (enviado_em) where estado = 'enviado';
create index emails_fila_destinatario on emails_fila (destinatario, created_at);

alter table emails_fila enable row level security;      -- sem políticas: só o service_role
revoke all on emails_fila from anon, authenticated;

-- ---------- 1. Que tipos de notificação geram e-mail -------------------
create function private.tipo_envia_email(p_tipo text) returns boolean
language sql immutable as $$
  select p_tipo in ('novo_prestador', 'pedido_subscricao', 'pedido_cliente', 'apoio',
                    'nova_simulacao', 'empresa_aprovada', 'empresa_recusada', 'pagamento_confirmado',
                    'simulacao_aceite', 'simulacao_recusada', 'estado_encomenda')
$$;

-- ---------- 2. Quem recebe ---------------------------------------------
--  utilizador  → a pessoa da notificação (ex.: o cliente)
--  empresa     → os administradores ativos da empresa (e, para pedidos de simulação, também os operadores)
--  plataforma  → os administradores da plataforma
-- Só endereços confirmados. Sem duplicados.
create function private.destinatarios_email(p_n notificacoes)
returns table (email text, destino text)
language sql stable security definer set search_path = public, auth as $$
  select distinct lower(u.email)::text, 'utilizador'::text
    from auth.users u
   where p_n.user_id is not null and u.id = p_n.user_id and u.email is not null and u.email_confirmed_at is not null
  union
  select distinct lower(u.email)::text, 'empresa'::text
    from funcionarios f join auth.users u on u.id = f.id
   where p_n.empresa_id is not null and p_n.user_id is null
     and f.empresa_id = p_n.empresa_id and f.ativo and u.email is not null and u.email_confirmed_at is not null
     and (f.papel = 'admin_empresa' or (p_n.tipo = 'nova_simulacao' and f.papel = 'operador'))
  union
  select distinct lower(u.email)::text, 'plataforma'::text
    from administradores_plataforma a join auth.users u on u.id = a.user_id
   where p_n.para_plataforma and u.email is not null and u.email_confirmed_at is not null
$$;

-- ---------- 3. Notificação → fila --------------------------------------
create function private.enfileirar_emails() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not private.tipo_envia_email(new.tipo) then return new; end if;
  begin
    -- Anti-inundação: ninguém recebe mais de 30 e-mails em 24 h (ex.: um cliente a gerar centenas de simulações
    -- para um prestador). Os avisos continuam a existir dentro da aplicação; só o e-mail é omitido.
    insert into emails_fila (notificacao_id, destinatario, destino, tipo, titulo, corpo)
      select new.id, d.email, d.destino, new.tipo, new.titulo, new.corpo
        from private.destinatarios_email(new) d
       where (select count(*) from emails_fila q
               where q.destinatario = d.email and q.created_at > now() - interval '24 hours') < 30
      on conflict (notificacao_id, destinatario) do nothing;
  exception when others then
    -- Um problema com a fila NUNCA pode impedir a notificação nem a decisão que a originou.
    raise warning 'Elolog: não foi possível enfileirar e-mails da notificação %: %', new.id, sqlerrm;
  end;
  return new;
end $$;

create trigger trg_notificacoes_emails after insert on notificacoes
  for each row execute function private.enfileirar_emails();

-- ---------- 4. Funções de serviço (só service_role) --------------------
-- Reserva um lote para envio. Linhas "a_enviar" cuja reserva expirou (função interrompida) voltam a ser apanhadas.
-- Também: expira o que está há mais de 3 dias na fila (ficaria desatualizado) e apaga o histórico com mais de 90 dias.
create function public.servico_reservar_emails(p_max int default 20, p_reserva_min int default 5)
returns setof emails_fila
language plpgsql security definer set search_path = public as $$
declare v_ids uuid[];
begin
  if p_max < 1 or p_max > 100 or p_reserva_min < 1 then raise exception 'Parâmetros inválidos.'; end if;

  update emails_fila set estado = 'falhou', erro = 'Expirado: mais de 3 dias na fila.'
   where estado = 'pendente' and created_at < now() - interval '3 days';
  delete from emails_fila where estado in ('enviado', 'falhou') and created_at < now() - interval '90 days';

  -- skip locked: duas chamadas em simultâneo nunca reservam as mesmas linhas
  select array_agg(s.id) into v_ids from (
    select id from emails_fila
     where (estado = 'pendente' and proxima_tentativa <= now())
        or (estado = 'a_enviar' and reservado_ate < now())
     order by created_at
     limit p_max
     for update skip locked) s;
  if v_ids is null then return; end if;

  update emails_fila
     set estado = 'a_enviar', tentativas = tentativas + 1, reservado_ate = now() + make_interval(mins => p_reserva_min)
   where id = any (v_ids);

  return query select * from emails_fila where id = any (v_ids) order by created_at;
end $$;

-- Resultado de um envio. p_resultado:
--   enviado  → feito
--   repetir  → falha temporária: volta à fila com espera crescente (2, 4, 8, 16… min, no máximo 60); ao fim de 5 tentativas falha
--   falhou   → falha definitiva (ex.: endereço inválido)
--   libertar → não chegou a ser tentado (limite do fornecedor): volta à fila sem gastar tentativa
create function public.servico_marcar_email(p_id uuid, p_resultado text, p_fornecedor_id text default null, p_erro text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare v emails_fila;
begin
  select * into v from emails_fila where id = p_id for update;
  if not found then return; end if;
  if p_resultado = 'enviado' then
    update emails_fila set estado = 'enviado', enviado_em = now(), fornecedor_id = left(p_fornecedor_id, 120),
                           erro = null, reservado_ate = null where id = p_id;
  elsif p_resultado = 'falhou' then
    update emails_fila set estado = 'falhou', erro = left(coalesce(p_erro, 'Falha definitiva.'), 300), reservado_ate = null where id = p_id;
  elsif p_resultado = 'libertar' then
    update emails_fila set estado = 'pendente', tentativas = greatest(v.tentativas - 1, 0), reservado_ate = null,
                           proxima_tentativa = now() + interval '2 minutes', erro = left(p_erro, 300) where id = p_id;
  elsif p_resultado = 'repetir' then
    if v.tentativas >= 5 then
      update emails_fila set estado = 'falhou', erro = left(coalesce(p_erro, 'Falha temporária repetida.'), 300), reservado_ate = null where id = p_id;
    else
      update emails_fila set estado = 'pendente', reservado_ate = null, erro = left(p_erro, 300),
                             proxima_tentativa = now() + make_interval(mins => least(60, (2 ^ v.tentativas)::int)) where id = p_id;
    end if;
  else
    raise exception 'Resultado desconhecido: %', p_resultado;
  end if;
end $$;

-- E-mails enviados desde as 00:00 UTC (o Brevo repõe o limite diário à meia-noite UTC).
create function public.servico_emails_enviados_hoje() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from emails_fila
   where estado = 'enviado' and enviado_em >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC')
$$;

revoke execute on function
  public.servico_reservar_emails(int, int),
  public.servico_marcar_email(uuid, text, text, text),
  public.servico_emails_enviados_hoje()
  from public, anon, authenticated;
grant execute on function
  public.servico_reservar_emails(int, int),
  public.servico_marcar_email(uuid, text, text, text),
  public.servico_emails_enviados_hoje()
  to service_role;
revoke execute on function private.tipo_envia_email(text), private.destinatarios_email(notificacoes), private.enfileirar_emails() from public;


-- ===== 00091_endurecer.sql =====
-- =====================================================================
-- Elolog · 0009 · Endurecimento das permissões do papel "anon" (OPCIONAL, recomendado)
-- Depende de 0001–0008.
-- Motivo: no Supabase, cada tabela e função nova em "public" recebe por omissão permissões para anon/authenticated.
-- A 0003 revogou as tabelas do anon, mas as criadas DEPOIS (sessoes_empresa, emails_fila...) voltaram a tê-las.
-- Nada fica exposto (o RLS bloqueia e não há políticas para anon), mas é uma camada de defesa a menos.
-- O visitante sem sessão só precisa de UMA coisa: validar_empresa() (1.º passo do login do prestador).
-- É isto que o teste 01 (01_instalacao.sql) assinala como AVISO.
-- NÃO FOI EXECUTADO: aplicar primeiro no projeto de teste e voltar a correr os testes 01 e 02.
-- =====================================================================
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon;
grant  execute on function public.validar_empresa(text, text, text) to anon;

-- Objetos futuros criados por este utilizador (o SQL Editor e as migrações correm como "postgres").
-- Se criar objetos com outro papel (ex.: supabase_admin), repita com "for role <papel>".
alter default privileges for role postgres in schema public revoke all on tables    from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke execute on functions from anon;


-- ===== 00101_painel.sql =====
-- =====================================================================
-- Elolog · 0010 · Indicadores reais do painel da administração (logística transitária)
-- Depende de 0001–0009.
-- Uma só chamada devolve tudo o que o painel mostra, calculado na base de dados (só leitura):
--   prestadores, subscrições e receita, clientes, funil comercial (simulação → proposta → encomenda → entrega),
--   pipeline logístico por estado da encomenda, alertas, rotas mais pedidas, prestadores mais ativos,
--   evolução semanal e atividade recente.
-- Só a administração da plataforma a pode executar. Não devolve dados pessoais (nomes de clientes, moradas, e-mails).
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- =====================================================================
create function public.painel_administracao(p_dias int default 30)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini timestamptz;
  v_res jsonb;
begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;
  if p_dias is null or p_dias not in (7, 14, 30, 60, 90, 180) then raise exception 'Período inválido: use 7, 30 ou 90 dias (ou o dobro, para comparar com o período anterior).'; end if;
  v_ini := now() - make_interval(days => p_dias);

  select jsonb_build_object(
    'gerado_em', now(),
    'periodo_dias', p_dias,

    'prestadores', (select jsonb_build_object(
        'ativos',              count(*) filter (where estado = 'aprovada'),
        'pendentes',           count(*) filter (where estado = 'pendente'),
        'suspensos',           count(*) filter (where estado = 'suspensa'),
        'recusados',           count(*) filter (where estado = 'rejeitada'),
        'pendentes_mais_48h',  count(*) filter (where estado = 'pendente' and created_at < now() - interval '48 hours'),
        'novos_periodo',       count(*) filter (where created_at >= v_ini))
      from empresas),

    -- receita recorrente mensal: subscrições ativas (as anuais a 1/12)
    'subscricoes', (select jsonb_build_object(
        'mrr',                     coalesce(sum(case when periodicidade = 'anual' then valor / 12 else valor end) filter (where estado = 'ativa'), 0),
        'ativas',                  count(*) filter (where estado = 'ativa'),
        'pagamentos_por_confirmar', count(*) filter (where estado = 'pendente' and pago_em is null),
        'valor_por_confirmar',     coalesce(sum(valor) filter (where estado = 'pendente' and pago_em is null), 0))
      from subscricoes),

    -- recibos internos emitidos ao confirmar pagamentos
    'receita', (select jsonb_build_object(
        'periodo', coalesce(sum(valor) filter (where tipo = 'recibo' and estado = 'paga' and emitida_em >= v_ini), 0),
        'mes',     coalesce(sum(valor) filter (where tipo = 'recibo' and estado = 'paga' and emitida_em >= date_trunc('month', now())), 0))
      from faturas_plataforma),

    'clientes', (select jsonb_build_object('total', count(*), 'novos_periodo', count(*) filter (where created_at >= v_ini)) from clientes),

    'funil', jsonb_build_object(
        'simulacoes', (select count(*) from simulacoes where estado <> 'rascunho' and enviada_em >= v_ini),
        'propostas',  (select count(*) from propostas where created_at >= v_ini),
        'aceites',    (select count(*) from propostas where estado = 'aceite' and created_at >= v_ini),
        'encomendas', (select count(*) from encomendas where created_at >= v_ini),
        'entregues',  (select count(*) from encomendas where estado = 'entregue' and created_at >= v_ini)),

    -- todos os estados aparecem, mesmo a zero (a ordem do fluxo é a do enum)
    'pipeline', (select jsonb_object_agg(e::text, coalesce(c.n, 0))
                   from unnest(enum_range(null::estado_encomenda)) e
                   left join (select estado, count(*) as n from encomendas group by estado) c on c.estado = e),

    'encomendas', (select jsonb_build_object(
        'em_curso',            count(*) filter (where estado not in ('entregue', 'cancelada')),
        'valor_em_curso',      coalesce(sum(preco_total) filter (where estado not in ('entregue', 'cancelada')), 0),
        'valor_periodo',       coalesce(sum(preco_total) filter (where created_at >= v_ini and estado <> 'cancelada'), 0),
        'paradas_mais_7d',     count(*) filter (where estado not in ('entregue', 'cancelada') and updated_at < now() - interval '7 days'),
        'canceladas_periodo',  count(*) filter (where estado = 'cancelada' and created_at >= v_ini))
      from encomendas),

    'rotas', coalesce((select jsonb_agg(r) from (
        select origem, destino, count(*) as pedidos, round(avg(preco_estimado), 2) as preco_medio
          from simulacoes where estado <> 'rascunho' and enviada_em >= v_ini
         group by origem, destino order by count(*) desc, origem, destino limit 5) r), '[]'::jsonb),

    'top_prestadores', coalesce((select jsonb_agg(t) from (
        select e.nome, count(*) as encomendas, coalesce(sum(o.preco_total), 0) as valor
          from encomendas o join empresas e on e.id = o.empresa_id
         where o.created_at >= v_ini and o.estado <> 'cancelada'
         group by e.nome order by count(*) desc, e.nome limit 5) t), '[]'::jsonb),

    -- últimas 8 semanas (segunda a domingo), incluindo a corrente
    'serie_semanal', (select jsonb_agg(s order by s.semana) from (
        select to_char(w, 'YYYY-MM-DD') as semana,
               (select count(*) from encomendas o where o.created_at >= w and o.created_at < w + interval '7 days') as encomendas,
               (select coalesce(sum(o.preco_total), 0) from encomendas o
                 where o.created_at >= w and o.created_at < w + interval '7 days' and o.estado <> 'cancelada') as valor
          from generate_series(date_trunc('week', now()) - interval '7 weeks', date_trunc('week', now()), interval '1 week') w) s),

    'apoio', (select jsonb_build_object('abertos', count(*) filter (where estado <> 'resolvido'),
                                        'escalados', count(*) filter (where estado = 'escalado')) from tickets),

    -- sem motivos nem dados pessoais: só o tipo de ação, quem agiu (papel), a empresa e quando
    'atividade', coalesce((select jsonb_agg(a) from (
        select au.acao, au.papel, e.nome as empresa, au.created_at
          from auditoria au left join empresas e on e.id = au.empresa_id
         order by au.created_at desc limit 8) a), '[]'::jsonb)
  ) into v_res;

  return v_res;
end $$;

revoke execute on function public.painel_administracao(int) from public, anon;
grant  execute on function public.painel_administracao(int) to authenticated;


-- ===== 00111_mfa_admin.sql =====
-- =====================================================================
-- Elolog · 0011 · Verificação em dois passos (TOTP) para a administração da plataforma
-- Depende de 0001–0010.
-- Com a regra LIGADA, só é administrador quem tem a sessão no nível aal2 (palavra-passe + código da aplicação de autenticação),
-- em todas as políticas e funções de administração (todas passam por private.e_admin_plataforma()).
-- DESLIGADA por omissão: ligar só depois de a administração ter registado o autenticador no 1.º acesso (senão ninguém entra).
--   ligar:     update private.plataforma_config set valor = 'true'  where chave = 'exigir_mfa_admin';
--   desligar:  update private.plataforma_config set valor = 'false' where chave = 'exigir_mfa_admin';   (recuperação, no SQL Editor)
-- Requer o MFA TOTP ativo no Supabase (Authentication → Multi-factor). NÃO FOI EXECUTADO: testar primeiro num projeto de teste.
-- =====================================================================
create table private.plataforma_config (chave text primary key, valor text not null);
revoke all on private.plataforma_config from public, anon, authenticated;     -- a API nunca a lê nem escreve
insert into private.plataforma_config values ('exigir_mfa_admin', 'false');

create function private.mfa_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select valor from private.plataforma_config where chave = 'exigir_mfa_admin'), 'false') <> 'true'
      or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
$$;
grant execute on function private.mfa_ok() to authenticated, service_role;

-- Mesmas assinaturas de 0003 e 0007 (as permissões de execução mantêm-se).
create or replace function private.e_admin_plataforma() returns boolean
language sql stable security definer set search_path = public as $$
  select private.mfa_ok() and exists (select 1 from administradores_plataforma where user_id = auth.uid())
$$;

create or replace function public.sou_admin_plataforma()
returns table (ok boolean, nome text)
language sql stable security definer set search_path = public as $$
  select true, a.nome from administradores_plataforma a where a.user_id = auth.uid() and private.mfa_ok()
$$;


-- ===== 00121_avisos_seguranca.sql =====
-- =====================================================================
-- Elolog · 0012 · Correções dos avisos de segurança do Supabase (aplicada no projeto «Elolog T» a 24/10/2026)
-- Depende de 0001–0011.
--   1. A vista empresas_disponiveis passa a respeitar as permissões de quem consulta (security_invoker)
--      e deixa de estar exposta na API: só as funções do servidor a usam (calcular_propostas, enviar_simulacao),
--      e essas correm como dono, por isso continuam a ver todas as empresas aprovadas.
--   2. search_path fixo nas funções internas que ainda não o tinham.
--   3. Tabelas internas (segredos, sessões, tentativas, fila de e-mails, contadores) sem qualquer privilégio
--      para anon/authenticated. O RLS já as bloqueava; isto é uma segunda camada.
-- =====================================================================
alter view public.empresas_disponiveis set (security_invoker = true);
revoke all on public.empresas_disponiveis from anon, authenticated;

alter function private.set_updated_at()                                   set search_path = public;
alter function private.bloquear_estado_direto()                           set search_path = public;
alter function private.proteger_preco_encomenda()                         set search_path = public;
alter function private.custo_recolha_por_km()                             set search_path = public;
alter function private.preco_com_tarifa(tarifas, int, numeric, numeric)   set search_path = public;
alter function private.permissoes_validas(text[])                         set search_path = public;
alter function private.tipo_envia_email(text)                             set search_path = public;

revoke all on public.empresa_segredos, public.sessoes_empresa, public.tentativas_gate,
              public.emails_fila, public.contadores from anon, authenticated;


-- ===== 00131_producao_parte1.sql =====
-- Elolog — produção, parte 1: tarefas agendadas (emails), documentos no armazenamento e faturas certificadas.
-- Depois de aplicar: select private.agendar_tarefas('https://<projeto>.supabase.co');  (uma vez por projeto)

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- ---------- 1. Tarefas agendadas ----------------------------------------------
-- O segredo do agendador é gerado aqui e fica no cofre (vault): nunca aparece em ficheiros nem no navegador.
-- As funções de servidor leem-no com a chave de serviço (servico_segredo_cron).
create or replace function private.chamar_funcao(p_nome text, p_corpo jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_url text; v_seg text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'url_projeto';
  select decrypted_secret into v_seg from vault.decrypted_secrets where name = 'cron_secret';
  if v_url is null or v_seg is null then return null; end if;
  return net.http_post(url := v_url || '/functions/v1/' || p_nome,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_seg),
    body := p_corpo, timeout_milliseconds := 55000);
end $$;
revoke all on function private.chamar_funcao(text, jsonb) from public, anon, authenticated;

create or replace function private.agendar_tarefas(p_url text)
returns text language plpgsql security definer set search_path = '' as $$
begin
  if p_url !~ '^https://[a-z0-9-]+\.supabase\.co$' then raise exception 'Endereço do projeto inválido: %', p_url; end if;
  if exists (select 1 from vault.secrets where name = 'url_projeto') then
    update vault.secrets set secret = p_url where name = 'url_projeto';
  else perform vault.create_secret(p_url, 'url_projeto', 'Endereço do projeto (tarefas agendadas)'); end if;
  if not exists (select 1 from vault.secrets where name = 'cron_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'cron_secret', 'Segredo das funções agendadas');
  end if;
  perform cron.schedule('elolog-emails', '*/5 * * * *', $c$select private.chamar_funcao('enviar-emails')$c$);
  perform cron.schedule('elolog-navios', '7,37 * * * *', $c$select private.chamar_funcao('navios-ais')$c$);
  perform cron.schedule('elolog-pagamentos', '*/10 * * * *', $c$select private.chamar_funcao('pagamentos', '{"acao":"verificar"}'::jsonb)$c$);
  perform cron.schedule('elolog-limpar-net', '17 3 * * *', $c$delete from net._http_response where created < now() - interval '2 days'$c$);
  return 'Tarefas agendadas: emails (5 min), navios (30 min), pagamentos (10 min), limpeza diária.';
end $$;
revoke all on function private.agendar_tarefas(text) from public, anon, authenticated;

create or replace function public.servico_segredo_cron() returns text
language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret' $$;
revoke all on function public.servico_segredo_cron() from public, anon, authenticated;
grant execute on function public.servico_segredo_cron() to service_role;

-- ---------- 2. Documentos no armazenamento ------------------------------------
-- Limite de 20 MB e só formatos de documento e imagem.
update storage.buckets set file_size_limit = 20971520,
  allowed_mime_types = array['application/pdf','image/jpeg','image/png','image/webp',
    'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
  where id = 'documentos';

-- A empresa vê os documentos que o cliente juntou às encomendas dela.
drop policy if exists docs_empresa_ver_cliente on documentos;
create policy docs_empresa_ver_cliente on documentos for select to authenticated
  using (encomenda_id is not null and exists (select 1 from encomendas en
         where en.id = documentos.encomenda_id and en.empresa_id = private.minha_empresa()));

-- O cliente só junta documentos às suas encomendas (ou ao seu perfil, sem encomenda).
drop policy if exists docs_cliente_criar on documentos;
create policy docs_cliente_criar on documentos for insert to authenticated
  with check (cliente_id = auth.uid() and empresa_id is null and enviado_por = auth.uid()
    and (encomenda_id is null or exists (select 1 from encomendas en where en.id = documentos.encomenda_id and en.cliente_id = auth.uid())));

-- ---------- 3. Faturas certificadas -------------------------------------------
-- A Elolog não emite faturas: a empresa carrega o PDF do seu programa certificado pela AT.
-- O QR da fatura (Portaria 195/2020) é lido no navegador e validado aqui antes de ficar registado.
create table if not exists faturas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  encomenda_id uuid references encomendas(id) on delete set null,
  cliente_id uuid,
  documento_id uuid references documentos(id) on delete set null,
  tipo_documento text not null,            -- FT, FR, FS, NC, ND
  numero text not null,                    -- ex.: FT A/123
  atcud text not null,                     -- ex.: JJHC3KYL-123
  data_emissao date not null,
  nif_emitente text not null,
  nif_adquirente text not null,
  total numeric(12,2) not null check (total >= 0),
  total_iva numeric(12,2) not null default 0,
  hash4 text,
  certificado text,
  qr_texto text not null,
  estado text not null default 'valida' check (estado in ('valida','anulada')),
  registada_por uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  unique (empresa_id, numero),
  unique (empresa_id, atcud)
);
alter table faturas enable row level security;
create policy faturas_empresa_ver on faturas for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro','operador']));
create policy faturas_cliente_ver on faturas for select to authenticated using (cliente_id = auth.uid());
create policy faturas_admin_ver on faturas for select to authenticated using (private.e_admin_plataforma());
revoke insert, update, delete on faturas from anon, authenticated;

create or replace function private.nif_valido(p text) returns boolean language plpgsql immutable set search_path = '' as $$
declare s int := 0; i int; d int;
begin
  if p = '999999990' then return true; end if;                -- consumidor final
  if p !~ '^[1-9][0-9]{8}$' then return false; end if;
  for i in 1..8 loop s := s + substr(p, i, 1)::int * (10 - i); end loop;
  d := 11 - (s % 11); if d >= 10 then d := 0; end if;
  return d = substr(p, 9, 1)::int;
end $$;


-- ===== 00132_producao_parte2.sql =====
-- Elolog — produção, parte 2: registo de faturas certificadas e pagamentos ifthenpay (Multibanco e MB WAY).

-- ---------- 1. Registar uma fatura a partir do QR da AT ---------------------------
create or replace function public.registar_fatura(p_documento uuid, p_qr text, p_encomenda uuid default null)
returns faturas language plpgsql security definer set search_path = public as $$
declare m jsonb := '{}'; parte text; k text; v text; e empresas; en encomendas; d documentos; f faturas;
        v_total numeric; v_data date; v_faturado numeric;
begin
  if not private.papel_em(array['admin_empresa','financeiro']) then raise exception 'Só o administrador ou o financeiro registam faturas.'; end if;
  select * into e from empresas where id = private.minha_empresa();
  select * into d from documentos where id = p_documento and empresa_id = e.id;
  if d.id is null then raise exception 'Documento não encontrado nesta empresa.'; end if;
  if length(coalesce(p_qr, '')) not between 20 and 1000 then raise exception 'Código QR da fatura em falta ou inválido.'; end if;
  foreach parte in array string_to_array(p_qr, '*') loop
    k := split_part(parte, ':', 1); v := substr(parte, length(k) + 2);
    if k <> '' then m := m || jsonb_build_object(k, v); end if;
  end loop;
  if not (m ? 'A' and m ? 'B' and m ? 'D' and m ? 'F' and m ? 'G' and m ? 'H' and m ? 'O') then
    raise exception 'O QR não tem os campos obrigatórios da AT (A, B, D, F, G, H, O).'; end if;
  if regexp_replace(m->>'A', '^PT', '') <> regexp_replace(coalesce(e.nif, ''), '^PT', '') then
    raise exception 'O NIF do emitente (%) não é o NIF da empresa.', m->>'A'; end if;
  if not private.nif_valido(m->>'B') then raise exception 'NIF do cliente inválido: %', m->>'B'; end if;
  if m->>'D' not in ('FT','FR','FS','NC','ND') then raise exception 'Tipo de documento não aceite: %', m->>'D'; end if;
  if coalesce(m->>'E', 'N') = 'A' then raise exception 'Esta fatura está anulada.'; end if;
  if m->>'H' !~ '^[A-Z0-9]{8,}-[0-9]+$' then raise exception 'ATCUD inválido: %', m->>'H'; end if;
  begin v_data := to_date(m->>'F', 'YYYYMMDD'); v_total := (m->>'O')::numeric;
  exception when others then raise exception 'Data ou total ilegíveis no QR.'; end;
  if v_data > current_date or v_data < current_date - 400 then raise exception 'Data da fatura fora do intervalo aceite.'; end if;
  if p_encomenda is not null then
    select * into en from encomendas where id = p_encomenda and empresa_id = e.id;
    if en.id is null then raise exception 'Encomenda não encontrada nesta empresa.'; end if;
    if en.cliente_nif is not null and m->>'B' <> '999999990' and m->>'B' <> en.cliente_nif then
      raise exception 'O NIF do cliente na fatura (%) não corresponde ao da encomenda.', m->>'B'; end if;
    select coalesce(sum(case when tipo_documento = 'NC' then -total else total end), 0) into v_faturado
      from faturas where encomenda_id = en.id and estado = 'valida';
    if m->>'D' <> 'NC' and en.preco_total is not null and v_faturado + v_total > en.preco_total + 0.01 then
      raise exception 'O total faturado (% €) passaria o preço da encomenda (% €).', v_faturado + v_total, en.preco_total; end if;
  end if;
  insert into faturas (empresa_id, encomenda_id, cliente_id, documento_id, tipo_documento, numero, atcud, data_emissao,
    nif_emitente, nif_adquirente, total, total_iva, hash4, certificado, qr_texto)
  values (e.id, en.id, en.cliente_id, d.id, m->>'D', m->>'G', m->>'H', v_data, m->>'A', m->>'B', v_total,
    coalesce(nullif(m->>'N', '')::numeric, 0), m->>'Q', m->>'R', p_qr)
  returning * into f;
  update documentos set categoria = 'fatura', visibilidade = case when en.id is null then visibilidade else 'cliente' end,
    encomenda_id = coalesce(en.id, encomenda_id) where id = d.id;
  if en.cliente_id is not null then
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (en.cliente_id, 'fatura_emitida', 'Fatura ' || f.numero, 'A fatura da encomenda ' || en.codigo || ' já está nos seus documentos.', 'faturas', f.id);
  end if;
  insert into auditoria (empresa_id, user_id, acao, entidade, entidade_id, depois)
  values (e.id, auth.uid(), 'registar_fatura', 'faturas', f.id::text, jsonb_build_object('numero', f.numero, 'total', f.total));
  return f;
exception when unique_violation then raise exception 'Esta fatura (número ou ATCUD) já foi registada.';
end $$;
revoke all on function public.registar_fatura(uuid, text, uuid) from public, anon;
grant execute on function public.registar_fatura(uuid, text, uuid) to authenticated;

create or replace function private.tipo_envia_email(p_tipo text) returns boolean language sql immutable set search_path = public as $$
  select p_tipo in ('novo_prestador', 'pedido_subscricao', 'pedido_cliente', 'apoio', 'nova_simulacao', 'empresa_aprovada',
    'empresa_recusada', 'pagamento_confirmado', 'simulacao_aceite', 'simulacao_recusada', 'estado_encomenda', 'fatura_emitida', 'pagamento_recebido') $$;

-- ---------- 2. Configuração de pagamentos da empresa ---------------------------
-- As chaves da ifthenpay ficam numa tabela sem acesso pela aplicação; só funções de servidor as leem.
create table if not exists empresa_pagamentos_config (
  empresa_id uuid primary key references empresas(id) on delete cascade,
  mb_key text, mbway_key text, chave_antiphishing text,
  ativo boolean not null default false, sandbox boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table empresa_pagamentos_config enable row level security;
revoke all on empresa_pagamentos_config from anon, authenticated;

create or replace function public.ver_config_pagamentos() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c empresa_pagamentos_config; mascara text := '••••';
begin
  if not private.papel_em(array['admin_empresa','financeiro']) then raise exception 'Sem permissão.'; end if;
  select * into c from empresa_pagamentos_config where empresa_id = private.minha_empresa();
  return jsonb_build_object('multibanco', case when c.mb_key is null then null else mascara || right(c.mb_key, 3) end,
    'mbway', case when c.mbway_key is null then null else mascara || right(c.mbway_key, 3) end,
    'antiphishing', c.chave_antiphishing is not null, 'ativo', coalesce(c.ativo, false), 'sandbox', coalesce(c.sandbox, true));
end $$;

create or replace function public.guardar_config_pagamentos(p_mb_key text, p_mbway_key text, p_antiphishing text, p_ativo boolean, p_sandbox boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid := private.minha_empresa(); limpa text;
begin
  if not private.papel_em(array['admin_empresa']) then raise exception 'Só o administrador da empresa altera os pagamentos.'; end if;
  foreach limpa in array array[p_mb_key, p_mbway_key] loop
    if nullif(trim(limpa), '') is not null and trim(limpa) !~ '^[A-Za-z0-9-]{6,40}$' then raise exception 'Chave ifthenpay com formato inválido.'; end if;
  end loop;
  if nullif(trim(p_antiphishing), '') is not null and length(trim(p_antiphishing)) < 12 then raise exception 'A chave anti-phishing deve ter pelo menos 12 caracteres.'; end if;
  insert into empresa_pagamentos_config (empresa_id) values (v_emp) on conflict (empresa_id) do nothing;
  update empresa_pagamentos_config set
    mb_key = coalesce(nullif(trim(p_mb_key), ''), mb_key), mbway_key = coalesce(nullif(trim(p_mbway_key), ''), mbway_key),
    chave_antiphishing = coalesce(nullif(trim(p_antiphishing), ''), chave_antiphishing),
    ativo = coalesce(p_ativo, ativo), sandbox = coalesce(p_sandbox, sandbox), updated_at = now()
  where empresa_id = v_emp;
  if p_ativo and exists (select 1 from empresa_pagamentos_config where empresa_id = v_emp
                         and (chave_antiphishing is null or (mb_key is null and mbway_key is null))) then
    raise exception 'Para ativar indique a chave anti-phishing e pelo menos uma chave (Multibanco ou MB WAY).'; end if;
  insert into auditoria (empresa_id, user_id, acao, entidade, entidade_id) values (v_emp, auth.uid(), 'config_pagamentos', 'empresas', v_emp::text);
  return public.ver_config_pagamentos();
end $$;
revoke all on function public.ver_config_pagamentos(), public.guardar_config_pagamentos(text, text, text, boolean, boolean) from public, anon;
grant execute on function public.ver_config_pagamentos(), public.guardar_config_pagamentos(text, text, text, boolean, boolean) to authenticated;


-- ===== 00133_producao_parte3.sql =====
-- Elolog — produção, parte 3: pedidos de pagamento (ifthenpay) e posições reais dos navios (AIS).

-- ---------- 1. Pedidos de pagamento ---------------------------------------------
create table if not exists pedidos_pagamento (
  id uuid primary key default gen_random_uuid(),
  order_id text not null unique check (length(order_id) <= 15),
  empresa_id uuid not null references empresas(id) on delete cascade,
  encomenda_id uuid not null references encomendas(id) on delete cascade,
  cliente_id uuid not null,
  metodo text not null check (metodo in ('multibanco','mbway')),
  valor numeric(12,2) not null check (valor > 0),
  estado text not null default 'pendente' check (estado in ('pendente','pago','expirado','recusado','erro')),
  request_id text, entidade text, referencia text, telemovel text, mensagem text,
  expira_em timestamptz, pago_em timestamptz, pagamento_id uuid references pagamentos(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists pedidos_pagamento_encomenda on pedidos_pagamento (encomenda_id, estado);
alter table pedidos_pagamento enable row level security;
create policy pedidos_cliente_ver on pedidos_pagamento for select to authenticated using (cliente_id = auth.uid());
create policy pedidos_empresa_ver on pedidos_pagamento for select to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro','operador']));
create policy pedidos_admin_ver on pedidos_pagamento for select to authenticated using (private.e_admin_plataforma());
revoke insert, update, delete on pedidos_pagamento from anon, authenticated;

-- Só a função de servidor «pagamentos» (chave de serviço) usa as três funções abaixo.
create or replace function public.servico_preparar_pedido(p_cliente uuid, p_encomenda text, p_metodo text, p_telemovel text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare en encomendas; c empresa_pagamentos_config; v_pago numeric; v_valor numeric; p pedidos_pagamento;
begin
  select * into en from encomendas where codigo = p_encomenda and cliente_id = p_cliente;
  if en.id is null then raise exception 'Encomenda não encontrada.'; end if;
  select * into c from empresa_pagamentos_config where empresa_id = en.empresa_id and ativo;
  if c.empresa_id is null then raise exception 'Esta empresa ainda não aceita pagamentos online.'; end if;
  if p_metodo = 'multibanco' and c.mb_key is null or p_metodo = 'mbway' and c.mbway_key is null then raise exception 'Método não disponível para esta empresa.'; end if;
  if p_metodo = 'mbway' and coalesce(p_telemovel, '') !~ '^9[1236][0-9]{7}$' then raise exception 'Indique um telemóvel português válido (9 dígitos).'; end if;
  if (select count(*) from pedidos_pagamento where encomenda_id = en.id and created_at > now() - interval '1 hour') >= 6 then
    raise exception 'Demasiados pedidos de pagamento seguidos. Tente daqui a pouco.'; end if;
  select coalesce(sum(valor), 0) into v_pago from pagamentos where encomenda_id = en.id and estado = 'pago';
  v_valor := round(coalesce(en.preco_total, 0) - v_pago, 2);
  if v_valor <= 0 then raise exception 'Esta encomenda já está paga.'; end if;
  -- Reaproveita uma referência Multibanco ainda válida com o mesmo valor.
  select * into p from pedidos_pagamento where encomenda_id = en.id and metodo = 'multibanco' and p_metodo = 'multibanco'
    and estado = 'pendente' and valor = v_valor and referencia is not null and (expira_em is null or expira_em > now()) limit 1;
  if p.id is not null then return jsonb_build_object('reutilizar', true, 'pedido', to_jsonb(p)); end if;
  update pedidos_pagamento set estado = 'expirado', updated_at = now() where encomenda_id = en.id and estado = 'pendente' and metodo = p_metodo;
  insert into pedidos_pagamento (order_id, empresa_id, encomenda_id, cliente_id, metodo, valor, telemovel)
  values ('EL' || upper(substr(md5(gen_random_uuid()::text), 1, 12)), en.empresa_id, en.id, p_cliente, p_metodo, v_valor, nullif(p_telemovel, ''))
  returning * into p;
  return jsonb_build_object('reutilizar', false, 'pedido', to_jsonb(p), 'sandbox', c.sandbox,
    'chave', case when p_metodo = 'multibanco' then c.mb_key else c.mbway_key end, 'descricao', 'Encomenda ' || en.codigo);
end $$;

create or replace function public.servico_atualizar_pedido(p_id uuid, p_estado text, p_dados jsonb)
returns void language sql security definer set search_path = public as $$
  update pedidos_pagamento set estado = coalesce(p_estado, estado), request_id = coalesce(p_dados->>'request_id', request_id),
    entidade = coalesce(p_dados->>'entidade', entidade), referencia = coalesce(p_dados->>'referencia', referencia),
    expira_em = coalesce((p_dados->>'expira_em')::timestamptz, expira_em), mensagem = left(coalesce(p_dados->>'mensagem', mensagem), 300),
    updated_at = now()
  where id = p_id and estado = 'pendente' $$;

-- Confirma um pagamento (aviso da ifthenpay ou verificação do MB WAY). Repetir não paga duas vezes.
create or replace function public.servico_confirmar_pedido(p_order_id text, p_chave text, p_valor numeric, p_origem text)
returns text language plpgsql security definer set search_path = public as $$
declare p pedidos_pagamento; c empresa_pagamentos_config; v_pag uuid; en encomendas;
begin
  select * into p from pedidos_pagamento where order_id = p_order_id for update;
  if p.id is null then return 'desconhecido'; end if;
  select * into c from empresa_pagamentos_config where empresa_id = p.empresa_id;
  if p_origem = 'aviso' and (c.chave_antiphishing is null or p_chave is distinct from c.chave_antiphishing) then return 'chave_invalida'; end if;
  if p.estado = 'pago' then return 'ja_pago'; end if;
  if abs(coalesce(p_valor, -1) - p.valor) > 0.009 then return 'valor_diferente'; end if;
  insert into pagamentos (empresa_id, encomenda_id, cliente_id, tipo, valor, estado, metodo, referencia, pago_em)
  values (p.empresa_id, p.encomenda_id, p.cliente_id, 'total', p.valor, 'pago',
    case when p.metodo = 'mbway' then 'MB WAY' else 'Multibanco' end, coalesce(p.referencia, p.request_id, p.order_id), now())
  returning id into v_pag;
  update pedidos_pagamento set estado = 'pago', pago_em = now(), pagamento_id = v_pag, updated_at = now() where id = p.id;
  select * into en from encomendas where id = p.encomenda_id;
  insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  values (p.cliente_id, 'pagamento_recebido', 'Pagamento recebido', 'Recebemos ' || p.valor || ' € da encomenda ' || en.codigo || '.', 'pagamentos', v_pag);
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  values (p.empresa_id, 'pagamento_recebido', 'Pagamento recebido · ' || en.codigo, p.valor || ' € por ' || p.metodo || '.', 'pagamentos', v_pag);
  insert into auditoria (empresa_id, acao, entidade, entidade_id, depois)
  values (p.empresa_id, 'pagamento_online', 'pagamentos', v_pag::text, jsonb_build_object('metodo', p.metodo, 'valor', p.valor, 'origem', p_origem));
  return 'pago';
end $$;

-- Pedidos MB WAY à espera, para a verificação periódica (caso o aviso não chegue).
create or replace function public.servico_pedidos_mbway_pendentes() returns table (id uuid, order_id text, request_id text, valor numeric, chave text, sandbox boolean)
language plpgsql security definer set search_path = public as $$
begin
  update pedidos_pagamento pp set estado = 'expirado', updated_at = now()
    where pp.estado = 'pendente' and (pp.metodo = 'mbway' and pp.created_at < now() - interval '30 minutes' or pp.expira_em < now());
  return query select pp.id, pp.order_id, pp.request_id, pp.valor, c.mbway_key, c.sandbox from pedidos_pagamento pp
    join empresa_pagamentos_config c on c.empresa_id = pp.empresa_id
    where pp.metodo = 'mbway' and pp.estado = 'pendente' and pp.request_id is not null limit 50;
end $$;

revoke all on function public.servico_preparar_pedido(uuid, text, text, text), public.servico_atualizar_pedido(uuid, text, jsonb),
  public.servico_confirmar_pedido(text, text, numeric, text), public.servico_pedidos_mbway_pendentes() from public, anon, authenticated;
grant execute on function public.servico_preparar_pedido(uuid, text, text, text), public.servico_atualizar_pedido(uuid, text, jsonb),
  public.servico_confirmar_pedido(text, text, numeric, text), public.servico_pedidos_mbway_pendentes() to service_role;

-- ---------- 2. Navios seguidos e posições AIS -----------------------------------
create table if not exists navios_seguidos (
  empresa_id uuid not null references empresas(id) on delete cascade,
  mmsi text not null check (mmsi ~ '^[0-9]{9}$'),
  nome text not null check (length(nome) between 2 and 80),
  viagem text, created_at timestamptz not null default now(),
  primary key (empresa_id, mmsi)
);
create table if not exists navios_posicoes (
  mmsi text primary key, nome text, imo text, latitude double precision, longitude double precision,
  velocidade_nos numeric, rumo numeric, destino text, eta timestamptz, posicao_em timestamptz, atualizado_em timestamptz not null default now()
);
alter table navios_seguidos enable row level security;
alter table navios_posicoes enable row level security;
create policy navios_seguidos_empresa on navios_seguidos for all to authenticated
  using (empresa_id = private.minha_empresa()) with check (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','operador','armazem']));
create policy navios_posicoes_ver on navios_posicoes for select to authenticated
  using (private.e_admin_plataforma() or exists (select 1 from navios_seguidos s where s.mmsi = navios_posicoes.mmsi and s.empresa_id = private.minha_empresa()));
revoke insert, update, delete on navios_posicoes from anon, authenticated;

create or replace function public.servico_navios_seguidos() returns table (mmsi text) language sql stable security definer set search_path = public as $$
  select distinct mmsi from navios_seguidos order by 1 limit 50 $$;
revoke all on function public.servico_navios_seguidos() from public, anon, authenticated;
grant execute on function public.servico_navios_seguidos() to service_role;


-- ===== 00134_pedido_cotacao.sql =====
-- v60 — Pedido de cotação: o cliente pode enviar a simulação a um prestador que ainda não tem tarifa para a rota.
-- O prestador responde com um preço manual ao aceitar. A administração vê todas as simulações (rascunhos incluídos).

create or replace function public.enviar_simulacao(p_simulacao uuid, p_empresa uuid)
returns simulacoes language plpgsql security definer set search_path to 'public' as $$
declare v_sim simulacoes; v_t tarifas; v_preco numeric;
begin
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.cliente_id is distinct from auth.uid() then raise exception 'Simulação inexistente.'; end if;
  if v_sim.estado <> 'rascunho' then raise exception 'A simulação já foi enviada (%).', v_sim.estado; end if;
  if not exists (select 1 from empresas_disponiveis e where e.id = p_empresa) then raise exception 'Este prestador não está disponível.'; end if;

  v_t := private.tarifa_aplicavel(p_empresa, v_sim.origem, v_sim.destino, v_sim.tipo_carga);
  if v_t.id is not null then
    v_preco := private.preco_com_tarifa(v_t, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3)
               + case when v_sim.recolha_na_morada then round(coalesce(v_sim.recolha_distancia_km, 0) * private.custo_recolha_por_km(), 2) else 0 end;
  end if;

  update simulacoes set estado = 'enviada', empresa_destinatario_id = p_empresa, enviada_em = now(),
         preco_estimado = v_preco, moeda_estimada = coalesce(v_t.moeda, 'EUR'), tarifa_estimada_id = v_t.id
   where id = v_sim.id returning * into v_sim;

  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (p_empresa, 'nova_simulacao',
            case when v_preco is null then 'Novo pedido de cotação' else 'Nova simulação recebida' end,
            case when v_preco is null then v_sim.origem || ' → ' || v_sim.destino || ': sem tarifa para esta rota. Indique o preço ao aceitar.' end,
            'simulacoes', v_sim.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (p_empresa, auth.uid(), 'cliente', 'enviar_simulacao', 'simulacoes', v_sim.id::text,
            jsonb_build_object('preco_estimado', v_preco, 'tarifa', v_t.id, 'pedido_cotacao', v_preco is null));
  return v_sim;
end $$;

-- Aceitar com preço manual (obrigatório quando não houve tarifa).
drop function if exists public.aceitar_simulacao(uuid);
create function public.aceitar_simulacao(p_simulacao uuid, p_preco numeric default null)
returns encomendas language plpgsql security definer set search_path to 'public' as $$
declare v_sim simulacoes; v_enc encomendas; v_prop uuid; v_preco numeric;
begin
  if private.minha_empresa() is null or not private.papel_em(array['admin_empresa','operador']) then
    raise exception 'Sem permissão para aceitar simulações.'; end if;
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.empresa_destinatario_id is distinct from private.minha_empresa() then raise exception 'Simulação inexistente.'; end if;
  if v_sim.estado not in ('enviada', 'respondida') then raise exception 'A simulação já não está disponível (%).', v_sim.estado; end if;
  v_preco := coalesce(p_preco, v_sim.preco_estimado);
  if v_preco is null or v_preco <= 0 then raise exception 'Indique o preço para este pedido de cotação.'; end if;
  if v_preco > 10000000 then raise exception 'Preço inválido.'; end if;
  v_preco := round(v_preco, 2);

  update propostas set estado = 'cancelada', respondida_em = now()
   where simulacao_id = v_sim.id and empresa_id = v_sim.empresa_destinatario_id and estado = 'enviada';
  insert into propostas (simulacao_id, empresa_id, tarifa_id, preco, moeda, estado, mensagem, criado_por, respondida_em)
  values (v_sim.id, v_sim.empresa_destinatario_id, v_sim.tarifa_estimada_id, v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), 'aceite',
          case when p_preco is not null and v_sim.preco_estimado is distinct from v_preco then 'Aceite com preço indicado pelo prestador.'
               else 'Aceite ao preço calculado pelas tarifas do prestador.' end, auth.uid(), now())
  returning id into v_prop;
  update simulacoes set estado = 'convertida', preco_estimado = v_preco where id = v_sim.id;

  insert into encomendas (empresa_id, cliente_id, simulacao_id, proposta_id, origem, destino, tipo_carga, descricao,
                          quantidade, peso_kg, volume_m3, volumes, preco_total, moeda, estado, data_prevista,
                          morada_recolha, remetente, destinatario, valor_declarado, observacoes, criado_por)
  values (v_sim.empresa_destinatario_id, v_sim.cliente_id, v_sim.id, v_prop, v_sim.origem, v_sim.destino,
          v_sim.tipo_carga, v_sim.descricao, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3, v_sim.volumes,
          v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), 'aprovacao', v_sim.data_prevista,
          v_sim.morada_recolha, v_sim.remetente, v_sim.destinatario, v_sim.valor_declarado, v_sim.observacoes, auth.uid())
  returning * into v_enc;

  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id)
    values (v_enc.id, v_enc.empresa_id, null, 'aprovacao', 'Simulação aceite pelo prestador', auth.uid());
  insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v_sim.cliente_id, 'simulacao_aceite', 'O prestador aceitou o seu pedido',
            'Encomenda ' || v_enc.codigo || ' criada e a aguardar aprovação operacional.', 'encomendas', v_enc.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_enc.empresa_id, auth.uid(), private.meu_papel()::text, 'aceitar_simulacao', 'simulacoes', v_sim.id::text,
            jsonb_build_object('encomenda', v_enc.codigo, 'preco', v_preco));
  return v_enc;
end $$;
revoke execute on function public.aceitar_simulacao(uuid, numeric) from public, anon;
grant execute on function public.aceitar_simulacao(uuid, numeric) to authenticated;

-- Lista de simulações para a administração da plataforma (inclui rascunhos e nome do cliente/prestador).
create or replace function public.simulacoes_administracao(p_limite int default 50)
returns table (id uuid, codigo text, estado text, origem text, destino text, tipo_carga text, volume_m3 numeric, peso_kg numeric,
               preco_estimado numeric, cliente text, cliente_email text, prestador text, created_at timestamptz, enviada_em timestamptz)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  return query
    select s.id, s.codigo::text, s.estado::text, s.origem, s.destino, s.tipo_carga, s.volume_m3, s.peso_kg, s.preco_estimado,
           c.nome::text, c.email::text, e.nome::text, s.created_at, s.enviada_em
      from simulacoes s left join clientes c on c.id = s.cliente_id left join empresas e on e.id = s.empresa_destinatario_id
     order by s.created_at desc limit least(greatest(coalesce(p_limite, 50), 1), 200);
end $$;
revoke execute on function public.simulacoes_administracao(int) from public, anon;
grant execute on function public.simulacoes_administracao(int) to authenticated;


-- ===== 00135_equipa_e_pedidos_admin.sql =====
-- v61 — Equipa da plataforma (funcionários Elolog que gerem o portal) e pedidos registados pela administração
-- em nome de clientes que contactam a Elolog (telefone, email, balcão), com escolha do prestador.

-- 1. Equipa da plataforma ------------------------------------------------------------------------------------
alter table administradores_plataforma
  add column if not exists email text,
  add column if not exists papel text not null default 'admin',
  add column if not exists ativo boolean not null default true,
  add column if not exists criado_por uuid;
do $$ begin
  alter table administradores_plataforma add constraint administradores_plataforma_papel_chk check (papel in ('admin','operador','apoio'));
exception when duplicate_object then null; end $$;
update administradores_plataforma a set email = u.email from auth.users u where u.id = a.user_id and a.email is null;

create or replace function private.e_admin_plataforma() returns boolean language sql stable security definer set search_path to 'public' as $$
  select private.mfa_ok() and exists (select 1 from administradores_plataforma where user_id = auth.uid() and ativo)
$$;

-- Lista da equipa (qualquer membro ativo pode ver).
create or replace function public.equipa_plataforma()
returns table (user_id uuid, nome text, email text, papel text, ativo boolean, created_at timestamptz, sou_eu boolean)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  return query select a.user_id, a.nome, a.email, a.papel, a.ativo, a.created_at, a.user_id = auth.uid()
                 from administradores_plataforma a order by a.ativo desc, a.nome;
end $$;
revoke execute on function public.equipa_plataforma() from public, anon;
grant execute on function public.equipa_plataforma() to authenticated;

-- Funções só para a Edge Function «gerir-equipa» (chave de serviço).
create or replace function public.servico_equipa_pode_gerir(p_user uuid) returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from administradores_plataforma where user_id = p_user and ativo and papel = 'admin')
$$;
create or replace function public.servico_equipa_criar(p_user uuid, p_nome text, p_email text, p_papel text, p_autor uuid)
returns administradores_plataforma language plpgsql security definer set search_path to 'public' as $$
declare r administradores_plataforma;
begin
  if not public.servico_equipa_pode_gerir(p_autor) then raise exception 'Só um administrador da plataforma pode criar funcionários.'; end if;
  if p_papel not in ('admin','operador','apoio') then raise exception 'Função inválida.'; end if;
  insert into administradores_plataforma (user_id, nome, email, papel, ativo, criado_por)
    values (p_user, left(trim(p_nome), 120), lower(trim(p_email)), p_papel, true, p_autor) returning * into r;
  insert into auditoria (user_id, papel, acao, entidade, entidade_id, depois)
    values (p_autor, 'admin_plataforma', 'criar_funcionario_plataforma', 'administradores_plataforma', p_user::text, jsonb_build_object('papel', p_papel, 'email', r.email));
  return r;
end $$;
create or replace function public.servico_equipa_alterar(p_alvo uuid, p_ativo boolean, p_papel text, p_autor uuid)
returns administradores_plataforma language plpgsql security definer set search_path to 'public' as $$
declare r administradores_plataforma;
begin
  if not public.servico_equipa_pode_gerir(p_autor) then raise exception 'Só um administrador da plataforma pode alterar a equipa.'; end if;
  if p_alvo = p_autor then raise exception 'Não pode alterar o seu próprio acesso.'; end if;
  if p_papel is not null and p_papel not in ('admin','operador','apoio') then raise exception 'Função inválida.'; end if;
  update administradores_plataforma set ativo = coalesce(p_ativo, ativo), papel = coalesce(p_papel, papel) where user_id = p_alvo returning * into r;
  if not found then raise exception 'Funcionário inexistente.'; end if;
  if not exists (select 1 from administradores_plataforma where ativo and papel = 'admin') then raise exception 'Tem de existir pelo menos um administrador ativo.'; end if;
  insert into auditoria (user_id, papel, acao, entidade, entidade_id, depois)
    values (p_autor, 'admin_plataforma', 'alterar_funcionario_plataforma', 'administradores_plataforma', p_alvo::text, jsonb_build_object('ativo', r.ativo, 'papel', r.papel));
  return r;
end $$;
revoke execute on function public.servico_equipa_pode_gerir(uuid), public.servico_equipa_criar(uuid,text,text,text,uuid), public.servico_equipa_alterar(uuid,boolean,text,uuid) from public, anon, authenticated;
grant execute on function public.servico_equipa_pode_gerir(uuid), public.servico_equipa_criar(uuid,text,text,text,uuid), public.servico_equipa_alterar(uuid,boolean,text,uuid) to service_role;

-- 2. Pedidos registados pela administração --------------------------------------------------------------------
alter table simulacoes alter column cliente_id drop not null;
alter table simulacoes add column if not exists registado_por uuid, add column if not exists canal text not null default 'cliente';
do $$ begin
  alter table simulacoes add constraint simulacoes_canal_chk check (canal in ('cliente','telefone','email','balcao','outro'));
exception when duplicate_object then null; end $$;

-- Clientes registados (para escolher no formulário).
create or replace function public.clientes_administracao(p_texto text default null)
returns table (id uuid, nome text, email text, telefone text, nif text, morada text)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  return query select c.id, c.nome, c.email, c.telefone, c.nif, c.morada from clientes c
    where p_texto is null or c.nome ilike '%' || p_texto || '%' or c.email ilike '%' || p_texto || '%' or c.telefone ilike '%' || p_texto || '%'
    order by c.nome limit 20;
end $$;
revoke execute on function public.clientes_administracao(text) from public, anon;
grant execute on function public.clientes_administracao(text) to authenticated;

-- Regista o pedido e envia-o ao prestador escolhido. O preço vem da tarifa do prestador ou do valor
-- combinado com o cliente (p_preco). Sem nenhum dos dois, segue como pedido de cotação.
create or replace function public.admin_registar_pedido(p_dados jsonb, p_empresa uuid, p_preco numeric default null)
returns simulacoes language plpgsql security definer set search_path to 'public' as $$
declare v_sim simulacoes; v_t tarifas; v_preco numeric; v_cli uuid; v_rem jsonb;
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  if coalesce(trim(p_dados->>'origem'),'') = '' or coalesce(trim(p_dados->>'destino'),'') = '' then raise exception 'Indique a origem e o destino.'; end if;
  if not exists (select 1 from empresas_disponiveis e where e.id = p_empresa) then raise exception 'Este prestador não está disponível.'; end if;
  if p_preco is not null and (p_preco <= 0 or p_preco > 10000000) then raise exception 'Preço inválido.'; end if;
  v_cli := nullif(p_dados->>'cliente_id','')::uuid;
  if v_cli is not null and not exists (select 1 from clientes where id = v_cli) then raise exception 'Cliente inexistente.'; end if;
  v_rem := coalesce(p_dados->'remetente', '{}'::jsonb);
  if v_cli is null and coalesce(trim(v_rem->>'nome'),'') = '' then raise exception 'Indique o cliente (nome e contacto).'; end if;
  if v_cli is null and coalesce(trim(v_rem->>'telefone'),'') = '' and coalesce(trim(v_rem->>'email'),'') = '' then raise exception 'Indique o telefone ou o email do cliente.'; end if;

  insert into simulacoes (cliente_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes, recolha_na_morada,
                          recolha_distancia_km, data_prevista, morada_recolha, remetente, destinatario, valor_declarado, observacoes, registado_por, canal)
  values (v_cli, left(trim(p_dados->>'origem'),120), left(trim(p_dados->>'destino'),120), nullif(p_dados->>'tipo_carga',''), left(p_dados->>'descricao',500),
          coalesce((p_dados->>'quantidade')::int, 1), coalesce((p_dados->>'peso_kg')::numeric, 0), coalesce((p_dados->>'volume_m3')::numeric, 0),
          coalesce(p_dados->'volumes', '[]'::jsonb), coalesce((p_dados->>'recolha')::boolean, false), nullif(p_dados->>'km','')::numeric,
          nullif(p_dados->>'data_prevista','')::date, nullif(p_dados->>'morada_recolha',''), v_rem, coalesce(p_dados->'destinatario','{}'::jsonb),
          nullif(p_dados->>'valor_declarado','')::numeric, left(p_dados->>'observacoes',1000), auth.uid(), coalesce(nullif(p_dados->>'canal',''),'telefone'))
  returning * into v_sim;

  v_t := private.tarifa_aplicavel(p_empresa, v_sim.origem, v_sim.destino, v_sim.tipo_carga);
  if v_t.id is not null then
    v_preco := private.preco_com_tarifa(v_t, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3)
               + case when v_sim.recolha_na_morada then round(coalesce(v_sim.recolha_distancia_km, 0) * private.custo_recolha_por_km(), 2) else 0 end;
  end if;
  v_preco := coalesce(round(p_preco, 2), v_preco);

  update simulacoes set estado = 'enviada', empresa_destinatario_id = p_empresa, enviada_em = now(), preco_estimado = v_preco,
         moeda_estimada = coalesce(v_t.moeda, 'EUR'), tarifa_estimada_id = v_t.id where id = v_sim.id returning * into v_sim;
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (p_empresa, 'nova_simulacao', case when v_preco is null then 'Novo pedido de cotação (Elolog)' else 'Novo pedido registado pela Elolog' end,
            v_sim.origem || ' → ' || v_sim.destino || coalesce(' · ' || (v_rem->>'nome'), ''), 'simulacoes', v_sim.id);
  if v_cli is not null then
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (v_cli, 'pedido_registado', 'A Elolog registou o seu pedido', v_sim.codigo || ' · ' || v_sim.origem || ' → ' || v_sim.destino, 'simulacoes', v_sim.id);
  end if;
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (p_empresa, auth.uid(), 'admin_plataforma', 'admin_registar_pedido', 'simulacoes', v_sim.id::text,
            jsonb_build_object('preco', v_preco, 'preco_combinado', p_preco is not null, 'canal', v_sim.canal, 'cliente', v_cli));
  return v_sim;
end $$;
revoke execute on function public.admin_registar_pedido(jsonb, uuid, numeric) from public, anon;
grant execute on function public.admin_registar_pedido(jsonb, uuid, numeric) to authenticated;

-- 3. Aceitar um pedido sem cliente registado avisa a administração (que contacta o cliente).
create or replace function public.aceitar_simulacao(p_simulacao uuid, p_preco numeric default null)
returns encomendas language plpgsql security definer set search_path to 'public' as $$
declare v_sim simulacoes; v_enc encomendas; v_prop uuid; v_preco numeric;
begin
  if private.minha_empresa() is null or not private.papel_em(array['admin_empresa','operador']) then
    raise exception 'Sem permissão para aceitar simulações.'; end if;
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.empresa_destinatario_id is distinct from private.minha_empresa() then raise exception 'Simulação inexistente.'; end if;
  if v_sim.estado not in ('enviada', 'respondida') then raise exception 'A simulação já não está disponível (%).', v_sim.estado; end if;
  v_preco := coalesce(p_preco, v_sim.preco_estimado);
  if v_preco is null or v_preco <= 0 then raise exception 'Indique o preço para este pedido de cotação.'; end if;
  if v_preco > 10000000 then raise exception 'Preço inválido.'; end if;
  v_preco := round(v_preco, 2);

  update propostas set estado = 'cancelada', respondida_em = now()
   where simulacao_id = v_sim.id and empresa_id = v_sim.empresa_destinatario_id and estado = 'enviada';
  insert into propostas (simulacao_id, empresa_id, tarifa_id, preco, moeda, estado, mensagem, criado_por, respondida_em)
  values (v_sim.id, v_sim.empresa_destinatario_id, v_sim.tarifa_estimada_id, v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), 'aceite',
          case when p_preco is not null and v_sim.preco_estimado is distinct from v_preco then 'Aceite com preço indicado pelo prestador.'
               else 'Aceite ao preço calculado pelas tarifas do prestador.' end, auth.uid(), now())
  returning id into v_prop;
  update simulacoes set estado = 'convertida', preco_estimado = v_preco where id = v_sim.id;

  insert into encomendas (empresa_id, cliente_id, simulacao_id, proposta_id, origem, destino, tipo_carga, descricao,
                          quantidade, peso_kg, volume_m3, volumes, preco_total, moeda, estado, data_prevista,
                          morada_recolha, remetente, destinatario, valor_declarado, observacoes, criado_por)
  values (v_sim.empresa_destinatario_id, v_sim.cliente_id, v_sim.id, v_prop, v_sim.origem, v_sim.destino,
          v_sim.tipo_carga, v_sim.descricao, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3, v_sim.volumes,
          v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), 'aprovacao', v_sim.data_prevista,
          v_sim.morada_recolha, v_sim.remetente, v_sim.destinatario, v_sim.valor_declarado, v_sim.observacoes, auth.uid())
  returning * into v_enc;

  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id)
    values (v_enc.id, v_enc.empresa_id, null, 'aprovacao', 'Simulação aceite pelo prestador', auth.uid());
  insert into notificacoes (user_id, para_plataforma, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v_sim.cliente_id, v_sim.cliente_id is null, 'simulacao_aceite',
            case when v_sim.cliente_id is null then 'Prestador aceitou um pedido registado pela Elolog' else 'O prestador aceitou o seu pedido' end,
            'Encomenda ' || v_enc.codigo || ' criada' || case when v_sim.cliente_id is null then '. Informe o cliente: ' || coalesce(v_sim.remetente->>'nome','') || ' ' || coalesce(v_sim.remetente->>'telefone','') else ' e a aguardar aprovação operacional.' end,
            'encomendas', v_enc.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_enc.empresa_id, auth.uid(), private.meu_papel()::text, 'aceitar_simulacao', 'simulacoes', v_sim.id::text,
            jsonb_build_object('encomenda', v_enc.codigo, 'preco', v_preco));
  return v_enc;
end $$;
revoke execute on function public.aceitar_simulacao(uuid, numeric) from public, anon;
grant execute on function public.aceitar_simulacao(uuid, numeric) to authenticated;


-- 4. Lista de simulações da administração: inclui o canal e o nome de contacto quando não há conta de cliente.
drop function if exists public.simulacoes_administracao(int);
create function public.simulacoes_administracao(p_limite int default 50)
returns table (id uuid, codigo text, estado text, origem text, destino text, tipo_carga text, volume_m3 numeric, peso_kg numeric,
               preco_estimado numeric, cliente text, cliente_email text, prestador text, canal text, created_at timestamptz, enviada_em timestamptz)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  return query
    select s.id, s.codigo::text, s.estado::text, s.origem, s.destino, s.tipo_carga, s.volume_m3, s.peso_kg, s.preco_estimado,
           coalesce(c.nome, s.remetente->>'nome')::text, coalesce(c.email, s.remetente->>'email')::text, e.nome::text, s.canal, s.created_at, s.enviada_em
      from simulacoes s left join clientes c on c.id = s.cliente_id left join empresas e on e.id = s.empresa_destinatario_id
     order by s.created_at desc limit least(greatest(coalesce(p_limite, 50), 1), 200);
end $$;
revoke execute on function public.simulacoes_administracao(int) from public, anon;
grant execute on function public.simulacoes_administracao(int) to authenticated;


select private.agendar_tarefas('https://wcggcpdiswbzrdpwgdpb.supabase.co');

-- ===== Permissões da API (projetos Supabase novos não dão acesso automático às tabelas e funções) =====
grant select, insert, update, delete, references, trigger, truncate on all tables in schema public to anon, authenticated, service_role;
grant usage, select, update on all sequences in schema public to anon, authenticated, service_role;
grant execute on all functions in schema public to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant select, insert, update, delete, references, trigger, truncate on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant usage, select, update on sequences to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated, service_role;
grant usage on schema private to authenticated, service_role;
do $p$ begin execute $s$grant execute on function private.proximo_codigo(text) to authenticated, service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.transitar_encomenda(uuid, estado_encomenda, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.aceitar_proposta(uuid) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.decidir_empresa(uuid, boolean, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.transitar_encomenda(uuid, estado_encomenda, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.aceitar_proposta(uuid) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.decidir_empresa(uuid, boolean, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function private.e_admin_plataforma(), private.minha_empresa(), private.meu_papel(), private.papel_em(text[]), private.tem_permissao(text), private.cliente_visivel(uuid), private.ve_ticket(uuid) to authenticated, service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on all tables in schema public from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on all sequences in schema public from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke insert, update, delete on auditoria, encomenda_historico, encomenda_transicoes from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke update on empresas from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant update (nome_comercial, telefone, morada, codigo_postal, cidade) on empresas to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke update on funcionarios from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant update (nome, papel, ativo, numero_interno, veiculo_habitual, permissoes) on funcionarios to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke update on encomendas from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant update (cliente_nome, cliente_nif, cliente_telefone, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes, preco_total, data_prevista, assinatura_documento_id, pin_validacao_hash) on encomendas to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke update on notificacoes from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on empresas_disponiveis from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function private.norm(text), private.custo_recolha_por_km(), private.tarifa_aplicavel(uuid, text, text, text, text), private.preco_com_tarifa(tarifas, int, numeric, numeric) from public;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke insert, update on simulacoes from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant insert (cliente_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes, recolha_na_morada, recolha_distancia_km) on simulacoes to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant update (origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes, recolha_na_morada, recolha_distancia_km) on simulacoes to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.calcular_propostas(text, text, text, int, numeric, numeric, numeric, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.enviar_simulacao(uuid, uuid) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.cancelar_simulacao(uuid) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.calcular_propostas(text, text, text, int, numeric, numeric, numeric, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.enviar_simulacao(uuid, uuid) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.cancelar_simulacao(uuid) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant insert (data_prevista, morada_recolha, remetente, destinatario, valor_declarado, observacoes) on simulacoes to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant update (data_prevista, morada_recolha, remetente, destinatario, valor_declarado, observacoes) on simulacoes to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant update (morada_recolha, destinatario, valor_declarado, observacoes) on encomendas to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function private.verificar_empresa(text, text, text) from public;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.validar_empresa(text, text, text) to anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.abrir_sessao_empresa(text, text, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.abrir_sessao_empresa(text, text, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.terminar_sessao_empresa() from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.terminar_sessao_empresa() to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.sessao_empresa_ativa() to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.aceitar_simulacao(uuid), public.recusar_simulacao(uuid, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.aceitar_simulacao(uuid), public.recusar_simulacao(uuid, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.transitar_encomenda(uuid, estado_encomenda, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.transitar_encomenda(uuid, estado_encomenda, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke update on funcionarios from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.servico_limite(text, int, int), public.servico_utilizador_existe(text), public.servico_registar_prestador(uuid, text, text, text, text, text, text, text, text, text, text), public.servico_admin_empresa(uuid), public.servico_verificar_limite_funcionarios(uuid), public.servico_criar_funcionario(uuid, uuid, uuid, text, text, papel_funcionario, text, text, text, text, text[], boolean), public.servico_obter_funcionario(uuid, uuid), public.servico_atualizar_funcionario(uuid, uuid, uuid, jsonb), public.servico_preparar_remocao(uuid, uuid, uuid), public.servico_auditar(uuid, uuid, text, text, jsonb), public.servico_encerrar_sessoes(uuid) from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.servico_limite(text, int, int), public.servico_utilizador_existe(text), public.servico_registar_prestador(uuid, text, text, text, text, text, text, text, text, text, text), public.servico_admin_empresa(uuid), public.servico_verificar_limite_funcionarios(uuid), public.servico_criar_funcionario(uuid, uuid, uuid, text, text, papel_funcionario, text, text, text, text, text[], boolean), public.servico_obter_funcionario(uuid, uuid), public.servico_atualizar_funcionario(uuid, uuid, uuid, jsonb), public.servico_preparar_remocao(uuid, uuid, uuid), public.servico_auditar(uuid, uuid, text, text, jsonb), public.servico_encerrar_sessoes(uuid) to service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function private.permissoes_validas(text[]), private.validar_alteracao_acesso(uuid, uuid, uuid, boolean) from public;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.sou_admin_plataforma() from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.sou_admin_plataforma() to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.confirmar_pagamento_subscricao(uuid, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.confirmar_pagamento_subscricao(uuid, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on emails_fila from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.servico_reservar_emails(int, int), public.servico_marcar_email(uuid, text, text, text), public.servico_emails_enviados_hoje() from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.servico_reservar_emails(int, int), public.servico_marcar_email(uuid, text, text, text), public.servico_emails_enviados_hoje() to service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function private.tipo_envia_email(text), private.destinatarios_email(notificacoes), private.enfileirar_emails() from public;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on all tables in schema public from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on all sequences in schema public from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on all functions in schema public from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.validar_empresa(text, text, text) to anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$alter default privileges for role postgres in schema public revoke all on tables from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$alter default privileges for role postgres in schema public revoke all on sequences from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$alter default privileges for role postgres in schema public revoke execute on functions from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.painel_administracao(int) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.painel_administracao(int) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on private.plataforma_config from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function private.mfa_ok() to authenticated, service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on public.empresas_disponiveis from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on public.empresa_segredos, public.sessoes_empresa, public.tentativas_gate, public.emails_fila, public.contadores from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function private.chamar_funcao(text, jsonb) from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function private.agendar_tarefas(text) from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function public.servico_segredo_cron() from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.servico_segredo_cron() to service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke insert, update, delete on faturas from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function public.registar_fatura(uuid, text, uuid) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.registar_fatura(uuid, text, uuid) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on empresa_pagamentos_config from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function public.ver_config_pagamentos(), public.guardar_config_pagamentos(text, text, text, boolean, boolean) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.ver_config_pagamentos(), public.guardar_config_pagamentos(text, text, text, boolean, boolean) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke insert, update, delete on pedidos_pagamento from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function public.servico_preparar_pedido(uuid, text, text, text), public.servico_atualizar_pedido(uuid, text, jsonb), public.servico_confirmar_pedido(text, text, numeric, text), public.servico_pedidos_mbway_pendentes() from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.servico_preparar_pedido(uuid, text, text, text), public.servico_atualizar_pedido(uuid, text, jsonb), public.servico_confirmar_pedido(text, text, numeric, text), public.servico_pedidos_mbway_pendentes() to service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke insert, update, delete on navios_posicoes from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function public.servico_navios_seguidos() from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.servico_navios_seguidos() to service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.aceitar_simulacao(uuid, numeric) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.aceitar_simulacao(uuid, numeric) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.simulacoes_administracao(int) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.simulacoes_administracao(int) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.equipa_plataforma() from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.equipa_plataforma() to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.servico_equipa_pode_gerir(uuid), public.servico_equipa_criar(uuid,text,text,text,uuid), public.servico_equipa_alterar(uuid,boolean,text,uuid) from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.servico_equipa_pode_gerir(uuid), public.servico_equipa_criar(uuid,text,text,text,uuid), public.servico_equipa_alterar(uuid,boolean,text,uuid) to service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.clientes_administracao(text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.clientes_administracao(text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.admin_registar_pedido(jsonb, uuid, numeric) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.admin_registar_pedido(jsonb, uuid, numeric) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.aceitar_simulacao(uuid, numeric) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.aceitar_simulacao(uuid, numeric) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.simulacoes_administracao(int) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.simulacoes_administracao(int) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;

-- ===== 00136_whatsapp.sql =====
-- v66 — Assistente ELO no WhatsApp (WhatsApp Business Cloud API da Meta).
-- A Edge Function «whatsapp-elo» recebe as mensagens e responde; estas funções só correm com a chave de serviço.

create table if not exists whatsapp_conversas (
  telefone     text primary key,                 -- número do cliente, só dígitos, com indicativo
  nome         text,
  passo        text,
  dados        jsonb not null default '{}',
  humano_desde timestamptz,
  mensagens    int not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
alter table whatsapp_conversas enable row level security;
revoke all on whatsapp_conversas from anon, authenticated;

-- Estado de uma encomenda pedido por WhatsApp: só responde se o número de quem pergunta for o do cliente,
-- o da encomenda ou o do destinatário (últimos 9 dígitos). Caso contrário não revela nada.
create or replace function public.servico_whatsapp_estado(p_codigo text, p_telefone text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e encomendas; v_tel text := right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 9); v_ok boolean;
begin
  if length(v_tel) < 9 then return jsonb_build_object('autorizado', false); end if;
  select * into e from encomendas where upper(codigo) = upper(trim(p_codigo));
  if not found then return jsonb_build_object('autorizado', false); end if;
  select v_tel in (
           right(regexp_replace(coalesce(e.cliente_telefone, ''), '\D', '', 'g'), 9),
           right(regexp_replace(coalesce(e.destinatario->>'telefone', ''), '\D', '', 'g'), 9),
           right(regexp_replace(coalesce((select c.telefone from clientes c where c.id = e.cliente_id), ''), '\D', '', 'g'), 9))
    into v_ok;
  if not coalesce(v_ok, false) then return jsonb_build_object('autorizado', false); end if;
  return jsonb_build_object('autorizado', true, 'codigo', e.codigo, 'estado', e.estado::text, 'origem', e.origem,
    'destino', e.destino, 'data_prevista', e.data_prevista, 'atualizado', e.updated_at,
    'prestador', (select coalesce(m.nome_comercial, m.nome) from empresas m where m.id = e.empresa_id));
end $$;

-- Pedido de atendimento humano: avisa a administração (notificação + email) e marca a conversa.
create or replace function public.servico_whatsapp_pedido_humano(p_telefone text, p_nome text, p_mensagem text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into notificacoes (para_plataforma, tipo, titulo, corpo)
  values (true, 'apoio', 'Pedido de contacto por WhatsApp',
          left(coalesce(nullif(trim(p_nome), ''), 'Sem nome') || ' · +' || regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g')
               || coalesce(' · «' || nullif(trim(p_mensagem), '') || '»', ''), 480));
  update whatsapp_conversas set humano_desde = now(), updated_at = now() where telefone = regexp_replace(p_telefone, '\D', '', 'g');
end $$;

revoke all on function public.servico_whatsapp_estado(text, text), public.servico_whatsapp_pedido_humano(text, text, text) from public, anon, authenticated;
grant execute on function public.servico_whatsapp_estado(text, text), public.servico_whatsapp_pedido_humano(text, text, text) to service_role;
grant select, insert, update on whatsapp_conversas to service_role;

-- ===== 00137_caixas_email.sql =====
-- v67 — Painel de email: caixas de correio (IMAP/SMTP) ligadas à plataforma.
-- Só o administrador da plataforma (caixas da Elolog, empresa_id nulo) e o administrador de cada prestador
-- (caixas da sua empresa) as podem usar. A palavra-passe da caixa fica encriptada no cofre (Vault) e só a
-- Edge Function «email-caixa» (chave de serviço) a lê. O navegador nunca a recebe.

create table if not exists caixas_email (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid references empresas(id) on delete cascade,   -- nulo = caixa da Elolog (administração)
  email       text not null check (length(email) <= 254 and email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$'),
  nome        text not null default '',
  imap_host   text not null check (imap_host ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
  imap_porta  int  not null default 993 check (imap_porta = 993),
  smtp_host   text not null check (smtp_host ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
  smtp_porta  int  not null default 465 check (smtp_porta = 465),
  utilizador  text not null check (length(utilizador) between 1 and 254),
  segredo_id  uuid,                                               -- vault.secrets.id
  criado_por  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists caixas_email_unica on caixas_email (coalesce(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(email));
alter table caixas_email enable row level security;
revoke all on caixas_email from anon, authenticated;

-- Quem pode usar as caixas de um âmbito (empresa nula = Elolog).
create or replace function private.email_pode(p_user uuid, p_empresa uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case when p_empresa is null
    then exists (select 1 from administradores_plataforma where user_id = p_user and ativo and papel = 'admin')
    else exists (select 1 from funcionarios where id = p_user and ativo and papel = 'admin_empresa' and empresa_id = p_empresa) end
$$;

-- Ao apagar a caixa (ou a empresa), apaga também a palavra-passe do cofre.
create or replace function private.email_limpar_segredo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.segredo_id is not null then delete from vault.secrets where id = old.segredo_id; end if;
  return old;
end $$;
create or replace trigger caixas_email_limpar after delete on caixas_email for each row execute function private.email_limpar_segredo();

-- Âmbitos a que o utilizador tem acesso: {"plataforma": bool, "empresa": uuid|null}.
create or replace function public.servico_email_acesso(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('plataforma', private.email_pode(p_user, null),
    'empresa', (select empresa_id from funcionarios where id = p_user and ativo and papel = 'admin_empresa'))
$$;

-- Caixas visíveis (sem a palavra-passe).
create or replace function public.servico_email_caixas(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'email', email, 'nome', nome, 'imap_host', imap_host, 'imap_porta', imap_porta,
    'smtp_host', smtp_host, 'smtp_porta', smtp_porta, 'utilizador', utilizador, 'elolog', empresa_id is null, 'tem_senha', segredo_id is not null)
    order by empresa_id nulls first, email), '[]'::jsonb)
  from caixas_email c where private.email_pode(p_user, c.empresa_id)
$$;

-- Criar ou alterar uma caixa. p_senha nula mantém a atual. A Edge Function testa a ligação antes de chamar.
create or replace function public.servico_email_gravar(p_user uuid, p_id uuid, p_dados jsonb, p_senha text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r caixas_email; v_emp uuid; v_seg uuid;
begin
  if p_id is not null then
    select * into r from caixas_email where id = p_id;
    if not found or not private.email_pode(p_user, r.empresa_id) then raise exception 'Caixa de email inexistente.'; end if;
    v_emp := r.empresa_id;
  else
    if private.email_pode(p_user, null) and coalesce(p_dados->>'ambito', 'elolog') = 'elolog' then v_emp := null;
    else select empresa_id into v_emp from funcionarios where id = p_user and ativo and papel = 'admin_empresa';
      if v_emp is null then raise exception 'Sem permissão para configurar caixas de email.'; end if; end if;
    if (select count(*) from caixas_email where empresa_id is not distinct from v_emp) >= 5 then raise exception 'Máximo de 5 caixas de email.'; end if;
    if p_senha is null then raise exception 'Indique a palavra-passe da caixa.'; end if;
  end if;
  insert into caixas_email as c (id, empresa_id, email, nome, imap_host, imap_porta, smtp_host, smtp_porta, utilizador, criado_por)
  values (coalesce(p_id, gen_random_uuid()), v_emp, lower(trim(p_dados->>'email')), left(coalesce(trim(p_dados->>'nome'), ''), 80),
          lower(trim(p_dados->>'imap_host')), 993, lower(trim(p_dados->>'smtp_host')), 465, trim(p_dados->>'utilizador'), p_user)
  on conflict (id) do update set email = excluded.email, nome = excluded.nome, imap_host = excluded.imap_host,
    smtp_host = excluded.smtp_host, utilizador = excluded.utilizador, updated_at = now()
  returning * into r;
  if p_senha is not null then
    if r.segredo_id is null then
      v_seg := vault.create_secret(p_senha, 'email_caixa_' || r.id::text, 'Palavra-passe da caixa ' || r.email);
      update caixas_email set segredo_id = v_seg where id = r.id;
    else perform vault.update_secret(r.segredo_id, p_senha); end if;
  end if;
  return jsonb_build_object('id', r.id, 'email', r.email);
exception when unique_violation then raise exception 'Essa caixa de email já está configurada.';
end $$;

-- Dados de ligação com a palavra-passe (só para a Edge Function).
create or replace function public.servico_email_credenciais(p_user uuid, p_caixa uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r caixas_email; v_senha text;
begin
  select * into r from caixas_email where id = p_caixa;
  if not found or not private.email_pode(p_user, r.empresa_id) then raise exception 'Caixa de email inexistente.'; end if;
  select decrypted_secret into v_senha from vault.decrypted_secrets where id = r.segredo_id;
  return jsonb_build_object('elolog', r.empresa_id is null, 'email', r.email, 'nome', r.nome, 'imap_host', r.imap_host, 'imap_porta', r.imap_porta,
    'smtp_host', r.smtp_host, 'smtp_porta', r.smtp_porta, 'utilizador', r.utilizador, 'senha', v_senha);
end $$;

create or replace function public.servico_email_remover(p_user uuid, p_caixa uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_emp uuid;
begin
  select empresa_id into v_emp from caixas_email where id = p_caixa;
  if not found or not private.email_pode(p_user, v_emp) then raise exception 'Caixa de email inexistente.'; end if;
  delete from caixas_email where id = p_caixa;
end $$;

revoke all on function private.email_pode(uuid, uuid), public.servico_email_acesso(uuid), public.servico_email_caixas(uuid),
  public.servico_email_gravar(uuid, uuid, jsonb, text), public.servico_email_credenciais(uuid, uuid), public.servico_email_remover(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.servico_email_acesso(uuid), public.servico_email_caixas(uuid), public.servico_email_gravar(uuid, uuid, jsonb, text),
  public.servico_email_credenciais(uuid, uuid), public.servico_email_remover(uuid, uuid) to service_role;
grant select, insert, update, delete on caixas_email to service_role;

-- ===== 00138_acessos_email_chat.sql =====
-- v70 — (1) Acessos às caixas de email dados pelo administrador a funcionários; (2) chat interno da equipa com hierarquia.

-- ===== 1. Acessos às caixas de email =====
create table if not exists caixas_email_acesso (
  caixa_id      uuid not null references caixas_email(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  concedido_por uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  primary key (caixa_id, user_id)
);
alter table caixas_email_acesso enable row level security;
revoke all on caixas_email_acesso from anon, authenticated;

-- Pode usar (ler, responder) a caixa: o administrador do âmbito ou um funcionário ativo desse âmbito com acesso concedido.
create or replace function private.email_usar(p_user uuid, p_caixa uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from caixas_email c where c.id = p_caixa and (private.email_pode(p_user, c.empresa_id)
    or (exists (select 1 from caixas_email_acesso a where a.caixa_id = c.id and a.user_id = p_user)
        and case when c.empresa_id is null then exists (select 1 from administradores_plataforma where user_id = p_user and ativo)
                 else exists (select 1 from funcionarios where id = p_user and ativo and empresa_id = c.empresa_id) end)))
$$;

create or replace function public.servico_email_acesso(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('plataforma', private.email_pode(p_user, null),
    'empresa', (select empresa_id from funcionarios where id = p_user and ativo and papel = 'admin_empresa'),
    'delegado', exists (select 1 from caixas_email_acesso a where a.user_id = p_user and private.email_usar(p_user, a.caixa_id)))
$$;

create or replace function public.servico_email_caixas(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'email', email, 'nome', nome, 'imap_host', imap_host, 'imap_porta', imap_porta,
    'smtp_host', smtp_host, 'smtp_porta', smtp_porta, 'utilizador', utilizador, 'elolog', empresa_id is null, 'tem_senha', segredo_id is not null,
    'gerir', private.email_pode(p_user, c.empresa_id)) order by empresa_id nulls first, email), '[]'::jsonb)
  from caixas_email c where private.email_usar(p_user, c.id)
$$;

create or replace function public.servico_email_credenciais(p_user uuid, p_caixa uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r caixas_email; v_senha text;
begin
  select * into r from caixas_email where id = p_caixa;
  if not found or not private.email_usar(p_user, p_caixa) then raise exception 'Caixa de email inexistente.'; end if;
  select decrypted_secret into v_senha from vault.decrypted_secrets where id = r.segredo_id;
  return jsonb_build_object('elolog', r.empresa_id is null, 'gerir', private.email_pode(p_user, r.empresa_id), 'email', r.email, 'nome', r.nome,
    'imap_host', r.imap_host, 'imap_porta', r.imap_porta, 'smtp_host', r.smtp_host, 'smtp_porta', r.smtp_porta, 'utilizador', r.utilizador, 'senha', v_senha);
end $$;

-- Funcionários do âmbito da caixa e se já têm acesso (só para quem gere a caixa).
create or replace function public.servico_email_acessos(p_user uuid, p_caixa uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid;
begin
  select empresa_id into v_emp from caixas_email where id = p_caixa;
  if not found or not private.email_pode(p_user, v_emp) then raise exception 'Só o administrador pode dar acessos a esta caixa.'; end if;
  return coalesce((select jsonb_agg(x order by x->>'nome') from (
      select jsonb_build_object('user_id', a.user_id, 'nome', a.nome, 'email', a.email, 'papel', a.papel,
        'acesso', exists (select 1 from caixas_email_acesso g where g.caixa_id = p_caixa and g.user_id = a.user_id)) x
        from administradores_plataforma a where v_emp is null and a.ativo and a.user_id <> p_user
      union all
      select jsonb_build_object('user_id', f.id, 'nome', f.nome, 'email', f.email, 'papel', f.papel::text,
        'acesso', exists (select 1 from caixas_email_acesso g where g.caixa_id = p_caixa and g.user_id = f.id))
        from funcionarios f where v_emp is not null and f.empresa_id = v_emp and f.ativo and f.id <> p_user) t), '[]'::jsonb);
end $$;

create or replace function public.servico_email_conceder(p_user uuid, p_caixa uuid, p_alvo uuid, p_sim boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_emp uuid;
begin
  select empresa_id into v_emp from caixas_email where id = p_caixa;
  if not found or not private.email_pode(p_user, v_emp) then raise exception 'Só o administrador pode dar acessos a esta caixa.'; end if;
  if p_sim then
    if not (case when v_emp is null then exists (select 1 from administradores_plataforma where user_id = p_alvo and ativo)
                 else exists (select 1 from funcionarios where id = p_alvo and ativo and empresa_id = v_emp) end) then
      raise exception 'Esse funcionário não pertence a esta equipa.'; end if;
    insert into caixas_email_acesso (caixa_id, user_id, concedido_por) values (p_caixa, p_alvo, p_user) on conflict do nothing;
  else
    delete from caixas_email_acesso where caixa_id = p_caixa and user_id = p_alvo;
  end if;
end $$;

revoke all on function private.email_usar(uuid, uuid), public.servico_email_acessos(uuid, uuid), public.servico_email_conceder(uuid, uuid, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.servico_email_acessos(uuid, uuid), public.servico_email_conceder(uuid, uuid, uuid, boolean) to service_role;
grant select, insert, update, delete on caixas_email_acesso to service_role;

-- ===== 2. Chat interno da equipa =====
create table if not exists chat_mensagens (
  id         uuid primary key default gen_random_uuid(),
  de         uuid not null references auth.users(id) on delete cascade,
  para       uuid not null references auth.users(id) on delete cascade,
  texto      text not null check (length(texto) between 1 and 2000),
  lida_em    timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists chat_conversa on chat_mensagens (least(de, para), greatest(de, para), created_at desc);
create index if not exists chat_por_ler on chat_mensagens (para) where lida_em is null;
alter table chat_mensagens enable row level security;
revoke all on chat_mensagens from anon, authenticated;

-- Organização ('elolog' ou id da empresa), papel e nome de um funcionário ativo.
create or replace function private.chat_perfil(p_user uuid, out org text, out papel text, out nome text)
language sql stable security definer set search_path = public as $$
  select * from (select 'elolog'::text, a.papel, a.nome from administradores_plataforma a where a.user_id = p_user and a.ativo
    union all select f.empresa_id::text, f.papel::text, f.nome from funcionarios f where f.id = p_user and f.ativo) t limit 1
$$;

-- Hierarquia: na Elolog todos falam entre si; a equipa Elolog fala com o administrador de cada prestador;
-- no prestador, o administrador e os operadores falam com todos, cada função fala com a mesma função,
-- e armazém ↔ terreno (fluxo físico da carga). Financeiro não fala diretamente com terreno/armazém. Empresas diferentes nunca.
create or replace function private.chat_pode(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a <> b and coalesce((select
      (x.org = 'elolog' and y.org = 'elolog')
      or (x.org = 'elolog' and y.papel = 'admin_empresa') or (y.org = 'elolog' and x.papel = 'admin_empresa')
      or (x.org = y.org and x.org <> 'elolog' and (x.papel = y.papel or 'admin_empresa' in (x.papel, y.papel) or 'operador' in (x.papel, y.papel)
          or (least(x.papel, y.papel) = 'armazem' and greatest(x.papel, y.papel) = 'operador_terreno')))
    from private.chat_perfil(a) x, private.chat_perfil(b) y where x.org is not null and y.org is not null), false)
$$;

create or replace function public.chat_contactos()
returns table (user_id uuid, nome text, papel text, organizacao text, por_ler int, ultima text, ultima_em timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare eu uuid := auth.uid(); p record;
begin
  select * into p from private.chat_perfil(eu);
  if p.org is null then return; end if;
  return query
  with cand as (
    select a.user_id as id, a.nome, a.papel, 'Elolog'::text as org from administradores_plataforma a
      where a.ativo and (p.org = 'elolog' or p.papel = 'admin_empresa')
    union all
    select f.id, f.nome, f.papel::text, coalesce(e.nome_comercial, e.nome) from funcionarios f join empresas e on e.id = f.empresa_id
      where f.ativo and ((p.org <> 'elolog' and f.empresa_id::text = p.org) or (p.org = 'elolog' and f.papel = 'admin_empresa'))
  )
  select c.id, c.nome, c.papel, c.org,
    (select count(*)::int from chat_mensagens m where m.de = c.id and m.para = eu and m.lida_em is null),
    (select left(m.texto, 80) from chat_mensagens m where (m.de = c.id and m.para = eu) or (m.de = eu and m.para = c.id) order by m.created_at desc limit 1),
    (select max(m.created_at) from chat_mensagens m where (m.de = c.id and m.para = eu) or (m.de = eu and m.para = c.id))
  from cand c where private.chat_pode(eu, c.id)
  order by 7 desc nulls last, 2 limit 300;
end $$;

-- Últimas 60 mensagens com um contacto (marca como lidas as recebidas).
create or replace function public.chat_conversa(p_com uuid)
returns setof chat_mensagens language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid();
begin
  if not private.chat_pode(eu, p_com) and not exists (select 1 from chat_mensagens where (de = eu and para = p_com) or (de = p_com and para = eu)) then
    raise exception 'Sem permissão para falar com este funcionário.'; end if;
  update chat_mensagens set lida_em = now() where de = p_com and para = eu and lida_em is null;
  return query select * from (select * from chat_mensagens m where (m.de = eu and m.para = p_com) or (m.de = p_com and m.para = eu)
    order by m.created_at desc limit 60) t order by t.created_at;
end $$;

create or replace function public.chat_enviar(p_para uuid, p_texto text)
returns chat_mensagens language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); r chat_mensagens;
begin
  if not private.chat_pode(eu, p_para) then raise exception 'A hierarquia da equipa não permite esta conversa.'; end if;
  if length(trim(coalesce(p_texto, ''))) = 0 then raise exception 'Escreva a mensagem.'; end if;
  if (select count(*) from chat_mensagens where de = eu and created_at > now() - interval '1 minute') >= 30 then
    raise exception 'Demasiadas mensagens seguidas. Aguarde um minuto.'; end if;
  insert into chat_mensagens (de, para, texto) values (eu, p_para, left(trim(p_texto), 2000)) returning * into r;
  return r;
end $$;

create or replace function public.chat_por_ler() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from chat_mensagens where para = auth.uid() and lida_em is null
$$;

revoke all on function private.chat_perfil(uuid), private.chat_pode(uuid, uuid), public.chat_contactos(), public.chat_conversa(uuid),
  public.chat_enviar(uuid, text), public.chat_por_ler() from public, anon;
grant execute on function public.chat_contactos(), public.chat_conversa(uuid), public.chat_enviar(uuid, text), public.chat_por_ler() to authenticated;

-- ===== 00139_email_atribuicoes.sql =====
-- v70 — Encaminhar um email a um funcionário para responder (atribuição). Quem tem acesso à caixa escolhe o colega
-- adequado; esse colega vê o email em «Atribuídos», pode lê-lo e responder-lhe, mesmo sem acesso ao resto da caixa.

create table if not exists email_atribuicoes (
  id            uuid primary key default gen_random_uuid(),
  caixa_id      uuid not null references caixas_email(id) on delete cascade,
  uid           bigint not null check (uid > 0),
  de            text not null default '',
  assunto       text not null default '',
  atribuido_a   uuid not null references auth.users(id) on delete cascade,
  atribuido_por uuid references auth.users(id) on delete set null,
  nota          text check (length(nota) <= 500),
  estado        text not null default 'aberto' check (estado in ('aberto', 'respondido')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (caixa_id, uid, atribuido_a)
);
alter table email_atribuicoes enable row level security;
revoke all on email_atribuicoes from anon, authenticated;

-- Funcionário ativo do âmbito da caixa (Elolog ou a empresa da caixa).
create or replace function private.email_da_equipa(p_user uuid, p_caixa uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from caixas_email c where c.id = p_caixa and case when c.empresa_id is null
    then exists (select 1 from administradores_plataforma where user_id = p_user and ativo)
    else exists (select 1 from funcionarios where id = p_user and ativo and empresa_id = c.empresa_id) end)
$$;

-- Acesso: inclui quem só tem emails atribuídos.
create or replace function public.servico_email_acesso(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('plataforma', private.email_pode(p_user, null),
    'empresa', (select empresa_id from funcionarios where id = p_user and ativo and papel = 'admin_empresa'),
    'delegado', exists (select 1 from caixas_email_acesso a where a.user_id = p_user and private.email_usar(p_user, a.caixa_id))
             or exists (select 1 from email_atribuicoes t where t.atribuido_a = p_user and private.email_da_equipa(p_user, t.caixa_id)))
$$;

-- Credenciais (nova versão; a antiga de 2 argumentos fica sem uso): caixa inteira (email_usar) ou só a mensagem atribuída (restrito = true).
create or replace function public.servico_email_credenciais2(p_user uuid, p_caixa uuid, p_uid bigint default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r caixas_email; v_senha text; v_restrito boolean := false;
begin
  select * into r from caixas_email where id = p_caixa;
  if not found then raise exception 'Caixa de email inexistente.'; end if;
  if not private.email_usar(p_user, p_caixa) then
    if p_uid is null or not private.email_da_equipa(p_user, p_caixa)
       or not exists (select 1 from email_atribuicoes where caixa_id = p_caixa and uid = p_uid and atribuido_a = p_user) then
      raise exception 'Caixa de email inexistente.'; end if;
    v_restrito := true;
  end if;
  select decrypted_secret into v_senha from vault.decrypted_secrets where id = r.segredo_id;
  return jsonb_build_object('elolog', r.empresa_id is null, 'gerir', private.email_pode(p_user, r.empresa_id), 'restrito', v_restrito,
    'email', r.email, 'nome', r.nome, 'imap_host', r.imap_host, 'imap_porta', r.imap_porta, 'smtp_host', r.smtp_host, 'smtp_porta', r.smtp_porta,
    'utilizador', r.utilizador, 'senha', v_senha);
end $$;

-- Colegas a quem se pode encaminhar (equipa da caixa, sem o próprio).
create or replace function public.servico_email_equipa(p_user uuid, p_caixa uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid;
begin
  if not private.email_usar(p_user, p_caixa) then raise exception 'Sem acesso a esta caixa.'; end if;
  select empresa_id into v_emp from caixas_email where id = p_caixa;
  return coalesce((select jsonb_agg(x order by x->>'nome') from (
      select jsonb_build_object('user_id', a.user_id, 'nome', a.nome, 'papel', a.papel) x from administradores_plataforma a
        where v_emp is null and a.ativo and a.user_id <> p_user
      union all
      select jsonb_build_object('user_id', f.id, 'nome', f.nome, 'papel', f.papel::text) from funcionarios f
        where v_emp is not null and f.empresa_id = v_emp and f.ativo and f.id <> p_user) t), '[]'::jsonb);
end $$;

-- Encaminhar: regista a atribuição e avisa o colega no chat da equipa.
create or replace function public.servico_email_atribuir(p_user uuid, p_caixa uuid, p_uid bigint, p_alvo uuid, p_de text, p_assunto text, p_nota text)
returns void language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  if not private.email_usar(p_user, p_caixa) then raise exception 'Sem acesso a esta caixa.'; end if;
  if p_alvo = p_user or not private.email_da_equipa(p_alvo, p_caixa) then raise exception 'Escolha um colega desta equipa.'; end if;
  insert into email_atribuicoes (caixa_id, uid, de, assunto, atribuido_a, atribuido_por, nota)
  values (p_caixa, p_uid, left(coalesce(p_de, ''), 300), left(coalesce(p_assunto, ''), 300), p_alvo, p_user, nullif(left(trim(coalesce(p_nota, '')), 500), ''))
  on conflict (caixa_id, uid, atribuido_a) do update set estado = 'aberto', nota = excluded.nota, atribuido_por = excluded.atribuido_por, updated_at = now();
  select email into v_email from caixas_email where id = p_caixa;
  insert into chat_mensagens (de, para, texto) values (p_user, p_alvo, left(
    '📧 Encaminhei-lhe um email para responder (' || v_email || '): «' || coalesce(nullif(p_assunto, ''), 'sem assunto') || '» de ' || coalesce(p_de, '') ||
    coalesce(E'\nNota: ' || nullif(trim(p_nota), ''), '') || E'\nAbra Email › Atribuídos.', 2000));
end $$;

-- Emails atribuídos ao utilizador (abertos primeiro).
create or replace function public.servico_email_atribuidos(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'caixa', t.caixa_id, 'caixa_email', c.email, 'uid', t.uid, 'de', t.de, 'assunto', t.assunto,
      'nota', t.nota, 'estado', t.estado, 'data', t.created_at, 'por', coalesce((select nome from administradores_plataforma where user_id = t.atribuido_por),
      (select nome from funcionarios where id = t.atribuido_por), '')) order by t.estado, t.created_at desc), '[]'::jsonb)
  from email_atribuicoes t join caixas_email c on c.id = t.caixa_id
  where t.atribuido_a = p_user and private.email_da_equipa(p_user, t.caixa_id)
$$;

create or replace function public.servico_email_respondido(p_user uuid, p_caixa uuid, p_uid bigint) returns void
language sql security definer set search_path = public as $$
  update email_atribuicoes set estado = 'respondido', updated_at = now() where caixa_id = p_caixa and uid = p_uid and atribuido_a = p_user
$$;

revoke all on function private.email_da_equipa(uuid, uuid), public.servico_email_credenciais2(uuid, uuid, bigint), public.servico_email_equipa(uuid, uuid),
  public.servico_email_atribuir(uuid, uuid, bigint, uuid, text, text, text), public.servico_email_atribuidos(uuid), public.servico_email_respondido(uuid, uuid, bigint)
  from public, anon, authenticated;
grant execute on function public.servico_email_credenciais2(uuid, uuid, bigint), public.servico_email_equipa(uuid, uuid),
  public.servico_email_atribuir(uuid, uuid, bigint, uuid, text, text, text), public.servico_email_atribuidos(uuid), public.servico_email_respondido(uuid, uuid, bigint) to service_role;
grant select, insert, update, delete on email_atribuicoes to service_role;
-- ===== 00140_chat_so_equipa.sql =====
-- v70 — Chat separado por organização: a equipa Elolog só fala entre si; cada prestador só dentro da sua empresa.
-- A administração da plataforma não vê nem contacta os funcionários dos prestadores pelo chat.

create or replace function private.chat_pode(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a <> b and coalesce((select
      (x.org = 'elolog' and y.org = 'elolog')
      or (x.org = y.org and x.org <> 'elolog' and (x.papel = y.papel or 'admin_empresa' in (x.papel, y.papel) or 'operador' in (x.papel, y.papel)
          or (least(x.papel, y.papel) = 'armazem' and greatest(x.papel, y.papel) = 'operador_terreno')))
    from private.chat_perfil(a) x, private.chat_perfil(b) y where x.org is not null and y.org is not null), false)
$$;

create or replace function public.chat_contactos()
returns table (user_id uuid, nome text, papel text, organizacao text, por_ler int, ultima text, ultima_em timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare eu uuid := auth.uid(); p record;
begin
  select * into p from private.chat_perfil(eu);
  if p.org is null then return; end if;
  return query
  with cand as (
    select a.user_id as id, a.nome, a.papel, 'Elolog'::text as org from administradores_plataforma a where a.ativo and p.org = 'elolog'
    union all
    select f.id, f.nome, f.papel::text, coalesce(e.nome_comercial, e.nome) from funcionarios f join empresas e on e.id = f.empresa_id
      where f.ativo and p.org <> 'elolog' and f.empresa_id::text = p.org
  )
  select c.id, c.nome, c.papel, c.org,
    (select count(*)::int from chat_mensagens m where m.de = c.id and m.para = eu and m.lida_em is null),
    (select left(m.texto, 80) from chat_mensagens m where (m.de = c.id and m.para = eu) or (m.de = eu and m.para = c.id) order by m.created_at desc limit 1),
    (select max(m.created_at) from chat_mensagens m where (m.de = c.id and m.para = eu) or (m.de = eu and m.para = c.id))
  from cand c where private.chat_pode(eu, c.id)
  order by 7 desc nulls last, 2 limit 300;
end $$;

-- Conversa só entre quem a hierarquia permite (já não basta ter mensagens antigas).
create or replace function public.chat_conversa(p_com uuid)
returns setof chat_mensagens language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid();
begin
  if not private.chat_pode(eu, p_com) then raise exception 'Sem permissão para falar com este funcionário.'; end if;
  update chat_mensagens set lida_em = now() where de = p_com and para = eu and lida_em is null;
  return query select * from (select * from chat_mensagens m where (m.de = eu and m.para = p_com) or (m.de = p_com and m.para = eu)
    order by m.created_at desc limit 60) t order by t.created_at;
end $$;

-- O contador também só conta mensagens de colegas da mesma organização.
create or replace function public.chat_por_ler() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from chat_mensagens where para = auth.uid() and lida_em is null and private.chat_pode(auth.uid(), de)
$$;

-- ===== 00141_chat_grupos.sql =====
-- v71 — Chat: dentro da mesma organização todos falam com todos (sem hierarquia) e podem criar grupos.
-- A equipa Elolog continua separada de cada prestador; empresas diferentes nunca se veem.

create or replace function private.chat_pode(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a <> b and coalesce((select x.org = y.org from private.chat_perfil(a) x, private.chat_perfil(b) y
    where x.org is not null and y.org is not null), false)
$$;

create table if not exists chat_grupos (
  id         uuid primary key default gen_random_uuid(),
  org        text not null,                         -- 'elolog' ou id da empresa
  nome       text not null check (length(nome) between 1 and 80),
  criado_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists chat_grupo_membros (
  grupo_id uuid not null references chat_grupos(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  lido_ate timestamptz not null default now(),
  primary key (grupo_id, user_id)
);
create table if not exists chat_grupo_mensagens (
  id         uuid primary key default gen_random_uuid(),
  grupo_id   uuid not null references chat_grupos(id) on delete cascade,
  de         uuid not null references auth.users(id) on delete cascade,
  texto      text not null check (length(texto) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists chat_grupo_msgs on chat_grupo_mensagens (grupo_id, created_at desc);
alter table chat_grupos enable row level security; alter table chat_grupo_membros enable row level security; alter table chat_grupo_mensagens enable row level security;
revoke all on chat_grupos, chat_grupo_membros, chat_grupo_mensagens from anon, authenticated;

-- Membro ativo do grupo (e ainda funcionário ativo da organização do grupo).
create or replace function private.chat_membro(p_user uuid, p_grupo uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from chat_grupo_membros m join chat_grupos g on g.id = m.grupo_id
    where m.grupo_id = p_grupo and m.user_id = p_user and g.org = (select org from private.chat_perfil(p_user)))
$$;

create or replace function public.chat_grupo_criar(p_nome text, p_membros uuid[]) returns uuid
language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); v_org text := (select org from private.chat_perfil(auth.uid())); g uuid; m uuid;
begin
  if v_org is null then raise exception 'Sem permissão para criar grupos.'; end if;
  if length(trim(coalesce(p_nome, ''))) = 0 then raise exception 'Dê um nome ao grupo.'; end if;
  if coalesce(array_length(p_membros, 1), 0) = 0 then raise exception 'Escolha pelo menos um colega.'; end if;
  if (select count(*) from chat_grupos where criado_por = eu and created_at > now() - interval '1 hour') >= 20 then raise exception 'Demasiados grupos criados. Aguarde.'; end if;
  insert into chat_grupos (org, nome, criado_por) values (v_org, left(trim(p_nome), 80), eu) returning id into g;
  insert into chat_grupo_membros (grupo_id, user_id) values (g, eu);
  foreach m in array p_membros loop
    if private.chat_pode(eu, m) then insert into chat_grupo_membros (grupo_id, user_id) values (g, m) on conflict do nothing; end if;
  end loop;
  return g;
end $$;

create or replace function public.chat_grupo_adicionar(p_grupo uuid, p_membros uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); m uuid;
begin
  if not private.chat_membro(eu, p_grupo) then raise exception 'Não pertence a este grupo.'; end if;
  foreach m in array coalesce(p_membros, '{}') loop
    if private.chat_pode(eu, m) then insert into chat_grupo_membros (grupo_id, user_id) values (p_grupo, m) on conflict do nothing; end if;
  end loop;
end $$;

create or replace function public.chat_grupo_sair(p_grupo uuid) returns void
language sql security definer set search_path = public as $$
  delete from chat_grupo_membros where grupo_id = p_grupo and user_id = auth.uid()
$$;

create or replace function public.chat_grupos()
returns table (id uuid, nome text, membros int, por_ler int, ultima text, ultima_em timestamptz, nomes text)
language sql stable security definer set search_path = public as $$
  select g.id, g.nome, (select count(*)::int from chat_grupo_membros x where x.grupo_id = g.id),
    (select count(*)::int from chat_grupo_mensagens t where t.grupo_id = g.id and t.de <> auth.uid() and t.created_at > m.lido_ate),
    (select left(t.texto, 80) from chat_grupo_mensagens t where t.grupo_id = g.id order by t.created_at desc limit 1),
    (select max(t.created_at) from chat_grupo_mensagens t where t.grupo_id = g.id),
    (select string_agg(p.nome, ', ' order by p.nome) from chat_grupo_membros x, private.chat_perfil(x.user_id) p where x.grupo_id = g.id and p.nome is not null)
  from chat_grupos g join chat_grupo_membros m on m.grupo_id = g.id and m.user_id = auth.uid()
  where private.chat_membro(auth.uid(), g.id) order by 6 desc nulls last, 2
$$;

create or replace function public.chat_grupo_conversa(p_grupo uuid)
returns table (id uuid, de uuid, nome_de text, texto text, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not private.chat_membro(auth.uid(), p_grupo) then raise exception 'Não pertence a este grupo.'; end if;
  update chat_grupo_membros set lido_ate = now() where grupo_id = p_grupo and user_id = auth.uid();
  return query select t.id, t.de, (select nome from private.chat_perfil(t.de)), t.texto, t.created_at from (
    select * from chat_grupo_mensagens x where x.grupo_id = p_grupo order by x.created_at desc limit 80) t order by t.created_at;
end $$;

create or replace function public.chat_grupo_enviar(p_grupo uuid, p_texto text)
returns chat_grupo_mensagens language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); r chat_grupo_mensagens;
begin
  if not private.chat_membro(eu, p_grupo) then raise exception 'Não pertence a este grupo.'; end if;
  if length(trim(coalesce(p_texto, ''))) = 0 then raise exception 'Escreva a mensagem.'; end if;
  if (select count(*) from chat_grupo_mensagens where de = eu and created_at > now() - interval '1 minute') >= 30 then raise exception 'Demasiadas mensagens seguidas. Aguarde um minuto.'; end if;
  insert into chat_grupo_mensagens (grupo_id, de, texto) values (p_grupo, eu, left(trim(p_texto), 2000)) returning * into r;
  update chat_grupo_membros set lido_ate = now() where grupo_id = p_grupo and user_id = eu;
  return r;
end $$;

-- Contador: mensagens diretas + mensagens de grupo por ler.
create or replace function public.chat_por_ler() returns int
language sql stable security definer set search_path = public as $$
  select (select count(*)::int from chat_mensagens where para = auth.uid() and lida_em is null and private.chat_pode(auth.uid(), de))
       + (select count(*)::int from chat_grupo_mensagens t join chat_grupo_membros m on m.grupo_id = t.grupo_id and m.user_id = auth.uid()
           where t.de <> auth.uid() and t.created_at > m.lido_ate and private.chat_membro(auth.uid(), t.grupo_id))
$$;

revoke all on function private.chat_membro(uuid, uuid), public.chat_grupo_criar(text, uuid[]), public.chat_grupo_adicionar(uuid, uuid[]), public.chat_grupo_sair(uuid),
  public.chat_grupos(), public.chat_grupo_conversa(uuid), public.chat_grupo_enviar(uuid, text) from public, anon;
grant execute on function public.chat_grupo_criar(text, uuid[]), public.chat_grupo_adicionar(uuid, uuid[]), public.chat_grupo_sair(uuid),
  public.chat_grupos(), public.chat_grupo_conversa(uuid), public.chat_grupo_enviar(uuid, text) to authenticated;

-- ===== 00142_codigos_elo.sql =====
-- v72 — Novas referências: encomendas ELO_<REF>-000123 (REF = referência do prestador) e simulações ELO_SM-000045.
-- A referência do prestador é criada sozinha a partir do nome (ex.: «Transatlântico Demo, Lda.» → TRAN) e é única.
-- As encomendas e simulações antigas (TR-AAAA-NNNNNN / SIM-AAAA-NNNNNN) passam para o formato novo.

alter table empresas add column if not exists referencia text;

-- Referência curta e única a partir do nome: 4 letras da primeira palavra (sem acentos); se faltar, completa com a seguinte; se já existir, junta um número.
create or replace function private.referencia_empresa(p_nome text, p_id uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare v_base text; v_ref text; n int := 1;
begin
  v_base := upper(translate(coalesce(p_nome, ''), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑáàâãäéèêëíìîïóòôõöúùûüçñ', 'AAAAAEEEEIIIIOOOOOUUUUCNaaaaaeeeeiiiiooooouuuucn'));
  v_base := regexp_replace(v_base, '\m(LDA|LIMITADA|SA|S\.A|UNIPESSOAL|SOCIEDADE|COMPANHIA|CIA)\M', '', 'g');
  v_base := left(regexp_replace(v_base, '[^A-Z]', '', 'g'), 4);
  if length(v_base) < 3 then v_base := rpad(coalesce(nullif(v_base, ''), 'PRS'), 3, 'X'); end if;
  v_ref := v_base;
  while exists (select 1 from empresas where referencia = v_ref and id <> p_id) loop n := n + 1; v_ref := v_base || n; end loop;
  return v_ref;
end $$;

do $$ declare e record; begin
  for e in select id, coalesce(nullif(nome_comercial, ''), nome) n from empresas where referencia is null order by created_at loop
    update empresas set referencia = private.referencia_empresa(e.n, e.id) where id = e.id;
  end loop;
end $$;
create unique index if not exists empresas_referencia on empresas (referencia);
do $$ begin
  alter table empresas add constraint empresas_referencia_chk check (referencia ~ '^[A-Z0-9]{2,8}$');
exception when duplicate_object then null; end $$;

create or replace function private.empresa_referencia_auto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.referencia is null or new.referencia = '' then new.referencia := private.referencia_empresa(coalesce(nullif(new.nome_comercial, ''), new.nome), new.id); end if;
  new.referencia := upper(new.referencia);
  return new;
end $$;
create or replace trigger empresas_referencia_auto before insert or update of referencia on empresas for each row execute function private.empresa_referencia_auto();

-- Numeração contínua (não recomeça no ano novo): contadores com ano = 0.
create or replace function private.codigo_elo(p_prefixo text) returns text
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  insert into contadores (prefixo, ano, valor) values (p_prefixo, 0, 1)
  on conflict (prefixo, ano) do update set valor = contadores.valor + 1 returning valor into v;
  return p_prefixo || '-' || lpad(v::text, 6, '0');
end $$;
grant execute on function private.codigo_elo(text) to authenticated, service_role;

-- Encomendas: o código é dado pelo servidor ao criar (ELO_<REF>-NNNNNN).
alter table encomendas alter column codigo set default '';
create or replace function private.encomenda_codigo_auto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.codigo, '') = '' then
    new.codigo := private.codigo_elo('ELO_' || coalesce((select referencia from empresas where id = new.empresa_id), 'PRS'));
  end if;
  return new;
end $$;
create or replace trigger encomendas_codigo_auto before insert on encomendas for each row execute function private.encomenda_codigo_auto();

-- Simulações: ELO_SM-NNNNNN.
alter table simulacoes alter column codigo set default private.codigo_elo('ELO_SM');

-- Converter os códigos antigos (só os do formato automático).
do $$ declare r record; begin
  for r in select e.id, m.referencia from encomendas e join empresas m on m.id = e.empresa_id where e.codigo ~ '^TR-\d{4}-\d{6}$' order by e.created_at loop
    update encomendas set codigo = private.codigo_elo('ELO_' || r.referencia) where id = r.id;
  end loop;
  for r in select id from simulacoes where codigo ~ '^SIM-\d{4}-\d{6}$' order by created_at loop
    update simulacoes set codigo = private.codigo_elo('ELO_SM') where id = r.id;
  end loop;
end $$;

-- ===== 00143_repor_senha_empresa.sql =====
-- v74 — Recuperar a palavra-passe da EMPRESA (1.º passo do login do prestador).
-- Só para a Edge Function «recuperar-acesso» (chave de serviço). O código é enviado para o email oficial da empresa.

-- Empresa por nome + NIF (como no login) ou por id. Devolve o email oficial e uma «impressão» do segredo atual
-- (para o código deixar de valer depois de a palavra-passe mudar). Nada disto chega ao navegador.
create or replace function public.servico_empresa_reposicao(p_nome text, p_nif text, p_id uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', e.id, 'nome', coalesce(e.nome_comercial, e.nome), 'email', e.email, 'estado', e.estado,
    'impressao', md5(coalesce(s.segredo_hash, '') || e.id::text))
  from empresas e left join empresa_segredos s on s.empresa_id = e.id
  where (p_id is not null and e.id = p_id)
     or (p_id is null and private.norm(e.nif) = private.norm(p_nif) and private.norm(e.nome) = private.norm(p_nome))
  limit 1
$$;

create or replace function public.servico_empresa_definir_senha(p_id uuid, p_senha text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if length(coalesce(p_senha, '')) < 8 then raise exception 'A palavra-passe da empresa é demasiado curta (mínimo 8 caracteres).'; end if;
  insert into empresa_segredos (empresa_id, segredo_hash) values (p_id, extensions.crypt(p_senha, extensions.gen_salt('bf')))
  on conflict (empresa_id) do update set segredo_hash = excluded.segredo_hash;
  delete from tentativas_gate where chave = p_id::text;
  insert into notificacoes (empresa_id, tipo, titulo, corpo)
  values (p_id, 'seguranca', 'Palavra-passe da empresa alterada', 'A palavra-passe de acesso da empresa foi reposta através do email oficial.');
end $$;

revoke all on function public.servico_empresa_reposicao(text, text, uuid), public.servico_empresa_definir_senha(uuid, text) from public, anon, authenticated;
grant execute on function public.servico_empresa_reposicao(text, text, uuid), public.servico_empresa_definir_senha(uuid, text) to service_role;

-- ===== 00144_espaco_ficheiros.sql =====
-- v74 — Espaço de ficheiros garantido por plano: mede o que cada empresa (e cada cliente) guarda e trava novos envios no limite.
-- Limite da empresa: valor acordado (Empresarial) → armazenamento_gb do plano da subscrição → 50 GB se o plano for personalizado → 2 GB.
-- Clientes: 1 GB cada. Avisos à empresa aos 80 % e aos 100 % (e à equipa Elolog aos 100 %).

alter table empresas add column if not exists armazenamento_gb_acordado numeric(8,2) check (armazenamento_gb_acordado is null or armazenamento_gb_acordado > 0);

-- Bytes guardados numa pasta do bucket «documentos» (<empresa_id>/… ou <cliente_id>/…).
create or replace function private.espaco_usado(p_pasta text) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(sum(coalesce((o.metadata->>'size')::bigint, 0)), 0)::bigint
  from storage.objects o where o.bucket_id = 'documentos' and o.name like p_pasta || '/%'
$$;

create or replace function private.espaco_limite_empresa(p_empresa uuid) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare v_gb numeric; v_pers boolean;
begin
  select e.armazenamento_gb_acordado into v_gb from empresas e where e.id = p_empresa;
  if v_gb is null then
    select p.armazenamento_gb, p.personalizado into v_gb, v_pers from subscricoes s join planos p on p.id = s.plano_id
    where s.empresa_id = p_empresa order by (s.estado = 'ativa') desc, s.created_at desc limit 1;
    v_gb := coalesce(v_gb, case when v_pers then 50 else 2 end);
  end if;
  return (v_gb * 1073741824)::bigint;
end $$;

-- Ainda há espaço para mais um ficheiro nesta pasta? (usado pela política de envio)
create or replace function private.espaco_disponivel(p_pasta text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when p_pasta = private.minha_empresa()::text then private.espaco_usado(p_pasta) < private.espaco_limite_empresa(private.minha_empresa())
    when p_pasta = auth.uid()::text then private.espaco_usado(p_pasta) < 1073741824
    else true end
$$;

do $$ begin
  create policy storage_documentos_espaco on storage.objects as restrictive for insert to authenticated
    with check (bucket_id <> 'documentos' or private.espaco_disponivel((storage.foldername(name))[1]));
exception when duplicate_object then null; end $$;

-- O meu espaço (empresa do funcionário ou o próprio cliente). Cria os avisos de 80 % / 100 % uma vez por mês.
create or replace function public.espaco_ficheiros() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_emp uuid := private.minha_empresa(); v_usado bigint; v_lim bigint; v_pct int; v_tit text;
begin
  if auth.uid() is null then raise exception 'Sessão inválida.'; end if;
  if v_emp is not null then v_usado := private.espaco_usado(v_emp::text); v_lim := private.espaco_limite_empresa(v_emp);
  else v_usado := private.espaco_usado(auth.uid()::text); v_lim := 1073741824; end if;
  v_pct := floor(100.0 * v_usado / greatest(v_lim, 1));
  if v_emp is not null and v_pct >= 80 then
    v_tit := case when v_pct >= 100 then 'Espaço de ficheiros esgotado' else 'Espaço de ficheiros quase cheio' end;
    if not exists (select 1 from notificacoes where empresa_id = v_emp and tipo = 'espaco' and titulo = v_tit and created_at > now() - interval '30 days') then
      insert into notificacoes (empresa_id, tipo, titulo, corpo) values (v_emp, 'espaco', v_tit,
        format('A empresa usa %s%% do espaço de ficheiros do plano. %s', v_pct,
          case when v_pct >= 100 then 'Novos documentos ficam bloqueados até libertar espaço ou mudar de plano.' else 'Considere mudar de plano antes de chegar ao limite.' end));
      if v_pct >= 100 then insert into notificacoes (para_plataforma, tipo, titulo, corpo, referencia_tabela, referencia_id)
        values (true, 'espaco', 'Empresa sem espaço de ficheiros', (select coalesce(nome_comercial, nome) from empresas where id = v_emp) || ' chegou ao limite do plano.', 'empresas', v_emp); end if;
    end if;
  end if;
  return jsonb_build_object('tipo', case when v_emp is null then 'cliente' else 'empresa' end, 'usado', v_usado, 'limite', v_lim, 'percentagem', v_pct);
end $$;

-- Equipa Elolog: espaço de todas as empresas, e definir o valor acordado de um contrato personalizado.
create or replace function public.espaco_empresas()
returns table (empresa_id uuid, nome text, plano text, usado bigint, limite bigint, acordado_gb numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  return query select e.id, coalesce(e.nome_comercial, e.nome),
    (select p.nome from subscricoes s join planos p on p.id = s.plano_id where s.empresa_id = e.id order by (s.estado = 'ativa') desc, s.created_at desc limit 1),
    private.espaco_usado(e.id::text), private.espaco_limite_empresa(e.id), e.armazenamento_gb_acordado
  from empresas e where e.estado = 'aprovada' order by 4 desc, 2;
end $$;

create or replace function public.espaco_definir_acordado(p_empresa uuid, p_gb numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  if p_gb is not null and (p_gb <= 0 or p_gb > 10000) then raise exception 'Indique um valor entre 0,1 e 10 000 GB.'; end if;
  update empresas set armazenamento_gb_acordado = p_gb where id = p_empresa;
end $$;

revoke all on function private.espaco_usado(text), private.espaco_limite_empresa(uuid), public.espaco_ficheiros(), public.espaco_empresas(),
  public.espaco_definir_acordado(uuid, numeric) from public, anon;
grant execute on function private.espaco_disponivel(text) to authenticated;
grant execute on function public.espaco_ficheiros(), public.espaco_empresas(), public.espaco_definir_acordado(uuid, numeric) to authenticated;

-- ===== 00145_declaracoes.sql =====
-- v75 — Declarações da encomenda (6 modelos internos de apoio): os dados preenchem-se uma vez e servem a todos os modelos.
-- O cliente preenche proprietário, destinatário, viatura e bens; o prestador da encomenda completa o embarque e pode corrigir tudo.

create table if not exists encomenda_declaracoes (
  encomenda_id   uuid primary key references encomendas(id) on delete cascade,
  dados          jsonb not null default '{}'::jsonb check (jsonb_typeof(dados) = 'object' and pg_column_size(dados) < 200000),
  atualizado_por uuid references auth.users(id) on delete set null,
  updated_at     timestamptz not null default now()
);
alter table encomenda_declaracoes enable row level security;
revoke all on encomenda_declaracoes from anon, authenticated;

-- Encomenda pelo código, só para o cliente dela ou para a empresa prestadora. Devolve também quem está a pedir.
create or replace function private.declaracao_acesso(p_codigo text, out v_id uuid, out v_papel text)
language sql stable security definer set search_path = public as $$
  select e.id, case when e.cliente_id = auth.uid() then 'cliente' else 'empresa' end
  from encomendas e where e.codigo = p_codigo
    and (e.cliente_id = auth.uid() or (private.minha_empresa() is not null and e.empresa_id = private.minha_empresa()))
$$;

create or replace function public.declaracoes_ler(p_codigo text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a record; r jsonb;
begin
  select * into a from private.declaracao_acesso(p_codigo);
  if a.v_id is null then raise exception 'Encomenda não encontrada.'; end if;
  select jsonb_build_object('codigo', e.codigo, 'origem', e.origem, 'destino', e.destino, 'papel', a.v_papel,
      'cliente', jsonb_build_object('nome', c.nome, 'nif', c.nif, 'telefone', c.telefone, 'morada', c.morada, 'email', c.email),
      'empresa', jsonb_build_object('nome', coalesce(m.nome_comercial, m.nome), 'nif', m.nif, 'email', m.email, 'telefone', m.telefone),
      'dados', coalesce(d.dados, '{}'::jsonb), 'atualizado_em', d.updated_at)
    into r
  from encomendas e left join clientes c on c.id = e.cliente_id left join empresas m on m.id = e.empresa_id
    left join encomenda_declaracoes d on d.encomenda_id = e.id
  where e.id = a.v_id;
  return r;
end $$;

create or replace function public.declaracoes_gravar(p_codigo text, p_dados jsonb) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare a record; v_antes jsonb; v_novo jsonb; v_quando timestamptz := now();
begin
  select * into a from private.declaracao_acesso(p_codigo);
  if a.v_id is null then raise exception 'Encomenda não encontrada.'; end if;
  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then raise exception 'Dados inválidos.'; end if;
  if jsonb_typeof(coalesce(p_dados->'bens', '[]')) <> 'array' or jsonb_array_length(coalesce(p_dados->'bens', '[]')) > 300 then raise exception 'A lista de bens é inválida (máximo 300 linhas).'; end if;
  select dados into v_antes from encomenda_declaracoes where encomenda_id = a.v_id;
  v_novo := p_dados;
  if a.v_papel = 'cliente' then   -- o embarque é do prestador
    v_novo := (v_novo - 'embarque') || jsonb_build_object('embarque', coalesce(v_antes->'embarque', '{}'::jsonb));
  end if;
  insert into encomenda_declaracoes (encomenda_id, dados, atualizado_por, updated_at) values (a.v_id, v_novo, auth.uid(), v_quando)
  on conflict (encomenda_id) do update set dados = excluded.dados, atualizado_por = excluded.atualizado_por, updated_at = excluded.updated_at;
  return v_quando;
end $$;

revoke all on function private.declaracao_acesso(text), public.declaracoes_ler(text), public.declaracoes_gravar(text, jsonb) from public, anon;
grant execute on function public.declaracoes_ler(text), public.declaracoes_gravar(text, jsonb) to authenticated;

-- ===== 00146_acesso_temporario.sql =====
-- v76 — A equipa Elolog cria um prestador com um CÓDIGO DE ACESSO TEMPORÁRIO (válido 72 h), enviado por email ao administrador
-- da empresa. O código serve de palavra-passe da empresa e da conta pessoal; no primeiro início de sessão é obrigatório trocar as duas.
-- Enquanto não trocar, a conta não vê nem altera nenhum dado da empresa (minha_empresa / meu_papel devolvem nulo).
-- (Inclui também a regra da v81: o administrador da empresa precisa do 2.º passo — sessão aal2.)

create table if not exists acessos_temporarios (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  empresa_id uuid not null references empresas(id) on delete cascade,
  expira_em  timestamptz not null,
  criado_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table acessos_temporarios enable row level security;
revoke all on acessos_temporarios from anon, authenticated;

create or replace function private.minha_empresa() returns uuid
language sql stable security definer set search_path = public as $$ select f.empresa_id from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = auth.uid() and f.ativo and (f.papel <> 'admin_empresa' or coalesce(auth.jwt() ->> 'aal', '') = 'aal2')
     and not exists (select 1 from acessos_temporarios t where t.user_id = f.id) $$;
create or replace function private.meu_papel() returns papel_funcionario
language sql stable security definer set search_path = public as $$ select f.papel from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = auth.uid() and f.ativo and (f.papel <> 'admin_empresa' or coalesce(auth.jwt() ->> 'aal', '') = 'aal2')
     and not exists (select 1 from acessos_temporarios t where t.user_id = f.id) $$;
create or replace function public.servico_admin_empresa(p_user uuid) returns uuid
language sql stable security definer set search_path = public as $$ select f.empresa_id from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = p_user and f.ativo and f.papel = 'admin_empresa' and not exists (select 1 from acessos_temporarios t where t.user_id = f.id) $$;

-- Estado do primeiro acesso da conta com sessão iniciada (a interface pergunta logo a seguir ao login).
create or replace function public.primeiro_acesso() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('pendente', true, 'expirado', t.expira_em < now(), 'expira_em', t.expira_em)
    from acessos_temporarios t where t.user_id = auth.uid()), jsonb_build_object('pendente', false))
$$;

-- Criar o prestador (só a Edge Function «criar-prestador», depois de criar a conta de autenticação do administrador).
create or replace function public.servico_criar_prestador_admin(p_autor uuid, p_user uuid, p_empresa jsonb, p_admin_nome text, p_admin_email text,
  p_plano text, p_aprovada boolean, p_codigo text, p_expira timestamptz) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; v_plano planos; t text := '';
begin
  if not public.servico_equipa_pode_gerir(p_autor) then raise exception 'Só um administrador da plataforma pode criar prestadores.'; end if;
  if length(trim(coalesce(p_empresa->>'nome', ''))) < 2 then raise exception 'Indique o nome legal da empresa.'; end if;
  if coalesce(p_empresa->>'nif', '') !~ '^\s*\d{9}\s*$' then raise exception 'O NIF da empresa deve ter 9 algarismos.'; end if;
  if exists (select 1 from empresas where private.norm(nif) = private.norm(p_empresa->>'nif')) then raise exception 'Já existe uma empresa registada com este NIF.'; end if;
  if length(coalesce(p_codigo, '')) < 10 then raise exception 'Código temporário inválido.'; end if;
  select * into v_plano from planos where lower(nome) = lower(trim(coalesce(p_plano, ''))) and ativo;
  insert into empresas (nome, nome_comercial, nif, email, telefone, morada, codigo_postal, cidade, pais, estado, aprovada_por, aprovada_em)
  values (trim(p_empresa->>'nome'), nullif(trim(p_empresa->>'nome_comercial'), ''), trim(p_empresa->>'nif'), lower(trim(p_empresa->>'email')),
    nullif(trim(p_empresa->>'telefone'), ''), nullif(trim(p_empresa->>'morada'), ''), nullif(trim(p_empresa->>'codigo_postal'), ''),
    nullif(trim(p_empresa->>'cidade'), ''), coalesce(nullif(trim(p_empresa->>'pais'), ''), 'Portugal'),
    (case when p_aprovada then 'aprovada' else 'pendente' end)::estado_empresa, case when p_aprovada then p_autor end, case when p_aprovada then now() end)
  returning id into v_emp;
  insert into empresa_segredos (empresa_id, segredo_hash) values (v_emp, extensions.crypt(p_codigo, extensions.gen_salt('bf')));
  if v_plano.id is not null then
    insert into subscricoes (empresa_id, plano_id, estado, periodicidade, valor) values (v_emp, v_plano.id, 'pendente', 'mensal', v_plano.preco_mensal);
  end if;
  insert into funcionarios (id, empresa_id, nome, email, papel) values (p_user, v_emp, trim(p_admin_nome), lower(trim(p_admin_email)), 'admin_empresa');
  insert into acessos_temporarios (user_id, empresa_id, expira_em, criado_por) values (p_user, v_emp, p_expira, p_autor);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_emp, p_autor, 'admin_plataforma', 'criar_prestador_admin', 'empresas', v_emp::text, jsonb_build_object('plano', v_plano.nome, 'aprovada', p_aprovada, 'expira_em', p_expira));
  return v_emp;
end $$;

-- Novo código para um primeiro acesso ainda pendente (o anterior deixa de valer). Devolve o administrador e a empresa.
create or replace function public.servico_renovar_acesso_temporario(p_autor uuid, p_empresa uuid, p_codigo text, p_expira timestamptz)
returns table (user_id uuid, email text, nome text, empresa text, nif text)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.servico_equipa_pode_gerir(p_autor) then raise exception 'Só um administrador da plataforma pode reenviar códigos.'; end if;
  if length(coalesce(p_codigo, '')) < 10 then raise exception 'Código temporário inválido.'; end if;
  update acessos_temporarios t set expira_em = p_expira, criado_por = p_autor where t.empresa_id = p_empresa;
  if not found then raise exception 'Esta empresa já concluiu o primeiro acesso.'; end if;
  update empresa_segredos set segredo_hash = extensions.crypt(p_codigo, extensions.gen_salt('bf')) where empresa_id = p_empresa;
  delete from tentativas_gate where chave = p_empresa::text;
  return query select t.user_id, f.email, f.nome, e.nome, e.nif
    from acessos_temporarios t join funcionarios f on f.id = t.user_id join empresas e on e.id = t.empresa_id where t.empresa_id = p_empresa;
end $$;

-- Ler o acesso temporário de uma conta (a Edge Function verifica-o antes de mudar a palavra-passe pessoal).
create or replace function public.servico_acesso_temporario(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('empresa_id', t.empresa_id, 'expirado', t.expira_em < now()) from acessos_temporarios t where t.user_id = p_user
$$;

-- Concluir o primeiro acesso: nova palavra-passe da empresa e fim do acesso temporário.
create or replace function public.servico_concluir_primeiro_acesso(p_user uuid, p_senha_empresa text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare t acessos_temporarios;
begin
  select * into t from acessos_temporarios where user_id = p_user for update;
  if not found then raise exception 'Não há nenhum primeiro acesso pendente.'; end if;
  if t.expira_em < now() then raise exception 'O código temporário expirou. Peça um novo à Elolog.'; end if;
  if length(coalesce(p_senha_empresa, '')) < 8 then raise exception 'A palavra-passe da empresa é demasiado curta (mínimo 8 caracteres).'; end if;
  update empresa_segredos set segredo_hash = extensions.crypt(p_senha_empresa, extensions.gen_salt('bf')) where empresa_id = t.empresa_id;
  delete from acessos_temporarios where user_id = p_user;
  insert into notificacoes (empresa_id, tipo, titulo, corpo) values (t.empresa_id, 'seguranca', 'Primeiro acesso concluído', 'As palavras-passe temporárias foram substituídas pelo administrador da empresa.');
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id) values (t.empresa_id, p_user, 'admin_empresa', 'concluir_primeiro_acesso', 'empresas', t.empresa_id::text);
  return t.empresa_id;
end $$;

-- Equipa Elolog: primeiros acessos ainda por concluir (para reenviar o código).
create or replace function public.acessos_temporarios_pendentes()
returns table (empresa_id uuid, empresa text, nif text, admin_email text, expira_em timestamptz, expirado boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  return query select e.id, coalesce(e.nome_comercial, e.nome), e.nif, f.email, t.expira_em, t.expira_em < now()
    from acessos_temporarios t join empresas e on e.id = t.empresa_id join funcionarios f on f.id = t.user_id order by t.created_at desc;
end $$;

revoke all on function public.primeiro_acesso(), public.servico_criar_prestador_admin(uuid, uuid, jsonb, text, text, text, boolean, text, timestamptz),
  public.servico_renovar_acesso_temporario(uuid, uuid, text, timestamptz), public.servico_acesso_temporario(uuid),
  public.servico_concluir_primeiro_acesso(uuid, text), public.acessos_temporarios_pendentes() from public, anon, authenticated;
grant execute on function public.primeiro_acesso(), public.acessos_temporarios_pendentes() to authenticated;
grant execute on function public.servico_criar_prestador_admin(uuid, uuid, jsonb, text, text, text, boolean, text, timestamptz),
  public.servico_renovar_acesso_temporario(uuid, uuid, text, timestamptz), public.servico_acesso_temporario(uuid),
  public.servico_concluir_primeiro_acesso(uuid, text) to service_role;

-- ===== 00147_ocorrencias.sql =====
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

-- ===== 00148_cliente_so_clientes.sql =====
-- v78 — A Área de Cliente é só para clientes: uma conta da equipa Elolog ou de um funcionário de prestador
-- já não consegue entrar como cliente (nem criar um perfil de cliente por engano).

-- Tipo de conta da sessão: 'equipa' (Elolog), 'funcionario' (prestador), 'cliente' ou null.
create or replace function public.tipo_conta() returns text
language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from administradores_plataforma where user_id = auth.uid()) then 'equipa'
              when exists (select 1 from funcionarios where id = auth.uid()) then 'funcionario'
              when exists (select 1 from clientes where id = auth.uid()) then 'cliente' end
$$;
revoke all on function public.tipo_conta() from public, anon;
grant execute on function public.tipo_conta() to authenticated;

-- A base de dados recusa criar um perfil de cliente para contas da equipa ou de prestadores.
do $$ begin
  create policy clientes_so_clientes on clientes as restrictive for insert to authenticated
    with check (not exists (select 1 from administradores_plataforma a where a.user_id = auth.uid())
            and not exists (select 1 from funcionarios f where f.id = auth.uid()));
exception when duplicate_object then null; end $$;

-- Limpar perfis de cliente criados por engano para contas da equipa/prestadores (só os que não têm simulações nem encomendas).
delete from clientes c
 where (exists (select 1 from administradores_plataforma a where a.user_id = c.id) or exists (select 1 from funcionarios f where f.id = c.id))
   and not exists (select 1 from encomendas e where e.cliente_id = c.id) and not exists (select 1 from simulacoes s where s.cliente_id = c.id);

-- ===== 00149_login_funcionario.sql =====
-- v80 — Login simples para funcionários do prestador: NIF da empresa + n.º de funcionário + palavra-passe pessoal.
-- A palavra-passe da EMPRESA só é pedida ao administrador da empresa (acesso ao portal de administração da empresa).
-- O n.º de funcionário passa a ser dado automaticamente (0001, 0002, …) e é único dentro de cada empresa.

-- Número automático: contador por empresa em «contadores», formato 0001 (salta números já usados à mão).
create or replace function private.funcionario_numero_auto() returns trigger
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  new.numero_interno := nullif(upper(trim(coalesce(new.numero_interno, ''))), '');
  if new.numero_interno is null then
    loop
      insert into contadores (prefixo, ano, valor) values ('FUNC_' || new.empresa_id::text, 0, 1)
      on conflict (prefixo, ano) do update set valor = contadores.valor + 1 returning valor into v;
      new.numero_interno := lpad(v::text, 4, '0');
      exit when not exists (select 1 from funcionarios f where f.empresa_id = new.empresa_id and f.id <> new.id
        and ltrim(upper(f.numero_interno), '0') = ltrim(new.numero_interno, '0'));
    end loop;
  end if;
  return new;
end $$;
create or replace trigger funcionarios_numero_auto before insert or update of numero_interno on funcionarios
  for each row execute function private.funcionario_numero_auto();

-- Dar número a quem ainda não tem (por ordem de criação).
do $$ declare r record; begin
  for r in select id from funcionarios where coalesce(trim(numero_interno), '') = '' order by created_at loop
    update funcionarios set numero_interno = null where id = r.id;
  end loop;
end $$;
create unique index if not exists funcionarios_numero_unico on funcionarios (empresa_id, (ltrim(upper(numero_interno), '0')));

-- Só para a Edge Function «entrar-funcionario»: encontrar a conta pelo NIF da empresa e pelo n.º de funcionário.
create or replace function public.servico_funcionario_por_numero(p_nif text, p_numero text)
returns table (user_id uuid, email text, nome text, papel papel_funcionario, ativo boolean, empresa_id uuid, empresa_nome text, empresa_aprovada boolean)
language sql stable security definer set search_path = public as $$
  select f.id, f.email, f.nome, f.papel, f.ativo, e.id, coalesce(e.nome_comercial, e.nome), e.estado = 'aprovada'
  from funcionarios f join empresas e on e.id = f.empresa_id
  where private.norm(e.nif) = private.norm(regexp_replace(coalesce(p_nif, ''), '\s', '', 'g'))
    and ltrim(upper(f.numero_interno), '0') = ltrim(upper(trim(coalesce(p_numero, ''))), '0')
    and trim(coalesce(p_numero, '')) <> ''
  limit 1
$$;

-- Abrir a sessão da empresa para um funcionário que já provou a palavra-passe pessoal (nunca para o administrador).
create or replace function public.servico_abrir_sessao_funcionario(p_user uuid) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare f funcionarios; v_validade timestamptz := now() + interval '12 hours';
begin
  select * into f from funcionarios where id = p_user and ativo;
  if not found then raise exception 'Conta de funcionário inativa.'; end if;
  if f.papel = 'admin_empresa' then raise exception 'O administrador da empresa entra com a palavra-passe da empresa.'; end if;
  if not exists (select 1 from empresas where id = f.empresa_id and estado = 'aprovada') then raise exception 'A empresa ainda não está aprovada.'; end if;
  insert into sessoes_empresa (user_id, empresa_id, valida_ate) values (p_user, f.empresa_id, v_validade)
  on conflict (user_id) do update set empresa_id = excluded.empresa_id, valida_ate = excluded.valida_ate;
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id)
    values (f.empresa_id, p_user, f.papel::text, 'abrir_sessao_funcionario', 'funcionarios', p_user::text);
  return v_validade;
end $$;

revoke all on function public.servico_funcionario_por_numero(text, text), public.servico_abrir_sessao_funcionario(uuid) from public, anon, authenticated;
grant execute on function public.servico_funcionario_por_numero(text, text), public.servico_abrir_sessao_funcionario(uuid) to service_role;

-- ===== 00150_mfa_admin_empresa.sql =====
-- v81 — Verificação em dois passos (código da aplicação de autenticação) para o ADMINISTRADOR DA EMPRESA.
-- Sem o 2.º passo (sessão aal2), o administrador não abre a sessão da empresa nem vê/altera dados da empresa,
-- mesmo que alguém descubra as duas palavras-passe. Os restantes funcionários não são afetados.
-- (Inclui a tabela acessos_temporarios da 00146, para esta migração funcionar com ou sem a 00146 aplicada.)

create table if not exists acessos_temporarios (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  empresa_id uuid not null references empresas(id) on delete cascade,
  expira_em  timestamptz not null,
  criado_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table acessos_temporarios enable row level security;
revoke all on acessos_temporarios from anon, authenticated;

-- Sessão com o 2.º passo confirmado?
create or replace function private.aal2() returns boolean
language sql stable set search_path = public as $$ select coalesce(auth.jwt() ->> 'aal', '') = 'aal2' $$;

create or replace function private.minha_empresa() returns uuid
language sql stable security definer set search_path = public as $$ select f.empresa_id from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = auth.uid() and f.ativo and (f.papel <> 'admin_empresa' or private.aal2())
     and not exists (select 1 from acessos_temporarios t where t.user_id = f.id) $$;
create or replace function private.meu_papel() returns papel_funcionario
language sql stable security definer set search_path = public as $$ select f.papel from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = auth.uid() and f.ativo and (f.papel <> 'admin_empresa' or private.aal2())
     and not exists (select 1 from acessos_temporarios t where t.user_id = f.id) $$;

-- Abrir a sessão da empresa: depois da palavra-passe da empresa certa, o administrador ainda tem de confirmar o código.
create or replace function public.abrir_sessao_empresa(p_nome text, p_nif text, p_senha text)
returns table (ok boolean, mensagem text, empresa_id uuid, empresa_nome text, papel papel_funcionario, funcionario_nome text, email text, valida_ate timestamptz)
language plpgsql security definer set search_path = public as $$
declare r record; v_f funcionarios; v_validade timestamptz := now() + interval '12 hours';
begin
  select * into v_f from funcionarios where id = auth.uid() and ativo;
  if not found then
    return query select false, 'Esta conta não é de um funcionário ativo de uma empresa.', null::uuid, null::text, null::papel_funcionario, null::text, null::text, null::timestamptz; return;
  end if;
  select * into r from private.verificar_empresa(p_nome, p_nif, p_senha);
  if r.p_empresa is null then
    return query select false, r.p_mensagem, null::uuid, null::text, null::papel_funcionario, null::text, null::text, null::timestamptz; return;
  end if;
  if r.p_empresa <> v_f.empresa_id then
    return query select false, 'Esta conta de funcionário não pertence à empresa indicada.', null::uuid, null::text, null::papel_funcionario, null::text, null::text, null::timestamptz; return;
  end if;
  if v_f.papel = 'admin_empresa' and not private.aal2() then
    return query select false, 'MFA_NECESSARIO', null::uuid, null::text, v_f.papel, v_f.nome, v_f.email, null::timestamptz; return;
  end if;
  insert into sessoes_empresa (user_id, empresa_id, valida_ate) values (auth.uid(), v_f.empresa_id, v_validade)
  on conflict (user_id) do update set empresa_id = excluded.empresa_id, valida_ate = excluded.valida_ate;
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id)
    values (v_f.empresa_id, auth.uid(), v_f.papel::text, 'abrir_sessao_empresa', 'funcionarios', auth.uid()::text);
  return query select true, null::text, e.id, e.nome, v_f.papel, v_f.nome, v_f.email, v_validade from empresas e where e.id = v_f.empresa_id;
end $$;

-- Edge Functions que agem pelo administrador da empresa (ex.: gerir funcionários) passam o nível da sessão.
create or replace function public.servico_admin_empresa_aal(p_user uuid, p_aal text) returns uuid
language sql stable security definer set search_path = public as $$ select f.empresa_id from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = p_user and f.ativo and f.papel = 'admin_empresa' and p_aal = 'aal2'
     and not exists (select 1 from acessos_temporarios t where t.user_id = f.id) $$;
revoke all on function public.servico_admin_empresa_aal(uuid, text) from public, anon, authenticated;
grant execute on function public.servico_admin_empresa_aal(uuid, text) to service_role;

-- ===== 00151_regras_seguranca.sql =====
-- v84 — Regras de segurança obrigatórias (documentacao/REGRAS_SEGURANCA.md). Tudo falha em modo fechado:
-- se uma verificação não puder ser feita, a operação é recusada.

-- ---------- R7. Registo de auditoria: só se acrescenta, nunca se altera nem apaga ----------
revoke update, delete, truncate on auditoria from anon, authenticated;
create or replace function private.auditoria_imutavel() returns trigger language plpgsql as $$
begin raise exception 'AUDITORIA_IMUTAVEL: o registo de auditoria não pode ser alterado nem apagado.'; end $$;
create or replace trigger auditoria_imutavel before update or delete on auditoria
  for each row execute function private.auditoria_imutavel();

-- Guarda quem fez o quê nas tabelas sensíveis. Argumento opcional: lista de campos a guardar (o resto fica de fora).
-- Campos secretos nunca são guardados.
create or replace function private.auditar_alteracao() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_antes jsonb; v_depois jsonb; v_id text; v_emp text; v_campos text[];
  v_secretos constant text[] := array['segredo_hash','mb_key','mbway_key','chave_antiphishing','pin_validacao_hash','segredo_id'];
begin
  if tg_nargs > 0 then v_campos := string_to_array(tg_argv[0], ','); end if;
  if tg_op <> 'INSERT' then v_antes := to_jsonb(old) - v_secretos; end if;
  if tg_op <> 'DELETE' then v_depois := to_jsonb(new) - v_secretos; end if;
  if tg_op = 'UPDATE' and v_antes = v_depois then return new; end if;
  v_id := coalesce(v_depois->>'id', v_antes->>'id', v_depois->>'user_id', v_antes->>'user_id', v_depois->>'empresa_id', v_antes->>'empresa_id');
  v_emp := case when tg_table_name = 'empresas' then v_id else coalesce(v_depois->>'empresa_id', v_antes->>'empresa_id') end;
  if v_campos is not null then
    select jsonb_object_agg(k, v) into v_antes from jsonb_each(v_antes) e(k, v) where k = any(v_campos);
    select jsonb_object_agg(k, v) into v_depois from jsonb_each(v_depois) e(k, v) where k = any(v_campos);
  end if;
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, antes, depois)
  values (nullif(v_emp, '')::uuid, auth.uid(), coalesce(auth.role(), 'sistema'), lower(tg_op), tg_table_name, v_id, v_antes, v_depois);
  return coalesce(new, old);
end $$;

do $$ declare t text; begin
  foreach t in array array['empresas','funcionarios','administradores_plataforma','acessos_temporarios','pagamentos',
    'pedidos_pagamento','faturas','faturas_plataforma','subscricoes','planos','regras_comissao','regras_financeiras',
    'regras_conformidade','tarifas','caixas_email','caixas_email_acesso','documentos'] loop
    execute format('create or replace trigger auditar after insert or update or delete on %I for each row execute function private.auditar_alteracao()', t);
  end loop;
end $$;
create or replace trigger auditar after insert or update or delete on empresa_segredos
  for each row execute function private.auditar_alteracao('empresa_id,updated_at');
create or replace trigger auditar after insert or update or delete on empresa_pagamentos_config
  for each row execute function private.auditar_alteracao('empresa_id,ativo,sandbox,updated_at');
create or replace trigger auditar after insert or delete on clientes
  for each row execute function private.auditar_alteracao('id,estado,created_at');
create or replace trigger auditar after insert or delete on encomendas
  for each row execute function private.auditar_alteracao('id,codigo,empresa_id,estado,preco_total,suspensa');
create or replace trigger auditar_estado after update on encomendas for each row
  when (old.estado is distinct from new.estado or old.preco_total is distinct from new.preco_total or old.suspensa is distinct from new.suspensa
        or old.empresa_id is distinct from new.empresa_id or old.cliente_id is distinct from new.cliente_id)
  execute function private.auditar_alteracao('id,codigo,empresa_id,estado,preco_total,suspensa,suspensa_motivo');

-- Bloqueios de segurança (pedido recusado, limite, verificação falhada) registados pelas Edge Functions.
create or replace function public.servico_registar_bloqueio(p_funcao text, p_motivo text, p_user uuid default null) returns void
language sql security definer set search_path = public as $$
  insert into auditoria (user_id, papel, acao, entidade, motivo)
  values (p_user, 'sistema', 'bloqueio_seguranca', left(coalesce(p_funcao, '?'), 60), left(coalesce(p_motivo, ''), 300)) $$;
revoke all on function public.servico_registar_bloqueio(text, text, uuid) from public, anon, authenticated;
grant execute on function public.servico_registar_bloqueio(text, text, uuid) to service_role;

-- ---------- R5/R11. Ficheiros: só tipos permitidos, verificados pelo servidor antes de outros os verem ----------
alter table documentos add column if not exists verificado boolean not null default false;
alter table documentos add column if not exists verificado_em timestamptz;
alter table documentos add column if not exists verificacao_motivo text;

create or replace function private.tipos_ficheiro() returns jsonb language sql immutable as $$ select '{
  "application/pdf":["pdf"], "image/jpeg":["jpg","jpeg"], "image/png":["png"], "image/webp":["webp"],
  "application/msword":["doc"], "application/vnd.ms-excel":["xls"],
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document":["docx"],
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":["xlsx"]}'::jsonb $$;

create or replace function private.documento_validar() returns trigger
language plpgsql security definer set search_path = public, storage as $$
declare o record; v_ext text; v_servico boolean := coalesce(auth.role(), 'service_role') = 'service_role';  -- sem JWT = ligação direta à base (migrações, tarefas)
begin
  if tg_op = 'UPDATE' then
    if not v_servico and (new.verificado is distinct from old.verificado or new.storage_path is distinct from old.storage_path
        or new.mime is distinct from old.mime or new.tamanho_bytes is distinct from old.tamanho_bytes or new.verificado_em is distinct from old.verificado_em) then
      raise exception 'FICHEIRO_RECUSADO: só o servidor pode alterar a verificação de um ficheiro.'; end if;
    return new;
  end if;
  if not v_servico then new.verificado := false; new.verificado_em := null; new.verificacao_motivo := null; end if;
  if new.mime is null or not (private.tipos_ficheiro() ? new.mime) then
    raise exception 'FICHEIRO_RECUSADO: tipo de ficheiro não permitido.'; end if;
  v_ext := lower(substring(new.storage_path from '\.([A-Za-z0-9]{1,5})$'));
  if v_ext is null or not ((private.tipos_ficheiro() -> new.mime) ? v_ext) then
    raise exception 'FICHEIRO_RECUSADO: a extensão do ficheiro não corresponde ao tipo.'; end if;
  if coalesce(new.tamanho_bytes, 0) < 1 or new.tamanho_bytes > 20971520 then
    raise exception 'FICHEIRO_RECUSADO: tamanho inválido (máximo 20 MB).'; end if;
  select owner, metadata into o from storage.objects where bucket_id = 'documentos' and name = new.storage_path;
  if not found then raise exception 'FICHEIRO_RECUSADO: o ficheiro não está no armazenamento.'; end if;
  if not v_servico and o.owner is distinct from auth.uid() then
    raise exception 'FICHEIRO_RECUSADO: o ficheiro não foi enviado por este utilizador.'; end if;
  if (o.metadata->>'mimetype') is distinct from new.mime or (o.metadata->>'size')::bigint is distinct from new.tamanho_bytes then
    raise exception 'FICHEIRO_RECUSADO: o ficheiro guardado não corresponde ao declarado.'; end if;
  if not v_servico then new.enviado_por := auth.uid(); end if;
  return new;
end $$;
create or replace trigger documento_validar before insert or update on documentos
  for each row execute function private.documento_validar();

-- Ninguém (além de quem o enviou) vê um documento antes de o servidor confirmar o conteúdo.
do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'documentos_so_verificados') then
    create policy documentos_so_verificados on documentos as restrictive for select to authenticated
      using (verificado or enviado_por = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname = 'storage_documentos_verificados') then
    create policy storage_documentos_verificados on storage.objects as restrictive for select to authenticated
      using (bucket_id <> 'documentos' or owner = auth.uid()
             or exists (select 1 from public.documentos d where d.storage_path = storage.objects.name and d.verificado));
  end if;
end $$;

create or replace function public.servico_documento_verificado(p_id uuid, p_ok boolean, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$ begin
  update documentos set verificado = p_ok, verificado_em = now(), verificacao_motivo = left(p_motivo, 200) where id = p_id;
  insert into auditoria (user_id, papel, acao, entidade, entidade_id, motivo)
  values (null, 'sistema', case when p_ok then 'ficheiro_verificado' else 'ficheiro_recusado' end, 'documentos', p_id::text, left(p_motivo, 200));
end $$;
revoke all on function public.servico_documento_verificado(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.servico_documento_verificado(uuid, boolean, text) to service_role;

-- ---------- R9/R10. Limite de pedidos também em escritas diretas (fora das Edge Functions) ----------
create or replace function private.limitar_escritas() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_max int := coalesce(tg_argv[0], '60')::int; v_n int; v_chave text;
begin
  if auth.uid() is null or coalesce(auth.role(), '') = 'service_role' then return new; end if;
  v_chave := 'esc:' || tg_table_name || ':' || auth.uid();
  insert into tentativas_gate (chave, falhas, ultima_falha) values (v_chave, 1, now())
  on conflict (chave) do update set falhas = case when tentativas_gate.ultima_falha < now() - interval '10 minutes' then 1
    else tentativas_gate.falhas + 1 end, ultima_falha = now()
  returning falhas into v_n;
  if v_n > v_max then raise exception 'LIMITE_EXCEDIDO: demasiados pedidos. Aguarde alguns minutos.'; end if;
  return new;
end $$;
do $$ declare r record; begin
  for r in select * from (values ('documentos',60),('chat_mensagens',150),('chat_grupo_mensagens',150),('ocorrencias',30),
      ('ocorrencia_registos',60),('tickets',20),('ticket_mensagens',60),('simulacoes',60),('pedidos_cliente',30),
      ('encomendas',120),('pagamentos',120),('cliente_notas',60),('propostas',120)) v(t, m) loop
    if to_regclass('public.' || r.t) is not null then
      execute format('create or replace trigger limitar_escritas before insert on %I for each row execute function private.limitar_escritas(%L)', r.t, r.m::text);
    end if;
  end loop;
end $$;

-- ===== 00152_codigo_reserva_mfa.sql =====
-- v85 — 2.ª opção de verificação: CÓDIGO DE RESERVA (para quando não há acesso ao telemóvel).
-- Quem já usa a aplicação de autenticação (administração da plataforma e administrador da empresa) gera um código fixo
-- de 16 caracteres, mostrado UMA vez. Se perder o telemóvel, entra com a palavra-passe + este código.
-- Segurança: só se gera com o telemóvel confirmado (aal2); guardado só como hash (bcrypt); 5 tentativas por 15 min;
-- cada uso fica na auditoria e gera um aviso por email; vale só para a sessão em que foi usado (12 h); pode ser trocado.

create table if not exists codigos_reserva (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  hash       text not null,
  criado_em  timestamptz not null default now(),
  usado_em   timestamptz,
  usos       int not null default 0
);
create table if not exists sessoes_reserva (
  session_id uuid primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  valida_ate timestamptz not null
);
alter table codigos_reserva enable row level security;
alter table sessoes_reserva enable row level security;
revoke all on codigos_reserva, sessoes_reserva from anon, authenticated;

-- Sessão reforçada = código da aplicação (aal2) OU código de reserva usado nesta mesma sessão.
create or replace function private.sessao_reforcada() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2' or exists (select 1 from sessoes_reserva s
    where s.session_id::text = auth.jwt() ->> 'session_id' and s.user_id = auth.uid() and s.valida_ate > now()) $$;

create or replace function private.aal2() returns boolean
language sql stable security definer set search_path = public as $$ select private.sessao_reforcada() $$;

create or replace function private.minha_empresa() returns uuid
language sql stable security definer set search_path = public as $$ select f.empresa_id from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = auth.uid() and f.ativo and (f.papel <> 'admin_empresa' or private.sessao_reforcada())
     and not exists (select 1 from acessos_temporarios t where t.user_id = f.id) $$;
create or replace function private.meu_papel() returns papel_funcionario
language sql stable security definer set search_path = public as $$ select f.papel from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = auth.uid() and f.ativo and (f.papel <> 'admin_empresa' or private.sessao_reforcada())
     and not exists (select 1 from acessos_temporarios t where t.user_id = f.id) $$;

create or replace function private.mfa_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select valor from private.plataforma_config where chave = 'exigir_mfa_admin'), 'false') <> 'true'
      or private.sessao_reforcada() $$;

-- Gerar (ou trocar) o código. Só com o telemóvel confirmado nesta sessão (não com outro código de reserva).
create or replace function public.gerar_codigo_reserva() returns text
language plpgsql volatile security definer set search_path = public as $$
declare v_alf text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; v_b bytea := extensions.gen_random_bytes(16); v_c text := ''; i int;
begin
  if auth.uid() is null then raise exception 'SESSAO_INVALIDA'; end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'MFA_NECESSARIO: confirme primeiro o código da aplicação de autenticação.'; end if;
  for i in 0..15 loop
    v_c := v_c || substr(v_alf, (get_byte(v_b, i) % 32) + 1, 1);
    if i in (3, 7, 11) then v_c := v_c || '-'; end if;
  end loop;
  insert into codigos_reserva (user_id, hash) values (auth.uid(), extensions.crypt(v_c, extensions.gen_salt('bf', 10)))
  on conflict (user_id) do update set hash = excluded.hash, criado_em = now(), usado_em = null, usos = 0;
  insert into auditoria (user_id, acao, entidade, entidade_id) values (auth.uid(), 'codigo_reserva_gerado', 'codigos_reserva', auth.uid()::text);
  return v_c;
end $$;

create or replace function public.estado_codigo_reserva() returns table (tem boolean, criado_em timestamptz, usado_em timestamptz)
language sql stable security definer set search_path = public as $$
  select true, c.criado_em, c.usado_em from codigos_reserva c where c.user_id = auth.uid()
  union all select false, null, null where not exists (select 1 from codigos_reserva where user_id = auth.uid()) $$;

-- Usar o código: depois da palavra-passe certa (sessão aal1). Erro = devolve false (não lança, para a auditoria ficar).
create or replace function public.usar_codigo_reserva(p_codigo text) returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare v_c text := upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g')); v_h text; v_sess uuid;
begin
  if auth.uid() is null then return false; end if;
  begin v_sess := (auth.jwt() ->> 'session_id')::uuid; exception when others then v_sess := null; end;
  if v_sess is null then return false; end if;
  if not public.servico_limite('reserva:' || auth.uid(), 5, 15) then
    insert into auditoria (user_id, acao, entidade, entidade_id, depois)
      values (auth.uid(), 'bloqueio_seguranca', 'codigos_reserva', auth.uid()::text, jsonb_build_object('motivo', 'demasiadas tentativas do código de reserva'));
    return false;
  end if;
  select hash into v_h from codigos_reserva where user_id = auth.uid();
  if v_h is null or length(v_c) <> 16
     or extensions.crypt(substr(v_c,1,4)||'-'||substr(v_c,5,4)||'-'||substr(v_c,9,4)||'-'||substr(v_c,13,4), v_h) <> v_h then
    insert into auditoria (user_id, acao, entidade, entidade_id) values (auth.uid(), 'codigo_reserva_errado', 'codigos_reserva', auth.uid()::text);
    return false;
  end if;
  insert into sessoes_reserva (session_id, user_id, valida_ate) values (v_sess, auth.uid(), now() + interval '12 hours')
  on conflict (session_id) do update set valida_ate = excluded.valida_ate where sessoes_reserva.user_id = auth.uid();
  update codigos_reserva set usado_em = now(), usos = usos + 1 where user_id = auth.uid();
  insert into auditoria (user_id, acao, entidade, entidade_id) values (auth.uid(), 'codigo_reserva_usado', 'codigos_reserva', auth.uid()::text);
  insert into notificacoes (user_id, tipo, titulo, corpo)
    values (auth.uid(), 'alerta_seguranca', 'Entrada com o código de reserva',
            'Alguém entrou na sua conta com o código de reserva. Se não foi você, mude já a palavra-passe e gere um novo código.');
  return true;
end $$;

-- Para as Edge Functions: a sessão (utilizador + session_id do token já validado) está reforçada?
create or replace function public.servico_sessao_reforcada(p_user uuid, p_session text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from sessoes_reserva s where s.user_id = p_user and s.session_id::text = p_session and s.valida_ate > now()) $$;

revoke all on function public.gerar_codigo_reserva(), public.estado_codigo_reserva(), public.usar_codigo_reserva(text),
  public.servico_sessao_reforcada(uuid, text) from public, anon;
grant execute on function public.gerar_codigo_reserva(), public.estado_codigo_reserva(), public.usar_codigo_reserva(text) to authenticated;
revoke all on function public.servico_sessao_reforcada(uuid, text) from authenticated;
grant execute on function public.servico_sessao_reforcada(uuid, text) to service_role;

-- O aviso de uso também segue por email.
create or replace function private.tipo_envia_email(p_tipo text) returns boolean language sql immutable set search_path = public as $$
  select p_tipo in ('novo_prestador', 'pedido_subscricao', 'pedido_cliente', 'apoio', 'nova_simulacao', 'empresa_aprovada',
    'empresa_recusada', 'pagamento_confirmado', 'simulacao_aceite', 'simulacao_recusada', 'estado_encomenda', 'fatura_emitida',
    'pagamento_recebido', 'alerta_seguranca') $$;

-- ===== 00158_funis_gargalo.sql =====
-- v94 — Três funis (clientes, prestadores, financeiro) e o indicador «Gargalo principal» no Centro de comando.
-- Só ACRESCENTA uma função de leitura (só administração). Não altera tabelas, dados nem ligações Supabase.
-- Regras obrigatórias (só se conta o que existe de facto na base de dados):
--  1. Só contam propostas de prestadores APROVADOS — nunca se mostram propostas fictícias.
--  2. Só há aceite se houver proposta válida (enviada/aceite, de prestador aprovado).
--  3. Só há valor contratado com proposta ACEITE (encomendas sem proposta aceite ficam fora do funil).
--  4. Só há valor faturado com fatura VÁLIDA registada.
--  5. Só há valor recebido com pagamento CONFIRMADO (estado «pago», menos reembolsos).
--  6. Planos (subscrições) e comissões das encomendas são contabilizados em separado.

create or replace function public.painel_funis(p_dias integer default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_ini timestamptz; r jsonb; a_sim uuid[]; a_prop uuid[]; a_aceite uuid[]; a_enc uuid[];
  -- clientes
  c_sim int; c_prop int; c_aceite int; c_enc int; c_entregue int; c_sem_prop int; c_expiradas int; c_recusadas int;
  -- prestadores
  p_registos int; p_pagos int; p_aprovados int; p_disponiveis int; p_com_prop int; p_com_enc int; p_pend48 int; p_pend int;
  -- financeiro
  f_sim numeric; f_prop numeric; f_aceite numeric; f_fat numeric; f_rec numeric; f_com numeric; f_sem_regra int;
  pl_recebido numeric; pl_por_confirmar numeric; pl_ativos int; pl_mrr numeric;
  g jsonb; taxa numeric; melhor numeric := 2; e record;
begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;
  if p_dias is null or p_dias not in (7, 14, 30, 60, 90, 180, 365) then raise exception 'Período inválido.'; end if;
  v_ini := now() - make_interval(days => p_dias);

  -- ---------- coorte: simulações enviadas no período, propostas válidas/aceites e encomendas com proposta aceite
  select coalesce(array_agg(s.id), '{}') into a_sim from simulacoes s
   where s.estado <> 'rascunho' and coalesce(s.enviada_em, s.created_at) >= v_ini;
  select coalesce(array_agg(p.id), '{}') into a_prop
    from propostas p join empresas em on em.id = p.empresa_id and em.estado = 'aprovada'            -- regra 1
   where p.simulacao_id = any(a_sim)
     and (p.estado = 'aceite' or (p.estado = 'enviada' and (p.validade is null or p.validade >= current_date)));   -- regra 2
  select coalesce(array_agg(p.id), '{}') into a_aceite from propostas p where p.id = any(a_prop) and p.estado = 'aceite';
  select coalesce(array_agg(o.id), '{}') into a_enc from encomendas o
   where o.proposta_id = any(a_aceite) and o.estado <> 'cancelada';                                                   -- regra 3

  select count(*) into c_sim from simulacoes where id = any(a_sim);
  select count(distinct simulacao_id) into c_prop from propostas where id = any(a_prop);
  select count(distinct simulacao_id) into c_aceite from propostas where id = any(a_aceite);
  select count(*) into c_enc from encomendas where id = any(a_enc);
  select count(*) into c_entregue from encomendas where id = any(a_enc) and estado = 'entregue';
  select count(*) into c_sem_prop from encomendas o where o.created_at >= v_ini and o.estado <> 'cancelada'
     and not exists (select 1 from propostas p where p.id = o.proposta_id and p.estado = 'aceite');
  select count(*) filter (where p.estado = 'enviada' and p.validade < current_date), count(*) filter (where p.estado = 'recusada')
    into c_expiradas, c_recusadas from propostas p where p.simulacao_id = any(a_sim);

  -- ---------- prestadores (estado atual + atividade no período)
  select count(*), count(*) filter (where estado = 'aprovada'), count(*) filter (where estado = 'pendente' and created_at < now() - interval '48 hours'),
         count(*) filter (where estado = 'pendente')
    into p_registos, p_aprovados, p_pend48, p_pend from empresas;
  select count(distinct empresa_id) into p_pagos from subscricoes where pago_em is not null or estado = 'ativa';
  select count(*) into p_disponiveis from empresas em where em.estado = 'aprovada'
     and exists (select 1 from subscricoes s where s.empresa_id = em.id and s.estado = 'ativa');
  select count(distinct empresa_id) into p_com_prop from propostas where id = any(a_prop);
  select count(distinct empresa_id) into p_com_enc from encomendas where id = any(a_enc);

  -- ---------- financeiro (coorte do período)
  select coalesce(sum(preco_estimado), 0) into f_sim from simulacoes where id = any(a_sim);
  select coalesce(sum(preco), 0) into f_prop from propostas where id = any(a_prop);
  select coalesce(sum(preco), 0) into f_aceite from propostas where id = any(a_aceite);
  select coalesce(sum(f.total), 0) into f_fat from faturas f where f.estado = 'valida' and f.encomenda_id = any(a_enc);   -- regra 4
  select coalesce(sum(case when pg.tipo = 'reembolso' then -pg.valor else pg.valor end), 0) into f_rec
    from pagamentos pg where pg.estado = 'pago' and pg.encomenda_id = any(a_enc);                                          -- regra 5
  -- comissões: regra ativa da empresa (ou a global) sobre o valor RECEBIDO de cada encomenda
  select coalesce(sum(case when rc.tipo_valor = 'percentagem' then x.recebido * rc.valor / 100 when rc.tipo_valor = 'fixo' then rc.valor else 0 end), 0),
         count(*) filter (where rc.id is null)
    into f_com, f_sem_regra
    from (select o.id, o.empresa_id, sum(case when pg.tipo = 'reembolso' then -pg.valor else pg.valor end) as recebido
            from encomendas o join pagamentos pg on pg.encomenda_id = o.id and pg.estado = 'pago' where o.id = any(a_enc) group by o.id, o.empresa_id having sum(pg.valor) > 0) x
    left join lateral (select * from regras_comissao c where c.ativa and (c.empresa_id = x.empresa_id or c.empresa_id is null)
                        order by (c.empresa_id is null), c.updated_at desc limit 1) rc on true;
  -- planos (regra 6: separados das comissões)
  select coalesce(sum(valor) filter (where tipo = 'recibo' and estado = 'paga' and emitida_em >= v_ini), 0) into pl_recebido from faturas_plataforma;
  select coalesce(sum(valor) filter (where estado = 'pendente' and pago_em is null), 0), count(*) filter (where estado = 'ativa'),
         coalesce(sum(case when periodicidade = 'anual' then valor / 12 else valor end) filter (where estado = 'ativa'), 0)
    into pl_por_confirmar, pl_ativos, pl_mrr from subscricoes;

  -- ---------- gargalo principal: a primeira condição que trava tudo; senão, a etapa com pior passagem
  if p_disponiveis = 0 then
    g := jsonb_build_object('funil', 'prestadores', 'etapa', 'disponiveis', 'titulo', 'Sem prestadores disponíveis',
      'mensagem', case when p_pend > 0 then p_pend || ' pedido(s) de inscrição à espera de validação. Sem prestadores aprovados com subscrição ativa não há propostas.'
                       else 'Não há prestadores aprovados com subscrição ativa: os clientes não recebem propostas.' end,
      'acao', 'Validar pedidos de inscrição', 'pagina', 'adminProviderRequests');
  elsif c_sim = 0 then
    g := jsonb_build_object('funil', 'clientes', 'etapa', 'simulacoes', 'titulo', 'Sem procura', 'mensagem', 'Não houve simulações no período.',
      'acao', 'Divulgar o simulador e a pesquisa marítima', 'pagina', 'dashboard');
  else
    for e in select * from (values
        ('clientes', 'propostas', 'Simulações sem proposta', c_prop::numeric, c_sim::numeric, 'Pedir aos prestadores que respondam às simulações', 'adminOperations'),
        ('clientes', 'aceites', 'Propostas não aceites', c_aceite::numeric, c_prop::numeric, 'Rever preços e prazos das propostas', 'adminOperations'),
        ('clientes', 'encomendas', 'Aceites sem encomenda', c_enc::numeric, c_aceite::numeric, 'Acompanhar a criação das encomendas', 'adminOperations'),
        ('financeiro', 'faturado', 'Valor contratado por faturar', f_fat, f_aceite, 'Pedir aos prestadores que registem as faturas', 'adminBilling'),
        ('financeiro', 'recebido', 'Faturado por receber', f_rec, f_fat, 'Confirmar pagamentos em falta', 'adminBilling')) t(funil, etapa, titulo, num, den, acao, pagina)
    loop
      if e.den > 0 then
        taxa := least(e.num / e.den, 1);
        if taxa < melhor then melhor := taxa;
          g := jsonb_build_object('funil', e.funil, 'etapa', e.etapa, 'titulo', e.titulo, 'taxa', round(taxa * 100),
            'mensagem', 'Só ' || round(taxa * 100) || ' % passam esta etapa.', 'acao', e.acao, 'pagina', e.pagina);
        end if;
      end if;
    end loop;
    if g is null then g := jsonb_build_object('funil', 'clientes', 'etapa', 'aceites', 'titulo', 'Sem gargalo', 'mensagem', 'O funil está a avançar sem bloqueios.', 'acao', '', 'pagina', 'dashboard'); end if;
  end if;

  r := jsonb_build_object('gerado_em', now(), 'periodo_dias', p_dias, 'gargalo', g,
    'clientes', jsonb_build_object('etapas', jsonb_build_array(
        jsonb_build_object('id', 'simulacoes', 'nome', 'Simulações', 'n', c_sim, 'pagina', 'adminOperations'),
        jsonb_build_object('id', 'propostas', 'nome', 'Com proposta válida', 'n', c_prop, 'pagina', 'adminOperations', 'extra', jsonb_build_object('expiradas', c_expiradas, 'recusadas', c_recusadas)),
        jsonb_build_object('id', 'aceites', 'nome', 'Aceites', 'n', c_aceite, 'pagina', 'adminOperations'),
        jsonb_build_object('id', 'encomendas', 'nome', 'Encomendas', 'n', c_enc, 'pagina', 'adminOperations', 'extra', jsonb_build_object('sem_proposta_aceite', c_sem_prop)),
        jsonb_build_object('id', 'entregues', 'nome', 'Entregues', 'n', c_entregue, 'pagina', 'adminOperations'))),
    'prestadores', jsonb_build_object('etapas', jsonb_build_array(
        jsonb_build_object('id', 'registos', 'nome', 'Registados', 'n', p_registos, 'pagina', 'adminProviderRequests', 'extra', jsonb_build_object('pendentes', p_pend, 'pendentes_48h', p_pend48)),
        jsonb_build_object('id', 'pagos', 'nome', 'Subscrição paga', 'n', p_pagos, 'pagina', 'adminPlans'),
        jsonb_build_object('id', 'aprovados', 'nome', 'Aprovados', 'n', p_aprovados, 'pagina', 'adminActiveProviders'),
        jsonb_build_object('id', 'disponiveis', 'nome', 'Disponíveis', 'n', p_disponiveis, 'pagina', 'adminActiveProviders'),
        jsonb_build_object('id', 'com_proposta', 'nome', 'Com propostas', 'n', p_com_prop, 'pagina', 'adminActiveProviders'),
        jsonb_build_object('id', 'com_encomenda', 'nome', 'Com encomendas', 'n', p_com_enc, 'pagina', 'adminActiveProviders'))),
    'financeiro', jsonb_build_object('etapas', jsonb_build_array(
        jsonb_build_object('id', 'simulado', 'nome', 'Valor simulado', 'v', f_sim, 'pagina', 'adminOperations'),
        jsonb_build_object('id', 'proposto', 'nome', 'Valor proposto', 'v', f_prop, 'pagina', 'adminOperations'),
        jsonb_build_object('id', 'contratado', 'nome', 'Valor contratado', 'v', f_aceite, 'pagina', 'adminOperations'),
        jsonb_build_object('id', 'faturado', 'nome', 'Valor faturado', 'v', f_fat, 'pagina', 'adminBilling'),
        jsonb_build_object('id', 'recebido', 'nome', 'Valor recebido', 'v', f_rec, 'pagina', 'adminBilling'),
        jsonb_build_object('id', 'comissoes', 'nome', 'Comissões Elolog', 'v', round(f_com, 2), 'pagina', 'adminCommissions', 'extra', jsonb_build_object('sem_regra', f_sem_regra))),
      'planos', jsonb_build_object('recebido', pl_recebido, 'por_confirmar', pl_por_confirmar, 'ativos', pl_ativos, 'mrr', round(pl_mrr, 2))),
    'resumo', jsonb_build_object('prestadores_disponiveis', p_disponiveis, 'simulacoes', c_sim,
      'conversao', case when c_sim > 0 then round(c_enc * 100.0 / c_sim) end, 'valor_contratado', f_aceite,
      'receita_comissoes', round(f_com, 2), 'receita_planos', pl_recebido));
  return r;
end $$;
revoke all on function public.painel_funis(integer) from public, anon;
grant execute on function public.painel_funis(integer) to authenticated;

-- ===== 00160_encomendas_diretas.sql =====
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

-- ===== 00161_encomendas_diretas_revisao.sql =====
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

commit;

-- ===== 00162_etapas_operacao_a.sql (fora da transação: novos valores de tipo) =====
-- v100 (parte A) — novas etapas: «Disponível» (aviso ao cliente) entre «Destino» e «Levantado», e a tarefa de processamento no destino.
-- Só acrescenta valores aos tipos existentes (têm de ficar numa transação própria, antes da parte B).
alter type estado_encomenda add value if not exists 'disponivel' after 'destino';
alter type tipo_trabalho add value if not exists 'processamento_destino';

begin;
-- ===== 00162_etapas_operacao_b.sql =====
-- v100 (parte B) — Regras automáticas de movimentação das encomendas, histórico obrigatório e ficha da operação.
-- Só ACRESCENTA colunas, transições e funções; transitar_encomenda() continua a existir (passa a usar as novas regras).
-- Regras: só avança com os requisitos da etapa; aprovação dispensada só no fluxo autorizado direto para armazém (com motivo de exceção);
-- pagamento pendente gera alerta financeiro; receção no armazém exige quantidade (e ocorrências se não bater certo); expedição exige navio,
-- viagem e data prevista; chegada cria tarefa de processamento no destino; Disponível exige essa tarefa concluída; Levantado só a partir de
-- Disponível e com confirmação do levantamento. Nunca «Em trânsito» → «Levantado» diretamente.

alter table encomendas add column if not exists navio text;
alter table encomendas add column if not exists viagem text;
alter table encomendas add column if not exists partida_prevista date;
alter table encomendas add column if not exists chegada_prevista date;
alter table recibos_armazem add column if not exists quantidade_recebida int check (quantidade_recebida is null or quantidade_recebida >= 0);
alter table encomenda_historico add column if not exists codigo text;
alter table encomenda_historico add column if not exists responsavel text;
alter table encomenda_historico add column if not exists prestador text;
alter table encomenda_historico add column if not exists documentos uuid[];
alter table encomenda_historico add column if not exists motivo_excecao text;

insert into encomenda_transicoes (de, para, papeis) select * from (values
  ('destino'::estado_encomenda, 'disponivel'::estado_encomenda, '{admin_empresa,operador}'::papel_funcionario[]),
  ('disponivel', 'entregue', '{admin_empresa,operador,operador_terreno}'),
  ('aprovacao', 'armazenamento', '{admin_empresa,operador,armazem}')) v(de, para, papeis)
 where not exists (select 1 from encomenda_transicoes t where t.de = v.de and t.para = v.para);

-- Requisitos de cada etapa (usado ao avançar e na ficha)
create or replace function private.encomenda_falta(e encomendas, p_para estado_encomenda, p_excecao text default null) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare f text[] := '{}'; r recibos_armazem;
begin
  if e.estado = 'aprovacao' and p_para = 'armazenamento' then          -- aprovação dispensada (fluxo autorizado)
    if not (e.criada_no_terreno or private.meu_papel() = 'admin_empresa') then f := f || text 'fluxo autorizado direto para armazém (registo no terreno ou administrador da empresa)'; end if;
    if length(trim(coalesce(p_excecao, ''))) < 5 then f := f || text 'motivo de exceção para dispensar a aprovação'; end if;
  end if;
  if p_para = 'armazenamento' then
    if e.criada_no_terreno then
      if e.cliente_id is null and coalesce(e.cliente_nome, '') = '' then f := f || text 'cliente'; end if;
      if coalesce(e.origem, '') = '' or coalesce(e.destino, '') = '' then f := f || text 'rota'; end if;
      if not exists (select 1 from pagamentos pg where pg.encomenda_id = e.id and pg.tipo <> 'reembolso' and pg.estado in ('pendente','parcial','pago')) then f := f || text 'primeiro pagamento'; end if;
      if e.assinatura_documento_id is null and e.pin_validacao_hash is null then f := f || text 'assinatura ou PIN do cliente'; end if;
    end if;
    select * into r from recibos_armazem where encomenda_id = e.id;
    if r.encomenda_id is null or not r.confirmado or r.quantidade_recebida is null then f := f || text 'receção no armazém com quantidade confirmada';
    elsif e.quantidade is not null and r.quantidade_recebida <> e.quantidade and coalesce(trim(r.ocorrencias), '') = '' then
      f := f || ('ocorrência a explicar a diferença de quantidade (' || r.quantidade_recebida || ' de ' || e.quantidade || ')'); end if;
  end if;
  if p_para = 'expedicao' and not exists (select 1 from recibos_armazem ra where ra.encomenda_id = e.id and ra.confirmado and ra.carga_conferida) then
    f := f || text 'receção confirmada e carga conferida pelo armazém'; end if;
  if p_para = 'em_transito' and not (coalesce(e.navio, '') <> '' and coalesce(e.viagem, '') <> '' and e.partida_prevista is not null)
     and not exists (select 1 from manifesto_encomendas me join manifestos m on m.id = me.manifesto_id where me.encomenda_id = e.id
                      and coalesce(m.transportador, '') <> '' and coalesce(m.numero_viagem, '') <> '' and m.partida is not null) then
    f := f || text 'navio, viagem e data prevista de partida'; end if;
  if p_para = 'disponivel' and not exists (select 1 from trabalhos_terreno t where t.encomenda_id = e.id and t.tipo = 'processamento_destino' and t.estado = 'concluida') then
    f := f || text 'processamento no destino concluído'; end if;
  if p_para = 'entregue' then
    if e.estado <> 'disponivel' then f := f || text 'passar por Destino e Disponível (chegada e aviso ao cliente)'; end if;
    if not exists (select 1 from entregas en where en.encomenda_id = e.id and coalesce(en.identificacao, '') <> '' and (en.assinatura_documento_id is not null or en.pin_validado)) then
      f := f || text 'confirmação do levantamento (identificação e assinatura/PIN)'; end if;
  end if;
  return f;
end $$;

-- Avançar uma encomenda (com histórico obrigatório)
create or replace function public.avancar_encomenda(p_encomenda uuid, p_para estado_encomenda, p_nota text default null,
  p_documentos uuid[] default null, p_excecao text default null) returns encomendas
language plpgsql security definer set search_path = public as $$
declare v_enc encomendas; v_papel papel_funcionario; v_falta text[]; v_resp text; v_prest text;
begin
  select * into v_enc from encomendas where id = p_encomenda for update;
  if not found then raise exception 'Encomenda inexistente.'; end if;
  if private.minha_empresa() is distinct from v_enc.empresa_id then raise exception 'Sem permissão para esta encomenda (inicie a sessão da empresa).'; end if;
  v_papel := private.meu_papel();
  if v_papel is null then raise exception 'Sem permissão para esta encomenda.'; end if;
  if v_enc.suspensa and p_para <> 'cancelada' then raise exception 'A encomenda está suspensa (%). Retome-a antes de mudar o estado.', coalesce(v_enc.suspensa_motivo, 'ocorrência'); end if;
  if not exists (select 1 from encomenda_transicoes t where t.de = v_enc.estado and t.para = p_para and v_papel = any (t.papeis)) then
    raise exception 'Transição % → % não permitida para o papel %.', v_enc.estado, p_para, v_papel; end if;
  if v_papel = 'operador_terreno' and not (coalesce(v_enc.criado_por = auth.uid(), false)
       or exists (select 1 from trabalhos_terreno tt where tt.encomenda_id = v_enc.id and tt.operador_id = auth.uid())) then
    raise exception 'Este serviço não está atribuído ao operador.'; end if;
  if p_documentos is not null and exists (select 1 from unnest(p_documentos) d where not exists (select 1 from documentos x where x.id = d and (x.empresa_id = v_enc.empresa_id or x.encomenda_id = v_enc.id))) then
    raise exception 'Documento inválido para esta encomenda.'; end if;
  v_falta := private.encomenda_falta(v_enc, p_para, p_excecao);
  if cardinality(v_falta) > 0 then raise exception 'Não é possível avançar. Complete: %.', array_to_string(v_falta, ', '); end if;
  perform set_config('elolog.transicao', 'on', true);
  update encomendas set estado = p_para where id = v_enc.id;
  perform set_config('elolog.transicao', 'off', true);
  select nome into v_resp from funcionarios where id = auth.uid();
  select coalesce(nome_comercial, nome) into v_prest from empresas where id = v_enc.empresa_id;
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id, codigo, responsavel, prestador, documentos, motivo_excecao)
    values (v_enc.id, v_enc.empresa_id, v_enc.estado, p_para, nullif(trim(p_nota), ''), auth.uid(), v_enc.codigo, v_resp, v_prest, p_documentos, nullif(trim(p_excecao), ''));
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, antes, depois, motivo)
    values (v_enc.empresa_id, auth.uid(), v_papel::text, 'transicao_encomenda', 'encomendas', v_enc.id::text,
            jsonb_build_object('estado', v_enc.estado), jsonb_build_object('estado', p_para), coalesce(nullif(trim(p_excecao), ''), p_nota));
  if v_enc.cliente_id is not null then
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (v_enc.cliente_id, 'estado_encomenda', case when p_para = 'disponivel' then 'A sua encomenda ' || v_enc.codigo || ' está disponível para levantamento'
              else 'A sua encomenda ' || v_enc.codigo || ' mudou de estado' end, p_para::text, 'encomendas', v_enc.id); end if;
  if p_para = 'destino' then                                             -- chegada: tarefa de processamento no destino
    insert into trabalhos_terreno (empresa_id, encomenda_id, tipo, data, notas) values (v_enc.empresa_id, v_enc.id, 'processamento_destino', current_date, 'Processar a chegada: conferir carga e preparar a disponibilização.');
    insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (v_enc.empresa_id, 'tarefa_destino', 'Chegada de ' || v_enc.codigo || ': processar no destino', v_enc.destino, 'encomendas', v_enc.id); end if;
  select * into v_enc from encomendas where id = p_encomenda;
  return v_enc;
end $$;

-- A função antiga mantém o nome e passa a usar as novas regras
create or replace function public.transitar_encomenda(p_encomenda uuid, p_para estado_encomenda, p_nota text default null) returns encomendas
language sql security definer set search_path = public as $$ select public.avancar_encomenda(p_encomenda, p_para, p_nota, null, null) $$;

-- Ações de etapa (não mudam o estado; ficam no histórico)
create or replace function private.encomenda_da_empresa(p_encomenda uuid, p_papeis text[]) returns encomendas language plpgsql security definer set search_path = public as $$
declare e encomendas; begin
  select * into e from encomendas where id = p_encomenda;
  if not found or private.minha_empresa() is distinct from e.empresa_id then raise exception 'Sem permissão para esta encomenda.'; end if;
  if not private.papel_em(p_papeis) then raise exception 'A sua função não permite esta ação.'; end if;
  return e; end $$;
create or replace function private.encomenda_nota(e encomendas, p_nota text) returns void language sql security definer set search_path = public as $$
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id, codigo, responsavel, prestador)
  select e.id, e.empresa_id, e.estado, e.estado, p_nota, auth.uid(), e.codigo, (select nome from funcionarios where id = auth.uid()),
         (select coalesce(nome_comercial, nome) from empresas where id = e.empresa_id) $$;

create or replace function public.encomenda_rececao_armazem(p_encomenda uuid, p_quantidade int, p_conferida boolean, p_ocorrencias text default null,
  p_localizacao text default null, p_armazem uuid default null) returns void language plpgsql security definer set search_path = public as $$
declare e encomendas;
begin
  e := private.encomenda_da_empresa(p_encomenda, array['admin_empresa','operador','armazem']);
  if p_quantidade is null or p_quantidade < 0 then raise exception 'Indique a quantidade recebida.'; end if;
  if e.quantidade is not null and p_quantidade <> e.quantidade and length(trim(coalesce(p_ocorrencias, ''))) < 5 then
    raise exception 'A quantidade recebida (%) é diferente da prevista (%). Descreva a ocorrência.', p_quantidade, e.quantidade; end if;
  insert into recibos_armazem (encomenda_id, armazem_id, confirmado, carga_conferida, localizacao, ocorrencias, confirmado_por, confirmado_em, quantidade_recebida)
    values (e.id, p_armazem, true, coalesce(p_conferida, false), nullif(trim(p_localizacao), ''), nullif(trim(p_ocorrencias), ''), auth.uid(), now(), p_quantidade)
  on conflict (encomenda_id) do update set armazem_id = coalesce(excluded.armazem_id, recibos_armazem.armazem_id), confirmado = true, carga_conferida = excluded.carga_conferida,
    localizacao = coalesce(excluded.localizacao, recibos_armazem.localizacao), ocorrencias = excluded.ocorrencias, confirmado_por = auth.uid(), confirmado_em = now(),
    quantidade_recebida = excluded.quantidade_recebida, updated_at = now();
  perform private.encomenda_nota(e, 'Receção no armazém: ' || p_quantidade || ' volume(s)' || case when p_conferida then ', carga conferida' else '' end ||
    coalesce('. Ocorrências: ' || nullif(trim(p_ocorrencias), ''), ''));
end $$;

create or replace function public.encomenda_expedicao(p_encomenda uuid, p_navio text, p_viagem text, p_partida date, p_chegada date default null) returns void
language plpgsql security definer set search_path = public as $$
declare e encomendas;
begin
  e := private.encomenda_da_empresa(p_encomenda, array['admin_empresa','operador','armazem']);
  if length(trim(coalesce(p_navio, ''))) < 2 or length(trim(coalesce(p_viagem, ''))) < 1 or p_partida is null then raise exception 'Indique o navio, a viagem e a data prevista de partida.'; end if;
  if p_chegada is not null and p_chegada < p_partida then raise exception 'A chegada prevista não pode ser antes da partida.'; end if;
  update encomendas set navio = trim(p_navio), viagem = trim(p_viagem), partida_prevista = p_partida, chegada_prevista = p_chegada where id = e.id;
  perform private.encomenda_nota(e, 'Expedição: navio ' || trim(p_navio) || ', viagem ' || trim(p_viagem) || ', partida ' || to_char(p_partida, 'DD/MM/YYYY') ||
    coalesce(', chegada ' || to_char(p_chegada, 'DD/MM/YYYY'), ''));
end $$;

create or replace function public.encomenda_processamento_destino(p_encomenda uuid, p_nota text default null) returns void
language plpgsql security definer set search_path = public as $$
declare e encomendas;
begin
  e := private.encomenda_da_empresa(p_encomenda, array['admin_empresa','operador','armazem']);
  if e.estado <> 'destino' then raise exception 'O processamento no destino faz-se depois de confirmar a chegada.'; end if;
  update trabalhos_terreno set estado = 'concluida', notas = coalesce(nullif(trim(p_nota), ''), notas) where encomenda_id = e.id and tipo = 'processamento_destino' and estado <> 'concluida';
  if not found then raise exception 'Não há tarefa de processamento por concluir.'; end if;
  perform private.encomenda_nota(e, 'Processamento no destino concluído' || coalesce(': ' || nullif(trim(p_nota), ''), '.'));
end $$;

create or replace function public.encomenda_levantamento(p_encomenda uuid, p_identificacao text, p_documento uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e encomendas;
begin
  e := private.encomenda_da_empresa(p_encomenda, array['admin_empresa','operador','operador_terreno']);
  if e.estado <> 'disponivel' then raise exception 'O levantamento só se confirma com a encomenda Disponível.'; end if;
  if length(trim(coalesce(p_identificacao, ''))) < 3 then raise exception 'Indique a identificação de quem levanta.'; end if;
  if p_documento is null or not exists (select 1 from documentos d where d.id = p_documento and d.empresa_id = e.empresa_id) then raise exception 'Anexe o comprovativo de entrega assinado.'; end if;
  insert into entregas (encomenda_id, identificacao, assinatura_documento_id, entregue_por, entregue_em) values (e.id, trim(p_identificacao), p_documento, auth.uid(), now())
  on conflict (encomenda_id) do update set identificacao = excluded.identificacao, assinatura_documento_id = excluded.assinatura_documento_id, entregue_por = auth.uid(), entregue_em = now(), updated_at = now();
  perform private.encomenda_nota(e, 'Levantamento confirmado: ' || trim(p_identificacao));
end $$;

-- Pagamento pendente → alerta financeiro (uma vez por pagamento a cada 24 h)
create or replace function private.alerta_pagamento_pendente() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.tipo <> 'reembolso' and new.estado in ('pendente', 'parcial') and (tg_op = 'INSERT' or old.estado is distinct from new.estado)
     and not exists (select 1 from notificacoes n where n.referencia_id = new.id and n.tipo = 'alerta_financeiro' and n.created_at > now() - interval '24 hours') then
    insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      select new.empresa_id, 'alerta_financeiro', 'Pagamento ' || new.estado || ' — ' || coalesce(e.codigo, ''), new.valor || ' ' || new.moeda, 'pagamentos', new.id
        from encomendas e where e.id = new.encomenda_id;
  end if;
  return new;
end $$;
create or replace trigger alerta_pagamento_pendente after insert or update on pagamentos for each row execute function private.alerta_pagamento_pendente();

revoke all on function public.avancar_encomenda(uuid, estado_encomenda, text, uuid[], text), public.encomenda_rececao_armazem(uuid, int, boolean, text, text, uuid),
  public.encomenda_expedicao(uuid, text, text, date, date), public.encomenda_processamento_destino(uuid, text), public.encomenda_levantamento(uuid, text, uuid) from public, anon;
grant execute on function public.avancar_encomenda(uuid, estado_encomenda, text, uuid[], text), public.encomenda_rececao_armazem(uuid, int, boolean, text, text, uuid),
  public.encomenda_expedicao(uuid, text, text, date, date), public.encomenda_processamento_destino(uuid, text), public.encomenda_levantamento(uuid, text, uuid) to authenticated;
revoke all on function private.encomenda_falta(encomendas, estado_encomenda, text), private.encomenda_da_empresa(uuid, text[]), private.encomenda_nota(encomendas, text) from public, anon, authenticated;

-- ===== 00163_ficha_operacao.sql =====
-- v100 — Ficha da operação: tudo o que é preciso para trabalhar uma encomenda (resumo, percurso de 11 etapas, carga, financeiro,
-- histórico) e as próximas ações com os requisitos em falta. Só leitura; administração da plataforma ou a empresa da encomenda.

create or replace function public.encomenda_ficha(p_codigo text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e encomendas; adm boolean := private.e_admin_plataforma(); papel papel_funcionario := private.meu_papel(); r jsonb;
  pago numeric; comissao numeric; regra regras_comissao; ordem text[] := array['aprovacao','agendamento','recolha','armazenamento','expedicao','em_transito','destino','disponivel','entregue'];
begin
  select * into e from encomendas where codigo = upper(trim(p_codigo)) or id::text = trim(p_codigo);
  if not found then raise exception 'Encomenda não encontrada.'; end if;
  if not adm and private.minha_empresa() is distinct from e.empresa_id then raise exception 'Sem permissão para esta encomenda.'; end if;
  select coalesce(sum(case when tipo = 'reembolso' then -valor else valor end), 0) into pago from pagamentos where encomenda_id = e.id and estado = 'pago';
  select * into regra from regras_comissao c where c.ativa and (c.empresa_id = e.empresa_id or c.empresa_id is null) order by (c.empresa_id is null), c.updated_at desc limit 1;
  comissao := case when regra.id is null then null when regra.tipo_valor = 'percentagem' then round(e.preco_total * regra.valor / 100, 2) else regra.valor end;
  r := jsonb_build_object(
    'encomenda', to_jsonb(e) - 'pin_validacao_hash',
    'prestador', (select coalesce(nome_comercial, nome) from empresas where id = e.empresa_id),
    'cliente', (select jsonb_build_object('nome', coalesce(c.nome, e.cliente_nome), 'email', c.email, 'telefone', coalesce(c.telefone, e.cliente_telefone), 'nif', coalesce(c.nif, e.cliente_nif))
                  from (select 1) x left join clientes c on c.id = e.cliente_id),
    'simulacao', (select jsonb_build_object('codigo', s.codigo, 'em', s.created_at) from simulacoes s where s.id = e.simulacao_id),
    'proposta', (select jsonb_build_object('preco', p.preco, 'estado', p.estado, 'em', p.respondida_em) from propostas p where p.id = e.proposta_id),
    'chegou_em', (select jsonb_object_agg(para, em) from (select h.para::text para, min(h.created_at) em from encomenda_historico h where h.encomenda_id = e.id group by h.para) t),
    'armazem', (select to_jsonb(ra) || jsonb_build_object('armazem', a.nome) from recibos_armazem ra left join armazens a on a.id = ra.armazem_id where ra.encomenda_id = e.id),
    'entrega', (select to_jsonb(en) from entregas en where en.encomenda_id = e.id),
    'tarefa_destino', (select jsonb_build_object('estado', t.estado, 'notas', t.notas, 'data', t.data) from trabalhos_terreno t where t.encomenda_id = e.id and t.tipo = 'processamento_destino' order by t.created_at desc limit 1),
    'documentos', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'nome', d.nome, 'categoria', d.categoria, 'mime', d.mime, 'caminho', d.storage_path, 'em', d.created_at) order by d.created_at), '[]'::jsonb)
                     from documentos d where d.encomenda_id = e.id and d.verificado),
    'pagamentos', (select coalesce(jsonb_agg(jsonb_build_object('codigo', pg.codigo, 'tipo', pg.tipo, 'valor', pg.valor, 'estado', pg.estado, 'metodo', pg.metodo, 'pago_em', pg.pago_em, 'em', pg.created_at) order by pg.created_at), '[]'::jsonb)
                     from pagamentos pg where pg.encomenda_id = e.id),
    'financeiro', jsonb_build_object('preco', e.preco_total, 'pago', pago, 'em_divida', greatest(e.preco_total - pago, 0), 'comissao', comissao,
                     'comissao_regra', case when regra.id is null then null when regra.tipo_valor = 'percentagem' then regra.valor || ' %' else regra.valor || ' € fixo' end,
                     'pendentes', (select count(*) from pagamentos pg where pg.encomenda_id = e.id and pg.estado in ('pendente','parcial'))),
    'historico', (select coalesce(jsonb_agg(jsonb_build_object('de', h.de, 'para', h.para, 'em', h.created_at, 'responsavel', coalesce(h.responsavel, f.nome), 'prestador', h.prestador,
                     'nota', h.nota, 'motivo_excecao', h.motivo_excecao, 'documentos', (select jsonb_agg(d.nome) from documentos d where d.id = any (h.documentos))) order by h.id), '[]'::jsonb)
                     from encomenda_historico h left join funcionarios f on f.id = h.user_id where h.encomenda_id = e.id),
    'ocorrencias', (select coalesce(jsonb_agg(jsonb_build_object('codigo', o.codigo, 'tipo', o.tipo, 'gravidade', o.gravidade, 'estado', o.estado, 'descricao', o.descricao, 'resolucao', o.resolucao, 'em', o.created_at) order by o.created_at), '[]'::jsonb)
                     from ocorrencias o where o.encomenda_id = e.id),
    'proximos', (select coalesce(jsonb_agg(jsonb_build_object('para', t.para, 'permitido', papel is not null and papel = any (t.papeis) and not adm,
                     'excecao', t.de = 'aprovacao' and t.para = 'armazenamento', 'falta', to_jsonb(private.encomenda_falta(e, t.para, case when t.de = 'aprovacao' and t.para = 'armazenamento' then 'motivo a indicar' end)))
                     order by array_position(ordem, t.para::text) nulls last), '[]'::jsonb)
                     from encomenda_transicoes t where t.de = e.estado and t.para <> 'cancelada' and not (t.de = 'destino' and t.para = 'entregue')),
    'pode_cancelar', exists (select 1 from encomenda_transicoes t where t.de = e.estado and t.para = 'cancelada' and papel = any (t.papeis)),
    'papel', coalesce(papel::text, case when adm then 'administracao' end));
  return r;
end $$;
revoke all on function public.encomenda_ficha(text) from public, anon;
grant execute on function public.encomenda_ficha(text) to authenticated;

-- ===== 00164_painel_vivo.sql =====
-- v101 — «Painel ao vivo» do Centro de Controlo (administração). Só ACRESCENTA uma função de leitura:
-- não altera tabelas, dados, autenticação, permissões, fluxos de encomendas, comissões nem planos.
-- Tudo vem dos dados reais: comissões pela regra ativa (da empresa ou global) sobre pagamentos confirmados hoje,
-- planos pelos recibos pagos hoje, navios pelas encomendas expedidas (navio/viagem) e pela posição AIS quando existe.

create or replace function public.painel_vivo() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_hoje date := current_date; r jsonb;
  k_com numeric; k_planos numeric; k_media numeric; k_curso int; k_novas int; k_novas_ant int;
  k_prazo_n int; k_prazo_ok int; k_prazo_ant_n int; k_prazo_ant_ok int; k_risco numeric; k_risco_n int; k_atras int;
begin
  if not private.e_admin_plataforma() then raise exception 'Apenas a administração da plataforma.'; end if;

  -- receita da Elolog hoje: comissões (regra ativa da empresa, senão a global) sobre o recebido hoje + planos pagos hoje
  with pg as (select p.empresa_id, p.pago_em::date d, sum(case when p.tipo = 'reembolso' then -p.valor else p.valor end) v
                from pagamentos p where p.estado = 'pago' and p.pago_em >= v_hoje - 14 group by 1, 2),
       c as (select pg.d, case when rc.tipo_valor = 'percentagem' then pg.v * rc.valor / 100 when rc.tipo_valor = 'fixo' then rc.valor else 0 end com
               from pg left join lateral (select * from regras_comissao x where x.ativa and (x.empresa_id = pg.empresa_id or x.empresa_id is null)
                                          order by (x.empresa_id is null), x.updated_at desc limit 1) rc on true)
  select coalesce(sum(com) filter (where d = v_hoje), 0), coalesce(sum(com) filter (where d < v_hoje), 0) / 14 into k_com, k_media from c;
  select coalesce(sum(valor), 0) into k_planos from faturas_plataforma where tipo = 'recibo' and estado = 'paga' and emitida_em::date = v_hoje;
  k_media := k_media + coalesce((select sum(valor) from faturas_plataforma where tipo = 'recibo' and estado = 'paga'
                                  and emitida_em::date >= v_hoje - 14 and emitida_em::date < v_hoje), 0) / 14;

  select count(*) filter (where estado not in ('entregue', 'cancelada')),
         count(*) filter (where created_at >= now() - interval '30 days'),
         count(*) filter (where created_at >= now() - interval '60 days' and created_at < now() - interval '30 days'),
         count(*) filter (where estado not in ('entregue', 'cancelada') and coalesce(chegada_prevista, data_prevista) < v_hoje)
    into k_curso, k_novas, k_novas_ant, k_atras from encomendas;
  select count(*) filter (where en.entregue_em >= now() - interval '30 days'),
         count(*) filter (where en.entregue_em >= now() - interval '30 days' and en.entregue_em::date <= coalesce(e.chegada_prevista, e.data_prevista, en.entregue_em::date)),
         count(*) filter (where en.entregue_em >= now() - interval '60 days' and en.entregue_em < now() - interval '30 days'),
         count(*) filter (where en.entregue_em >= now() - interval '60 days' and en.entregue_em < now() - interval '30 days'
                          and en.entregue_em::date <= coalesce(e.chegada_prevista, e.data_prevista, en.entregue_em::date))
    into k_prazo_n, k_prazo_ok, k_prazo_ant_n, k_prazo_ant_ok
    from entregas en join encomendas e on e.id = en.encomenda_id and e.estado = 'entregue';
  select coalesce(sum(valor), 0), count(*) into k_risco, k_risco_n from pagamentos where estado in ('pendente', 'parcial') and tipo <> 'reembolso';

  r := jsonb_build_object('gerado_em', now(),
    'kpis', jsonb_build_object(
      'receita_hoje', round(k_com + k_planos, 2), 'comissoes_hoje', round(k_com, 2), 'planos_hoje', k_planos, 'receita_media_14d', round(k_media, 2),
      'em_curso', k_curso, 'novas_30d', k_novas, 'novas_30d_anteriores', k_novas_ant,
      'prazo_pct', case when k_prazo_n > 0 then round(k_prazo_ok * 100.0 / k_prazo_n, 1) end,
      'prazo_pct_anterior', case when k_prazo_ant_n > 0 then round(k_prazo_ant_ok * 100.0 / k_prazo_ant_n, 1) end,
      'risco_valor', k_risco, 'risco_pagamentos', k_risco_n, 'atrasadas', k_atras),

    -- viagens: encomendas expedidas ou em trânsito agrupadas por navio e viagem; posição AIS se o navio é seguido
    'viagens', coalesce((select jsonb_agg(v order by v->>'partida') from (
      select jsonb_build_object('navio', e.navio, 'viagem', e.viagem, 'origem', mode() within group (order by e.origem), 'destino', mode() within group (order by e.destino),
        'encomendas', count(*), 'codigos', jsonb_agg(e.codigo order by e.codigo), 'partida', min(e.partida_prevista), 'chegada', max(e.chegada_prevista),
        'em_transito', bool_or(e.estado = 'em_transito'), 'atrasada', bool_or(e.estado <> 'destino' and e.chegada_prevista < v_hoje),
        'prestadores', (select jsonb_agg(distinct coalesce(em.nome_comercial, em.nome)) from encomendas e2 join empresas em on em.id = e2.empresa_id
                         where e2.navio = e.navio and coalesce(e2.viagem, '') = coalesce(e.viagem, '') and e2.estado in ('expedicao', 'em_transito')),
        'ais', (select jsonb_build_object('lat', p.latitude, 'lon', p.longitude, 'nos', p.velocidade_nos, 'eta', p.eta, 'em', p.posicao_em)
                  from navios_posicoes p where lower(p.nome) = lower(e.navio) and p.latitude is not null order by p.posicao_em desc nulls last limit 1)) v
        from encomendas e where e.estado in ('expedicao', 'em_transito') and coalesce(e.navio, '') <> ''
       group by e.navio, e.viagem) x), '[]'::jsonb),

    -- encomendas por porto: antes de embarcar contam na origem, depois na chegada
    'portos', coalesce((select jsonb_agg(jsonb_build_object('cidade', cidade, 'n', n) order by n desc) from (
      select case when estado in ('em_transito', 'destino', 'disponivel') then destino else origem end cidade, count(*) n
        from encomendas where estado not in ('entregue', 'cancelada') group by 1) p where cidade is not null), '[]'::jsonb),

    'veiculos', coalesce((select jsonb_agg(jsonb_build_object('matricula', v.matricula, 'descricao', v.descricao, 'empresa', coalesce(em.nome_comercial, em.nome),
        'servicos_hoje', (select count(*) from trabalhos_terreno t where t.veiculo_id = v.id and t.data = v_hoje),
        'por_fazer', (select count(*) from trabalhos_terreno t where t.veiculo_id = v.id and t.data = v_hoje and t.estado::text <> 'concluida'))
        order by em.nome, v.matricula) from veiculos v join empresas em on em.id = v.empresa_id where v.ativo), '[]'::jsonb),

    'armazens', coalesce((select jsonb_agg(jsonb_build_object('nome', a.nome, 'morada', a.morada, 'empresa', coalesce(em.nome_comercial, em.nome),
        'encomendas', (select count(*) from recibos_armazem ra join encomendas e on e.id = ra.encomenda_id where ra.armazem_id = a.id and e.estado = 'armazenamento'),
        'volumes', (select coalesce(sum(ra.quantidade_recebida), 0) from recibos_armazem ra join encomendas e on e.id = ra.encomenda_id where ra.armazem_id = a.id and e.estado = 'armazenamento'))
        order by a.nome) from armazens a join empresas em on em.id = a.empresa_id where a.ativo), '[]'::jsonb),

    'recentes', coalesce((select jsonb_agg(x order by x->>'atualizada' desc) from (
      select jsonb_build_object('codigo', e.codigo, 'origem', e.origem, 'destino', e.destino, 'chegada', coalesce(e.chegada_prevista, e.data_prevista),
        'transporte', case when coalesce(e.navio, '') <> '' then e.navio || coalesce(' ' || e.viagem, '') end, 'prestador', coalesce(em.nome_comercial, em.nome),
        'cliente', coalesce(e.cliente_nome, c.nome), 'estado', e.estado, 'suspensa', e.suspensa,
        'atrasada', e.estado not in ('entregue', 'cancelada') and coalesce(e.chegada_prevista, e.data_prevista) < v_hoje,
        'pagamento_pendente', exists (select 1 from pagamentos p where p.encomenda_id = e.id and p.estado in ('pendente', 'parcial')), 'atualizada', e.updated_at) x
        from encomendas e join empresas em on em.id = e.empresa_id left join clientes c on c.id = e.cliente_id
       order by e.updated_at desc limit 20) t), '[]'::jsonb));
  return r;
end $$;
revoke all on function public.painel_vivo() from public, anon;
grant execute on function public.painel_vivo() to authenticated;

-- ===== 00165_codigo_email_notificacoes.sql =====
-- v107 — 1) Código de 6 dígitos por email no 2.º passo do administrador da empresa (alternativa à aplicação de autenticação).
--         O código é criado só pelo serviço (Edge Function recuperar-acesso, ação «codigo_entrada»), guardado cifrado,
--         vale 10 minutos, máx. 5 tentativas, e só serve para a sessão onde foi pedido. Quando certo, reforça essa sessão
--         durante 12 horas (o mesmo mecanismo do código de reserva: sessoes_reserva → private.sessao_reforcada()).
--       2) Notificações: quem as pode ver passa a poder marcá-las como lidas (só a coluna lida_em; as regras RLS já existiam).
--       3) Segurança: TRUNCATE retirado a anon/authenticated (passava por cima das regras de acesso; a aplicação nunca o usa).
-- Só acrescenta; não altera dados, perfis nem fluxos.

create table if not exists public.codigos_email (
  user_id uuid primary key references auth.users(id) on delete cascade,
  session_id uuid not null,
  hash text not null,
  expira_em timestamptz not null,
  tentativas int not null default 0,
  created_at timestamptz not null default now());
alter table public.codigos_email enable row level security;
revoke all on public.codigos_email from anon, authenticated;

create or replace function public.servico_codigo_email_criar(p_user uuid, p_sessao uuid)
returns table (codigo text, email text, nome text)
language plpgsql security definer set search_path = public as $$
declare v_b bytea := extensions.gen_random_bytes(4); v_c text; v_f funcionarios;
begin
  select * into v_f from funcionarios where id = p_user and ativo;
  if not found or coalesce(v_f.email, '') = '' or p_sessao is null then return; end if;
  v_c := lpad(((get_byte(v_b,0)::bigint * 16777216 + get_byte(v_b,1) * 65536 + get_byte(v_b,2) * 256 + get_byte(v_b,3)) % 1000000)::text, 6, '0');
  insert into codigos_email (user_id, session_id, hash, expira_em, tentativas, created_at)
    values (p_user, p_sessao, extensions.crypt(v_c, extensions.gen_salt('bf')), now() + interval '10 minutes', 0, now())
    on conflict (user_id) do update set session_id = excluded.session_id, hash = excluded.hash, expira_em = excluded.expira_em, tentativas = 0, created_at = now();
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id)
    values (v_f.empresa_id, p_user, v_f.papel::text, 'codigo_email_enviado', 'codigos_email', p_user::text);
  return query select v_c, v_f.email, v_f.nome;
end $$;
revoke all on function public.servico_codigo_email_criar(uuid, uuid) from public, anon, authenticated;
grant execute on function public.servico_codigo_email_criar(uuid, uuid) to service_role;

create or replace function public.confirmar_codigo_email(p_codigo text)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_sess uuid; v_r codigos_email; v_c text := regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g');
begin
  if auth.uid() is null then return false; end if;
  begin v_sess := (auth.jwt() ->> 'session_id')::uuid; exception when others then v_sess := null; end;
  if v_sess is null then return false; end if;
  select * into v_r from codigos_email where user_id = auth.uid() for update;
  if not found or v_r.expira_em < now() or v_r.session_id <> v_sess or v_r.tentativas >= 5 then return false; end if;
  if length(v_c) <> 6 or extensions.crypt(v_c, v_r.hash) <> v_r.hash then
    update codigos_email set tentativas = tentativas + 1 where user_id = auth.uid();
    insert into auditoria (user_id, acao, entidade, entidade_id) values (auth.uid(), 'codigo_email_errado', 'codigos_email', auth.uid()::text);
    return false;
  end if;
  update codigos_email set expira_em = now() - interval '1 second', tentativas = 99 where user_id = auth.uid();   -- uso único
  insert into sessoes_reserva (session_id, user_id, valida_ate) values (v_sess, auth.uid(), now() + interval '12 hours')
    on conflict (session_id) do update set valida_ate = excluded.valida_ate where sessoes_reserva.user_id = auth.uid();
  insert into auditoria (user_id, acao, entidade, entidade_id) values (auth.uid(), 'codigo_email_usado', 'codigos_email', auth.uid()::text);
  return true;
end $$;
revoke all on function public.confirmar_codigo_email(text) from public, anon;
grant execute on function public.confirmar_codigo_email(text) to authenticated;

grant update (lida_em) on public.notificacoes to authenticated;

revoke truncate on all tables in schema public from anon, authenticated;
alter default privileges in schema public revoke truncate on tables from anon, authenticated;

-- ===== 00166_seguimento_simulacoes.sql =====
-- v109 — Fluxo de nutrição (seguimento de simulações) e boas-vindas, com consentimento.
-- Gatilho: o cliente faz uma simulação na Área de Cliente e marca «Quero receber por email o seguimento desta simulação».
-- Emails: 1 dia, 3 dias e 7 dias depois (Edge Function «seguimento», agendada de hora a hora).
-- Regra de saída: ao aprovar uma cotação (simulação «convertida») sai da nutrição e entra nas boas-vindas
-- (email de serviço com o acompanhamento da carga, enviado a todos os clientes que aprovam). Também sai se cancelar a
-- simulação ou se pedir para deixar de receber (ligação em todos os emails). Só acrescenta; não altera fluxos nem dados.

create table if not exists public.seguimento_simulacoes (
  simulacao_id uuid primary key references public.simulacoes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null,
  fluxo text not null default 'nutricao' check (fluxo in ('nutricao', 'boas_vindas')),
  passo int not null default 0,
  proximo_envio timestamptz,
  estado text not null default 'ativo' check (estado in ('ativo', 'concluido', 'saiu', 'cancelado')),
  motivo text,
  token uuid not null default gen_random_uuid() unique,
  consentimento_em timestamptz,
  ultimo_envio timestamptz,
  erro text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now());
create index if not exists seguimento_pendentes on public.seguimento_simulacoes (proximo_envio) where estado = 'ativo';
alter table public.seguimento_simulacoes enable row level security;
revoke all on public.seguimento_simulacoes from anon, authenticated;

-- O cliente dá (ou retira) o consentimento para uma simulação sua.
create or replace function public.seguimento_simulacao(p_simulacao uuid, p_aceito boolean)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_sim simulacoes; v_email text;
begin
  select * into v_sim from simulacoes where id = p_simulacao;
  if not found or v_sim.cliente_id is distinct from auth.uid() then return false; end if;
  if not coalesce(p_aceito, false) then
    update seguimento_simulacoes set estado = 'cancelado', motivo = 'retirou o consentimento', updated_at = now()
     where simulacao_id = p_simulacao and fluxo = 'nutricao' and estado = 'ativo';
    return true;
  end if;
  if v_sim.estado in ('convertida', 'cancelada') then return false; end if;
  select email into v_email from auth.users where id = auth.uid();
  if coalesce(v_email, '') = '' then return false; end if;
  insert into seguimento_simulacoes (simulacao_id, user_id, email, fluxo, passo, proximo_envio, estado, consentimento_em)
    values (p_simulacao, auth.uid(), v_email, 'nutricao', 0, now() + interval '1 day', 'ativo', now())
  on conflict (simulacao_id) do update set estado = 'ativo', motivo = null, consentimento_em = now(), email = excluded.email,
    proximo_envio = coalesce(seguimento_simulacoes.proximo_envio, excluded.proximo_envio), updated_at = now()
   where seguimento_simulacoes.fluxo = 'nutricao';
  insert into auditoria (user_id, acao, entidade, entidade_id) values (auth.uid(), 'seguimento_consentimento', 'simulacoes', p_simulacao::text);
  return true;
end $$;
revoke all on function public.seguimento_simulacao(uuid, boolean) from public, anon;
grant execute on function public.seguimento_simulacao(uuid, boolean) to authenticated;

-- Regra de saída (automática, na base de dados): aprovou → boas-vindas; cancelou → sai.
create or replace function private.seguimento_estado_simulacao() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  if new.estado = 'convertida' and old.estado is distinct from 'convertida' then
    select email into v_email from auth.users where id = new.cliente_id;
    if coalesce(v_email, '') <> '' then
      insert into seguimento_simulacoes (simulacao_id, user_id, email, fluxo, passo, proximo_envio, estado, motivo)
        values (new.id, new.cliente_id, v_email, 'boas_vindas', 0, now(), 'ativo', null)
      on conflict (simulacao_id) do update set fluxo = 'boas_vindas', passo = 0, proximo_envio = now(), estado = 'ativo',
        motivo = case when seguimento_simulacoes.fluxo = 'nutricao' then 'aprovou a cotação: saiu da nutrição' else seguimento_simulacoes.motivo end,
        updated_at = now();
    end if;
  elsif new.estado = 'cancelada' and old.estado is distinct from 'cancelada' then
    update seguimento_simulacoes set estado = 'saiu', motivo = 'simulação cancelada', updated_at = now()
     where simulacao_id = new.id and fluxo = 'nutricao' and estado = 'ativo';
  end if;
  return new;
end $$;
create or replace trigger seguimento_estado after update of estado on public.simulacoes
  for each row execute function private.seguimento_estado_simulacao();

-- Só o serviço (Edge Function «seguimento»): emails a enviar agora, já reservados por 15 minutos (não há envios duplicados).
create or replace function public.servico_seguimento_pendentes(p_limite int default 50)
returns table (simulacao_id uuid, email text, nome text, fluxo text, passo int, token uuid, codigo text, origem text, destino text,
               estado_simulacao text, propostas int, encomenda text)
language plpgsql security definer set search_path = public as $$
begin
  return query
  with alvo as (
    select s.simulacao_id from seguimento_simulacoes s
     where s.estado = 'ativo' and s.proximo_envio <= now() order by s.proximo_envio limit greatest(1, least(p_limite, 200))
     for update skip locked),
  reserva as (
    update seguimento_simulacoes s set proximo_envio = now() + interval '15 minutes', updated_at = now()
      from alvo where s.simulacao_id = alvo.simulacao_id returning s.*)
  select r.simulacao_id, r.email, coalesce(c.nome, u.raw_user_meta_data ->> 'nome', '')::text, r.fluxo, r.passo, r.token,
         si.codigo, si.origem, si.destino, si.estado::text,
         (select count(*)::int from propostas p where p.simulacao_id = r.simulacao_id and p.estado = 'enviada'),
         (select e.codigo from encomendas e where e.simulacao_id = r.simulacao_id order by e.created_at desc limit 1)
    from reserva r join simulacoes si on si.id = r.simulacao_id
    left join clientes c on c.id = r.user_id left join auth.users u on u.id = r.user_id;
end $$;
revoke all on function public.servico_seguimento_pendentes(int) from public, anon, authenticated;
grant execute on function public.servico_seguimento_pendentes(int) to service_role;

-- Só o serviço: regista o resultado e marca o próximo passo (nutrição: dia 1 → dia 3 → dia 7 → fim; boas-vindas: 1 email).
create or replace function public.servico_seguimento_marcar(p_simulacao uuid, p_ok boolean, p_erro text default null, p_saltar boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v seguimento_simulacoes;
begin
  select * into v from seguimento_simulacoes where simulacao_id = p_simulacao for update;
  if not found then return; end if;
  if not p_ok and not p_saltar then
    update seguimento_simulacoes set proximo_envio = now() + interval '1 hour', erro = left(p_erro, 300), updated_at = now() where simulacao_id = p_simulacao;
    return;
  end if;
  if v.fluxo = 'boas_vindas' or v.passo >= 2 then
    update seguimento_simulacoes set passo = v.passo + 1, estado = 'concluido', proximo_envio = null, ultimo_envio = case when p_ok then now() else ultimo_envio end,
      erro = null, updated_at = now() where simulacao_id = p_simulacao;
  else
    update seguimento_simulacoes set passo = v.passo + 1, ultimo_envio = case when p_ok then now() else ultimo_envio end, erro = null, updated_at = now(),
      proximo_envio = v.consentimento_em + case v.passo when 0 then interval '3 days' else interval '7 days' end
     where simulacao_id = p_simulacao;
  end if;
end $$;
revoke all on function public.servico_seguimento_marcar(uuid, boolean, text, boolean) from public, anon, authenticated;
grant execute on function public.servico_seguimento_marcar(uuid, boolean, text, boolean) to service_role;

-- «Deixar de receber» (ligação nos emails): qualquer pessoa com o token; não revela nada sobre a conta.
create or replace function public.servico_seguimento_sair(p_token uuid)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  update seguimento_simulacoes set estado = 'cancelado', motivo = 'pediu para deixar de receber', proximo_envio = null, updated_at = now()
   where token = p_token and fluxo = 'nutricao' and estado = 'ativo';
  return found;
end $$;
revoke all on function public.servico_seguimento_sair(uuid) from public, anon, authenticated;
grant execute on function public.servico_seguimento_sair(uuid) to service_role;

-- Agendamento: de hora a hora (minuto 23), pela mesma via das outras tarefas (private.chamar_funcao com o segredo do cofre).
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and to_regprocedure('private.chamar_funcao(text,jsonb)') is not null then
    perform cron.schedule('elolog-seguimento', '23 * * * *', $c$select private.chamar_funcao('seguimento', '{"acao":"processar"}'::jsonb)$c$);
  end if;
end $$;

-- ===== 00167_tarifarios_base.sql =====
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

-- ===== 00168_tarifarios_regras.sql =====
-- v114 — Centro de Gestão de Tarifários (2/3): regras validadas no servidor (o navegador não decide nada).
-- Prestador: cria, atualiza (nova versão), desativa e submete. Administração: aprova, rejeita, suspende, pede alterações, reativa.
-- Uma tarifa aprovada nunca muda de valor: as alterações são uma nova versão que só substitui a anterior quando for aprovada.

-- ---------- Guarda das tarifas dos prestadores ----------
create or replace function private.tarifa_guarda() returns trigger language plpgsql security definer set search_path = public as $$
-- de confiança: sem sessão de utilizador (base de dados, instalador, chave de serviço), que já não passa pelas regras de acesso
declare confiavel boolean := auth.uid() is null; admin boolean := confiavel or private.e_admin_plataforma();
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    if confiavel and new.estado = 'rascunho' and new.decidida_em is null then new.estado := case when new.ativa then 'aprovada' else 'inativa' end; end if;
    if not admin and new.estado not in ('rascunho', 'pendente') then new.estado := 'pendente'; end if;
    if new.estado = 'pendente' then new.submetida_em := now(); end if;
    if not admin then new.decidida_em := null; new.decidida_por := null; new.motivo_decisao := null; end if;
  else
    if not admin then
      new.decidida_em := old.decidida_em; new.decidida_por := old.decidida_por; new.motivo_decisao := old.motivo_decisao;
      if new.estado is distinct from old.estado and not ((old.estado, new.estado) in
         (('rascunho','pendente'), ('alteracoes_pedidas','pendente'), ('rejeitada','pendente'), ('inativa','pendente'), ('pendente','rascunho'), ('aprovada','inativa'))) then
        raise exception 'Só a administração Elolog pode aprovar, rejeitar ou suspender tarifas.' using errcode = '42501';
      end if;
      if old.estado in ('aprovada', 'suspensa', 'substituida', 'inativa') and
         (new.aplicacao, new.metodo, new.valor, new.moeda, new.quantidade_minima, new.preco_minimo, new.preco_maximo, new.limite_min, new.limite_max,
          new.origem, new.destino, new.tipo_carga, new.transporte, new.regras::text, new.validade_inicio, new.validade_fim) is distinct from
         (old.aplicacao, old.metodo, old.valor, old.moeda, old.quantidade_minima, old.preco_minimo, old.preco_maximo, old.limite_min, old.limite_max,
          old.origem, old.destino, old.tipo_carga, old.transporte, old.regras::text, old.validade_inicio, old.validade_fim) then
        raise exception 'Uma tarifa aprovada não muda de preço nem de condições: crie uma nova versão e submeta-a.';
      end if;
      if new.estado = 'pendente' and old.estado <> 'pendente' then new.submetida_em := now(); end if;
    end if;
  end if;
  new.ativa := new.estado = 'aprovada';
  return new;
end $$;
create or replace trigger tarifas_guarda before insert or update on public.tarifas for each row execute function private.tarifa_guarda();

-- ---------- Guarda dos suplementos e dos tarifários gerais ----------
create or replace function private.suplemento_guarda() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if auth.uid() is not null and not private.e_admin_plataforma() then
    if new.empresa_id is null then raise exception 'Os suplementos gerais são da administração Elolog.' using errcode = '42501'; end if;
    if tg_op = 'INSERT' then new.estado := 'pendente'; new.motivo_decisao := null;
    else
      new.motivo_decisao := old.motivo_decisao;
      if old.estado = 'aprovado' and (new.tipo, new.valor, new.chave, new.servico, new.tipo_carga, new.automatico) is distinct from (old.tipo, old.valor, old.chave, old.servico, old.tipo_carga, old.automatico)
        then new.estado := 'pendente'; end if;   -- mudar um suplemento aprovado volta a precisar de aprovação
      if new.estado not in ('pendente', 'inativo') and new.estado is distinct from old.estado then
        raise exception 'Só a administração Elolog pode aprovar ou suspender suplementos.' using errcode = '42501'; end if;
    end if;
  end if;
  return new;
end $$;
create or replace trigger tarifa_suplementos_guarda before insert or update on public.tarifa_suplementos for each row execute function private.suplemento_guarda();

create or replace function private.tarifa_geral_codigo() returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  if new.codigo is null then new.codigo := 'TG-' || lpad(nextval('public.tarifas_gerais_seq')::text, 4, '0'); end if;
  if tg_op = 'UPDATE' and old.estado = 'substituida' and new.estado <> 'substituida' then raise exception 'Esta versão já foi substituída.'; end if;
  -- mudar o preço ou as condições de um tarifário em vigor exige motivo e cria nova versão (o histórico guarda os valores anteriores)
  if tg_op = 'UPDATE' and old.estado = 'ativa' and (new.metodo, new.valor, new.moeda, new.preco_minimo, new.preco_maximo, new.limite_min, new.limite_max, new.origem, new.destino,
      new.tipo_carga, new.servico, new.regras::text, new.validade_inicio, new.validade_fim, new.prestadores, new.uso) is distinct from
     (old.metodo, old.valor, old.moeda, old.preco_minimo, old.preco_maximo, old.limite_min, old.limite_max, old.origem, old.destino,
      old.tipo_carga, old.servico, old.regras::text, old.validade_inicio, old.validade_fim, old.prestadores, old.uso) then
    if coalesce(trim(new.motivo_alteracao), '') = '' or new.motivo_alteracao is not distinct from old.motivo_alteracao then
      raise exception 'Indique o motivo da alteração: fica no histórico.'; end if;
    new.versao := old.versao + 1;
  end if;
  return new;
end $$;
create or replace trigger tarifas_gerais_codigo before insert or update on public.tarifas_gerais for each row execute function private.tarifa_geral_codigo();

-- ---------- Prestador: guardar (nova tarifa ou nova versão) e submeter, validado no servidor ----------
create or replace function public.tarifa_guardar(p_dados jsonb, p_base uuid default null, p_submeter boolean default true, p_motivo text default null)
returns public.tarifas language plpgsql security definer set search_path = public as $$
declare v_emp uuid := private.minha_empresa(); v_base tarifas; v_nova tarifas; v_valor numeric := (p_dados ->> 'valor')::numeric;
        v_min numeric := nullif(p_dados ->> 'limite_min', '')::numeric; v_max numeric := nullif(p_dados ->> 'limite_max', '')::numeric;
begin
  if v_emp is null or not private.papel_em(array['admin_empresa', 'financeiro']) then raise exception 'Só o administrador ou o financeiro da empresa podem gravar tarifas.' using errcode = '42501'; end if;
  if coalesce(trim(p_dados ->> 'nome'), '') = '' or length(p_dados ->> 'nome') > 120 then raise exception 'Indique o nome da tarifa (até 120 caracteres).'; end if;
  if v_valor is null or v_valor < 0 or v_valor > 10000000 then raise exception 'Indique um valor entre 0 e 10 000 000.'; end if;
  if v_min is not null and v_max is not null and v_max < v_min then raise exception 'O limite máximo é menor do que o mínimo.'; end if;
  if nullif(p_dados ->> 'validade_fim', '')::date < current_date then raise exception 'A data de fim já passou: esta tarifa nasceria expirada.'; end if;
  if p_base is not null then
    select * into v_base from tarifas where id = p_base and empresa_id = v_emp;
    if not found then raise exception 'Tarifa de origem inexistente.'; end if;
    if v_base.estado = 'substituida' then raise exception 'Esta versão já foi substituída; parta da versão em vigor.'; end if;
  end if;
  perform set_config('elolog.motivo', coalesce(nullif(trim(p_motivo), ''), case when p_base is null then 'Nova tarifa' else 'Nova versão' end), true);
  insert into tarifas (empresa_id, tarifa_pai_id, versao, nome, aplicacao, tipo_carga, metodo, valor, moeda, quantidade_minima, preco_minimo, preco_maximo,
                       limite_min, limite_max, transporte, origem, destino, validade_inicio, validade_fim, regras, notas, estado, criado_por)
  values (v_emp, p_base, coalesce(v_base.versao, 0) + 1, trim(p_dados ->> 'nome'), coalesce(nullif(p_dados ->> 'aplicacao', ''), 'carga')::aplicacao_tarifa,
          nullif(trim(p_dados ->> 'tipo_carga'), ''), (p_dados ->> 'metodo')::metodo_cobranca, round(v_valor, 4), coalesce(nullif(p_dados ->> 'moeda', ''), 'EUR'),
          coalesce(nullif(p_dados ->> 'quantidade_minima', '')::numeric, 0), coalesce(nullif(p_dados ->> 'preco_minimo', '')::numeric, 0), nullif(p_dados ->> 'preco_maximo', '')::numeric,
          v_min, v_max, nullif(trim(p_dados ->> 'transporte'), ''), nullif(trim(p_dados ->> 'origem'), ''), nullif(trim(p_dados ->> 'destino'), ''),
          nullif(p_dados ->> 'validade_inicio', '')::date, nullif(p_dados ->> 'validade_fim', '')::date, coalesce(p_dados -> 'regras', '{}'), nullif(trim(p_dados ->> 'notas'), ''),
          case when p_submeter then 'pendente' else 'rascunho' end, auth.uid())
  returning * into v_nova;
  if p_submeter then
    insert into notificacoes (para_plataforma, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (true, 'tarifa_submetida', 'Uma tarifa espera aprovação',
            (select nome from empresas where id = v_emp) || ' submeteu «' || v_nova.nome || '» (versão ' || v_nova.versao || ').', 'tarifas', v_nova.id);
  end if;
  perform set_config('elolog.motivo', '', true);
  return v_nova;
end $$;
revoke all on function public.tarifa_guardar(jsonb, uuid, boolean, text) from public, anon;
grant execute on function public.tarifa_guardar(jsonb, uuid, boolean, text) to authenticated;

-- ---------- Administração: decidir sobre tarifas e suplementos dos prestadores ----------
create or replace function public.tarifa_decidir(p_tarifa uuid, p_decisao text, p_motivo text default null)
returns public.tarifas language plpgsql security definer set search_path = public as $$
declare v tarifas; v_para text; v_tit text;
begin
  if not private.e_admin_plataforma() then raise exception 'Só a administração Elolog decide sobre tarifas.' using errcode = '42501'; end if;
  select * into v from tarifas where id = p_tarifa for update;
  if not found then raise exception 'Tarifa inexistente.'; end if;
  v_para := case p_decisao when 'aprovar' then 'aprovada' when 'rejeitar' then 'rejeitada' when 'pedir_alteracoes' then 'alteracoes_pedidas'
                           when 'suspender' then 'suspensa' when 'reativar' then 'aprovada' end;
  if v_para is null then raise exception 'Decisão desconhecida.'; end if;
  if p_decisao in ('aprovar', 'rejeitar', 'pedir_alteracoes') and v.estado <> 'pendente' then raise exception 'Só uma tarifa submetida pode ser %.', replace(p_decisao, '_', ' '); end if;
  if p_decisao = 'suspender' and v.estado <> 'aprovada' then raise exception 'Só uma tarifa aprovada pode ser suspensa.'; end if;
  if p_decisao = 'reativar' and v.estado <> 'suspensa' then raise exception 'Só uma tarifa suspensa pode ser reativada.'; end if;
  if p_decisao <> 'aprovar' and p_decisao <> 'reativar' and coalesce(trim(p_motivo), '') = '' then raise exception 'Indique o motivo: o prestador vai lê-lo.'; end if;
  if v_para = 'aprovada' and v.validade_fim is not null and v.validade_fim < current_date then raise exception 'Esta tarifa já expirou a %.', to_char(v.validade_fim, 'DD/MM/YYYY'); end if;
  perform set_config('elolog.motivo', coalesce(nullif(trim(p_motivo), ''), initcap(replace(p_decisao, '_', ' '))), true);
  update tarifas set estado = v_para, decidida_em = now(), decidida_por = auth.uid(), motivo_decisao = nullif(trim(p_motivo), '') where id = v.id returning * into v;
  if p_decisao = 'aprovar' and v.tarifa_pai_id is not null then
    perform set_config('elolog.motivo', 'Substituída pela versão ' || v.versao, true);
    update tarifas set estado = 'substituida' where id = v.tarifa_pai_id and estado in ('aprovada', 'suspensa', 'inativa', 'pendente', 'alteracoes_pedidas', 'rejeitada');
  end if;
  v_tit := case p_decisao when 'aprovar' then 'Tarifa aprovada: já entra nas simulações' when 'rejeitar' then 'Tarifa rejeitada'
           when 'pedir_alteracoes' then 'A Elolog pediu alterações a uma tarifa' when 'suspender' then 'Tarifa suspensa' else 'Tarifa reativada' end;
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  values (v.empresa_id, 'tarifa_decisao', v_tit, '«' || v.nome || '» (versão ' || v.versao || ')' || coalesce('. ' || nullif(trim(p_motivo), ''), '.'), 'tarifas', v.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois, motivo)
  values (v.empresa_id, auth.uid(), 'admin_plataforma', 'tarifa_' || p_decisao, 'tarifas', v.id::text, jsonb_build_object('estado', v.estado, 'versao', v.versao), nullif(trim(p_motivo), ''));
  perform set_config('elolog.motivo', '', true);
  return v;
end $$;
revoke all on function public.tarifa_decidir(uuid, text, text) from public, anon;
grant execute on function public.tarifa_decidir(uuid, text, text) to authenticated;

create or replace function public.suplemento_decidir(p_suplemento uuid, p_decisao text, p_motivo text default null)
returns public.tarifa_suplementos language plpgsql security definer set search_path = public as $$
declare v tarifa_suplementos; v_para text := case p_decisao when 'aprovar' then 'aprovado' when 'rejeitar' then 'rejeitado' when 'suspender' then 'suspenso' when 'reativar' then 'aprovado' end;
begin
  if not private.e_admin_plataforma() then raise exception 'Só a administração Elolog decide sobre suplementos.' using errcode = '42501'; end if;
  if v_para is null then raise exception 'Decisão desconhecida.'; end if;
  if p_decisao in ('rejeitar', 'suspender') and coalesce(trim(p_motivo), '') = '' then raise exception 'Indique o motivo: o prestador vai lê-lo.'; end if;
  perform set_config('elolog.motivo', coalesce(nullif(trim(p_motivo), ''), initcap(p_decisao)), true);
  update tarifa_suplementos set estado = v_para, motivo_decisao = nullif(trim(p_motivo), '') where id = p_suplemento returning * into v;
  if not found then raise exception 'Suplemento inexistente.'; end if;
  if v.empresa_id is not null then
    insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v.empresa_id, 'suplemento_decisao', 'Suplemento ' || v_para, '«' || v.nome || '»' || coalesce('. ' || nullif(trim(p_motivo), ''), '.'), 'tarifa_suplementos', v.id);
  end if;
  perform set_config('elolog.motivo', '', true);
  return v;
end $$;
revoke all on function public.suplemento_decidir(uuid, text, text) from public, anon;
grant execute on function public.suplemento_decidir(uuid, text, text) to authenticated;

-- ===== 00169_motor_precos.sql =====
-- v114 — Centro de Gestão de Tarifários (3/4): o motor de preços, fonte única de preços da Elolog.
-- Ordem: 1 serviço · 2 modalidade · 3 origem e destino · 4 prestador · 5 tarifas ativas e válidas · 6 tarifa específica
--        · 7 suplementos autorizados · 8 comissão Elolog · 9 preço final.
-- Comissão «incluida» (o modelo de sempre): o cliente paga o preço do prestador + suplementos e a comissão é retida a esse valor.
-- Comissão «separada»: o cliente vê e paga a taxa de serviço Elolog à parte, em cima do preço do prestador.

alter table public.simulacoes add column if not exists preco_detalhe jsonb;
alter table public.propostas  add column if not exists preco_detalhe jsonb;
alter table public.encomendas add column if not exists preco_detalhe jsonb;

-- quanto «mede» o pedido na modalidade da tarifa (mesma fórmula de sempre: peso usa o volumétrico; o resto, volume)
create or replace function private.tarifa_medida(p_metodo metodo_cobranca, p_regras jsonb, q int, peso numeric, vol numeric)
returns numeric language sql immutable set search_path = public as $$
  select case p_metodo when 'fixo' then 1
    when 'peso' then greatest(coalesce(peso, 0), coalesce(vol, 0) * coalesce(nullif((p_regras ->> 'volumetricFactor')::numeric, 0), 167))
    when 'unidade' then coalesce(q, 0)::numeric else coalesce(vol, 0) end $$;

-- compatível: o pedido tem a medida que a modalidade precisa e está dentro dos limites da tarifa
create or replace function private.tarifa_compativel(p_metodo metodo_cobranca, p_regras jsonb, p_min numeric, p_max numeric, q int, peso numeric, vol numeric)
returns boolean language sql immutable set search_path = public as $$
  select m > 0 and (p_min is null or m >= p_min) and (p_max is null or m <= p_max)
    from (select private.tarifa_medida(p_metodo, p_regras, q, peso, vol) m) x $$;

create or replace function private.tarifa_preco(p_metodo metodo_cobranca, p_valor numeric, p_min numeric, p_max numeric, p_regras jsonb, q int, peso numeric, vol numeric)
returns numeric language sql immutable set search_path = public as $$
  select round(least(greatest(case p_metodo when 'fixo' then p_valor else private.tarifa_medida(p_metodo, p_regras, q, peso, vol) * p_valor end, coalesce(p_min, 0)),
                     coalesce(p_max, 'infinity'::numeric)), 2) $$;

create or replace function private.rota_bate(p_regra text, p_pedido text) returns boolean language sql stable set search_path = public, extensions as $$
  select coalesce(p_regra, '') = '' or strpos(private.norm(p_pedido), private.norm(p_regra)) > 0 or strpos(private.norm(p_regra), private.norm(p_pedido)) > 0 $$;

-- 5 e 6: a tarifa APROVADA, válida e compatível mais específica do prestador
create or replace function private.tarifa_escolhida(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric)
returns public.tarifas language sql stable security definer set search_path = public, extensions as $$
  select t.* from tarifas t
   where t.empresa_id = p_empresa and t.estado = 'aprovada' and t.aplicacao = 'carga'
     and (t.validade_inicio is null or t.validade_inicio <= current_date) and (t.validade_fim is null or t.validade_fim >= current_date)
     and private.rota_bate(t.origem, p_origem) and private.rota_bate(t.destino, p_destino)
     and (coalesce(t.transporte, '') = '' or coalesce(p_servico, '') = '' or private.norm(t.transporte) = private.norm(p_servico))
     and (coalesce(t.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = '' or strpos(private.norm(p_tipo_carga), private.norm(t.tipo_carga)) > 0)
     and private.tarifa_compativel(t.metodo, t.regras, t.limite_min, t.limite_max, q, peso, vol)
   order by ((coalesce(t.origem, '') <> '')::int + (coalesce(t.destino, '') <> '')::int + (coalesce(t.tipo_carga, '') <> '')::int + (coalesce(t.transporte, '') <> '')::int) desc,
            t.versao desc, t.created_at desc limit 1 $$;

-- 5 e 6 (alternativa): tarifário comercial geral da Elolog associado a este prestador
create or replace function private.tarifa_geral_escolhida(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric)
returns public.tarifas_gerais language sql stable security definer set search_path = public, extensions as $$
  select g.* from tarifas_gerais g
   where g.uso = 'comercial' and g.estado = 'ativa' and p_empresa = any (g.prestadores)
     and (g.validade_inicio is null or g.validade_inicio <= current_date) and (g.validade_fim is null or g.validade_fim >= current_date)
     and private.rota_bate(g.origem, p_origem) and private.rota_bate(g.destino, p_destino)
     and (coalesce(g.servico, '') = '' or coalesce(p_servico, '') = '' or private.norm(g.servico) = private.norm(p_servico))
     and (coalesce(g.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = '' or strpos(private.norm(p_tipo_carga), private.norm(g.tipo_carga)) > 0)
     and private.tarifa_compativel(g.metodo, g.regras, g.limite_min, g.limite_max, q, peso, vol)
   order by ((coalesce(g.origem, '') <> '')::int + (coalesce(g.destino, '') <> '')::int + (coalesce(g.tipo_carga, '') <> '')::int) desc, g.versao desc limit 1 $$;

-- 7: suplementos aprovados e válidos (o do prestador vale mais do que o geral da mesma chave); recolha: por km pedido
create or replace function private.suplementos_calc(p_empresa uuid, p_servico text, p_tipo_carga text, p_km numeric, p_base numeric)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare r record; itens jsonb := '[]'; total numeric := 0; m numeric; tem_recolha boolean := false;
begin
  for r in select distinct on (s.chave, case when s.chave = 'outro' then s.id end) s.* from tarifa_suplementos s
            where s.estado = 'aprovado' and (s.empresa_id = p_empresa or s.empresa_id is null)
              and (s.validade_inicio is null or s.validade_inicio <= current_date) and (s.validade_fim is null or s.validade_fim >= current_date)
              and (coalesce(s.servico, '') = '' or coalesce(p_servico, '') = '' or private.norm(s.servico) = private.norm(p_servico))
              and (coalesce(s.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = '' or strpos(private.norm(p_tipo_carga), private.norm(s.tipo_carga)) > 0)
            order by s.chave, case when s.chave = 'outro' then s.id end, (s.empresa_id is null), s.updated_at desc loop
    if r.chave = 'recolha_km' then
      if coalesce(p_km, 0) <= 0 then continue; end if; tem_recolha := true;
    elsif not r.automatico then continue; end if;
    m := round(case r.tipo when 'fixo' then r.valor when 'percentual' then p_base * r.valor / 100 else coalesce(p_km, 0) * r.valor end, 2);
    total := total + m;
    itens := itens || jsonb_build_object('id', r.id, 'nome', r.nome, 'chave', r.chave, 'tipo', r.tipo, 'valor', r.valor, 'montante', m, 'origem', case when r.empresa_id is null then 'elolog' else 'prestador' end);
  end loop;
  if coalesce(p_km, 0) > 0 and not tem_recolha then   -- sem suplemento configurado: o custo por km de sempre
    m := round(p_km * private.custo_recolha_por_km(), 2); total := total + m;
    itens := itens || jsonb_build_object('nome', 'Recolha na morada', 'chave', 'recolha_km', 'tipo', 'por_km', 'valor', private.custo_recolha_por_km(), 'montante', m, 'origem', 'elolog');
  end if;
  return jsonb_build_object('total', total, 'itens', itens);
end $$;

-- 8: a regra de comissão ativa mais específica (prestador, modalidade, rota), dentro do período
create or replace function private.comissao_escolhida(p_empresa uuid, p_metodo metodo_cobranca, p_origem text, p_destino text)
returns public.regras_comissao language sql stable security definer set search_path = public, extensions as $$
  select c.* from regras_comissao c
   where c.ativa and (c.inicio is null or c.inicio <= current_date) and (c.fim is null or c.fim >= current_date)
     and (c.empresa_id is null or c.empresa_id = p_empresa) and (c.metodo is null or p_metodo is null or c.metodo = p_metodo)
     and private.rota_bate(c.rota_origem, p_origem) and private.rota_bate(c.rota_destino, p_destino)
   order by ((c.empresa_id is not null)::int + (c.metodo is not null)::int + (coalesce(c.rota_origem, '') <> '')::int + (coalesce(c.rota_destino, '') <> '')::int) desc,
            c.promocional desc, c.prioridade desc, c.updated_at desc limit 1 $$;

create or replace function private.comissao_valor(c public.regras_comissao, p_base numeric) returns numeric language sql immutable as $$
  select case when c.id is null then 0 when c.tipo_valor = 'percentagem' then round(p_base * c.valor / 100, 2) else round(c.valor, 2) end $$;

-- o motor: devolve o preço e o caminho que fez (para a administração) e a cópia a guardar quando for aprovado
create or replace function private.motor_preco(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric, km numeric)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare t tarifas; g tarifas_gerais; c regras_comissao; base numeric; sup jsonb; com numeric; ap text; met metodo_cobranca; tj jsonb; orig text; moeda text;
begin
  t := private.tarifa_escolhida(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol);
  if t.id is not null then
    met := t.metodo; orig := 'prestador'; moeda := t.moeda;
    base := private.tarifa_preco(t.metodo, t.valor, t.preco_minimo, t.preco_maximo, t.regras, q, peso, vol);
    tj := jsonb_build_object('id', t.id, 'nome', t.nome, 'versao', t.versao, 'metodo', t.metodo, 'valor', t.valor, 'moeda', t.moeda, 'preco_minimo', t.preco_minimo,
          'preco_maximo', t.preco_maximo, 'limite_min', t.limite_min, 'limite_max', t.limite_max, 'regras', t.regras, 'validade_inicio', t.validade_inicio, 'validade_fim', t.validade_fim, 'notas', t.notas);
  else
    g := private.tarifa_geral_escolhida(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol);
    if g.id is null then
      return jsonb_build_object('disponivel', false, 'mensagem', 'Não existe uma tarifa automática disponível. Solicite uma cotação personalizada.');
    end if;
    met := g.metodo; orig := 'geral'; moeda := g.moeda;
    base := private.tarifa_preco(g.metodo, g.valor, g.preco_minimo, g.preco_maximo, g.regras, q, peso, vol);
    tj := jsonb_build_object('id', g.id, 'codigo', g.codigo, 'nome', g.nome, 'versao', g.versao, 'metodo', g.metodo, 'valor', g.valor, 'moeda', g.moeda, 'preco_minimo', g.preco_minimo,
          'preco_maximo', g.preco_maximo, 'limite_min', g.limite_min, 'limite_max', g.limite_max, 'regras', g.regras, 'validade_inicio', g.validade_inicio, 'validade_fim', g.validade_fim, 'condicoes', g.condicoes);
  end if;
  sup := private.suplementos_calc(p_empresa, p_servico, p_tipo_carga, km, base);
  c := private.comissao_escolhida(p_empresa, met, p_origem, p_destino);
  com := private.comissao_valor(c, base + (sup ->> 'total')::numeric); ap := coalesce(c.apresentacao, 'incluida');
  return jsonb_build_object('disponivel', true, 'origem_tarifa', orig, 'tarifa_id', case when orig = 'prestador' then t.id end, 'tarifa', tj, 'moeda', moeda,
    'pedido', jsonb_build_object('servico', p_servico, 'origem', p_origem, 'destino', p_destino, 'tipo_carga', p_tipo_carga, 'quantidade', q, 'peso_kg', peso, 'volume_m3', vol, 'recolha_km', km,
                                 'medida', private.tarifa_medida(met, tj -> 'regras', q, peso, vol)),
    'preco_prestador', base, 'suplementos', sup -> 'itens', 'suplementos_total', (sup ->> 'total')::numeric,
    'comissao', com, 'apresentacao', ap,
    'comissao_regra', case when c.id is null then null else jsonb_build_object('id', c.id, 'nome', c.nome, 'tipo_valor', c.tipo_valor, 'valor', c.valor, 'promocional', c.promocional) end,
    'preco_final', base + (sup ->> 'total')::numeric + case when ap = 'separada' then com else 0 end,
    'liquido_prestador', base + (sup ->> 'total')::numeric - case when ap = 'incluida' then com else 0 end, 'calculado_em', now());
end $$;
revoke all on function private.motor_preco(uuid, text, text, text, text, int, numeric, numeric, numeric) from public, anon, authenticated;

-- ===== 00170_motor_integracao.sql =====
-- v114 — Centro de Gestão de Tarifários (4/4): toda a plataforma consulta o mesmo motor de preços.
-- Simulação do cliente, envio ao prestador e aceitação usam private.motor_preco; a aceitação guarda uma cópia (preco_detalhe)
-- dos valores e condições em vigor nesse momento, que não muda com atualizações posteriores das tarifas.
-- O cliente nunca recebe tarifas internas, margens nem a comissão incluída: só o preço final e, se for separada, a taxa de serviço.

create or replace function public.calcular_precos(p_origem text, p_destino text, p_tipo_carga text default null, p_quantidade int default 0, p_peso_kg numeric default 0,
  p_volume_m3 numeric default 0, p_recolha_km numeric default 0, p_servico text default null)
returns table (prestador_id uuid, prestador_nome text, disponivel boolean, preco_final numeric, taxa_servico numeric, moeda char(3), mensagem text)
language plpgsql stable security definer set search_path = public as $$
declare r record; m jsonb;
begin
  if not exists (select 1 from clientes c where c.id = auth.uid()) and not private.e_admin_plataforma() then raise exception 'Apenas clientes autenticados.'; end if;
  if coalesce(trim(p_origem), '') = '' or coalesce(trim(p_destino), '') = '' then raise exception 'Indique origem e destino.'; end if;
  if least(coalesce(p_quantidade, 0), coalesce(p_peso_kg, 0), coalesce(p_volume_m3, 0), coalesce(p_recolha_km, 0)) < 0 then raise exception 'Valores negativos não são permitidos.'; end if;
  for r in select e.id, e.nome from empresas_disponiveis e order by e.nome loop
    m := private.motor_preco(r.id, p_servico, p_origem, p_destino, p_tipo_carga, p_quantidade, p_peso_kg, p_volume_m3, p_recolha_km);
    prestador_id := r.id; prestador_nome := r.nome; disponivel := (m ->> 'disponivel')::boolean;
    preco_final := (m ->> 'preco_final')::numeric; moeda := m ->> 'moeda'; mensagem := m ->> 'mensagem';
    taxa_servico := case when m ->> 'apresentacao' = 'separada' then (m ->> 'comissao')::numeric end;
    return next;
  end loop;
end $$;
revoke all on function public.calcular_precos(text, text, text, int, numeric, numeric, numeric, text) from public, anon;
grant execute on function public.calcular_precos(text, text, text, int, numeric, numeric, numeric, text) to authenticated;

-- a função antiga continua a responder (mesmas colunas) para as versões da aplicação que ainda a chamam, agora pelo motor
create or replace function public.calcular_propostas(p_origem text, p_destino text, p_tipo_carga text default null, p_quantidade integer default 0, p_peso_kg numeric default 0,
  p_volume_m3 numeric default 0, p_recolha_km numeric default 0, p_transporte text default null)
returns table (prestador_id uuid, prestador_nome text, disponivel boolean, preco_total numeric, moeda character)
language sql stable security definer set search_path = public as $$
  select x.prestador_id, x.prestador_nome, x.disponivel, x.preco_final, x.moeda from public.calcular_precos(p_origem, p_destino, p_tipo_carga, p_quantidade, p_peso_kg, p_volume_m3, p_recolha_km, p_transporte) x $$;

-- a administração testa o motor com todos os passos (nunca exposto ao cliente nem ao prestador)
create or replace function public.testar_preco(p_empresa uuid, p_origem text, p_destino text, p_tipo_carga text default null, p_quantidade int default 0, p_peso_kg numeric default 0,
  p_volume_m3 numeric default 0, p_recolha_km numeric default 0, p_servico text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Só a administração Elolog pode testar o motor de preços.' using errcode = '42501'; end if;
  return private.motor_preco(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, p_quantidade, p_peso_kg, p_volume_m3, p_recolha_km);
end $$;
revoke all on function public.testar_preco(uuid, text, text, text, int, numeric, numeric, numeric, text) from public, anon;
grant execute on function public.testar_preco(uuid, text, text, text, int, numeric, numeric, numeric, text) to authenticated;

create or replace function public.enviar_simulacao(p_simulacao uuid, p_empresa uuid)
returns simulacoes language plpgsql security definer set search_path = public as $$
declare v_sim simulacoes; m jsonb; v_preco numeric;
begin
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.cliente_id is distinct from auth.uid() then raise exception 'Simulação inexistente.'; end if;
  if v_sim.estado <> 'rascunho' then raise exception 'A simulação já foi enviada (%).', v_sim.estado; end if;
  if not exists (select 1 from empresas_disponiveis e where e.id = p_empresa) then raise exception 'Este prestador não está disponível.'; end if;
  m := private.motor_preco(p_empresa, null, v_sim.origem, v_sim.destino, v_sim.tipo_carga, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3,
                           case when v_sim.recolha_na_morada then coalesce(v_sim.recolha_distancia_km, 0) else 0 end);
  if (m ->> 'disponivel')::boolean then v_preco := (m ->> 'preco_final')::numeric; end if;
  update simulacoes set estado = 'enviada', empresa_destinatario_id = p_empresa, enviada_em = now(), preco_estimado = v_preco,
         moeda_estimada = coalesce(m ->> 'moeda', 'EUR'), tarifa_estimada_id = (m ->> 'tarifa_id')::uuid, preco_detalhe = case when v_preco is not null then m end
   where id = v_sim.id returning * into v_sim;
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (p_empresa, 'nova_simulacao', case when v_preco is null then 'Novo pedido de cotação' else 'Nova simulação recebida' end,
            case when v_preco is null then 'De ' || v_sim.origem || ' para ' || v_sim.destino || ': ainda não tem tarifa aprovada para este pedido. Indique o preço ao aceitar.' end,
            'simulacoes', v_sim.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (p_empresa, auth.uid(), 'cliente', 'enviar_simulacao', 'simulacoes', v_sim.id::text,
            jsonb_build_object('preco_estimado', v_preco, 'tarifa', m ->> 'tarifa_id', 'origem_tarifa', m ->> 'origem_tarifa', 'pedido_cotacao', v_preco is null));
  return v_sim;
end $$;

-- cópia congelada no momento da aprovação (valores e condições em vigor nesse instante)
create or replace function private.preco_congelado(p_det jsonb, p_preco numeric, p_moeda text, p_tarifa uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(p_det, jsonb_build_object('origem_tarifa', 'cotacao', 'preco_final', p_preco, 'moeda', p_moeda, 'tarifa_id', p_tarifa,
           'tarifa', (select to_jsonb(t) - 'criado_por' from tarifas t where t.id = p_tarifa))) || jsonb_build_object('congelado_em', now()) $$;

-- ===== 00171_aceitacao_congela_preco.sql =====
-- v114 — A aceitação guarda a cópia dos valores e condições em vigor (preco_detalhe), e a ficha lê a comissão dessa cópia.
-- aceitar_simulacao e aceitar_proposta ficam iguais em tudo o resto (mesmas verificações, histórico, notificações e auditoria).

create or replace function public.aceitar_proposta(p_proposta uuid)
returns encomendas language plpgsql security definer set search_path = public as $$
declare v_prop propostas; v_sim simulacoes; v_enc encomendas; v_det jsonb;
begin
  select * into v_prop from propostas where id = p_proposta for update;
  if not found then raise exception 'Proposta inexistente.'; end if;
  select * into v_sim from simulacoes where id = v_prop.simulacao_id for update;
  if v_sim.cliente_id is distinct from auth.uid() then raise exception 'Sem permissão.'; end if;
  if v_prop.estado <> 'enviada' then raise exception 'A proposta já não está disponível (%).', v_prop.estado; end if;
  if v_prop.validade is not null and v_prop.validade < current_date then raise exception 'A proposta expirou.'; end if;
  v_det := private.preco_congelado(coalesce(v_prop.preco_detalhe, case when v_sim.preco_estimado = v_prop.preco then v_sim.preco_detalhe end), v_prop.preco, v_prop.moeda, v_prop.tarifa_id);
  update propostas set estado = 'aceite', respondida_em = now(), preco_detalhe = v_det where id = v_prop.id;
  update propostas set estado = 'recusada', respondida_em = now() where simulacao_id = v_prop.simulacao_id and id <> v_prop.id and estado = 'enviada';
  update simulacoes set estado = 'convertida' where id = v_sim.id;
  insert into encomendas (empresa_id, cliente_id, simulacao_id, proposta_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes,
                          preco_total, moeda, estado, criado_por, preco_detalhe)
  values (v_prop.empresa_id, v_sim.cliente_id, v_sim.id, v_prop.id, v_sim.origem, v_sim.destino, v_sim.tipo_carga, v_sim.descricao, v_sim.quantidade, v_sim.peso_kg,
          v_sim.volume_m3, v_sim.volumes, v_prop.preco, v_prop.moeda, 'aprovacao', auth.uid(), v_det) returning * into v_enc;
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id)
    values (v_enc.id, v_enc.empresa_id, null, 'aprovacao', 'Proposta aceite pelo cliente', auth.uid());
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_enc.empresa_id, auth.uid(), 'cliente', 'aceitar_proposta', 'propostas', v_prop.id::text, jsonb_build_object('encomenda', v_enc.codigo));
  return v_enc;
end $$;

create or replace function public.aceitar_simulacao(p_simulacao uuid, p_preco numeric default null)
returns encomendas language plpgsql security definer set search_path = public as $$
declare v_sim simulacoes; v_enc encomendas; v_prop uuid; v_preco numeric; v_det jsonb; c regras_comissao; com numeric;
begin
  if private.minha_empresa() is null or not private.papel_em(array['admin_empresa','operador']) then raise exception 'Sem permissão para aceitar simulações.'; end if;
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.empresa_destinatario_id is distinct from private.minha_empresa() then raise exception 'Simulação inexistente.'; end if;
  if v_sim.estado not in ('enviada', 'respondida') then raise exception 'A simulação já não está disponível (%).', v_sim.estado; end if;
  v_preco := coalesce(p_preco, v_sim.preco_estimado);
  if v_preco is null or v_preco <= 0 then raise exception 'Indique o preço para este pedido de cotação.'; end if;
  if v_preco > 10000000 then raise exception 'Preço inválido.'; end if;
  v_preco := round(v_preco, 2);
  if p_preco is null or v_sim.preco_estimado is not distinct from v_preco then
    v_det := v_sim.preco_detalhe;
  else  -- cotação personalizada: o preço indicado é o do prestador; a comissão Elolog aplica-se pelas mesmas regras do motor
    c := private.comissao_escolhida(v_sim.empresa_destinatario_id, null, v_sim.origem, v_sim.destino); com := private.comissao_valor(c, v_preco);
    v_det := jsonb_build_object('disponivel', true, 'origem_tarifa', 'cotacao', 'moeda', coalesce(v_sim.moeda_estimada, 'EUR'), 'preco_prestador', v_preco, 'suplementos', '[]'::jsonb,
      'suplementos_total', 0, 'comissao', com, 'apresentacao', coalesce(c.apresentacao, 'incluida'),
      'comissao_regra', case when c.id is null then null else jsonb_build_object('id', c.id, 'nome', c.nome, 'tipo_valor', c.tipo_valor, 'valor', c.valor) end,
      'preco_final', v_preco + case when c.apresentacao = 'separada' then com else 0 end,
      'liquido_prestador', v_preco - case when coalesce(c.apresentacao, 'incluida') = 'incluida' then com else 0 end);
    v_preco := (v_det ->> 'preco_final')::numeric;
  end if;
  v_det := private.preco_congelado(v_det, v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), v_sim.tarifa_estimada_id);

  update propostas set estado = 'cancelada', respondida_em = now()
   where simulacao_id = v_sim.id and empresa_id = v_sim.empresa_destinatario_id and estado = 'enviada';
  insert into propostas (simulacao_id, empresa_id, tarifa_id, preco, moeda, estado, mensagem, criado_por, respondida_em, preco_detalhe)
  values (v_sim.id, v_sim.empresa_destinatario_id, v_sim.tarifa_estimada_id, v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), 'aceite',
          case when p_preco is not null and v_sim.preco_estimado is distinct from round(p_preco, 2) then 'Aceite com preço indicado pelo prestador.'
               else 'Aceite ao preço calculado pelas tarifas do prestador.' end, auth.uid(), now(), v_det)
  returning id into v_prop;
  update simulacoes set estado = 'convertida', preco_estimado = v_preco where id = v_sim.id;

  insert into encomendas (empresa_id, cliente_id, simulacao_id, proposta_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes, preco_total, moeda,
                          estado, data_prevista, morada_recolha, remetente, destinatario, valor_declarado, observacoes, criado_por, preco_detalhe)
  values (v_sim.empresa_destinatario_id, v_sim.cliente_id, v_sim.id, v_prop, v_sim.origem, v_sim.destino, v_sim.tipo_carga, v_sim.descricao, v_sim.quantidade, v_sim.peso_kg,
          v_sim.volume_m3, v_sim.volumes, v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), 'aprovacao', v_sim.data_prevista, v_sim.morada_recolha, v_sim.remetente,
          v_sim.destinatario, v_sim.valor_declarado, v_sim.observacoes, auth.uid(), v_det)
  returning * into v_enc;

  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id)
    values (v_enc.id, v_enc.empresa_id, null, 'aprovacao', 'Simulação aceite pelo prestador', auth.uid());
  insert into notificacoes (user_id, para_plataforma, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v_sim.cliente_id, v_sim.cliente_id is null, 'simulacao_aceite',
            case when v_sim.cliente_id is null then 'Prestador aceitou um pedido registado pela Elolog' else 'O prestador aceitou o seu pedido' end,
            'Encomenda ' || v_enc.codigo || ' criada' || case when v_sim.cliente_id is null then '. Informe o cliente: ' || coalesce(v_sim.remetente->>'nome','') || ' ' || coalesce(v_sim.remetente->>'telefone','') else ' e a aguardar aprovação operacional.' end,
            'encomendas', v_enc.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_enc.empresa_id, auth.uid(), private.meu_papel()::text, 'aceitar_simulacao', 'simulacoes', v_sim.id::text, jsonb_build_object('encomenda', v_enc.codigo, 'preco', v_preco));
  return v_enc;
end $$;

-- a cópia congelada não se altera depois (nem pelo prestador, nem por engano): só a administração da plataforma
create or replace function private.proteger_preco_detalhe() returns trigger language plpgsql set search_path = public as $$
begin
  if old.preco_detalhe is not null and new.preco_detalhe is distinct from old.preco_detalhe and not private.e_admin_plataforma() then
    raise exception 'O preço acordado não muda depois de aprovado.'; end if;
  return new;
end $$;
create or replace trigger encomendas_preco_detalhe before update of preco_detalhe on public.encomendas for each row execute function private.proteger_preco_detalhe();

-- a ficha da operação passa a usar a comissão guardada na aprovação (quando existe), em vez de a recalcular
do $$ declare d text := pg_get_functiondef('public.encomenda_ficha(text)'::regprocedure); n text; begin
  n := replace(d, 'comissao := case when regra.id is null then null', 'comissao := case when (e.preco_detalhe ->> ''comissao'') is not null then (e.preco_detalhe ->> ''comissao'')::numeric when regra.id is null then null');
  if n <> d then execute n; end if;
end $$;

-- ===== 00172_comissao_percentagem.sql =====
-- v114 — Uma comissão em percentagem fica entre 0 e 100 % (validado no servidor, não só no formulário).
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'regras_comissao_percentagem_valida') then
    alter table public.regras_comissao add constraint regras_comissao_percentagem_valida
      check (valor >= 0 and (tipo_valor::text <> 'percentagem' or valor <= 100)) not valid;
  end if;
end $$;

-- ===== 00173_tarifas_veiculos.sql =====
-- v115 — Regras de cobrança (1/2): tarifários de veículos, referência visível aos prestadores e acessos do prestador ao centro.
-- Tarifa de veículo: custo da recolha/entrega por tipo de veículo (saída + km, com mínimo), escolhida pela capacidade que o pedido precisa.
-- Mesmo circuito das outras tarifas: o prestador submete, a administração aprova; tudo fica no histórico.

create table if not exists public.tarifas_veiculos (
  id uuid primary key default gen_random_uuid(), empresa_id uuid references public.empresas(id) on delete cascade,   -- null = tarifa geral da Elolog
  nome text not null check (length(trim(nome)) between 1 and 120), veiculo text not null default 'carrinha'
    check (veiculo in ('mota','ligeiro','carrinha','camiao_pequeno','camiao','pesado','outro')),
  capacidade_kg numeric check (capacidade_kg is null or capacidade_kg > 0), capacidade_m3 numeric check (capacidade_m3 is null or capacidade_m3 > 0),
  preco_saida numeric not null default 0 check (preco_saida >= 0 and preco_saida <= 1000000),
  preco_km numeric not null default 0 check (preco_km >= 0 and preco_km <= 100000),
  preco_minimo numeric not null default 0 check (preco_minimo >= 0 and preco_minimo <= 1000000),
  moeda text not null default 'EUR', servico text, versao int not null default 1,
  estado text not null default 'pendente' check (estado in ('pendente','aprovado','rejeitado','suspenso','inativo')),
  validade_inicio date, validade_fim date, motivo_decisao text, motivo_alteracao text, criado_por uuid references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint tarifas_veiculos_validade check (validade_fim is null or validade_inicio is null or validade_fim >= validade_inicio));
create index if not exists tarifas_veiculos_empresa on public.tarifas_veiculos (empresa_id, estado);
alter table public.tarifas_veiculos enable row level security;
revoke all on public.tarifas_veiculos from anon;
grant select, insert, update on public.tarifas_veiculos to authenticated;
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas_veiculos' and policyname = 'tv_admin') then
  create policy tv_admin on public.tarifas_veiculos for all to authenticated using (private.e_admin_plataforma()) with check (private.e_admin_plataforma());
end if; end $$;
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas_veiculos' and policyname = 'tv_empresa') then
  create policy tv_empresa on public.tarifas_veiculos for all to authenticated
  using (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']))
  with check (empresa_id = private.minha_empresa() and private.papel_em(array['admin_empresa','financeiro']));
end if; end $$;
-- os prestadores veem as tarifas gerais de veículos em vigor (para comparar), sem as poder mudar
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas_veiculos' and policyname = 'tv_geral_ve') then
  create policy tv_geral_ve on public.tarifas_veiculos for select to authenticated
  using (empresa_id is null and estado = 'aprovado' and private.minha_empresa() is not null);
end if; end $$;

-- guarda: o prestador só cria «pendente»; mudar preço ou capacidade de uma tarifa aprovada volta a «pendente» e sobe a versão
create or replace function private.veiculo_guarda() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if auth.uid() is not null and not private.e_admin_plataforma() then
    if new.empresa_id is null then raise exception 'As tarifas gerais de veículos são da administração Elolog.' using errcode = '42501'; end if;
    if tg_op = 'INSERT' then new.estado := 'pendente'; new.motivo_decisao := null; new.versao := 1;
    else
      new.motivo_decisao := old.motivo_decisao; new.empresa_id := old.empresa_id;
      if (new.veiculo, new.capacidade_kg, new.capacidade_m3, new.preco_saida, new.preco_km, new.preco_minimo, new.moeda, new.servico, new.validade_inicio, new.validade_fim)
         is distinct from (old.veiculo, old.capacidade_kg, old.capacidade_m3, old.preco_saida, old.preco_km, old.preco_minimo, old.moeda, old.servico, old.validade_inicio, old.validade_fim) then
        new.estado := 'pendente'; new.versao := old.versao + 1;
      elsif new.estado not in ('pendente', 'inativo') and new.estado is distinct from old.estado then
        raise exception 'Só a administração Elolog pode aprovar ou suspender tarifas de veículos.' using errcode = '42501';
      end if;
    end if;
  elsif tg_op = 'UPDATE' and (new.preco_saida, new.preco_km, new.preco_minimo, new.capacidade_kg, new.capacidade_m3)
        is distinct from (old.preco_saida, old.preco_km, old.preco_minimo, old.capacidade_kg, old.capacidade_m3) then
    new.versao := old.versao + 1;
  end if;
  return new;
end $$;
create or replace trigger tarifas_veiculos_guarda before insert or update on public.tarifas_veiculos for each row execute function private.veiculo_guarda();
create or replace trigger tarifas_veiculos_registo after insert or update on public.tarifas_veiculos for each row execute function private.tarifa_registo();

create or replace function public.veiculo_decidir(p_veiculo uuid, p_decisao text, p_motivo text default null)
returns public.tarifas_veiculos language plpgsql security definer set search_path = public as $$
declare v tarifas_veiculos; v_para text := case p_decisao when 'aprovar' then 'aprovado' when 'rejeitar' then 'rejeitado' when 'suspender' then 'suspenso' when 'reativar' then 'aprovado' end;
begin
  if not private.e_admin_plataforma() then raise exception 'Só a administração Elolog decide sobre tarifas de veículos.' using errcode = '42501'; end if;
  if v_para is null then raise exception 'Decisão desconhecida.'; end if;
  if p_decisao in ('rejeitar', 'suspender') and coalesce(trim(p_motivo), '') = '' then raise exception 'Indique o motivo: o prestador vai lê-lo.'; end if;
  perform set_config('elolog.motivo', coalesce(nullif(trim(p_motivo), ''), initcap(p_decisao)), true);
  update tarifas_veiculos set estado = v_para, motivo_decisao = nullif(trim(p_motivo), '') where id = p_veiculo returning * into v;
  if not found then raise exception 'Tarifa de veículo inexistente.'; end if;
  if v.empresa_id is not null then
    insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v.empresa_id, 'veiculo_decisao', 'Tarifa de veículo ' || v_para, '«' || v.nome || '»' || coalesce('. ' || nullif(trim(p_motivo), ''), '.'), 'tarifas_veiculos', v.id);
  end if;
  perform set_config('elolog.motivo', '', true);
  return v;
end $$;
revoke all on function public.veiculo_decidir(uuid, text, text) from public, anon;
grant execute on function public.veiculo_decidir(uuid, text, text) to authenticated;

-- avisar a Elolog quando um prestador submete uma tarifa de veículo
create or replace function private.veiculo_aviso() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.empresa_id is not null and new.estado = 'pendente' and (tg_op = 'INSERT' or old.estado is distinct from 'pendente') then
    insert into notificacoes (para_plataforma, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (true, 'veiculo_submetido', 'Uma tarifa de veículo espera aprovação',
            coalesce((select nome from empresas where id = new.empresa_id), 'Um prestador') || ' submeteu «' || new.nome || '».', 'tarifas_veiculos', new.id);
  end if;
  return new;
end $$;
create or replace trigger tarifas_veiculos_aviso after insert or update of estado on public.tarifas_veiculos for each row execute function private.veiculo_aviso();

-- os prestadores aprovados veem os tarifários gerais de REFERÊNCIA em vigor (para alinharem os preços); os comerciais só se estiverem associados
do $$ begin if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'tarifas_gerais' and policyname = 'tg_prestador_ref') then
  create policy tg_prestador_ref on public.tarifas_gerais for select to authenticated
  using (uso = 'referencia' and estado = 'ativa' and private.minha_empresa() is not null);
end if; end $$;

-- comissões que se aplicam à empresa do prestador (só leitura, só as ativas, sem as regras de outros prestadores)
create or replace function public.minhas_comissoes()
returns table (nome text, tipo_valor text, valor numeric, metodo text, rota_origem text, rota_destino text, inicio date, fim date, promocional boolean, apresentacao text, geral boolean)
language sql stable security definer set search_path = public as $$
  select c.nome, c.tipo_valor::text, c.valor, c.metodo::text, c.rota_origem, c.rota_destino, c.inicio, c.fim, c.promocional, c.apresentacao, c.empresa_id is null
    from regras_comissao c
   where private.minha_empresa() is not null and private.papel_em(array['admin_empresa','financeiro'])
     and c.ativa and (c.fim is null or c.fim >= current_date) and (c.empresa_id is null or c.empresa_id = private.minha_empresa())
   order by (c.empresa_id is not null) desc, c.prioridade desc $$;
revoke all on function public.minhas_comissoes() from public, anon;
grant execute on function public.minhas_comissoes() to authenticated;

-- ===== 00174_motor_descricao_veiculos.sql =====
-- v115 — Regras de cobrança (2/2): o motor de preços passa a procurar pela DESCRIÇÃO da carga e a usar as tarifas de veículos.
-- Motor de busca: quando a descrição do pedido contém o nome de uma tarifa (ou uma das suas palavras-chave), essa tarifa ganha.
--   Ex.: tarifa «Frigorífico» (por unidade) e descrição «2 frigoríficos combinados» → usa a tarifa «Frigorífico».
--   Uma tarifa marcada «só pela descrição» (regras.so_descricao) só entra quando a descrição coincide.
-- Recolha: com km pedidos, usa a tarifa de veículo aprovada mais barata que leva o peso e o volume (do prestador; senão, a geral da Elolog);
--   sem tarifa de veículo, fica tudo como antes (suplemento de recolha ou 1 € por km).
-- As funções antigas continuam (mesmas assinaturas) e passam pelo motor novo, sem descrição: o resultado é o de sempre.

-- palavras da descrição comparadas por início de palavra, sem acentos nem maiúsculas (aceita plurais: «frigorífico» ↔ «frigoríficos»)
create or replace function private.descricao_bate(p_desc text, p_nome text, p_regras jsonb) returns boolean
language sql stable set search_path = public, extensions as $$
  select coalesce(trim(p_desc), '') <> '' and exists (
    select 1 from (select p_nome as w union all
                   select jsonb_array_elements_text(case when jsonb_typeof(p_regras -> 'palavras') = 'array' then p_regras -> 'palavras' else '[]'::jsonb end)) x,
                  lateral (select trim(regexp_replace(private.norm(x.w), '[^a-z0-9]+', ' ', 'g')) as p) n
     where length(n.p) >= 3
       and strpos(' ' || regexp_replace(private.norm(p_desc), '[^a-z0-9]+', ' ', 'g') || ' ', ' ' || n.p) > 0) $$;

create or replace function private.tarifa_escolhida_d(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric, p_descricao text)
returns public.tarifas language sql stable security definer set search_path = public, extensions as $$
  select t.* from tarifas t
   where t.empresa_id = p_empresa and t.estado = 'aprovada' and t.aplicacao = 'carga'
     and (t.validade_inicio is null or t.validade_inicio <= current_date) and (t.validade_fim is null or t.validade_fim >= current_date)
     and private.rota_bate(t.origem, p_origem) and private.rota_bate(t.destino, p_destino)
     and (coalesce(t.transporte, '') = '' or coalesce(p_servico, '') = '' or private.norm(t.transporte) = private.norm(p_servico))
     and (coalesce(t.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = '' or strpos(private.norm(p_tipo_carga), private.norm(t.tipo_carga)) > 0)
     and (coalesce(t.regras ->> 'so_descricao', '') <> 'true' or private.descricao_bate(p_descricao, t.nome, t.regras))
     and private.tarifa_compativel(t.metodo, t.regras, t.limite_min, t.limite_max, q, peso, vol)
   order by private.descricao_bate(p_descricao, t.nome, t.regras) desc,
            ((coalesce(t.origem, '') <> '')::int + (coalesce(t.destino, '') <> '')::int + (coalesce(t.tipo_carga, '') <> '')::int + (coalesce(t.transporte, '') <> '')::int) desc,
            t.versao desc, t.created_at desc limit 1 $$;
create or replace function private.tarifa_escolhida(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric)
returns public.tarifas language sql stable security definer set search_path = public, extensions as $$
  select * from private.tarifa_escolhida_d(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol, null) $$;

create or replace function private.tarifa_geral_escolhida_d(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric, p_descricao text)
returns public.tarifas_gerais language sql stable security definer set search_path = public, extensions as $$
  select g.* from tarifas_gerais g
   where g.uso = 'comercial' and g.estado = 'ativa' and p_empresa = any (g.prestadores)
     and (g.validade_inicio is null or g.validade_inicio <= current_date) and (g.validade_fim is null or g.validade_fim >= current_date)
     and private.rota_bate(g.origem, p_origem) and private.rota_bate(g.destino, p_destino)
     and (coalesce(g.servico, '') = '' or coalesce(p_servico, '') = '' or private.norm(g.servico) = private.norm(p_servico))
     and (coalesce(g.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = '' or strpos(private.norm(p_tipo_carga), private.norm(g.tipo_carga)) > 0)
     and (coalesce(g.regras ->> 'so_descricao', '') <> 'true' or private.descricao_bate(p_descricao, g.nome, g.regras))
     and private.tarifa_compativel(g.metodo, g.regras, g.limite_min, g.limite_max, q, peso, vol)
   order by private.descricao_bate(p_descricao, g.nome, g.regras) desc,
            ((coalesce(g.origem, '') <> '')::int + (coalesce(g.destino, '') <> '')::int + (coalesce(g.tipo_carga, '') <> '')::int) desc, g.versao desc limit 1 $$;
create or replace function private.tarifa_geral_escolhida(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric)
returns public.tarifas_gerais language sql stable security definer set search_path = public, extensions as $$
  select * from private.tarifa_geral_escolhida_d(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol, null) $$;

-- o veículo aprovado mais barato que leva a carga (primeiro os do prestador, depois os gerais da Elolog)
create or replace function private.veiculo_escolhido(p_empresa uuid, p_servico text, peso numeric, vol numeric, km numeric) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('id', v.id, 'nome', v.nome, 'chave', 'recolha_km', 'tipo', 'veiculo', 'veiculo', v.veiculo, 'valor', v.preco_km,
           'montante', round(greatest(v.preco_minimo, v.preco_saida + coalesce(km, 0) * v.preco_km), 2), 'origem', case when v.empresa_id is null then 'elolog' else 'prestador' end, 'versao', v.versao)
    from tarifas_veiculos v
   where v.estado = 'aprovado' and (v.empresa_id = p_empresa or v.empresa_id is null)
     and (v.validade_inicio is null or v.validade_inicio <= current_date) and (v.validade_fim is null or v.validade_fim >= current_date)
     and (coalesce(v.servico, '') = '' or coalesce(p_servico, '') = '' or private.norm(v.servico) = private.norm(p_servico))
     and (v.capacidade_kg is null or coalesce(peso, 0) <= v.capacidade_kg) and (v.capacidade_m3 is null or coalesce(vol, 0) <= v.capacidade_m3)
   order by (v.empresa_id is null), greatest(v.preco_minimo, v.preco_saida + coalesce(km, 0) * v.preco_km), v.updated_at desc limit 1 $$;

create or replace function private.suplementos_calc_d(p_empresa uuid, p_servico text, p_tipo_carga text, p_km numeric, p_base numeric, peso numeric, vol numeric)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare r record; itens jsonb := '[]'; total numeric := 0; m numeric; tem_recolha boolean := false; vei jsonb;
begin
  if coalesce(p_km, 0) > 0 then
    vei := private.veiculo_escolhido(p_empresa, p_servico, peso, vol, p_km);
    if vei is not null then tem_recolha := true; total := (vei ->> 'montante')::numeric; itens := jsonb_build_array(vei); end if;
  end if;
  for r in select distinct on (s.chave, case when s.chave = 'outro' then s.id end) s.* from tarifa_suplementos s
            where s.estado = 'aprovado' and (s.empresa_id = p_empresa or s.empresa_id is null)
              and (s.validade_inicio is null or s.validade_inicio <= current_date) and (s.validade_fim is null or s.validade_fim >= current_date)
              and (coalesce(s.servico, '') = '' or coalesce(p_servico, '') = '' or private.norm(s.servico) = private.norm(p_servico))
              and (coalesce(s.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = '' or strpos(private.norm(p_tipo_carga), private.norm(s.tipo_carga)) > 0)
            order by s.chave, case when s.chave = 'outro' then s.id end, (s.empresa_id is null), s.updated_at desc loop
    if r.chave = 'recolha_km' then
      if coalesce(p_km, 0) <= 0 or vei is not null then continue; end if; tem_recolha := true;
    elsif not r.automatico then continue; end if;
    m := round(case r.tipo when 'fixo' then r.valor when 'percentual' then p_base * r.valor / 100 else coalesce(p_km, 0) * r.valor end, 2);
    total := total + m;
    itens := itens || jsonb_build_object('id', r.id, 'nome', r.nome, 'chave', r.chave, 'tipo', r.tipo, 'valor', r.valor, 'montante', m, 'origem', case when r.empresa_id is null then 'elolog' else 'prestador' end);
  end loop;
  if coalesce(p_km, 0) > 0 and not tem_recolha then
    m := round(p_km * private.custo_recolha_por_km(), 2); total := total + m;
    itens := itens || jsonb_build_object('nome', 'Recolha na morada', 'chave', 'recolha_km', 'tipo', 'por_km', 'valor', private.custo_recolha_por_km(), 'montante', m, 'origem', 'elolog');
  end if;
  return jsonb_build_object('total', total, 'itens', itens);
end $$;
create or replace function private.suplementos_calc(p_empresa uuid, p_servico text, p_tipo_carga text, p_km numeric, p_base numeric)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select private.suplementos_calc_d(p_empresa, p_servico, p_tipo_carga, p_km, p_base, null, null) $$;

-- ===== 00175_motor_v2.sql =====
-- v115 — o motor de preços com a descrição da carga e os veículos (continua a ser a fonte única de preços).
-- private.motor_preco (assinatura antiga) passa a chamar private.motor_preco_d sem descrição: o resultado não muda.

create or replace function private.motor_preco_d(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric, km numeric, p_descricao text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare t tarifas; g tarifas_gerais; c regras_comissao; base numeric; sup jsonb; com numeric; ap text; met metodo_cobranca; tj jsonb; orig text; moeda text; achou boolean := false;
begin
  t := private.tarifa_escolhida_d(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol, p_descricao);
  if t.id is not null then
    met := t.metodo; orig := 'prestador'; moeda := t.moeda; achou := private.descricao_bate(p_descricao, t.nome, t.regras);
    base := private.tarifa_preco(t.metodo, t.valor, t.preco_minimo, t.preco_maximo, t.regras, q, peso, vol);
    tj := jsonb_build_object('id', t.id, 'nome', t.nome, 'versao', t.versao, 'metodo', t.metodo, 'valor', t.valor, 'moeda', t.moeda, 'preco_minimo', t.preco_minimo,
          'preco_maximo', t.preco_maximo, 'limite_min', t.limite_min, 'limite_max', t.limite_max, 'regras', t.regras, 'validade_inicio', t.validade_inicio, 'validade_fim', t.validade_fim, 'notas', t.notas);
  else
    g := private.tarifa_geral_escolhida_d(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol, p_descricao);
    if g.id is null then
      return jsonb_build_object('disponivel', false, 'mensagem', 'Não existe uma tarifa automática disponível. Solicite uma cotação personalizada.');
    end if;
    met := g.metodo; orig := 'geral'; moeda := g.moeda; achou := private.descricao_bate(p_descricao, g.nome, g.regras);
    base := private.tarifa_preco(g.metodo, g.valor, g.preco_minimo, g.preco_maximo, g.regras, q, peso, vol);
    tj := jsonb_build_object('id', g.id, 'codigo', g.codigo, 'nome', g.nome, 'versao', g.versao, 'metodo', g.metodo, 'valor', g.valor, 'moeda', g.moeda, 'preco_minimo', g.preco_minimo,
          'preco_maximo', g.preco_maximo, 'limite_min', g.limite_min, 'limite_max', g.limite_max, 'regras', g.regras, 'validade_inicio', g.validade_inicio, 'validade_fim', g.validade_fim, 'condicoes', g.condicoes);
  end if;
  sup := private.suplementos_calc_d(p_empresa, p_servico, p_tipo_carga, km, base, peso, vol);
  c := private.comissao_escolhida(p_empresa, met, p_origem, p_destino);
  com := private.comissao_valor(c, base + (sup ->> 'total')::numeric); ap := coalesce(c.apresentacao, 'incluida');
  return jsonb_build_object('disponivel', true, 'origem_tarifa', orig, 'tarifa_id', case when orig = 'prestador' then t.id end, 'tarifa', tj, 'moeda', moeda,
    'pela_descricao', achou,
    'pedido', jsonb_build_object('servico', p_servico, 'origem', p_origem, 'destino', p_destino, 'tipo_carga', p_tipo_carga, 'descricao', p_descricao, 'quantidade', q, 'peso_kg', peso,
                                 'volume_m3', vol, 'recolha_km', km, 'medida', private.tarifa_medida(met, tj -> 'regras', q, peso, vol)),
    'preco_prestador', base, 'suplementos', sup -> 'itens', 'suplementos_total', (sup ->> 'total')::numeric,
    'comissao', com, 'apresentacao', ap,
    'comissao_regra', case when c.id is null then null else jsonb_build_object('id', c.id, 'nome', c.nome, 'tipo_valor', c.tipo_valor, 'valor', c.valor, 'promocional', c.promocional) end,
    'preco_final', base + (sup ->> 'total')::numeric + case when ap = 'separada' then com else 0 end,
    'liquido_prestador', base + (sup ->> 'total')::numeric - case when ap = 'incluida' then com else 0 end, 'calculado_em', now());
end $$;
revoke all on function private.motor_preco_d(uuid, text, text, text, text, int, numeric, numeric, numeric, text) from public, anon, authenticated;

create or replace function private.motor_preco(p_empresa uuid, p_servico text, p_origem text, p_destino text, p_tipo_carga text, q int, peso numeric, vol numeric, km numeric)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select private.motor_preco_d(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, q, peso, vol, km, null) $$;

-- simulador do cliente: igual a calcular_precos, com a descrição da carga (o cliente só recebe o preço final)
create or replace function public.precos_automaticos(p_origem text, p_destino text, p_tipo_carga text default null, p_quantidade int default 0, p_peso_kg numeric default 0,
  p_volume_m3 numeric default 0, p_recolha_km numeric default 0, p_servico text default null, p_descricao text default null)
returns table (prestador_id uuid, prestador_nome text, disponivel boolean, preco_final numeric, taxa_servico numeric, moeda char(3), mensagem text)
language plpgsql stable security definer set search_path = public as $$
declare r record; m jsonb;
begin
  if not exists (select 1 from clientes c where c.id = auth.uid()) and not private.e_admin_plataforma() then raise exception 'Apenas clientes autenticados.'; end if;
  if coalesce(trim(p_origem), '') = '' or coalesce(trim(p_destino), '') = '' then raise exception 'Indique origem e destino.'; end if;
  if least(coalesce(p_quantidade, 0), coalesce(p_peso_kg, 0), coalesce(p_volume_m3, 0), coalesce(p_recolha_km, 0)) < 0 then raise exception 'Valores negativos não são permitidos.'; end if;
  if length(coalesce(p_descricao, '')) > 1000 then raise exception 'A descrição é demasiado longa.'; end if;
  for r in select e.id, e.nome from empresas_disponiveis e order by e.nome loop
    m := private.motor_preco_d(r.id, p_servico, p_origem, p_destino, p_tipo_carga, p_quantidade, p_peso_kg, p_volume_m3, p_recolha_km, p_descricao);
    prestador_id := r.id; prestador_nome := r.nome; disponivel := (m ->> 'disponivel')::boolean;
    preco_final := (m ->> 'preco_final')::numeric; moeda := m ->> 'moeda'; mensagem := m ->> 'mensagem';
    taxa_servico := case when m ->> 'apresentacao' = 'separada' then (m ->> 'comissao')::numeric end;
    return next;
  end loop;
end $$;
revoke all on function public.precos_automaticos(text, text, text, int, numeric, numeric, numeric, text, text) from public, anon;
grant execute on function public.precos_automaticos(text, text, text, int, numeric, numeric, numeric, text, text) to authenticated;

-- simulador de preços do centro: a administração testa qualquer prestador; o prestador (administrador ou financeiro) só a sua empresa
create or replace function public.simular_preco(p_empresa uuid, p_origem text, p_destino text, p_tipo_carga text default null, p_quantidade int default 0, p_peso_kg numeric default 0,
  p_volume_m3 numeric default 0, p_recolha_km numeric default 0, p_servico text default null, p_descricao text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid := p_empresa;
begin
  if not private.e_admin_plataforma() then
    if private.minha_empresa() is null or not private.papel_em(array['admin_empresa','financeiro']) then
      raise exception 'Só a administração Elolog ou o financeiro da empresa podem simular preços.' using errcode = '42501'; end if;
    v_emp := private.minha_empresa();
  end if;
  if v_emp is null then raise exception 'Escolha o prestador.'; end if;
  if least(coalesce(p_quantidade, 0), coalesce(p_peso_kg, 0), coalesce(p_volume_m3, 0), coalesce(p_recolha_km, 0)) < 0 then raise exception 'Valores negativos não são permitidos.'; end if;
  return private.motor_preco_d(v_emp, p_servico, p_origem, p_destino, p_tipo_carga, p_quantidade, p_peso_kg, p_volume_m3, p_recolha_km, p_descricao);
end $$;
revoke all on function public.simular_preco(uuid, text, text, text, int, numeric, numeric, numeric, text, text) from public, anon;
grant execute on function public.simular_preco(uuid, text, text, text, int, numeric, numeric, numeric, text, text) to authenticated;

-- o envio ao prestador usa a descrição guardada na simulação (mesmo preço que o cliente viu)
do $$ declare d text := pg_get_functiondef('public.enviar_simulacao(uuid, uuid)'::regprocedure); n text; begin
  n := replace(d, 'm := private.motor_preco(p_empresa, null, v_sim.origem, v_sim.destino, v_sim.tipo_carga, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3,
                           case when v_sim.recolha_na_morada then coalesce(v_sim.recolha_distancia_km, 0) else 0 end);',
                  'm := private.motor_preco_d(p_empresa, null, v_sim.origem, v_sim.destino, v_sim.tipo_carga, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3,
                           case when v_sim.recolha_na_morada then coalesce(v_sim.recolha_distancia_km, 0) else 0 end, v_sim.descricao);');
  if n = d then raise exception 'enviar_simulacao: não encontrei a chamada ao motor para atualizar.'; end if;
  execute n;
end $$;


commit;

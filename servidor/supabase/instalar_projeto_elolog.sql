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

commit;

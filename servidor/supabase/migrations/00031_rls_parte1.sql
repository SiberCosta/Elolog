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

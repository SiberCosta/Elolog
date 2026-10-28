-- Elolog — instalação, parte 2 de 4 (00051_prestador_parte1.sql a 00071_admin.sql). Correr pela ordem: 1, 2, 3, 4.
begin;
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
commit;

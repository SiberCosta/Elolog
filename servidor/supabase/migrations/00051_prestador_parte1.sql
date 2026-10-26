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

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

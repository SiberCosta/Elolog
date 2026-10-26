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

-- =====================================================================
-- Elolog · Aprovar manualmente uma empresa que se registou (operação da administração)
-- ALTERNATIVA ao painel da administração (que já faz isto, com confirmação de pagamento, motivo e auditoria).
-- Use este script só se o painel não estiver disponível.
-- Executar no SQL Editor do Supabase (corre como administrador da base de dados).
--
-- Contorna decidir_empresa(), que exige uma sessão de administrador da plataforma (auth.uid()),
-- e por isso REGISTA a decisão na auditoria. Confirme o pagamento da subscrição ANTES de correr.
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- =====================================================================

-- 1) Ver os registos pendentes (empresa, plano, pagamento declarado)
select e.nome, e.nif, e.email, e.estado, p.nome as plano, s.valor, s.metodo_pagamento, s.referencia, s.pago_em, e.created_at
  from empresas e
  join subscricoes s on s.empresa_id = e.id
  join planos p on p.id = s.plano_id
 where e.estado = 'pendente'
 order by e.created_at;

-- 2) Aprovar UMA empresa (trocar o NIF). Só depois de confirmar o pagamento.
do $$
declare
  v_nif text := '500123456';          -- <<< NIF da empresa a aprovar
  v_emp uuid;
begin
  select id into v_emp from empresas where nif = v_nif and estado = 'pendente';
  if v_emp is null then raise exception 'Não há empresa PENDENTE com o NIF %.', v_nif; end if;

  update subscricoes set pago_em = now(), estado = 'ativa' where empresa_id = v_emp and estado = 'pendente';
  update empresas set estado = 'aprovada', aprovada_em = now() where id = v_emp;

  insert into auditoria (empresa_id, papel, acao, entidade, entidade_id, depois)
    values (v_emp, 'admin_plataforma', 'aprovar_empresa_manual', 'empresas', v_emp::text,
            jsonb_build_object('nif', v_nif, 'via', 'SQL Editor'));
  raise notice 'Empresa % aprovada. O administrador já pode iniciar sessão.', v_nif;
end $$;

-- 3) Recusar (em vez de aprovar):
-- update empresas set estado = 'rejeitada' where nif = '500123456' and estado = 'pendente';
-- update subscricoes set estado = 'cancelada' where empresa_id = (select id from empresas where nif = '500123456');

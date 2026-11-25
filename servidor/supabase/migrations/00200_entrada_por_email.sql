-- v163 — Entrada por email para todos.
-- Depois de entrar com email (ou telemóvel) e palavra-passe, a aplicação pergunta ao servidor que tipo de conta é e
-- abre a área certa:
--   · cliente          → área de cliente (nada muda);
--   · equipa Elolog     → consola (com a verificação em dois passos de sempre);
--   · funcionário       → abre já a sessão da empresa (como «entrar-funcionario», mas sem pedir NIF nem n.º);
--   · admin da empresa  → NÃO abre a sessão: devolve o nome e o NIF da empresa para a aplicação pedir a palavra-passe da
--                         empresa e o código de verificação (abrir_sessao_empresa, como até aqui).
-- Não muda tabelas, regras de acesso nem dados. Só junta uma função chamável por quem já tem sessão.

create or replace function public.entrar_por_email()
returns table(tipo text, mensagem text, empresa_id uuid, empresa_nome text, empresa_nome_registo text, empresa_nif text,
              papel papel_funcionario, funcionario_nome text, email text, valida_ate timestamptz)
language plpgsql security definer set search_path to 'public' as $$
declare f funcionarios; e empresas; v_validade timestamptz := now() + interval '12 hours';
begin
  if auth.uid() is null then raise exception 'Sem sessão iniciada.'; end if;
  if exists (select 1 from administradores_plataforma a where a.user_id = auth.uid()) then
    return query select 'equipa'::text, null::text, null::uuid, null::text, null::text, null::text, null::papel_funcionario, null::text, null::text, null::timestamptz; return;
  end if;
  select * into f from funcionarios where id = auth.uid();
  if not found then
    return query select 'cliente'::text, null::text, null::uuid, null::text, null::text, null::text, null::papel_funcionario, null::text, null::text, null::timestamptz; return;
  end if;
  select * into e from empresas where id = f.empresa_id;
  if not f.ativo then
    return query select 'recusado'::text, 'Esta conta de funcionário está desativada. Contacte o administrador da empresa.'::text,
      null::uuid, null::text, null::text, null::text, null::papel_funcionario, null::text, null::text, null::timestamptz; return;
  end if;
  if e.estado = 'pendente' then
    return query select 'recusado'::text, 'O registo da empresa aguarda validação da administração.'::text,
      null::uuid, null::text, null::text, null::text, null::papel_funcionario, null::text, null::text, null::timestamptz; return;
  end if;
  if e.estado <> 'aprovada' then
    return query select 'recusado'::text, 'A empresa não está autorizada a aceder à plataforma.'::text,
      null::uuid, null::text, null::text, null::text, null::papel_funcionario, null::text, null::text, null::timestamptz; return;
  end if;
  if f.papel = 'admin_empresa' then
    -- o administrador continua a precisar da palavra-passe da empresa e do código (abrir_sessao_empresa)
    return query select 'admin_empresa'::text, null::text, e.id, coalesce(e.nome_comercial, e.nome), e.nome, e.nif, f.papel, f.nome, f.email, null::timestamptz; return;
  end if;
  insert into sessoes_empresa (user_id, empresa_id, valida_ate) values (auth.uid(), f.empresa_id, v_validade)
  on conflict (user_id) do update set empresa_id = excluded.empresa_id, valida_ate = excluded.valida_ate;
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id)
    values (f.empresa_id, auth.uid(), f.papel::text, 'abrir_sessao_funcionario_email', 'funcionarios', auth.uid()::text);
  return query select 'funcionario'::text, null::text, e.id, coalesce(e.nome_comercial, e.nome), e.nome, e.nif, f.papel, f.nome, f.email, v_validade;
end $$;

revoke all on function public.entrar_por_email() from public, anon;
grant execute on function public.entrar_por_email() to authenticated;

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

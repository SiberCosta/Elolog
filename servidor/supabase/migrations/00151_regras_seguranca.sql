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

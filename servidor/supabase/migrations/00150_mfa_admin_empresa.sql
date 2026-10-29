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

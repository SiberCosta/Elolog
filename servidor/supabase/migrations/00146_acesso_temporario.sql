-- v76 — A equipa Elolog cria um prestador com um CÓDIGO DE ACESSO TEMPORÁRIO (válido 72 h), enviado por email ao administrador
-- da empresa. O código serve de palavra-passe da empresa e da conta pessoal; no primeiro início de sessão é obrigatório trocar as duas.
-- Enquanto não trocar, a conta não vê nem altera nenhum dado da empresa (minha_empresa / meu_papel devolvem nulo).
-- (Inclui também a regra da v81: o administrador da empresa precisa do 2.º passo — sessão aal2.)

create table if not exists acessos_temporarios (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  empresa_id uuid not null references empresas(id) on delete cascade,
  expira_em  timestamptz not null,
  criado_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table acessos_temporarios enable row level security;
revoke all on acessos_temporarios from anon, authenticated;

create or replace function private.minha_empresa() returns uuid
language sql stable security definer set search_path = public as $$ select f.empresa_id from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = auth.uid() and f.ativo and (f.papel <> 'admin_empresa' or coalesce(auth.jwt() ->> 'aal', '') = 'aal2')
     and not exists (select 1 from acessos_temporarios t where t.user_id = f.id) $$;
create or replace function private.meu_papel() returns papel_funcionario
language sql stable security definer set search_path = public as $$ select f.papel from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = auth.uid() and f.ativo and (f.papel <> 'admin_empresa' or coalesce(auth.jwt() ->> 'aal', '') = 'aal2')
     and not exists (select 1 from acessos_temporarios t where t.user_id = f.id) $$;
create or replace function public.servico_admin_empresa(p_user uuid) returns uuid
language sql stable security definer set search_path = public as $$ select f.empresa_id from funcionarios f
    join empresas em on em.id = f.empresa_id and em.estado = 'aprovada'
    join sessoes_empresa s on s.user_id = f.id and s.empresa_id = f.empresa_id and s.valida_ate > now()
   where f.id = p_user and f.ativo and f.papel = 'admin_empresa' and not exists (select 1 from acessos_temporarios t where t.user_id = f.id) $$;

-- Estado do primeiro acesso da conta com sessão iniciada (a interface pergunta logo a seguir ao login).
create or replace function public.primeiro_acesso() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('pendente', true, 'expirado', t.expira_em < now(), 'expira_em', t.expira_em)
    from acessos_temporarios t where t.user_id = auth.uid()), jsonb_build_object('pendente', false))
$$;

-- Criar o prestador (só a Edge Function «criar-prestador», depois de criar a conta de autenticação do administrador).
create or replace function public.servico_criar_prestador_admin(p_autor uuid, p_user uuid, p_empresa jsonb, p_admin_nome text, p_admin_email text,
  p_plano text, p_aprovada boolean, p_codigo text, p_expira timestamptz) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; v_plano planos; t text := '';
begin
  if not public.servico_equipa_pode_gerir(p_autor) then raise exception 'Só um administrador da plataforma pode criar prestadores.'; end if;
  if length(trim(coalesce(p_empresa->>'nome', ''))) < 2 then raise exception 'Indique o nome legal da empresa.'; end if;
  if coalesce(p_empresa->>'nif', '') !~ '^\s*\d{9}\s*$' then raise exception 'O NIF da empresa deve ter 9 algarismos.'; end if;
  if exists (select 1 from empresas where private.norm(nif) = private.norm(p_empresa->>'nif')) then raise exception 'Já existe uma empresa registada com este NIF.'; end if;
  if length(coalesce(p_codigo, '')) < 10 then raise exception 'Código temporário inválido.'; end if;
  select * into v_plano from planos where lower(nome) = lower(trim(coalesce(p_plano, ''))) and ativo;
  insert into empresas (nome, nome_comercial, nif, email, telefone, morada, codigo_postal, cidade, pais, estado, aprovada_por, aprovada_em)
  values (trim(p_empresa->>'nome'), nullif(trim(p_empresa->>'nome_comercial'), ''), trim(p_empresa->>'nif'), lower(trim(p_empresa->>'email')),
    nullif(trim(p_empresa->>'telefone'), ''), nullif(trim(p_empresa->>'morada'), ''), nullif(trim(p_empresa->>'codigo_postal'), ''),
    nullif(trim(p_empresa->>'cidade'), ''), coalesce(nullif(trim(p_empresa->>'pais'), ''), 'Portugal'),
    (case when p_aprovada then 'aprovada' else 'pendente' end)::estado_empresa, case when p_aprovada then p_autor end, case when p_aprovada then now() end)
  returning id into v_emp;
  insert into empresa_segredos (empresa_id, segredo_hash) values (v_emp, extensions.crypt(p_codigo, extensions.gen_salt('bf')));
  if v_plano.id is not null then
    insert into subscricoes (empresa_id, plano_id, estado, periodicidade, valor) values (v_emp, v_plano.id, 'pendente', 'mensal', v_plano.preco_mensal);
  end if;
  insert into funcionarios (id, empresa_id, nome, email, papel) values (p_user, v_emp, trim(p_admin_nome), lower(trim(p_admin_email)), 'admin_empresa');
  insert into acessos_temporarios (user_id, empresa_id, expira_em, criado_por) values (p_user, v_emp, p_expira, p_autor);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_emp, p_autor, 'admin_plataforma', 'criar_prestador_admin', 'empresas', v_emp::text, jsonb_build_object('plano', v_plano.nome, 'aprovada', p_aprovada, 'expira_em', p_expira));
  return v_emp;
end $$;

-- Novo código para um primeiro acesso ainda pendente (o anterior deixa de valer). Devolve o administrador e a empresa.
create or replace function public.servico_renovar_acesso_temporario(p_autor uuid, p_empresa uuid, p_codigo text, p_expira timestamptz)
returns table (user_id uuid, email text, nome text, empresa text, nif text)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.servico_equipa_pode_gerir(p_autor) then raise exception 'Só um administrador da plataforma pode reenviar códigos.'; end if;
  if length(coalesce(p_codigo, '')) < 10 then raise exception 'Código temporário inválido.'; end if;
  update acessos_temporarios t set expira_em = p_expira, criado_por = p_autor where t.empresa_id = p_empresa;
  if not found then raise exception 'Esta empresa já concluiu o primeiro acesso.'; end if;
  update empresa_segredos set segredo_hash = extensions.crypt(p_codigo, extensions.gen_salt('bf')) where empresa_id = p_empresa;
  delete from tentativas_gate where chave = p_empresa::text;
  return query select t.user_id, f.email, f.nome, e.nome, e.nif
    from acessos_temporarios t join funcionarios f on f.id = t.user_id join empresas e on e.id = t.empresa_id where t.empresa_id = p_empresa;
end $$;

-- Ler o acesso temporário de uma conta (a Edge Function verifica-o antes de mudar a palavra-passe pessoal).
create or replace function public.servico_acesso_temporario(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('empresa_id', t.empresa_id, 'expirado', t.expira_em < now()) from acessos_temporarios t where t.user_id = p_user
$$;

-- Concluir o primeiro acesso: nova palavra-passe da empresa e fim do acesso temporário.
create or replace function public.servico_concluir_primeiro_acesso(p_user uuid, p_senha_empresa text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare t acessos_temporarios;
begin
  select * into t from acessos_temporarios where user_id = p_user for update;
  if not found then raise exception 'Não há nenhum primeiro acesso pendente.'; end if;
  if t.expira_em < now() then raise exception 'O código temporário expirou. Peça um novo à Elolog.'; end if;
  if length(coalesce(p_senha_empresa, '')) < 8 then raise exception 'A palavra-passe da empresa é demasiado curta (mínimo 8 caracteres).'; end if;
  update empresa_segredos set segredo_hash = extensions.crypt(p_senha_empresa, extensions.gen_salt('bf')) where empresa_id = t.empresa_id;
  delete from acessos_temporarios where user_id = p_user;
  insert into notificacoes (empresa_id, tipo, titulo, corpo) values (t.empresa_id, 'seguranca', 'Primeiro acesso concluído', 'As palavras-passe temporárias foram substituídas pelo administrador da empresa.');
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id) values (t.empresa_id, p_user, 'admin_empresa', 'concluir_primeiro_acesso', 'empresas', t.empresa_id::text);
  return t.empresa_id;
end $$;

-- Equipa Elolog: primeiros acessos ainda por concluir (para reenviar o código).
create or replace function public.acessos_temporarios_pendentes()
returns table (empresa_id uuid, empresa text, nif text, admin_email text, expira_em timestamptz, expirado boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  return query select e.id, coalesce(e.nome_comercial, e.nome), e.nif, f.email, t.expira_em, t.expira_em < now()
    from acessos_temporarios t join empresas e on e.id = t.empresa_id join funcionarios f on f.id = t.user_id order by t.created_at desc;
end $$;

revoke all on function public.primeiro_acesso(), public.servico_criar_prestador_admin(uuid, uuid, jsonb, text, text, text, boolean, text, timestamptz),
  public.servico_renovar_acesso_temporario(uuid, uuid, text, timestamptz), public.servico_acesso_temporario(uuid),
  public.servico_concluir_primeiro_acesso(uuid, text), public.acessos_temporarios_pendentes() from public, anon, authenticated;
grant execute on function public.primeiro_acesso(), public.acessos_temporarios_pendentes() to authenticated;
grant execute on function public.servico_criar_prestador_admin(uuid, uuid, jsonb, text, text, text, boolean, text, timestamptz),
  public.servico_renovar_acesso_temporario(uuid, uuid, text, timestamptz), public.servico_acesso_temporario(uuid),
  public.servico_concluir_primeiro_acesso(uuid, text) to service_role;

-- v80 — Login simples para funcionários do prestador: NIF da empresa + n.º de funcionário + palavra-passe pessoal.
-- A palavra-passe da EMPRESA só é pedida ao administrador da empresa (acesso ao portal de administração da empresa).
-- O n.º de funcionário passa a ser dado automaticamente (0001, 0002, …) e é único dentro de cada empresa.

-- Número automático: contador por empresa em «contadores», formato 0001 (salta números já usados à mão).
create or replace function private.funcionario_numero_auto() returns trigger
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  new.numero_interno := nullif(upper(trim(coalesce(new.numero_interno, ''))), '');
  if new.numero_interno is null then
    loop
      insert into contadores (prefixo, ano, valor) values ('FUNC_' || new.empresa_id::text, 0, 1)
      on conflict (prefixo, ano) do update set valor = contadores.valor + 1 returning valor into v;
      new.numero_interno := lpad(v::text, 4, '0');
      exit when not exists (select 1 from funcionarios f where f.empresa_id = new.empresa_id and f.id <> new.id
        and ltrim(upper(f.numero_interno), '0') = ltrim(new.numero_interno, '0'));
    end loop;
  end if;
  return new;
end $$;
create or replace trigger funcionarios_numero_auto before insert or update of numero_interno on funcionarios
  for each row execute function private.funcionario_numero_auto();

-- Dar número a quem ainda não tem (por ordem de criação).
do $$ declare r record; begin
  for r in select id from funcionarios where coalesce(trim(numero_interno), '') = '' order by created_at loop
    update funcionarios set numero_interno = null where id = r.id;
  end loop;
end $$;
create unique index if not exists funcionarios_numero_unico on funcionarios (empresa_id, (ltrim(upper(numero_interno), '0')));

-- Só para a Edge Function «entrar-funcionario»: encontrar a conta pelo NIF da empresa e pelo n.º de funcionário.
create or replace function public.servico_funcionario_por_numero(p_nif text, p_numero text)
returns table (user_id uuid, email text, nome text, papel papel_funcionario, ativo boolean, empresa_id uuid, empresa_nome text, empresa_aprovada boolean)
language sql stable security definer set search_path = public as $$
  select f.id, f.email, f.nome, f.papel, f.ativo, e.id, coalesce(e.nome_comercial, e.nome), e.estado = 'aprovada'
  from funcionarios f join empresas e on e.id = f.empresa_id
  where private.norm(e.nif) = private.norm(regexp_replace(coalesce(p_nif, ''), '\s', '', 'g'))
    and ltrim(upper(f.numero_interno), '0') = ltrim(upper(trim(coalesce(p_numero, ''))), '0')
    and trim(coalesce(p_numero, '')) <> ''
  limit 1
$$;

-- Abrir a sessão da empresa para um funcionário que já provou a palavra-passe pessoal (nunca para o administrador).
create or replace function public.servico_abrir_sessao_funcionario(p_user uuid) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare f funcionarios; v_validade timestamptz := now() + interval '12 hours';
begin
  select * into f from funcionarios where id = p_user and ativo;
  if not found then raise exception 'Conta de funcionário inativa.'; end if;
  if f.papel = 'admin_empresa' then raise exception 'O administrador da empresa entra com a palavra-passe da empresa.'; end if;
  if not exists (select 1 from empresas where id = f.empresa_id and estado = 'aprovada') then raise exception 'A empresa ainda não está aprovada.'; end if;
  insert into sessoes_empresa (user_id, empresa_id, valida_ate) values (p_user, f.empresa_id, v_validade)
  on conflict (user_id) do update set empresa_id = excluded.empresa_id, valida_ate = excluded.valida_ate;
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id)
    values (f.empresa_id, p_user, f.papel::text, 'abrir_sessao_funcionario', 'funcionarios', p_user::text);
  return v_validade;
end $$;

revoke all on function public.servico_funcionario_por_numero(text, text), public.servico_abrir_sessao_funcionario(uuid) from public, anon, authenticated;
grant execute on function public.servico_funcionario_por_numero(text, text), public.servico_abrir_sessao_funcionario(uuid) to service_role;

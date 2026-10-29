-- v74 — Espaço de ficheiros garantido por plano: mede o que cada empresa (e cada cliente) guarda e trava novos envios no limite.
-- Limite da empresa: valor acordado (Empresarial) → armazenamento_gb do plano da subscrição → 50 GB se o plano for personalizado → 2 GB.
-- Clientes: 1 GB cada. Avisos à empresa aos 80 % e aos 100 % (e à equipa Elolog aos 100 %).

alter table empresas add column if not exists armazenamento_gb_acordado numeric(8,2) check (armazenamento_gb_acordado is null or armazenamento_gb_acordado > 0);

-- Bytes guardados numa pasta do bucket «documentos» (<empresa_id>/… ou <cliente_id>/…).
create or replace function private.espaco_usado(p_pasta text) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(sum(coalesce((o.metadata->>'size')::bigint, 0)), 0)::bigint
  from storage.objects o where o.bucket_id = 'documentos' and o.name like p_pasta || '/%'
$$;

create or replace function private.espaco_limite_empresa(p_empresa uuid) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare v_gb numeric; v_pers boolean;
begin
  select e.armazenamento_gb_acordado into v_gb from empresas e where e.id = p_empresa;
  if v_gb is null then
    select p.armazenamento_gb, p.personalizado into v_gb, v_pers from subscricoes s join planos p on p.id = s.plano_id
    where s.empresa_id = p_empresa order by (s.estado = 'ativa') desc, s.created_at desc limit 1;
    v_gb := coalesce(v_gb, case when v_pers then 50 else 2 end);
  end if;
  return (v_gb * 1073741824)::bigint;
end $$;

-- Ainda há espaço para mais um ficheiro nesta pasta? (usado pela política de envio)
create or replace function private.espaco_disponivel(p_pasta text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when p_pasta = private.minha_empresa()::text then private.espaco_usado(p_pasta) < private.espaco_limite_empresa(private.minha_empresa())
    when p_pasta = auth.uid()::text then private.espaco_usado(p_pasta) < 1073741824
    else true end
$$;

do $$ begin
  create policy storage_documentos_espaco on storage.objects as restrictive for insert to authenticated
    with check (bucket_id <> 'documentos' or private.espaco_disponivel((storage.foldername(name))[1]));
exception when duplicate_object then null; end $$;

-- O meu espaço (empresa do funcionário ou o próprio cliente). Cria os avisos de 80 % / 100 % uma vez por mês.
create or replace function public.espaco_ficheiros() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_emp uuid := private.minha_empresa(); v_usado bigint; v_lim bigint; v_pct int; v_tit text;
begin
  if auth.uid() is null then raise exception 'Sessão inválida.'; end if;
  if v_emp is not null then v_usado := private.espaco_usado(v_emp::text); v_lim := private.espaco_limite_empresa(v_emp);
  else v_usado := private.espaco_usado(auth.uid()::text); v_lim := 1073741824; end if;
  v_pct := floor(100.0 * v_usado / greatest(v_lim, 1));
  if v_emp is not null and v_pct >= 80 then
    v_tit := case when v_pct >= 100 then 'Espaço de ficheiros esgotado' else 'Espaço de ficheiros quase cheio' end;
    if not exists (select 1 from notificacoes where empresa_id = v_emp and tipo = 'espaco' and titulo = v_tit and created_at > now() - interval '30 days') then
      insert into notificacoes (empresa_id, tipo, titulo, corpo) values (v_emp, 'espaco', v_tit,
        format('A empresa usa %s%% do espaço de ficheiros do plano. %s', v_pct,
          case when v_pct >= 100 then 'Novos documentos ficam bloqueados até libertar espaço ou mudar de plano.' else 'Considere mudar de plano antes de chegar ao limite.' end));
      if v_pct >= 100 then insert into notificacoes (para_plataforma, tipo, titulo, corpo, referencia_tabela, referencia_id)
        values (true, 'espaco', 'Empresa sem espaço de ficheiros', (select coalesce(nome_comercial, nome) from empresas where id = v_emp) || ' chegou ao limite do plano.', 'empresas', v_emp); end if;
    end if;
  end if;
  return jsonb_build_object('tipo', case when v_emp is null then 'cliente' else 'empresa' end, 'usado', v_usado, 'limite', v_lim, 'percentagem', v_pct);
end $$;

-- Equipa Elolog: espaço de todas as empresas, e definir o valor acordado de um contrato personalizado.
create or replace function public.espaco_empresas()
returns table (empresa_id uuid, nome text, plano text, usado bigint, limite bigint, acordado_gb numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  return query select e.id, coalesce(e.nome_comercial, e.nome),
    (select p.nome from subscricoes s join planos p on p.id = s.plano_id where s.empresa_id = e.id order by (s.estado = 'ativa') desc, s.created_at desc limit 1),
    private.espaco_usado(e.id::text), private.espaco_limite_empresa(e.id), e.armazenamento_gb_acordado
  from empresas e where e.estado = 'aprovada' order by 4 desc, 2;
end $$;

create or replace function public.espaco_definir_acordado(p_empresa uuid, p_gb numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  if p_gb is not null and (p_gb <= 0 or p_gb > 10000) then raise exception 'Indique um valor entre 0,1 e 10 000 GB.'; end if;
  update empresas set armazenamento_gb_acordado = p_gb where id = p_empresa;
end $$;

revoke all on function private.espaco_usado(text), private.espaco_limite_empresa(uuid), public.espaco_ficheiros(), public.espaco_empresas(),
  public.espaco_definir_acordado(uuid, numeric) from public, anon;
grant execute on function private.espaco_disponivel(text) to authenticated;
grant execute on function public.espaco_ficheiros(), public.espaco_empresas(), public.espaco_definir_acordado(uuid, numeric) to authenticated;

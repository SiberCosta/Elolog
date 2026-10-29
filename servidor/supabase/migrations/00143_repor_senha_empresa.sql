-- v74 — Recuperar a palavra-passe da EMPRESA (1.º passo do login do prestador).
-- Só para a Edge Function «recuperar-acesso» (chave de serviço). O código é enviado para o email oficial da empresa.

-- Empresa por nome + NIF (como no login) ou por id. Devolve o email oficial e uma «impressão» do segredo atual
-- (para o código deixar de valer depois de a palavra-passe mudar). Nada disto chega ao navegador.
create or replace function public.servico_empresa_reposicao(p_nome text, p_nif text, p_id uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', e.id, 'nome', coalesce(e.nome_comercial, e.nome), 'email', e.email, 'estado', e.estado,
    'impressao', md5(coalesce(s.segredo_hash, '') || e.id::text))
  from empresas e left join empresa_segredos s on s.empresa_id = e.id
  where (p_id is not null and e.id = p_id)
     or (p_id is null and private.norm(e.nif) = private.norm(p_nif) and private.norm(e.nome) = private.norm(p_nome))
  limit 1
$$;

create or replace function public.servico_empresa_definir_senha(p_id uuid, p_senha text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if length(coalesce(p_senha, '')) < 8 then raise exception 'A palavra-passe da empresa é demasiado curta (mínimo 8 caracteres).'; end if;
  insert into empresa_segredos (empresa_id, segredo_hash) values (p_id, extensions.crypt(p_senha, extensions.gen_salt('bf')))
  on conflict (empresa_id) do update set segredo_hash = excluded.segredo_hash;
  delete from tentativas_gate where chave = p_id::text;
  insert into notificacoes (empresa_id, tipo, titulo, corpo)
  values (p_id, 'seguranca', 'Palavra-passe da empresa alterada', 'A palavra-passe de acesso da empresa foi reposta através do email oficial.');
end $$;

revoke all on function public.servico_empresa_reposicao(text, text, uuid), public.servico_empresa_definir_senha(uuid, text) from public, anon, authenticated;
grant execute on function public.servico_empresa_reposicao(text, text, uuid), public.servico_empresa_definir_senha(uuid, text) to service_role;

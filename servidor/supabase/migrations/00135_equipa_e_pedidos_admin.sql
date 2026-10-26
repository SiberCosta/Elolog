-- v61 — Equipa da plataforma (funcionários Elolog que gerem o portal) e pedidos registados pela administração
-- em nome de clientes que contactam a Elolog (telefone, email, balcão), com escolha do prestador.

-- 1. Equipa da plataforma ------------------------------------------------------------------------------------
alter table administradores_plataforma
  add column if not exists email text,
  add column if not exists papel text not null default 'admin',
  add column if not exists ativo boolean not null default true,
  add column if not exists criado_por uuid;
do $$ begin
  alter table administradores_plataforma add constraint administradores_plataforma_papel_chk check (papel in ('admin','operador','apoio'));
exception when duplicate_object then null; end $$;
update administradores_plataforma a set email = u.email from auth.users u where u.id = a.user_id and a.email is null;

create or replace function private.e_admin_plataforma() returns boolean language sql stable security definer set search_path to 'public' as $$
  select private.mfa_ok() and exists (select 1 from administradores_plataforma where user_id = auth.uid() and ativo)
$$;

-- Lista da equipa (qualquer membro ativo pode ver).
create or replace function public.equipa_plataforma()
returns table (user_id uuid, nome text, email text, papel text, ativo boolean, created_at timestamptz, sou_eu boolean)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  return query select a.user_id, a.nome, a.email, a.papel, a.ativo, a.created_at, a.user_id = auth.uid()
                 from administradores_plataforma a order by a.ativo desc, a.nome;
end $$;
revoke execute on function public.equipa_plataforma() from public, anon;
grant execute on function public.equipa_plataforma() to authenticated;

-- Funções só para a Edge Function «gerir-equipa» (chave de serviço).
create or replace function public.servico_equipa_pode_gerir(p_user uuid) returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from administradores_plataforma where user_id = p_user and ativo and papel = 'admin')
$$;
create or replace function public.servico_equipa_criar(p_user uuid, p_nome text, p_email text, p_papel text, p_autor uuid)
returns administradores_plataforma language plpgsql security definer set search_path to 'public' as $$
declare r administradores_plataforma;
begin
  if not public.servico_equipa_pode_gerir(p_autor) then raise exception 'Só um administrador da plataforma pode criar funcionários.'; end if;
  if p_papel not in ('admin','operador','apoio') then raise exception 'Função inválida.'; end if;
  insert into administradores_plataforma (user_id, nome, email, papel, ativo, criado_por)
    values (p_user, left(trim(p_nome), 120), lower(trim(p_email)), p_papel, true, p_autor) returning * into r;
  insert into auditoria (user_id, papel, acao, entidade, entidade_id, depois)
    values (p_autor, 'admin_plataforma', 'criar_funcionario_plataforma', 'administradores_plataforma', p_user::text, jsonb_build_object('papel', p_papel, 'email', r.email));
  return r;
end $$;
create or replace function public.servico_equipa_alterar(p_alvo uuid, p_ativo boolean, p_papel text, p_autor uuid)
returns administradores_plataforma language plpgsql security definer set search_path to 'public' as $$
declare r administradores_plataforma;
begin
  if not public.servico_equipa_pode_gerir(p_autor) then raise exception 'Só um administrador da plataforma pode alterar a equipa.'; end if;
  if p_alvo = p_autor then raise exception 'Não pode alterar o seu próprio acesso.'; end if;
  if p_papel is not null and p_papel not in ('admin','operador','apoio') then raise exception 'Função inválida.'; end if;
  update administradores_plataforma set ativo = coalesce(p_ativo, ativo), papel = coalesce(p_papel, papel) where user_id = p_alvo returning * into r;
  if not found then raise exception 'Funcionário inexistente.'; end if;
  if not exists (select 1 from administradores_plataforma where ativo and papel = 'admin') then raise exception 'Tem de existir pelo menos um administrador ativo.'; end if;
  insert into auditoria (user_id, papel, acao, entidade, entidade_id, depois)
    values (p_autor, 'admin_plataforma', 'alterar_funcionario_plataforma', 'administradores_plataforma', p_alvo::text, jsonb_build_object('ativo', r.ativo, 'papel', r.papel));
  return r;
end $$;
revoke execute on function public.servico_equipa_pode_gerir(uuid), public.servico_equipa_criar(uuid,text,text,text,uuid), public.servico_equipa_alterar(uuid,boolean,text,uuid) from public, anon, authenticated;
grant execute on function public.servico_equipa_pode_gerir(uuid), public.servico_equipa_criar(uuid,text,text,text,uuid), public.servico_equipa_alterar(uuid,boolean,text,uuid) to service_role;

-- 2. Pedidos registados pela administração --------------------------------------------------------------------
alter table simulacoes alter column cliente_id drop not null;
alter table simulacoes add column if not exists registado_por uuid, add column if not exists canal text not null default 'cliente';
do $$ begin
  alter table simulacoes add constraint simulacoes_canal_chk check (canal in ('cliente','telefone','email','balcao','outro'));
exception when duplicate_object then null; end $$;

-- Clientes registados (para escolher no formulário).
create or replace function public.clientes_administracao(p_texto text default null)
returns table (id uuid, nome text, email text, telefone text, nif text, morada text)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  return query select c.id, c.nome, c.email, c.telefone, c.nif, c.morada from clientes c
    where p_texto is null or c.nome ilike '%' || p_texto || '%' or c.email ilike '%' || p_texto || '%' or c.telefone ilike '%' || p_texto || '%'
    order by c.nome limit 20;
end $$;
revoke execute on function public.clientes_administracao(text) from public, anon;
grant execute on function public.clientes_administracao(text) to authenticated;

-- Regista o pedido e envia-o ao prestador escolhido. O preço vem da tarifa do prestador ou do valor
-- combinado com o cliente (p_preco). Sem nenhum dos dois, segue como pedido de cotação.
create or replace function public.admin_registar_pedido(p_dados jsonb, p_empresa uuid, p_preco numeric default null)
returns simulacoes language plpgsql security definer set search_path to 'public' as $$
declare v_sim simulacoes; v_t tarifas; v_preco numeric; v_cli uuid; v_rem jsonb;
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  if coalesce(trim(p_dados->>'origem'),'') = '' or coalesce(trim(p_dados->>'destino'),'') = '' then raise exception 'Indique a origem e o destino.'; end if;
  if not exists (select 1 from empresas_disponiveis e where e.id = p_empresa) then raise exception 'Este prestador não está disponível.'; end if;
  if p_preco is not null and (p_preco <= 0 or p_preco > 10000000) then raise exception 'Preço inválido.'; end if;
  v_cli := nullif(p_dados->>'cliente_id','')::uuid;
  if v_cli is not null and not exists (select 1 from clientes where id = v_cli) then raise exception 'Cliente inexistente.'; end if;
  v_rem := coalesce(p_dados->'remetente', '{}'::jsonb);
  if v_cli is null and coalesce(trim(v_rem->>'nome'),'') = '' then raise exception 'Indique o cliente (nome e contacto).'; end if;
  if v_cli is null and coalesce(trim(v_rem->>'telefone'),'') = '' and coalesce(trim(v_rem->>'email'),'') = '' then raise exception 'Indique o telefone ou o email do cliente.'; end if;

  insert into simulacoes (cliente_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes, recolha_na_morada,
                          recolha_distancia_km, data_prevista, morada_recolha, remetente, destinatario, valor_declarado, observacoes, registado_por, canal)
  values (v_cli, left(trim(p_dados->>'origem'),120), left(trim(p_dados->>'destino'),120), nullif(p_dados->>'tipo_carga',''), left(p_dados->>'descricao',500),
          coalesce((p_dados->>'quantidade')::int, 1), coalesce((p_dados->>'peso_kg')::numeric, 0), coalesce((p_dados->>'volume_m3')::numeric, 0),
          coalesce(p_dados->'volumes', '[]'::jsonb), coalesce((p_dados->>'recolha')::boolean, false), nullif(p_dados->>'km','')::numeric,
          nullif(p_dados->>'data_prevista','')::date, nullif(p_dados->>'morada_recolha',''), v_rem, coalesce(p_dados->'destinatario','{}'::jsonb),
          nullif(p_dados->>'valor_declarado','')::numeric, left(p_dados->>'observacoes',1000), auth.uid(), coalesce(nullif(p_dados->>'canal',''),'telefone'))
  returning * into v_sim;

  v_t := private.tarifa_aplicavel(p_empresa, v_sim.origem, v_sim.destino, v_sim.tipo_carga);
  if v_t.id is not null then
    v_preco := private.preco_com_tarifa(v_t, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3)
               + case when v_sim.recolha_na_morada then round(coalesce(v_sim.recolha_distancia_km, 0) * private.custo_recolha_por_km(), 2) else 0 end;
  end if;
  v_preco := coalesce(round(p_preco, 2), v_preco);

  update simulacoes set estado = 'enviada', empresa_destinatario_id = p_empresa, enviada_em = now(), preco_estimado = v_preco,
         moeda_estimada = coalesce(v_t.moeda, 'EUR'), tarifa_estimada_id = v_t.id where id = v_sim.id returning * into v_sim;
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (p_empresa, 'nova_simulacao', case when v_preco is null then 'Novo pedido de cotação (Elolog)' else 'Novo pedido registado pela Elolog' end,
            v_sim.origem || ' → ' || v_sim.destino || coalesce(' · ' || (v_rem->>'nome'), ''), 'simulacoes', v_sim.id);
  if v_cli is not null then
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (v_cli, 'pedido_registado', 'A Elolog registou o seu pedido', v_sim.codigo || ' · ' || v_sim.origem || ' → ' || v_sim.destino, 'simulacoes', v_sim.id);
  end if;
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (p_empresa, auth.uid(), 'admin_plataforma', 'admin_registar_pedido', 'simulacoes', v_sim.id::text,
            jsonb_build_object('preco', v_preco, 'preco_combinado', p_preco is not null, 'canal', v_sim.canal, 'cliente', v_cli));
  return v_sim;
end $$;
revoke execute on function public.admin_registar_pedido(jsonb, uuid, numeric) from public, anon;
grant execute on function public.admin_registar_pedido(jsonb, uuid, numeric) to authenticated;

-- 3. Aceitar um pedido sem cliente registado avisa a administração (que contacta o cliente).
create or replace function public.aceitar_simulacao(p_simulacao uuid, p_preco numeric default null)
returns encomendas language plpgsql security definer set search_path to 'public' as $$
declare v_sim simulacoes; v_enc encomendas; v_prop uuid; v_preco numeric;
begin
  if private.minha_empresa() is null or not private.papel_em(array['admin_empresa','operador']) then
    raise exception 'Sem permissão para aceitar simulações.'; end if;
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.empresa_destinatario_id is distinct from private.minha_empresa() then raise exception 'Simulação inexistente.'; end if;
  if v_sim.estado not in ('enviada', 'respondida') then raise exception 'A simulação já não está disponível (%).', v_sim.estado; end if;
  v_preco := coalesce(p_preco, v_sim.preco_estimado);
  if v_preco is null or v_preco <= 0 then raise exception 'Indique o preço para este pedido de cotação.'; end if;
  if v_preco > 10000000 then raise exception 'Preço inválido.'; end if;
  v_preco := round(v_preco, 2);

  update propostas set estado = 'cancelada', respondida_em = now()
   where simulacao_id = v_sim.id and empresa_id = v_sim.empresa_destinatario_id and estado = 'enviada';
  insert into propostas (simulacao_id, empresa_id, tarifa_id, preco, moeda, estado, mensagem, criado_por, respondida_em)
  values (v_sim.id, v_sim.empresa_destinatario_id, v_sim.tarifa_estimada_id, v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), 'aceite',
          case when p_preco is not null and v_sim.preco_estimado is distinct from v_preco then 'Aceite com preço indicado pelo prestador.'
               else 'Aceite ao preço calculado pelas tarifas do prestador.' end, auth.uid(), now())
  returning id into v_prop;
  update simulacoes set estado = 'convertida', preco_estimado = v_preco where id = v_sim.id;

  insert into encomendas (empresa_id, cliente_id, simulacao_id, proposta_id, origem, destino, tipo_carga, descricao,
                          quantidade, peso_kg, volume_m3, volumes, preco_total, moeda, estado, data_prevista,
                          morada_recolha, remetente, destinatario, valor_declarado, observacoes, criado_por)
  values (v_sim.empresa_destinatario_id, v_sim.cliente_id, v_sim.id, v_prop, v_sim.origem, v_sim.destino,
          v_sim.tipo_carga, v_sim.descricao, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3, v_sim.volumes,
          v_preco, coalesce(v_sim.moeda_estimada, 'EUR'), 'aprovacao', v_sim.data_prevista,
          v_sim.morada_recolha, v_sim.remetente, v_sim.destinatario, v_sim.valor_declarado, v_sim.observacoes, auth.uid())
  returning * into v_enc;

  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id)
    values (v_enc.id, v_enc.empresa_id, null, 'aprovacao', 'Simulação aceite pelo prestador', auth.uid());
  insert into notificacoes (user_id, para_plataforma, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v_sim.cliente_id, v_sim.cliente_id is null, 'simulacao_aceite',
            case when v_sim.cliente_id is null then 'Prestador aceitou um pedido registado pela Elolog' else 'O prestador aceitou o seu pedido' end,
            'Encomenda ' || v_enc.codigo || ' criada' || case when v_sim.cliente_id is null then '. Informe o cliente: ' || coalesce(v_sim.remetente->>'nome','') || ' ' || coalesce(v_sim.remetente->>'telefone','') else ' e a aguardar aprovação operacional.' end,
            'encomendas', v_enc.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_enc.empresa_id, auth.uid(), private.meu_papel()::text, 'aceitar_simulacao', 'simulacoes', v_sim.id::text,
            jsonb_build_object('encomenda', v_enc.codigo, 'preco', v_preco));
  return v_enc;
end $$;
revoke execute on function public.aceitar_simulacao(uuid, numeric) from public, anon;
grant execute on function public.aceitar_simulacao(uuid, numeric) to authenticated;


-- 4. Lista de simulações da administração: inclui o canal e o nome de contacto quando não há conta de cliente.
drop function if exists public.simulacoes_administracao(int);
create function public.simulacoes_administracao(p_limite int default 50)
returns table (id uuid, codigo text, estado text, origem text, destino text, tipo_carga text, volume_m3 numeric, peso_kg numeric,
               preco_estimado numeric, cliente text, cliente_email text, prestador text, canal text, created_at timestamptz, enviada_em timestamptz)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  return query
    select s.id, s.codigo::text, s.estado::text, s.origem, s.destino, s.tipo_carga, s.volume_m3, s.peso_kg, s.preco_estimado,
           coalesce(c.nome, s.remetente->>'nome')::text, coalesce(c.email, s.remetente->>'email')::text, e.nome::text, s.canal, s.created_at, s.enviada_em
      from simulacoes s left join clientes c on c.id = s.cliente_id left join empresas e on e.id = s.empresa_destinatario_id
     order by s.created_at desc limit least(greatest(coalesce(p_limite, 50), 1), 200);
end $$;
revoke execute on function public.simulacoes_administracao(int) from public, anon;
grant execute on function public.simulacoes_administracao(int) to authenticated;

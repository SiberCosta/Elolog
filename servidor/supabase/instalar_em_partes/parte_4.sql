-- Elolog — instalação, parte 4 de 4 (00134_pedido_cotacao.sql a 00135_equipa_e_pedidos_admin.sql). Correr pela ordem: 1, 2, 3, 4.
begin;
-- ===== 00134_pedido_cotacao.sql =====
-- v60 — Pedido de cotação: o cliente pode enviar a simulação a um prestador que ainda não tem tarifa para a rota.
-- O prestador responde com um preço manual ao aceitar. A administração vê todas as simulações (rascunhos incluídos).

create or replace function public.enviar_simulacao(p_simulacao uuid, p_empresa uuid)
returns simulacoes language plpgsql security definer set search_path to 'public' as $$
declare v_sim simulacoes; v_t tarifas; v_preco numeric;
begin
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.cliente_id is distinct from auth.uid() then raise exception 'Simulação inexistente.'; end if;
  if v_sim.estado <> 'rascunho' then raise exception 'A simulação já foi enviada (%).', v_sim.estado; end if;
  if not exists (select 1 from empresas_disponiveis e where e.id = p_empresa) then raise exception 'Este prestador não está disponível.'; end if;

  v_t := private.tarifa_aplicavel(p_empresa, v_sim.origem, v_sim.destino, v_sim.tipo_carga);
  if v_t.id is not null then
    v_preco := private.preco_com_tarifa(v_t, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3)
               + case when v_sim.recolha_na_morada then round(coalesce(v_sim.recolha_distancia_km, 0) * private.custo_recolha_por_km(), 2) else 0 end;
  end if;

  update simulacoes set estado = 'enviada', empresa_destinatario_id = p_empresa, enviada_em = now(),
         preco_estimado = v_preco, moeda_estimada = coalesce(v_t.moeda, 'EUR'), tarifa_estimada_id = v_t.id
   where id = v_sim.id returning * into v_sim;

  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (p_empresa, 'nova_simulacao',
            case when v_preco is null then 'Novo pedido de cotação' else 'Nova simulação recebida' end,
            case when v_preco is null then v_sim.origem || ' → ' || v_sim.destino || ': sem tarifa para esta rota. Indique o preço ao aceitar.' end,
            'simulacoes', v_sim.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (p_empresa, auth.uid(), 'cliente', 'enviar_simulacao', 'simulacoes', v_sim.id::text,
            jsonb_build_object('preco_estimado', v_preco, 'tarifa', v_t.id, 'pedido_cotacao', v_preco is null));
  return v_sim;
end $$;

-- Aceitar com preço manual (obrigatório quando não houve tarifa).
drop function if exists public.aceitar_simulacao(uuid);
create function public.aceitar_simulacao(p_simulacao uuid, p_preco numeric default null)
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
  insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (v_sim.cliente_id, 'simulacao_aceite', 'O prestador aceitou o seu pedido',
            'Encomenda ' || v_enc.codigo || ' criada e a aguardar aprovação operacional.', 'encomendas', v_enc.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (v_enc.empresa_id, auth.uid(), private.meu_papel()::text, 'aceitar_simulacao', 'simulacoes', v_sim.id::text,
            jsonb_build_object('encomenda', v_enc.codigo, 'preco', v_preco));
  return v_enc;
end $$;
revoke execute on function public.aceitar_simulacao(uuid, numeric) from public, anon;
grant execute on function public.aceitar_simulacao(uuid, numeric) to authenticated;

-- Lista de simulações para a administração da plataforma (inclui rascunhos e nome do cliente/prestador).
create or replace function public.simulacoes_administracao(p_limite int default 50)
returns table (id uuid, codigo text, estado text, origem text, destino text, tipo_carga text, volume_m3 numeric, peso_kg numeric,
               preco_estimado numeric, cliente text, cliente_email text, prestador text, created_at timestamptz, enviada_em timestamptz)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Sem permissão.'; end if;
  return query
    select s.id, s.codigo::text, s.estado::text, s.origem, s.destino, s.tipo_carga, s.volume_m3, s.peso_kg, s.preco_estimado,
           c.nome::text, c.email::text, e.nome::text, s.created_at, s.enviada_em
      from simulacoes s left join clientes c on c.id = s.cliente_id left join empresas e on e.id = s.empresa_destinatario_id
     order by s.created_at desc limit least(greatest(coalesce(p_limite, 50), 1), 200);
end $$;
revoke execute on function public.simulacoes_administracao(int) from public, anon;
grant execute on function public.simulacoes_administracao(int) to authenticated;


-- ===== 00135_equipa_e_pedidos_admin.sql =====
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


select private.agendar_tarefas('https://wcggcpdiswbzrdpwgdpb.supabase.co');

-- ===== Permissões da API (projetos Supabase novos não dão acesso automático às tabelas e funções) =====
grant select, insert, update, delete, references, trigger, truncate on all tables in schema public to anon, authenticated, service_role;
grant usage, select, update on all sequences in schema public to anon, authenticated, service_role;
grant execute on all functions in schema public to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant select, insert, update, delete, references, trigger, truncate on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant usage, select, update on sequences to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated, service_role;
grant usage on schema private to authenticated, service_role;
do $p$ begin execute $s$grant execute on function private.proximo_codigo(text) to authenticated, service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.transitar_encomenda(uuid, estado_encomenda, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.aceitar_proposta(uuid) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.decidir_empresa(uuid, boolean, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.transitar_encomenda(uuid, estado_encomenda, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.aceitar_proposta(uuid) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.decidir_empresa(uuid, boolean, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function private.e_admin_plataforma(), private.minha_empresa(), private.meu_papel(), private.papel_em(text[]), private.tem_permissao(text), private.cliente_visivel(uuid), private.ve_ticket(uuid) to authenticated, service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on all tables in schema public from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on all sequences in schema public from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke insert, update, delete on auditoria, encomenda_historico, encomenda_transicoes from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke update on empresas from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant update (nome_comercial, telefone, morada, codigo_postal, cidade) on empresas to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke update on funcionarios from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant update (nome, papel, ativo, numero_interno, veiculo_habitual, permissoes) on funcionarios to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke update on encomendas from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant update (cliente_nome, cliente_nif, cliente_telefone, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes, preco_total, data_prevista, assinatura_documento_id, pin_validacao_hash) on encomendas to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke update on notificacoes from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on empresas_disponiveis from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function private.norm(text), private.custo_recolha_por_km(), private.tarifa_aplicavel(uuid, text, text, text, text), private.preco_com_tarifa(tarifas, int, numeric, numeric) from public;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke insert, update on simulacoes from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant insert (cliente_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes, recolha_na_morada, recolha_distancia_km) on simulacoes to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant update (origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3, volumes, recolha_na_morada, recolha_distancia_km) on simulacoes to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.calcular_propostas(text, text, text, int, numeric, numeric, numeric, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.enviar_simulacao(uuid, uuid) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.cancelar_simulacao(uuid) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.calcular_propostas(text, text, text, int, numeric, numeric, numeric, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.enviar_simulacao(uuid, uuid) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.cancelar_simulacao(uuid) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant insert (data_prevista, morada_recolha, remetente, destinatario, valor_declarado, observacoes) on simulacoes to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant update (data_prevista, morada_recolha, remetente, destinatario, valor_declarado, observacoes) on simulacoes to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant update (morada_recolha, destinatario, valor_declarado, observacoes) on encomendas to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function private.verificar_empresa(text, text, text) from public;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.validar_empresa(text, text, text) to anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.abrir_sessao_empresa(text, text, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.abrir_sessao_empresa(text, text, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.terminar_sessao_empresa() from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.terminar_sessao_empresa() to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.sessao_empresa_ativa() to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.aceitar_simulacao(uuid), public.recusar_simulacao(uuid, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.aceitar_simulacao(uuid), public.recusar_simulacao(uuid, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.transitar_encomenda(uuid, estado_encomenda, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.transitar_encomenda(uuid, estado_encomenda, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke update on funcionarios from authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.servico_limite(text, int, int), public.servico_utilizador_existe(text), public.servico_registar_prestador(uuid, text, text, text, text, text, text, text, text, text, text), public.servico_admin_empresa(uuid), public.servico_verificar_limite_funcionarios(uuid), public.servico_criar_funcionario(uuid, uuid, uuid, text, text, papel_funcionario, text, text, text, text, text[], boolean), public.servico_obter_funcionario(uuid, uuid), public.servico_atualizar_funcionario(uuid, uuid, uuid, jsonb), public.servico_preparar_remocao(uuid, uuid, uuid), public.servico_auditar(uuid, uuid, text, text, jsonb), public.servico_encerrar_sessoes(uuid) from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.servico_limite(text, int, int), public.servico_utilizador_existe(text), public.servico_registar_prestador(uuid, text, text, text, text, text, text, text, text, text, text), public.servico_admin_empresa(uuid), public.servico_verificar_limite_funcionarios(uuid), public.servico_criar_funcionario(uuid, uuid, uuid, text, text, papel_funcionario, text, text, text, text, text[], boolean), public.servico_obter_funcionario(uuid, uuid), public.servico_atualizar_funcionario(uuid, uuid, uuid, jsonb), public.servico_preparar_remocao(uuid, uuid, uuid), public.servico_auditar(uuid, uuid, text, text, jsonb), public.servico_encerrar_sessoes(uuid) to service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function private.permissoes_validas(text[]), private.validar_alteracao_acesso(uuid, uuid, uuid, boolean) from public;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.sou_admin_plataforma() from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.sou_admin_plataforma() to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.confirmar_pagamento_subscricao(uuid, text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.confirmar_pagamento_subscricao(uuid, text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on emails_fila from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.servico_reservar_emails(int, int), public.servico_marcar_email(uuid, text, text, text), public.servico_emails_enviados_hoje() from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.servico_reservar_emails(int, int), public.servico_marcar_email(uuid, text, text, text), public.servico_emails_enviados_hoje() to service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function private.tipo_envia_email(text), private.destinatarios_email(notificacoes), private.enfileirar_emails() from public;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on all tables in schema public from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on all sequences in schema public from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on all functions in schema public from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.validar_empresa(text, text, text) to anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$alter default privileges for role postgres in schema public revoke all on tables from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$alter default privileges for role postgres in schema public revoke all on sequences from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$alter default privileges for role postgres in schema public revoke execute on functions from anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.painel_administracao(int) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.painel_administracao(int) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on private.plataforma_config from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function private.mfa_ok() to authenticated, service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on public.empresas_disponiveis from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on public.empresa_segredos, public.sessoes_empresa, public.tentativas_gate, public.emails_fila, public.contadores from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function private.chamar_funcao(text, jsonb) from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function private.agendar_tarefas(text) from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function public.servico_segredo_cron() from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.servico_segredo_cron() to service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke insert, update, delete on faturas from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function public.registar_fatura(uuid, text, uuid) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.registar_fatura(uuid, text, uuid) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on empresa_pagamentos_config from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function public.ver_config_pagamentos(), public.guardar_config_pagamentos(text, text, text, boolean, boolean) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.ver_config_pagamentos(), public.guardar_config_pagamentos(text, text, text, boolean, boolean) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke insert, update, delete on pedidos_pagamento from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function public.servico_preparar_pedido(uuid, text, text, text), public.servico_atualizar_pedido(uuid, text, jsonb), public.servico_confirmar_pedido(text, text, numeric, text), public.servico_pedidos_mbway_pendentes() from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.servico_preparar_pedido(uuid, text, text, text), public.servico_atualizar_pedido(uuid, text, jsonb), public.servico_confirmar_pedido(text, text, numeric, text), public.servico_pedidos_mbway_pendentes() to service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke insert, update, delete on navios_posicoes from anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke all on function public.servico_navios_seguidos() from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.servico_navios_seguidos() to service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.aceitar_simulacao(uuid, numeric) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.aceitar_simulacao(uuid, numeric) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.simulacoes_administracao(int) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.simulacoes_administracao(int) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.equipa_plataforma() from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.equipa_plataforma() to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.servico_equipa_pode_gerir(uuid), public.servico_equipa_criar(uuid,text,text,text,uuid), public.servico_equipa_alterar(uuid,boolean,text,uuid) from public, anon, authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.servico_equipa_pode_gerir(uuid), public.servico_equipa_criar(uuid,text,text,text,uuid), public.servico_equipa_alterar(uuid,boolean,text,uuid) to service_role;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.clientes_administracao(text) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.clientes_administracao(text) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.admin_registar_pedido(jsonb, uuid, numeric) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.admin_registar_pedido(jsonb, uuid, numeric) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.aceitar_simulacao(uuid, numeric) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.aceitar_simulacao(uuid, numeric) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$revoke execute on function public.simulacoes_administracao(int) from public, anon;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;
do $p$ begin execute $s$grant execute on function public.simulacoes_administracao(int) to authenticated;$s$; exception when undefined_function or undefined_table or undefined_object or invalid_schema_name then null; end $p$;

-- ===== 00136_whatsapp.sql =====
-- v66 — Assistente ELO no WhatsApp (WhatsApp Business Cloud API da Meta).
-- A Edge Function «whatsapp-elo» recebe as mensagens e responde; estas funções só correm com a chave de serviço.

create table if not exists whatsapp_conversas (
  telefone     text primary key,                 -- número do cliente, só dígitos, com indicativo
  nome         text,
  passo        text,
  dados        jsonb not null default '{}',
  humano_desde timestamptz,
  mensagens    int not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
alter table whatsapp_conversas enable row level security;
revoke all on whatsapp_conversas from anon, authenticated;

-- Estado de uma encomenda pedido por WhatsApp: só responde se o número de quem pergunta for o do cliente,
-- o da encomenda ou o do destinatário (últimos 9 dígitos). Caso contrário não revela nada.
create or replace function public.servico_whatsapp_estado(p_codigo text, p_telefone text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e encomendas; v_tel text := right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 9); v_ok boolean;
begin
  if length(v_tel) < 9 then return jsonb_build_object('autorizado', false); end if;
  select * into e from encomendas where upper(codigo) = upper(trim(p_codigo));
  if not found then return jsonb_build_object('autorizado', false); end if;
  select v_tel in (
           right(regexp_replace(coalesce(e.cliente_telefone, ''), '\D', '', 'g'), 9),
           right(regexp_replace(coalesce(e.destinatario->>'telefone', ''), '\D', '', 'g'), 9),
           right(regexp_replace(coalesce((select c.telefone from clientes c where c.id = e.cliente_id), ''), '\D', '', 'g'), 9))
    into v_ok;
  if not coalesce(v_ok, false) then return jsonb_build_object('autorizado', false); end if;
  return jsonb_build_object('autorizado', true, 'codigo', e.codigo, 'estado', e.estado::text, 'origem', e.origem,
    'destino', e.destino, 'data_prevista', e.data_prevista, 'atualizado', e.updated_at,
    'prestador', (select coalesce(m.nome_comercial, m.nome) from empresas m where m.id = e.empresa_id));
end $$;

-- Pedido de atendimento humano: avisa a administração (notificação + email) e marca a conversa.
create or replace function public.servico_whatsapp_pedido_humano(p_telefone text, p_nome text, p_mensagem text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into notificacoes (para_plataforma, tipo, titulo, corpo)
  values (true, 'apoio', 'Pedido de contacto por WhatsApp',
          left(coalesce(nullif(trim(p_nome), ''), 'Sem nome') || ' · +' || regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g')
               || coalesce(' · «' || nullif(trim(p_mensagem), '') || '»', ''), 480));
  update whatsapp_conversas set humano_desde = now(), updated_at = now() where telefone = regexp_replace(p_telefone, '\D', '', 'g');
end $$;

revoke all on function public.servico_whatsapp_estado(text, text), public.servico_whatsapp_pedido_humano(text, text, text) from public, anon, authenticated;
grant execute on function public.servico_whatsapp_estado(text, text), public.servico_whatsapp_pedido_humano(text, text, text) to service_role;
grant select, insert, update on whatsapp_conversas to service_role;

-- ===== 00137_caixas_email.sql =====
-- v67 — Painel de email: caixas de correio (IMAP/SMTP) ligadas à plataforma.
-- Só o administrador da plataforma (caixas da Elolog, empresa_id nulo) e o administrador de cada prestador
-- (caixas da sua empresa) as podem usar. A palavra-passe da caixa fica encriptada no cofre (Vault) e só a
-- Edge Function «email-caixa» (chave de serviço) a lê. O navegador nunca a recebe.

create table if not exists caixas_email (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid references empresas(id) on delete cascade,   -- nulo = caixa da Elolog (administração)
  email       text not null check (length(email) <= 254 and email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$'),
  nome        text not null default '',
  imap_host   text not null check (imap_host ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
  imap_porta  int  not null default 993 check (imap_porta = 993),
  smtp_host   text not null check (smtp_host ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
  smtp_porta  int  not null default 465 check (smtp_porta = 465),
  utilizador  text not null check (length(utilizador) between 1 and 254),
  segredo_id  uuid,                                               -- vault.secrets.id
  criado_por  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists caixas_email_unica on caixas_email (coalesce(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(email));
alter table caixas_email enable row level security;
revoke all on caixas_email from anon, authenticated;

-- Quem pode usar as caixas de um âmbito (empresa nula = Elolog).
create or replace function private.email_pode(p_user uuid, p_empresa uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case when p_empresa is null
    then exists (select 1 from administradores_plataforma where user_id = p_user and ativo and papel = 'admin')
    else exists (select 1 from funcionarios where id = p_user and ativo and papel = 'admin_empresa' and empresa_id = p_empresa) end
$$;

-- Ao apagar a caixa (ou a empresa), apaga também a palavra-passe do cofre.
create or replace function private.email_limpar_segredo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.segredo_id is not null then delete from vault.secrets where id = old.segredo_id; end if;
  return old;
end $$;
create or replace trigger caixas_email_limpar after delete on caixas_email for each row execute function private.email_limpar_segredo();

-- Âmbitos a que o utilizador tem acesso: {"plataforma": bool, "empresa": uuid|null}.
create or replace function public.servico_email_acesso(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('plataforma', private.email_pode(p_user, null),
    'empresa', (select empresa_id from funcionarios where id = p_user and ativo and papel = 'admin_empresa'))
$$;

-- Caixas visíveis (sem a palavra-passe).
create or replace function public.servico_email_caixas(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'email', email, 'nome', nome, 'imap_host', imap_host, 'imap_porta', imap_porta,
    'smtp_host', smtp_host, 'smtp_porta', smtp_porta, 'utilizador', utilizador, 'elolog', empresa_id is null, 'tem_senha', segredo_id is not null)
    order by empresa_id nulls first, email), '[]'::jsonb)
  from caixas_email c where private.email_pode(p_user, c.empresa_id)
$$;

-- Criar ou alterar uma caixa. p_senha nula mantém a atual. A Edge Function testa a ligação antes de chamar.
create or replace function public.servico_email_gravar(p_user uuid, p_id uuid, p_dados jsonb, p_senha text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r caixas_email; v_emp uuid; v_seg uuid;
begin
  if p_id is not null then
    select * into r from caixas_email where id = p_id;
    if not found or not private.email_pode(p_user, r.empresa_id) then raise exception 'Caixa de email inexistente.'; end if;
    v_emp := r.empresa_id;
  else
    if private.email_pode(p_user, null) and coalesce(p_dados->>'ambito', 'elolog') = 'elolog' then v_emp := null;
    else select empresa_id into v_emp from funcionarios where id = p_user and ativo and papel = 'admin_empresa';
      if v_emp is null then raise exception 'Sem permissão para configurar caixas de email.'; end if; end if;
    if (select count(*) from caixas_email where empresa_id is not distinct from v_emp) >= 5 then raise exception 'Máximo de 5 caixas de email.'; end if;
    if p_senha is null then raise exception 'Indique a palavra-passe da caixa.'; end if;
  end if;
  insert into caixas_email as c (id, empresa_id, email, nome, imap_host, imap_porta, smtp_host, smtp_porta, utilizador, criado_por)
  values (coalesce(p_id, gen_random_uuid()), v_emp, lower(trim(p_dados->>'email')), left(coalesce(trim(p_dados->>'nome'), ''), 80),
          lower(trim(p_dados->>'imap_host')), 993, lower(trim(p_dados->>'smtp_host')), 465, trim(p_dados->>'utilizador'), p_user)
  on conflict (id) do update set email = excluded.email, nome = excluded.nome, imap_host = excluded.imap_host,
    smtp_host = excluded.smtp_host, utilizador = excluded.utilizador, updated_at = now()
  returning * into r;
  if p_senha is not null then
    if r.segredo_id is null then
      v_seg := vault.create_secret(p_senha, 'email_caixa_' || r.id::text, 'Palavra-passe da caixa ' || r.email);
      update caixas_email set segredo_id = v_seg where id = r.id;
    else perform vault.update_secret(r.segredo_id, p_senha); end if;
  end if;
  return jsonb_build_object('id', r.id, 'email', r.email);
exception when unique_violation then raise exception 'Essa caixa de email já está configurada.';
end $$;

-- Dados de ligação com a palavra-passe (só para a Edge Function).
create or replace function public.servico_email_credenciais(p_user uuid, p_caixa uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r caixas_email; v_senha text;
begin
  select * into r from caixas_email where id = p_caixa;
  if not found or not private.email_pode(p_user, r.empresa_id) then raise exception 'Caixa de email inexistente.'; end if;
  select decrypted_secret into v_senha from vault.decrypted_secrets where id = r.segredo_id;
  return jsonb_build_object('elolog', r.empresa_id is null, 'email', r.email, 'nome', r.nome, 'imap_host', r.imap_host, 'imap_porta', r.imap_porta,
    'smtp_host', r.smtp_host, 'smtp_porta', r.smtp_porta, 'utilizador', r.utilizador, 'senha', v_senha);
end $$;

create or replace function public.servico_email_remover(p_user uuid, p_caixa uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_emp uuid;
begin
  select empresa_id into v_emp from caixas_email where id = p_caixa;
  if not found or not private.email_pode(p_user, v_emp) then raise exception 'Caixa de email inexistente.'; end if;
  delete from caixas_email where id = p_caixa;
end $$;

revoke all on function private.email_pode(uuid, uuid), public.servico_email_acesso(uuid), public.servico_email_caixas(uuid),
  public.servico_email_gravar(uuid, uuid, jsonb, text), public.servico_email_credenciais(uuid, uuid), public.servico_email_remover(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.servico_email_acesso(uuid), public.servico_email_caixas(uuid), public.servico_email_gravar(uuid, uuid, jsonb, text),
  public.servico_email_credenciais(uuid, uuid), public.servico_email_remover(uuid, uuid) to service_role;
grant select, insert, update, delete on caixas_email to service_role;

-- ===== 00138_acessos_email_chat.sql =====
-- v70 — (1) Acessos às caixas de email dados pelo administrador a funcionários; (2) chat interno da equipa com hierarquia.

-- ===== 1. Acessos às caixas de email =====
create table if not exists caixas_email_acesso (
  caixa_id      uuid not null references caixas_email(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  concedido_por uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  primary key (caixa_id, user_id)
);
alter table caixas_email_acesso enable row level security;
revoke all on caixas_email_acesso from anon, authenticated;

-- Pode usar (ler, responder) a caixa: o administrador do âmbito ou um funcionário ativo desse âmbito com acesso concedido.
create or replace function private.email_usar(p_user uuid, p_caixa uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from caixas_email c where c.id = p_caixa and (private.email_pode(p_user, c.empresa_id)
    or (exists (select 1 from caixas_email_acesso a where a.caixa_id = c.id and a.user_id = p_user)
        and case when c.empresa_id is null then exists (select 1 from administradores_plataforma where user_id = p_user and ativo)
                 else exists (select 1 from funcionarios where id = p_user and ativo and empresa_id = c.empresa_id) end)))
$$;

create or replace function public.servico_email_acesso(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('plataforma', private.email_pode(p_user, null),
    'empresa', (select empresa_id from funcionarios where id = p_user and ativo and papel = 'admin_empresa'),
    'delegado', exists (select 1 from caixas_email_acesso a where a.user_id = p_user and private.email_usar(p_user, a.caixa_id)))
$$;

create or replace function public.servico_email_caixas(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'email', email, 'nome', nome, 'imap_host', imap_host, 'imap_porta', imap_porta,
    'smtp_host', smtp_host, 'smtp_porta', smtp_porta, 'utilizador', utilizador, 'elolog', empresa_id is null, 'tem_senha', segredo_id is not null,
    'gerir', private.email_pode(p_user, c.empresa_id)) order by empresa_id nulls first, email), '[]'::jsonb)
  from caixas_email c where private.email_usar(p_user, c.id)
$$;

create or replace function public.servico_email_credenciais(p_user uuid, p_caixa uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r caixas_email; v_senha text;
begin
  select * into r from caixas_email where id = p_caixa;
  if not found or not private.email_usar(p_user, p_caixa) then raise exception 'Caixa de email inexistente.'; end if;
  select decrypted_secret into v_senha from vault.decrypted_secrets where id = r.segredo_id;
  return jsonb_build_object('elolog', r.empresa_id is null, 'gerir', private.email_pode(p_user, r.empresa_id), 'email', r.email, 'nome', r.nome,
    'imap_host', r.imap_host, 'imap_porta', r.imap_porta, 'smtp_host', r.smtp_host, 'smtp_porta', r.smtp_porta, 'utilizador', r.utilizador, 'senha', v_senha);
end $$;

-- Funcionários do âmbito da caixa e se já têm acesso (só para quem gere a caixa).
create or replace function public.servico_email_acessos(p_user uuid, p_caixa uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid;
begin
  select empresa_id into v_emp from caixas_email where id = p_caixa;
  if not found or not private.email_pode(p_user, v_emp) then raise exception 'Só o administrador pode dar acessos a esta caixa.'; end if;
  return coalesce((select jsonb_agg(x order by x->>'nome') from (
      select jsonb_build_object('user_id', a.user_id, 'nome', a.nome, 'email', a.email, 'papel', a.papel,
        'acesso', exists (select 1 from caixas_email_acesso g where g.caixa_id = p_caixa and g.user_id = a.user_id)) x
        from administradores_plataforma a where v_emp is null and a.ativo and a.user_id <> p_user
      union all
      select jsonb_build_object('user_id', f.id, 'nome', f.nome, 'email', f.email, 'papel', f.papel::text,
        'acesso', exists (select 1 from caixas_email_acesso g where g.caixa_id = p_caixa and g.user_id = f.id))
        from funcionarios f where v_emp is not null and f.empresa_id = v_emp and f.ativo and f.id <> p_user) t), '[]'::jsonb);
end $$;

create or replace function public.servico_email_conceder(p_user uuid, p_caixa uuid, p_alvo uuid, p_sim boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_emp uuid;
begin
  select empresa_id into v_emp from caixas_email where id = p_caixa;
  if not found or not private.email_pode(p_user, v_emp) then raise exception 'Só o administrador pode dar acessos a esta caixa.'; end if;
  if p_sim then
    if not (case when v_emp is null then exists (select 1 from administradores_plataforma where user_id = p_alvo and ativo)
                 else exists (select 1 from funcionarios where id = p_alvo and ativo and empresa_id = v_emp) end) then
      raise exception 'Esse funcionário não pertence a esta equipa.'; end if;
    insert into caixas_email_acesso (caixa_id, user_id, concedido_por) values (p_caixa, p_alvo, p_user) on conflict do nothing;
  else
    delete from caixas_email_acesso where caixa_id = p_caixa and user_id = p_alvo;
  end if;
end $$;

revoke all on function private.email_usar(uuid, uuid), public.servico_email_acessos(uuid, uuid), public.servico_email_conceder(uuid, uuid, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.servico_email_acessos(uuid, uuid), public.servico_email_conceder(uuid, uuid, uuid, boolean) to service_role;
grant select, insert, update, delete on caixas_email_acesso to service_role;

-- ===== 2. Chat interno da equipa =====
create table if not exists chat_mensagens (
  id         uuid primary key default gen_random_uuid(),
  de         uuid not null references auth.users(id) on delete cascade,
  para       uuid not null references auth.users(id) on delete cascade,
  texto      text not null check (length(texto) between 1 and 2000),
  lida_em    timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists chat_conversa on chat_mensagens (least(de, para), greatest(de, para), created_at desc);
create index if not exists chat_por_ler on chat_mensagens (para) where lida_em is null;
alter table chat_mensagens enable row level security;
revoke all on chat_mensagens from anon, authenticated;

-- Organização ('elolog' ou id da empresa), papel e nome de um funcionário ativo.
create or replace function private.chat_perfil(p_user uuid, out org text, out papel text, out nome text)
language sql stable security definer set search_path = public as $$
  select * from (select 'elolog'::text, a.papel, a.nome from administradores_plataforma a where a.user_id = p_user and a.ativo
    union all select f.empresa_id::text, f.papel::text, f.nome from funcionarios f where f.id = p_user and f.ativo) t limit 1
$$;

-- Hierarquia: na Elolog todos falam entre si; a equipa Elolog fala com o administrador de cada prestador;
-- no prestador, o administrador e os operadores falam com todos, cada função fala com a mesma função,
-- e armazém ↔ terreno (fluxo físico da carga). Financeiro não fala diretamente com terreno/armazém. Empresas diferentes nunca.
create or replace function private.chat_pode(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a <> b and coalesce((select
      (x.org = 'elolog' and y.org = 'elolog')
      or (x.org = 'elolog' and y.papel = 'admin_empresa') or (y.org = 'elolog' and x.papel = 'admin_empresa')
      or (x.org = y.org and x.org <> 'elolog' and (x.papel = y.papel or 'admin_empresa' in (x.papel, y.papel) or 'operador' in (x.papel, y.papel)
          or (least(x.papel, y.papel) = 'armazem' and greatest(x.papel, y.papel) = 'operador_terreno')))
    from private.chat_perfil(a) x, private.chat_perfil(b) y where x.org is not null and y.org is not null), false)
$$;

create or replace function public.chat_contactos()
returns table (user_id uuid, nome text, papel text, organizacao text, por_ler int, ultima text, ultima_em timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare eu uuid := auth.uid(); p record;
begin
  select * into p from private.chat_perfil(eu);
  if p.org is null then return; end if;
  return query
  with cand as (
    select a.user_id as id, a.nome, a.papel, 'Elolog'::text as org from administradores_plataforma a
      where a.ativo and (p.org = 'elolog' or p.papel = 'admin_empresa')
    union all
    select f.id, f.nome, f.papel::text, coalesce(e.nome_comercial, e.nome) from funcionarios f join empresas e on e.id = f.empresa_id
      where f.ativo and ((p.org <> 'elolog' and f.empresa_id::text = p.org) or (p.org = 'elolog' and f.papel = 'admin_empresa'))
  )
  select c.id, c.nome, c.papel, c.org,
    (select count(*)::int from chat_mensagens m where m.de = c.id and m.para = eu and m.lida_em is null),
    (select left(m.texto, 80) from chat_mensagens m where (m.de = c.id and m.para = eu) or (m.de = eu and m.para = c.id) order by m.created_at desc limit 1),
    (select max(m.created_at) from chat_mensagens m where (m.de = c.id and m.para = eu) or (m.de = eu and m.para = c.id))
  from cand c where private.chat_pode(eu, c.id)
  order by 7 desc nulls last, 2 limit 300;
end $$;

-- Últimas 60 mensagens com um contacto (marca como lidas as recebidas).
create or replace function public.chat_conversa(p_com uuid)
returns setof chat_mensagens language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid();
begin
  if not private.chat_pode(eu, p_com) and not exists (select 1 from chat_mensagens where (de = eu and para = p_com) or (de = p_com and para = eu)) then
    raise exception 'Sem permissão para falar com este funcionário.'; end if;
  update chat_mensagens set lida_em = now() where de = p_com and para = eu and lida_em is null;
  return query select * from (select * from chat_mensagens m where (m.de = eu and m.para = p_com) or (m.de = p_com and m.para = eu)
    order by m.created_at desc limit 60) t order by t.created_at;
end $$;

create or replace function public.chat_enviar(p_para uuid, p_texto text)
returns chat_mensagens language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); r chat_mensagens;
begin
  if not private.chat_pode(eu, p_para) then raise exception 'A hierarquia da equipa não permite esta conversa.'; end if;
  if length(trim(coalesce(p_texto, ''))) = 0 then raise exception 'Escreva a mensagem.'; end if;
  if (select count(*) from chat_mensagens where de = eu and created_at > now() - interval '1 minute') >= 30 then
    raise exception 'Demasiadas mensagens seguidas. Aguarde um minuto.'; end if;
  insert into chat_mensagens (de, para, texto) values (eu, p_para, left(trim(p_texto), 2000)) returning * into r;
  return r;
end $$;

create or replace function public.chat_por_ler() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from chat_mensagens where para = auth.uid() and lida_em is null
$$;

revoke all on function private.chat_perfil(uuid), private.chat_pode(uuid, uuid), public.chat_contactos(), public.chat_conversa(uuid),
  public.chat_enviar(uuid, text), public.chat_por_ler() from public, anon;
grant execute on function public.chat_contactos(), public.chat_conversa(uuid), public.chat_enviar(uuid, text), public.chat_por_ler() to authenticated;

-- ===== 00139_email_atribuicoes.sql =====
-- v70 — Encaminhar um email a um funcionário para responder (atribuição). Quem tem acesso à caixa escolhe o colega
-- adequado; esse colega vê o email em «Atribuídos», pode lê-lo e responder-lhe, mesmo sem acesso ao resto da caixa.

create table if not exists email_atribuicoes (
  id            uuid primary key default gen_random_uuid(),
  caixa_id      uuid not null references caixas_email(id) on delete cascade,
  uid           bigint not null check (uid > 0),
  de            text not null default '',
  assunto       text not null default '',
  atribuido_a   uuid not null references auth.users(id) on delete cascade,
  atribuido_por uuid references auth.users(id) on delete set null,
  nota          text check (length(nota) <= 500),
  estado        text not null default 'aberto' check (estado in ('aberto', 'respondido')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (caixa_id, uid, atribuido_a)
);
alter table email_atribuicoes enable row level security;
revoke all on email_atribuicoes from anon, authenticated;

-- Funcionário ativo do âmbito da caixa (Elolog ou a empresa da caixa).
create or replace function private.email_da_equipa(p_user uuid, p_caixa uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from caixas_email c where c.id = p_caixa and case when c.empresa_id is null
    then exists (select 1 from administradores_plataforma where user_id = p_user and ativo)
    else exists (select 1 from funcionarios where id = p_user and ativo and empresa_id = c.empresa_id) end)
$$;

-- Acesso: inclui quem só tem emails atribuídos.
create or replace function public.servico_email_acesso(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('plataforma', private.email_pode(p_user, null),
    'empresa', (select empresa_id from funcionarios where id = p_user and ativo and papel = 'admin_empresa'),
    'delegado', exists (select 1 from caixas_email_acesso a where a.user_id = p_user and private.email_usar(p_user, a.caixa_id))
             or exists (select 1 from email_atribuicoes t where t.atribuido_a = p_user and private.email_da_equipa(p_user, t.caixa_id)))
$$;

-- Credenciais (nova versão; a antiga de 2 argumentos fica sem uso): caixa inteira (email_usar) ou só a mensagem atribuída (restrito = true).
create or replace function public.servico_email_credenciais2(p_user uuid, p_caixa uuid, p_uid bigint default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r caixas_email; v_senha text; v_restrito boolean := false;
begin
  select * into r from caixas_email where id = p_caixa;
  if not found then raise exception 'Caixa de email inexistente.'; end if;
  if not private.email_usar(p_user, p_caixa) then
    if p_uid is null or not private.email_da_equipa(p_user, p_caixa)
       or not exists (select 1 from email_atribuicoes where caixa_id = p_caixa and uid = p_uid and atribuido_a = p_user) then
      raise exception 'Caixa de email inexistente.'; end if;
    v_restrito := true;
  end if;
  select decrypted_secret into v_senha from vault.decrypted_secrets where id = r.segredo_id;
  return jsonb_build_object('elolog', r.empresa_id is null, 'gerir', private.email_pode(p_user, r.empresa_id), 'restrito', v_restrito,
    'email', r.email, 'nome', r.nome, 'imap_host', r.imap_host, 'imap_porta', r.imap_porta, 'smtp_host', r.smtp_host, 'smtp_porta', r.smtp_porta,
    'utilizador', r.utilizador, 'senha', v_senha);
end $$;

-- Colegas a quem se pode encaminhar (equipa da caixa, sem o próprio).
create or replace function public.servico_email_equipa(p_user uuid, p_caixa uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid;
begin
  if not private.email_usar(p_user, p_caixa) then raise exception 'Sem acesso a esta caixa.'; end if;
  select empresa_id into v_emp from caixas_email where id = p_caixa;
  return coalesce((select jsonb_agg(x order by x->>'nome') from (
      select jsonb_build_object('user_id', a.user_id, 'nome', a.nome, 'papel', a.papel) x from administradores_plataforma a
        where v_emp is null and a.ativo and a.user_id <> p_user
      union all
      select jsonb_build_object('user_id', f.id, 'nome', f.nome, 'papel', f.papel::text) from funcionarios f
        where v_emp is not null and f.empresa_id = v_emp and f.ativo and f.id <> p_user) t), '[]'::jsonb);
end $$;

-- Encaminhar: regista a atribuição e avisa o colega no chat da equipa.
create or replace function public.servico_email_atribuir(p_user uuid, p_caixa uuid, p_uid bigint, p_alvo uuid, p_de text, p_assunto text, p_nota text)
returns void language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  if not private.email_usar(p_user, p_caixa) then raise exception 'Sem acesso a esta caixa.'; end if;
  if p_alvo = p_user or not private.email_da_equipa(p_alvo, p_caixa) then raise exception 'Escolha um colega desta equipa.'; end if;
  insert into email_atribuicoes (caixa_id, uid, de, assunto, atribuido_a, atribuido_por, nota)
  values (p_caixa, p_uid, left(coalesce(p_de, ''), 300), left(coalesce(p_assunto, ''), 300), p_alvo, p_user, nullif(left(trim(coalesce(p_nota, '')), 500), ''))
  on conflict (caixa_id, uid, atribuido_a) do update set estado = 'aberto', nota = excluded.nota, atribuido_por = excluded.atribuido_por, updated_at = now();
  select email into v_email from caixas_email where id = p_caixa;
  insert into chat_mensagens (de, para, texto) values (p_user, p_alvo, left(
    '📧 Encaminhei-lhe um email para responder (' || v_email || '): «' || coalesce(nullif(p_assunto, ''), 'sem assunto') || '» de ' || coalesce(p_de, '') ||
    coalesce(E'\nNota: ' || nullif(trim(p_nota), ''), '') || E'\nAbra Email › Atribuídos.', 2000));
end $$;

-- Emails atribuídos ao utilizador (abertos primeiro).
create or replace function public.servico_email_atribuidos(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'caixa', t.caixa_id, 'caixa_email', c.email, 'uid', t.uid, 'de', t.de, 'assunto', t.assunto,
      'nota', t.nota, 'estado', t.estado, 'data', t.created_at, 'por', coalesce((select nome from administradores_plataforma where user_id = t.atribuido_por),
      (select nome from funcionarios where id = t.atribuido_por), '')) order by t.estado, t.created_at desc), '[]'::jsonb)
  from email_atribuicoes t join caixas_email c on c.id = t.caixa_id
  where t.atribuido_a = p_user and private.email_da_equipa(p_user, t.caixa_id)
$$;

create or replace function public.servico_email_respondido(p_user uuid, p_caixa uuid, p_uid bigint) returns void
language sql security definer set search_path = public as $$
  update email_atribuicoes set estado = 'respondido', updated_at = now() where caixa_id = p_caixa and uid = p_uid and atribuido_a = p_user
$$;

revoke all on function private.email_da_equipa(uuid, uuid), public.servico_email_credenciais2(uuid, uuid, bigint), public.servico_email_equipa(uuid, uuid),
  public.servico_email_atribuir(uuid, uuid, bigint, uuid, text, text, text), public.servico_email_atribuidos(uuid), public.servico_email_respondido(uuid, uuid, bigint)
  from public, anon, authenticated;
grant execute on function public.servico_email_credenciais2(uuid, uuid, bigint), public.servico_email_equipa(uuid, uuid),
  public.servico_email_atribuir(uuid, uuid, bigint, uuid, text, text, text), public.servico_email_atribuidos(uuid), public.servico_email_respondido(uuid, uuid, bigint) to service_role;
grant select, insert, update, delete on email_atribuicoes to service_role;
-- ===== 00140_chat_so_equipa.sql =====
-- v70 — Chat separado por organização: a equipa Elolog só fala entre si; cada prestador só dentro da sua empresa.
-- A administração da plataforma não vê nem contacta os funcionários dos prestadores pelo chat.

create or replace function private.chat_pode(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a <> b and coalesce((select
      (x.org = 'elolog' and y.org = 'elolog')
      or (x.org = y.org and x.org <> 'elolog' and (x.papel = y.papel or 'admin_empresa' in (x.papel, y.papel) or 'operador' in (x.papel, y.papel)
          or (least(x.papel, y.papel) = 'armazem' and greatest(x.papel, y.papel) = 'operador_terreno')))
    from private.chat_perfil(a) x, private.chat_perfil(b) y where x.org is not null and y.org is not null), false)
$$;

create or replace function public.chat_contactos()
returns table (user_id uuid, nome text, papel text, organizacao text, por_ler int, ultima text, ultima_em timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare eu uuid := auth.uid(); p record;
begin
  select * into p from private.chat_perfil(eu);
  if p.org is null then return; end if;
  return query
  with cand as (
    select a.user_id as id, a.nome, a.papel, 'Elolog'::text as org from administradores_plataforma a where a.ativo and p.org = 'elolog'
    union all
    select f.id, f.nome, f.papel::text, coalesce(e.nome_comercial, e.nome) from funcionarios f join empresas e on e.id = f.empresa_id
      where f.ativo and p.org <> 'elolog' and f.empresa_id::text = p.org
  )
  select c.id, c.nome, c.papel, c.org,
    (select count(*)::int from chat_mensagens m where m.de = c.id and m.para = eu and m.lida_em is null),
    (select left(m.texto, 80) from chat_mensagens m where (m.de = c.id and m.para = eu) or (m.de = eu and m.para = c.id) order by m.created_at desc limit 1),
    (select max(m.created_at) from chat_mensagens m where (m.de = c.id and m.para = eu) or (m.de = eu and m.para = c.id))
  from cand c where private.chat_pode(eu, c.id)
  order by 7 desc nulls last, 2 limit 300;
end $$;

-- Conversa só entre quem a hierarquia permite (já não basta ter mensagens antigas).
create or replace function public.chat_conversa(p_com uuid)
returns setof chat_mensagens language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid();
begin
  if not private.chat_pode(eu, p_com) then raise exception 'Sem permissão para falar com este funcionário.'; end if;
  update chat_mensagens set lida_em = now() where de = p_com and para = eu and lida_em is null;
  return query select * from (select * from chat_mensagens m where (m.de = eu and m.para = p_com) or (m.de = p_com and m.para = eu)
    order by m.created_at desc limit 60) t order by t.created_at;
end $$;

-- O contador também só conta mensagens de colegas da mesma organização.
create or replace function public.chat_por_ler() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from chat_mensagens where para = auth.uid() and lida_em is null and private.chat_pode(auth.uid(), de)
$$;

-- ===== 00141_chat_grupos.sql =====
-- v71 — Chat: dentro da mesma organização todos falam com todos (sem hierarquia) e podem criar grupos.
-- A equipa Elolog continua separada de cada prestador; empresas diferentes nunca se veem.

create or replace function private.chat_pode(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a <> b and coalesce((select x.org = y.org from private.chat_perfil(a) x, private.chat_perfil(b) y
    where x.org is not null and y.org is not null), false)
$$;

create table if not exists chat_grupos (
  id         uuid primary key default gen_random_uuid(),
  org        text not null,                         -- 'elolog' ou id da empresa
  nome       text not null check (length(nome) between 1 and 80),
  criado_por uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists chat_grupo_membros (
  grupo_id uuid not null references chat_grupos(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  lido_ate timestamptz not null default now(),
  primary key (grupo_id, user_id)
);
create table if not exists chat_grupo_mensagens (
  id         uuid primary key default gen_random_uuid(),
  grupo_id   uuid not null references chat_grupos(id) on delete cascade,
  de         uuid not null references auth.users(id) on delete cascade,
  texto      text not null check (length(texto) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists chat_grupo_msgs on chat_grupo_mensagens (grupo_id, created_at desc);
alter table chat_grupos enable row level security; alter table chat_grupo_membros enable row level security; alter table chat_grupo_mensagens enable row level security;
revoke all on chat_grupos, chat_grupo_membros, chat_grupo_mensagens from anon, authenticated;

-- Membro ativo do grupo (e ainda funcionário ativo da organização do grupo).
create or replace function private.chat_membro(p_user uuid, p_grupo uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from chat_grupo_membros m join chat_grupos g on g.id = m.grupo_id
    where m.grupo_id = p_grupo and m.user_id = p_user and g.org = (select org from private.chat_perfil(p_user)))
$$;

create or replace function public.chat_grupo_criar(p_nome text, p_membros uuid[]) returns uuid
language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); v_org text := (select org from private.chat_perfil(auth.uid())); g uuid; m uuid;
begin
  if v_org is null then raise exception 'Sem permissão para criar grupos.'; end if;
  if length(trim(coalesce(p_nome, ''))) = 0 then raise exception 'Dê um nome ao grupo.'; end if;
  if coalesce(array_length(p_membros, 1), 0) = 0 then raise exception 'Escolha pelo menos um colega.'; end if;
  if (select count(*) from chat_grupos where criado_por = eu and created_at > now() - interval '1 hour') >= 20 then raise exception 'Demasiados grupos criados. Aguarde.'; end if;
  insert into chat_grupos (org, nome, criado_por) values (v_org, left(trim(p_nome), 80), eu) returning id into g;
  insert into chat_grupo_membros (grupo_id, user_id) values (g, eu);
  foreach m in array p_membros loop
    if private.chat_pode(eu, m) then insert into chat_grupo_membros (grupo_id, user_id) values (g, m) on conflict do nothing; end if;
  end loop;
  return g;
end $$;

create or replace function public.chat_grupo_adicionar(p_grupo uuid, p_membros uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); m uuid;
begin
  if not private.chat_membro(eu, p_grupo) then raise exception 'Não pertence a este grupo.'; end if;
  foreach m in array coalesce(p_membros, '{}') loop
    if private.chat_pode(eu, m) then insert into chat_grupo_membros (grupo_id, user_id) values (p_grupo, m) on conflict do nothing; end if;
  end loop;
end $$;

create or replace function public.chat_grupo_sair(p_grupo uuid) returns void
language sql security definer set search_path = public as $$
  delete from chat_grupo_membros where grupo_id = p_grupo and user_id = auth.uid()
$$;

create or replace function public.chat_grupos()
returns table (id uuid, nome text, membros int, por_ler int, ultima text, ultima_em timestamptz, nomes text)
language sql stable security definer set search_path = public as $$
  select g.id, g.nome, (select count(*)::int from chat_grupo_membros x where x.grupo_id = g.id),
    (select count(*)::int from chat_grupo_mensagens t where t.grupo_id = g.id and t.de <> auth.uid() and t.created_at > m.lido_ate),
    (select left(t.texto, 80) from chat_grupo_mensagens t where t.grupo_id = g.id order by t.created_at desc limit 1),
    (select max(t.created_at) from chat_grupo_mensagens t where t.grupo_id = g.id),
    (select string_agg(p.nome, ', ' order by p.nome) from chat_grupo_membros x, private.chat_perfil(x.user_id) p where x.grupo_id = g.id and p.nome is not null)
  from chat_grupos g join chat_grupo_membros m on m.grupo_id = g.id and m.user_id = auth.uid()
  where private.chat_membro(auth.uid(), g.id) order by 6 desc nulls last, 2
$$;

create or replace function public.chat_grupo_conversa(p_grupo uuid)
returns table (id uuid, de uuid, nome_de text, texto text, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if not private.chat_membro(auth.uid(), p_grupo) then raise exception 'Não pertence a este grupo.'; end if;
  update chat_grupo_membros set lido_ate = now() where grupo_id = p_grupo and user_id = auth.uid();
  return query select t.id, t.de, (select nome from private.chat_perfil(t.de)), t.texto, t.created_at from (
    select * from chat_grupo_mensagens x where x.grupo_id = p_grupo order by x.created_at desc limit 80) t order by t.created_at;
end $$;

create or replace function public.chat_grupo_enviar(p_grupo uuid, p_texto text)
returns chat_grupo_mensagens language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); r chat_grupo_mensagens;
begin
  if not private.chat_membro(eu, p_grupo) then raise exception 'Não pertence a este grupo.'; end if;
  if length(trim(coalesce(p_texto, ''))) = 0 then raise exception 'Escreva a mensagem.'; end if;
  if (select count(*) from chat_grupo_mensagens where de = eu and created_at > now() - interval '1 minute') >= 30 then raise exception 'Demasiadas mensagens seguidas. Aguarde um minuto.'; end if;
  insert into chat_grupo_mensagens (grupo_id, de, texto) values (p_grupo, eu, left(trim(p_texto), 2000)) returning * into r;
  update chat_grupo_membros set lido_ate = now() where grupo_id = p_grupo and user_id = eu;
  return r;
end $$;

-- Contador: mensagens diretas + mensagens de grupo por ler.
create or replace function public.chat_por_ler() returns int
language sql stable security definer set search_path = public as $$
  select (select count(*)::int from chat_mensagens where para = auth.uid() and lida_em is null and private.chat_pode(auth.uid(), de))
       + (select count(*)::int from chat_grupo_mensagens t join chat_grupo_membros m on m.grupo_id = t.grupo_id and m.user_id = auth.uid()
           where t.de <> auth.uid() and t.created_at > m.lido_ate and private.chat_membro(auth.uid(), t.grupo_id))
$$;

revoke all on function private.chat_membro(uuid, uuid), public.chat_grupo_criar(text, uuid[]), public.chat_grupo_adicionar(uuid, uuid[]), public.chat_grupo_sair(uuid),
  public.chat_grupos(), public.chat_grupo_conversa(uuid), public.chat_grupo_enviar(uuid, text) from public, anon;
grant execute on function public.chat_grupo_criar(text, uuid[]), public.chat_grupo_adicionar(uuid, uuid[]), public.chat_grupo_sair(uuid),
  public.chat_grupos(), public.chat_grupo_conversa(uuid), public.chat_grupo_enviar(uuid, text) to authenticated;

-- ===== 00142_codigos_elo.sql =====
-- v72 — Novas referências: encomendas ELO_<REF>-000123 (REF = referência do prestador) e simulações ELO_SM-000045.
-- A referência do prestador é criada sozinha a partir do nome (ex.: «Transatlântico Demo, Lda.» → TRAN) e é única.
-- As encomendas e simulações antigas (TR-AAAA-NNNNNN / SIM-AAAA-NNNNNN) passam para o formato novo.

alter table empresas add column if not exists referencia text;

-- Referência curta e única a partir do nome: 4 letras da primeira palavra (sem acentos); se faltar, completa com a seguinte; se já existir, junta um número.
create or replace function private.referencia_empresa(p_nome text, p_id uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare v_base text; v_ref text; n int := 1;
begin
  v_base := upper(translate(coalesce(p_nome, ''), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑáàâãäéèêëíìîïóòôõöúùûüçñ', 'AAAAAEEEEIIIIOOOOOUUUUCNaaaaaeeeeiiiiooooouuuucn'));
  v_base := regexp_replace(v_base, '\m(LDA|LIMITADA|SA|S\.A|UNIPESSOAL|SOCIEDADE|COMPANHIA|CIA)\M', '', 'g');
  v_base := left(regexp_replace(v_base, '[^A-Z]', '', 'g'), 4);
  if length(v_base) < 3 then v_base := rpad(coalesce(nullif(v_base, ''), 'PRS'), 3, 'X'); end if;
  v_ref := v_base;
  while exists (select 1 from empresas where referencia = v_ref and id <> p_id) loop n := n + 1; v_ref := v_base || n; end loop;
  return v_ref;
end $$;

do $$ declare e record; begin
  for e in select id, coalesce(nullif(nome_comercial, ''), nome) n from empresas where referencia is null order by created_at loop
    update empresas set referencia = private.referencia_empresa(e.n, e.id) where id = e.id;
  end loop;
end $$;
create unique index if not exists empresas_referencia on empresas (referencia);
do $$ begin
  alter table empresas add constraint empresas_referencia_chk check (referencia ~ '^[A-Z0-9]{2,8}$');
exception when duplicate_object then null; end $$;

create or replace function private.empresa_referencia_auto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.referencia is null or new.referencia = '' then new.referencia := private.referencia_empresa(coalesce(nullif(new.nome_comercial, ''), new.nome), new.id); end if;
  new.referencia := upper(new.referencia);
  return new;
end $$;
create or replace trigger empresas_referencia_auto before insert or update of referencia on empresas for each row execute function private.empresa_referencia_auto();

-- Numeração contínua (não recomeça no ano novo): contadores com ano = 0.
create or replace function private.codigo_elo(p_prefixo text) returns text
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  insert into contadores (prefixo, ano, valor) values (p_prefixo, 0, 1)
  on conflict (prefixo, ano) do update set valor = contadores.valor + 1 returning valor into v;
  return p_prefixo || '-' || lpad(v::text, 6, '0');
end $$;
grant execute on function private.codigo_elo(text) to authenticated, service_role;

-- Encomendas: o código é dado pelo servidor ao criar (ELO_<REF>-NNNNNN).
alter table encomendas alter column codigo set default '';
create or replace function private.encomenda_codigo_auto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.codigo, '') = '' then
    new.codigo := private.codigo_elo('ELO_' || coalesce((select referencia from empresas where id = new.empresa_id), 'PRS'));
  end if;
  return new;
end $$;
create or replace trigger encomendas_codigo_auto before insert on encomendas for each row execute function private.encomenda_codigo_auto();

-- Simulações: ELO_SM-NNNNNN.
alter table simulacoes alter column codigo set default private.codigo_elo('ELO_SM');

-- Converter os códigos antigos (só os do formato automático).
do $$ declare r record; begin
  for r in select e.id, m.referencia from encomendas e join empresas m on m.id = e.empresa_id where e.codigo ~ '^TR-\d{4}-\d{6}$' order by e.created_at loop
    update encomendas set codigo = private.codigo_elo('ELO_' || r.referencia) where id = r.id;
  end loop;
  for r in select id from simulacoes where codigo ~ '^SIM-\d{4}-\d{6}$' order by created_at loop
    update simulacoes set codigo = private.codigo_elo('ELO_SM') where id = r.id;
  end loop;
end $$;

-- ===== 00143_repor_senha_empresa.sql =====
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

-- ===== 00144_espaco_ficheiros.sql =====
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

-- ===== 00145_declaracoes.sql =====
-- v75 — Declarações da encomenda (6 modelos internos de apoio): os dados preenchem-se uma vez e servem a todos os modelos.
-- O cliente preenche proprietário, destinatário, viatura e bens; o prestador da encomenda completa o embarque e pode corrigir tudo.

create table if not exists encomenda_declaracoes (
  encomenda_id   uuid primary key references encomendas(id) on delete cascade,
  dados          jsonb not null default '{}'::jsonb check (jsonb_typeof(dados) = 'object' and pg_column_size(dados) < 200000),
  atualizado_por uuid references auth.users(id) on delete set null,
  updated_at     timestamptz not null default now()
);
alter table encomenda_declaracoes enable row level security;
revoke all on encomenda_declaracoes from anon, authenticated;

-- Encomenda pelo código, só para o cliente dela ou para a empresa prestadora. Devolve também quem está a pedir.
create or replace function private.declaracao_acesso(p_codigo text, out v_id uuid, out v_papel text)
language sql stable security definer set search_path = public as $$
  select e.id, case when e.cliente_id = auth.uid() then 'cliente' else 'empresa' end
  from encomendas e where e.codigo = p_codigo
    and (e.cliente_id = auth.uid() or (private.minha_empresa() is not null and e.empresa_id = private.minha_empresa()))
$$;

create or replace function public.declaracoes_ler(p_codigo text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a record; r jsonb;
begin
  select * into a from private.declaracao_acesso(p_codigo);
  if a.v_id is null then raise exception 'Encomenda não encontrada.'; end if;
  select jsonb_build_object('codigo', e.codigo, 'origem', e.origem, 'destino', e.destino, 'papel', a.v_papel,
      'cliente', jsonb_build_object('nome', c.nome, 'nif', c.nif, 'telefone', c.telefone, 'morada', c.morada, 'email', c.email),
      'empresa', jsonb_build_object('nome', coalesce(m.nome_comercial, m.nome), 'nif', m.nif, 'email', m.email, 'telefone', m.telefone),
      'dados', coalesce(d.dados, '{}'::jsonb), 'atualizado_em', d.updated_at)
    into r
  from encomendas e left join clientes c on c.id = e.cliente_id left join empresas m on m.id = e.empresa_id
    left join encomenda_declaracoes d on d.encomenda_id = e.id
  where e.id = a.v_id;
  return r;
end $$;

create or replace function public.declaracoes_gravar(p_codigo text, p_dados jsonb) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare a record; v_antes jsonb; v_novo jsonb; v_quando timestamptz := now();
begin
  select * into a from private.declaracao_acesso(p_codigo);
  if a.v_id is null then raise exception 'Encomenda não encontrada.'; end if;
  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then raise exception 'Dados inválidos.'; end if;
  if jsonb_typeof(coalesce(p_dados->'bens', '[]')) <> 'array' or jsonb_array_length(coalesce(p_dados->'bens', '[]')) > 300 then raise exception 'A lista de bens é inválida (máximo 300 linhas).'; end if;
  select dados into v_antes from encomenda_declaracoes where encomenda_id = a.v_id;
  v_novo := p_dados;
  if a.v_papel = 'cliente' then   -- o embarque é do prestador
    v_novo := (v_novo - 'embarque') || jsonb_build_object('embarque', coalesce(v_antes->'embarque', '{}'::jsonb));
  end if;
  insert into encomenda_declaracoes (encomenda_id, dados, atualizado_por, updated_at) values (a.v_id, v_novo, auth.uid(), v_quando)
  on conflict (encomenda_id) do update set dados = excluded.dados, atualizado_por = excluded.atualizado_por, updated_at = excluded.updated_at;
  return v_quando;
end $$;

revoke all on function private.declaracao_acesso(text), public.declaracoes_ler(text), public.declaracoes_gravar(text, jsonb) from public, anon;
grant execute on function public.declaracoes_ler(text), public.declaracoes_gravar(text, jsonb) to authenticated;

-- ===== 00146_acesso_temporario.sql =====
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

-- ===== 00147_ocorrencias.sql =====
-- v77 — Ocorrências e suspensão da encomenda; o manifesto deixa de ser obrigatório para passar a «em trânsito»
-- (o despacho pode ser feito por um despachante à parte e carregado na plataforma como documento «despacho»).
-- Fluxo da ocorrência: registo → classificação → responsável → resolução → comunicação ao cliente → encerramento.
-- Uma ocorrência pode suspender a encomenda: o estado logístico mantém-se, mas não avança até ser retomada.

alter table encomendas add column if not exists suspensa boolean not null default false;
alter table encomendas add column if not exists suspensa_motivo text;
alter table encomendas add column if not exists suspensa_em timestamptz;

create table if not exists ocorrencias (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null unique default private.codigo_elo('ELO_OC'),
  encomenda_id   uuid not null references encomendas(id) on delete cascade,
  empresa_id     uuid not null references empresas(id),
  tipo           text not null default 'outro' check (tipo in ('atraso','dano','perda','documentacao','alfandega','pagamento','endereco','outro')),
  gravidade      text not null default 'media' check (gravidade in ('baixa','media','alta','critica')),
  estado         text not null default 'aberta' check (estado in ('aberta','em_resolucao','resolvida','encerrada')),
  descricao      text not null check (length(descricao) between 3 and 2000),
  resolucao      text check (length(resolucao) <= 2000),
  responsavel_id uuid references auth.users(id) on delete set null,
  visivel_cliente boolean not null default false,
  suspendeu      boolean not null default false,
  aberta_por     uuid references auth.users(id) on delete set null,
  aberta_por_cliente boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  encerrada_em   timestamptz
);
create index if not exists ocorrencias_encomenda on ocorrencias (encomenda_id, created_at desc);
create index if not exists ocorrencias_empresa on ocorrencias (empresa_id, estado);
create table if not exists ocorrencia_registos (
  id            bigint generated always as identity primary key,
  ocorrencia_id uuid not null references ocorrencias(id) on delete cascade,
  user_id       uuid references auth.users(id) on delete set null,
  acao          text not null,
  nota          text,
  created_at    timestamptz not null default now()
);
alter table ocorrencias enable row level security; alter table ocorrencia_registos enable row level security;
revoke all on ocorrencias, ocorrencia_registos from anon, authenticated;

-- Quem pode tratar ocorrências na empresa: administrador, operador, armazém e terreno (o financeiro só vê).
create or replace function private.ocorrencia_gestor() returns boolean
language sql stable security definer set search_path = public as $$ select private.papel_em(array['admin_empresa','operador','armazem','operador_terreno']) $$;

/** Encomenda pelo código, para a empresa prestadora (gestão) ou para o cliente dela. */
create or replace function private.ocorrencia_encomenda(p_codigo text, out v_enc encomendas, out v_cliente boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  select * into v_enc from encomendas e where e.codigo = p_codigo
    and (e.cliente_id = auth.uid() or (private.minha_empresa() is not null and e.empresa_id = private.minha_empresa()));
  if v_enc.id is null then raise exception 'Encomenda não encontrada.'; end if;
  v_cliente := v_enc.cliente_id = auth.uid() and private.minha_empresa() is distinct from v_enc.empresa_id;
end $$;

create or replace function private.ocorrencia_avisar_cliente(o ocorrencias, p_titulo text, p_corpo text) returns void
language sql security definer set search_path = public as $$
  insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
  select e.cliente_id, 'ocorrencia', p_titulo, left(p_corpo, 400), 'encomendas', e.id from encomendas e where e.id = o.encomenda_id and e.cliente_id is not null
$$;

-- Suspender / retomar (o estado logístico não muda; fica registado no histórico).
create or replace function public.encomenda_suspender(p_codigo text, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare a record;
begin
  select * into a from private.ocorrencia_encomenda(p_codigo);
  if a.v_cliente or not private.ocorrencia_gestor() then raise exception 'Sem permissão para suspender a encomenda.'; end if;
  if length(trim(coalesce(p_motivo, ''))) < 3 then raise exception 'Indique o motivo da suspensão.'; end if;
  if (a.v_enc).estado in ('entregue','cancelada') then raise exception 'Não é possível suspender uma encomenda %.', (a.v_enc).estado; end if;
  update encomendas set suspensa = true, suspensa_motivo = left(trim(p_motivo), 300), suspensa_em = now() where id = (a.v_enc).id;
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id) values ((a.v_enc).id, (a.v_enc).empresa_id, (a.v_enc).estado, (a.v_enc).estado, 'Suspensa: ' || left(trim(p_motivo), 300), auth.uid());
  if (a.v_enc).cliente_id is not null then insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values ((a.v_enc).cliente_id, 'ocorrencia', 'A encomenda ' || p_codigo || ' está suspensa', left(trim(p_motivo), 300), 'encomendas', (a.v_enc).id); end if;
end $$;

create or replace function public.encomenda_retomar(p_codigo text, p_nota text default null) returns void
language plpgsql security definer set search_path = public as $$
declare a record;
begin
  select * into a from private.ocorrencia_encomenda(p_codigo);
  if a.v_cliente or not private.ocorrencia_gestor() then raise exception 'Sem permissão para retomar a encomenda.'; end if;
  if not (a.v_enc).suspensa then raise exception 'A encomenda não está suspensa.'; end if;
  update encomendas set suspensa = false, suspensa_motivo = null, suspensa_em = null where id = (a.v_enc).id;
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id) values ((a.v_enc).id, (a.v_enc).empresa_id, (a.v_enc).estado, (a.v_enc).estado, 'Retomada' || coalesce(': ' || nullif(trim(p_nota), ''), ''), auth.uid());
  if (a.v_enc).cliente_id is not null then insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values ((a.v_enc).cliente_id, 'ocorrencia', 'A encomenda ' || p_codigo || ' foi retomada', coalesce(nullif(trim(p_nota), ''), 'O processo continua.'), 'encomendas', (a.v_enc).id); end if;
end $$;

-- Registar: a empresa (com classificação, gravidade, responsável e opção de suspender) ou o cliente (fica «aberta», visível para ele).
create or replace function public.ocorrencia_criar(p_codigo text, p_descricao text, p_tipo text default 'outro', p_gravidade text default 'media',
  p_suspender boolean default false, p_visivel_cliente boolean default false) returns ocorrencias
language plpgsql security definer set search_path = public as $$
declare a record; o ocorrencias;
begin
  select * into a from private.ocorrencia_encomenda(p_codigo);
  if not a.v_cliente and not private.ocorrencia_gestor() then raise exception 'Sem permissão para registar ocorrências.'; end if;
  if (select count(*) from ocorrencias where aberta_por = auth.uid() and created_at > now() - interval '1 hour') >= 20 then raise exception 'Demasiadas ocorrências seguidas. Aguarde.'; end if;
  insert into ocorrencias (encomenda_id, empresa_id, tipo, gravidade, descricao, visivel_cliente, suspendeu, aberta_por, aberta_por_cliente)
  values ((a.v_enc).id, (a.v_enc).empresa_id, case when a.v_cliente then 'outro' else coalesce(p_tipo, 'outro') end, case when a.v_cliente then 'media' else coalesce(p_gravidade, 'media') end,
    trim(p_descricao), a.v_cliente or coalesce(p_visivel_cliente, false), not a.v_cliente and coalesce(p_suspender, false), auth.uid(), a.v_cliente)
  returning * into o;
  insert into ocorrencia_registos (ocorrencia_id, user_id, acao, nota) values (o.id, auth.uid(), case when a.v_cliente then 'Comunicada pelo cliente' else 'Registada' end, left(trim(p_descricao), 300));
  if a.v_cliente then
    insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (o.empresa_id, 'ocorrencia', 'Ocorrência comunicada pelo cliente — ' || p_codigo, left(trim(p_descricao), 300), 'encomendas', o.encomenda_id);
  else
    if o.visivel_cliente then perform private.ocorrencia_avisar_cliente(o, 'Ocorrência na encomenda ' || p_codigo, trim(p_descricao)); end if;
    if o.suspendeu and not (a.v_enc).suspensa then perform public.encomenda_suspender(p_codigo, 'Ocorrência ' || o.codigo || ': ' || left(trim(p_descricao), 200)); end if;
  end if;
  return o;
end $$;

-- Tratar: classificar, atribuir responsável, mudar estado, registar resolução, comunicar ao cliente.
create or replace function public.ocorrencia_atualizar(p_id uuid, p_estado text default null, p_tipo text default null, p_gravidade text default null,
  p_responsavel uuid default null, p_resolucao text default null, p_comunicar boolean default null, p_nota text default null) returns ocorrencias
language plpgsql security definer set search_path = public as $$
declare o ocorrencias; v_nota text[] := '{}';
begin
  select * into o from ocorrencias where id = p_id for update;
  if o.id is null or o.empresa_id is distinct from private.minha_empresa() or not private.ocorrencia_gestor() then raise exception 'Sem permissão para esta ocorrência.'; end if;
  if o.estado = 'encerrada' then raise exception 'A ocorrência já está encerrada.'; end if;
  if p_responsavel is not null and not exists (select 1 from funcionarios where id = p_responsavel and empresa_id = o.empresa_id and ativo) then raise exception 'O responsável tem de ser um funcionário ativo da empresa.'; end if;
  if p_estado in ('resolvida','encerrada') and length(trim(coalesce(p_resolucao, o.resolucao, ''))) < 3 then raise exception 'Descreva a resolução antes de resolver ou encerrar.'; end if;
  if p_estado is not null and p_estado <> o.estado then v_nota := v_nota || ('Estado: ' || p_estado); end if;
  if p_tipo is not null and p_tipo <> o.tipo then v_nota := v_nota || ('Tipo: ' || p_tipo); end if;
  if p_gravidade is not null and p_gravidade <> o.gravidade then v_nota := v_nota || ('Gravidade: ' || p_gravidade); end if;
  if p_responsavel is not null and p_responsavel is distinct from o.responsavel_id then v_nota := v_nota || ('Responsável: ' || coalesce((select nome from funcionarios where id = p_responsavel), '?')); end if;
  if nullif(trim(p_resolucao), '') is not null then v_nota := v_nota || 'Resolução registada'::text; end if;
  if p_comunicar and not o.visivel_cliente then v_nota := v_nota || 'Comunicada ao cliente'::text; end if;
  update ocorrencias set estado = coalesce(p_estado, estado), tipo = coalesce(p_tipo, tipo), gravidade = coalesce(p_gravidade, gravidade),
    responsavel_id = coalesce(p_responsavel, responsavel_id), resolucao = coalesce(nullif(trim(p_resolucao), ''), resolucao),
    visivel_cliente = visivel_cliente or coalesce(p_comunicar, false), updated_at = now(),
    encerrada_em = case when coalesce(p_estado, estado) = 'encerrada' then now() else encerrada_em end
  where id = p_id returning * into o;
  insert into ocorrencia_registos (ocorrencia_id, user_id, acao, nota) values (o.id, auth.uid(), coalesce(nullif(array_to_string(v_nota, ' · '), ''), 'Nota'), nullif(left(trim(coalesce(p_nota, '')), 500), ''));
  if o.visivel_cliente and (p_comunicar or p_estado in ('resolvida','encerrada')) then
    perform private.ocorrencia_avisar_cliente(o, 'Ocorrência ' || o.codigo || ' — ' || case o.estado when 'resolvida' then 'resolvida' when 'encerrada' then 'encerrada' else 'atualização' end,
      coalesce(o.resolucao, o.descricao));
  end if;
  return o;
end $$;

-- Ocorrências de uma encomenda (o cliente só vê as que lhe foram comunicadas, sem notas internas).
create or replace function public.ocorrencias_da_encomenda(p_codigo text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a record;
begin
  select * into a from private.ocorrencia_encomenda(p_codigo);
  return jsonb_build_object('suspensa', (a.v_enc).suspensa, 'motivo', (a.v_enc).suspensa_motivo, 'cliente', a.v_cliente,
    'pode_gerir', not a.v_cliente and private.ocorrencia_gestor(),
    'equipa', case when a.v_cliente then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome) order by f.nome) from funcionarios f where f.empresa_id = (a.v_enc).empresa_id and f.ativo), '[]') end,
    'lista', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'codigo', o.codigo, 'tipo', o.tipo, 'gravidade', o.gravidade, 'estado', o.estado, 'descricao', o.descricao,
        'resolucao', o.resolucao, 'responsavel', (select nome from funcionarios where id = o.responsavel_id), 'responsavel_id', o.responsavel_id, 'visivel_cliente', o.visivel_cliente,
        'suspendeu', o.suspendeu, 'do_cliente', o.aberta_por_cliente, 'criada', o.created_at,
        'registos', case when a.v_cliente then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('acao', r.acao, 'nota', r.nota, 'quando', r.created_at,
            'quem', coalesce((select nome from funcionarios where id = r.user_id), (select nome from clientes where id = r.user_id), 'Sistema')) order by r.created_at) from ocorrencia_registos r where r.ocorrencia_id = o.id), '[]') end)
      order by o.created_at desc, o.codigo desc) from ocorrencias o where o.encomenda_id = (a.v_enc).id and (not a.v_cliente or o.visivel_cliente)), '[]'));
end $$;

-- Transições: suspensa não avança; manifesto já não é obrigatório para «em trânsito».
create or replace function public.transitar_encomenda(p_encomenda uuid, p_para estado_encomenda, p_nota text default null) returns encomendas
language plpgsql security definer set search_path = public as $$
declare
  v_enc   encomendas;
  v_papel papel_funcionario;
  v_falta text[] := '{}';
begin
  select * into v_enc from encomendas where id = p_encomenda for update;
  if not found then raise exception 'Encomenda inexistente.'; end if;
  if private.minha_empresa() is distinct from v_enc.empresa_id then
    raise exception 'Sem permissão para esta encomenda (inicie a sessão da empresa).';
  end if;
  v_papel := private.meu_papel();
  if v_papel is null then raise exception 'Sem permissão para esta encomenda.'; end if;
  if v_enc.suspensa and p_para <> 'cancelada' then
    raise exception 'A encomenda está suspensa (%). Retome-a antes de mudar o estado.', coalesce(v_enc.suspensa_motivo, 'ocorrência');
  end if;
  if not exists (select 1 from encomenda_transicoes t
                  where t.de = v_enc.estado and t.para = p_para and v_papel = any (t.papeis)) then
    raise exception 'Transição % → % não permitida para o papel %.', v_enc.estado, p_para, v_papel;
  end if;
  if v_papel = 'operador_terreno' and not (
       coalesce(v_enc.criado_por = auth.uid(), false)
       or exists (select 1 from trabalhos_terreno tt
                   where tt.encomenda_id = v_enc.id and tt.operador_id = auth.uid())) then
    raise exception 'Este serviço não está atribuído ao operador.';
  end if;
  if p_para = 'armazenamento' and v_enc.criada_no_terreno then
    if v_enc.cliente_id is null and coalesce(v_enc.cliente_nome, '') = '' then v_falta := v_falta || 'cliente'; end if;
    if coalesce(v_enc.origem, '') = '' or coalesce(v_enc.destino, '') = '' then v_falta := v_falta || 'rota'; end if;
    if not exists (select 1 from pagamentos pg
                    where pg.encomenda_id = v_enc.id and pg.tipo <> 'reembolso'
                      and pg.estado in ('pendente','parcial','pago')) then
      v_falta := v_falta || 'primeiro pagamento';
    end if;
    if v_enc.assinatura_documento_id is null and v_enc.pin_validacao_hash is null then
      v_falta := v_falta || 'assinatura ou PIN do cliente';
    end if;
  end if;
  if p_para = 'expedicao' and not exists (
       select 1 from recibos_armazem ra
        where ra.encomenda_id = v_enc.id and ra.confirmado and ra.carga_conferida) then
    v_falta := v_falta || 'receção confirmada e carga conferida pelo armazém';
  end if;
  if p_para = 'entregue' and not exists (
       select 1 from entregas en
        where en.encomenda_id = v_enc.id
          and coalesce(en.identificacao, '') <> ''
          and (en.assinatura_documento_id is not null or en.pin_validado)) then
    v_falta := v_falta || 'identificação e assinatura/PIN de entrega';
  end if;
  if cardinality(v_falta) > 0 then
    raise exception 'Não é possível avançar. Complete: %.', array_to_string(v_falta, ', ');
  end if;
  perform set_config('elolog.transicao', 'on', true);
  update encomendas set estado = p_para where id = v_enc.id;
  perform set_config('elolog.transicao', 'off', true);
  insert into encomenda_historico (encomenda_id, empresa_id, de, para, nota, user_id)
    values (v_enc.id, v_enc.empresa_id, v_enc.estado, p_para, p_nota, auth.uid());
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, antes, depois, motivo)
    values (v_enc.empresa_id, auth.uid(), v_papel::text, 'transicao_encomenda', 'encomendas', v_enc.id::text,
            jsonb_build_object('estado', v_enc.estado), jsonb_build_object('estado', p_para), p_nota);
  if v_enc.cliente_id is not null then
    insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
      values (v_enc.cliente_id, 'estado_encomenda', 'A sua encomenda ' || v_enc.codigo || ' mudou de estado',
              p_para::text, 'encomendas', v_enc.id);
  end if;
  select * into v_enc from encomendas where id = p_encomenda;
  return v_enc;
end $$;

revoke all on function private.ocorrencia_gestor(), private.ocorrencia_encomenda(text), private.ocorrencia_avisar_cliente(ocorrencias, text, text),
  public.encomenda_suspender(text, text), public.encomenda_retomar(text, text), public.ocorrencia_criar(text, text, text, text, boolean, boolean),
  public.ocorrencia_atualizar(uuid, text, text, text, uuid, text, boolean, text), public.ocorrencias_da_encomenda(text) from public, anon;
grant execute on function public.encomenda_suspender(text, text), public.encomenda_retomar(text, text), public.ocorrencia_criar(text, text, text, text, boolean, boolean),
  public.ocorrencia_atualizar(uuid, text, text, text, uuid, text, boolean, text), public.ocorrencias_da_encomenda(text) to authenticated;

-- ===== 00148_cliente_so_clientes.sql =====
-- v78 — A Área de Cliente é só para clientes: uma conta da equipa Elolog ou de um funcionário de prestador
-- já não consegue entrar como cliente (nem criar um perfil de cliente por engano).

-- Tipo de conta da sessão: 'equipa' (Elolog), 'funcionario' (prestador), 'cliente' ou null.
create or replace function public.tipo_conta() returns text
language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from administradores_plataforma where user_id = auth.uid()) then 'equipa'
              when exists (select 1 from funcionarios where id = auth.uid()) then 'funcionario'
              when exists (select 1 from clientes where id = auth.uid()) then 'cliente' end
$$;
revoke all on function public.tipo_conta() from public, anon;
grant execute on function public.tipo_conta() to authenticated;

-- A base de dados recusa criar um perfil de cliente para contas da equipa ou de prestadores.
do $$ begin
  create policy clientes_so_clientes on clientes as restrictive for insert to authenticated
    with check (not exists (select 1 from administradores_plataforma a where a.user_id = auth.uid())
            and not exists (select 1 from funcionarios f where f.id = auth.uid()));
exception when duplicate_object then null; end $$;

-- Limpar perfis de cliente criados por engano para contas da equipa/prestadores (só os que não têm simulações nem encomendas).
delete from clientes c
 where (exists (select 1 from administradores_plataforma a where a.user_id = c.id) or exists (select 1 from funcionarios f where f.id = c.id))
   and not exists (select 1 from encomendas e where e.cliente_id = c.id) and not exists (select 1 from simulacoes s where s.cliente_id = c.id);

-- ===== 00149_login_funcionario.sql =====
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

-- ===== 00150_mfa_admin_empresa.sql =====
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

commit;

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

commit;

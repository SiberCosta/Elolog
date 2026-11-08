-- v114 — Centro de Gestão de Tarifários (4/4): toda a plataforma consulta o mesmo motor de preços.
-- Simulação do cliente, envio ao prestador e aceitação usam private.motor_preco; a aceitação guarda uma cópia (preco_detalhe)
-- dos valores e condições em vigor nesse momento, que não muda com atualizações posteriores das tarifas.
-- O cliente nunca recebe tarifas internas, margens nem a comissão incluída: só o preço final e, se for separada, a taxa de serviço.

create or replace function public.calcular_precos(p_origem text, p_destino text, p_tipo_carga text default null, p_quantidade int default 0, p_peso_kg numeric default 0,
  p_volume_m3 numeric default 0, p_recolha_km numeric default 0, p_servico text default null)
returns table (prestador_id uuid, prestador_nome text, disponivel boolean, preco_final numeric, taxa_servico numeric, moeda char(3), mensagem text)
language plpgsql stable security definer set search_path = public as $$
declare r record; m jsonb;
begin
  if not exists (select 1 from clientes c where c.id = auth.uid()) and not private.e_admin_plataforma() then raise exception 'Apenas clientes autenticados.'; end if;
  if coalesce(trim(p_origem), '') = '' or coalesce(trim(p_destino), '') = '' then raise exception 'Indique origem e destino.'; end if;
  if least(coalesce(p_quantidade, 0), coalesce(p_peso_kg, 0), coalesce(p_volume_m3, 0), coalesce(p_recolha_km, 0)) < 0 then raise exception 'Valores negativos não são permitidos.'; end if;
  for r in select e.id, e.nome from empresas_disponiveis e order by e.nome loop
    m := private.motor_preco(r.id, p_servico, p_origem, p_destino, p_tipo_carga, p_quantidade, p_peso_kg, p_volume_m3, p_recolha_km);
    prestador_id := r.id; prestador_nome := r.nome; disponivel := (m ->> 'disponivel')::boolean;
    preco_final := (m ->> 'preco_final')::numeric; moeda := m ->> 'moeda'; mensagem := m ->> 'mensagem';
    taxa_servico := case when m ->> 'apresentacao' = 'separada' then (m ->> 'comissao')::numeric end;
    return next;
  end loop;
end $$;
revoke all on function public.calcular_precos(text, text, text, int, numeric, numeric, numeric, text) from public, anon;
grant execute on function public.calcular_precos(text, text, text, int, numeric, numeric, numeric, text) to authenticated;

-- a função antiga continua a responder (mesmas colunas) para as versões da aplicação que ainda a chamam, agora pelo motor
create or replace function public.calcular_propostas(p_origem text, p_destino text, p_tipo_carga text default null, p_quantidade integer default 0, p_peso_kg numeric default 0,
  p_volume_m3 numeric default 0, p_recolha_km numeric default 0, p_transporte text default null)
returns table (prestador_id uuid, prestador_nome text, disponivel boolean, preco_total numeric, moeda character)
language sql stable security definer set search_path = public as $$
  select x.prestador_id, x.prestador_nome, x.disponivel, x.preco_final, x.moeda from public.calcular_precos(p_origem, p_destino, p_tipo_carga, p_quantidade, p_peso_kg, p_volume_m3, p_recolha_km, p_transporte) x $$;

-- a administração testa o motor com todos os passos (nunca exposto ao cliente nem ao prestador)
create or replace function public.testar_preco(p_empresa uuid, p_origem text, p_destino text, p_tipo_carga text default null, p_quantidade int default 0, p_peso_kg numeric default 0,
  p_volume_m3 numeric default 0, p_recolha_km numeric default 0, p_servico text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not private.e_admin_plataforma() then raise exception 'Só a administração Elolog pode testar o motor de preços.' using errcode = '42501'; end if;
  return private.motor_preco(p_empresa, p_servico, p_origem, p_destino, p_tipo_carga, p_quantidade, p_peso_kg, p_volume_m3, p_recolha_km);
end $$;
revoke all on function public.testar_preco(uuid, text, text, text, int, numeric, numeric, numeric, text) from public, anon;
grant execute on function public.testar_preco(uuid, text, text, text, int, numeric, numeric, numeric, text) to authenticated;

create or replace function public.enviar_simulacao(p_simulacao uuid, p_empresa uuid)
returns simulacoes language plpgsql security definer set search_path = public as $$
declare v_sim simulacoes; m jsonb; v_preco numeric;
begin
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.cliente_id is distinct from auth.uid() then raise exception 'Simulação inexistente.'; end if;
  if v_sim.estado <> 'rascunho' then raise exception 'A simulação já foi enviada (%).', v_sim.estado; end if;
  if not exists (select 1 from empresas_disponiveis e where e.id = p_empresa) then raise exception 'Este prestador não está disponível.'; end if;
  m := private.motor_preco(p_empresa, null, v_sim.origem, v_sim.destino, v_sim.tipo_carga, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3,
                           case when v_sim.recolha_na_morada then coalesce(v_sim.recolha_distancia_km, 0) else 0 end);
  if (m ->> 'disponivel')::boolean then v_preco := (m ->> 'preco_final')::numeric; end if;
  update simulacoes set estado = 'enviada', empresa_destinatario_id = p_empresa, enviada_em = now(), preco_estimado = v_preco,
         moeda_estimada = coalesce(m ->> 'moeda', 'EUR'), tarifa_estimada_id = (m ->> 'tarifa_id')::uuid, preco_detalhe = case when v_preco is not null then m end
   where id = v_sim.id returning * into v_sim;
  insert into notificacoes (empresa_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (p_empresa, 'nova_simulacao', case when v_preco is null then 'Novo pedido de cotação' else 'Nova simulação recebida' end,
            case when v_preco is null then 'De ' || v_sim.origem || ' para ' || v_sim.destino || ': ainda não tem tarifa aprovada para este pedido. Indique o preço ao aceitar.' end,
            'simulacoes', v_sim.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (p_empresa, auth.uid(), 'cliente', 'enviar_simulacao', 'simulacoes', v_sim.id::text,
            jsonb_build_object('preco_estimado', v_preco, 'tarifa', m ->> 'tarifa_id', 'origem_tarifa', m ->> 'origem_tarifa', 'pedido_cotacao', v_preco is null));
  return v_sim;
end $$;

-- cópia congelada no momento da aprovação (valores e condições em vigor nesse instante)
create or replace function private.preco_congelado(p_det jsonb, p_preco numeric, p_moeda text, p_tarifa uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(p_det, jsonb_build_object('origem_tarifa', 'cotacao', 'preco_final', p_preco, 'moeda', p_moeda, 'tarifa_id', p_tarifa,
           'tarifa', (select to_jsonb(t) - 'criado_por' from tarifas t where t.id = p_tarifa))) || jsonb_build_object('congelado_em', now()) $$;

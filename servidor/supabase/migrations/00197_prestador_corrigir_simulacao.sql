-- Elolog v154: o prestador corrige uma simulação que recebeu (antes de a aceitar). Só a empresa a quem foi enviada,
-- só funcionários de administração ou operação, só enquanto está «enviada». Muda apenas carga, rota, datas, moradas,
-- observações e preço; regista o antes e o depois na auditoria e avisa o cliente. Não apaga dados.
create or replace function public.prestador_corrigir_simulacao(p_simulacao uuid, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp uuid := private.minha_empresa(); v_papel text := private.meu_papel()::text; s simulacoes; n simulacoes; v_preco numeric;
begin
  if v_emp is null or v_papel not in ('admin_empresa', 'operador') then
    raise exception 'Só a administração ou a operação da empresa podem corrigir simulações.' using errcode = '42501'; end if;
  if jsonb_typeof(coalesce(p_dados, '{}'::jsonb)) <> 'object' then raise exception 'Dados inválidos.'; end if;
  select * into s from simulacoes where id = p_simulacao for update;
  if not found or s.empresa_destinatario_id is distinct from v_emp then raise exception 'Simulação não encontrada.' using errcode = '42501'; end if;
  if s.estado <> 'enviada' then raise exception 'Esta simulação já foi respondida e não pode ser corrigida.'; end if;
  if coalesce(trim(p_dados ->> 'origem'), s.origem) = '' or coalesce(trim(p_dados ->> 'destino'), s.destino) = '' then raise exception 'Indique a origem e o destino.'; end if;
  v_preco := nullif(p_dados ->> 'preco', '')::numeric;
  if v_preco is not null and (v_preco <= 0 or v_preco > 10000000) then raise exception 'Preço inválido.'; end if;
  if p_dados ? 'volumes' and (jsonb_typeof(p_dados -> 'volumes') <> 'array' or jsonb_array_length(p_dados -> 'volumes') > 200) then raise exception 'Lista de volumes inválida.'; end if;
  update simulacoes set
    origem = coalesce(left(nullif(trim(p_dados ->> 'origem'), ''), 200), origem),
    destino = coalesce(left(nullif(trim(p_dados ->> 'destino'), ''), 200), destino),
    tipo_carga = coalesce(left(nullif(trim(p_dados ->> 'tipo_carga'), ''), 120), tipo_carga),
    descricao = coalesce(left(nullif(trim(p_dados ->> 'descricao'), ''), 1000), descricao),
    quantidade = coalesce(nullif(p_dados ->> 'quantidade', '')::numeric::int, quantidade),
    peso_kg = coalesce(nullif(p_dados ->> 'peso_kg', '')::numeric, peso_kg),
    volume_m3 = coalesce(nullif(p_dados ->> 'volume_m3', '')::numeric, volume_m3),
    volumes = case when p_dados ? 'volumes' then p_dados -> 'volumes' else volumes end,
    data_prevista = coalesce(nullif(p_dados ->> 'data_prevista', '')::date, data_prevista),
    recolha_na_morada = coalesce((p_dados ->> 'recolha')::boolean, recolha_na_morada),
    morada_recolha = case when p_dados ? 'morada_recolha' then left(nullif(trim(p_dados ->> 'morada_recolha'), ''), 300) else morada_recolha end,
    recolha_distancia_km = coalesce(nullif(p_dados ->> 'recolha_km', '')::numeric, recolha_distancia_km),
    remetente = case when jsonb_typeof(p_dados -> 'remetente') = 'object' then remetente || (p_dados -> 'remetente') else remetente end,
    destinatario = case when jsonb_typeof(p_dados -> 'destinatario') = 'object' then destinatario || (p_dados -> 'destinatario') else destinatario end,
    valor_declarado = case when p_dados ? 'valor_declarado' then nullif(p_dados ->> 'valor_declarado', '')::numeric else valor_declarado end,
    observacoes = case when p_dados ? 'observacoes' then left(nullif(trim(p_dados ->> 'observacoes'), ''), 1000) else observacoes end,
    preco_estimado = coalesce(v_preco, preco_estimado)
  where id = p_simulacao returning * into n;
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, antes, depois, motivo)
    values (v_emp, auth.uid(), v_papel, 'corrigir_simulacao', 'simulacoes', s.id::text,
            jsonb_build_object('origem', s.origem, 'destino', s.destino, 'peso_kg', s.peso_kg, 'volume_m3', s.volume_m3, 'preco', s.preco_estimado, 'data_prevista', s.data_prevista),
            jsonb_build_object('origem', n.origem, 'destino', n.destino, 'peso_kg', n.peso_kg, 'volume_m3', n.volume_m3, 'preco', n.preco_estimado, 'data_prevista', n.data_prevista),
            left(nullif(trim(p_dados ->> 'nota'), ''), 500));
  insert into notificacoes (user_id, tipo, titulo, corpo, referencia_tabela, referencia_id)
    values (s.cliente_id, 'simulacao_corrigida', 'O prestador corrigiu o seu pedido ' || s.codigo,
            'Reveja os dados atualizados' || case when n.preco_estimado is distinct from s.preco_estimado and n.preco_estimado is not null
              then '. Novo valor: ' || to_char(n.preco_estimado, 'FM999G999G990D00') || ' €' else '' end
            || coalesce('. Nota: ' || left(nullif(trim(p_dados ->> 'nota'), ''), 300), '') || '.', 'simulacoes', s.id);
  return jsonb_build_object('id', n.id, 'codigo', n.codigo, 'preco_estimado', n.preco_estimado);
end $$;
revoke all on function public.prestador_corrigir_simulacao(uuid, jsonb) from public, anon;
grant execute on function public.prestador_corrigir_simulacao(uuid, jsonb) to authenticated;

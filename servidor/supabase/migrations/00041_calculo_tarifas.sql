-- =====================================================================
-- Elolog · 0004 · Cálculo de preços NO SERVIDOR
-- Depende de 0001, 0002 e 0003. Replica a lógica do front-end
-- (window.elologFindActiveTariff em js/prestador/financeiro.js e atualizarPrestadoresCliente()
--  em js/cliente/simulacao.js), mas o cliente nunca lê as tarifas:
-- recebe apenas o total por prestador.
-- NÃO FOI EXECUTADO: testar primeiro num projeto Supabase de teste.
-- =====================================================================
create extension if not exists unaccent with schema extensions;
-- Idempotente: se uma versão anterior da 0003 já foi aplicada, remove o acesso direto a tarifas.
drop policy if exists tarifas_clientes on tarifas;
-- ---------- 1. Estimativa guardada na simulação -----------------------
alter table simulacoes add column preco_estimado     numeric(14,2) check (preco_estimado >= 0),
  add column moeda_estimada     char(3), add column tarifa_estimada_id uuid references tarifas(id);
-- Uma tarifa usada numa proposta OU numa estimativa não é alterada retroativamente.
create or replace function private.proteger_tarifa_usada() returns trigger
language plpgsql security definer set search_path = public as $$ begin
  if (exists (select 1 from propostas p where p.tarifa_id = old.id)
      or exists (select 1 from simulacoes s where s.tarifa_estimada_id = old.id)) and (
       (new.aplicacao, new.metodo, new.valor, new.moeda, new.quantidade_minima, new.preco_minimo,
        new.origem, new.destino, new.tipo_carga, new.transporte, new.regras::text) is distinct from
       (old.aplicacao, old.metodo, old.valor, old.moeda, old.quantidade_minima, old.preco_minimo,
        old.origem, old.destino, old.tipo_carga, old.transporte, old.regras::text)) then
    raise exception 'Tarifa já utilizada: crie uma nova versão (a anterior fica inativa).'; end if;
  return new; end $$; -- ---------- 2. Funções internas (não expostas pela API) ---------------
-- Mesma normalização do front-end: aparar, minúsculas, sem acentos.
create function private.norm(p text) returns text
language sql stable set search_path = public, extensions as $$
  select lower(trim(extensions.unaccent(coalesce(p, '')))) $$;
-- No front-end o custo de recolha do cliente é 1 € por km (custoKm = km). Ajustar aqui se mudar.
create function private.custo_recolha_por_km() returns numeric
language sql immutable as $$ select 1.00::numeric $$;
-- Tarifa ativa MAIS ESPECÍFICA para prestador, rota e carga.
-- Critérios iguais a elologFindActiveTariff: estado ativo, datas de validade, origem/destino
-- por correspondência parcial nos dois sentidos, transporte igual (se ambos existirem) e
-- tipo de carga contido no pedido. Ordena por nº de campos preenchidos (origem, destino, carga);
-- desempate (que o front-end deixava à ordem de gravação): versão mais recente.
-- DIFERENÇA: só considera tarifas de aplicação 'carga' (o front-end também podia apanhar 'recolha').
create function private.tarifa_aplicavel(
  p_empresa uuid, p_origem text, p_destino text, p_tipo_carga text, p_transporte text default null
) returns tarifas language sql stable security definer set search_path = public, extensions as $$ select t.*
    from tarifas t where t.empresa_id = p_empresa and t.ativa and t.aplicacao = 'carga'
     and (t.validade_inicio is null or t.validade_inicio <= current_date)
     and (t.validade_fim    is null or t.validade_fim    >= current_date) and (coalesce(t.origem, '') = ''
          or strpos(private.norm(p_origem), private.norm(t.origem)) > 0
          or strpos(private.norm(t.origem), private.norm(p_origem)) > 0) and (coalesce(t.destino, '') = ''
          or strpos(private.norm(p_destino), private.norm(t.destino)) > 0
          or strpos(private.norm(t.destino), private.norm(p_destino)) > 0)
     and (coalesce(t.transporte, '') = '' or coalesce(p_transporte, '') = ''
          or private.norm(t.transporte) = private.norm(p_transporte))
     and (coalesce(t.tipo_carga, '') = '' or coalesce(p_tipo_carga, '') = ''
          or strpos(private.norm(p_tipo_carga), private.norm(t.tipo_carga)) > 0)
   order by ((coalesce(t.origem, '')     <> '')::int + (coalesce(t.destino, '')    <> '')::int
           + (coalesce(t.tipo_carga, '') <> '')::int) desc, t.versao desc, t.created_at desc limit 1 $$;
-- Preço da carga com uma tarifa. Fórmulas do front-end:
--   fixo     → valor
--   peso     → maior(peso real, volume × fator volumétrico) × valor   (fator em regras->>'volumetricFactor', por omissão 167)
--   unidade  → quantidade × valor
--   restantes (volume, wm, contentor) → volume m³ × valor
-- e depois aplica o preço mínimo. p_peso_kg é o PESO TOTAL da carga.
create function private.preco_com_tarifa(t tarifas, p_quantidade int, p_peso_kg numeric, p_volume_m3 numeric)
returns numeric language sql immutable as $$ select round(greatest( case t.metodo when 'fixo'    then t.valor
      when 'peso'    then greatest(coalesce(p_peso_kg, 0), coalesce(p_volume_m3, 0)
                                   * coalesce(nullif((t.regras ->> 'volumetricFactor')::numeric, 0), 167)) * t.valor
      when 'unidade' then coalesce(p_quantidade, 0) * t.valor
      else                coalesce(p_volume_m3, 0) * t.valor end, t.preco_minimo), 2) $$;
revoke execute on function private.norm(text), private.custo_recolha_por_km(),
  private.tarifa_aplicavel(uuid, text, text, text, text),
  private.preco_com_tarifa(tarifas, int, numeric, numeric) from public;
-- ---------- 3. Colunas que o cliente pode escrever na simulação -------
-- O preço estimado, o estado e o destinatário só mudam por funções do servidor.
revoke insert, update on simulacoes from authenticated;
grant  insert (cliente_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3,
               volumes, recolha_na_morada, recolha_distancia_km) on simulacoes to authenticated;
grant  update (origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3,
               volumes, recolha_na_morada, recolha_distancia_km) on simulacoes to authenticated;
-- Depois de enviada, os dados já não se editam (invalidariam a estimativa): cancela-se e cria-se outra.
drop policy sim_cliente_editar on simulacoes;
create policy sim_cliente_editar on simulacoes for update to authenticated
  using (cliente_id = auth.uid() and estado = 'rascunho')
  with check (cliente_id = auth.uid() and estado = 'rascunho');
-- ---------- 4. Pré-visualização: um total por prestador disponível ----
-- Não devolve tarifas nem fórmulas, só o total (já com recolha).
create function public.calcular_propostas( p_origem text, p_destino text, p_tipo_carga text default null,
  p_quantidade int default 0, p_peso_kg numeric default 0, p_volume_m3 numeric default 0,
  p_recolha_km numeric default 0, p_transporte text default null
) returns table (prestador_id uuid, prestador_nome text, disponivel boolean, preco_total numeric, moeda char(3))
language plpgsql stable security definer set search_path = public as $$ declare r   record; v_t tarifas; begin
  if not exists (select 1 from clientes c where c.id = auth.uid()) then
    raise exception 'Apenas clientes autenticados.'; end if;
  if coalesce(trim(p_origem), '') = '' or coalesce(trim(p_destino), '') = '' then
    raise exception 'Indique origem e destino.'; end if;
  if coalesce(p_quantidade, 0) < 0 or coalesce(p_peso_kg, 0) < 0
     or coalesce(p_volume_m3, 0) < 0 or coalesce(p_recolha_km, 0) < 0 then
    raise exception 'Valores negativos não são permitidos.'; end if;
  for r in select e.id, e.nome from empresas_disponiveis e order by e.nome loop
    v_t := private.tarifa_aplicavel(r.id, p_origem, p_destino, p_tipo_carga, p_transporte);
    prestador_id   := r.id; prestador_nome := r.nome; if v_t.id is null then
      disponivel := false;  preco_total := null;  moeda := null;      -- "A aguardar tarifa"
    else disponivel  := true;
      preco_total := private.preco_com_tarifa(v_t, p_quantidade, p_peso_kg, p_volume_m3)
                     + round(coalesce(p_recolha_km, 0) * private.custo_recolha_por_km(), 2);
      moeda       := v_t.moeda; end if; return next; end loop; end $$;
-- ---------- 5. Envio explícito ao prestador (fixa a estimativa) -------
create function public.enviar_simulacao(p_simulacao uuid, p_empresa uuid) returns simulacoes
language plpgsql security definer set search_path = public as $$ declare v_sim   simulacoes; v_t     tarifas;
  v_preco numeric; begin select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.cliente_id is distinct from auth.uid() then raise exception 'Simulação inexistente.';
  end if; if v_sim.estado <> 'rascunho' then raise exception 'A simulação já foi enviada (%).', v_sim.estado;
  end if; if not exists (select 1 from empresas_disponiveis e where e.id = p_empresa) then
    raise exception 'Este prestador não está disponível.'; end if;
  v_t := private.tarifa_aplicavel(p_empresa, v_sim.origem, v_sim.destino, v_sim.tipo_carga);
  if v_t.id is null then raise exception 'O prestador ainda não configurou tarifa para esta rota.'; end if;
  v_preco := private.preco_com_tarifa(v_t, v_sim.quantidade, v_sim.peso_kg, v_sim.volume_m3)
             + case when v_sim.recolha_na_morada
                    then round(coalesce(v_sim.recolha_distancia_km, 0) * private.custo_recolha_por_km(), 2)
                    else 0 end; update simulacoes
     set estado = 'enviada', empresa_destinatario_id = p_empresa, enviada_em = now(),
         preco_estimado = v_preco, moeda_estimada = v_t.moeda, tarifa_estimada_id = v_t.id where id = v_sim.id
   returning * into v_sim;
  insert into notificacoes (empresa_id, tipo, titulo, referencia_tabela, referencia_id)
    values (p_empresa, 'nova_simulacao', 'Nova simulação recebida', 'simulacoes', v_sim.id);
  insert into auditoria (empresa_id, user_id, papel, acao, entidade, entidade_id, depois)
    values (p_empresa, auth.uid(), 'cliente', 'enviar_simulacao', 'simulacoes', v_sim.id::text,
            jsonb_build_object('preco_estimado', v_preco, 'tarifa', v_t.id)); return v_sim; end $$;
-- ---------- 6. Cancelar (rascunho, enviada ou respondida) -------------
create function public.cancelar_simulacao(p_simulacao uuid) returns simulacoes
language plpgsql security definer set search_path = public as $$ declare v_sim simulacoes; begin
  select * into v_sim from simulacoes where id = p_simulacao for update;
  if not found or v_sim.cliente_id is distinct from auth.uid() then raise exception 'Simulação inexistente.';
  end if; if v_sim.estado not in ('rascunho', 'enviada', 'respondida') then
    raise exception 'Não é possível cancelar uma simulação (%).', v_sim.estado; end if;
  update propostas set estado = 'cancelada', respondida_em = now()
   where simulacao_id = v_sim.id and estado = 'enviada';
  update simulacoes set estado = 'cancelada' where id = v_sim.id returning * into v_sim; return v_sim; end $$;
-- ---------- 7. Execução -----------------------------------------------
revoke execute on function public.calcular_propostas(text, text, text, int, numeric, numeric, numeric, text) from public, anon;
revoke execute on function public.enviar_simulacao(uuid, uuid) from public, anon;
revoke execute on function public.cancelar_simulacao(uuid) from public, anon;
grant  execute on function public.calcular_propostas(text, text, text, int, numeric, numeric, numeric, text) to authenticated;
grant  execute on function public.enviar_simulacao(uuid, uuid) to authenticated;
grant  execute on function public.cancelar_simulacao(uuid) to authenticated;

-- Elolog v156: rastreio público no site («Rastrear carga»), autorizado só com o código.
-- Devolve apenas: código, etapa, origem, destino, partida e chegada previstas e data da última mudança.
-- Sem nomes, moradas, contactos, preços nem empresa. Limite: 30 consultas por 10 minutos por endereço.
-- Um código de simulação já aceite (ELO_SM-…) devolve a encomenda em que se transformou. Não altera dados.
create or replace function public.rastrear_encomenda(p_codigo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c text := upper(trim(coalesce(p_codigo, ''))); v_ip text; e encomendas; s simulacoes;
begin
  if v_c !~ '^ELO_[A-Z0-9]{1,12}-[0-9]{1,9}$' then return jsonb_build_object('encontrada', false, 'motivo', 'formato'); end if;
  begin v_ip := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1); exception when others then v_ip := ''; end;
  if not public.servico_limite('rastreio:' || coalesce(nullif(trim(v_ip), ''), 'sem-ip'), 30, 10) then
    return jsonb_build_object('encontrada', false, 'motivo', 'limite'); end if;
  select * into e from encomendas where codigo = v_c;
  if not found then
    select * into s from simulacoes where codigo = v_c and estado <> 'rascunho';
    if not found then return jsonb_build_object('encontrada', false, 'motivo', 'inexistente'); end if;
    select * into e from encomendas where simulacao_id = s.id order by created_at desc limit 1;
    if not found then
      return jsonb_build_object('encontrada', true, 'codigo', s.codigo, 'etapa', case when s.estado = 'cancelada' then 'cancelada' else 'cotacao' end,
        'origem', s.origem, 'destino', s.destino, 'atualizada', s.updated_at);
    end if;
  end if;
  return jsonb_build_object('encontrada', true, 'codigo', e.codigo, 'etapa', e.estado::text, 'suspensa', coalesce(e.suspensa, false),
    'origem', e.origem, 'destino', e.destino, 'partida_prevista', e.partida_prevista, 'chegada_prevista', e.chegada_prevista, 'atualizada', e.updated_at);
end $$;
revoke all on function public.rastrear_encomenda(text) from public;
grant execute on function public.rastrear_encomenda(text) to anon, authenticated;

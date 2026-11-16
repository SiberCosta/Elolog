-- Elolog v156: rastreio público no site (exceção autorizada à regra «o público só executa validar_empresa»).
-- Com o código completo devolve só: etapa atual, origem e destino, datas previstas, última atualização e as etapas
-- já passadas com a data. Nunca devolve nomes, moradas, contactos, preços nem documentos.
-- Limite: 20 pesquisas por 10 minutos por endereço. Não altera nem apaga dados.
create or replace function public.rastrear_encomenda(p_codigo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_cod text := upper(regexp_replace(coalesce(p_codigo, ''), '\s', '', 'g')); v_ip text; e encomendas; v_etapas jsonb;
begin
  if v_cod !~ '^ELO_[A-Z0-9]{2,12}-\d{6}$' then return jsonb_build_object('encontrada', false, 'motivo', 'formato'); end if;
  begin v_ip := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1); exception when others then v_ip := ''; end;
  if not public.servico_limite('rastreio:' || coalesce(nullif(trim(v_ip), ''), 'sem-ip'), 20, 10) then
    return jsonb_build_object('encontrada', false, 'motivo', 'limite'); end if;
  select * into e from encomendas where codigo = v_cod;
  if not found then return jsonb_build_object('encontrada', false, 'motivo', 'nao_existe'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('etapa', h.para, 'data', h.created_at) order by h.created_at), '[]'::jsonb) into v_etapas
    from encomenda_historico h where h.encomenda_id = e.id and h.para is not null;
  return jsonb_build_object('encontrada', true, 'codigo', e.codigo, 'estado', e.estado, 'suspensa', coalesce(e.suspensa, false),
    'origem', left(e.origem, 80), 'destino', left(e.destino, 80), 'data_recolha', e.data_prevista,
    'partida_prevista', e.partida_prevista, 'chegada_prevista', e.chegada_prevista, 'atualizada', e.updated_at, 'etapas', v_etapas);
end $$;
revoke all on function public.rastrear_encomenda(text) from public;
grant execute on function public.rastrear_encomenda(text) to anon, authenticated;

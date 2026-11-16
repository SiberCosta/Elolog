-- Elolog v158: cada operador só tem uma rota a decorrer. iniciar_percurso recusa uma rota nova enquanto houver outra
-- do mesmo operador sem terminar (com sinal nas últimas 12 horas). rota_ativa() diz ao telemóvel qual é, antes de pedir
-- a localização. Não apaga nem altera dados.
create or replace function public.rota_ativa()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('trabalho_id', s.trabalho_id, 'tipo', t.tipo, 'codigo', e.codigo, 'iniciado_em', s.iniciado_em)
    from trabalhos_seguimento s join trabalhos_terreno t on t.id = s.trabalho_id left join encomendas e on e.id = s.encomenda_id
   where s.operador_id = auth.uid() and s.terminado_em is null and t.estado = 'em_curso' and s.atualizado_em > now() - interval '12 hours'
   order by s.atualizado_em desc limit 1 $$;
revoke all on function public.rota_ativa() from public, anon;
grant execute on function public.rota_ativa() to authenticated;

create or replace function public.iniciar_percurso(p_trabalho uuid, p_lat numeric, p_lon numeric, p_precisao integer DEFAULT NULL::integer, p_previsto_ate timestamp with time zone DEFAULT NULL::timestamp with time zone)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare t trabalhos_terreno; v_outra text;
begin
  t := private.trabalho_meu(p_trabalho);
  if t.estado not in ('planeada', 'em_curso') then raise exception 'Este serviço já está fechado.'; end if;
  if p_previsto_ate is not null and (p_previsto_ate < now() - interval '1 day' or p_previsto_ate > now() + interval '14 days') then raise exception 'Hora combinada inválida.'; end if;
  select upper(case when o.tipo = 'entrega' then 'ENT-' else 'REC-' end || left(o.id::text, 5)) || coalesce(' (' || e.codigo || ')', '') into v_outra
    from trabalhos_seguimento s join trabalhos_terreno o on o.id = s.trabalho_id left join encomendas e on e.id = s.encomenda_id
   where s.operador_id = coalesce(t.operador_id, auth.uid()) and s.trabalho_id <> t.id and s.terminado_em is null and o.estado = 'em_curso'
     and s.atualizado_em > now() - interval '12 hours' limit 1;
  if v_outra is not null then raise exception 'Termine primeiro a rota %: só pode ter uma rota a decorrer.', v_outra; end if;
  update trabalhos_terreno set estado = 'em_curso', operador_id = coalesce(operador_id, auth.uid()), updated_at = now() where id = t.id;
  insert into trabalhos_seguimento (trabalho_id, empresa_id, encomenda_id, operador_id, lat, lon, precisao_m, previsto_ate)
  values (t.id, t.empresa_id, t.encomenda_id, coalesce(t.operador_id, auth.uid()), p_lat, p_lon, p_precisao, p_previsto_ate)
  on conflict (trabalho_id) do update set lat = excluded.lat, lon = excluded.lon, precisao_m = excluded.precisao_m, atualizado_em = now(), terminado_em = null,
    previsto_ate = coalesce(excluded.previsto_ate, trabalhos_seguimento.previsto_ate), alerta_sinal_em = null;
  perform private.emitir_evento(t.empresa_id, 'percurso.iniciado', (select codigo from encomendas where id = t.encomenda_id), jsonb_build_object('servico', t.tipo, 'previsto_ate', p_previsto_ate));
  return jsonb_build_object('ok', true);
end $function$;

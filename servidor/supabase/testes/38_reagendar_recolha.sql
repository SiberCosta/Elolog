-- 38: reagendar uma recolha falhada (migração 00208). Corre em rollback; usa a encomenda em «recolha» e os funcionários
-- da empresa dela, com sessões de empresa criadas só dentro da transação.
begin;
create temp table t_x on commit drop as select e.id enc, e.empresa_id emp,
  (select id from funcionarios f where f.empresa_id=e.empresa_id and papel='operador' limit 1) op,
  (select id from funcionarios f where f.empresa_id=e.empresa_id and papel='operador_terreno' limit 1) ter
  from encomendas e where e.estado='recolha' limit 1;
grant select on t_x to authenticated;
delete from sessoes_empresa where user_id in (select op from t_x union select ter from t_x);
insert into sessoes_empresa(user_id, empresa_id, valida_ate) select op, emp, now()+interval '1 hour' from t_x union all select ter, emp, now()+interval '1 hour' from t_x;
insert into trabalhos_terreno(empresa_id, encomenda_id, tipo, data, estado) select emp, enc, 'recolha', current_date, 'planeada' from t_x;
select set_config('request.jwt.claims', json_build_object('sub',(select ter from t_x),'role','authenticated')::text, true);
set local role authenticated;
do $rel$ declare r text := ''; begin
  begin perform public.avancar_encomenda((select enc from t_x), 'agendamento', 'O cliente não estava'); r := r || 'terreno_pode=SIM '; exception when others then r := r || 'terreno_recusado '; end;
  perform set_config('request.jwt.claims', json_build_object('sub',(select op from t_x),'role','authenticated')::text, true);
  begin perform public.avancar_encomenda((select enc from t_x), 'agendamento', null); r := r || 'sem_motivo_aceite '; exception when others then r := r || 'sem_motivo_recusado '; end;
  perform public.avancar_encomenda((select enc from t_x), 'agendamento', 'Cliente ausente; nova recolha sexta de manhã');
  r := r || 'operador_reagendou estado=' || (select estado from encomendas where id=(select enc from t_x));
  raise exception 'RELATORIO %', r; end $rel$;
-- Resultado na base real (25/11/2026): terreno_recusado sem_motivo_recusado operador_reagendou estado=agendamento

-- 39: fluxo completo de ponta a ponta na base real, TODO dentro de uma transação que é desfeita no fim (nada fica gravado).
-- Atores reais da empresa aprovada (operador, armazém, operador de terreno) e um cliente real; sessões de empresa criadas
-- só dentro da transação. Cada passo regista OK/ERRO e o relatório sai na exceção final.
begin;
create temp table t_a on commit drop as
 select e.id emp,
  (select id from funcionarios f where f.empresa_id=e.id and papel='operador' and ativo limit 1) op,
  (select id from funcionarios f where f.empresa_id=e.id and papel='armazem' and ativo limit 1) arm,
  (select id from funcionarios f where f.empresa_id=e.id and papel='operador_terreno' and ativo limit 1) ter,
  (select c.id from clientes c where not exists (select 1 from funcionarios f where f.id=c.id) limit 1) cli
 from empresas e where e.estado='aprovada' limit 1;
create temp table t_r (n serial, passo text, resultado text) on commit drop;
create temp table t_v (k text primary key, v text) on commit drop;
grant all on t_a, t_r, t_v to authenticated; grant usage on sequence t_r_n_seq to authenticated;
delete from sessoes_empresa where user_id in (select op from t_a union select arm from t_a union select ter from t_a);
insert into sessoes_empresa(user_id, empresa_id, valida_ate) select x, (select emp from t_a), now()+interval '1 hour' from (select op x from t_a union all select arm from t_a union all select ter from t_a) s;
set local role authenticated;
do $e2e$
declare a t_a; s simulacoes; enc encomendas; r text; trab uuid;
begin
  select * into a from t_a;
  -- quem é quem
  perform set_config('request.jwt.claims', json_build_object('sub',a.cli,'role','authenticated')::text, true);
  -- 1. cliente cria e envia simulação
  begin
    insert into simulacoes (cliente_id, origem, destino, tipo_carga, descricao, quantidade, peso_kg, volume_m3)
      values (a.cli, 'Lisboa', 'São Tomé', 'Comercial', 'Teste E2E (desfeito)', 2, 120, 0.4) returning * into s;
    s := public.enviar_simulacao(s.id, a.emp);
    insert into t_r(passo,resultado) values ('1 cliente envia simulação', 'OK estado='||s.estado||' preço='||coalesce(s.preco_estimado::text,'cotação'));
    insert into t_v values ('sim', s.id::text);
  exception when others then insert into t_r(passo,resultado) values ('1 cliente envia simulação','ERRO '||sqlerrm); end;
  -- 2. outro cliente não vê a simulação; enviar duas vezes é recusado
  begin perform public.enviar_simulacao((select v::uuid from t_v where k='sim'), a.emp); insert into t_r(passo,resultado) values ('2 reenviar a mesma simulação','FALHA: aceite');
  exception when others then insert into t_r(passo,resultado) values ('2 reenviar a mesma simulação','OK recusado: '||left(sqlerrm,50)); end;
  -- 3. prestador (operador) aceita com preço
  perform set_config('request.jwt.claims', json_build_object('sub',a.op,'role','authenticated')::text, true);
  begin enc := public.aceitar_simulacao((select v::uuid from t_v where k='sim'), 350);
    insert into t_v values ('enc', enc.id::text);
    insert into t_r(passo,resultado) values ('3 prestador aceita (350 €)','OK encomenda '||enc.codigo||' estado='||enc.estado||' preço='||enc.preco_total);
  exception when others then insert into t_r(passo,resultado) values ('3 prestador aceita','ERRO '||sqlerrm); end;
  begin perform public.aceitar_simulacao((select v::uuid from t_v where k='sim'), 350); insert into t_r(passo,resultado) values ('4 aceitar outra vez (duplo clique)','FALHA: duplicou');
  exception when others then insert into t_r(passo,resultado) values ('4 aceitar outra vez (duplo clique)','OK recusado: '||left(sqlerrm,50)); end;
  -- 5. aprovação → agendamento → recolha
  begin perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'agendamento','Teste'); insert into t_r(passo,resultado) values ('5 aprovação → agendamento','OK');
  exception when others then insert into t_r(passo,resultado) values ('5 aprovação → agendamento','ERRO '||sqlerrm); end;
  begin perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'recolha','Teste'); insert into t_r(passo,resultado) values ('6 agendamento → recolha','OK');
  exception when others then insert into t_r(passo,resultado) values ('6 agendamento → recolha','ERRO '||sqlerrm); end;
  -- 7. saltar estados é recusado (recolha → expedição)
  begin perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'expedicao','Teste'); insert into t_r(passo,resultado) values ('7 saltar recolha → expedição','FALHA: aceite');
  exception when others then insert into t_r(passo,resultado) values ('7 saltar recolha → expedição','OK recusado: '||left(sqlerrm,50)); end;
  -- 8. armazém sem receção é recusado; armazém regista receção; avança
  begin perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'armazenamento','Teste'); insert into t_r(passo,resultado) values ('8 armazém sem receção','FALHA: aceite');
  exception when others then insert into t_r(passo,resultado) values ('8 armazém sem receção','OK recusado: '||left(sqlerrm,70)); end;
  perform set_config('request.jwt.claims', json_build_object('sub',a.arm,'role','authenticated')::text, true);
  begin perform public.encomenda_rececao_armazem((select v::uuid from t_v where k='enc'), 2, true, null, 'Corredor A3', null); insert into t_r(passo,resultado) values ('9 armazém regista receção (2 volumes, conferida)','OK');
  exception when others then insert into t_r(passo,resultado) values ('9 armazém regista receção','ERRO '||sqlerrm); end;
  perform set_config('request.jwt.claims', json_build_object('sub',a.op,'role','authenticated')::text, true);
  begin perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'armazenamento','Teste'); insert into t_r(passo,resultado) values ('10 recolha → armazenamento','OK');
  exception when others then insert into t_r(passo,resultado) values ('10 recolha → armazenamento','ERRO '||sqlerrm); end;
  begin perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'expedicao','Teste'); insert into t_r(passo,resultado) values ('11 armazenamento → expedição','OK');
  exception when others then insert into t_r(passo,resultado) values ('11 armazenamento → expedição','ERRO '||sqlerrm); end;
  begin perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'em_transito','Teste'); insert into t_r(passo,resultado) values ('12 em trânsito sem navio','FALHA: aceite');
  exception when others then insert into t_r(passo,resultado) values ('12 em trânsito sem navio','OK recusado: '||left(sqlerrm,60)); end;
  begin perform public.encomenda_expedicao((select v::uuid from t_v where k='enc'), 'Navio Teste', 'V001', current_date+3, current_date+20);
    perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'em_transito','Teste'); insert into t_r(passo,resultado) values ('13 navio indicado → em trânsito','OK');
  exception when others then insert into t_r(passo,resultado) values ('13 navio indicado → em trânsito','ERRO '||sqlerrm); end;
  begin perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'destino','Teste'); insert into t_r(passo,resultado) values ('14 em trânsito → destino (cria tarefa de destino)','OK');
  exception when others then insert into t_r(passo,resultado) values ('14 em trânsito → destino','ERRO '||sqlerrm); end;
  begin perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'disponivel','Teste'); insert into t_r(passo,resultado) values ('15 disponível sem processar destino','FALHA: aceite');
  exception when others then insert into t_r(passo,resultado) values ('15 disponível sem processar destino','OK recusado: '||left(sqlerrm,60)); end;
  begin perform public.encomenda_processamento_destino((select v::uuid from t_v where k='enc'), 'Conferida no destino');
    perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'disponivel','Teste'); insert into t_r(passo,resultado) values ('16 destino processado → disponível','OK');
  exception when others then insert into t_r(passo,resultado) values ('16 destino processado → disponível','ERRO '||sqlerrm); end;
  begin perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'entregue','Teste'); insert into t_r(passo,resultado) values ('17 entregar sem confirmar levantamento','FALHA: aceite');
  exception when others then insert into t_r(passo,resultado) values ('17 entregar sem confirmar levantamento','OK recusado: '||left(sqlerrm,60)); end;
  begin perform public.encomenda_levantamento((select v::uuid from t_v where k='enc'), 'CC 12345678', null);
    perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'entregue','Teste'); insert into t_r(passo,resultado) values ('18 levantamento confirmado → entregue','OK');
  exception when others then insert into t_r(passo,resultado) values ('18 levantamento confirmado → entregue','ERRO '||left(sqlerrm,120)); end;
  begin perform public.avancar_encomenda((select v::uuid from t_v where k='enc'),'cancelada','Teste'); insert into t_r(passo,resultado) values ('19 cancelar depois de entregue','FALHA: aceite');
  exception when others then insert into t_r(passo,resultado) values ('19 cancelar depois de entregue','OK recusado: '||left(sqlerrm,50)); end;
  -- 20. cliente: vê a encomenda, o histórico e a notificação; avalia
  perform set_config('request.jwt.claims', json_build_object('sub',a.cli,'role','authenticated')::text, true);
  begin insert into t_r(passo,resultado) select '20 cliente vê encomenda/histórico/notificações','OK '||(select estado from encomendas where id=(select v::uuid from t_v where k='enc'))||' · '||
      (select count(*) from encomenda_historico where encomenda_id=(select v::uuid from t_v where k='enc'))||' passos · '||
      (select count(*) from notificacoes where referencia_id=(select v::uuid from t_v where k='enc'))||' notificações';
  exception when others then insert into t_r(passo,resultado) values ('20 cliente vê','ERRO '||sqlerrm); end;
  begin perform public.avaliar_prestador((select v::uuid from t_v where k='enc'), 5, 5, 5, 5, 'Teste'); insert into t_r(passo,resultado) values ('21 cliente avalia o prestador','OK');
  exception when others then insert into t_r(passo,resultado) values ('21 cliente avalia','ERRO '||sqlerrm); end;
  -- 22. rastreio público pelo código
  begin insert into t_r(passo,resultado) select '22 rastreio público pelo código','OK '||left(public.rastrear_encomenda((select codigo from encomendas where id=(select v::uuid from t_v where k='enc')))::text,80);
  exception when others then insert into t_r(passo,resultado) values ('22 rastreio público','ERRO '||sqlerrm); end;
  select string_agg(n||'. '||passo||' → '||resultado, E'\n' order by n) into r from t_r;
  raise exception E'RELATORIO\n%', r;
end $e2e$;

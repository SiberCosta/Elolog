-- 40: consentimento do preço (00209), pagar antes de expedir e aviso ao prestador (00210), valores em formato PT (00211).
-- Corre em rollback (nada fica gravado). Atores reais: cliente, operador e armazém da empresa aprovada.
begin;
create temp table t_a on commit drop as select e.id emp,(select id from funcionarios f where f.empresa_id=e.id and papel='operador' and ativo limit 1) op,(select id from funcionarios f where f.empresa_id=e.id and papel='armazem' and ativo limit 1) arm,(select c.id from clientes c where not exists (select 1 from funcionarios f where f.id=c.id) limit 1) cli from empresas e where e.estado='aprovada' limit 1;
delete from sessoes_empresa where user_id in (select op from t_a union select arm from t_a); insert into sessoes_empresa(user_id,empresa_id,valida_ate) select op,emp,now()+interval '1 hour' from t_a union all select arm,emp,now()+interval '1 hour' from t_a;
do $t$ declare a t_a; s simulacoes; e encomendas; r text:=''; begin select * into a from t_a;
 perform set_config('request.jwt.claims', json_build_object('sub',a.cli,'role','authenticated')::text, true);
 insert into simulacoes (cliente_id,origem,destino,tipo_carga,quantidade,peso_kg,volume_m3) values (a.cli,'Lisboa','São Tomé','Comercial',2,120,0.4) returning * into s; s:=public.enviar_simulacao(s.id,a.emp);
 perform set_config('request.jwt.claims', json_build_object('sub',a.op,'role','authenticated')::text, true);
 e:=public.aceitar_simulacao(s.id, s.preco_estimado+300);
 r:=r||'notificação ao cliente: '||(select corpo from notificacoes where tipo='proposta_recebida' and user_id=a.cli order by created_at desc limit 1)||E'\n';
 perform set_config('request.jwt.claims', json_build_object('sub',a.cli,'role','authenticated')::text, true);
 e:=public.aceitar_proposta((select id from propostas where simulacao_id=s.id and estado='enviada'));
 r:=r||'aviso ao prestador: '||(select titulo from notificacoes where empresa_id=a.emp and tipo='proposta_aceite' and referencia_id=e.id)||E'\n';
 perform set_config('request.jwt.claims', json_build_object('sub',a.op,'role','authenticated')::text, true);
 perform public.avancar_encomenda(e.id,'agendamento','t'); perform public.avancar_encomenda(e.id,'recolha','t');
 perform set_config('request.jwt.claims', json_build_object('sub',a.arm,'role','authenticated')::text, true);
 perform public.encomenda_rececao_armazem(e.id,2,true,null,'A1',null);
 perform set_config('request.jwt.claims', json_build_object('sub',a.op,'role','authenticated')::text, true);
 perform public.avancar_encomenda(e.id,'armazenamento','t');
 begin perform public.avancar_encomenda(e.id,'expedicao','t'); r:=r||'sem pagamento: ACEITE (falha)'||E'\n'; exception when others then r:=r||'sem pagamento: recusado'||E'\n'; end;
 insert into pagamentos(empresa_id,encomenda_id,cliente_id,tipo,valor,moeda,estado,metodo,pago_em) values (a.emp,e.id,a.cli,'prestacao',(e.preco_total/2),'EUR','pago','teste',now());
 begin perform public.avancar_encomenda(e.id,'expedicao','t'); r:=r||'metade paga: ACEITE (falha)'||E'\n'; exception when others then r:=r||'metade paga: recusado'||E'\n'; end;
 insert into pagamentos(empresa_id,encomenda_id,cliente_id,tipo,valor,moeda,estado,metodo,pago_em) values (a.emp,e.id,a.cli,'prestacao',e.preco_total-(e.preco_total/2),'EUR','pago','teste',now());
 perform public.avancar_encomenda(e.id,'expedicao','t'); r:=r||'tudo pago: OK estado='||(select estado from encomendas where id=e.id);
 raise exception E'RELATORIO\n%', r; end $t$;
-- Resultado na base real (25/11/2026): notificação «… 2 200,00 EUR. Aceite ou recuse…»; aviso ao prestador «O cliente aceitou o preço: nova
-- encomenda …»; sem pagamento: recusado (pago 0,00 de 2 200,00 EUR); metade paga: recusado (1 100,00 de 2 200,00); tudo pago: expedicao.

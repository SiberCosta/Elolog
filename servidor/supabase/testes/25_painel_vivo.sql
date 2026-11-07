-- Testes da v101: «Painel ao vivo» (só leitura, só administração, dados reais). Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('66666666-6666-6666-6666-666666666666','equipa@elolog.pt'), ('55555555-5555-5555-5555-555555555555','cliente@x.pt');
insert into administradores_plataforma (user_id, nome) values ('66666666-6666-6666-6666-666666666666','Equipa');
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
create temp table j (d jsonb); grant all on j to authenticated;
set local session_replication_role = replica;
insert into empresas (id, nome, nif, email, estado) values ('a0000000-0000-0000-0000-000000000001','Atlântico Cargo','500000001','a@x.pt','aprovada');
insert into encomendas (codigo, id, empresa_id, origem, destino, estado, navio, viagem, partida_prevista, chegada_prevista, cliente_nome) values
  ('T1','e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Lisboa','São Tomé','em_transito','Ilhéu das Rolas','118', current_date - 5, current_date + 7, 'Ana'),
  ('T2','e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','Lisboa','São Tomé','em_transito','Ilhéu das Rolas','118', current_date - 5, current_date + 7, 'Rui'),
  ('T3','e0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','Leixões','Luanda','em_transito','Atlântico Sul','31', current_date - 20, current_date - 2, 'Sofia'),
  ('T4','e0000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','Lisboa','Praia','armazenamento',null,null,null,null,'Maria'),
  ('T5','e0000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','Lisboa','São Tomé','entregue',null,null,null,current_date - 3,'João');
insert into pagamentos (encomenda_id, empresa_id, tipo, valor, estado, pago_em) values
  ('e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','total',500,'pago', now()),
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','total',300,'pendente', null);
insert into regras_comissao (escopo, evento, tipo_valor, valor, ativa) values ('encomenda','pagamento','percentagem',8,true);
insert into faturas_plataforma (empresa_id, tipo, estado, valor, emitida_em) values ('a0000000-0000-0000-0000-000000000001','recibo','paga',49, now());
insert into entregas (encomenda_id, identificacao, pin_validado, entregue_em) values ('e0000000-0000-0000-0000-000000000005','João, CC', true, now() - interval '4 days');
insert into armazens (id, empresa_id, nome, ativo) values ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Alverca',true);
insert into recibos_armazem (encomenda_id, armazem_id, confirmado, carga_conferida, quantidade_recebida) values ('e0000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-000000000001',true,true,12);
set local session_replication_role = origin;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated","aal":"aal2"}', true);
insert into j select public.painel_vivo();
insert into r select 1, (d->'kpis'->>'comissoes_hoje')::numeric = 40 and (d->'kpis'->>'planos_hoje')::numeric = 49 and (d->'kpis'->>'receita_hoje')::numeric = 89, 'receita hoje = comissão 8 % de 500 € + plano 49 €' from j;
insert into r select 2, (d->'kpis'->>'em_curso')::int = 4, 'encomendas em curso (sem entregues nem canceladas)' from j;
insert into r select 3, (d->'kpis'->>'risco_valor')::numeric = 300 and (d->'kpis'->>'risco_pagamentos')::int = 1, 'dinheiro em risco = pagamentos pendentes' from j;
insert into r select 4, (d->'kpis'->>'atrasadas')::int = 1, 'encomendas atrasadas (chegada prevista ultrapassada)' from j;
insert into r select 5, (d->'kpis'->>'prazo_pct')::numeric = 100, 'levantada antes da chegada prevista conta no prazo' from j;
insert into r select 6, jsonb_array_length(d->'viagens') = 2, 'viagens agrupadas por navio e viagem' from j;
insert into r select 7, exists (select 1 from jsonb_array_elements(d->'viagens') v where v->>'navio' = 'Ilhéu das Rolas' and (v->>'encomendas')::int = 2), 'Ilhéu das Rolas com 2 encomendas' from j;
insert into r select 8, exists (select 1 from jsonb_array_elements(d->'viagens') v where v->>'navio' = 'Atlântico Sul' and (v->>'atrasada')::boolean), 'viagem atrasada assinalada' from j;
insert into r select 9, exists (select 1 from jsonb_array_elements(d->'portos') p where p->>'cidade' = 'São Tomé' and (p->>'n')::int = 2), 'em trânsito conta no porto de chegada' from j;
insert into r select 10, exists (select 1 from jsonb_array_elements(d->'armazens') a where a->>'nome' = 'Alverca' and (a->>'volumes')::int = 12), 'armazém com volumes guardados' from j;
insert into r select 11, jsonb_array_length(d->'recentes') = 5, 'encomendas recentes' from j;
select set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}', true);
do $$ begin perform public.painel_vivo(); insert into r values (12, false, 'cliente não abre o painel');
exception when others then insert into r values (12, true, 'cliente não abre o painel'); end $$;
reset role;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

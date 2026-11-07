-- Testes da v94: três funis e «Gargalo principal» (regras obrigatórias). Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('66666666-6666-6666-6666-666666666666','equipa@elolog.pt'), ('55555555-5555-5555-5555-555555555555','cliente@x.pt');
insert into administradores_plataforma (user_id, nome) values ('66666666-6666-6666-6666-666666666666','Equipa');
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
create temp table j (fase text, d jsonb); grant all on j to authenticated;
-- dados de teste (sem gatilhos, para montar o cenário diretamente)
set local session_replication_role = replica;
insert into empresas (id, nome, nif, email, estado) values ('a0000000-0000-0000-0000-000000000001','Prest A','500000001','a@x.pt','pendente');
insert into planos (id, nome) values ('b0000000-0000-0000-0000-000000000001','Base');
insert into simulacoes (id, origem, destino, estado, enviada_em, preco_estimado, empresa_destinatario_id) values
  ('c0000000-0000-0000-0000-000000000001','Lisboa','São Tomé','respondida', now() - interval '2 days', 1000, 'a0000000-0000-0000-0000-000000000001'),
  ('c0000000-0000-0000-0000-000000000002','Lisboa','São Tomé','enviada', now() - interval '1 day', 500, 'a0000000-0000-0000-0000-000000000001'),
  ('c0000000-0000-0000-0000-000000000003','Lisboa','São Tomé','rascunho', now(), 9999, 'a0000000-0000-0000-0000-000000000001');
insert into propostas (id, simulacao_id, empresa_id, preco, estado) values ('d0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',900,'aceite');
insert into propostas (id, simulacao_id, empresa_id, preco, estado, validade) values ('d0000000-0000-0000-0000-000000000002','c0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',450,'enviada', current_date - 1);
insert into encomendas (codigo, id, empresa_id, origem, destino, proposta_id, estado, preco_total) values
  ('T1','e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Lisboa','São Tomé','d0000000-0000-0000-0000-000000000001','entregue',900),
  ('T2','e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','Lisboa','São Tomé', null,'entregue',700);
insert into faturas (encomenda_id, empresa_id, numero, atcud, data_emissao, nif_adquirente, nif_emitente, qr_texto, tipo_documento, total, estado, registada_por) values
  ('e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','FT 1','X-1', current_date,'999999990','500000001','q','FT',900,'valida','66666666-6666-6666-6666-666666666666'),
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','FT 2','X-2', current_date,'999999990','500000001','q','FT',700,'valida','66666666-6666-6666-6666-666666666666');
insert into pagamentos (encomenda_id, empresa_id, tipo, valor, estado) values
  ('e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','prestacao',600,'pago'),
  ('e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','prestacao',300,'pendente'),
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','total',700,'pago');
insert into regras_comissao (escopo, evento, tipo_valor, valor, ativa) values ('encomenda','pagamento','percentagem',10,true);
insert into faturas_plataforma (empresa_id, tipo, estado, valor, emitida_em) values ('a0000000-0000-0000-0000-000000000001','recibo','paga',49, now());
set local session_replication_role = origin;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated","aal":"aal2"}', true);
insert into j select 'pendente', public.painel_funis(30);
reset role;
update empresas set estado = 'aprovada';
insert into subscricoes (empresa_id, plano_id, valor, estado, periodicidade, pago_em) values ('a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001',49,'ativa','mensal', now());
set local role authenticated;
insert into j select 'aprovada', public.painel_funis(30);

insert into r select 1, (d->'clientes'->'etapas'->1->>'n')::int = 0, 'regra 1: prestador não aprovado ⇒ 0 propostas' from j where fase = 'pendente';
insert into r select 2, (d->'clientes'->'etapas'->2->>'n')::int = 0 and (d->'financeiro'->'etapas'->2->>'v')::numeric = 0, 'regras 2-3: sem proposta válida ⇒ sem aceite nem contratado' from j where fase = 'pendente';
insert into r select 3, d->'gargalo'->>'funil' = 'prestadores' and d->'gargalo'->>'etapa' = 'disponiveis', 'gargalo = prestadores disponíveis' from j where fase = 'pendente';
insert into r select 4, (d->'clientes'->'etapas'->0->>'n')::int = 2, 'rascunhos não contam como simulações' from j where fase = 'aprovada';
insert into r select 5, (d->'clientes'->'etapas'->1->>'n')::int = 1, 'proposta expirada não é válida' from j where fase = 'aprovada';
insert into r select 6, (d->'financeiro'->'etapas'->2->>'v')::numeric = 900, 'valor contratado = só propostas aceites' from j where fase = 'aprovada';
insert into r select 7, (d->'financeiro'->'etapas'->3->>'v')::numeric = 900, 'regra 4: faturado só do funil (fatura válida)' from j where fase = 'aprovada';
insert into r select 8, (d->'financeiro'->'etapas'->4->>'v')::numeric = 600, 'regra 5: recebido só pagamentos confirmados' from j where fase = 'aprovada';
insert into r select 9, (d->'financeiro'->'etapas'->5->>'v')::numeric = 60, 'comissão 10 % sobre o recebido' from j where fase = 'aprovada';
insert into r select 10, (d->'financeiro'->'planos'->>'recebido')::numeric = 49 and (d->'resumo'->>'receita_comissoes')::numeric = 60, 'regra 6: planos separados das comissões' from j where fase = 'aprovada';
insert into r select 11, (d->'clientes'->'etapas'->3->'extra'->>'sem_proposta_aceite')::int = 1, 'encomenda sem proposta aceite fica fora do funil' from j where fase = 'aprovada';
insert into r select 12, (d->'prestadores'->'etapas'->3->>'n')::int = 1, 'prestador aprovado com subscrição ativa = disponível' from j where fase = 'aprovada';
insert into r select 13, d->'gargalo'->>'funil' <> 'prestadores' and d->'gargalo' ? 'acao', 'gargalo passa para a etapa com pior passagem' from j where fase = 'aprovada';
select set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}', true);
do $$ begin perform public.painel_funis(30); insert into r values (14, false, 'cliente não vê os funis');
exception when others then insert into r values (14, true, 'cliente não vê os funis'); end $$;
reset role;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select d->'gargalo' from j;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

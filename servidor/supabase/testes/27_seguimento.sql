-- Testes da v109: fluxo de nutrição com consentimento, saída automática ao aprovar e boas-vindas. Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values ('77777777-7777-7777-7777-777777777777','ana@cliente.pt'), ('88888888-8888-8888-8888-888888888888','rui@cliente.pt');
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
set local session_replication_role = replica;
insert into clientes (id, nome, email) values ('77777777-7777-7777-7777-777777777777','Ana','ana@cliente.pt'), ('88888888-8888-8888-8888-888888888888','Rui','rui@cliente.pt');
insert into empresas (id, nome, nif, email, estado) values ('a0000000-0000-0000-0000-000000000001','Atlântico Cargo','500000001','a@x.pt','aprovada');
insert into simulacoes (id, codigo, cliente_id, origem, destino, estado, empresa_destinatario_id, enviada_em) values
  ('c0000000-0000-0000-0000-000000000001','SM-1','77777777-7777-7777-7777-777777777777','Lisboa','São Tomé','respondida','a0000000-0000-0000-0000-000000000001',now()),
  ('c0000000-0000-0000-0000-000000000002','SM-2','77777777-7777-7777-7777-777777777777','Lisboa','Praia','enviada','a0000000-0000-0000-0000-000000000001',now());
insert into propostas (simulacao_id, empresa_id, preco, estado) values ('c0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001', 400, 'enviada');
set local session_replication_role = origin;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"88888888-8888-8888-8888-888888888888","role":"authenticated"}', true);
insert into r select 1, not public.seguimento_simulacao('c0000000-0000-0000-0000-000000000001', true), 'ninguém dá consentimento por uma simulação de outra pessoa';
select set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}', true);
insert into r select 2, public.seguimento_simulacao('c0000000-0000-0000-0000-000000000001', true), 'o cliente dá consentimento para a sua simulação';
insert into r select 3, public.seguimento_simulacao('c0000000-0000-0000-0000-000000000002', true), 'consentimento na 2.ª simulação';
do $$ begin perform 1 from seguimento_simulacoes; insert into r values (4, false, 'o cliente não lê a tabela de seguimento diretamente');
exception when insufficient_privilege then insert into r values (4, true, 'o cliente não lê a tabela de seguimento diretamente'); end $$;
reset role;

insert into r select 5, (select fluxo = 'nutricao' and estado = 'ativo' and proximo_envio > now() + interval '23 hours' and email = 'ana@cliente.pt'
  from seguimento_simulacoes where simulacao_id = 'c0000000-0000-0000-0000-000000000001'), 'o 1.º email fica para daqui a 1 dia';
insert into r select 6, not exists (select 1 from public.servico_seguimento_pendentes(50)), 'nada sai antes do tempo';
update seguimento_simulacoes set proximo_envio = now() - interval '1 minute';
create temp table p as select * from public.servico_seguimento_pendentes(50);
insert into r select 7, (select count(*) = 2 from p) and (select propostas = 1 and codigo = 'SM-1' from p where simulacao_id = 'c0000000-0000-0000-0000-000000000001'), 'chegada a hora, saem os 2 com o n.º de propostas';
insert into r select 8, not exists (select 1 from public.servico_seguimento_pendentes(50)), 'reservados: não saem em duplicado';
select public.servico_seguimento_marcar('c0000000-0000-0000-0000-000000000001', true);
insert into r select 9, (select passo = 1 and proximo_envio::date = (consentimento_em + interval '3 days')::date from seguimento_simulacoes where simulacao_id = 'c0000000-0000-0000-0000-000000000001'), 'depois do 1.º email, o 2.º fica para o dia 3';
select public.servico_seguimento_marcar('c0000000-0000-0000-0000-000000000002', false, 'teste');
insert into r select 10, (select passo = 0 and proximo_envio > now() + interval '50 minutes' from seguimento_simulacoes where simulacao_id = 'c0000000-0000-0000-0000-000000000002'), 'falhou o envio: tenta de novo daqui a 1 hora';

-- regra de saída: aprovou a cotação → sai da nutrição e entra nas boas-vindas
update simulacoes set estado = 'convertida' where id = 'c0000000-0000-0000-0000-000000000001';
insert into r select 11, (select fluxo = 'boas_vindas' and estado = 'ativo' and motivo like 'aprovou%' and proximo_envio <= now() from seguimento_simulacoes where simulacao_id = 'c0000000-0000-0000-0000-000000000001'), 'ao aprovar sai da nutrição e entra nas boas-vindas';
select public.servico_seguimento_marcar('c0000000-0000-0000-0000-000000000001', true);
insert into r select 12, (select estado = 'concluido' from seguimento_simulacoes where simulacao_id = 'c0000000-0000-0000-0000-000000000001'), 'boas-vindas: 1 email e termina';
-- quem aprova sem ter dado consentimento também recebe as boas-vindas (email de serviço)
set local session_replication_role = replica;
insert into simulacoes (id, codigo, cliente_id, origem, destino, estado, empresa_destinatario_id, enviada_em) values ('c0000000-0000-0000-0000-000000000003','SM-3','88888888-8888-8888-8888-888888888888','Porto','Luanda','respondida','a0000000-0000-0000-0000-000000000001',now());
set local session_replication_role = origin;
update simulacoes set estado = 'convertida' where id = 'c0000000-0000-0000-0000-000000000003';
insert into r select 13, (select fluxo = 'boas_vindas' and email = 'rui@cliente.pt' from seguimento_simulacoes where simulacao_id = 'c0000000-0000-0000-0000-000000000003'), 'boas-vindas para quem aprova sem consentimento de nutrição';
-- deixar de receber pela ligação do email
insert into r select 14, public.servico_seguimento_sair((select token from seguimento_simulacoes where simulacao_id = 'c0000000-0000-0000-0000-000000000002')), 'a ligação «deixar de receber» funciona';
insert into r select 15, (select estado = 'cancelado' from seguimento_simulacoes where simulacao_id = 'c0000000-0000-0000-0000-000000000002'), '…e não volta a receber';
insert into r select 16, not public.servico_seguimento_sair(gen_random_uuid()), 'um token inventado não faz nada';
-- cancelar a simulação também tira do fluxo
update seguimento_simulacoes set estado = 'ativo' where simulacao_id = 'c0000000-0000-0000-0000-000000000002';
update simulacoes set estado = 'cancelada' where id = 'c0000000-0000-0000-0000-000000000002';
insert into r select 17, (select estado = 'saiu' from seguimento_simulacoes where simulacao_id = 'c0000000-0000-0000-0000-000000000002'), 'cancelar a simulação tira do fluxo';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}', true);
do $$ begin perform public.servico_seguimento_pendentes(5); insert into r values (18, false, 'o cliente não chama as funções do serviço');
exception when insufficient_privilege then insert into r values (18, true, 'o cliente não chama as funções do serviço'); end $$;
reset role;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

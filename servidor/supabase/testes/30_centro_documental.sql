-- Testes da v122: Centro Documental — emissão automática, numeração por empresa, versões, imutabilidade, permissões e validação pelo QR.
-- Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated, anon, service_role;
insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111','cliente@x.pt'), ('22222222-2222-2222-2222-222222222222','admin-a@x.pt'),
  ('33333333-3333-3333-3333-333333333333','admin-b@x.pt'), ('44444444-4444-4444-4444-444444444444','fin-a@x.pt'), ('55555555-5555-5555-5555-555555555555','arm-a@x.pt');
set local session_replication_role = replica;
insert into clientes (id, nome, email, nif) values ('11111111-1111-1111-1111-111111111111','Ana Cliente','cliente@x.pt','123456789');
insert into empresas (id, nome, nif, email, estado, morada, cidade) values ('a0000000-0000-0000-0000-00000000000a','Prest A','500000010','a@x.pt','aprovada','Rua A 1','Almada'),
  ('b0000000-0000-0000-0000-00000000000b','Prest B','500000020','b@x.pt','aprovada',null,null);
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-00000000000a','Rita (A)','admin-a@x.pt','admin_empresa'),
  ('33333333-3333-3333-3333-333333333333','b0000000-0000-0000-0000-00000000000b','Nuno (B)','admin-b@x.pt','admin_empresa'),
  ('44444444-4444-4444-4444-444444444444','a0000000-0000-0000-0000-00000000000a','Filipa (fin A)','fin-a@x.pt','financeiro'),
  ('55555555-5555-5555-5555-555555555555','a0000000-0000-0000-0000-00000000000a','Pedro (arm A)','arm-a@x.pt','armazem');
insert into sessoes_empresa (user_id, empresa_id, valida_ate) select id, empresa_id, now() + interval '1 hour' from funcionarios
  where id in ('22222222-2222-2222-2222-222222222222','33333333-3333-3333-3333-333333333333','44444444-4444-4444-4444-444444444444','55555555-5555-5555-5555-555555555555');
insert into encomendas (id, codigo, empresa_id, cliente_id, origem, destino, descricao, quantidade, peso_kg, volume_m3, preco_total, estado, remetente, destinatario)
values ('e0000000-0000-0000-0000-00000000000e','ELO-TESTE-1','a0000000-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111','Almada','São Tomé','Bidões',4,120,1.25,300,'aprovacao',
  '{"nome":"Ana","telefone":"+351900000000","morada":"Rua X 5, Almada","nif":"123456789"}','{"nome":"Rui","telefone":"+239900000","morada":"Bairro Y, São Tomé"}');
set local session_replication_role = origin;
create or replace function pg_temp.como(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated', 'aal', 'aal2')::text, true) $$;
create or replace function pg_temp.falha(n int, nome text, q text) returns void language plpgsql as $$ begin execute q; insert into r values (n, false, nome);
  exception when others then insert into r values (n, true, nome); end $$;
create or replace function pg_temp.estado(p text) returns void language plpgsql as $$ begin perform set_config('elolog.transicao', 'on', true);
  update encomendas set estado = p::estado_encomenda where id = 'e0000000-0000-0000-0000-00000000000e'; perform set_config('elolog.transicao', 'off', true); end $$;
grant execute on all functions in schema pg_temp to authenticated, anon;
\set E '''e0000000-0000-0000-0000-00000000000e'''

-- 1-3) guia automática só depois da aprovação, e só uma
insert into r select 1, count(*) = 0, 'em aprovação não há guia' from documentos_emitidos;
select pg_temp.estado('agendamento');
insert into r select 2, count(*) = 1 and min(numero) = 'EL-GUI-' || extract(year from now())::int || '-000001' and min(versao) = 1, 'aprovada: guia EL-GUI-ano-000001 v1'
  from documentos_emitidos where tipo = 'guia';
select pg_temp.estado('recolha');
insert into r select 3, count(*) = 1, 'mudar de estado não duplica a guia' from documentos_emitidos where tipo = 'guia';
insert into r select 4, (dados -> 'remetente' ? 'nif') is false and dados -> 'empresa' ->> 'nome' = 'Prest A' and dados -> 'encomenda' ->> 'codigo' = 'ELO-TESTE-1'
  and length(codigo_validacao) = 24 and length(sha256) = 64, 'fotografia dos dados, código de validação e sha256' from documentos_emitidos where tipo = 'guia';
insert into r select 5, count(*) = 1, 'cliente recebe notificação' from notificacoes where user_id = '11111111-1111-1111-1111-111111111111' and tipo = 'documento_emitido';

-- 6-10) imutabilidade (mesmo para o dono da base de dados)
select pg_temp.falha(6, 'não se altera o conteúdo', $q$update documentos_emitidos set dados = '{}' where tipo = 'guia'$q$);
select pg_temp.falha(7, 'não se apaga', $q$delete from documentos_emitidos where tipo = 'guia'$q$);
select pg_temp.falha(8, 'não se apaga o histórico', $q$delete from documentos_eventos$q$);

-- permissões de leitura
set local role authenticated;
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into r select 9, count(*) = 1, 'o cliente vê a guia da sua encomenda' from documentos_emitidos;
select pg_temp.falha(10, 'o cliente não escreve na tabela', $q$insert into documentos_emitidos (empresa_id, tipo, numero, encomenda_id, referencia, dados, sha256) values ('a0000000-0000-0000-0000-00000000000a','guia','X','e0000000-0000-0000-0000-00000000000e','X','{}','x')$q$);
select pg_temp.como('33333333-3333-3333-3333-333333333333');
insert into r select 11, count(*) = 0, 'outra empresa não vê' from documentos_emitidos;
select pg_temp.falha(12, 'outra empresa não regista eventos', $q$select registar_evento_documento((select id from documentos_emitidos limit 1), 'consultado')$q$);
select pg_temp.falha(13, 'outra empresa não reemite', format($q$select reemitir_documento(%L, 'Correção de teste')$q$, (select id from (select id from documentos_emitidos) x limit 1)));
select pg_temp.como('22222222-2222-2222-2222-222222222222');
insert into r select 14, count(*) = 1, 'a empresa emissora vê' from documentos_emitidos;
select registar_evento_documento((select id from documentos_emitidos limit 1), 'impresso');
insert into r select 15, count(*) = 2, 'histórico: emitido + impresso' from documentos_eventos;

-- 16-18) correção = nova versão com o mesmo número
select pg_temp.falha(16, 'sem alterações não cria versão', format($q$select reemitir_documento(%L, 'Correção de teste')$q$, (select id from documentos_emitidos where tipo = 'guia')));
reset role; update encomendas set descricao = 'Bidões de 200 L' where id = :E; set local role authenticated; select pg_temp.como('22222222-2222-2222-2222-222222222222');
select pg_temp.falha(17, 'motivo obrigatório', format($q$select reemitir_documento(%L, '')$q$, (select id from documentos_emitidos where tipo = 'guia')));
select reemitir_documento((select id from documentos_emitidos where tipo = 'guia'), 'Descrição da carga corrigida');
insert into r select 18, count(*) = 2 and count(distinct numero) = 1 and count(*) filter (where estado = 'valido' and versao = 2) = 1
  and count(*) filter (where estado = 'substituido' and versao = 1) = 1, 'v2 com o mesmo número; v1 substituída e consultável' from documentos_emitidos where tipo = 'guia';

-- 19-20) receção: só depois de confirmada
reset role;
insert into recibos_armazem (encomenda_id, confirmado, quantidade_recebida, carga_conferida, confirmado_por) values (:E, false, 3, false, '55555555-5555-5555-5555-555555555555');
insert into r select 19, count(*) = 0, 'receção por confirmar não gera guia de receção' from documentos_emitidos where tipo = 'rececao';
update recibos_armazem set confirmado = true, confirmado_em = now(), localizacao = 'Corredor 2' where encomenda_id = :E;
insert into r select 20, count(*) = 1 and min(numero) like 'EL-REC-%-000001' and (array_agg(dados))[1] -> 'rececao' ->> 'quantidade_recebida' = '3'
  and (array_agg(dados))[1] -> 'rececao' ->> 'por' = 'Pedro (arm A)', 'receção confirmada: EL-REC com quantidade e funcionário' from documentos_emitidos where tipo = 'rececao';

-- 21-24) pagamentos: só o montante recebido; parcial e integral
insert into pagamentos (id, codigo, empresa_id, encomenda_id, cliente_id, tipo, valor, estado, metodo) values
  ('90000000-0000-0000-0000-000000000001','PAG-T1','a0000000-0000-0000-0000-00000000000a',:E,'11111111-1111-1111-1111-111111111111','prestacao',100,'pendente','MB WAY');
insert into r select 21, count(*) = 0, 'pagamento pendente não gera comprovativo' from documentos_emitidos where tipo = 'pagamento';
update pagamentos set estado = 'pago', pago_em = now() - interval '1 minute' where id = '90000000-0000-0000-0000-000000000001';
insert into r select 22, count(*) = 1 and (array_agg(dados))[1] -> 'pagamento' ->> 'estado' = 'parcial' and ((array_agg(dados))[1] -> 'pagamento' ->> 'saldo')::numeric = 200
  and ((array_agg(dados))[1] -> 'pagamento' ->> 'valor')::numeric = 100, 'pagamento parcial: 100 € recebidos, saldo 200 €' from documentos_emitidos where tipo = 'pagamento';
insert into pagamentos (id, codigo, empresa_id, encomenda_id, cliente_id, tipo, valor, estado, metodo, pago_em) values
  ('90000000-0000-0000-0000-000000000002','PAG-T2','a0000000-0000-0000-0000-00000000000a',:E,'11111111-1111-1111-1111-111111111111','prestacao',200,'pago','Multibanco', now());
insert into r select 23, count(*) = 2 and count(distinct numero) = 2 and bool_or(dados -> 'pagamento' ->> 'estado' = 'integral' and (dados -> 'pagamento' ->> 'saldo')::numeric = 0),
  'segundo pagamento: comprovativo próprio, integral, saldo 0' from documentos_emitidos where tipo = 'pagamento';

-- 24-27) quem vê os comprovativos e quem pode emitir
set local role authenticated;
select pg_temp.como('55555555-5555-5555-5555-555555555555');
insert into r select 24, count(*) filter (where tipo = 'pagamento') = 0 and count(*) filter (where tipo = 'rececao') = 1, 'armazém vê a receção mas não os pagamentos' from documentos_emitidos;
select pg_temp.falha(25, 'armazém não emite comprovativos', $q$select emitir_documento('ELO-TESTE-1', 'pagamento', 'PAG-T1')$q$);
select pg_temp.como('44444444-4444-4444-4444-444444444444');
insert into r select 26, count(*) filter (where tipo = 'pagamento') = 2, 'financeiro vê os comprovativos' from documentos_emitidos;
insert into r select 27, (emitir_documento('ELO-TESTE-1', 'pagamento', 'PAG-T1') ->> 'numero') like 'EL-RCP-%-000001', 'emitir um documento que já existe devolve o mesmo';

-- 28-31) validação pública pelo QR
reset role; create temp table c as select versao, codigo_validacao from documentos_emitidos where tipo = 'guia'; grant select on c to anon, service_role;
select pg_temp.falha(35, 'o público (anon) não chama a validação diretamente: só pela função do servidor', $q$set local role anon; select servico_validar_documento('ffffffffffffffffffffffff')$q$);
reset role; set local role service_role; select set_config('request.jwt.claims', '{"role":"service_role"}', true);
insert into r select 28, (v ->> 'encontrado')::boolean and v ->> 'numero' like 'EL-GUI-%' and (v ->> 'versao')::int = 2 and v ->> 'estado' = 'valido' and not (v ? 'dados')
  and v::text not like '%Rua X%' and v::text not like '%Ana%', 'validação: número, versão e estado, sem dados pessoais'
  from (select servico_validar_documento((select codigo_validacao from c where versao = 2)) v) x;
reset role;
insert into r select 29, (servico_validar_documento((select codigo_validacao from documentos_emitidos where tipo = 'guia' and versao = 1)) ->> 'estado') = 'substituido', 'versão antiga aparece como substituída';
insert into r select 30, (servico_validar_documento('ffffffffffffffffffffffff') ->> 'encontrado')::boolean = false and (servico_validar_documento('x'' or 1=1') ->> 'encontrado')::boolean = false, 'código errado: não encontrado';
insert into r select 31, count(*) >= 2, 'validações ficam no histórico' from documentos_eventos where acao = 'validado';

-- 32-34) logótipo do prestador; 36) o público não lê logótipos diretamente
select pg_temp.falha(36, 'anon não executa logotipo_empresa', $q$set local role anon; select logotipo_empresa('a0000000-0000-0000-0000-00000000000a')$q$);
reset role;
set local role authenticated; select pg_temp.como('22222222-2222-2222-2222-222222222222');
select pg_temp.falha(32, 'logótipo: só imagens PNG/JPEG/WebP', $q$select definir_logotipo('data:image/svg+xml;base64,PHN2Zz4=')$q$);
select definir_logotipo('data:image/png;base64,iVBORw0KGgo=');
insert into r select 33, logotipo_empresa('a0000000-0000-0000-0000-00000000000a') like 'data:image/png%', 'logótipo guardado e disponível para os documentos';
select pg_temp.como('44444444-4444-4444-4444-444444444444');
select pg_temp.falha(34, 'só o administrador muda o logótipo', $q$select definir_logotipo('data:image/png;base64,iVBORw0KGgo=')$q$);

reset role;
select n, case when ok then 'ok' else 'FALHOU' end, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as resultado from r;
rollback;

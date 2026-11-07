-- Testes da v99: revisão administrativa das encomendas diretas (comprovativo, correção, documentos adicionais, encaminhar). Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
create temp table r (n int, ok boolean, nome text); grant all on r to authenticated;
create temp table v (k text primary key, id uuid); grant all on v to authenticated;
insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111','cliente@x.pt'), ('66666666-6666-6666-6666-666666666666','equipa@elolog.pt'),
  ('22222222-2222-2222-2222-222222222222','op-a@x.pt'), ('33333333-3333-3333-3333-333333333333','op-d@x.pt');
insert into administradores_plataforma (user_id, nome) values ('66666666-6666-6666-6666-666666666666','Equipa');
set local session_replication_role = replica;
insert into empresas (id, nome, nif, email, estado) values ('a0000000-0000-0000-0000-00000000000a','Prest A','500000010','a@x.pt','aprovada'),
  ('b0000000-0000-0000-0000-00000000000b','Prest B','500000020','b@x.pt','aprovada'), ('c0000000-0000-0000-0000-00000000000c','Prest C','500000030','c@x.pt','pendente'),
  ('d0000000-0000-0000-0000-00000000000d','Prest D','500000040','d@x.pt','aprovada');
insert into planos (id, nome) values ('f0000000-0000-0000-0000-00000000000f','Base');
insert into subscricoes (empresa_id, plano_id, valor, estado, periodicidade) select e, 'f0000000-0000-0000-0000-00000000000f', 10, 'ativa', 'mensal'
  from unnest(array['a0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000b','c0000000-0000-0000-0000-00000000000c','d0000000-0000-0000-0000-00000000000d']::uuid[]) e;
insert into tarifas (empresa_id, nome, metodo, valor, origem, destino) values ('a0000000-0000-0000-0000-00000000000a','LIS-STP','peso',2,'Lisboa','São Tomé'),
  ('b0000000-0000-0000-0000-00000000000b','POR-LAD','peso',2,'Porto','Luanda');
insert into funcionarios (id, empresa_id, nome, email, papel) values ('22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-00000000000a','Op A','op-a@x.pt','operador'),
  ('33333333-3333-3333-3333-333333333333','d0000000-0000-0000-0000-00000000000d','Op D','op-d@x.pt','operador');
insert into sessoes_empresa (user_id, empresa_id, valida_ate) values ('22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-00000000000a', now() + interval '1 hour'),
  ('33333333-3333-3333-3333-333333333333','d0000000-0000-0000-0000-00000000000d', now() + interval '1 hour');
insert into documentos (id, cliente_id, categoria, nome, visibilidade, storage_path, enviado_por, verificado) values
  ('e0000000-0000-0000-0000-00000000000e','11111111-1111-1111-1111-111111111111','comprovativo','orcamento.pdf','cliente','11111111-1111-1111-1111-111111111111/orc.pdf','11111111-1111-1111-1111-111111111111',true);
set local session_replication_role = origin;

create or replace function pg_temp.como(u text) returns void language sql as $$ select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated', 'aal', 'aal2')::text, true) $$;
create or replace function pg_temp.falha(n int, nome text, q text) returns void language plpgsql as $$ begin execute q; insert into r values (n, false, nome);
  exception when others then insert into r values (n, true, nome); end $$;
grant execute on all functions in schema pg_temp to authenticated;
set local role authenticated;

-- cliente
select pg_temp.como('11111111-1111-1111-1111-111111111111');
insert into v select 'ed', (public.criar_encomenda_direta('a0000000-0000-0000-0000-00000000000a','Lisboa','São Tomé','Roupa e calçado',3,50,0.4,300,current_date+5,'e0000000-0000-0000-0000-00000000000e','Frágil')->>'id')::uuid;
reset role;
insert into auth.users (id, email) values ('44444444-4444-4444-4444-444444444444','outro@x.pt');
set local session_replication_role = replica;
insert into documentos (id, cliente_id, categoria, nome, visibilidade, storage_path, enviado_por, verificado) values
  ('e1000000-0000-0000-0000-00000000000e','11111111-1111-1111-1111-111111111111','comprovativo','fatura-pro-forma.pdf','cliente','11111111-1111-1111-1111-111111111111/pf.pdf','11111111-1111-1111-1111-111111111111',true);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.como('66666666-6666-6666-6666-666666666666');
select pg_temp.falha(1, 'não valida sem abrir o comprovativo', format($q$select public.admin_encomenda_direta(%L,'validar')$q$, (select id from v)));
select public.admin_comprovativo_visto((select id from v));
insert into r select 2, comprovativo_visto_em is not null, 'abertura do comprovativo registada' from encomendas_diretas;
select pg_temp.falha(3, 'pedido de documentos exige descrição', format($q$select public.admin_encomenda_direta(%L,'pedir_documentos','')$q$, (select id from v)));
select public.admin_encomenda_direta((select id from v), 'pedir_documentos', 'Envie a fatura pró-forma da mercadoria.');
insert into r select 4, estado = 'em_analise_admin' and pedido_documentos like 'Envie%', 'documentos pedidos (fica em análise)' from encomendas_diretas;
select pg_temp.falha(5, 'não valida com documentos por receber', format($q$select public.admin_encomenda_direta(%L,'validar')$q$, (select id from v)));
select public.admin_corrigir_encomenda_direta((select id from v), '{"valor_acordado": 280, "peso_kg": 48, "mercadoria": "Roupa"}', 'Valor confirmado com o prestador.');
insert into r select 6, valor_acordado = 280 and peso_kg = 48 and empresa_id = 'a0000000-0000-0000-0000-00000000000a', 'administração corrige dados (prestador mantém-se)' from encomendas_diretas;
insert into r select 7, coalesce(bool_or(nota like 'Dados corrigidos — %valor: 300.00 → 280%'),false), 'correção fica no histórico com antes → depois' from encomendas_diretas_historico;
select pg_temp.falha(8, 'correção que torna o prestador inelegível é recusada', format($q$select public.admin_corrigir_encomenda_direta(%L,'{"destino":"Luanda"}')$q$, (select id from v)));
select pg_temp.falha(9, 'sem alterações não regista nada', format($q$select public.admin_corrigir_encomenda_direta(%L,'{"valor_acordado":280}')$q$, (select id from v)));
-- cliente envia o documento pedido
select pg_temp.como('44444444-4444-4444-4444-444444444444');
select pg_temp.falha(10, 'outro cliente não junta documentos', format($q$select public.cliente_anexo_encomenda_direta(%L,'e1000000-0000-0000-0000-00000000000e')$q$, (select id from v)));
select pg_temp.como('11111111-1111-1111-1111-111111111111');
select public.cliente_anexo_encomenda_direta((select id from v), 'e1000000-0000-0000-0000-00000000000e', 'Pró-forma em anexo');
insert into r select 11, pedido_documentos is null, 'pedido satisfeito quando o cliente envia' from encomendas_diretas;
insert into r select 12, jsonb_array_length(public.encomendas_diretas_lista()->0->'anexos') = 1, 'anexo aparece na lista do cliente' from (select 1) x;
select pg_temp.falha(13, 'cliente não corrige dados administrativos', format($q$select public.admin_corrigir_encomenda_direta(%L,'{"valor_acordado":1}')$q$, (select id from v)));
-- validar e encaminhar num passo
select pg_temp.como('66666666-6666-6666-6666-666666666666');
select public.admin_encomenda_direta((select id from v), 'validar_enviar');
insert into r select 14, estado = 'enviada_prestador', 'validar e encaminhar ao prestador' from encomendas_diretas;
select pg_temp.falha(15, 'depois de encaminhar já não se corrige', format($q$select public.admin_corrigir_encomenda_direta(%L,'{"volumes":9}')$q$, (select id from v)));
select pg_temp.como('22222222-2222-2222-2222-222222222222');
insert into r select 16, count(*) = 1, 'prestador abre o documento adicional' from documentos where id = 'e1000000-0000-0000-0000-00000000000e';
reset role;
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

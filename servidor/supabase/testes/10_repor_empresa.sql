-- Testes da v74: repor a palavra-passe da empresa (funções de serviço). Só em base de TESTES; tudo é desfeito.
\set ON_ERROR_STOP 1
begin;
insert into empresas (id, nome, nif, email, estado) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Luso Freight, Lda','500000000','g@l.pt','aprovada');
insert into empresa_segredos values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', extensions.crypt('Antiga123', extensions.gen_salt('bf')));
create temp table r (n int, ok boolean, nome text); create temp table i (v text);
insert into r select 1, servico_empresa_reposicao('luso freight, lda','500000000', null)->>'email' = 'g@l.pt', 'encontra por nome + NIF (como no login)';
insert into r select 2, servico_empresa_reposicao('Outra','500000000', null) is null, 'nome errado não encontra';
insert into i select servico_empresa_reposicao(null, null, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')->>'impressao';
select servico_empresa_definir_senha('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Nova12345');
insert into r select 3, (select p_empresa from private.verificar_empresa('Luso Freight, Lda','500000000','Nova12345')) is not null
  and (select p_empresa from private.verificar_empresa('Luso Freight, Lda','500000000','Antiga123')) is null, 'entra com a nova, não com a antiga';
insert into r select 4, servico_empresa_reposicao(null, null, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')->>'impressao' <> (select v from i), 'código antigo deixa de valer (impressão muda)';
do $$ begin perform servico_empresa_definir_senha('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'curta'); insert into r values (5, false, 'recusa palavra-passe curta');
  exception when others then insert into r values (5, true, 'recusa palavra-passe curta'); end $$;
insert into r select 6, not has_function_privilege('anon', 'public.servico_empresa_definir_senha(uuid,text)', 'execute'), 'só a chave de serviço';
select n, case when ok then 'OK' else 'FALHOU' end as resultado, nome from r order by n;
select count(*) filter (where ok) || '/' || count(*) as total from r;
rollback;

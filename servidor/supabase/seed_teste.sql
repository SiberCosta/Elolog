-- =====================================================================
-- Elolog · DADOS DE TESTE (NÃO usar em produção)
-- Cria 1 prestador aprovado, com subscrição ativa e 2 tarifas, para o ecrã de simulação
-- do cliente devolver propostas reais. Executar no SQL Editor (corre como administrador,
-- ignora RLS) DEPOIS das migrações 0001–0011.
-- NÃO FOI EXECUTADO: se der erro, enviar a mensagem para corrigir.
-- =====================================================================
with e as (
  insert into empresas (nome, nome_comercial, nif, email, cidade, pais, estado, aprovada_em)
  values ('Transitária Teste, Lda', 'Transitária Teste', '500000001', 'geral@transitaria-teste.pt',
          'Lisboa', 'Portugal', 'aprovada', now())
  returning id
), seg as (
  -- palavra-passe da empresa (1.º passo do login): senha-empresa-teste  (só para testes!)
  insert into empresa_segredos (empresa_id, segredo_hash)
  select e.id, extensions.crypt('senha-empresa-teste', extensions.gen_salt('bf')) from e
  returning empresa_id
), s as (
  insert into subscricoes (empresa_id, plano_id, estado, periodicidade, valor, pago_em)
  select e.id, p.id, 'ativa', 'mensal', p.preco_mensal, now()
    from e, planos p where p.nome = 'Básico'
  returning empresa_id
)
insert into tarifas (empresa_id, nome, aplicacao, tipo_carga, metodo, valor, preco_minimo, origem, destino, regras)
select e.id, t.nome, 'carga', t.tipo_carga, t.metodo::metodo_cobranca, t.valor, t.minimo, t.origem, t.destino, t.regras::jsonb
  from e, (values
    ('Lisboa → Luanda (geral, por m³)', null,        'volume', 180.00, 50.00, 'Lisboa', 'Luanda', '{}'),
    ('Lisboa → Luanda (comercial, por peso)', 'Comercial', 'peso', 1.20, 60.00, 'Lisboa', 'Luanda', '{"volumetricFactor":167}')
  ) as t(nome, tipo_carga, metodo, valor, minimo, origem, destino, regras);

-- Resultado esperado de calcular_propostas('Lisboa','Luanda','Comercial', qtd 2, peso 20 kg, 0.4 m³):
--   tarifa mais específica = "comercial, por peso" → maior(20 kg; 0,4 × 167 = 66,8 kg) × 1,20 = 80,16 €

-- ---------------------------------------------------------------------
-- FUNCIONÁRIO DE TESTE DO PRESTADOR (2.º passo do login)
-- 1) Supabase → Authentication → Users → "Add user": e-mail operador@transitaria-teste.pt,
--    uma palavra-passe à escolha e "Auto Confirm User" ligado.
-- 2) Voltar aqui e executar o bloco abaixo (pode repetir-se sem problema):
do $$
declare v_uid uuid; v_emp uuid;
begin
  select id into v_uid from auth.users where email = 'operador@transitaria-teste.pt';
  if v_uid is null then
    raise notice 'Crie primeiro o utilizador operador@transitaria-teste.pt em Authentication > Users.';
    return;
  end if;
  select id into v_emp from empresas where nif = '500000001';
  insert into funcionarios (id, empresa_id, nome, email, papel)
  values (v_uid, v_emp, 'Operador Teste', 'operador@transitaria-teste.pt', 'admin_empresa')
  on conflict (id) do nothing;
  raise notice 'Funcionário de teste ligado à empresa.';
end $$;
-- Login no ecrã "Prestador": nome "Transitária Teste, Lda" · NIF 500000001 · senha "senha-empresa-teste",
-- depois o e-mail e a palavra-passe do passo 1.

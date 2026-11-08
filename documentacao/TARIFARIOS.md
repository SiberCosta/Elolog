# Regras de cobrança: centro de controlo comercial e tarifário (v114 e v115)

Fonte única de preços da Elolog. Todos os preços automáticos vêm do servidor (`private.motor_preco`), e não há regras de cálculo espalhadas pelo código do navegador.

## Quem faz o quê

| Quem | Pode |
|---|---|
| Administração Elolog (com sessão de 2 passos) | Tarifários gerais (referência e comerciais), regras de comissão, suplementos gerais. Aprovar, rejeitar, suspender, reativar ou pedir alterações às tarifas e suplementos dos prestadores. Testar o motor. Ver todo o histórico. |
| Prestador (administrador ou financeiro da empresa) | Criar tarifas e novas versões: rotas, categorias, limites mínimo e máximo, preço mínimo e máximo, validade. Submetê-las para aprovação. Desativar as suas. Ver o histórico da sua empresa. **Não** vê nem altera tarifários gerais (só os comerciais em que está associado, em leitura) nem comissões. |
| Cliente | Vê só o preço final (e a «taxa de serviço Elolog» quando a comissão é apresentada à parte). Nunca vê tarifas internas, margens nem a comissão incluída. |

## Ordem do motor de preços

1. Serviço.
2. Modalidade (peso, volume, unidade, preço fixo, contentor).
3. Origem e destino.
4. Prestador.
5. Tarifas aprovadas, dentro da validade e compatíveis com a medida (limites mínimo e máximo).
6. A mais específica (rota, categoria, serviço); sem tarifa própria, usa-se o tarifário geral **comercial** associado ao prestador.
7. Suplementos aprovados. O do prestador vale mais do que o geral da mesma natureza; a recolha conta só se houver km. Sem suplemento configurado, a recolha custa 1 € por km.
8. Comissão Elolog: a regra mais específica (prestador, modalidade, rota), depois a promocional, depois a prioridade.
9. Preço final:
   - **incluída**: o cliente paga o preço do prestador e os suplementos, e o prestador recebe esse valor menos a comissão;
   - **separada**: o cliente paga o preço do prestador, os suplementos e a taxa de serviço, e o prestador recebe o preço e os suplementos.

Sem tarifa válida, o cliente lê: «Não existe uma tarifa automática disponível. Solicite uma cotação personalizada.»

## Onde está

- **Administração**: Subscrições e faturação › Regras de cobrança.
- **Prestador**: Financeiro › Regras de cobrança.

Os dois ecrãs têm os mesmos separadores:

- Visão geral
- Tarifários gerais ELOLog
- Tarifários dos prestadores
- Tarifários de veículos
- Comissões
- Simulador de preços
- Histórico e auditoria

A administração decide; o prestador vê e submete as suas tarifas.

## Motor de busca pela descrição (v115)

Quando a descrição da carga contém o nome de uma tarifa ou uma das suas «palavras da descrição», o motor escolhe essa tarifa antes de qualquer outra. A comparação faz-se pelo início das palavras, sem acentos nem maiúsculas: «2 frigoríficos» encontra «Frigorífico», mas «frigideiras» não.

- Uma tarifa marcada **«só quando a descrição coincidir»** só entra nesses casos. Serve, por exemplo, para o preço por unidade de um artigo.
- **No servidor:** a regra está em `private.descricao_bate` e é usada por `precos_automaticos` (o simulador do cliente), pelo envio da simulação e por `simular_preco`.
- **Na simulação direta do prestador:** ao escrever a «Carga / descrição», a linha recebe a tarifação e o preço da tarifa ativa com nome igual, e há sugestões dos nomes das tarifas. Um preço mudado à mão é respeitado.
- **No centro:** a caixa «Motor de busca» mostra que regras coincidem com uma descrição ou um nome.

## Tarifários de veículos (v115)

Cada tarifa de veículo tem um tipo de veículo, uma capacidade em kg e em m³ e um preço composto por saída, preço por km e mínimo.

- Com recolha, o motor escolhe o veículo aprovado mais barato que leva o peso e o volume. Procura primeiro os do prestador e, se não houver, os gerais da Elolog.
- Se não houver nenhum, a recolha calcula-se como antes: suplemento de recolha ou 1 € por km.
- O prestador submete as suas tarifas de veículo, que ficam «por aprovar»; mudar o preço ou a capacidade volta a pedir aprovação. Só a administração cria as tarifas gerais.

## Estados e versões

- Tarifa do prestador: rascunho → por aprovar → aprovada. Também pode ficar rejeitada, com alterações pedidas, suspensa, desativada ou substituída.
- Uma tarifa aprovada **não muda de preço nem de condições**. Uma alteração cria uma nova versão (por aprovar), e a anterior continua em vigor até a nova ser aprovada; nessa altura fica «substituída».
- Num tarifário geral em vigor, mudar o preço exige um motivo e aumenta a versão.
- Uma tarifa ou um tarifário fora da validade deixam de entrar nos cálculos.

## Histórico

A tabela `tarifas_historico` regista cada criação, alteração ou decisão sobre tarifas, tarifários gerais, suplementos e comissões, com:

- o valor anterior e o novo;
- o estado anterior e o novo;
- a versão;
- o motivo;
- o utilizador, a data e a hora.

## Preço congelado

Quando uma proposta ou uma simulação é aceite, a encomenda guarda `preco_detalhe`: a tarifa e a versão usadas, os suplementos, a comissão e a forma de apresentação, o preço final e o líquido do prestador. As alterações feitas depois às tarifas não são retroativas. Só a administração da plataforma pode corrigir esta cópia.

## Segurança

- RLS em todas as tabelas novas.
- Validações em gatilhos e funções `security definer`, nunca só no formulário.
- O motor (`private.*`) não é chamável pelo navegador; o cliente usa `calcular_precos`, que devolve só o preço final.
- A administração usa `testar_preco`, que mostra todos os passos.
- O prestador vê as referências da Elolog, os comerciais a que está associado, as tarifas gerais de veículos e as comissões que se aplicam à sua empresa (`minhas_comissoes`). Não vê as regras de outros prestadores.
- Migrações: 00167 a 00175. Testes: `servidor/supabase/testes/28_tarifarios.sql` e `29_regras_cobranca.sql`.

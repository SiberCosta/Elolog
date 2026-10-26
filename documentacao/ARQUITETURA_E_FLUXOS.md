# Elolog — arquitetura funcional e regras de operação

## Perfis

- Cliente: simula, aceita propostas, acompanha encomendas, documentos e pagamentos.
- Administrador: configura a empresa, equipa, permissões e acompanha toda a operação.
- Operador administrativo: gere propostas, encomendas e exceções autorizadas.
- Operador de recolha/entrega: vê apenas serviços atribuídos, cria encomendas no terreno, recolhe assinaturas, fotografias e pagamentos autorizados.
- Armazém: confirma receção física, confere carga, regista localização e ocorrências.
- Financeiro: valida pagamentos, prestações, comprovativos e reconciliação.

## Adesão de um prestador

1. Selecionar **Criar perfil → Prestador**.
2. Preencher os dados da empresa e criar as credenciais.
3. Escolher um dos planos ativos definidos em **Administração → Planos e subscrições**.
4. Registar e confirmar o pagamento da subscrição.
5. Aguardar a validação administrativa da Elolog.
6. Depois da autorização, a subscrição fica ativa e o administrador da empresa pode criar os funcionários.

O botão de criação do perfil permanece bloqueado até existir um pagamento confirmado. Os preços, limites e funcionalidades apresentados são lidos da configuração central de planos; não existem cópias independentes no formulário. O pagamento guarda plano, valor, periodicidade, método, referência, data e identificação da empresa. A recusa administrativa suspende a subscrição; a autorização ativa-a.

O acesso do prestador exige correspondência exata entre nome da empresa, NIF, e-mail e palavra-passe do perfil registado. A empresa só avança para a autenticação do funcionário se estiver aprovada e, quando aplicável, com pagamento confirmado. A aprovação administrativa cria a primeira conta de administrador da empresa. Nenhum funcionário ou administrador é criado automaticamente durante uma tentativa de login.

As ações administrativas **Autorizar**, **Ativar** e **Reativar** utilizam a mesma rotina de ativação. Se um registo aprovado por uma versão anterior não possuir a conta inicial, ela é reparada depois da autenticação válida da empresa. No primeiro acesso, o e-mail do administrador é preenchido automaticamente e o utilizador apenas confirma a palavra-passe criada no registo.

## Fluxo principal

1. Simulação criada pelo cliente segue para análise e proposta.
2. Proposta aceite gera encomenda para aprovação operacional.
3. Encomenda aprovada segue para agendamento e recolha.
4. Recolha concluída segue para receção e confirmação no armazém.
5. Carga confirmada segue para preparação, expedição e manifesto.
6. Manifesto confirmado permite iniciar trânsito.
7. No destino, a carga fica disponível para levantamento ou entrega.
8. Assinatura ou PIN encerra o serviço e arquiva os documentos.

## Exceção: encomenda criada no terreno

A encomenda criada por operador autorizado não regressa à aprovação administrativa. O operador deve registar cliente, rota, carga, assinatura/PIN e primeiro pagamento. Depois de concluir a recolha, a encomenda entra diretamente em **Armazenamento**, aguardando confirmação física do armazém.

## Regras obrigatórias

| Transição | Condições mínimas |
| --- | --- |
| Terreno → Armazenamento | Cliente, rota, primeiro pagamento e assinatura/PIN |
| Armazenamento → Expedição | Receção confirmada e carga conferida |
| Expedição → Em trânsito | Manifesto confirmado |
| Destino → Entregue/Levantado | Identificação e assinatura/PIN |

Alterações críticas ficam registadas no histórico de auditoria. Documentos assinados e manifestos confirmados devem ser versionados, nunca substituídos silenciosamente.

## Pagamentos no terreno

O operador só pode registar numerário se tiver a permissão correspondente. Deve indicar total ou prestação, valor recebido, saldo, data, encomenda e cliente. O registo fica pendente de reconciliação financeira; o operador não pode alterar preço nem eliminar o recebimento.

## Operação real

Esta versão funciona como protótipo local persistente no navegador. Para produção são necessários API autenticada, base de dados transacional, armazenamento seguro de documentos, perfis e permissões no servidor, trilho de auditoria imutável, emissão fiscal adequada, backups e integração com pagamentos, mapas e serviços aduaneiros aplicáveis.

## Ambiente de teste limpo

Esta distribuição executa uma reinicialização única na primeira abertura da Área de Cliente. São eliminados perfis, sessões, prestadores, funcionários, simulações, propostas, encomendas, pagamentos, documentos, equipa de terreno, notificações, manifestações, declarações, pedidos e históricos anteriormente guardados neste navegador.

Os planos Básico, Profissional e Empresarial continuam disponíveis porque são configurações padrão do código. Depois da primeira limpeza, os novos registos permanecem guardados para permitir testar o fluxo completo sem a plataforma apagar os dados a cada atualização da página.

## Notificações administrativas

Todo pedido encaminhado ao administrador também cria uma notificação persistente, mesmo quando o registo já foi guardado diretamente no respetivo módulo. Estão abrangidos novos prestadores, alterações ou eliminação de dados do cliente, pedidos de subscrição, apoio à subscrição, pedidos de apoio do cliente e reclamações escaladas.

A notificação apresenta solicitante, assunto, referência e data. Ao clicar, o administrador é encaminhado para Pedidos de inscrição, Clientes, Planos e subscrições ou Apoio e reclamações, conforme a origem do pedido. Abrir a pasta diretamente não elimina a notificação; ela permanece no histórico e apenas muda para lida quando o administrador a seleciona ou utiliza “Marcar todas como lidas”.
# Módulo Financeiro do prestador

O menu simples de pagamentos foi substituído pelo módulo **Financeiro**, isolado por empresa prestadora. Inclui visão geral, tabela de preços, rotas e tarifas, serviços adicionais, armazenamento, impostos e taxas, descontos, faturação, recebimentos e histórico de alterações.

- As tarifas são guardadas por prestador e podem ser calculadas por unidade, volume, peso, W/M, contentor ou preço fixo.
- A rota, tipo de carga, validade, preço mínimo e regras avançadas fazem parte da configuração, não do HTML.
- Uma tarifa já utilizada não é alterada retroativamente: a edição inativa a anterior e cria uma nova versão auditada.
- O simulador procura primeiro a tarifa ativa mais específica para prestador, origem, destino e carga. Só usa a referência de demonstração quando a empresa ainda não configurou uma tarifa.
- A lista de propostas é dinâmica: empresas registadas aparecem quando estão autorizadas, ativas e, quando aplicável, com a subscrição paga. Se ainda não tiverem tarifa para a rota, aparecem identificadas como “A aguardar tarifa” e não podem ser selecionadas até concluírem a configuração financeira.
- Uma simulação guardada pelo cliente permanece como rascunho privado e não aumenta o indicador “Novas simulações” do prestador. Só entra no dashboard e na pasta de propostas quando existe um prestador destinatário e um registo explícito de envio. Depois de respondida ou convertida em encomenda, deixa de ser contabilizada como nova.
- Admin e Financeiro podem configurar e confirmar; Operador tem consulta limitada; Armazém não acede ao módulo.
- Recebimentos suportam pagamentos totais ou planos de prestações e apresentam o saldo da encomenda.

# Auditoria integral Elolog — registo persistente

Este ficheiro guarda o progresso da auditoria integral (website, plataforma, perfis, fluxos, segurança, mobile e PWA).
Cada fase continua a partir do ponto anterior. Não se marca como testado o que não foi testado.

## Fase 1 — 25/11/2026 (v176)

### Método

- **Plataforma:** corrida automática com Playwright (Chrome), em modo de demonstração (dados locais, sem servidor) e com os 4 perfis: administração, prestador (administrador da empresa), cliente e operador de terreno. Larguras de 1280, 820 e 390 px.
- **Inventário:** todas as entradas de menu, incluindo submenus abertos. Para cada ecrã registou-se:
  - botões, ligações, campos, formulários e tabelas;
  - elementos sem nome acessível e campos sem rótulo;
  - alvos de toque pequenos;
  - deslocamento horizontal e erros de JavaScript e de consola.
- **Interações:** cada botão visível de cada ecrã foi clicado, com verificação de reação: mudança no ecrã, janela, transferência, janela de ficheiro, nova página ou diálogo. Ações sensíveis (apagar, suspender, pagar, sair…) não foram clicadas. Os casos «sem efeito» foram revistos um a um.
- **Permissões no ecrã:** tentou-se abrir cada página de outro perfil, chamando `showPage`, `showProviderPage` e `showAdminPage`.
- **Servidor (Supabase, produção, só leitura ou com rollback):**
  - avisos de segurança;
  - leitura de todas as tabelas como visitante anónimo e como cliente;
  - bloqueios e verificação de estado nas funções críticas;
  - transições de estado das encomendas.
- **Site público:** 8 páginas a 3 larguras, com metadados, títulos, `h1`, robots, ligações internas, acessibilidade básica e erros.
- **Emails:** registos de envio, fila de emails e registos DNS (ver v175).

### Inventário de ecrãs

59 ecrãs (`section.page`) no documento da aplicação, mais 8 páginas públicas.

| Perfil | Ecrãs a que chega pelo menu ou por ações | Ecrãs com interações testadas |
|---|---|---|
| Administração | 21 `admin*` + painel + modo suporte (ecrãs do prestador em leitura) | 25 |
| Prestador | 35 | 29 |
| Cliente | 9: início, simulação, encomendas, propostas, pagamentos, documentos, apoio, perfil, rastreio | 8 |
| Operador de terreno | 1 no menu (`providerFieldTeam`) + ligações internas | 9 |
| Site público | inicio, simulador, legal, seguimento, validar, index, 404, entrada na app | 8 |

Os mapas «menu → ecrã» de cada perfil estão em `ferramentas/auditoria-integral/alcance.json`.

### Matriz de cobertura (interações)

| Perfil | Pares ecrã/botão | Funciona | Sem efeito (justificado) | Não testado |
|---|---|---|---|---|
| Cliente | 34 | 28 | 0 | 6 (pagar, eliminar conta, dependem de contexto) |
| Operador de terreno | 52 | 47 | 0 | 5 (fotografia e envio sem serviço aberto) |
| Prestador | 170 | 132 | 5 | 33 (ações sensíveis ou que precisam de uma encomenda/tab aberta) |
| Administração | 97 | 86 | 2 | 9 |
| **Total** | **353** | **293 (83 %)** | **7 (2 %)** | **53 (15 %)** |

Notas sobre a matriz:
- Os 8 filtros de etapa do «Quadro de encomendas» e o «Guardar» da ficha de cliente foram confirmados à mão; contam em «Funciona».
- «Sem efeito (justificado)»: filtros que já estavam ativos («Todas», «Pendentes», «Hoje», «Visão geral»).
- **Botões decorativos ou sem ação encontrados: 0.**

### Outros resultados

- **Mobile, tablet e desktop:** 0 ecrãs com deslocamento horizontal e 0 erros de JavaScript, nos 4 perfis e nas 3 larguras. Regressão no fim: 363 aberturas de ecrã, sem erros.
- **Acessibilidade básica:** 0 botões ou ligações sem nome acessível e 0 campos sem rótulo nos ecrãs dos 4 perfis. Os 2 casos do site público eram falsos positivos (usam `aria-labelledby` e `alt` na imagem).
  - Alvos de toque: no centro de comando havia 20 controlos entre 24 e 30 px (períodos, ordenação, ligações). Cumprem o mínimo do WCAG 2.2 (24 px), mas foram aumentados no telemóvel.
- **Site público:** cada página tem 1 `h1`, descrição e canónico. As páginas privadas, de seguimento e de validação têm `noindex`. Ligações internas partidas: 0.
- **PWA:**
  - manifesto válido: nome, ícones 192/512 e *maskable*, `start_url`, `scope`, `standalone`;
  - *service worker* com cache versionada (v223) e página offline.
  - Instalação, offline real e ecrã de abertura **não testados** em aparelho.

### Segurança (servidor)

| Verificação | Resultado |
|---|---|
| Leitura de tabelas como visitante anónimo | 0 tabelas com dados |
| Leitura como cliente (conta real, em rollback) | Só os seus dados: cliente, encomendas, propostas, simulações, notificações; mais planos e viagens publicadas, que são públicos |
| Funções críticas (`aceitar_proposta`, `aceitar_simulacao`, `avancar_encomenda`) | Bloqueiam a linha (`for update`) e verificam o estado: um duplo clique não duplica nem salta estados |
| `admin_registar_pedido` | Não é idempotente, mas o botão do assistente fica desativado durante o envio (`producao-1.js`) |
| `validar_empresa` (anónimo) | Bloqueio de 15 min após 5 falhas por empresa |
| Avisos do Supabase | 31 tabelas sem política (de propósito: só o servidor lhes acede); funções `SECURITY DEFINER` expostas, todas com verificação interna, e as anónimas são públicas por desenho (rastreio, site, 1.º passo do prestador); proteção contra palavras-passe divulgadas **desligada** |

### Problemas

| ID | Prioridade | Ecrã / perfil | Problema | Estado |
|---|---|---|---|---|
| A-01 | P1 | Todos | Qualquer perfil abria ecrãs de outro perfil ao chamar `showPage('adminSettings')`, `showProviderPage('providerFinanceiro')`, etc. Os dados continuavam protegidos pelo servidor, mas o ecrã abria | **Corrigido**: `app/comum/guarda-paginas.js`. Cliente: 57 → 9 ecrãs; terreno sem finanças, definições, segurança, funcionários, subscrição, relatórios nem integrações |
| A-02 | P1 | Entrada da empresa | 1.º código de entrada só era enviado depois de tocar num botão | Corrigido em v175 |
| A-03 | P2 | Registo de cliente | Sem forma de pedir outro email de confirmação | Corrigido em v175 |
| A-04 | P2 | Supabase Auth | Proteção contra palavras-passe divulgadas desligada (só existe no plano Pro) | **Corrigido na plataforma (v177)**: `app/comum/senha-segura.js` verifica no aparelho (Have I Been Pwned, k-anonimato) ao criar ou mudar palavras-passe: registo de cliente e prestador, primeiro acesso, recuperação, funcionários. O início de sessão não é verificado. Quando passar ao plano Pro, ligar também no painel |
| A-05 | P2 | Fluxo de encomenda | Uma recolha falhada não podia voltar a «Agendamento» (só cancelar) | **Corrigido (v177, migração 00208)**: «Reagendar a recolha» para administrador da empresa e operador, com motivo obrigatório (o cliente recebe-o); os serviços de recolha abertos no terreno ficam cancelados. Teste 38 |
| A-06 | P2 | Operador de terreno | Podia abrir ecrãs operacionais do prestador fora do seu menu | **Corrigido (v177)**: só abre os serviços de terreno, «Ao vivo» e o registo de encomenda no terreno (privilégio mínimo); o resto volta aos serviços com aviso |
| A-07 | P3 | Centro de comando (telemóvel) | Controlos de 24–30 px | **Corrigido**: 36–40 px abaixo de 900 px |
| A-08 | P3 | Ficha do cliente (prestador) | Sem cliente escolhido, «Guardar» só avisava com uma janela do navegador | **Corrigido (v178)**: campo e «Guardar» desativados até escolher um cliente, com indicação; aviso da plataforma em vez de `alert` |
| A-09 | P3 | Início (cliente) | «Pesquisar» com o campo vazio | Revisto: já mostrava «Indique o código da encomenda para pesquisar.» (leitura por leitor de ecrã); **melhorado (v178)**: o cursor volta ao campo |
| A-11 | P1 | PWA (todos) | O *service worker* guardava na cache do aparelho as respostas do servidor (dados pessoais lidos com sessão), que lá ficavam depois de sair | **Corrigido (v177)**: só se guardam ficheiros do próprio site; a cache antiga é apagada ao atualizar (v224) |
| A-12 | P3 | Fluxo de encomenda | `destino → entregue` estava na tabela de transições mas era sempre recusado (é obrigatório passar por «Disponível») | **Corrigido (00208)**: sai da tabela e da lista de passos |
| A-13 | P2 | Todos os botões | `componentes.js` marcava `aria-disabled="true"` num botão desativado quando aparecia no ecrã, mas não o retirava quando o botão era ativado depois; o clique ficava bloqueado | **Corrigido (v178)**: acompanha as mudanças de `disabled`. Encontrado ao corrigir A-08; na varredura dos ecrãs não havia outros casos |
| A-10 | P3 | `validar_empresa` | 5 tentativas erradas bloqueiam a empresa 15 min; um terceiro pode provocar esse bloqueio | Aceite: é a contrapartida da proteção contra força bruta |

### Não testado nesta fase (próximas fases)

- Fluxos completos com o servidor real e dados de teste: simulação → proposta → aprovação → recolha → pagamento → armazém → expedição → entrega. Não se criam dados fictícios em produção, por isso é preciso um projeto de testes (*branch* Supabase) ou contas de teste autorizadas.
- Pagamentos reais, carregamento de ficheiros reais e transferências de PDF com o servidor.
- Ações sensíveis (apagar, suspender, recusar, pagar): verificadas só pela presença de confirmação, não executadas.
- Ecrãs que dependem de uma encomenda ou tab aberta (53 pares ecrã/botão).
- PWA em aparelho (instalação, offline, atualização), teclado do telemóvel e leitor de ecrã.
- Contraste de cores (precisa de axe-core, que não está instalado neste ambiente).

### Cobertura real desta fase

- Ecrãs inventariados: 59 de 59 da aplicação e 8 de 8 públicos.
- Pares ecrã/botão: 300 de 353 testados (85 %); 53 por testar.
- Problemas encontrados: 13. Corrigidos: 12 (A-01 a A-09, A-11 a A-13). Aceite: 1 (A-10). Pendentes da fase 1: 0.

## Fase 2 — 25/11/2026 (v179): fluxo completo com o servidor real

### Método

O fluxo de ponta a ponta correu na base real **dentro de uma única transação desfeita no fim**: nada fica gravado e não há dados fictícios em produção. Ver o teste 39 (`servidor/supabase/testes/39_fluxo_completo.sql`).
- Atores reais: um cliente e o operador, o armazém e o operador de terreno da empresa aprovada.
- As sessões de empresa existem só dentro da transação.

### Resultado (22 passos)

| # | Passo | Resultado |
|---|---|---|
| 1 | Cliente cria e envia simulação | OK, preço calculado pelas tarifas (1 900 €) |
| 2 | Reenviar a mesma simulação | Recusado (correto) |
| 3 | Prestador aceita | OK, encomenda criada em «Aprovação» |
| 4 | Aceitar outra vez (duplo clique) | Recusado (correto) |
| 5–6 | Aprovação → agendamento → recolha | OK |
| 7 | Saltar recolha → expedição | Recusado (correto) |
| 8 | Armazém sem receção registada | Recusado (correto) |
| 9–11 | Receção registada pelo armazém (2 volumes, conferida) → armazenamento → expedição | OK |
| 12 | Em trânsito sem navio | Recusado (correto) |
| 13–14 | Navio indicado → em trânsito → destino (cria tarefa no destino) | OK |
| 15 | Disponível sem processar o destino | Recusado (correto) |
| 16 | Destino processado → disponível | OK |
| 17 | Entregar sem confirmar o levantamento | Recusado (correto) |
| 18 | Confirmar o levantamento só com identificação | Recusado: exige o comprovativo assinado (regra correta; o carregamento de ficheiros não é possível num teste SQL) |
| 19 | Cancelar depois de «Disponível» | Recusado (correto) |
| 20 | Cliente vê a encomenda | OK: 11 passos de histórico e 9 notificações |
| 21 | Cliente avalia antes da entrega | Recusado (correto: só depois de entregue) |
| 22 | Rastreio público pelo código | OK |

Os passos 1 a 18 e o reagendamento (teste 38) confirmam que o servidor impõe a ordem das etapas, os documentos e as confirmações de cada uma.

### Problema encontrado

| ID | Prioridade | Problema | Estado |
|---|---|---|---|
| A-14 | **P1** | Pedido de cotação ou preço acima do calculado criava a encomenda sem o cliente concordar; o cliente não tinha onde aceitar ou recusar propostas | **Corrigido (v179–v180, migração 00209 aplicada com autorização)**. Teste em rollback: abaixo do calculado → encomenda direta; acima → proposta de 7 dias e notificação; o cliente recusa → o prestador é avisado e propõe outro preço; o cliente aceita → encomenda ao preço aceite |

### Regras aprovadas e aplicadas (v180, migração 00210)

- **Pagar antes de expedir:** para passar a «Expedição», os pagamentos confirmados têm de cobrir o preço total. Só o administrador da empresa pode expedir sem pagamento, indicando o motivo (fica no histórico e na auditoria). Na ficha da encomenda, o botão passa a «Expedir sem pagamento total (indique o motivo)».
- **Aviso ao prestador:** quando o cliente aceita uma proposta de preço, o prestador recebe a notificação «O cliente aceitou o preço: nova encomenda …».
- Teste 40 em rollback, na base real:
  - sem pagamento → recusado, com «pago 0,00 de 2 200,00 EUR»;
  - metade paga → recusado;
  - tudo pago → avança para expedição;
  - o aviso ao prestador e a notificação ao cliente saem.
- 00211: os valores nas mensagens do servidor passam ao formato português («2 200,00», não «2,200.00»).

### Observações de regra de negócio (antes de v180)

- O pagamento não é exigido para avançar etapas (só nas encomendas criadas no terreno, antes do armazém). Se a Elolog quiser «pagar antes de expedir», é uma regra a acrescentar em `encomenda_falta`.
- `aceitar_proposta` não avisa o prestador. A encomenda aparece em «Aprovar pedidos», mas sem notificação.

### Pagamento em prestações (v181, migração 00212 — por aplicar)

- O cliente, ao pagar online (Multibanco ou MB WAY), escolhe «Tudo» ou «Em prestações» e indica o valor desta prestação.
- Mínimo por prestação: 25 % do total ou 10 € (o maior); a última prestação é sempre o que falta. O servidor valida (não confia no navegador).
- Cada pagamento online fica com tipo `prestacao` (se não salda) ou `total` (se salda). Avisos ao cliente e à empresa dizem quanto falta.
- Mantém-se a regra de 00210: só expede com tudo pago.
- O prestador já registava recebimentos parciais à mão («Registar recebimento» aceita valor menor e grava `prestacao`).
- Testes:
  - teste 41 em rollback na base real, com a migração dentro da transação: 9/9 (mínimo, recusa abaixo/acima, prestação, expedição bloqueada, resto, já paga, estranho sem acesso);
  - função `pagamentos`: 23/23 (inclui 4 novos de prestação);
  - Playwright com servidor simulado a 1280 e 390 px: escolha, recusa de 20 € (mínimo 50 €), envio de `valor: 60`, referência mostrada, sem erros nem overflow.
- Por fazer com autorização: aplicar 00212 e publicar a função `pagamentos` (a função nova funciona também com a base antiga quando não se envia valor).

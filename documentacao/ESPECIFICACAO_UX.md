# Elolog: especificação de experiência (v112)

Uma plataforma, três papéis, o mesmo sistema. Esta especificação junta-se ao [guia de tom](TOM_DE_VOZ.md) e à diretriz [Operação clara](OPERACAO_CLARA.md). O que aqui está marcado como **feito** já está no código; o que está marcado como **seguinte** está especificado e pronto a implementar.

## 0. Princípios (e a psicologia por trás)

| Princípio | Porque funciona | Como se vê na Elolog |
|---|---|---|
| **Dizer o que está a acontecer, não onde está o sistema** | A incerteza cria mais ansiedade do que uma má notícia dita com clareza | «A carga está no armazém a ser conferida por Marta Lopes», em vez de «Etapa 6/11» |
| **Mostrar o progresso por fases, não por passos** | O efeito de proximidade do objetivo: 2 de 4 fases motiva; 6 de 11 passos cansa | O Fluxo Vivo agrupa as 11 etapas em 4 fases: Acordo, Origem, No mar, Chegada |
| **Uma coisa de cada vez** | Escolher entre muitas opções iguais paralisa | «O seu próximo passo» no topo do menu; no máximo 2 ações à vista por linha |
| **Urgência só quando é verdade** | Um alarme constante deixa de ser ouvido | Âmbar só a partir de 48 h por pagar ou 5 dias sem movimento; nunca contadores falsos |
| **Nunca um beco sem saída** | Um ecrã vazio sem caminho parece um erro | Cada vazio diz quando muda e leva ao passo onde o trabalho está |
| **Fechar bem** | Recordamos sobretudo o pico e o fim de uma experiência | «Entregue. Obrigado por enviar com a Elolog.» |
| **Nada inventado** | A confiança perde-se à primeira data errada | Sem previsão, diz «Ainda sem previsão de chegada»; o nome de quem tratou só aparece quando está registado |

## 1. Sistema vivo (tokens)

Fonte: `app/comum/vivo.css` (componentes) e `partilhado/estilos/paleta.css` (cores). **Feito.**

| Token | Valor | Uso |
|---|---|---|
| Raios | 8, 12, 16, 22 px (`--vv-r1…r4`) | dicas · botões e campos · cartões · janelas |
| Sombra 1 | 1 px + 6 px suaves | cartões em repouso |
| Sombra 2 | 1 px + 28 px difusa | menus e dicas |
| Sombra 3 | 2 px + 56 px difusa | janelas (modais) |
| Acento por papel | cliente: verde Elolog · prestador: azul · administração: azul-claro (o âmbar fica reservado à urgência) | margem do «próximo passo», foco, marcadores (`body[data-papel]`) |
| Movimento | 0,32 s, `cubic-bezier(.2,.7,.2,1)` | entradas e mudanças de estado; desligado com «movimento reduzido» |
| Tipografia | Work Sans; 22 título de janela, 17 frase do fluxo, 15 texto, 13 apoio, 12 rótulos | sem maiúsculas decorativas, sem espaçamento de letras |

Estados de cor (um significado cada):
- **verde**: corre bem;
- **âmbar**: alguém tem de decidir, ou algo está a ficar atrasado;
- **vermelho**: atrasado ou erro;
- **cinzento**: sem dados para dizer.

## 2. Navegação universal

### 2.1 A mesma estrutura para os três papéis
1. **Topo do menu**: logótipo e quem entrou (nome e papel).
2. **O seu próximo passo** (**feito**): um cartão com a coisa mais útil a fazer agora. Toca-se e vai-se lá; no telemóvel, o menu fecha-se.
3. **Grupos do papel**: cada grupo abre-se no sítio, sem mudar de página.
4. **Sair**, sempre no fundo.

O cliente, o prestador e a administração usam o mesmo esqueleto. Só mudam os grupos e o acento de cor, por isso quem passa de um papel para outro (por exemplo, a administração em «Entrar como suporte») não precisa de reaprender nada.

### 2.2 Regras do «próximo passo» (`app/comum/navegacao-viva.js`)

| Papel | Ordem de prioridade | Exemplo de texto |
|---|---|---|
| Cliente | 1. pagamento em aberto (urgente a partir de 2 dias) → 2. encomenda em curso → 3. simular | «Regularizar um pagamento. ELO_TRAN-000226, pendente há 3 dias» |
| Prestador | aprovação → pagamento → recolha → armazém → expedição → chegada → levantamento → viagem | «1 encomenda espera a sua aprovação. Abrir e tratar» |
| Administração | clientes com apoio escalado → empresas à espera há mais de 48 h → pagamentos de subscrição → encomendas diretas → empresas à espera de validação → encomendas paradas há mais de 7 dias → apoio por responder | «2 prestadores já pagaram e esperam confirmação. Confirmar pagamentos agora» |
| Prestador sem nada | | «Tudo em dia. Veja se chegaram novas simulações» |

### 2.3 Menu que conta (**feito**, prestador)
- Cada etapa do menu (Aprovar pedidos, Programar recolhas, Receção e localização, Expedição, Em trânsito, No destino, Disponível) mostra quantas encomendas tem.
- As etapas sem encomendas ficam a 60 % de opacidade, mas nunca desaparecem: esconder opções desorienta mais do que mostrá-las calmas.
- O leitor de ecrã ouve «Programar recolhas: 1 encomenda».

### 2.4 Mudança de papel (**feito**, `app/administracao/modo-suporte.js`)
- «Entrar como suporte» pede confirmação («Vai ver a Elolog como esta empresa a vê… tudo fica registado em seu nome»).
- Depois aparece uma faixa fixa azul no topo: «Está a ver a Elolog como Atlântico Lda. Desde as 13:46…», com o botão [Voltar à administração].
- O início e o fim ficam na auditoria; ao voltar, a administração regressa a «Prestadores ativos».
- Com o servidor, a base de dados não deixa a administração entrar nos dados internos de uma empresa (regra de segurança). O modo suporte abre então em leitura, com caminhos reais: ficha da empresa, histórico, operações e pedidos de apoio.

## 3. Fluxo Vivo de Operação (`app/comum/fluxo-vivo.js`)

**Feito** nos ecrãs:
- Encomendas do cliente;
- ficha da encomenda no prestador («Atualizar estado»);
- rastreio por código;
- lista «Encomendas ativas» no início do cliente (versão compacta).

### 3.1 Anatomia
```
┌───────────────────────────────────────────────────────────────┐
│ A carga está no armazém a ser conferida por Marta Lopes.  ● Segue a bom ritmo │
│ Acordo ▬▬▬▬▬   Origem ▬▬▬▬●   No mar ─────   Chegada ─────       │
│ Concluído      Armazenamento,   Expedição,     Destino,          │
│                passo 3 de 3     Em trânsito    Disponível, …      │
│ Última atualização hoje às 08:41 por Marta Lopes.   [ Ação certa ] │
└───────────────────────────────────────────────────────────────┘
```
1. **Frase**: o que está a acontecer, em voz humana. O cliente e o prestador ouvem frases diferentes (tabela 3.3).
2. **Saúde**: um indicador com cor, calculado com dados reais (tabela 3.2). O ponto verde «respira».
3. **Quatro fases**: as concluídas a azul-claro; a atual enche-se até ao passo onde está, com um ponto que pulsa; as seguintes dizem que etapas faltam.
4. **Rodapé**: a última atualização (quando e por quem, se estiver registado), a previsão de chegada e a ação certa.

Versão compacta (listas):
- quatro traços de fase;
- o nome da etapa;
- a saúde com o ponto de cor.

### 3.2 Saúde do processo (regras exatas, por esta ordem)

| Condição | Estado | Texto |
|---|---|---|
| Encomenda cancelada | cinzento | Encomenda cancelada |
| Etapa final | verde | Concluída |
| Previsão ultrapassada há mais de 1 dia e carga ainda não chegou | vermelho | Passou da previsão de 05/11/2026 |
| Sem movimento há mais de 7 dias | vermelho | Sem movimento há 9 dias |
| Pagamento em aberto há 2 dias ou mais | âmbar | Pagamento por fazer há 3 dias |
| Sem movimento há mais de 4 dias | âmbar | Sem movimento há 5 dias |
| Previsão a menos de 2 dias e a carga ainda não saiu | âmbar | A previsão está perto e a carga ainda não saiu |
| Há previsão ou movimento | verde | Segue a bom ritmo |
| Não há nenhum dos dois | cinzento | Ainda sem previsão de chegada |

### 3.3 Frases por etapa

| Etapa | Cliente | Prestador | Ação do prestador |
|---|---|---|---|
| Simulação | Estamos a pedir preços às transportadoras para esta rota. | O cliente fez uma simulação para uma rota sua. | |
| Cotação | Já há propostas. Compare-as e escolha a que lhe serve. | O cliente espera a sua proposta de preço. | |
| Aprovação | A transportadora está a confirmar os dados da sua carga. | Confirme os dados da carga e aceite o pedido. | Rever e aceitar |
| Recolha | A recolha da carga está a ser combinada (por X). | Combine a recolha com o cliente e registe-a no terreno. | Registar a recolha |
| Pagamento | Falta confirmar o pagamento para a carga avançar. | Confirme o pagamento para a carga seguir para o armazém. | Confirmar pagamento |
| Armazenamento | A carga está no armazém a ser conferida (por X). | Confira a carga no armazém e diga onde ficou guardada. | Registar entrada no armazém |
| Expedição | A carga está a ser preparada para seguir viagem. | Feche a lista de carga e ligue-a a uma viagem. | Preparar a expedição |
| Em trânsito | A carga vai a caminho de Bissau. | Mantenha a previsão de chegada atualizada. | Atualizar a viagem |
| Destino | A carga chegou a Bissau e está a ser recebida. | Confirme a receção e o estado da carga. | Confirmar a chegada |
| Disponível | A encomenda está pronta para levantar. | Avise quem levanta e confirme a identificação. | Avisar quem levanta |
| Levantado | Entregue. Obrigado por enviar com a Elolog. | Encomenda fechada. Fica tudo no histórico. | |

«Por X» só aparece quando a última mudança registada foi para essa etapa e tem nome de quem a fez.

### 3.4 Movimento
- Ao abrir, a pista da fase atual enche-se em 0,9 s.
- O ponto atual pulsa a cada 2,4 s e o ponto verde da saúde «respira».
- Nada pisca nem treme.
- Com «movimento reduzido» no sistema, tudo fica parado.

## 4. Botões que mudam com o contexto

| Nível | Quando | Aparência | Exemplo |
|---|---|---|---|
| Normal | ação disponível, sem pressa | contorno azul-escuro | Ver estado da encomenda |
| Agora | é o passo seguinte do processo | principal | Pagar agora · Registar a recolha |
| Urgente | o mesmo passo, parado há 48 h ou mais | âmbar cheio, com «há 3 dias» e uma dica ao passar | **Regularizar agora** `há 3 dias` |

Regras:
- O botão urgente chama a atenção só duas vezes (anel que se expande) e depois fica quieto.
- O texto diz o que acontece («Regularizar agora»), nunca «Ver detalhes».
- Uma área tem no máximo um botão urgente.
- Função: `elologFluxo.acao(texto, código, "normal"|"agora"|"urgente", desde)`. **Feito** no Fluxo Vivo e no início do cliente.

**Dicas (tooltips):**
- atributo `data-dica="…"` em qualquer botão;
- aparecem ao passar o rato e ao chegar com o teclado;
- fundo azul-escuro, raio de 8 px, sombra 2, até 240 px de largura;
- dizem porquê, não o que o botão já diz.

**Janelas (modais):**
- raio de 22 px, sombra 3;
- subtítulo em letra normal, título sem rebordo de foco;
- uma frase de introdução;
- conteúdo em cartões em vez de tabelas largas;
- rodapé com «Fechar» à esquerda da ação principal;
- ações que apagam pedem um segundo toque.

## 5. Zero becos sem saída

Fonte: `app/comum/vazios-textos.js` (cerca de 100 vazios reescritos) e `app/comum/painel-vazio.js`. **Feito.**

| Tamanho | Onde | Anatomia |
|---|---|---|
| Grande | páginas e listas | ícone num círculo com órbita tracejada que roda devagar; título; quando muda; um botão |
| Compacto | dentro de cartões e painéis | ícone pequeno; título; frase; ligação sublinhada |

- O ícone escolhe-se pelo assunto: navio, dinheiro, documento, equipa, empresa, apoio, ocorrência, segurança, terreno, proposta, mensagem ou encomenda.
- Uma espera que dura mais de 15 s passa a «Está a demorar mais do que o costume», com «Tentar outra vez».

### Exemplos por painel (antes e depois)

| Painel | Antes | Depois | Caminho |
|---|---|---|---|
| Cliente | Não existem encomendas ativas neste momento. | Não tem encomendas a caminho. Quando aprovar uma proposta, acompanha aqui cada etapa da viagem. | Simular um envio |
| Cliente | Ainda não existem documentos disponíveis. | Ainda não há documentos. As faturas e os comprovativos das suas encomendas ficam aqui. | |
| Cliente | Ainda não registou encomendas diretas. | Já negociou com uma transportadora? Registe aqui a encomenda que combinou diretamente. | Registar encomenda direta |
| Prestador | Não existem novas simulações dirigidas a este prestador. | Ainda não chegaram simulações novas. Ter tarifas criadas ajuda a aparecer mais vezes. | |
| Prestador | Ainda não existem viaturas registadas. | Ainda não há viaturas. Registe-as para as atribuir às recolhas e entregas. | Adicionar viatura |
| Prestador | Ainda não existem viagens marítimas registadas. | Ainda não há viagens planeadas. Agende a próxima saída. | Agendar viagem |
| Prestador | Crie funcionários com a função Operador de recolha/entrega. | Ainda não há operadores no terreno. | Criar funcionário |
| Administração | Ainda não existem prestadores ativos. Autorize um prestador… | Ainda não há prestadores ativos. Autorize uma empresa em «Pedidos de inscrição». | Ver pedidos de inscrição |
| Administração | Sem eventos de auditoria. | Ainda sem eventos. Cada ação sensível fica registada aqui. | |
| Todos | Sem notificações operacionais. | Está tudo em dia. Quando algo precisar de si, avisamos aqui. | |

## 6. Textos por painel (antes e depois, os mais vistos)

**Cliente**

| Antes | Depois |
|---|---|
| Encomenda ELO_TRAN-000231: Armazenamento | Só falta o pagamento da encomenda ELO_TRAN-000226. O pagamento está por fazer há 3 dias. [Regularizar agora] |
| 11 círculos numerados com o nome da etapa | Fluxo Vivo com frase, saúde e 4 fases |
| Pagar | Pagar agora / Regularizar agora (a partir de 48 h) |

**Prestador**

| Antes | Depois |
|---|---|
| Menu com 9 etapas iguais | Etapas com contador; vazias discretas |
| Barra de etapas na ficha da encomenda | «Combine a recolha com o cliente e registe-a no terreno.», com «Passou da previsão de 05/11/2026» e [Registar a recolha] |
| Cobrança pendente | Há um valor por receber. Pode ser altura de lembrar o cliente. |

**Administração**

| Antes | Depois |
|---|---|
| Confirmação de pagamento da subscrição / Ver detalhes | 2 prestadores já pagaram e esperam a sua confirmação. [Confirmar pagamentos agora] |
| 7 botões por empresa | Ver empresa · Suspender prestador · Mais ações |

## 7. Implementação

| Ficheiro | O que faz |
|---|---|
| `app/comum/fluxo-vivo.js` | `elologFluxo.render(encomenda, papel)`, `.compacto()`, `.acao()`, `.saude()`, `.indice()`; substitui as barras do cliente, do prestador e do rastreio |
| `app/comum/navegacao-viva.js` | «O seu próximo passo», contadores do menu, `body[data-papel]`; `elologNavegacao.atualizar()` |
| `app/comum/vazios-textos.js` | dicionário dos vazios (acrescentar uma linha por vazio novo, só com ações reais) |
| `app/comum/painel-vazio.js` | vazios grande e compacto, etapas com nome, vigilância das esperas |
| `app/comum/vivo.css` | tokens e estilo de tudo o que está acima |

### Também feito na v112
1. Faixa de modo suporte (2.4).
2. Painel do prestador: o bloco «Como estão as encomendas» substitui «Encomendas recentes». Mostra as encomendas em curso ordenadas pela saúde (atrasadas primeiro) com o Fluxo Vivo compacto, e o subtítulo diz quantas precisam de atenção.
3. «Próximo passo» da administração com as regras do Centro de comando (tabela 2.2).
4. Notificações com o mesmo sistema dos botões:
   - cada uma termina numa ação com verbo («Tratar o pagamento», «Rever o pedido», «Juntar o documento», «Ver a encomenda»);
   - um alerta urgente por ler há 48 h ou mais fica âmbar, com «há N dias»;
   - os títulos foram reescritos: «Encomenda Recolha» passou a «A encomenda X avançou»; «Escalado: …» passou a «Ainda por tratar: …».
5. Servidor:
   - cada mudança de etapa grava quem a fez (`encomenda_historico.responsavel`, preenchido por `avancar_encomenda`);
   - a sincronização do cliente lê agora esse histórico e a data da última atualização, para que «por X», «Sem movimento há N dias» e «Última atualização» funcionem também com o servidor;
   - a ficha da operação (prestador e administração) mostra o Fluxo Vivo calculado com o mesmo histórico.

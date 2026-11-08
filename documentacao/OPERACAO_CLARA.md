# Operação clara (v110)

Diretriz para os ecrãs operacionais da Elolog: etapas, estados vazios, automações, janelas e gestão de prestadores. Completa o [guia de tom](TOM_DE_VOZ.md).

## 1. Reescrita de textos: antes e depois

### Etapas do percurso (prestador)

| Etapa | Antes | Depois (título) | Depois (o que fazer) |
|---|---|---|---|
| 4 Recolha | Agendamento e registo no terreno | Recolher a carga no cliente | Combine o dia com o cliente, vá buscar a carga e registe tudo no terreno: quem foi, em que viatura, fotografias e a assinatura de quem entregou. |
| 6 Armazenamento | Entrada e localização interna | Receber a carga no armazém | Confira a quantidade e o estado ao chegar, diga onde ficou guardada e registe qualquer dano com fotografia. |
| 7 Expedição | Viagem, contentor e lista de carga | Preparar a saída | Escolha a viagem, indique o contentor e feche a lista de carga antes da data de fecho do navio. |
| 8 Em trânsito | Acompanhamento do transporte | Acompanhar a viagem | Mantenha a previsão de chegada atualizada e registe qualquer atraso: o cliente vê o mesmo que você. |
| 9 Destino | Confirmação de chegada | Confirmar a chegada | Confirme que a carga chegou e em que estado. Depois disso, o destinatário fica a saber que a encomenda chegou. |
| 10 Disponível | Disponível para levantamento | Pronto para levantar | Diga ao cliente ou ao destinatário onde e quando pode levantar, e confirme a identificação de quem vem. |
| 11 Levantamento | Entrega e finalização | Entregar e fechar a encomenda | Registe quem levantou, recolha a assinatura e feche a encomenda. Fica tudo no histórico. |

Indicador: «ETAPA 04» e 11 pontos sem nome passam a «Etapa 4 de 11», uma barra com o nome de cada etapa e «A seguir: Pagamento».

### Estados vazios

| Ecrã | Antes | Depois | Ação |
|---|---|---|---|
| Recolha | Nada por tratar nesta etapa | Não há recolhas por fazer. Quando aprovar um pedido com recolha, ele aparece aqui para combinar o dia com o cliente. | Ver pedidos por aprovar |
| Armazenamento | Nada por tratar nesta etapa | O armazém está à espera da próxima carga. Cada carga aparece aqui assim que a recolha ficar registada. | Ver recolhas |
| Expedição | Nada por tratar nesta etapa | Nada para expedir por agora. Entretanto, confirme as próximas saídas. | Ver calendário marítimo |
| Em trânsito | Nada por tratar nesta etapa | Nenhuma carga em viagem. | Ver expedição |
| Destino | Nada por tratar nesta etapa | Nada a chegar neste momento. | Ver cargas em trânsito |
| Disponível | Nada por tratar nesta etapa | Nenhuma encomenda à espera de levantamento. | Ver chegadas |
| Levantamento | Nada por tratar nesta etapa | Nenhuma entrega por fechar. | Ver encomendas disponíveis |
| Equipa no terreno | Não existem recolhas neste estado. | Muda com o separador: «Nenhuma recolha agendada», «Nenhuma recolha em curso», «Ainda sem recolhas concluídas» | Agendar recolha |
| Aprovar pedidos | Não existem encomendas a aguardar aprovação. | Não há pedidos à espera da sua aprovação. Quando um cliente escolher a sua proposta, o pedido chega aqui. | Ver cotações recebidas |
| Pedidos de inscrição | Validação de Prestadores. Não existem pedidos de prestador. | Não há empresas à espera de validação. Quando uma transportadora pedir para entrar, o pedido aparece aqui com os documentos. | |
| Prestadores | Nenhum prestador corresponde aos filtros. | Nenhuma empresa com estes filtros. | Limpar filtros |
| Suspensos | Não existem prestadores suspensos. | Nenhuma empresa suspensa. Quando suspender um prestador, ele fica aqui até o voltar a ativar. | |
| Automação | Nenhuma ação automática executada até ao momento. | Ainda não houve nada para tratar. Quando uma regra fizer alguma coisa por si, aparece aqui. | |

### Automação

| Antes | Depois |
|---|---|
| Automação operacional / Centro inteligente | O que a Elolog faz por si |
| Motor automático ativo | A trabalhar em segundo plano |
| Executar agora | Verificar agora |
| Sincronizar pagamentos: concilia recebimentos do terreno com o registo financeiro principal. | Registar o que se recebe no terreno: quando o operador recebe um pagamento na entrega, passa-o logo para o financeiro. |
| Lembrar cobranças: cria alertas periódicos para saldos pendentes há mais de três dias. | Lembrar valores por receber: avisa-o quando um cliente tem um valor em falta há mais de 3 dias. |
| Avançar fluxo: encaminha encomendas pagas para Armazenamento. | Mandar para o armazém o que já está pago. |
| Distribuir serviços: atribui serviços sem responsável ao operador disponível com menor carga. | Distribuir serviços pela equipa: entrega cada serviço sem responsável a quem tem menos trabalho nesse momento. |
| Detetar atrasos: marca serviços que ultrapassaram o horário previsto. | Avisar quando algo se atrasa: marca o serviço que passou da hora combinada para poder ligar a tempo. |
| Controlar documentos: deteta cargas em expedição ou trânsito sem documentação associada. | Vigiar documentos em falta. |
| Atualizar viagens / Associar próximo barco / Criar alertas | Atualizar o estado das viagens / Escolher o próximo navio / Lembrar fechos de carga e chegadas |
| Ações hoje / Atenções abertas / Sincronizações | Feito por si hoje / Precisa de si / Última verificação |
| Automação concluída: 3 ação(ões). | Verifiquei tudo e tratei 3 assuntos. (ou) Verifiquei tudo: não havia nada para tratar. |
| Cobrança pendente: saldo de 120 € por regularizar. | Há um valor por receber: faltam 120 €. Pode ser altura de lembrar o cliente. |
| Documentação em falta: X está em expedição sem documento associado. | Falta um documento a esta carga: junte-o antes de a carga chegar à alfândega. |
| Serviço atrasado: ultrapassou o horário previsto. | Um serviço está atrasado: passou da hora combinada. Vale a pena ligar ao operador ou ao cliente. |

### Janelas e prestadores

| Antes | Depois |
|---|---|
| ARMAZÉM, TRANSPORTE MARÍTIMO (em maiúsculas) | Navios |
| Os navios em tempo real precisam do servidor. No modo de demonstração use o Mapa marítimo. | Aqui acompanha os navios que levam a sua carga. Esta é uma versão de demonstração, sem ligação aos navios reais. [Abrir mapa marítimo] |
| Tabela de 7 colunas, «à espera do 1.º sinal» | Um cartão por navio: estado («Com sinal» / «À espera do primeiro sinal»), destino, chegada prevista, velocidade e última posição |
| Deixar de seguir (apaga logo) | Deixar de seguir, depois «Confirmar: deixar de seguir» |
| Não foi possível ler os navios. | Não conseguimos ler os navios agora. Os navios que segue continuam guardados. [Tentar outra vez] |
| 7 botões por linha: Consultar, Redefinir palavra-passe, …, Eliminar | Ver empresa, Suspender prestador e «Mais ações» |
| Suspender (sem confirmação) | «Suspender Atlântico Cargo Lda?» Enquanto estiver suspensa, a empresa não pode trabalhar na Elolog. Pode reativá-la quando quiser. |
| 0/0 funcionários ativos, 0 faturas licenciadas | Ainda sem funcionários |
| Validar em 48 horas (parecia um filtro) | Prazo para validar: 48 horas |

## 2. Padrões de interface

**Etapa (stepper).** Uma etapa mostra, por esta ordem:
1. «Etapa N de 11»;
2. um título com verbo («Recolher a carga no cliente»);
3. uma frase com o que fazer;
4. a barra das 11 etapas (concluídas em azul-claro, a atual em azul-escuro, com o nome);
5. «A seguir: …».

No telemóvel a barra fica sem nomes; o título e «A seguir» chegam. O título da página no topo não se repete dentro do cartão.

**Estado vazio.** Tem três partes e nunca só uma frase:
1. o que se passa («Não há recolhas por fazer»);
2. quando é que isso muda («Quando aprovar um pedido com recolha…»);
3. um botão para o passo anterior do percurso, onde o trabalho está.

Moldura tracejada clara, centrado, com no máximo 520 px de largura.

**Cartão de regra (automação).**
- Um ícone da biblioteca da plataforma, nunca um símbolo solto como €, ! ou ⚓.
- Título com verbo e a frase do que faz por si.
- Interruptor com o estado escrito («Ligada» / «Desligada»).
- Regras agrupadas por assunto: Dinheiro, Encomendas e terreno, Navios. Uma regra desligada fica com fundo cinzento.

**Cartão de aviso.** Título com o facto, contexto numa frase e uma ação com verbo (ver [guia de tom](TOM_DE_VOZ.md)).

**Janela (modal).**
- Subtítulo pequeno em letra normal, título sem rebordo de foco, uma frase de introdução.
- Conteúdo em cartões em vez de tabelas largas.
- Rodapé com «Fechar» à esquerda da ação principal.
- Ações que apagam pedem um segundo toque ou uma confirmação.

**Linha de tabela com ações.**
- No máximo duas ações à vista: a mais comum e a de estado (suspender ou reativar).
- O resto vai para «Mais ações», com «Eliminar» em último e a vermelho.

## 3. Regras de código contra estados pendentes ou órfãos

1. **Toda a espera tem fim.** Uma mensagem «A carregar…» tem sempre três saídas: dados, vazio com ação, ou erro com «Tentar outra vez».
   - Rede de segurança em `app/comum/painel-vazio.js`: uma espera visível há mais de 15 s passa a «Está a demorar mais do que o costume» com «Tentar outra vez», que reabre a página ativa.
2. **Vazio desenhado no sítio.** O módulo que desenha a lista chama `elologVazio.etapa(pagina)` ou `elologVazio.terreno(tipo, separador, operador)` em vez de escrever «Sem registos.».
   - Mensagens antigas continuam a ser trocadas pelo texto exato (tabela `TXT`). Ao criar uma mensagem nova, acrescente-a lá com título, explicação e ação.
3. **Uma fonte para as etapas.** Os 11 nomes vivem em `elologVazio.ETAPAS`; o cartão de etapa só indica o número (`<span>ETAPA 06</span>`) e o resto é gerado.
4. **Erros com caminho.** `try/catch` à volta de cada leitura do servidor. O `catch` mostra o que aconteceu e um botão para repetir (exemplo: `navios()` em `producao-1.js`).
5. **Ações perigosas confirmadas.** Suspender usa `elologAlternarPrestador`; eliminar usa `openPlatformConfirmation`. Sem `alert()` para decisões.
6. **Filtros que escondem tudo** dão um estado vazio com «Limpar filtros» (`elologVazio.limparFiltros(...ids)`).
7. **Definições não se disfarçam de filtros**: um controlo que guarda uma definição tem rótulo próprio («Prazo para validar»).
8. **Números com palavras**: «2 de 3 funcionários ativos», «Ainda sem funcionários», e nunca «0/0».

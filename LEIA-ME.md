# Elolog

**Versão de 11/11/2026 (v127).** Se esta pasta tem este ficheiro, é a versão nova.

Plataforma de intermediação logística: clientes simulam e comparam propostas; transitárias gerem encomendas, equipa e cobranças; a administração Elolog valida e acompanha a rede.

## Onde está cada coisa

```
elolog/
├─ index.html           entrada: abre site/inicio.html
├─ site/                site público
│  ├─ inicio.html       página inicial
│  ├─ simulador.html    simulador de preço
│  ├─ estilos/          CSS do site (inicio-*.css, simulador-*.css)
│  └─ scripts/          JS do site (inicio-*.js, simulador-*.js)
├─ app/                 Área de Cliente (aplicação)
│  ├─ area-cliente.html página da aplicação (cliente, prestador e administração)
│  ├─ prestador.html    porta de entrada do prestador
│  ├─ administracao.html porta de entrada da administração
│  ├─ comum/            o que todos os perfis usam: login, navegação, estado, painel, servidor
│  ├─ cliente/          só do cliente
│  ├─ prestador/        só da transitária (todas as funções)
│  ├─ administracao/    só da administração Elolog
│  └─ service-worker.js, manifest.webmanifest, offline.html (aplicação instalável)
├─ partilhado/          usado pelo site e pela aplicação
│  ├─ estilos/          botões, ícones, efeitos, assistente, camada «profissional»
│  ├─ scripts/          assistente ELO, idioma (PT/EN), botões, efeitos, dados de demonstração
│  ├─ imagens/          logótipos, fotografias, ícones da aplicação
│  └─ fontes/           Work Sans
├─ servidor/supabase/   base de dados (migrations/), funções (functions/), testes/
├─ documentacao/        arquitetura, produção, incidentes, modelos legais, histórico de versões
└─ ferramentas/         compactar.cjs (JS e CSS) e compactar-sql.py (SQL)
```

Cada pasta da aplicação junta o JS e o CSS do mesmo assunto. Os pormenores estão em `app/LEIA-ME.md`, `partilhado/LEIA-ME.md` e `servidor/supabase/LEIA-ME.md`.

## Regras do código

- **Nenhum ficheiro de código passa das 200 linhas** (HTML, CSS, JS e SQL). O código está **compacto**: sem espaços nem linhas em branco a mais (feito com `ferramentas/compactar.cjs`, que usa o esbuild e só muda de linha em sítios seguros; o SQL com `ferramentas/compactar-sql.py`). A primeira linha de cada ficheiro diz para que serve.
- Partes seguidas do mesmo assunto ficam no mesmo ficheiro; só quando passam das 200 linhas há partes numeradas (`base-1.css`, `base-2.css`…), carregadas pela ordem dos números.
- O corpo das páginas maiores está em partes que se escrevem no próprio sítio (`app/comum/pagina-1…5.js`, `site/scripts/inicio-pagina-1.js`, `site/scripts/simulador-pagina-1.js`). Para mudar um texto ou um botão da página, procure-o nesses ficheiros.
- Os scripts da aplicação são **clássicos** (âmbito global, `onclick="…"` no HTML): a ordem conta. Não acrescentar `defer`, `async` nem `type="module"`.
- Os endereços de CSS e JS levam `?v=66`: mudar o número a cada versão publicada para os navegadores carregarem os ficheiros novos.

## Servidor (Supabase)

**Esta versão está ligada ao projeto «Elolog»** (`https://wcggcpdiswbzrdpwgdpb.supabase.co`, Frankfurt). O endereço e a chave pública estão em `app/comum/servidor-config.js`; a chave secreta (`service_role`) nunca vai para os ficheiros da aplicação. Instalação da base de dados: `servidor/supabase/instalar_projeto_elolog.sql` (ver «Pôr a funcionar» em `documentacao/PRODUCAO.md`).

- **Demonstração local**: acrescente `?demo=1` à morada (ex.: `app/area-cliente.html?demo=1`). Fica ativa nesse separador até o fechar (`?demo=0` desliga) e usa as contas de demonstração no navegador, sem tocar no servidor.
- **Voltar ao modo só local**: esvazie `supabaseUrl` e `supabaseAnonKey` em `servidor-config.js`.
- A biblioteca do Supabase é carregada do jsDelivr (versão fixa 2.45.4, `usarCdn: true`). Para não depender de outro site, coloque o ficheiro `supabase.js` em `app/comum/` e mude para `usarCdn: false`.

## v70 (tudo a atualizar sozinho)

- **Email:** com o painel aberto, a lista atualiza-se sozinha a cada 30 s e avisa «Novo email de …»; com o painel fechado, o menu «Email» mostra um contador vermelho de emails por ler (atualiza a cada 2 min). Ação nova `contar` na função `email-caixa`.
- **Código de confirmação ao ligar uma caixa:** ao ligar uma caixa nova (ou mudar o endereço), a plataforma envia um código de 6 dígitos para essa caixa e só guarda depois de o escrever (válido 10 minutos, máx. 8 tentativas por 10 min).
- **Cliente:** as encomendas e os pedidos enviados vêm do servidor e atualizam-se sozinhos a cada 30 s (`app/cliente/sincronizar.js`); quando o prestador muda o estado aparece um aviso («Encomenda TR-…: em trânsito»).
- **Versão nova:** a aplicação verifica a cada 5 minutos se foi publicada uma versão nova e recarrega sozinha (só quando não está a escrever nem com uma janela aberta).

## v129 (rejeitadas fecham, encomendas em todos os aparelhos, distância corrigida)

- **Encomenda rejeitada fecha mesmo**: o pagamento pendente sai de «Por receber» (fica guardado em `elolog_pagamentos_anulados`), deixa de contar em pendentes e alertas, e o Fluxo mostra «Encomenda cancelada». Corrige também as rejeitadas antes desta versão. Com servidor, rejeitar também cancela no servidor (`transitar_encomenda`).
- **Todos os aparelhos**: as encomendas da empresa no servidor aparecem no painel, nas listas e no quadro de qualquer aparelho e funcionário (telemóvel incluído), atualizadas de minuto a minuto e ao voltar à aplicação.
- **Distância da recolha**: uma morada com código postal português (0000-000) só é procurada em Portugal (antes «Campo Grande…» podia cair no Brasil: 9694 km). Se a recolha ficar a mais de 400 km do armazém mais próximo, não se cobra e pede-se a localidade e o país. A memória de moradas foi renovada para esquecer as posições erradas.
- Ficheiros: `app/prestador/encomendas-sincronizar.js` (novo); `cliente/simulacao.js`, `prestador/armazens-servidor.js`, `prestador/painel.js`, `comum/fluxo-vivo.js`. Sem migrações.

## v128 (encomendas do prestador no servidor e recolha por km)

- **Encomendas visíveis a todos**: a encomenda criada em «Simular e criar encomenda» (ou ao aceitar uma simulação revista) é gravada no servidor (`criar_encomenda_prestador`) e entra em «Aprovar pedidos» para todos os funcionários da empresa, com aviso «Nova encomenda para aprovar». Antes ficava só no navegador de quem a criou.
- **Encomendas antigas**: ao entrar, as encomendas em Aprovação que ficaram só neste navegador são enviadas uma vez (o código local impede duplicados).
- **Recolha por km**: a tarifa de recolha conta como valor × km até ao armazém mais próximo, com o preço mínimo da tarifa como piso (a mesma regra do servidor). O cálculo aparece por baixo da tarifa: «1,50 €/km × 12 km = 18,00 €». Sem morada de recolha, a recolha fica a 0 € até ser indicada.
- Servidor: migração `00187` (aplicada; acrescenta a tabela `encomendas_origem_local` e a função; não altera dados). Teste `testes/32_encomenda_prestador.sql` (10/10).
- Ficheiros: `app/prestador/encomendas-servidor.js` (novo); `app/prestador/servidor.js` mostra o nome do cliente destas encomendas.
- Ainda só locais: fotografias e documentos anexos às encomendas criadas pelo prestador.

## v127 (Fase 1: terreno ao vivo, comprovativo de entrega sem rede e integrações)

- **Serviços ao vivo** (motorista; menu Equipa e transportes e, para o operador de terreno, «Ao vivo» na barra): os serviços do dia com quem e onde, ligar, «Navegar», «Iniciar percurso» (com «Combinado até», opcional) e «Registar entrega/recolha».
- **Posição e chegada prevista**: ao iniciar o percurso, o telemóvel partilha a posição (de 30 em 30 s, com o ecrã ligado) e calcula a chegada prevista por estrada (OSRM, gratuito). Guarda-se só a última posição.
- **Alertas** (de 5 em 5 minutos, no servidor): «Atraso previsto» quando a chegada passa mais de 15 min da hora combinada (avisa a empresa e o cliente) e «Sem sinal do motorista» ao fim de 20 min sem posição (avisa a empresa). Cada alerta só uma vez.
- **Acompanhamento ao vivo** (empresa e administração): serviços em curso com chegada prevista, distância e estado (a tempo, atrasado, sem sinal), «Ver no mapa». O **cliente** vê no Início «A sua entrega está a caminho» com a hora prevista.
- **Comprovativo no terreno, sem rede**: resultado (entregue/recolhido, cliente ausente, recusado), quem recebeu, identificação, volumes conferidos, fotografias, **assinatura no ecrã**, notas, posição e hora. Sem rede fica guardado no telemóvel e segue sozinho quando houver ligação (sem duplicar).
- **Entrega concluída**: a entrega assinada no terreno passa a encomenda de «Disponível» a «Entregue» (a assinatura do terreno conta como confirmação) e emite o **Comprovativo de entrega (EL-ENT)** no Centro Documental, com quem recebeu, assinatura, posição e fotografias.
- **Integrações (webhooks)** (Empresa e configurações): endereço https://, escolha dos eventos (encomenda criada, mudança de estado, documento emitido, percurso iniciado, atraso previsto, comprovativo), segredo mostrado uma vez, evento de teste e registo dos últimos envios. Assinatura HMAC-SHA256 e até 8 tentativas.
- Servidor: migrações `00182`–`00186` (aplicadas; acrescentam tabelas e funções; a regra de tipos do Centro Documental passou a aceitar «entrega»; `encomenda_falta` e as funções do Centro Documental foram substituídas acrescentando só o caso da entrega), função `webhooks` (publicada), tarefas `elolog-terreno` e `elolog-webhooks` (só trabalham quando há serviços em curso ou eventos por enviar). Testes: `testes/31_fase1.sql` (31/31).
- Ficheiros: `app/comum/terreno-dados.js`, `terreno-motorista.js`, `terreno-vivo.js`, `integracoes.js`, `terreno.css`; Centro Documental (`centro-doc-modelo.js`, `centro-doc.js`, `centro-doc-demo.js`, `centro-doc-folha.css`); `app/prestador/menu-lateral.js`, `app/comum/acesso-por-funcao.js`.

## v126 (sem texto repetido no topo dos documentos)

- Saem do topo da guia, da receção e do comprovativo as etiquetas «Em vigor» e «Versão N»: o estado e a versão ficam só na legenda em baixo (e a marca «Substituído» continua sobre as versões antigas). Ficam no topo só os estados próprios do documento: «Pagamento parcial» / «Pago na totalidade» e «Sem diferenças» / «Diferença de N volume(s)».
- Ficheiro: `app/comum/centro-doc-modelo.js`. Sem migrações.

## v125 (documentos em cartões, Azul Atlântico e código de barras)

- **Cartões próprios**: Remetente, Destinatário (em destaque), Dados do navio, Totais de carga, Conteúdo e Percurso da carga; no comprovativo, Valor recebido, A conta, Detalhes do pagamento, Cliente e Encomenda; na receção, Totais recebidos e Armazém.
- **Azul Atlântico na estrutura**: faixa do topo com a marca Elolog e o logótipo do prestador num cartão branco, títulos dos cartões, destinatário e números críticos (volumes, peso, valor recebido). Verde, âmbar e vermelho só para estados («Em vigor», «Pagamento parcial», «Substituído», diferenças na receção).
- **Código de barras Code 128** da encomenda na guia, na receção, no comprovativo e em cada etiqueta (gerado sem bibliotecas e verificado: descodifica com o dígito de controlo certo).
- **Telemóvel e tablet**: no visualizador a folha já não encolhe; ocupa a largura e, abaixo de 700 px, os cartões empilham-se. A barra de ações fica em duas colunas no telemóvel.
- **A4 sem cortes**: se uma folha ficar mais alta do que o A4 (muitas linhas ou moradas longas), a impressão e o PDF reduzem-na proporcionalmente em vez de a cortar.
- Ficheiros: `app/comum/centro-doc-modelo.js`, `centro-doc-folha.css`, `centro-doc.css`, `centro-doc.js`, `centro-doc-pdf.js`. Sem migrações.

## v124 (guia e comprovativo redesenhados para quem os usa)

- **Guia**: lê-se como o caminho da carga. Em cima, a rota em grande (origem → destino) e a frase com modalidade, data e navio; depois os números de relance (volumes, peso, volume, valor declarado); «Sai de» e, com mais peso, «Entregar a»; «O que leva» com a tabela dos volumes; «Atenção ao manusear» quando há observações ou ocorrências; e o **percurso** em três paragens ligadas (receção, expedição, entrega), cada uma com hora, «volumes conferidos ____ de N» e assinatura.
- **Comprovativo**: diz em grande «Recebemos 150,00 €» e numa frase quem pagou, como, quando e para que encomenda; uma barra mostra quanto já está pago; «A conta» faz a soma à vista (total, pago antes, este pagamento, total pago, saldo); a nota «não é recibo nem fatura» fica no fim, em letra legível.
- **Legenda técnica** em baixo de todos os documentos, como num desenho de engenharia: documento, número, versão, folha, emissor, data, estado, código de validação com QR e, quando há correção, a linha «Revisão N» com o motivo.
- Marcas: Elolog à esquerda e o logótipo do prestador à direita. Números e códigos em letra monoespaçada. A letra Work Sans passa a ir também para a impressão.
- Ficheiros: `app/comum/centro-doc-modelo.js` (reescrito), `app/comum/centro-doc-folha.css` (novo: o estilo da folha A4 saiu de `centro-doc.css`), `app/comum/centro-doc-pdf.js`. Sem migrações.

## v123 (Centro Documental: guia, guia de receção e comprovativo, com as duas marcas)

- **Emissão automática no servidor**, só quando a etapa está confirmada: a **guia de encomenda** quando a encomenda sai da aprovação; a **guia de receção** quando o armazém confirma a receção; o **comprovativo de pagamento** quando um pagamento fica «pago» (com o valor recebido, o total pago, o saldo e «parcial» ou «integral»). O cliente recebe uma notificação.
- **Numeração própria de cada empresa**: EL-GUI-2026-000001, EL-REC-…, EL-RCP-…. **Nada se apaga nem se altera**: uma correção («Corrigir este documento», com motivo) cria a versão seguinte com o mesmo número e a anterior fica «substituída», sempre consultável e marcada no papel.
- **Duas marcas** em todos os documentos: Elolog à esquerda e o logótipo do prestador à direita (o logótipo das Configurações passa a ser guardado também no servidor; sem logótipo aparece o nome da empresa).
- **Digital e físico**: o mesmo modelo A4 serve para ver, **descarregar em PDF** e **imprimir**; a guia tem espaços para data, nome, assinatura e carimbo na receção, expedição e entrega, e **etiquetas dos volumes** (uma por volume, 4 por folha, com QR).
- **Validação pelo QR**: cada documento tem um código aleatório; `site/validar.html` mostra se é autêntico, se está em vigor ou foi substituído, sem nomes, moradas, contactos nem valores. Passa pela função `validar-documento` (limite de pedidos por IP); o público continua a executar só `validar_empresa`.
- **Centro documental** no menu de cada perfil: cliente (Pagamentos e documentos), prestador (Documentos) e administração (Conformidade e segurança). Separadores Guias, Receções, Comprovativos e Versões anteriores; pesquisa; histórico de emissão, consulta, impressão, descarga e validação; «Emitir um documento em falta» para encomendas anteriores.
- O comprovativo diz em letra visível que **não é recibo nem fatura fiscal**: o documento fiscal continua a ser emitido pelo programa certificado do prestador.
- Servidor: migrações `00180_centro_documental.sql` e `00181_centro_documental_emissao.sql` (aplicadas; só acrescentam tabelas e funções), função `validar-documento` (publicada). Testes: `testes/30_centro_documental.sql` (36/36).
- Ficheiros: `app/comum/centro-doc.js`, `centro-doc-modelo.js`, `centro-doc-pdf.js`, `centro-doc-demo.js`, `centro-doc.css`, `site/validar.html`, `site/scripts/validar.js`, `app/prestador/menu-lateral.js`.
- Bibliotecas gratuitas carregadas só quando se pede um PDF ou um QR (cdnjs): qrcode-generator 1.4.4, html2canvas 1.4.1 e jsPDF 2.5.1.

## v122 (armazéns fáceis de encontrar e validar)

- **Menu Armazém › «Armazéns e moradas»**: abre logo a secção dos armazéns (antes estava só no fim de «Empresa e configurações › Dados da empresa»).
- **Botão «Validar e guardar armazéns»** no topo da secção: procura todas as moradas no mapa e só guarda se todas forem encontradas; se alguma falhar, diz qual e não guarda nada. Mantém-se o «Validar morada» em cada armazém.
- **Na simulação direta**, quando a empresa ainda não tem armazém, aparece o botão «Adicionar armazém», que leva diretamente à secção.
- Ficheiros: `app/prestador/armazens-servidor.js`, `app/prestador/menu-lateral.js`, `app/comum/tarifarios.css`. Sem migrações.

## v121 (distância da recolha e validação dos armazéns)

- **Causa do «0 km»**: os armazéns só existiam no navegador onde foram escritos; noutro navegador, ou para outro funcionário, a simulação direta não encontrava nenhum e deixava 0 km. No servidor a Soim lda não tinha nenhum armazém gravado.
- **Corrigido**: a simulação direta e as Configurações leem os armazéns guardados no servidor (qualquer funcionário da empresa, em qualquer navegador). Se este navegador tiver armazéns que o servidor não tem, e o utilizador os puder gerir, são enviados automaticamente.
- **Sem armazém**: a distância passa a ser medida por estrada até à origem do envio, e a página diz isso («Sem armazém configurado: distância medida até à origem do envio…»), em vez de ficar em 0 km.
- **Botão «Validar morada»** em cada armazém (Configurações): procura a morada no mapa, mostra as coordenadas e a ligação «Confirmar no mapa», ou explica como corrigir. Ao alterar a morada, volta a «por validar».
- Ficheiros: `app/prestador/armazens-servidor.js`, `app/prestador/simulacao-direta.js` (texto do estado), `app/comum/tarifarios.css`. Sem migrações.

## v120 (proteção contra fuga de informação, AIS retirado, só pt-PT)

- **Política de conteúdo (CSP)** em todas as páginas HTML: o navegador só carrega scripts, estilos e ligações da própria Elolog, do Supabase do projeto e dos CDN usados (jsDelivr, cdnjs); bloqueia `<object>`, `<base>` alheio e formulários enviados para fora. Junta-se `referrer` restrito: os endereços internos (com ids de encomendas) não passam para sites externos.
- **Palavras-passe**: os campos de nova palavra-passe (funcionários e prestadores) têm `autocomplete="new-password"`, sem correção ortográfica nem maiúsculas automáticas. Nenhuma palavra-passe é guardada no navegador; os códigos dos links de email saem do endereço logo que são lidos.
- **Servidor** (migrações `00178` e `00179`, aplicadas): caminho de pesquisa fixo nas 4 funções internas que ainda não o tinham; a tarefa agendada dos navios foi retirada e `agendar_tarefas` deixou de a criar.
- **AIS retirado**: sai a função `navios-ais` (pasta apagada), a chave `AISSTREAM_API_KEY` deixa de existir na documentação e nos testes. Em «Navios em tempo real», cada navio guardado tem «Ver a posição real» (abre o VesselFinder pelo MMSI); deixou de se prometer atualização a cada 30 minutos.
- **Auditoria**: `ferramentas/auditoria.cjs` passa a verificar que todas as páginas têm CSP e referrer e que não há chave `service_role` no front-end.
- **pt-PT**: o último comentário com «senha» passou a «palavra-passe». Ficam só nomes internos da API (`p_senha`), que não se mudam para não quebrar o servidor.

## v119 (regra de trabalho e auditoria completa)

- **Regra de trabalho**: identificar → analisar → alterar → verificar → validar a página completa (`documentacao/REGRA_DE_TRABALHO.md`).
- **Auditoria automática**: `node ferramentas/auditoria.cjs` verifica a sintaxe de todo o JavaScript, ficheiros e scripts em falta, a cache do service worker, versões `?v=` misturadas, ficheiros com mais de 200 linhas e palavras do português do Brasil. Não altera nada.
- **Corrigido**: no painel do cliente, a pesquisa de encomenda tinha campos com ids repetidos (o bloco novo e o antigo usavam os mesmos); agora tem ids próprios (`cdashPesquisa`, `cdashResultado`). Em «Regras de cobrança», no telemóvel, os separadores alargavam a página para 932 px; agora deslizam dentro da página e o separador ativo fica à vista.

## v118 (Consola Elolog e código por SMS)

- **Consola Elolog**: a equipa Elolog entra em **www.elolog.pt/admin** (ou `app/area-cliente.html?acesso=administracao`). Ecrã próprio, escuro e sóbrio, sem a navegação do site, rodapé, assistente nem textos para clientes. A área de cliente deixou de mostrar a ligação «Equipa Elolog» e o aparelho já não volta sozinho ao acesso da equipa.
- **Código de entrada por SMS** (em vez de WhatsApp): o administrador da empresa escolhe email ou SMS para o número da sua ficha. O SMS usa créditos pagos da Brevo e só aparece depois de definido `SMS_REMETENTE` (ver `documentacao/CODIGO_SMS.md`).

## v117 (código de entrada por email ou WhatsApp, à escolha; substituído na v118 por SMS)

- No 3.º passo da entrada, o administrador da empresa escolhe receber o código **por email** ou **por WhatsApp** (telemóvel da ficha do funcionário). A escolha fica lembrada neste aparelho.
- O WhatsApp só aparece depois de criado o modelo de autenticação na Meta e definidos os segredos (ver `documentacao/CODIGO_WHATSAPP.md`). Cada mensagem é paga à Meta; sem isso, tudo continua por email, sem custo.
- Edge Function `recuperar-acesso` atualizada (ações `canais_codigo` e `codigo_entrada` com `canal`).

## v116 (tarifas do prestador sem aprovação, km por estrada, som, anexos, logótipo nos emails)

- **Tarifas do prestador**: as tarifas, veículos e suplementos que o prestador guarda entram logo em vigor (não dependem da administração). A Elolog continua a poder **suspender**; só ela levanta a suspensão. Alterar uma tarifa cria uma nova versão; as encomendas aceites mantêm o preço.
- **Operadores**: toda a equipa do prestador recebe as tarifas em vigor da empresa (servidor: `tarifas_ver_equipa`; aplicação: sincroniza ao entrar e ao abrir páginas).
- **Distância da recolha**: medida **por estrada** (OSRM, gratuito) desde o armazém de cada prestador. Os armazéns das Configurações são localizados no mapa e gravados no servidor (`guardar_armazens`); o simulador do cliente usa `precos_simulacao` com os km de cada prestador, validados no servidor (`km_recolha`). Armazém sem nome já não é ignorado.
- **Anexos**: sem limite fixo de fotografias e documentos; cada prestador define os seus em Configurações (vazio = sem limite).
- **Som das notificações**: aviso sonoro quando chega uma notificação nova; liga/desliga no painel de notificações.
- **Tarifas de veículos**: podem ser eliminadas (prestador as suas, administração qualquer uma); fica no histórico.
- **Emails**: logótipo servido pela função `logo-email` (PNG). As ligações dos emails passam a usar `https://elolog.pt` (o `www.elolog.pt` não tem certificado válido).
- Migrações 00176 e 00177 (aplicadas no Supabase e nos instaladores). Testes: 28 (30/30), 29 (29/29), 02 (78/78).

## v115 (Regras de cobrança no painel do prestador, motor de busca, veículos)

- **Prestador › Financeiro › Regras de cobrança**: centro de controlo comercial e tarifário com os separadores Visão geral, Tarifários gerais ELOLog, Tarifários dos prestadores, Tarifários de veículos, Comissões, Simulador de preços e Histórico e auditoria. A administração tem os mesmos separadores (Subscrições e faturação › Regras de cobrança).
- **Motor de busca**: quando a descrição da carga tem o nome de uma tarifa (ou uma «palavra da descrição»), o preço usa essa tarifa, tanto no simulador do cliente (servidor) como na simulação direta do prestador, onde a linha se preenche sozinha. Há também uma caixa de pesquisa no centro.
- **Tarifários de veículos**: custo da recolha por veículo (saída + km, mínimo, capacidade), com aprovação da Elolog.
- Migrações 00173 a 00175 (já aplicadas no Supabase e acrescentadas aos instaladores). Teste `29_regras_cobranca.sql` (20/20).

## v114 (Centro de Gestão de Tarifários, distância da recolha, funcionários)

- **Tarifários e comissões** (Administração › Subscrições e faturação): aprovar, rejeitar, suspender ou pedir alterações às tarifas e suplementos dos prestadores; tarifários gerais (referência e comerciais); regras de comissão (percentagem ou fixa, por prestador, modalidade, rota, período, promocional, incluída ou separada); histórico de alterações; teste do motor passo a passo. Ver `documentacao/TARIFARIOS.md`.
- **Fonte única de preços**: `private.motor_preco` no servidor. O simulador do cliente chama `calcular_precos`; o navegador não calcula preços. Sem tarifa válida aparece «Não existe uma tarifa automática disponível. Solicite uma cotação personalizada.»
- **Prestador**: guardar uma tarifa submete-a à Elolog (`tarifa_guardar`); só entra nas simulações depois de aprovada. Uma alteração é uma nova versão; a anterior continua em vigor até a nova ser aprovada.
- **Preço congelado**: ao aceitar uma proposta ou simulação, a encomenda guarda a cópia dos valores (`preco_detalhe`); alterações posteriores às tarifas não mudam encomendas aprovadas.
- **Distância da recolha**: tenta a morada completa, depois versões mais curtas (código postal, localidade); se não encontrar, deixa escrever os km à mão.
- **Funcionários**: as ações passaram para um menu «Ações» (já não saem da coluna); ao criar, o aviso diz exatamente que campo falta.
- Migrações 00167 a 00172 (já aplicadas no Supabase e acrescentadas aos instaladores). Testes: `testes/28_tarifarios.sql` (29/29) e `02` (78/78).

## v113 (acabamento: menu, etapas, Recolhas e Entregas)

- **Menu lateral**:
  - o cartão «O seu próximo passo» deixa espaço para a aba do item ativo (deixou de encostar);
  - quando está tudo bem passa a um estado calmo, só com um visto («Tudo em dia», «Tudo em ordem. Nada à espera de si agora»), em vez de chamar a atenção;
  - as etapas sem encomendas deixaram de ficar a cinzento (pareciam desativadas); só as que têm trabalho mostram o número.
- **Cartão de etapa**: passou a ter superfície própria (fundo branco, cantos e sombra iguais aos outros cartões), sem o rebordo curvo, e com «Etapa 6 de 11» numa etiqueta.
- **Recolhas e Entregas**:
  - os números passaram a ser os próprios filtros («Todas as recolhas 2», «Agendadas 1», «Em curso», «Concluídas» e «Com ocorrência», que só aparece quando há ocorrências);
  - sem serviços, a página vai direta ao convite para agendar, sem zeros;
  - os símbolos soltos (◷ ▶ ✓ ! ↙ ⌖ ●) foram trocados pelos ícones da plataforma;
  - o título já não se repete no computador e a descrição diz quem faz o quê;
  - um serviço sem responsável mostra «Escolha quem vai» e o botão «Escolher responsável»;
  - o estado vazio deixou de ter duas ilustrações.

## v112 (o que faltava da especificação)

- **Modo suporte a sério** (`app/administracao/modo-suporte.js`):
  - «Entrar como suporte» pede confirmação, mostra a Elolog como a empresa a vê e põe uma faixa fixa no topo com «Voltar à administração»;
  - o início e o fim ficam na auditoria;
  - com o servidor, abre em leitura com caminhos reais, porque a base de dados não deixa a administração entrar nos dados internos de uma empresa.
- **Painel do prestador**: «Como estão as encomendas» mostra as encomendas em curso ordenadas pela saúde, com as atrasadas primeiro.
- **Próximo passo da administração** com as regras do Centro de comando: apoio escalado, inscrições há mais de 48 h, pagamentos de subscrição, encomendas diretas, encomendas paradas.
- **Notificações**:
  - cada uma termina numa ação com verbo;
  - um alerta urgente por tratar há 48 h ou mais fica âmbar, com «há N dias»;
  - os títulos foram reescritos em tom humano.
- **Servidor**:
  - a sincronização do cliente lê o histórico de cada encomenda (quem mudou a etapa e quando) e a última atualização, para o Fluxo Vivo funcionar com dados reais;
  - a ficha da operação mostra o Fluxo Vivo e deixa de ter a barra repetida.

## v111 (sistema vivo: Fluxo Vivo, próximo passo, botões com urgência, zero becos sem saída)

Especificação completa por painel, com os princípios, as regras exatas e os textos antes e depois: `documentacao/ESPECIFICACAO_UX.md`.

- **Fluxo Vivo de Operação** (`app/comum/fluxo-vivo.js`), em vez das barras de 11 etapas, nas Encomendas do cliente, na ficha da encomenda do prestador e no rastreio:
  - uma frase do que está a acontecer, com quem tratou quando está registado;
  - a «saúde» calculada com a previsão, o último movimento e os pagamentos reais;
  - 4 fases com o passo atual a pulsar;
  - a ação certa.
  No início do cliente aparece a versão compacta.
- **O seu próximo passo** no topo do menu, para os três papéis (`app/comum/navegacao-viva.js`). No prestador, cada etapa do menu mostra quantas encomendas tem; as vazias ficam discretas.
- **Botões que mudam com a urgência**: um pagamento em aberto há 48 h ou mais passa de «Pagar agora» a «Regularizar agora», com «há N dias» e uma dica.
- **Zero becos sem saída**: cerca de 100 estados vazios reescritos (`app/comum/vazios-textos.js`), em dois tamanhos e com ícone, e com ação quando existe uma.
- **Tokens** de raio, sombra, movimento e acento por papel (`app/comum/vivo.css`). Com «movimento reduzido» no sistema, tudo fica parado.

## v110 (operação clara: etapas com nome, estados vazios com ação, automações, navios e prestadores)

Diretriz completa, com textos antes e depois, padrões e regras de código: `documentacao/OPERACAO_CLARA.md`.

- **Etapas do percurso**: «Etapa 4 de 11», o nome de cada etapa numa barra e «A seguir: …», em vez de 11 pontos sem nome. Os títulos das etapas dizem o que fazer («Recolher a carga no cliente», «Receber a carga no armazém»…).
- **Estados vazios**: dizem o que se passa, quando muda e levam ao passo onde está o trabalho («Não há recolhas por fazer», com o botão «Ver pedidos por aprovar»). Na equipa no terreno, o texto muda com o separador escolhido.
- **Esperas sem fim**: uma mensagem «A carregar…» parada mais de 15 s passa a «Está a demorar mais do que o costume», com o botão «Tentar outra vez».
- **Automação** («O que a Elolog faz por si»):
  - regras agrupadas (Dinheiro, Encomendas e terreno, Navios), com ícones e frases de operação;
  - o interruptor diz «Ligada» ou «Desligada»;
  - os avisos criados pelas regras falam como a equipa.
- **Navios em tempo real**: um cartão por navio (estado do sinal, destino, chegada prevista, velocidade, última posição), «Deixar de seguir» com confirmação e «Tentar outra vez» quando a leitura falha.
- **Prestadores**:
  - em cada linha só ficam à vista «Ver empresa» e «Suspender prestador»; o resto passa para «Mais ações»;
  - suspender pede confirmação e explica o efeito;
  - o prazo de validação tem rótulo próprio;
  - as janelas deixam de repetir o título e de mostrar o subtítulo em maiúsculas.

## v109 (tom humano, simulação rápida, seguimento por email com consentimento)

- **Textos e ações mais humanos** (guia em `documentacao/TOM_DE_VOZ.md`):
  - avisos do administrador em três partes: o que se passa, porque importa e uma ação concreta («Confirmar pagamentos agora», «Rever pedidos de inscrição», «Responder aos pedidos»);
  - na Área de Cliente, «Ver detalhes» passa a «Ver estado do pedido», «Pagar» a «Pagar agora» e o cartão do início fala com o cliente.
- **Simulação rápida no início da Área de Cliente**: origem, destino e «Simular agora», visíveis sem descer a página no computador e no telemóvel; leva os dois campos para o simulador completo.
- **Telemóvel**: teclado certo nos campos (código de rastreio em maiúsculas sem correção automática, valores com teclado decimal, botão «seguinte» entre campos); no site, o assistente e as traduções carregam depois da página (o simulador fica utilizável mais cedo).
- **ELO mais atento**: atalhos conforme o ecrã (no simulador: prazos e documentos; nas encomendas: desalfandegamento e «quando chega»). Respostas sobre desalfandegamento e prazos sem inventar datas nem prazos.
- **Seguimento por email (nutrição), só com consentimento**:
  - caixa «Avisar-me por email sobre este pedido» no Criar encomenda, desmarcada por omissão;
  - até 3 emails: dia 1 (propostas recebidas ou simulação guardada), dia 3 (documentos da alfândega), dia 7 (último lembrete);
  - **regra de saída automática**: ao aprovar uma cotação a pessoa sai da nutrição e recebe o email de boas-vindas e acompanhamento da carga; cancelar a simulação também a tira do fluxo;
  - «Deixar de receber» em todos os emails do seguimento (página `site/seguimento.html`);
  - base de dados: migração `00166_seguimento_simulacoes.sql` (já aplicada no servidor; teste `testes/27_seguimento.sql`, 18/18);
  - envio: Edge Function `seguimento` (já publicada), chamada de hora a hora pela tarefa `elolog-seguimento`; usa o Brevo já configurado, sem custos novos. Pausa: segredo `SEGUIMENTO_ATIVO=false`.

## v108 (Centro de comando sem repetições, sem euros, paleta de cores, posição real dos navios)

- **Cada facto aparece uma só vez no Centro de comando**:
  - frase grande: decisões à espera, navios no mar, prazo de levantamento e prestadores ativos;
  - «Atenção necessária»: a lista das decisões (sem repetir o total);
  - «Encomendas a acompanhar»: atrasos, pagamentos por confirmar e suspensões (saiu o alerta repetido «Encomendas em atraso»);
  - «Onde estão as encomendas»: o único sítio com as encomendas em curso.
  Saiu a grelha de quatro números, que repetia os blocos de baixo.
- **Sem valores em euros no Centro de comando**: saíram «Dinheiro em risco», o valor das subscrições por confirmar e os preços das simulações (passa a mostrar o volume). Os valores ficam só na área financeira (Faturação, Comissões, Pagamentos e o separador Financeiro da ficha).
- **Paleta de cores** (`partilhado/estilos/paleta.css`) e página de referência (`documentacao/paleta.html`):
  - marca, estados e neutros;
  - uma cor por área (decisões, operação, mar, rede e negócio, clientes, financeiro);
  - cada secção do Centro de comando tem a marca da sua área;
  - as decisões passam a âmbar e o vermelho fica só para erros.
- **Posição real dos navios**: no navio escolhido há a ligação «Ver a posição real»: abre a página do navio no VesselFinder quando o IMO é conhecido (vem do AIS); sem IMO, pesquisa a posição pelo nome do navio. A posição dentro da Elolog continua estimada pelas datas até ser configurada a chave gratuita do aisstream.io (`AISSTREAM_API_KEY`).

## v107 (código por email na entrada da empresa, notificações, recuperação, registo e mapa)

- **Código de 6 dígitos por email no passo de verificação do administrador da empresa**: depois do nome da empresa, NIF e palavra-passe, o administrador recebe logo um código no seu email (vale 10 minutos, só neste aparelho, máx. 5 tentativas, uso único) e entra com ele. A aplicação de autenticação continua disponível («Prefiro usar uma aplicação de autenticação»), tal como o código de reserva. Servidor: migração `00165_codigo_email_notificacoes.sql` (aplicada) e Edge Function `recuperar-acesso` (publicada, versão 20, ação nova `codigo_entrada`). Testes: `testes/26_codigo_email.sql` (13/13).
- **Erro «permission denied for table notificacoes» corrigido**: quem pode ver uma notificação já a pode marcar como lida (só a coluna `lida_em`; as regras de acesso já existiam).
- **Segurança**: retirada a permissão TRUNCATE (esvaziar tabelas) aos utilizadores com sessão e anónimos em todas as tabelas. Passava por cima das regras de acesso e a aplicação nunca a usa.
- **Recuperar a palavra-passe da empresa**:
  - «Voltar» no passo do código;
  - «Não recebeu? Enviar outro código»;
  - aviso para procurar na pasta de spam ou de promoções.
  A função passa a registar se o Brevo aceitou ou recusou cada email, e quando o nome e o NIF não coincidem com o registo (sem guardar endereços).
- **Criar perfil (prestador)**: botão «Voltar ao administrador» no passo 3 (planos), que mantém o que já foi escrito.
- **Mapa do corredor atlântico só depois de escolher um navio**: primeiro aparece a lista dos navios com carga; ao escolher um, o mapa abre centrado nele, com «Fechar o mapa».
- **Botões**: com o rato por cima, o fundo do botão principal passa também a azul-escuro (além do preenchimento), para o texto branco nunca ficar sobre branco; deixou de haver duas ondas ao clicar.

## v106 (frases no painel principal, sem receita, correções)

- **Painel principal sem valores de receita**: saíram «Receita da Elolog hoje», «Subscrições por mês» e «Recibos de subscrição». No lugar do número grande aparece uma **frase grande que muda sozinha de 7 em 7 segundos**, feita com os dados reais:
  - assuntos à espera de decisão;
  - encomendas atrasadas;
  - navios com carga Elolog;
  - encomendas em curso;
  - percentagem levantada no prazo;
  - subscrições por confirmar.

  Cada frase leva ao sítio certo. Os traços por baixo escolhem a frase. Pára com o rato ou o teclado em cima e não roda com «reduzir movimento».
- **Números ao lado**: encomendas em curso, levantadas no prazo, dinheiro em risco e prestadores ativos (com os pedidos de inscrição à espera).
- **Negócio no período**: simulações feitas, encomendas criadas, novos prestadores, novos clientes e cancelamentos. Sem «sem alteração» quando tudo está a zero, e com uma mensagem clara em vez de barras vazias quando ainda não há encomendas.
- **Erro corrigido** «invalid input syntax for type uuid: "NOT-…"»: os avisos criados no próprio navegador deixam de ser enviados ao servidor quando são marcados como lidos (só as notificações do servidor são).
- **Menu corrigido**: já não ficam duas opções ativas ao mesmo tempo (ex.: voltar ao Centro de comando deixava «Apoio e reclamações» marcado). As setas dos grupos passam a ser desenhadas (já não são «^» e «v»).
- **Apoio e reclamações**: a ilustração de «Sem pedidos em aberto» deixou de aparecer partida.

## v105 (uma só linguagem de cor, botões novos e auditoria de texto)

- **Centro de comando numa só linguagem de cor**: acabaram os painéis escuros. Tudo em superfícies claras, com o azul-escuro da Elolog para texto e ações, verde para o que está concluído e âmbar só para atrasos e risco. O mapa passou a claro (terra em trama de pontos, rotas e navios em azul).
- **Botões novos em toda a Elolog** (`partilhado/estilos/botoes-vivos.css`, carregado por último na aplicação e no site, e `partilhado/scripts/botoes-vivos.js`):
  - principal com contorno azul-escuro que se preenche da esquerda para a direita ao passar o rato;
  - secundário com contorno leve que escurece, ganha fundo suave e sobe ligeiramente;
  - confirmar (verde) e perigo (vermelho) com a mesma lógica;
  - ao carregar, o botão cede ligeiramente e nasce uma onda no ponto tocado;
  - anel de foco visível pelo teclado;
  - estado «a trabalhar» com o texto visível e um círculo a rodar;
  - respeita a opção «reduzir movimento» do sistema.
  Só muda o aspeto: nenhum botão mudou de ação.
- **Auditoria de texto e visual (retirar o ar de «gerado por máquina»)**:
  - 557 sinais retirados em 66 ficheiros:
    - setas no fim de botões («Simular →»);
    - símbolos colados ao texto (✓ ⚠ ✉ ▦ 📦);
    - pontos médios a separar dados («A · B»), passados a vírgulas;
    - travessões, passados a vírgulas ou dois pontos.
  - As setas de rota (origem → destino) mantêm-se, porque dão informação.
  - Feito por script só no texto visível (nunca em comentários nem dados estruturados), com as mesmas regras aplicadas ao dicionário de inglês.
  - Frases feitas reescritas com factos concretos:
    - capa do site: «Peça preços a vários transitários de uma só vez.» e como funciona;
    - serviços, rastreio, contacto e rodapé;
    - entrada na Área de Cliente;
    - painel do cliente.
  - «Em tempo real» e «atualização automática» trocados por descrições do que acontece.
  - Pequenos rótulos por cima dos títulos retirados (incluía um «Centro inteligente»).
  - Maiúsculas à inglesa corrigidas para português («Como funciona», «Transporte aéreo»).
  - Letra de máquina de escrever e maiúsculas forçadas retiradas do menu e da capa do site.
  - «Dashboard» que restava passou a «Painel».
  - ELO: respostas sem «Entendi»/«Com certeza». **Continua a identificar-se como assistente virtual**, por regra.
- Testes: 81 páginas abertas nos três perfis e as 3 páginas do site sem erros; todos os botões do Centro de comando executam a sua ação.

## v104 (Centro de comando só com o trabalho da administração)

- **Ficou**:
  - estado do negócio (receita de hoje, encomendas em curso, prazo, dinheiro em risco, subscrições);
  - navios com carga Elolog;
  - **Atenção necessária**, que passa a incluir as **encomendas diretas por tratar** (validação ou decisão da administração, com acesso direto à página);
  - **Encomendas a acompanhar** (só as que têm atraso, pagamento pendente ou suspensão, com «Ver todas as operações»);
  - onde estão as encomendas;
  - negócio no período com as encomendas por semana;
  - simulações dos clientes.
- **Saiu**:
  - meios em serviço (viaturas dos prestadores);
  - carga nos armazéns;
  - mapa de calor «Quando chegam os pedidos»;
  - rotas mais pedidas, prestadores mais ativos e atividade recente;
  - tabela de todas as encomendas recentes (continua em Operações).
- Só apresentação: nada foi apagado no servidor; os dados continuam disponíveis nas páginas próprias (Operações, Prestadores, Relatórios).

## v103 (Centro de comando num só ecrã; menu lateral igual em todos os ecrãs)

- **Um só ecrã**: acabaram os separadores «Ao vivo» e «Indicadores e simulações». Tudo o que estava nos dois está no Centro de comando, por esta ordem:
  - painel escuro com a receita de hoje em grande, encomendas em curso, levantadas no prazo, dinheiro em risco, subscrições por mês, e o mapa noturno do Atlântico com os navios;
  - «Onde estão as encomendas» (a cadeia logística numa barra contínua, com o número em cada etapa);
  - «Atenção necessária»;
  - encomendas recentes;
  - meios em serviço e carga nos armazéns;
  - painel escuro «Negócio nos últimos 7, 30 ou 90 dias» (serviços contratados, recibos de subscrição, novos prestadores e clientes, cancelamentos, evolução semanal e as horas a que chegam os pedidos);
  - rotas mais pedidas, prestadores mais ativos, atividade recente e simulações dos clientes.
- **Cabeçalho retirado** (título, frase, «atualizado há…» e separadores): as ações «Pedido por contacto», «Auditoria de prestador», «Ecrã inteiro» e «Atualizar» estão na linha de cima do painel escuro.
- **«Dashboard» passa a «Centro de comando»** na administração, a «Painel» no prestador e a «Início» no cliente (também no título do topo). «Personalizar painel» deixa de aparecer na administração, porque o ecrã único tem composição fixa.
- **Menu lateral igual no telemóvel e no computador** (capa com o porto, perfil com selo, mesmas opções e assinatura «Elolog • Ligando o mundo»). O menu rola por inteiro e «Sair» fica no fim, sem tapar opções.
- **Opção ativa nova**: uma aba clara que sai do menu escuro e se liga à área de conteúdo (cantos côncavos), com o ícone num selo azul-escuro. Igual para administração, prestador e cliente.
- Só apresentação: dados, permissões, fluxos, comissões, planos e ligação Supabase sem alterações. Ficheiros: `app/administracao/painel-vivo.js`, `painel-vivo-seccoes.js` (novo), `painel-vivo-mapa.js`, `painel-vivo.css`, `painel-vivo-2.css` (novo), `painel.js` (só expõe o período e a comparação), `app/comum/menu-movel.css`, `navegacao.js`, `pagina-1.js`, `prestador/menu-lateral.js` e `prestador/equipa-terreno-1.js` (só o nome «Painel»).

## v102 (Painel ao vivo: apresentação dos conteúdos)

- **Mapa sem nada por cima**: o acompanhamento das viagens passa para uma coluna ao lado do mapa (no telemóvel fica por baixo) e o mapa ganha uma legenda das cores (em rota, chega em breve, atrasado).
- **Encomendas recentes em largura total**: todas as colunas visíveis sem cortes; no telemóvel cada encomenda é um cartão com «Código, Origem, Destino, Chegada, Transporte, Prestador, Estado».
- **Meios em serviço** em lista compacta (duas colunas), uma linha por navio ou viatura, sem textos partidos.
- **Números do negócio**: a variação aparece numa etiqueta de cor (verde melhora, vermelho piora, âmbar atrasos) e os valores redondos deixam de mostrar «,00».
- **Viagens**: «Chega a …» e a origem da posição (AIS ou estimada) na mesma linha.
- Só muda a apresentação (`painel-vivo.js` e `painel-vivo.css`); dados, ações e ligações são os mesmos da v101.

## v101 (Centro de Controlo: «Painel ao vivo»)

- **Novo ecrã inicial do Centro de Controlo** com o design escolhido («Painel ao vivo»). O separador **«Indicadores e simulações»** mantém o painel anterior completo (nada foi retirado).
- **Quatro números de negócio, todos com dados reais**: receita da Elolog hoje (comissões pela regra ativa de cada empresa, ou a global, sobre os pagamentos confirmados hoje + planos pagos hoje, comparada com a média dos últimos 14 dias), encomendas em curso (e novas em 30 dias), levantadas no prazo (30 dias, comparado com os 30 anteriores) e dinheiro em risco (pagamentos pendentes e encomendas atrasadas). Cada número abre a página respetiva.
- **Navios ao vivo**: mapa do corredor atlântico (sem serviços externos) com os portos e o número de encomendas em cada um, e os navios com carga Elolog agrupados por navio e viagem. Posição **AIS** quando o navio é seguido; senão posição **estimada** pelas datas de partida e chegada (sempre indicado). Aproximar, afastar e aumentar o mapa; clicar numa viagem centra o navio; os códigos abrem a ficha da operação.
- **Meios em serviço** (navios e viaturas com serviços de hoje, filtro «Só em serviço»), **Encomendas recentes** (pesquisa, ordenação por coluna; cada linha abre a ficha da operação) e **Carga nos armazéns**.
- Atualiza-se sozinho a cada 30 s enquanto está visível; botão «Atualizar agora».
- Nada muda na ligação Supabase, nos dados, utilizadores, autenticação, permissões, fluxos de encomendas, comissões, planos ou fluxo marítimo: o painel só **lê**, através da função nova `painel_vivo` (apenas administração da plataforma).
- Servidor: migração `00164_painel_vivo.sql` (aplicada). Testes: `testes/25_painel_vivo.sql` (12/12). Front: `app/administracao/painel-vivo.js`, `painel-vivo-mapa.js` e `painel-vivo.css`.

## v100 (ficha da operação, regras automáticas e histórico obrigatório; funis retirados)

- **Funis retirados do Centro de comando** (o ecrã volta a ser de trabalho diário). A função `painel_funis` fica no servidor sem uso; para a apagar: `drop function if exists public.painel_funis(integer);` no SQL Editor.
- **Ficha da operação**: cada encomenda (linhas do Centro de comando, cartões do telemóvel e botão «Ficha» nos cartões do prestador) abre um painel lateral, sem sair do Centro. Separadores: **Resumo** (cliente, remetente, destinatário, rota, prestador, estado), **Percurso** (as 11 etapas com responsável, data e quem executou), **Carga** (volumes, peso, fotografias, documentos, armazém e expedição), **Financeiro** (preço, comissão Elolog, pagamentos, em dívida e alerta) e **Histórico** (todas as alterações e ocorrências). Em baixo, o **próximo passo** com o que falta e as ações da etapa.
- **Regras automáticas (servidor, `avancar_encomenda`)**: só avança com os requisitos da etapa; aprovação dispensada apenas no fluxo autorizado direto para armazém e com motivo de exceção; pagamento pendente gera alerta financeiro; receção no armazém exige quantidade confirmada (e ocorrência se não bater certo); expedição exige navio, viagem e data prevista; a chegada cria a tarefa de processamento no destino; «Disponível» exige essa tarefa concluída e avisa o cliente; «Levantado» só a partir de «Disponível» e com confirmação do levantamento (identificação + comprovativo assinado). **Nunca «Em trânsito» → «Levantado»** (nem por `transitar_encomenda`, que passa a usar as mesmas regras).
- **Histórico obrigatório** em cada mudança: número da encomenda, estado anterior e novo, data e hora, funcionário responsável, prestador, observações, documentos e motivo de exceção (também na auditoria).
- Servidor: migrações `00162_etapas_operacao_a.sql`, `00162_etapas_operacao_b.sql` e `00163_ficha_operacao.sql` (aplicadas; só acrescentam colunas, transições, o estado «Disponível» e funções). Testes: `testes/24_regras_operacao.sql` (20/20); `02` (78/78), `14` (10/10), `22` (22/22) e `23` (16/16) continuam a passar. Front: `app/comum/ficha-operacao.js`, `ficha-operacao-dados.js`, `ficha-operacao-acoes.js` e `ficha-operacao.css`.

## v99 (encomendas diretas: revisão administrativa)

- **Ver o comprovativo antes de validar**: «Analisar e validar» abre o comprovativo (PDF ou imagem) ao lado dos dados, com separadores para os documentos adicionais. A abertura fica registada no servidor e **só depois é possível validar**.
- **Corrigir dados administrativos** (antes de encaminhar): origem, destino, mercadoria, volumes, peso, volume, valor, data e observações, com razão da correção. O percurso guarda «antes → depois» e o cliente é avisado. O prestador não muda (só o cliente o pode trocar); uma correção que torne o prestador inelegível para a rota é recusada.
- **Pedir documentos adicionais**: pedido com sugestões (fatura pró-forma, lista de volumes, identificação do destinatário, comprovativo de pagamento). A encomenda mostra «Documentos pedidos» e não pode ser validada até o cliente enviar. O cliente usa «Enviar documentos pedidos» (ou «Juntar documento») na Área de Cliente.
- **Encaminhar**: «Validar e encaminhar» num só passo, ou «Validar» e depois «Encaminhar ao prestador». O prestador vê o comprovativo e os documentos adicionais.
- Servidor: migração `00161_encomendas_diretas_revisao.sql` (aplicada; só acrescenta colunas, a tabela `encomendas_diretas_anexos` e funções). Testes: `testes/23_encomendas_diretas_revisao.sql` (16/16) e `22` atualizado (22/22). Front: `app/administracao/encomendas-diretas-revisao.js`.

## v98 (encomendas diretas com validação da administração e decisão do prestador)

- **Área de Cliente**: novo menu «Encomendas diretas» e atalho «Registar encomenda direta» (também pelo ELO). Formulário: prestador (só ativos e elegíveis para a rota), origem, destino, mercadoria, volumes, peso, volume, valor acordado, data prevista, comprovativo (PDF/JPG/PNG, até 10 MB) e observações. O cliente acompanha o percurso completo e, depois de uma recusa ou não validação, pode **escolher outro prestador** (volta à validação) ou cancelar.
- **Administração** (Operações e clientes › Encomendas diretas): colocar em análise, validar, não validar (motivo para o cliente), enviar ao prestador, ver o comprovativo e contactar o cliente. Não pode mudar o prestador.
- **Prestador** (Operações › Encomendas diretas): só vê o pedido depois do encaminhamento; coloca em análise, aceita ou recusa — a recusa exige motivo (rota, espaço, preço/condições, documentação, mercadoria, outro com descrição). Os contactos do cliente só aparecem depois de aceitar.
- **Estados**: Pendente de validação (cliente) → Em análise / Validada / Não validada / Enviada ao prestador (administração) → Em análise / Aceite / Recusada (prestador). Nada é eliminado; cada passo fica no histórico e gera aviso ao cliente, à administração e ao prestador.
- **Elegibilidade**: prestador aprovado com subscrição ativa; se tiver tarifas com rota, a rota pedida tem de coincidir com uma delas; sem tarifas de rota, serve todas.
- Servidor: migração `00160_encomendas_diretas.sql` (aplicada; só acrescenta tabelas, funções e uma política de leitura do comprovativo). Testes: `testes/22_encomendas_diretas.sql` (22/22). Front: `app/comum/encomendas-diretas-dados.js`, `app/cliente/encomenda-direta.js`, `app/administracao/encomendas-diretas.js`, `app/comum/encomendas-diretas.css`.

## v97 (menu igual no telemóvel, avisos nas notificações, ELO mais curto, sem Pesquisa marítima)

- **Menu do telemóvel igual para cliente, prestador e administração**: mesma capa e posição do perfil, opções com a mesma altura, letra e ícones, a opção atual sempre destacada (também no prestador, que antes não destacava), grupos com seta e submenus com a mesma linha lateral (`app/comum/menu-movel.css`, `app/prestador/menu-lateral.js`).
- **Avisos de orientação fora do ecrã**: a faixa «Ainda não há atividade na plataforma…» passa a ser uma notificação (uma só vez) no painel de notificações (`window.elologAvisoUnico` em `app/comum/notificacoes.js`). Retiradas também as frases explicativas dos estados vazios e a nota do funil de clientes.
- **ELO mais curto**: ao abrir mostra só «Olá! Sou o ELO, o assistente virtual da Elolog. Em que posso ajudar?». Os atalhos, o botão da equipa e a nota de segurança só aparecem depois de a pessoa escrever; menos atalhos por perfil.
- **Pesquisa marítima retirada**: saem o menu (cliente, prestador e administração), os ficheiros `pesquisa-maritima*.js/.css`, as migrações 00153–00157, os testes 19 e 20, a função `navios-mst` e a parte «rota» da `navios-ais`. A tarefa diária da MyShipTracking foi desligada no Supabase (deixa de gastar créditos). O ELO deixou de indicar datas de navios.
- Para apagar as tabelas e funções da pesquisa no Supabase, executar à mão `servidor/supabase/migrations/00159_retirar_pesquisa_maritima.sql` no SQL Editor; depois apagar a Edge Function `navios-mst` e o segredo `MYSHIPTRACKING_API_KEY` no painel.

## v96 (regras de funcionamento do ELO e respostas em PT, EN e FR)

Novo ficheiro `partilhado/scripts/assistente-regras.js`, carregado antes do assistente em todas as páginas. As regras são verificadas antes de qualquer outra resposta:

1. **Não inventa preços, transportadoras nem datas de navios**: os preços só vêm da simulação, com tarifas de prestadores aprovados; as datas abrem a Pesquisa marítima (dados da plataforma); com servidor, deixa de sugerir prestadores guardados no dispositivo.
2. **Não confirma encomendas sem consultar a plataforma**: com servidor, o estado é lido no Supabase (ligação existente) e mostra a hora da consulta; o agendamento passa para a encomenda, onde só fica confirmado quando o prestador aceitar.
3. **Não recebe pagamentos**: encaminha para «Pagamentos»; se alguém escrever um cartão, IBAN ou palavra-passe, avisa e oculta-o.
4. **Não aprova prestadores**: explica que a aprovação é feita por uma pessoa; à administração abre «Pedidos de inscrição».
5. **Não mostra dados de terceiros**: sem sessão iniciada não consulta encomendas (nem por email/NIF do destinatário); com sessão, só vê o que as regras de acesso (RLS) da conta permitem.
6. e 7. **Pessoa da equipa e terminar**: atalhos «Falar com uma pessoa» e «Terminar conversa» sempre visíveis; ao terminar, a conversa é apagada do dispositivo.
8. **Identifica-se sempre como assistente virtual** na saudação e quando perguntam «és um robô?».
9. **Minimização de dados**: emails, telefones, NIF, IBAN, cartões e palavras-passe são ocultados antes de guardar a conversa e no resumo enviado à equipa; «apagar conversa» apaga já.
10. **Português, inglês e francês**: deteta a língua da mensagem ou escolhe-se no atalho «Idioma · Language · Langue»; respostas e atalhos mudam de língua.

## v95 (português de Portugal)

- Textos com termos do Brasil corrigidos para português de Portugal: «senha» → «palavra-passe» (entrada do prestador, registo, avisos), «Aguardando …» → «A aguardar …» (estados de propostas, pagamentos e encomendas), «Baixar» → «Descarregar», «Visualizar» → «Ver», «Confira» → «Verifique», «nota fiscal» → «nota de crédito», «(você)» → «(a sua conta)». A tradução para inglês foi atualizada com os novos textos.
- Pagamentos antigos guardados como «Aguardando confirmação» continuam a ser reconhecidos.

## v94 (três funis e «Gargalo principal» no Centro de comando)

- O Centro de comando mostra, ao mesmo tempo, o **Funil de Clientes**, o **Funil de Prestadores** e o **Funil Financeiro**, com indicadores resumidos no topo e cada etapa expansível (explicação, perdas face à etapa anterior, detalhes e atalho para a página certa). No telemóvel os funis ficam empilhados.
- Novo indicador **Gargalo principal**: primeiro o que trava tudo (sem prestadores disponíveis, sem procura); senão, a etapa com pior passagem, com a ação recomendada.
- Regras aplicadas no servidor (só dados registados, nunca valores inventados):
  1. sem prestadores **aprovados e disponíveis** (subscrição ativa), não há propostas;
  2. sem proposta válida (dentro da validade, de prestador aprovado), não há aceite;
  3. sem aceite, não há valor contratado (encomendas sem proposta aceite aparecem como «fora do funil»);
  4. sem fatura válida, não há valor faturado;
  5. sem pagamento confirmado, não há valor recebido (reembolsos descontados);
  6. **planos** dos prestadores e **comissões** das encomendas contados em separado (comissão calculada sobre o recebido, com a regra ativa).
- Em modo de demonstração os funis usam dados fictícios, sempre identificados.
- Servidor: migração `00158_funis_gargalo.sql` (aplicada; só acrescenta a função `painel_funis`, só para a administração — tabelas, dados e ligação Supabase inalterados). Testes: `testes/21_funis.sql` (14/14).
- Front: `app/administracao/funis.js` (usa a ligação existente `ELOLogServidor.cliente()`).

## v93 (todos os navios com destino São Tomé e partidas de São Tomé)

- `navios-mst` passa a procurar também, por zona, os navios que **declaram destino São Tomé (ST TMS / STTMS / SAO TOME)** nos portos de **Lisboa, Leixões, Setúbal e Sines**, e os navios **a sair de São Tomé** com o destino declarado. As saídas registadas no porto passam a 20 dias (limite das chaves de teste).
- Na pesquisa: «Com destino a São Tomé (ST TMS)» (com chegada prevista, destino declarado e porto onde foi visto), «No porto de São Tomé» e «Partidas de São Tomé (últimos 20 dias)» com o destino declarado.
- **Frequência: 1 vez por dia (06:23 UTC)**, escolhida pelo custo. Custo medido: ~480 créditos nas zonas + ~25 nas escalas por execução (~15 000/mês). A chave de **teste (2 000 créditos)** dura poucos dias; para uso contínuo é preciso o plano Basic (90 €/mês, 50 000 créditos).
- Limite: a MyShipTracking só tem AIS terrestre, por isso navios em alto mar só aparecem se já tiverem sido vistos num porto.
- Servidor: migração `00157_navios_stp_zonas.sql` (aplicada: coluna `local`, função `navios_stp`, tarefa diária). Testes: `mst.test.mts` (11/11).

## v92 (navios reais em São Tomé pela MyShipTracking)

- Nova Edge Function **`navios-mst`** (publicada): 3 vezes por dia (05:23, 13:23, 21:23 UTC) consulta a API MyShipTracking para o porto de **São Tomé (port_id 5867 na MyShipTracking; o código STTMS não existe lá)**: navios **no porto**, **previstos chegar** (com data/hora) e que **partiram** nos últimos 7 dias.
- Na Pesquisa marítima aparece a secção **«Navios em São Tomé»** com os três grupos, tipo de navio, bandeira, GT, IMO e ligação para o mapa (quando há posição).
- **Ativado** a 07/11/2026 (`MYSHIPTRACKING_API_KEY` definido). Primeiro teste: 2 navios reais (saídas recentes de São Tomé), 10 créditos gastos. «Sem navios» (ERR_NOT_FOUND) não é erro nem gasta créditos.
- **Custo estimado**: por execução ~10 créditos (navios no porto) + 1 crédito por navio previsto + 5 créditos por cada dia com saídas (máx. 35) → cerca de 20 a 60 créditos por execução, **~2 000 a 5 000 créditos/mês** (cabe no plano Basic de 50 000). Pedidos sem resultados não gastam créditos.
- Servidor: migração `00156_navios_myshiptracking.sql` (aplicada: colunas novas em `navios_rota`, função `navios_sao_tome`, tarefa agendada `elolog-navios-mst`). Ligações Supabase inalteradas. Testes: `functions/_testes/mst.test.mts` (7/7).

## v91 (pesquisa marítima sem aisstream: viagens publicadas pela Elolog)

- Decisão: **não usar o aisstream.io**. A pesquisa marítima mostra as viagens publicadas pela **equipa Elolog** e pelos prestadores (sem dependência de serviços externos).
- A **administração da plataforma** passa a ter «+ Publicar viagem» e «Editar» na Pesquisa marítima (Administração → Operações e clientes → Pesquisa marítima). As viagens aparecem aos clientes com o prestador «Elolog».
- Servidor: migração `00155_viagens_elolog.sql` (aplicada): tabela `viagens_elolog` (só a administração escreve; auditoria e limite de alterações) e `pesquisa_maritima` junta as duas origens. Teste: `testes/20_viagens_elolog.sql` (8/8); `19_pesquisa_maritima.sql` continua 17/17.
- A secção «Navios na rota · AIS» só aparece se um dia houver dados AIS (sem chave AIS fica escondida). A tabela `navios_rota` (v89) fica sem uso.
- Outras fontes avaliadas: AISHub (gratuito, mas exige recetor AIS próprio); MyShipTracking / VesselFinder (pagos por créditos).

## v90 (correções do menu no telemóvel)

- O perfil (iniciais, nome e função) já não fica por cima da onda da capa.
- Só o grupo **aberto** fica destacado (antes ficavam destacados todos os grupos que tinham sido abertos); a seta do grupo aberto vira para cima.
- Textos de todos os itens com a mesma cor (o «Apoio e reclamações» aparecia esbatido).

## v89 (pesquisa marítima: todos os navios e navios reais pelo AIS)

- Novo separador **«Todos os navios»** (abre por omissão): mostra todas as viagens publicadas e todos os navios detetados na rota, sem filtros de sentido, porto ou datas.
- **Navios reais na rota**: a função `navios-ais` (a cada 30 min) passa também a escutar o corredor Golfo da Guiné ⇄ Portugal e guarda os navios de carga cujo destino declarado no AIS é São Tomé/Neves (→ São Tomé) ou um porto português, vindo do sul (→ Portugal). Aparecem na secção «Navios na rota · AIS em tempo real», com destino, chegada prevista, última posição e ligação para o mapa.
- **Para funcionar precisa da chave AIS** (gratuita): criar conta em https://aisstream.io → «API Keys» → criar chave; no Supabase → Edge Functions → Secrets → `AISSTREAM_API_KEY` = a chave. Os primeiros navios aparecem na meia hora seguinte e a lista vai crescendo (cada navio envia os dados de viagem de ~6 em 6 minutos).
- Servidor: migração `00154_navios_na_rota.sql` (aplicada), `navios-ais` republicada (ligações Supabase inalteradas). Testes: `functions/_testes/rota.test.mts` (12/12).

## v88 (cores da marca)

- O menu do telemóvel e o centro de comando voltaram às **cores do design inicial**: tinta `#13293D` → `#17425c` no fundo, azul `#1F5F8B` na opção ativa e na onda, verde `#1F7A5C` no destaque do grupo aberto e no selo, textos `#dbe9f1` / `#9fbccd`. O desenho (capa com navio, perfil, «Sair», assinatura) mantém-se.

## v87 (EloLog Maritime Search e novo menu no telemóvel)

- **Pesquisa marítima Portugal ⇄ São Tomé e Príncipe** (menu: Cliente → «Pesquisa marítima»; Prestador → Encomendas → «Pesquisa marítima»; Administração → Operações e clientes → «Pesquisa marítima»).
  - Separadores: **Partidas**, **Chegadas**, **Navios** (agrupa as viagens por navio, com a próxima partida) e **Com espaço** (só viagens abertas, com prazo de carga em aberto e espaço livre).
  - Filtros: navio/linha/viagem, sentido, porto (Lisboa, Leixões, Setúbal, Sines, Aveiro, Figueira da Foz, São Tomé, Neves), datas e «só com espaço disponível».
  - Cada viagem mostra datas (e «daqui a N dias»), prazo de entrega da carga, estado, espaço livre (20', 40', grupagem m³, viaturas), prestador e, se houver MMSI, a **posição real AIS** com ligação para o mapa.
  - O cliente carrega em «Pedir cotação» e a simulação abre já preenchida com os portos e o navio.
  - O prestador (administrador ou operador) carrega em «+ Publicar viagem» / «Editar» para publicar e atualizar as suas viagens; pode deixá-las ocultas (rascunho).
  - **Ligações Supabase intactas**: o módulo usa a ligação já existente da plataforma; não cria clientes nem altera chaves ou configuração. No servidor só acrescenta a tabela `viagens_maritimas` e a função `pesquisa_maritima` (migração `00153`, aplicada). Viagens com MMSI passam a ser seguidas pelo AIS que já existe.
  - Segurança: só a própria empresa publica/altera; datas coerentes; limite de 60 alterações por 10 min; tudo na auditoria. Teste: `testes/19_pesquisa_maritima.sql` (17/17).
  - Sem servidor (modo de demonstração) mostra viagens fictícias identificadas como tal. Em produção a lista começa vazia até os prestadores publicarem.
  - Ficheiros: `app/comum/pesquisa-maritima.js`, `pesquisa-maritima-form.js`, `pesquisa-maritima.css`.
- **Menu lateral no telemóvel** com o visual do modelo enviado: capa com navio no porto e onda azul, perfil com iniciais e selo de verificação (administração), opção ativa em azul vivo com seta, grupo aberto destacado, «Sair» com contorno e «Elolog • Ligando o mundo». Ficheiro: `app/comum/menu-movel.css` (só em ecrãs até 900 px).

## v86 (voltar atrás, avisos de email, centro de comando no telemóvel)

- **Voltar atrás**: o botão «voltar» do telemóvel/navegador regressa à opção anterior dentro da plataforma (e fecha o menu lateral se estiver aberto). No início pede um segundo toque para sair. Ficheiro: `app/comum/historico.js`.
- **Avisos de email**: as caixas são verificadas a cada 30 s (antes 2 min). Quando chega um email aparece no ecrã um cartão com a caixa, o remetente e o assunto, e o botão «Abrir». Se autorizar os avisos do sistema (pedido ao abrir o Email), também avisa com a página em segundo plano (verificação a cada 60 s). Ficheiros: `app/comum/email-1.js`, `app/comum/email-avisos.js`.
- **Centro de comando no telemóvel**: painel visual no topo com o resumo do dia (operações em curso, valor e barra colorida por etapa), estado (a aguardar ação, urgentes, receita mensal), 8 atalhos grandes com contadores e as últimas 5 operações em cartões. A tabela larga e o fluxo em grelha ficam só no computador. Ficheiros: `app/administracao/centro-movel.js`, `app/administracao/centro.css`.

## v85 (código de reserva e menu)

- **2.ª opção de verificação — código de reserva**: para a administração da plataforma e o administrador da empresa, quando não há acesso ao telemóvel.
  - Depois de confirmar o código do telemóvel pela primeira vez, a plataforma mostra **uma vez** um código fixo (`XXXX-XXXX-XXXX-XXXX`). Guarde-o fora do telemóvel (papel ou gestor de palavras-passe).
  - Sem telemóvel: no 2.º passo, «Sem acesso ao telemóvel? Usar o código de reserva» → escreve o código → entra.
  - Para trocar o código: marcar «Gerar um novo código de reserva ao entrar com o telemóvel» (o anterior deixa de valer).
  - Segurança: guardado só como hash; 5 tentativas por 15 min; só se gera com o telemóvel; vale apenas para a sessão em que foi usado; cada uso fica na auditoria e gera um aviso (notificação e email).
  - O **painel de email** continua a pedir o código do telemóvel.
  - Servidor: migração `00152_codigo_reserva_mfa.sql` (aplicada); `gerir-equipa`, `criar-prestador`, `gerir-funcionarios` republicadas. Front: `app/comum/codigo-reserva.js`. Teste: `testes/18_codigo_reserva.sql` (17/17).
- **Menu (telemóvel)**: tocar num grupo do menu (ex.: «Encomendas») já não fecha o menu; só fecha depois de escolher a opção.

## v84 (regras de segurança obrigatórias)

- Regras e onde cada uma é garantida: `documentacao/REGRAS_SEGURANCA.md`.
- **Ficheiros**: só PDF, JPG, PNG, WEBP, DOC(X), XLS(X) até 20 MB. Verificados no navegador, na base de dados e pelo conteúdo no servidor (`verificar-ficheiro`). Até à verificação, só quem enviou vê o ficheiro; um ficheiro falso é apagado e a recusa fica registada.
- **Auditoria** só acrescenta (não se altera nem apaga) e regista sozinha as alterações sensíveis, sem segredos.
- **Limites de escrita** por utilizador na base de dados (ex.: 60 documentos / 10 min).
- **Edge Functions** com bloqueio seguro (`_shared/seguranca.ts`): segredos em falta, pedido grande demais ou qualquer falha → a operação não é executada.
- **Assistente ELO**: entrada limpa e limitada (500 caracteres, 15 mensagens/min); respostas verificadas antes de aparecer.
- Servidor: migração `00151_regras_seguranca.sql` (aplicada); todas as 13 funções republicadas. Testes: `testes/17_regras_seguranca.sql` (12/12).

## v83 (marca nova)

- **Logótipos novos** em `partilhado/imagens`: `elolog-logo.svg` (horizontal a cor), `elolog-logo-negativo.svg` (branco, para fundos escuros: rodapé e painel de entrada), `elolog-logo-nav.png`, `elolog-logo-full.png`, `elolog-logo-600.png` (também usado nos emails).
- **Ícones** novos: `favicon.ico`, `favicon-48/96/192`, `apple-touch-icon`, `icon-192/512` e `icon-maskable-512` (app instalada).
- **Imagem de partilha** (`elolog-partilha.jpg`) com o logótipo novo sobre azul-escuro.
- **Cores da marca**: azul `#1F5F8B`, verde `#1F7A5C`, tinta `#13293D` (antes `#236186`, `#237E5F`, `#0E2433`).
- **Logótipo animado** (`partilhado/scripts/logo-animado.js`): na primeira página de cada visita, o logótipo da barra desenha-se (cerca de 2 s). Nas páginas seguintes fica parado. Respeita a opção «reduzir movimento» do aparelho.

## v82 (endereços parecidos levam ao sítio certo)

- `app/administrador.html` abre a entrada da administração (tal como `app/administracao.html` e `/admin`).
- A página «Página não encontrada» (`404.html`) reencaminha sozinha endereços parecidos: com «admin/gestão/equipa» → administração; «prestador/empresa/funcionário» → acesso do prestador; «cliente/entrar/login/conta» → Área de Cliente; «simular/cotação/preço» → simulador.

## v81 (dois passos para o administrador da empresa)

- O **administrador da empresa** confirma cada entrada com o **código de 6 dígitos** de uma aplicação de autenticação (Google Authenticator, Microsoft Authenticator, Authy). Na primeira vez a plataforma mostra o **código QR** (e a chave para escrever à mão) para registar a aplicação. Passos: 1 · Empresa → 2 · A sua conta → **3 · Verificação**.
- Garantido no servidor: sem o 2.º passo a base de dados **não abre a sessão da empresa** e não mostra nem altera dados (mesmo com as duas palavras-passe certas ou com uma sessão de empresa ainda aberta). As funções `gerir-funcionarios` e `email-caixa` também o exigem ao administrador da empresa.
- Os outros funcionários (NIF + n.º + palavra-passe) não são afetados.
- Servidor: migração `00150_mfa_admin_empresa.sql` (aplicada); `gerir-funcionarios` e `email-caixa` republicadas. Front: `app/comum/mfa-empresa.js`. Testes: `testes/16_mfa_admin_empresa.sql` (8/8); testes antigos atualizados (02: 78/78).
- No modo de demonstração o 2.º passo não é pedido.

## v80 (funcionário entra só com NIF, n.º e palavra-passe)

- **Funcionário do prestador** (operador, terreno, armazém, financeiro): entra com **NIF da empresa + n.º de funcionário + a sua palavra-passe**. Já **não** precisa da palavra-passe da empresa. Opção «Lembrar o NIF e o número neste aparelho».
- **Administrador da empresa**: botão **«Sou administrador da empresa»** → nome + NIF + **palavra-passe da empresa** e depois a sua conta (como antes). Se o administrador tentar entrar como funcionário, a plataforma encaminha-o para este acesso.
- **N.º de funcionário automático** (0001, 0002, … por empresa), único dentro da empresa; pode continuar a ser definido à mão (ex.: OP-014). «0002» e «2» são o mesmo número.
- Servidor: migração `00149_login_funcionario.sql` (aplicada) e Edge Function **`entrar-funcionario`** (publicada): procura a conta pelo NIF + n.º, confirma a palavra-passe e abre a sessão da empresa; o email do funcionário não é exposto e há limite de tentativas. Front: `app/comum/login-funcionario.js`. Testes: `testes/15_login_funcionario.sql` (8/8).

## v79 (entrar mais facilmente: prestador e administração)

- **Separadores «Cliente | Prestador»** no topo do login (computador e telemóvel); ligação discreta **«Equipa Elolog»** por baixo para a administração.
- **Endereços curtos:** `www.elolog.pt/prestador` e `www.elolog.pt/admin` (pastas `prestador/` e `admin/` na raiz).
- O aparelho **lembra-se do último acesso**: quem entra como prestador ou administração volta direto a esse login ao abrir a Área de Cliente (o separador «Cliente» desfaz).
- Prestador: **«Lembrar a empresa neste aparelho»** guarda o nome, o NIF e o email do funcionário (nunca as palavras-passe); da próxima vez só escreve as palavras-passe. Passos renumerados: 1 · Empresa, 2 · Funcionário. Ficheiro: `app/comum/portas.js`.

## v78 (Área de Cliente só para clientes)

- Uma conta da equipa Elolog ou de um funcionário de prestador já não entra pela Área de Cliente: aparece a indicação do acesso certo (administração ou prestador). Antes, a plataforma criava por engano um perfil de cliente para essa conta.
- Servidor: migração `00148_cliente_so_clientes.sql` (aplicada) — função `tipo_conta()` e regra na base de dados que impede criar perfis de cliente para contas da equipa/prestadores. O perfil de cliente criado por engano é apagado pelo último bloco da migração (correr no SQL Editor).

## v77 (ocorrências e suspensão; manifesto opcional)

- Botão **«⚠ Ocorrências»** em cada encomenda (cliente: Ver detalhes; prestador: detalhe da encomenda, detalhe da operação e cartões de encomendas do servidor).
- **Prestador** (administrador, operador, armazém, terreno; o financeiro só consulta): regista a ocorrência com **tipo** (atraso, dano, perda, documentação, alfândega, pagamento, morada, outro) e **gravidade**, atribui **responsável**, muda o estado (aberta → em resolução → resolvida → encerrada; resolver exige descrever a resolução), **comunica ao cliente** e tem o histórico de cada passo (quem, quando, o quê).
- **Suspender / retomar a encomenda**: o estado logístico mantém-se e fica bloqueado até «Retomar» (só se pode cancelar). Fica no histórico da encomenda e o cliente é avisado. Uma ocorrência pode suspender logo ao ser registada.
- **Cliente**: «Comunicar um problema» e vê as ocorrências que lhe foram comunicadas (sem notas internas). A encomenda suspensa aparece como «Suspensa».
- **Manifesto opcional**: deixou de ser obrigatório para passar a «em trânsito». O prestador pode **juntar o despacho/manifesto feito pelo despachante** (documento «despacho», visível ao cliente).
- Servidor: migração `00147_ocorrencias.sql` (**aplicada**), códigos `ELO_OC-000001`. Front: `app/comum/ocorrencias.js`. Testes: `testes/14_ocorrencias.sql` (10/10).

## v76 (criar perfil Pessoal e prestador criado pela Elolog)

- **Criar perfil:** «Particular» passa a **«Pessoal»**. O botão «Criar administrador da empresa» só aparece no registo de uma empresa prestadora (estava visível por erro: os botões com `hidden` eram mostrados por uma regra `!important` de `acabamento.css` — corrigido para todos os botões). «Criar perfil» só fica ativo depois de **abrir e ler a política de privacidade** (janela com o texto; o botão «Li a política» só ativa ao chegar ao fim) e aceitar.
- **Conta Pessoal:** nome + **telemóvel ou email**, à escolha, confirmados — email por ligação de confirmação; telemóvel por **código SMS** (precisa de um fornecedor de SMS no Supabase, ver PRODUCAO.md). NIF opcional. Pode-se **entrar com o telemóvel** (912 345 678 ou +351…). Na **Empresa** continuam obrigatórios NIF e email. Ficheiro: `app/comum/registo-pessoal.js`.
- **Administração › Gestão de prestadores › + Criar prestador:** já não se escreve palavra-passe. A Elolog gera um **código de acesso temporário** (`ELO-XXXX-XXXX`, 72 h) e envia-o por email ao administrador da empresa (se o email falhar, o código aparece uma vez no ecrã). O código serve nos dois passos do login; no **primeiro acesso é obrigatório** criar a palavra-passe da empresa e a pessoal (janela que não se fecha). Enquanto não trocar, a conta não vê nem altera nada da empresa (garantido na base de dados). Lista «Primeiros acessos por concluir» com **Reenviar código**. Ficheiros: `app/comum/primeiro-acesso.js`, Edge Function `criar-prestador` (publicada), migração `00146_acesso_temporario.sql` (**aplicar no SQL Editor** — ver PRODUCAO.md), testes `testes/13_acesso_temporario.sql` (12/12).

## v75 (declarações da encomenda: 6 modelos)

- Botão **«📄 Declarações (6 modelos)»** no detalhe da encomenda (cliente: «Encomendas» › Ver detalhes; prestador: pesquisa de encomenda e detalhe da operação).
- Os dados preenchem-se **uma vez**, em 5 passos: Pessoas (proprietário, destinatário, finalidade) · Viatura (opcional) · Bens (linhas com quantidade, estado e valor) · Embarque · Documentos. O cliente preenche pessoas, viatura e bens; o **embarque é do prestador** (o cliente vê-o bloqueado e o servidor ignora alterações do cliente).
- Modelos: 1 Identificação da viatura (só se houver viatura) · 2 Bens no interior da viatura (ou «bens transportados») · 3 Conteúdo e valor · 4 Propriedade e finalidade · 5 Responsabilidade · 6 Folha de processo de exportação e transporte.
- **PDF** gerado no navegador, sem custos nem bibliotecas (`app/comum/declaracoes-pdf.js`), com local, data e linhas de assinatura; «Descarregar PDF» para imprimir e assinar, «Guardar na encomenda» junta-o aos documentos (visível ao cliente). Rodapé: documento interno de apoio, não substitui documentos aduaneiros.
- Servidor: migração `00145_declaracoes.sql` (aplicada) — `declaracoes_ler` / `declaracoes_gravar`; só o cliente da encomenda e a empresa prestadora acedem. Testes: `testes/12_declaracoes.sql` (8/8).

## v74 (recuperar a palavra-passe e espaço de ficheiros)

- **Esqueceu-se da palavra-passe (clientes, funcionários, equipa Elolog):** indica o email → recebe um email da Elolog com o botão «Criar nova palavra-passe» (abre `app/area-cliente.html?repor=…`) e um código de 6 dígitos para usar noutro aparelho. Válido 1 hora, uma só vez. Quem tem verificação em dois passos (administração) também escreve o código da aplicação. Depois da mudança: todas as sessões terminam e chega o email «A sua palavra-passe foi alterada». A resposta é sempre igual, exista ou não a conta.
- **Palavra-passe da empresa (1.º passo do prestador):** nome + NIF → código e ligação (`?repor-empresa=…`) para o **email oficial da empresa**; válido 30 minutos e deixa de valer assim que a palavra-passe muda. A empresa recebe uma notificação.
- Servidor: Edge Function `recuperar-acesso` (já publicada; usa os segredos Brevo que já existem) e migração `00143_repor_senha_empresa.sql` (aplicada). Front: `app/comum/recuperar.js`. Testes: `testes/10_repor_empresa.sql` (6/6).
- **Espaço de ficheiros garantido por plano:** o servidor mede o que cada empresa guarda (Básico 2 GB, Profissional 20 GB, Empresarial = valor acordado, 50 GB se não houver; clientes 1 GB) e **bloqueia novos documentos no limite**. Avisos à empresa aos 80 % e 100 % (e à Elolog aos 100 %). O quadro «Plano contratado» mostra o espaço real; em «Planos e subscrições» a equipa Elolog vê o espaço de cada empresa e define o valor acordado. Migração `00144_espaco_ficheiros.sql` (aplicada), `app/comum/espaco.js`, testes `testes/11_espaco_ficheiros.sql` (12/12).

## v73 (aparecer melhor nas pesquisas)

- Ícone do site (logótipo) para o Google e os separadores: `favicon.ico` na raiz e `partilhado/imagens/favicon-48/96/192.png`, `apple-touch-icon.png`.
- Títulos e descrições novos (página inicial, simulador, página legal) e dados estruturados (Organization com logótipo, contactos e telefone; WebSite com o nome «Elolog»; Service).
- Imagem de partilha 1200×630 com o logótipo (`partilhado/imagens/elolog-partilha.jpg`) para WhatsApp, LinkedIn, Facebook, etc.; `sitemap.xml` atualizado. Passos para o Google em `documentacao/PRODUCAO.md` › «Aparecer no Google».

## v72 (novas referências ELO)

- **Encomendas:** `ELO_<REF>-000123`, em que REF é a referência do prestador (criada sozinha a partir do nome, sem acentos: «Transatlântico Demo, Lda.» → `TRAN`; se repetir, ganha um número: `TRAN2`). A numeração é contínua por prestador.
- **Simulações:** `ELO_SM-000045`.
- Dadas pela base de dados (migração `00142_codigos_elo.sql`, já aplicada); as antigas `TR-…`/`SIM-…` passam para o formato novo. O ELO no WhatsApp reconhece `ELO_TRAN-000123` (e ainda os códigos antigos). Testes: `servidor/supabase/testes/09_codigos_elo.sql` (7/7).

## v71 (chat sem hierarquia e grupos)

- **Chat da equipa:** dentro da mesma organização todos falam com todos (sem hierarquia). A equipa Elolog continua separada de cada prestador: a administração da plataforma não vê nem contacta os funcionários dos prestadores, e empresas diferentes nunca se veem.
- **Grupos:** «+ Novo grupo» (nome + colegas). Qualquer membro escreve, adiciona colegas («+ Pessoas») ou sai do grupo. As mensagens dos grupos contam no contador vermelho do menu.
- Servidor: migração `00141_chat_grupos.sql` (já aplicada no projeto «Elolog»). Testes: `servidor/supabase/testes/08_chat_grupos.sql` (9/9) e `07_acessos_chat.sql` (26/26).

## v70 (email por equipa, chat e tudo a atualizar sozinho)

- **Email da equipa:** o administrador liga as caixas e, em **⚙ › Acessos**, escolhe que funcionários as podem usar (ler, responder, apagar). Só o administrador liga, altera ou remove caixas.
- **Encaminhar a funcionário:** ao ler um email, «👤 Encaminhar a funcionário» escolhe o colega adequado (com nota). O colega recebe-o na pasta **Atribuídos** e um aviso no chat, e pode responder mesmo sem acesso ao resto da caixa; fica marcado «Respondido».
- **Código de confirmação ao ligar uma caixa:** é enviado um código de 6 dígitos para essa caixa; só fica ligada depois de o escrever (válido 10 min).
- **Chat da equipa** (menu «Chat da equipa», também para o terreno): conversas entre funcionários da mesma organização, segundo a hierarquia — a equipa Elolog só fala entre si e não vê o chat dos prestadores; no prestador, administrador e operadores falam com todos, cada função com a mesma função e armazém ↔ terreno; o financeiro não fala diretamente com terreno/armazém; empresas diferentes nunca. Contador de mensagens por ler no menu.
- **Atualização automática:** email (lista a cada 30 s, contador no menu a cada 2 min, aviso «Novo email de …»), chat (4 s com a conversa aberta), encomendas do cliente vindas do servidor a cada 30 s com aviso quando o estado muda (`app/cliente/sincronizar.js`), e a aplicação recarrega sozinha quando há uma versão nova publicada.
- Servidor: migrações `00138_acessos_email_chat.sql`, `00139_email_atribuicoes.sql` e `00140_chat_so_equipa.sql` (já aplicadas no projeto «Elolog»); função `email-caixa` atualizada (já publicada). Testes: `servidor/supabase/testes/07_acessos_chat.sql` (26/26).

## v69 (entrada direta e simulador)

- `index.html` abre logo a página inicial, sem o ecrã intermédio «A abrir a plataforma Elolog… / Entrar na plataforma».
- Simulador: barra de navegação igual à da página inicial (transparente sobre a fotografia, mesma letra, fica branca ao rolar) e mesmas ligações (sem «Sobre Nós», que não existe na página inicial; também retirado da página legal).

## v68 (contacto WhatsApp e equipa)

- Número oficial **+351 934 876 092** em `partilhado/scripts/contactos.js`: o botão do ELO passa a abrir o WhatsApp da Elolog; o número aparece no rodapé (site e aplicação), na secção de contacto da página inicial, na página legal e nas respostas do ELO no WhatsApp.
- Lista «Equipa Elolog» corrigida: as colunas (nome, função, ações) ficam alinhadas em todas as linhas.

## v67 (painel de email)

- **Email dentro da plataforma** (menu «Email» da administração e, no prestador, em «Apoio ao cliente» › «Email»): ler, procurar, responder, responder a todos, reencaminhar, descarregar anexos, marcar como não lida e apagar (vai para o Lixo). Pastas Entrada, Enviados e Lixo; o que se envia fica também nos Enviados da caixa.
- **Só administradores:** o administrador da plataforma (caixas da Elolog, com 2.º fator) e o administrador de cada prestador (caixas da sua empresa). Operadores e outras funções não veem a opção.
- Liga a qualquer caixa com IMAP (porta 993) e SMTP (porta 465): www.pt/correio.pt, Gmail, Sapo, etc. A palavra-passe fica cifrada no cofre do Supabase e nunca chega ao navegador; cada caixa é testada antes de ser guardada.
- Servidor: migração `00137_caixas_email.sql` e Edge Function `email-caixa` (já publicada). O HTML dos emails abre isolado (sem scripts) e as imagens externas ficam bloqueadas até carregar em «Mostrar imagens».

## v66 (WhatsApp e assistente ELO)

- Contactos oficiais num só ficheiro (`partilhado/scripts/contactos.js`): número de WhatsApp e email. Sem número, o botão do ELO abre um email para `contacto@elolog.pt` com o resumo da conversa; com número, abre o WhatsApp da Elolog.
- **ELO no WhatsApp:** Edge Function `whatsapp-elo` (WhatsApp Business Cloud API da Meta) e migração `00136_whatsapp.sql`: menu, estado da encomenda só para o número associado, simulação, contactos, registo de prestadores e pedido de atendimento humano (notificação + email à administração). Ativação em `documentacao/PRODUCAO.md` › «WhatsApp».

## v65 (auditoria e projeto «Elolog»)

- A aplicação liga-se ao novo projeto Supabase **«Elolog»** (`wcggcpdiswbzrdpwgdpb`, Frankfurt). As 7 Edge Functions já estão publicadas. A base de dados instala-se com `servidor/supabase/instalar_projeto_elolog.sql` ou `instalar_em_partes/parte_1…4.sql` (SQL Editor › Run; já inclui as permissões da API que os projetos Supabase novos deixaram de dar — `permissoes_api.sql`); passos completos em `documentacao/PRODUCAO.md` › «Pôr a funcionar».
- Nome da aplicação corrigido («Elolog — Área de Cliente» em vez de «Elolog Operador»), página 404 própria, `robots.txt`, `sitemap.xml` e etiquetas de partilha no simulador e na página legal.

## v64 (página de informação legal)

- Nova página `site/legal.html` (corpo em `site/scripts/legal-pagina-1.js`, estilos no fim de `site/estilos/simulador-2.css`): identificação da empresa (DL 7/2004), termos de utilização, política de privacidade (RGPD), cookies, Livro de Reclamações Eletrónico e resolução alternativa de litígios (CNIACC). Os rodapés do site e da aplicação apontam para ela em vez dos ficheiros .md.
- **Antes de abrir ao público:** preencher NIPC, sede e registo comercial (procure «[a indicar]» em `legal-pagina-1.js`), criar o endereço `privacidade@elolog.pt` (reencaminhamento) e pedir revisão a um advogado.

## v63 (domínio elolog.pt)

- Endereço principal `https://www.elolog.pt` (ficheiro `CNAME`); email de contacto `contacto@elolog.pt`. Passos de DNS, GitHub, Brevo e Supabase em `documentacao/PRODUCAO.md` › «Domínio elolog.pt».

## v62 (simulação com o desenho do site)

- As simulações da aplicação (cliente, «Criar encomenda» do prestador e pedido pela administração) usam o desenho do simulador do site: cada bloco é um cartão com ícone, título, descrição curta e «ETAPA 0n»; o resumo lateral mostra cada valor numa linha própria e o total destacado. Só muda a apresentação: campos e cálculos ficam iguais (`app/comum/simulacao-site.js` + regras «v62» em `app/comum/paineis.css`).

## v61 (equipa Elolog, pedidos por contacto e ELO automático)

- **Equipa Elolog** (Conformidade e segurança › Funcionários e acessos): o administrador cria funcionários do portal com função *Administrador*, *Operador* ou *Apoio*, muda a função, repõe a palavra-passe e desativa (as sessões terminam). No 1.º acesso cada funcionário configura o código de autenticação. Servidor: Edge Function `gerir-equipa` e rpc `equipa_plataforma` (`app/administracao/equipa.js`).
- **Pedido por contacto** (botão no Centro de comando e em Operações e clientes): quando um cliente liga, escreve ou vem ao balcão, a administração faz a simulação em 4 etapas (cliente, rota e carga, prestador, confirmação), escolhe o prestador e pode indicar o preço combinado. O prestador recebe o pedido com a indicação «Registado pela Elolog»; se o cliente não tiver conta, a administração é avisada quando o prestador aceitar (`app/administracao/pedido-contacto.js`, rpc `admin_registar_pedido`, migração `00135`).
- **ELO automático**: atalhos e fluxos por perfil (`partilhado/scripts/assistente-fluxos.js`). Administração: pedido por contacto, simulações dos clientes, novo funcionário. Prestador: pedidos de cotação, nova tarifa, registar fatura, navios, pagamentos online. Cliente: nova simulação, pagar encomenda, documentos, pedir cotação. Basta escrever o pedido por palavras próprias (ex.: «o cliente ligou, quero criar uma encomenda»).

## v60 (tarifas, simulações e painel de simulação)

- **Tarifas**: «Guardar tarifa» volta a funcionar e a tarifa fica no servidor (tabela `tarifas`), com nova versão a cada alteração. Passa logo a aparecer nas propostas do simulador do cliente (`app/prestador/tarifas-servidor.js`). «Tipo de carga» passou a ser uma lista.
- **Simulações na administração**: a simulação fica registada no servidor logo que o cliente a efetua (rascunho). O Centro de comando mostra «Simulações dos clientes» com filtros: simuladas, enviadas, cotação e convertidas (`app/administracao/simulacoes.js`, rpc `simulacoes_administracao`).
- **Pedido de cotação**: o cliente pode escolher um prestador sem tarifa para a rota. O prestador recebe «Novo pedido de cotação» e aceita indicando o preço (migração `00134_pedido_cotacao.sql`).
- **Painel de simulação**: resumo lateral mais largo (2 colunas, sem barra de deslocamento) e propostas em linhas largas. As secções empilham até 1500 px e os volumes aparecem em cartões, sem tabela a cortar.
- **Perfil na barra lateral**: avatar com as iniciais certas, nome em até 2 linhas e função, igual em todos os painéis.
- **Simulação com o desenho do site**: cartões brancos por bloco, títulos com ícone e resumo em linhas «rótulo · valor», como em `site/simulador.html`.
- **Botões de submeter**: os formulários voltam a enviar (correção em `partilhado/scripts/componentes.js`).

## v59 (pronto para produção)

Guia passo a passo em `documentacao/PRODUCAO.md`; cópias em `documentacao/COPIAS_DE_SEGURANCA.md`.
- **Emails**: o envio corre sozinho a cada 5 minutos (pg_cron + pg_net). O segredo do agendador é gerado e guardado no cofre da base de dados, nunca em ficheiros. Falta só a conta Brevo (3 segredos).
- **Documentos**: ficheiros no armazenamento privado do Supabase (pasta por empresa ou por cliente, 20 MB, só PDF, imagens, Word e Excel); a empresa vê o que o cliente junta às encomendas dela; descarga por ligação de 2 minutos.
- **Faturas certificadas** (Financeiro › Registar fatura certificada, ou Documentos): carregar o PDF do programa certificado → a plataforma lê o QR da AT → resumo → confirmar. O servidor valida NIF, ATCUD, data, repetição e total; o cliente é avisado. Sem QR legível, cola-se o texto do QR.
- **Pagamentos ifthenpay**: Multibanco (entidade, referência, 3 dias) e MB WAY (pedido na app, 4 minutos, estado atualiza sozinho), em 3 passos com resumo. Chaves de cada empresa só no servidor (Empresa › Pagamentos online, voltam mascaradas); aviso automático com chave anti-phishing; verificação a cada 10 minutos. Sem chaves, fica o registo manual de antes.
- **Navios em tempo real** (Armazém): posição, velocidade, destino e ETA reais por AIS (aisstream.io, gratuito), a cada 30 minutos.
- **Cópias de segurança**: GitHub Actions diário, base de dados + ficheiros, cifrado AES-256, 30 dias.
- Servidor: migrações `00131`–`00133`, funções `pagamentos`, `pagamentos-aviso`, `navios-ais` (e `enviar-emails` atualizada). Testes: SQL `testes/05_producao.sql` (39/39), funções `_testes/producao.test.mts` (23/23), interface `prod` (21/21).

## v58 (área do prestador)

- **Menu lateral** igual ao do cliente e da administração (`app/prestador/menu-lateral.js`); a barra de navegação de cima deixou de aparecer. 12 áreas com submenus recolhíveis (só um aberto), a página atual e o seu grupo realçados e o título da barra igual ao item escolhido:
  Dashboard · Operações (quadro, criar encomenda, simular, atualizar estado, aprovar, programar recolhas, ocorrências, histórico, automação) · Clientes · Propostas (pedidos, criar cotação, enviadas, aceites, recusadas) · Armazém (receção, expedição, manifestos, calendário e mapa marítimo, trânsito, destino, disponível, saídas) · Equipa e transportes (agenda, painel do terreno, motoristas, viaturas, recolhas, entregas) · Financeiro (resumo, preços, faturação, recebimentos, reconciliação) · Documentos · Relatórios · Apoio ao cliente · Funcionários e acessos · Empresa e configurações.
  Cada função só vê o que as suas permissões deixam; o operador de terreno tem um menu próprio e curto. No telemóvel e no tablet o menu abre com ☰ e fecha ao escolher.
- **Dashboard** novo: cabeçalho discreto com «Simular» e «Criar encomenda»; 5 indicadores (operações do mês, encomendas pendentes, em armazém, por receber em €, alertas); 4 painéis: operações pendentes, expedições em curso, encomendas recentes e alertas calculados dos dados (atrasos, aprovações, pedidos sem resposta, pagamentos, ocorrências).
- Testes: os 46 itens do menu abertos no computador e no telemóvel sem erros; todos os botões dos 14 perfis sem erros; nenhuma página com scroll horizontal nem campos sem rótulo.

## v57 (menos caixas)

- **Validação de prestadores** e **Gestão de prestadores**: uma linha por empresa com colunas alinhadas e separadores, sem caixa à volta de cada registo; estado em etiqueta de cor (verde autorizado, âmbar pendente, vermelho suspenso/recusado). Na gestão ficam visíveis «Consultar» e «Mais ações» (as outras 6 ações; «Eliminar» a vermelho no fim).
- **Personalizar o painel**: lista em 3 colunas iguais, caixa de seleção + nome numa linha e setas pequenas lado a lado; blocos escondidos a cinzento.
- **Histórico de encomendas**: indicadores numa só faixa (sem barras de cor), separadores calmos (o escolhido em azul claro), filtros sem moldura e a lista com o cabeçalho dentro do mesmo cartão; lista vazia com ícone.
- Filtros das listas (prestadores, manifestos, clientes, histórico) deixam de ter uma caixa dentro do cartão.
- Menu lateral: quando um grupo está aberto, os itens deslizam e já não tapam «Sair».

## v56 (auditoria de design)

Relatório completo em `documentacao/AUDITORIA_DESIGN.md`. Em resumo:
- **Identidade única** — `partilhado/estilos/identidade.css` (carrega em último lugar) define as cores, a escala de letra (12 · 13 · 14 · 15 · 16 · 18 · 20 · 24 · 28 · 32), o espaço (base 4), os cantos (10 · 14 · 18) e a grelha; as variáveis das folhas antigas apontam para estes tokens. Todos os tamanhos de letra soltos foram encaixados na escala: nenhum texto abaixo de 12px e, por página, de até 20 tamanhos diferentes para no máximo 12.
- **Grelha** — o conteúdo usa a largura do ecrã (até 1640px) com a mesma margem lateral em todos os perfis; as páginas do prestador já não ficam presas a 1180px.
- **Navegação** — só a secção aberta é realçada: no menu lateral, a página atual e o seu grupo (que fica aberto; os outros fecham). Na barra do prestador, a secção certa fica sublinhada mesmo quando a página se abre por um atalho; «Mais» abre com clique (também no Safari e em ecrãs táteis).
- **Componentes** — `partilhado/scripts/componentes.js` (substitui `botoes.js`): todos os campos têm rótulo; as tabelas passam a cartões no telemóvel; linhas com muitas ações mostram só as principais e o resto em «Mais ações»; validação ao sair do campo (email, telefone, obrigatórios) e `eloValidar([...])` para marcar e focar o primeiro campo em falta. A simulação do cliente já usa esta validação.
- **Página inicial** — mostra 3 serviços e «Ver todos os serviços»; o menu Serviços abre o serviço escolhido.
- **Ações reais** — os indicadores do operador de terreno que não faziam nada abrem agora a rota; botão de alerta em contorno; logótipo do rodapé com destino.
- **Ecrãs** — telemóvel: sem sombra do menu fechado na margem, pesquisa da administração numa linha própria, título da barra encurtado, indicadores em 2 colunas, ligações do rodapé com alvo de toque maior; ficheiro de documento já não sai do ecrã no computador.

## v55 (menos ficheiros, 200 linhas)

- Ficheiros de código: de 178 para 134; nenhum passa das 200 linhas.
- Código compacto, sem espaços nem linhas em branco a mais; nomes, lógica e comportamento iguais. As 36 capturas de ecrã de antes e de depois são iguais e cliquei em todos os menus dos 14 perfis sem erros.
- Juntos: estilos base da aplicação (10 → 4), partes da página (8 → 5), dicionário inglês (6 → 1, frases separadas por « ¦ »), simulador do site (4 JS → 1), e os pares de ficheiros do mesmo assunto (estado, login, adaptador do servidor, encomendas, simulação do cliente, painel e servidor da administração, estilos do prestador, painel e tema, registo, rodapé com acabamento…).
- SQL: linhas juntas onde é seguro (nunca a seguir a um comentário nem dentro de texto); só mudaram espaços. O teste 1 voltou a correr no projeto sem falhas.

## v54

- Painéis do prestador e da administração no mesmo estilo do cliente (`app/comum/paineis.css`): cabeçalho «Posto de operação» claro com pontos e brilho verde; atalhos e indicadores do prestador em faixas únicas com linhas a separar (ícones de cor nos atalhos, ponto âmbar ou vermelho nos indicadores que pedem atenção); indicadores da administração numa só faixa com ícones de cor; esferas do fluxo operacional com degradê; cartões com cantos de 18px.

## v53

- «Personalizar painel» passou para o menu da esquerda (cliente e administração); o cabeçalho do painel deixa de ter botão. O prestador, que não tem menu à esquerda, mantém «Opções › Personalizar o painel».
- Painel do cliente com menos caixas: os quatro indicadores numa só faixa com linhas a separar; «Ações rápidas» numa lista simples; a pesquisa de encomendas dentro do «Histórico recente»; «Pagamentos pendentes» só aparece quando há pagamentos por fazer.

## v51 (painel do cliente)

- Painel do cliente redesenhado (`app/cliente/painel.js` + `app/cliente/painel.css`): «Próximo passo» claro com ilustração animada de rotas; indicadores com ícones de cor (azul, âmbar, verde, vermelho), mini-gráfico das encomendas dos últimos 6 meses e barra do que já está pago; encomendas ativas com o percurso Recolha → Armazém → Trânsito → Destino; «Ações rápidas» em mosaico 2×2; cartões com cantos maiores e sombra suave.
- Menu lateral do cliente: cartão com iniciais, página atual destacada, submenus com pontos e «Sair» em cartão.
- Só dados reais da conta: sem encomendas, aparece um estado vazio com «Fazer uma simulação».

## v50

- Idioma: em vez de PT e EN sempre à vista, um só botão (globo + idioma atual + seta) que abre a lista Português / English; fecha ao escolher, ao clicar fora ou com Esc, e funciona com as setas do teclado.

## v49

- Rodapé mais compacto: menos espaço, logótipo e letra mais pequenos, sem a marca-d'água ELOLOG.

## v48

- Capa: retiradas as três caixas de informação (4 passos, 8 etapas, 6 serviços).

## v47 (capa e rodapé)

- Capa da página inicial refeita na linha de sites de transporte como «Norvik» (`site/estilos/inicio-capa.css`): fotografia a toda a altura, menu transparente por cima dela (fica branco ao descer), título curto e enorme em maiúsculas, rótulos em letra de máquina, três caixas de informação com cantos marcados (4 passos, 8 etapas, 6 serviços) e a simulação rápida em vidro escuro.
- Retirada a faixa de serviços em movimento por baixo da capa.
- Rodapé novo e igual nas três páginas (`partilhado/estilos/rodape.css`): marca com e-mail de contacto, três colunas (Plataforma, Para empresas, Apoio), linha de base com «Dados protegidos» e «Voltar ao topo», e o nome ELOLOG em marca-d'água.

## v46 (botões)

- Um só comportamento em todo o site e aplicação: em repouso, contorno azul sobre branco (nada parece carregado); com o rato por cima, a cor enche da esquerda para a direita e a seta avança; com o teclado, igual mais anel de foco. Cantos de 12px, alturas de 44px (aplicação) e 48px (site).
- Seta em ícone nos botões de ação (substitui o «→» escrito), acrescentada por `partilhado/scripts/botoes.js`.
- Botões de sucesso iguais, em verde; secundários com contorno cinzento que ganha o azul.
- Atalhos do painel em linhas de lista com seta, em vez de quatro botões iguais.

## v45

- Avisos redesenhados (`app/comum/avisos.js`): título pelo tipo (Concluído, Atenção, Não foi possível concluir, Informação), ícones em traço, barra de tempo que pára com o rato por cima, sem avisos repetidos; no telemóvel ocupam a largura no topo.
- **Página inicial dinâmica** (`site/scripts/inicio-dinamico.js` + `site/estilos/inicio-dinamico.css`): entrada encenada do topo com a fotografia em zoom lento e profundidade ao rolar, faixa de serviços em movimento que acelera e muda de sentido com o rolar, títulos que se revelam, cartões de serviço em cascata (com o rato por cima: imagem que flutua e «Simular →»; clicar abre o simulador), rota animada no rastreio e barra de progresso da leitura. Fotografia e imagens originais mantidas; tudo desliga com «reduzir movimento».
- Botões (`partilhado/estilos/acabamento.css`, carrega em último): primário e sucesso em cor lisa, «Área de Cliente» com ícone de pessoa e contorno que só enche ao passar o rato, PT | EN com a mesma altura.

## v44

- Entrada da administração: depois do e-mail e da palavra-passe certos, passa sempre ao passo do código de 6 dígitos (registar o QR na 1.ª vez, verificar nas seguintes). Só depois do código é que se confirma se a conta é de administração.

## v43

- Administração: um registo da verificação em dois passos deixado a meio (QR mostrado sem confirmar o código) já não impede o seguinte; a aplicação apaga-o e mostra um QR novo.

## v42 (ligação ao Supabase)

- Projeto «Elolog T» criado e as 18 migrações aplicadas pela ordem (a nova `00121_avisos_seguranca.sql` corrige os avisos do Supabase: vista `empresas_disponiveis` com as permissões de quem consulta, `search_path` fixo em 7 funções internas, tabelas internas sem privilégios para a API).
- Teste 1 (instalação) sem falhas; teste 2 (comportamento) **78 de 78** verificações passaram: isolamento entre empresas, preços calculados no servidor, simulação → encomenda, aprovação e suspensão de empresas, painel da administração, verificação em dois passos, fila de e-mails.
- Publicadas as 3 funções do servidor: `registar-prestador`, `gerir-funcionarios`, `enviar-emails`.
- `?demo=1` passa a ficar ativo no separador, para a demonstração continuar a funcionar com o servidor ligado.

## v41 (reorganização)

- 46 → 26 pastas, agrupadas por área. Nomes sem espaços nem prefixos repetidos (`assets/css/elolog-botoes.css` → `partilhado/estilos/botoes.css`).
- Todos os ficheiros de código com no máximo 250 linhas: 16 ficheiros grandes divididos em partes, o corpo de 3 páginas passado para partes, as migrações SQL divididas por instruções completas (renumeradas `00011_…` a `01111_…`, pela mesma ordem).
- Comportamento igual ao da v40: 36 capturas de ecrã idênticas antes e depois (computador e telemóvel, todos os perfis), sem erros a clicar em todos os menus, idioma EN, modo sem internet e simulação rápida verificados.
- O histórico das versões anteriores está em `documentacao/HISTORICO_VERSOES.md`.

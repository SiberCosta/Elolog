# Histórico de versões

Notas de cada versão até à v40 (antes da reorganização em pastas por área). Os caminhos já foram atualizados para a estrutura nova.

**Versão de 24/10/2026 (v40).** Se esta pasta tem este ficheiro, é a versão nova.

| Pasta | O que é |
|---|---|
| `Pagina Inicial/` | Site público (`EloLog.html`) |
| `Simulador/` | Simulador de preço do site público |
| `Area de Cliente/` | Aplicação (clientes, prestadores, administração). Mapa dos scripts em `js/LEIA-ME.md`. `acesso/` tem as portas reservadas (prestador e administração); o ecrã de entrada só serve o cliente |
| `assets/` | Partilhado: `css/`, `js/`, `media/` (fotografias) e `logotipos/` |
| `supabase/` | Servidor: `migrations/` (SQL, por ordem), `functions/` (uma pasta por função), `testes/` |
| `DOCUMENTACAO/` | Arquitetura, produção, incidentes e modelos legais |
| `ferramentas/` | `minificar.mjs` (opcional) |

Para ligar ao servidor: `servidor/supabase/LEIA-ME.md`.

**Aspeto:** a paleta é a do logótipo (azul `#236186` e verde `#237E5F`). `app/comum/tema.css` carrega por último e define o menu lateral claro; para voltar ao menu escuro basta retirar essa ligação do HTML.

**Fluxos:** o cliente tem um menu de 5 áreas, um cartão «Próximo passo» no início e uma barra de 4 passos na simulação (`js/cliente/`). O prestador tem a «Fila de trabalho» no dashboard e um quadro de encomendas por etapa (`app/prestador/fila.js`). Os emoji foram trocados por ícones de traço (`partilhado/estilos/icones.css`).

**Dashboards por perfil:** cliente, prestador (por função) e administração usam o mesmo motor de blocos (`Area de Cliente/js/painel/`). Cada pessoa escolhe os blocos e a ordem em «Personalizar» (fica guardado por utilizador, no navegador), e os dados atualizam-se sozinhos. A administração mostra a tendência face ao período anterior.

## v7
- Operador de terreno: novo bloco «As minhas recolhas de hoje» (`app/prestador/painel.js`), ligado a `elolog_field_jobs` (tipo Recolha, atribuídas ao próprio, de hoje, por concluir). Cache do service worker v60.

## v8
- «Criar perfil»: escolha Particular / Empresa (NIF validado, pessoa de contacto nas empresas), novo ecrã em duas colunas (`app/comum/registo.css`, `app/comum/registo-tipo.js`). Corrigido o erro que mostrava campos de prestador no registo de cliente (atributo `hidden` ignorado pelo CSS). Cache v61.
- Painel esquerdo do registo: percurso «Simulação → Proposta → Encomenda → Documentos» (ou o do prestador). Cache v62.
- Centro de comando redesenhado como «folha de operações» (`app/comum/painel-folha.css`): indicadores em faixa, percurso da encomenda em linha, rotas e prestadores em quadro de partidas, alertas com palavra de gravidade. Cache v63.
- Centro de comando enxuto: por defeito só 4 indicadores, «Atenção agora» (máx. 3) e o percurso; os restantes blocos (negócio, funil, evolução, rotas, prestadores, atividade) ativam-se em «Personalizar». Cache v64.
- Centro de comando dinâmico: números que contam, barras que crescem, indicadores e etapas clicáveis (abrem a página respetiva), ponto «ao vivo» e «atualizado há N s». Respeita prefers-reduced-motion. Cache v65.

## v13
- Recuperar palavra-passe: janela plana, código em destaque, botão de mostrar palavra-passe (SVG) dentro do campo, confirmação com placeholder e botão (`app/comum/registo.css`, `app/comum/login.js`).
- Dashboard do prestador: folha centrada com margem superior (já não fica sob a barra), indicadores em faixa, percurso das 10 etapas clicável; por defeito menos blocos (`app/prestador/painel.js`).
- Barra do prestador: emoji/glifos substituídos por ícones (terreno, encomenda, pesquisa, idioma); menu «Mais» e Nova simulação redesenhados (`app/cliente/simulacao.css`).
- Assistente ELO sóbrio (`partilhado/estilos/assistente.css`) e «Como funciona» da página inicial como percurso com 4 paragens (`Pagina Inicial/css/processo.css`). Cache v67.

## v14
- Efeitos de interface em JS/CSS simples, inspirados em React Bits e Aceternity UI e escritos de raiz (`partilhado/scripts/efeitos.js`, `partilhado/estilos/efeitos.css`): foco de luz que segue o rato (indicadores, etapas, serviços), inclinação 3D nos cartões de serviços, botão magnético e borda em movimento no botão principal, título do topo que se revela palavra a palavra, grelha do topo reativa ao rato. Marcar elementos com `data-fx="spotlight tilt magnet split shine border"`. Respeita «reduzir movimento». Ícones dos serviços da página inicial.


## v15
- Revisão global: páginas internas do prestador na mesma folha plana (`app/comum/painel-paginas.css`): cabeçalhos com filete, listas em linhas, relatórios/configurações/subscrição sem caixas.
- `app/comum/painel-vazio.js`: estados vazios com percurso animado e faixa das 11 etapas nas páginas de processo.
- Entrada animada das páginas (respeita `prefers-reduced-motion`). Service worker v69.
- Ideias dos sites de referência em `elolog-efeitos`: dock com ampliação por proximidade na navegação (Aceternity), revelação em cascata ao rolar (Anime.js), etapas do rastreio a acender em sequência. SW v70.
- v16b: mapa de calor «Quando chegam os pedidos» no painel admin (Bklit); transições entre páginas com View Transitions (Motion); ícones de estado animados (Rive) em `app/comum/painel-transicao.js`. SW v71.
- v19 (cores do logótipo #236186 e #237E5F): Administração redesenhada a partir da referência do utilizador: menu lateral azul-escuro (`app/administracao/centro.css`, `app/administracao/centro.js`), barra com pesquisa que abre Operações, indicadores com ícone e mini-gráfico, «Fluxo operacional», «Atenção necessária» e tabela «Operações recentes». SW v72.
- v21: filtros em «Operações recentes» (pesquisa, estado, prestador, período, limpar, contagem). 
- v22: «Centro de comando» sem seletor de dias nem modo de apresentação; nova página «Auditoria de prestador» (verificações, separadores, exportação CSV/impressão, exportações registadas no registo de auditoria); «Atenção necessária» redesenhada. SW v73.
- v23: desenho unificado (cartões, ícones redondos, cores do logótipo) em prestador, cliente, terreno, assistente ELO e página inicial: `partilhado/estilos/unificado.css`, `centro.css`; menu lateral escuro também no cliente; título do banner do terreno corrigido. SW v74.
- v23b: controlos do «Como funciona» (setas, pontos, contador 01 / 04) corrigidos.
- v25: novo robô ELO (cara com visor, olhos que piscam, antena a pulsar, aceno ao passar o rato; ícone próprio em SVG). SW v75.
- v26: ELO automático (`partilhado/scripts/assistente.js`): reconhece o perfil (cliente/prestador/administração/visitante), saudação com resumo e emblema de alertas, atalhos por perfil; entende frases livres («de Lisboa para São Tomé, 200 kg», «onde está a minha encomenda», «agendar amanhã às 10:00», «abrir pagamentos/auditoria», «atrasos», «resumo»); preenche simulações, consulta a última encomenda, agenda com o prestador da encomenda, navega para as páginas e passa a conversa resumida ao WhatsApp. Continua sem executar pagamentos. SW v76.
- v27: «Editar dados» em cada funcionário (nome, e-mail, função, estado, telefone, n.º interno, licença, viatura; protege contra remover o último Admin ou alterar a própria função; regista na auditoria) em `app/prestador/equipa-editar.js`. Idioma PT/EN: seletor «PT | EN» em todas as páginas (`partilhado/scripts/idioma.js` + dicionário `partilhado/scripts/idioma-en.js`, uma linha «pt => en»); o que não estiver no dicionário permanece em português; datas e números seguem o idioma. SW v77.
- v28: navegação superior filtrada por função (cada funcionário só vê o que pode usar; operador de terreno vê apenas Dashboard, Recolhas, Entregas, Rota, Pagamentos, Ocorrências, Histórico, Perfil) em `app/comum/acesso-por-funcao.js`. Fotografia de perfil: clicar no avatar do topo para alterar, campo «Fotografia de perfil» ao editar/criar funcionário, avatar na lista de funcionários (imagem reduzida a 192 px e guardada por e-mail em `elolog_avatars`). SW v78.
- v29: notificações com âmbito restrito (`app/comum/notificacoes.js`): a administração só vê o que lhe é dirigido (nunca as do prestador); cada prestador só vê as da sua empresa e da sua função (financeiro → cobranças, armazém → receções…); o operador de terreno só vê os seus serviços; o cliente só as suas. Fluxos de alerta: encomenda muda de estado (equipa + cliente), prestador novo/aprovado/suspenso, fatura emitida, alertas urgentes com aviso imediato, separadores Todas/Não lidas/Urgentes, preferências por categoria e escalamento automático (24 h → Admin da empresa, 72 h → administração). SW v79.
- v30: painel de notificações redesenhado (cabeçalho com contagem, separadores em «pílula», grupos Hoje/Ontem/Anteriores, ícones por categoria, tempo relativo, ponto de não lida, selo Urgente, estado vazio ilustrado, animação de entrada). SW v80.
- v31: sistema de botões profissional (`partilhado/estilos/botoes.css`, carregado por último nas três áreas): variantes primário/secundário/fantasma/sucesso/perigo, tamanhos `btn-sm`/`btn-lg`, foco com anel duplo, estado pressionado, desativado, carregamento (`elologBotao.carregar(botao,true)`) e onda ao clicar (`elolog-buttons.js`); botões antigos (hero, pesquisa, registo, listas de funcionários) mapeados para o mesmo sistema. SW v81.


## v32
- Idioma PT/EN passou para a barra de navegação (sem sobrepor o sino de notificações).
- «Precisa de ajuda?» do assistente só surge após ~45 s de inatividade.
- A fotografia de perfil só se altera na página **Perfil** (Mais › Perfil; operador de terreno: separador Perfil). Clicar no avatar abre o perfil.
- Funcionários: colunas Estado / Último acesso / Ação alinhadas com o cabeçalho; ações num menu «Ações».
- Posto de operação com o mesmo desenho do painel do operador de terreno.
- Navegação: «ativo» apenas na opção clicada.
- Novo **Mapa marítimo** (Mais › Mapa marítimo): rotas por corredores marítimos, posição estimada pelas datas do calendário, posições reportadas manualmente, zoom/arrastar. Mapa e dados locais (`app/prestador/mapa-costas.js`); simplificado, sem AIS real.
- Administrador: barra de pesquisa corrigida (caixa única, sem contornos duplicados; pesquisa leva às operações).

## v33 (revisão de erros)
- Ensaio automático em navegador de todas as áreas (cliente, prestador nas 5 funções, administração), em computador e telemóvel, clicando em todos os botões de navegação.
- Corrigido: botão «Nova simulação» do painel do cliente abria uma página inexistente (`simulation`) e deixava a aplicação com erro; agora abre a simulação.
- Corrigido: clicar numa notificação de encomenda, como cliente, dava erro (página `orders` inexistente); agora abre «Minhas encomendas».
- Corrigido: botão antigo «Administração» do menu apontava para uma página inexistente.
- `showPage` (`app/comum/navegacao.js`) passou a aceitar os nomes antigos e a ignorar páginas desconhecidas em vez de bloquear o ecrã.
- Telemóvel: os blocos dos painéis do cliente e da administração saíam 60 px para fora do ecrã (deslocamento lateral); a grelha passa a uma coluna que nunca alarga (`app/comum/painel.css`).
- Logótipos repostos (`assets/logotipos/`: `elolog-logo-nav.png`, `elolog-logo-full.png`, `logo-elolog-icone.png`), recortados sem margem transparente.
- Ícones da aplicação gerados a partir do símbolo (`Area de Cliente/icons/`: 192, 512 e «maskable» 512). Sem eles, o service worker falhava a instalação e a aplicação não funcionava offline nem se instalava no telemóvel.
- Service worker v84.

## v34 (página inicial)
- Ecrã inteiro: o menu, o topo e todas as secções ocupam a largura do ecrã (antes ficavam numa coluna de ~1250 px ao centro). O topo ocupa a altura do ecrã abaixo do menu e o título acompanha o tamanho do ecrã (`Pagina Inicial/css/ecra-inteiro.css`).
- Cores da marca (`Pagina Inicial/css/marca.css`): verde `#237E5F` = ação principal (Simular Transporte, Enviar mensagem, Abrir contacto); azul `#236186` = acesso e navegação (Área de Cliente). «num só lugar.» com o percurso azul → verde do símbolo; pequenos títulos do topo em verde claro. Retirado o brilho azul/turquesa/branco do botão principal.
- Retirada do topo a animação decorativa (avião, navio, «ORIGEM»/«DESTINO»), que ficava por cima do título e da fotografia.
- Os dois ficheiros carregam por último em `EloLog.html`; para voltar ao aspeto anterior basta retirar as duas ligações.

## v35 (design profissional)
- Nova camada `partilhado/estilos/profissional.css`, carregada por último no site, no simulador e na Área de Cliente. Um só sistema: tinta `#0E2433`, **azul `#236186` para todas as ações principais**, verde `#237E5F` para confirmações e rótulos, fundo névoa `#F1F5F8`, contornos `#D7E1E8`, uma só família (Work Sans).
- Rótulos sem maiúsculas espaçadas (cerca de 130 textos passaram a minúsculas normais, no HTML e no JS; o dicionário PT→EN recebeu as novas chaves). Títulos numa só cor (sem palavras pintadas de outra cor). Botões sem setas acrescentadas.
- Cliente em **modo aplicação**: como o prestador e a administração, já não vê o menu e o rodapé do site à volta do painel (`app/comum/login.js`).
- «Como funciona»: as quatro etapas ficam visíveis ao mesmo tempo (antes só uma estava legível); o carrossel mantém-se no telemóvel.
- Topo da página inicial sem a etiqueta repetida; assistente ELO mais pequeno (48 px), já não tapa os cartões.
- Simulação do cliente: o cabeçalho da tabela de volumes só aparece quando há volumes (antes saía do formulário).
- Painel da administração no telemóvel: grelha numa coluna (corrigido um deslocamento lateral de 60 px).
- Service worker v85.

## v36 (página inicial mais leve)
- Retirado: a faixa de 4 indicadores do topo, o texto e a etiqueta «Acompanhamento em tempo real» do «Como funciona», os rótulos e as ligações de cada passo e de cada serviço, as etapas do rastreio, a secção «Porquê Elolog» (e «Sobre Nós» no menu), os 3 cartões e a nota do contacto, a secção final «Pronto para simplificar…» e o cartão de ajuda do rodapé.
- Formulário de contacto reduzido a nome, e-mail, motivo e mensagem (`js/script.js` aceita os campos em falta; o assunto passa a ser o motivo).
- Rótulos repetidos por cima dos títulos e ícones duplicados dos passos escondidos em `css/marca.css`.
- A página ficou cerca de 25 % mais curta no computador. Cópia da versão anterior do HTML: pedir, se for preciso voltar atrás.

## v37 (página inicial: simulação rápida, ilustrações e animações)
- Topo: mantém a fotografia. Os dois botões deram lugar a uma **simulação rápida** (origem, destino, peso) que abre o simulador já preenchido (`Simulador/js/script.js` lê `?origem=&destino=&peso=`).
- «Como funciona»: as etapas ficam ligadas por uma linha azul → verde, que se desenha ao entrar no ecrã, com as etapas a aparecer uma a uma; o contacto também entra ao rolar (`Pagina Inicial/js/topo.js`, `css/topo.css`). Com «reduzir movimento» fica tudo parado.

## v38
- Simulação rápida: o último campo é «Peso ou volume», com a unidade à escolha (kg ou m³). Com m³, o simulador abre com um volume de 1 m × 1 m × altura equivalente (ex.: 2,5 m³ → 100 × 100 × 250 cm), que o cliente ajusta às dimensões reais.
- Serviços: voltaram as imagens 3D originais (as ilustrações vetoriais da v37 foram retiradas).

## v39
- Nada aparece «ativo» sem o rato por cima: o cartão «Transporte Aéreo» deixou de estar escuro por defeito (os 6 serviços ficam iguais e escurecem com o rato, `Pagina Inicial/css/topo.css`); no painel da transitária, o atalho «Nova simulação» deixou de estar azul por defeito (os 4 atalhos ficam azuis com o rato ou o foco do teclado, `partilhado/estilos/profissional.css`). Service worker v86.
- Estado atual discreto em toda a Área de Cliente: a página aberta na barra do prestador fica a azul com um traço por baixo (o fundo azul só aparece com o rato por cima); o idioma escolhido (PT/EN) e a opção aberta nos menus laterais deixaram de ter fundo cheio.

## v40
- As alterações passam a aparecer logo: os endereços de CSS e JS levam `?v=40` (mudar o número a cada versão) e o service worker vai primeiro à rede para CSS e JS; a cache só serve sem internet. Service worker v87.
- Site público: «Área de Cliente», «Simular», «Rastrear» e «Enviar mensagem» ficam só com contorno azul e enchem-se de azul com o rato por cima (ou com o foco do teclado). Retirada a onda azul ao clicar.
